# v0.4 · 需求落地与 Apple 原生接入

核验：2026-11-10。当前可运行产品仍是React浏览器Demo；本文件明确区分已实现交互与原生交付，不能将空白健康卡片或玻璃CSS称为已经接入HealthKit或系统组件。

| 用户要求 | 本轮交付 | 尚需原生开发 |
| --- | --- | --- |
| 日常、雨后、周末预设 | 三种独立快照，可选择后编辑、更新或另存自定义；进行中的已备流程禁止覆盖 | 原生持久化与多设备同步 |
| 彩蛋不设开关 | 设置移除入口，迁移旧关闭值仍自动启用；减少动态效果保留 | 原生动效与触感 |
| 银色2024乐道L60、左前45度、星芒轮毂 | 参考2024实车图生成协调渲染，替换主页/完成/记录车辆；不是可旋转CAD模型，轮毂为示意 | 精确网格与配置素材验收 |
| R角与布局统一 | 控件16、内容面板24、设备外壳独立；导航玻璃、内容不透明 | 系统容器与系统材质适配 |
| 药剂使用方法 | 每瓶手工输入并保存；与购入标签和使用履历并存 | 云端同步 |
| 洗后注意事项 | 记录详情自动保存，下次编排显示最近提醒 | 可选跨设备同步 |
| 健康、热量与心率 | 明确“未连接”和无数据展示，未生成虚假测量值 | HealthKit、Watch workout session、授权、真机验证 |
| Action/Camera Control/玻璃/马达 | Apple体验说明与视觉近似 | App Intents、相机捕捉扩展、SwiftUI系统玻璃、原生触感 |
| 预洗/正洗 pH | 输入/展示0—14或未知；记录原液/工作液及来源/稀释条件，不自动猜值 | 官方库核验和产品地区/版本关联 |
| 桌面小组件 | 距上次洗车多久、药剂库存两种实时数据布局预览，点击进入记录/库存 | WidgetKit扩展安装与时间线刷新 |

## 健康数据

原生Watch在用户明确开始洗车时启动采集，以同一个sessionId关联记录。分别请求心率、活动能量读取权限；只有选择保存Workout时才请求相应写权限。使用HKWorkoutSession与HKLiveWorkoutBuilder，按设备实际样本显示活动能量kcal、带时间轴的心率、平均/最低/最高心率、采样覆盖率。明确“活动能量”与“总能量”区别，不从洗车分钟数推断卡路里，也不重复相加Workout汇总和底层能量样本。

拒绝、缺失、离腕、采样中断、同步延迟均显示无数据或缺口，不补零、不编造连续曲线；HealthKit读取没有数据不能单独证明用户拒绝。暂停的洗车操作时长与Workout时间范围分别记录。中断/来电/崩溃恢复必须幂等，结束一次只保存一份。健康数据默认不出现在桌面组件中。

依据：[Apple HealthKit workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)、[构建Watch运动应用](https://developer.apple.com/documentation/healthkit/building-a-workout-app-for-apple-watch)、[WWDC26 HealthKit zones](https://developer.apple.com/videos/play/wwdc2026/207/)。iOS/watchOS27有相关能力，但不表示洗车已被系统定义为独立运动类别。

## 实体按钮与拍摄

iPhone Action button由用户在系统中分配快捷指令，以App Intents打开当前准备/现场界面；不能通过一次误触静默扣库存或结束洗车。当前Series10没有Apple Watch Ultra的Action button，不混用两种硬件。

Camera Control用于“洗前/洗后照片”这个相机功能，需要相机权限、可见取景与AVCaptureEventInteraction；第三方相机作为默认入口还需要用户配置和适用的原生集成。不能承诺把它全局改为洗车下一步。照片与洗车session关联，锁屏拍摄和主应用数据访问边界单独验收。

依据：[Apple相机控制集成](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control)、[Camera Control选择第三方相机](https://support.apple.com/en-gb/guide/iphone/iph3940f00d2/27/ios/27)、[Apple健康应用与App Intents入口](https://developer.apple.com/health-fitness/)。

## 系统材质、触感与桌面

Liquid Glass优先使用系统导航/Tab栏与SwiftUI支持的材质；药剂用法、记录和健康数字保持清晰内容底。减少透明度时使用实体底，减少动态效果时停止装饰性折射和闪动。网页backdrop-filter是视觉近似，不能替代iOS27真机验收。

iPhone使用系统触感生成器（必要时Core Haptics），Watch使用系统haptic：单步确认轻量、完成成功提示、库存不足错误提示；一次点击只触发一次，遵循用户系统偏好，不把网页vibrate当作iPhone马达已适配。

WidgetKit使用App Group中的最小快照：最近完成时间、方案名、瓶数/库存摘要。距离上次洗车用时间锚点和系统时间线，跨日和时区变化重新计算；刷新受系统预算约束，不能承诺每秒刷新。组件点击使用深链进入对应记录/库存；变更后请求刷新，不在组件里直接扣库存。

依据：[SwiftUI Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[Core Haptics](https://developer.apple.com/documentation/corehaptics)、[WidgetKit交互](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)。原生交付需要macOS/Xcode签名工程、真机与权限测试，本Windows浏览器Demo未完成这些步骤。
