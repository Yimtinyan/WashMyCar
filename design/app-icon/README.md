# WashMyCar 应用图标 · v4 明暗双版

2026-11-11 · 2024 款乐道 L60 正面剪影 · 玉绿液态玻璃

| 明亮模式 | 暗夜模式 |
| --- | --- |
| <img src="../../native/iOS/Assets.xcassets/AppIcon.appiconset/Icon-Light.png" alt="浅玉绿色底，清透玻璃质感的乐道 L60 正面车形与一条下沿水纹" width="256" height="256"> | <img src="../../native/iOS/Assets.xcassets/AppIcon.appiconset/Icon-Dark.png" alt="深玉绿色底，同一乐道 L60 正面车形带柔和的珠白绿色折射亮边" width="256" height="256"> |
| [下载明亮版 PNG](../../native/iOS/Assets.xcassets/AppIcon.appiconset/Icon-Light.png) | [下载暗夜版 PNG](../../native/iOS/Assets.xcassets/AppIcon.appiconset/Icon-Dark.png) |

## 本轮设计

以用户指定的正面车形与单条水纹版本为编辑目标，保留构图、剪影语言和下沿流线。车头按 2024 款乐道 L60 正面照片提炼：较宽的跨界车肩部、梯形风挡、小后视镜、上挑日行灯与分体式下灯组。车辆为图标化剪影。

明亮版以比薄荷绿稍深的浅玉绿为基调，暗夜版采用同一色相的深玉绿。两版保持相同的主体轮廓、位置和比例。车形与水纹使用透光的玻璃体、细亮边、柔和折射与内部渐变，呈现 iOS Liquid Glass 风格的通透感。提示词中的主色方向为明亮版 #67BBA5、暗夜版 #102D29；生成图像有连续色调变化。

## 文件与生成提示词

| 文件 | 内容 |
| --- | --- |
| [AppIcon.appiconset](../../native/iOS/Assets.xcassets/AppIcon.appiconset) | Xcode 图标资源组，含明亮、暗夜两张 1024 × 1024 PNG 及 Any / Dark 映射 |
| [明亮原图](v4/washmycar-light-master.png) / [暗夜原图](v4/washmycar-dark-master.png) | 内置 Image Gen 原始输出，1254 × 1254 |
| [明亮版完整提示词](v4/prompt-light.txt) / [暗夜版完整提示词](v4/prompt-dark.txt) | 两次编辑的完整生成输入 |

使用内置 Image Gen 编辑用户指定的图标，并以 2024 款 L60 正面照片辅助调整车型。暗夜版以完成的明亮版为唯一编辑目标，锁定轮廓后调整颜色与光照。通过 macOS sips 等比导出标准尺寸。

两张标准图标为 RGB、不透明 PNG，背景铺满方形画布。通透感来自图标中的静态玻璃材质表现。外部圆角由系统处理。

## iOS 外观切换

iPhone target 的工程设置和工程生成脚本均已指定 AppIcon。资源组的默认 Any 对应明亮版，Dark 对应暗夜版，沿用系统的图标外观机制。

安装包含此资源的版本后，在 iPhone 主屏幕图标自定义中选择“自动”，系统会按外观选择明暗版本；也可手动选择浅色或深色。详见 [Apple 主屏幕图标自定义说明](https://support.apple.com/en-gb/guide/iphone/iph385473442/26/ios/26) 与 [Xcode 图标资源说明](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)。

## 参考与检查

车型年份依据 [乐道 2024 年上市公告](https://www.onvo.cn/news/20240919001)；车头视觉依据 [2024 款 L60 正面照片](https://newcar.xcar.com.cn/photo/s16624_1_c6883/6697398.htm)，图片仅用作轮廓参考。

- 核对两张交付 PNG 均为 1024 × 1024、RGB、无透明通道。
- 目视检查原图与 60 像素预览，核对两版的车形、灯组、水纹、边距和小尺寸识别。
- 通过 Xcode actool 编译整个资产目录，生成 Assets.car 和应用图标信息，无警告。
- 工程文件通过 plutil 语法检查，核对图片、提示词和文档链接。
- 本轮完成源资源配置和资产编译，设备安装与主屏幕切换效果留待安装后确认。
