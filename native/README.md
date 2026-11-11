# WashMyCar 原生 v0.1

这是可在 Xcode 打开的 SwiftUI 原生工程，沿用仓库 v0.5 Demo 的业务和素材。保留三个主导航：洗车、药剂、记录。浏览器 Demo 继续独立保留。

## 在 Xcode 中运行

1. 打开 [`WashMyCar.xcodeproj`](WashMyCar.xcodeproj)。工程已包含共享 schemes，不需要安装第三方依赖。
2. 选择 `WashMyCar` scheme 和 iPhone 模拟器或已连接的 iPhone，点击 Run。最低 iOS 17。
3. 真机运行前，在三个 targets 的 **Signing & Capabilities** 中选择同一个 Apple Development Team。默认 bundle IDs 为 `com.yimtinyan.WashMyCar`、`com.yimtinyan.WashMyCar.watchkitapp` 和 `com.yimtinyan.WashMyCar.widgets`。如果调整标识，同时更新 Watch 的 companion bundle ID。
4. 在 iPhone App 和小组件 target 中启用同一个 App Group：`group.com.yimtinyan.WashMyCar`。若更换 group ID，同时修改 `iOS/AppStore.swift`、`Widgets/WashWidgets.swift` 和工程生成脚本中的对应值。它只存放小组件最小摘要，主资料仍保存在 App 的 Application Support 中。
5. 选择 `WashMyCarWatch` scheme，运行到与 iPhone 配对的 Apple Watch，最低 watchOS 10。iPhone target 已嵌入 Watch App 和 Widget 扩展。

本机 Xcode 27.2 具备 iOS/watchOS SDK。2026-11-11 已使用本机开发证书构建并安装 iPhone 真机测试版；用户完成开发者信任后确认已显示原生首页，Mac 端随后也查询到手机上的 App 运行进程。模拟器可另外在 Xcode 的 Settings → Components 中下载运行时后创建。

### 个人开发团队的真机测试版

本次个人团队生成的描述文件没有 App Group 权限，直接构建默认工程会发生 entitlement 不匹配。可以使用以下专门的测试脚本，不修改正式工程的权限配置：

```sh
WASHMYCAR_TEAM_ID=YOURTEAM WASHMYCAR_DEVICE_ID=YOURDEVICE \
  bash native/Scripts/run_device.sh
```

脚本构建、安装并尝试启动 App；使用 `LOCAL_DEVICE_PREVIEW` 编译条件并移除本次构建的 App Group entitlement。手机的方案、库存、履历与记录照常保存于 App 本机目录，安装更新不会主动卸载或清空资料。此测试版不写共享摘要，小组件明确提示“共享未启用”；正式构建仍使用原来的 App Group 配置。手表 App 会一起签名嵌入，但安装至手表及双端通信需另行验收。

若首次启动提示未受信任的开发者，在 iPhone 的「设置 → 通用 → VPN 与设备管理 → 开发者 App」中信任自己的开发者，然后再打开 App。本次生成的描述文件有效期至 2026-11-18；到期后需要重新构建签名安装。团队、设备标识通过环境变量传入，不提交证书、描述文件或签名产物。

Mac Catalyst 可选择 **My Mac (Mac Catalyst)** 进行界面检查。Catalyst 不支持本项目的真实手表连接，不替代 iPhone/Watch 配对验收。

### 手表安装失败或一直等待

手机安装成功并不表示手表已注册到 Xcode。先运行 `xcrun devicectl list devices`，以及 `xcodebuild -project native/WashMyCar.xcodeproj -scheme WashMyCarWatch -showdestinations`。如果列表中没有物理 Apple Watch，先完成设备发现与配对，不能用 iPhone 的设备 ID 代替手表来签名安装。

本机 Xcode 27.2 可打开 Device Hub，点击 `+ → Pair Nearby Device…`。配对窗口提示在待配对设备的「设置 → 隐私与安全性 → 开发者模式」中开启开发者模式。按手表提示重启并确认后解锁，保持靠近 Mac 和其配对 iPhone，并按实际提示完成配对。若没有该选项，需进一步核对手表型号、系统版本及设备连接状态，不应先抹掉或重新配对手表来碰运气。参考 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)和[真机运行说明](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)。

手表出现在 Xcode 目标列表后，可选择 `WashMyCarWatch` scheme 和该手表点 Run，或者直接运行：

```sh
WASHMYCAR_TEAM_ID=YOURTEAM WASHMYCAR_WATCH_ID=YOURWATCH \
  bash native/Scripts/run_watch.sh
```

脚本使用手表自身的目标 ID 构建，允许 Xcode 注册该设备并生成描述文件，再直接安装和尝试启动手表 App。不卸载 App 或清空已有手表流程。首次连接、信任与开发者模式确认仍需在设备上完成。未识别到物理手表时，这条安装路径尚不能执行。

2026-11-11 已在 Apple Watch Series 10 / watchOS 27.0.1 实际执行此脚本：重新生成的描述文件包含该手表，签名构建、安装和启动命令均成功。此前随手机构建生成的 Watch 描述文件仅登记了 iPhone/iPad，不能据其本地签名校验通过就认为手表有安装授权。双端业务流程仍需继续验收，详见验证记录。

## 已实现

