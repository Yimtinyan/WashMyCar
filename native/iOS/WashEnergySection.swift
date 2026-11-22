import HealthKit
import SwiftUI

struct WashEnergySection: View {
    let record: JSON

    var body: some View {
        EnergyView(record: record)
            .id(record.id)
    }
}

struct WashEnergySettingsSection: View {
    var body: some View {
        EnergyView(record: nil)
    }
}

private struct EnergyReading {
    let kcal: Double
    let coverage: TimeInterval?
    let sources: [String]
}

private enum EnergyState {
    case checking, unavailable, needsRequest, configured, noSamples
    case reading(EnergyReading)
    case failed(String)
}

private struct EnergyView: View {
    let record: JSON?
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = EnergyState.checking
    @State private var revision = 0
    @State private var requesting = false

    // Only the real start and finish timestamps of a completed wash define the query.
    private var interval: DateInterval? {
        guard let record, !record["timingUnavailable"].flag,
              let start = record["startedAt"].number, let end = record["finishedAt"].number,
              start.isFinite, end.isFinite, start > 0, end > start else { return nil }
        return DateInterval(start: Date(timeIntervalSince1970: start / 1000),
                            end: Date(timeIntervalSince1970: end / 1000))
    }

    var body: some View {
        Section(record == nil ? "Apple 健康" : "同期活动能量") {
            if record != nil && interval == nil {
                Text("这条记录缺少有效的开始或结束时间，无法查询同期活动能量。")
            } else {
                if let interval {
                    LabeledContent("洗车时段", value: (interval.start..<interval.end).formatted(.interval.day().month().year().hour().minute().second()))
                }
                switch state {
                case .checking:
                    ProgressView("正在检查 Apple 健康…")
                case .unavailable:
                    Text("当前设备无法访问 Apple 健康。")
                case .needsRequest:
                    Text("允许读取「活动能量」后，洗车记录可显示这段时间的千卡数。")
                    Button("连接 Apple 健康") { Task { await requestAccess() } }
                        .disabled(requesting)
                case .configured:
                    Text("系统已询问读取权限。允许读取后，已完成的洗车记录会显示该时段可用的活动能量。")
                    Text("可在「健康」App 的个人资料中查看或更改授权。").font(.footnote).foregroundStyle(.secondary)
                case .noSamples:
                    Text("暂无完整落在本次洗车时段内的可读样本。可在「健康」中确认读取权限，或在 Apple Watch 同步后刷新。")
                    Button("重新读取") { revision += 1 }
                case .reading(let measurement):
                    LabeledContent("活动能量") {
                        Text("\(measurement.kcal.formatted(.number.precision(.fractionLength(0...2)))) kcal")
                            .monospacedDigit()
                    }
                    if let seconds = measurement.coverage {
                        LabeledContent("样本覆盖时长", value: Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                    }
                    if !measurement.sources.isEmpty {
                        LabeledContent("样本来源", value: measurement.sources.joined(separator: "、"))
                    }
                    Text("来自 Apple 健康。汇总完整落在洗车时段内的样本，包含暂停期间及同时进行的其他活动。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("刷新活动能量") { revision += 1 }
                case .failed(let message):
                    Text(message)
                    Button("重试") { revision += 1 }
                }
            }
        }
        .task(id: revision) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !requesting { revision += 1 }
        }
    }

    private static let store = HKHealthStore()
    private static let energy = HKQuantityType(.activeEnergyBurned)

    @MainActor private func requestAccess() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do {
            try await Self.store.requestAuthorization(toShare: [], read: [Self.energy])
            revision += 1
        } catch {
            state = .failed("未能完成健康权限请求。\n\(error.localizedDescription)")
        }
    }

    @MainActor private func reload() async {
        if record != nil && interval == nil { return }
        guard HKHealthStore.isHealthDataAvailable() else { state = .unavailable; return }
        state = .checking
        do {
            let status = try await Self.store.statusForAuthorizationRequest(toShare: [], read: [Self.energy])
            try Task.checkCancellation()
            // An unnecessary request means the system has already asked, including when access was declined.
            guard status == .unnecessary else { state = .needsRequest; return }
            guard let interval else { state = .configured; return }
            let dates = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end,
                                                    options: [.strictStartDate, .strictEndDate])
            let predicate = HKSamplePredicate.quantitySample(type: Self.energy, predicate: dates)
            let query = HKStatisticsQueryDescriptor(predicate: predicate, options: [.cumulativeSum, .duration])
            let statistics = try await query.result(for: Self.store)
            try Task.checkCancellation()
            guard let total = statistics?.sumQuantity() else { state = .noSamples; return }
            let sources = try? await HKSourceQueryDescriptor(predicate: predicate).result(for: Self.store)
            try Task.checkCancellation()
            state = .reading(EnergyReading(kcal: total.doubleValue(for: .kilocalorie()),
                                           coverage: statistics?.duration()?.doubleValue(for: .second()),
                                           sources: Set(sources?.map(\.name) ?? []).sorted()))
        } catch {
            guard !Task.isCancelled else { return }
            let nsError = error as NSError
            if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorNoData.rawValue {
                state = .noSamples
            } else {
                state = .failed("未能读取 Apple 健康。\n\(error.localizedDescription)")
            }
        }
    }
}
