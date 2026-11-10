import Foundation
import Combine
import WatchConnectivity

@MainActor
final class Connectivity: NSObject, ObservableObject, WCSessionDelegate {
    @Published var status = "正在连接"
    var receive: ((String, JSON, String) -> Void)?
    var activated: (() -> Void)?
    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
        if session == nil { status = "此设备不支持手表连接" }
    }
    func checkAvailability(payload: JSON) throws {
        guard let session else { throw WashError("此设备不支持手表连接，请使用 iPhone 执行。") }
        guard session.activationState == .activated else { throw WashError("连接尚未就绪，请稍后重试。") }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { throw WashError("请先配对手表并安装 WashMyCar 手表 App。") }
        #endif
        guard try payload.encoded().count < 50_000 else { throw WashError("方案内容过大，请缩短备注或使用手机执行。") }
    }
    func send(kind: String, payload: JSON) throws {
        try checkAvailability(payload: payload)
        guard let session else { return }
        let message: [String: Any] = ["kind": kind, "payload": try payload.encoded(), "checksum": try WashEngine.checksum(payload)]
        try session.updateApplicationContext(message)
        session.transferUserInfo(message)
        status = "已排队，等待另一设备保存确认"
    }
    private nonisolated func handle(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String, let data = message["payload"] as? Data,
              data.count <= Backup.maxBytes, let payload = try? JSON.read(data), let checksum = message["checksum"] as? String else { return }
        Task { @MainActor [weak self] in self?.receive?(kind, payload, checksum) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let message = error?.localizedDescription ?? (activationState == .activated ? "连接已就绪" : "连接未激活")
        Task { @MainActor [weak self] in
            self?.status = message
            if activationState == .activated { self?.activated?() }
        }
        handle(context)
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { handle(userInfo) }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