| 模块 | 原生行为 |
| --- | --- |
| 首页 | 原有银色乐道 L60 / 白内饰素材、当前方案与准备入口；其他车辆使用通用占位 |
| 编排 | 三种内置方案、步骤编辑/排序/删除、药剂与原液/清水用量、工具、现场备注、车辆与地点；个人方案另存与修订；内置原稿不可覆盖 |
| 备液 | 显示同车未处理备注；按同瓶汇总取用，只扣一次库存；未知/不足库存阻止确认；备液不会开始计时 |
| 药剂 | 搜索与用途筛选、添加/编辑、容量与精确/估算/未知余量、购买信息、用法与 pH 来源、额外取用及履历 |
| 现场 | iPhone 单端开始/暂停/恢复/完成；快照冻结后不可修改；有效用时排除暂停 |
| Watch | WatchConnectivity 发送 SHA-256 内容摘要；手表原子保存后回传确认；手表本地开始、暂停、逐步完成及离线保存；重复包不会重置进度；旧进度不会覆盖新进度 |
| 记录 | 自动保存一次完成记录；当时药剂快照只读；洗后备注可编辑、标记已处理或在本轮暂缓提醒；自动完成彩蛋，遵循减少动态效果 |
| 备份 | 兼容 `WashMyCarBackup` schema 1 / mL / Demo v2—v5；保留额外字段、购买资料、履历和快照；12 MB 上限、结构与关联校验、恢复数量预览、确认替换和本机回退副本 |
| 小组件 | 两个 WidgetKit 组件：距上次洗车时间、药剂瓶数；App Group 最小摘要；点击深链进入记录/药剂 |
| 快捷入口 | App Intents / App Shortcut 打开 App；用户可在系统快捷指令或操作按钮中配置；不会静默扣库存或完成步骤 |
| 外观 | 系统导航/Tab 栏、浅深色、Dynamic Type 字体、系统 VoiceOver 标签和原生触感 |

默认首次运行使用仓库的示例库存，之后不会重新灌入种子资料。浏览器的 localStorage 无法直接被原生 App 读取：先在 Demo 设置中导出完整 JSON，再在原生设置中选择“从备份恢复”。原生导出的备份也已通过 Demo 的 `readBackup` 校验。

## 执行权与持久化

准备方案冻结步骤和药剂副本，生成一笔 `prepare:<session-id>` 履历。开始、接收、重试、暂停、确认步骤和完成记录都不再次扣减库存。

未交接时，可选择用 iPhone 开始；开始后本次由 iPhone 负责。选择交给 Watch 时，先检查连接、配对安装状态及包大小，再持久化 Watch 执行权并发送。手表收到后先落盘，再回传确认；仅传输排队不算就绪。手机只接受同一流程、同一快照、更高 revision 的有效进度。

**当前不提供已交接流程的手机强制接管。** 断连后可在手表继续，连接恢复后自动/手动同步；手机等待手表回传。这样可以避免两边离线同时完成并产生冲突。若手表丢失或卸载，仍需后续实现双端确认的撤回/接管协议。含未完成 Watch 流程的备份可以导出，但拒绝恢复为第二个执行端。

主资料每次先通过校验并原子写盘，成功后才更新可见状态。读取损坏文件时显示错误并保留原文件，不用示例资料覆盖。恢复前保存 `BeforeRestore.json`；写入失败不会切换状态。它是本机回退文件，不能替代导出到其他位置的备份。

旧版没有计时锚点的进行中流程，从恢复时开始计时并显示说明，不推断之前的时长。迁移不重复扣库。

## 代码与验证

```
native/
  Shared/         JSON、备份迁移校验、库存与流程状态机、原子存储
  Platform/       WatchConnectivity 传输
  iOS/            SwiftUI 页面、应用状态、App Intents 与素材
  Watch/          手表界面与离线存储
  Widgets/        WidgetKit 扩展
  Resources/      从现有 Demo 派生的初始资料
  Tests/          业务测试和 Demo 导出兼容样本
  Config/         Info.plist 与 App Group entitlements
  Scripts/        不依赖 XcodeGen 的可重复工程生成脚本
```

正常开发直接使用已提交的 Xcode 工程。新增/删除源文件后可重新生成工程；脚本会覆盖工程配置与 Info.plist，在 Xcode 中手动修改的签名团队需要重新选择。也可使用 `WASHMYCAR_TEAM_ID=YOURTEAM python3 native/Scripts/generate_project.py` 指定团队后生成。

从仓库根目录运行：

```sh
swift test --package-path native
xcodebuild -project native/WashMyCar.xcodeproj -scheme WashMyCar \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath native/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project native/WashMyCar.xcodeproj -scheme WashMyCarWatch \
  -configuration Debug -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/washmycar-watch-build CODE_SIGNING_ALLOWED=NO build
```

这两条无签名构建命令用于编译检查，产物不能直接当作已签名真机安装包。共享业务层也可单独在 Xcode 打开 `Package.swift` 后运行测试。

本轮验证详见 [`verification.md`](verification.md)。尚未实现 HealthKit 读取、拍照附件、Camera Control、真实可旋转 3D 模型、云同步、完整英文界面和复杂车辆材质适用性判断；没有将这些入口伪装为已接入。
