# 原生 v0.1 验证记录

## 2026-11-11 · 手表安装排查

- 用户反馈：iPhone 的 Watch App 可以看到 WashMyCar，但安装失败或持续等待。
- 三种设备枚举（CoreDevice、Xcode 设备列表和 Instruments）均只识别到连接的 iPhone，没有物理 Apple Watch；Watch scheme 也未列出可运行的物理手表目标。
- 检查确认手机包内已嵌入 Watch App，companion bundle ID 正确，本地代码签名完整性校验通过。但其描述文件的设备列表只包含已知 iPhone 和 iPad，不包含 Apple Watch；此前的包完整性校验不能当作手表设备授权已满足。
- 已打开 Xcode 27.2 Device Hub 的 `Pair Nearby Device…` 入口。用户确认手表已开启开发者模式并解锁放在旁边，系统版本为 watchOS 27.0.1，且与 Mac 在同一 Wi-Fi。Mac Wi-Fi 与蓝牙均已开启，未更改网络、隐私或安全开关。
- 随后在 Xcode 打开原生工程并切换到 `WashMyCarWatch` scheme，在运行目标列表中发现物理 Apple Watch Series 10（watchOS 27.0.1），选择后 CoreDevice 也列出了该手表。
- 增加 `Scripts/run_watch.sh`，使用手表自身的目标标识注册、重新签名、直接安装和启动。Bash 语法检查通过，实际真机签名构建成功；新描述文件已包含该 Apple Watch，本地代码签名完整性校验通过。
- 设备安装命令成功，启动命令返回成功；再次查询手表已安装列表确认 WashMyCar 0.1.0（1），并确认手表上的主 App 进程仍在运行。至此手表安装和真机启动已确认；尚未验证完整双端方案传输、断连执行与完成回传，不将安装成功等同于双端业务验收。

## 2026-11-11 · iPhone 真机安装

- USB 连接的 iPhone 16 Pro Max（iOS 27.2）已配对，开发者模式开启，开发设备服务可用。
- 默认 App Group 构建因本机个人团队描述文件不包含所请求的共享组而失败。
- 增加独立真机测试脚本，使用 `LOCAL_DEVICE_PREVIEW` 条件并仅在此构建移除共享组 entitlement。手机主资料存储与业务规则不变，小组件明确展示共享未启用。
- 此真机测试构建签名成功，`codesign --verify --deep --strict` 通过。设备安装命令成功；再次查询设备确认 WashMyCar 0.1.0（1）已安装。
- 首次启动被 iOS 安全检查拒绝，错误涉及未明确受信任的开发者描述文件等签名条件；已请求用户在手机上信任自己的开发者后继续。此时不能声称已在真机成功启动或已完成 Watch 双端验收。
- 随后用户确认已完成信任并在手机看到“留一点时间，给爱车”首页；再次使用设备工具查询，确认主 App 与 Widget 扩展进程均正在该 iPhone 上运行。因此真机安装与首次启动已确认成功。尚未在真机完成整次洗车、备份恢复、Widget 共享数据或 Watch 通信验收；此测试版的小组件共享仍未启用。
- 本次描述文件有效期至 2026-11-18。设备标识、账号、证书、描述文件、签名产物和运行数据不提交仓库。

## 2026-11-10 · 编译与 Catalyst

日期：2026-11-10。环境：macOS / Xcode 27.2（27B52），Apple Swift 6.4.2。Xcode 工程使用 Swift 5 语言模式，共享业务 Swift Package 使用 Swift 6。

## 编译与测试

- `WashMyCar` iOS generic device Debug，无签名编译通过，同时构建并嵌入 Watch App 与 Widget 扩展。
- `WashMyCarWatch` watchOS generic device Debug，无签名独立编译通过。
- `WashMyCar` Mac Catalyst Debug，无签名编译并实际启动通过。
- 18 项共享业务测试全部通过，覆盖备液幂等、同瓶用量汇总、未知与不足库存、暂停与有效时间、完成幂等、独立历史快照、兼容备份往返、异常备份拒绝、旧版迁移、Watch 执行权与乱序/重复进度、同车备注、原子存储与恢复回退；未来版本本机资料拒绝降级并保留原文件。
- 另用 Demo 代码生成真实 v5 完成记录备份作为 fixture，核对购买资料、扩展字段、使用履历、车辆、方案和历史快照保留；旧版缺少备注状态时补充 `open`。
- 原 Demo 的 22 项 JavaScript 业务测试通过，现有 Demo 源码未修改。

## 实际界面操作（Mac Catalyst）

1. 从首页进入编排，预洗用量由 20 mL 改为 25 mL，保存后首页显示 25 mL。
2. 准备清单展示 GSF 25 mL、Reset 30 mL；未勾选标签核对时确认按钮禁用。确认后进入“尚未计时”的现场页。
3. 选择 iPhone 执行，二次确认后开始计时。暂停后“完成此步”禁用，恢复后继续，依次完成四个步骤。
4. 自动显示完成彩蛋并生成一条记录。实际记录中总时长 00:48、有效用时 00:43、暂停 00:05。
5. 记录的 GSF 历史快照仍显示当时 760 mL；当前库存为 735 mL，Reset 为 310 mL。确认步骤和完成记录没有再次扣减。
6. 填写并保存洗后备注“轮毂边缘还有水渍”；历史药剂详情标记只读，无修改入口。
7. 原生文件导出完成，实际 JSON 含 7 瓶药剂、1 条洗车记录、1 条取用履历，不包含健康明细。Demo 的 `readBackup` 接受此原生备份。
8. 用原生文件选择器选回导出文件，展示 1 辆车 / 7 瓶药剂 / 1 条记录 / 1 条履历 / 3 个方案；确认替换后显示“资料已恢复”。
9. 重启保留资料。检查深色模式，修正链接和主按钮的深色配色及标签对比度。

上述实际操作后，Mac 锁屏阻止了最终一次界面复查。最终源码的 iOS、watchOS、Catalyst 编译及 18 项共享测试均已通过；最后的按钮标签配色调整和“无手表连接时保留手机执行权”仍需解锁后补做界面复查，不能据此声称已通过真机验证。

验收操作仅使用新建 Catalyst App 的示例资料。运行资料、回退文件、导出测试文件、DerivedData 与依赖缓存不提交仓库。

## 尚未验收

本机没有 iOS / watchOS Simulator runtime，也没有为本轮配置配对真机与签名团队。以下必须继续在配对设备上验证：

- WatchConnectivity 的真实配对、持久保存确认、离线完成后回传、重装/换表与中断恢复。
- Widget 的 App Group 访问、系统时间线刷新、桌面安装和深链。
- iPhone / Watch 触感、湿手与水锁、VoiceOver、系统动态字体各档和横竖屏。
- App Shortcut / Action button 的实际用户配置。

HealthKit、Camera Control 和拍摄附件尚未实现。当前没有读写健康数据、获取相机权限，也没有已签名发布或 App Store 上传。

Xcode 的 Watch/Widget 目标可能提示没有 AppIntents 依赖而跳过元数据提取；它们没有声明 AppIntent。Catalyst 构建环境有 Metal toolchain 搜索路径警告，但链接和启动成功。这些不是跨设备或真机验收结果。
