import Foundation
import Combine
import WatchConnectivity

@MainActor
final class Connectivity: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status = "正在连接"
    var receive: ((String, JSON, String) -> Void)?
    var activated: (() -> Void)?
    private let session: WCSession?
    private var link = LinkState()
    private var verifiedAt: Double?
    private var probeID: String?
    private var lastEvent = "initializing"
    private var lastError: String?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
        refresh()
    }
    func refresh() {
        link.supported = session != nil
        link.activated = session?.activationState == .activated
        link.reachable = session?.isReachable ?? false
        #if os(iOS)
        link.phone = true
        link.paired = session?.isPaired ?? false
        link.peerInstalled = session?.isWatchAppInstalled ?? false
        #else
        link.phone = false
        link.peerInstalled = session?.isCompanionAppInstalled ?? false
        #endif
        if link.transferIssue != nil { verifiedAt = nil }
        link.verified = verifiedAt != nil
        status = link.status
        saveDiagnostics()
    }
    /// Read-only round trip: never prepares supplies, assigns execution or starts a timer.
    func checkConnection() {
        refresh()
        guard link.transferIssue == nil, link.reachable, let session else { return }
        let id = UUID().uuidString
        probeID = id
        session.sendMessage(["kind": "probe", "id": id], replyHandler: { [weak self] reply in
            let matches = reply["kind"] as? String == "probeReply" && reply["id"] as? String == id
            Task { @MainActor [weak self] in
                guard let self, self.probeID == id, matches else { return }
                self.verifiedAt = milliseconds(); self.lastError = nil
                self.lastEvent = "probeReply"; self.refresh()
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                self?.lastError = error.localizedDescription
                self?.lastEvent = "probeFailed"; self?.refresh()
            }
        })
    }
    func checkAvailability(payload: JSON) throws {
        refresh()
        if let issue = link.transferIssue { throw WashError(issue) }
        guard try payload.encoded().count < 50_000 else { throw WashError("方案内容过大，请缩短备注或使用手机执行。") }
    }
    func send(kind: String, payload: JSON) throws {
        try checkAvailability(payload: payload)
        guard let session else { return }
        let message: [String: Any] = ["kind": kind, "payload": try payload.encoded(), "checksum": try WashEngine.checksum(payload)]
        try session.updateApplicationContext(message)
        session.transferUserInfo(message)
        // Keep durable delivery and also send immediately when the peer is reachable.
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.lastError = error.localizedDescription; self?.lastEvent = "immediateSendFailedQueued"; self?.refresh()
                }
            })
        }
        lastEvent = "queued:\(kind)"; lastError = nil
        status = "已排队，等待另一设备保存确认"
        saveDiagnostics()
    }
    private func saveDiagnostics() {
        // Local runtime status only: no plans, inventory, notes, device IDs or health data.
        let snapshot: JSON = .object([
            "at": .number(milliseconds()), "supported": .bool(link.supported), "activated": .bool(link.activated),
            "phone": .bool(link.phone), "paired": .bool(link.paired), "peerInstalled": .bool(link.peerInstalled),
            "reachable": .bool(link.reachable), "verifiedAt": verifiedAt.map(JSON.number) ?? .null,
            "event": .string(lastEvent), "error": lastError.map(JSON.string) ?? .null, "status": .string(status)
        ])
        do {
            let folder = URL.applicationSupportDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try snapshot.encoded().write(to: folder.appendingPathComponent("ConnectivityStatus.json"), options: .atomic)
        } catch { /* Diagnostics must not interfere with stock or session persistence. */ }
    }
    private nonisolated func handle(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String, let data = message["payload"] as? Data,
              data.count <= Backup.maxBytes, let payload = try? JSON.read(data), let checksum = message["checksum"] as? String else { return }
        Task { @MainActor [weak self] in
            self?.lastEvent = "received:\(kind)"; self?.refresh()
            self?.receive?(kind, payload, checksum)
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.lastError = message; self?.lastEvent = "activated"; self?.checkConnection()
            if activationState == .activated { self?.activated?() }
        }
        handle(context)
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.lastEvent = "reachabilityChanged"; self?.checkConnection() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["kind"] as? String == "probe", let id = message["id"] as? String {
            replyHandler(["kind": "probeReply", "id": id])
            Task { @MainActor [weak self] in self?.lastEvent = "probeReceived"; self?.refresh() }
        } else { handle(message); replyHandler(["kind": "transportReceived"]) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { handle(userInfo) }
    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.lastEvent = "watchStateChanged"; self?.checkConnection() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.verifiedAt = nil; self?.refresh() }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #else
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.lastEvent = "companionChanged"; self?.checkConnection() }
    }
    #endif
}
