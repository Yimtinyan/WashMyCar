/// Activation, installation and a successful peer reply are separate facts.
public struct LinkState: Equatable, Sendable {
    public var supported = true
    public var activated = false
    public var phone = true
    public var paired = false
    public var peerInstalled = false
    public var reachable = false
    public var verified = false
    public init() {}
    public var transferIssue: String? {
        if !supported { return "此设备不支持手表连接，请使用 iPhone 执行。" }
        if !activated { return "系统连接尚未激活，请稍后重试。" }
        if phone && !paired { return "iPhone 尚未识别到已配对的 Apple Watch。" }
        if !peerInstalled {
            return phone ? "系统尚未确认手表 App 已安装，请在 iPhone 的 Watch App 完成安装后重试。"
                : "手表尚未识别到对应的 iPhone App，请先在配对的 iPhone 上打开 WashMyCar。"
        }
        return nil
    }
    public var status: String {
        if let issue = transferIssue { return issue }
        if verified { return reachable ? "双端通信已验证" : "已验证通信，等待后台同步机会" }
        return reachable ? "两端 App 已就绪，待验证通信" : "对端 App 已安装，等待同步机会"
    }
}
