# WashMyCar Figma 本地控制

这套工具让本机助手通过 Figma 开发插件检查、修改现有设计文件。它直接使用 Figma Plugin API，不经过之前受调用次数限制的 MCP 连接器。

**当前状态：2026年11月9日，已通过真实 Figma 桌面验证本地连接、图层读取、定向修改和 PNG 导出。** 已修正药剂余量数字并检查导出的药剂详情、手表预洗页面。该结果证明本地控制通道可用，不代表全部手机页面、全部手表状态或原生设备体验已经验收。

## 工作方式

**云端保存状态：**本次桌面窗口提示等待重新连接后同步，因此目前确认的是本机画布读写，尚未确认本次修复已同步到云端。请保持文件打开；修复参数、PNG预览和验证记录已保存在项目的 `design/figma/` 下，详情见 [本地验证记录](../../design/figma/local-verification-2026-11-09.md)。

```text
助手 / 命令行 → 本机连接服务 → Figma 插件界面 → 当前文件中的 Plugin API
助手 / 命令行 ← 结构信息、操作结果或截图 ← 插件回传
```

- 本机服务监听 `127.0.0.1:3847`，插件使用 `http://localhost:3847` 连接。服务只接受 `localhost` 或 `127.0.0.1` 的 Host。
- 服务每次启动生成新的随机连接口令。口令不是 Figma API Token，不需要提供 Figma 密码或个人访问令牌。
- 默认目标为 [WashMyCar 双端设计稿](https://www.figma.com/design/8ZDZ8qg4qoMJTtnXDQghDr)，真实文件键是 `8ZDZ8qg4qoMJTtnXDQghDr`。
- 插件和服务都会检查目标文件；不匹配时不执行写入。插件无法读取真实文件键时，也不允许写入。
- 关闭插件或点击“断开”后，不再领取新命令。**需要操作时请保持插件窗口打开。**
- 不添加 Windows 开机启动项，不安装系统服务或计划任务。后台服务仅在手动运行启动器后启动。

## 1 准备 Figma 桌面版

本地开发插件需要使用 Figma 桌面版。安装后自行登录，打开上面的 WashMyCar 文件，确认对文件具有编辑权限。浏览器里的 Figma 页面与桌面开发插件不是同一个运行入口。

官方说明：[Plugin Quickstart Guide](https://developers.figma.com/docs/plugins/plugin-quickstart-guide/)。

## 2 启动本机服务

在项目根目录运行：

```powershell
& .\tools\figma-local\start.ps1
```

启动器会查找本机或 Codex 自带的 Node.js，启动本地后台进程，并打开配对页面。配对页面可以复制当前连接口令、查看插件是否在线及是否打开了正确的文件。再次运行启动器会检查已有服务。

如果 PowerShell 不允许执行脚本，可以直接用已有 Node.js 前台运行，不需要修改系统执行策略：

```powershell
node .\tools\figma-local\server.mjs
```

保持该窗口打开，在另一个终端打开配对页面：

```powershell
node .\tools\figma-local\cli.mjs open
```

前台服务使用 `Ctrl+C` 停止。后台启动时，进程信息保存在 `.runtime/connection.json`；需要完全关闭后台服务时，让助手核对该进程后停止。插件的“断开”只关闭连接，不等于结束后台进程。

## 3 首次导入开发插件

1. 在 **Figma 桌面版**打开 WashMyCar 文件。
2. 从菜单进入 `Plugins → Development → Import plugin from manifest…`，不同版本也可能显示为 `Import new plugin from manifest…`。
3. 选择项目中的 `tools/figma-local/plugin/manifest.json`。
4. 在 `Plugins → Development` 中运行 **WashMyCar Local Control**。

如果 Figma 要求清单中包含它签发的插件 ID，先使用 `Plugins → Development → New plugin` 创建一个本地 Figma Design 插件，选择带界面的模板，取得 Figma 生成的 `id` 后，仅把该 `id` 加入本项目清单。不要编造数字 ID，也不要把清单里的 `main`、`ui`、网络配置和 `documentAccess` 替换成其他值。

清单使用 `documentAccess: "dynamic-page"`。其中 `enablePrivatePluginApi: true` 仅用于官方允许的本地开发接口，以读取真实文件键；不是向文件写入一个声称的身份值。开发网络白名单仅包含本机 `http://localhost:3847`，未开放其他域名。

官方说明：[开发插件导入](https://help.figma.com/hc/en-us/articles/360042786733-Create-a-classic-plugin-for-development)、[Plugin Manifest](https://developers.figma.com/docs/plugins/manifest/)。

## 4 配对并确认连接

1. 在本机配对页面点击“复制连接密钥”。
2. 粘贴到 Figma 插件的“本次连接口令”，点击“连接本地服务”。
3. 核对插件中的文件名、真实文件键和当前页面。
4. 回到配对页面点击“检查连接”，应显示目标文件在线。
5. 先执行下面的 `status` 和 `selection`，确认返回真实设计信息，再发送修改。

插件中的口令只保留在本次内存，不写入浏览器存储。服务为了供命令行读取，会把当前口令保存到本地 `.runtime/connection.json`；该目录已加入项目 `.gitignore`。**不要提交、公开、上传或截图分享这个目录及口令。** 重启服务后需要使用新口令重新连接。

## 命令行示例

以下命令均从项目根目录执行，需要本机服务运行。修改和截图还需要插件在线。

### 查看连接与当前选择

```powershell
node .\tools\figma-local\cli.mjs status
node .\tools\figma-local\cli.mjs command selection
```

`status` 返回服务状态、客户端和命令队列；它本身不能证明插件能读写画布。`selection` 返回 Figma 当前选择及页面信息，未选择任何图层时列表可以为空。

### 检查一个画板

先把请求保存为 `inspect.json`：

```json
{
  "rootId": "4:2009",
  "depth": 2,
  "limit": 100
}
```

```powershell
node .\tools\figma-local\cli.mjs command inspect .\inspect.json
```

这里的 ID 来自本项目已有设计稿；如果复制、重建设计文件或图层，ID 可能改变，应先读取和核对，不要仅凭名称猜测。

### 修复缺失字体与余量数字

在确认图层仍对应目标余量后，可把请求保存为 `patch.json`：

```json
{
  "nodes": [
    {
      "id": "4:2055",
      "props": {
        "fontName": { "family": "Inter", "style": "Regular" },
        "fontSize": 38,
        "lineHeight": { "unit": "PIXELS", "value": 44 },
        "characters": "340",
        "textAutoResize": "NONE",
        "width": 100,
        "height": 44
      }
    }
  ]
}
```

```powershell
node .\tools\figma-local\cli.mjs command patch .\patch.json
```

整段替换 `fontName` 时，插件只加载指定的新字体，并先替换字体再处理文字与排版，因此可以修复旧字体在本机缺失的情况。没有指定新字体时，插件会加载当前文字使用的全部字体；无法加载时会拒绝修改，而不是静默采用另一种字体。字号和尺寸只是本次图层修复值，不是全应用的通用设计规范。

### 保存画板截图

将截图参数保存为 `screenshot.json`：

```json
{ "rootId": "4:2009", "width": 786 }
```

```powershell
node .\tools\figma-local\cli.mjs command screenshot .\screenshot.json .\figma-detail.png
```

截图是 Figma 导出的 PNG，用来检查修改结果；它不会把原设计变成一张不可编辑图片。

### 用结构化场景创建整套新稿

`compose` 根据本机 JSON 创建原生、可编辑的 Figma 图层。默认创建新页面，现有页面不会被替换；指定 `pageId` 时，只向该页追加内容。不要同时填写 `pageId` 与 `pageName`。先查看页面列表：

```powershell
node .\tools\figma-local\cli.mjs command overview
```

把下面内容保存为 `scene.json`：

```json
{
  "pageName": "WashMyCar · V2 iPhone",
  "nodes": [
    {
      "ref": "home", "type": "FRAME",
      "props": {
        "name": "01 首页", "width": 440, "height": 956,
        "layoutMode": "NONE", "clipsContent": true,
        "fills": [{ "type": "SOLID", "color": { "r": 0.97, "g": 0.97, "b": 0.96 } }]
      },
      "children": [{
        "ref": "title", "type": "TEXT",
        "props": {
          "name": "标题", "x": 28, "y": 90, "width": 384, "height": 48,
          "characters": "准备好下一次洗车",
          "fontName": { "family": "Noto Sans SC", "style": "Regular" },
          "fontSize": 28, "lineHeight": { "unit": "PIXELS", "value": 40 },
          "textAutoResize": "NONE"
        },
        "reactions": [{ "trigger": "ON_CLICK", "navigation": "NAVIGATE", "targetRef": "plan" }]
      }]
    },
    {
      "ref": "plan", "type": "FRAME",
      "props": { "name": "02 洗车计划", "x": 520, "width": 440, "height": 956, "layoutMode": "NONE" }
    }
  ],
  "flowStartingPoints": [{ "ref": "home", "name": "手机主流程" }]
}
```

```powershell
node .\tools\figma-local\cli.mjs command compose .\scene.json
```

字体必须在目标 Figma 中可用。默认新建文字使用 Inter Regular；上面的中文字体也应先通过 `fonts` 确认。成功回执包含 `pageId`、所有 `createdNodeIds` 和 `{ ref: 图层ID }` 的 `refs` 字典，供后续检查、定向修改和截图使用。

支持以下声明式内容：

| 内容 | JSON 约定 |
| --- | --- |
| 原生图层 | `type` 为 `FRAME`、`TEXT`、`RECTANGLE`、`ELLIPSE`；只有 `FRAME` 可以写 `children` |
| 唯一引用 | 每个节点必须带 `ref`，本次命令中不能重复；仅允许字母、数字及 `._:-` |
| 自动布局 | `props.layoutMode` 为 `NONE/HORIZONTAL/VERTICAL`；支持间距、内边距、对齐、FIXED/HUG/FILL。自动布局中的绝对定位子项使用 `layoutPositioning: "ABSOLUTE"` |
| 颜色与外观 | `fills/strokes` 仅接受 SOLID；支持圆角、单角圆角、透明度、线宽和有限的 NORMAL DROP_SHADOW |
| 文字 | 支持字体、字号、行高、字距、段间距、水平/垂直对齐和文字框尺寸 |
| 约束与滚动 | `constraints` 接受水平/垂直 `MIN/CENTER/MAX/STRETCH/SCALE`；frame 支持 `overflowDirection` |
| 原型链接 | 节点 `reactions` 支持 `ON_CLICK` + `NAVIGATE/OVERLAY/BACK`。跳转目标 `targetRef` 必须是本次场景的顶层 FRAME；跨批使用 `targetId` 时，目标必须已存在于指定 `pageId` 的顶层 |
| 转场与起点 | 可选 `transition: { "type": "DISSOLVE", "duration": 0.2 }` 或 SMART_ANIMATE，时长0–2秒。`flowStartingPoints: [{ "ref": "home", "name": "主流程" }]` 可写多个，追加页时保留原有起点 |
| PNG 图片 | `assets: { "hero": { "mimeType": "image/png", "base64": "…" } }`，节点写 `image: { "assetRef": "hero", "scaleMode": "FILL" }`；也支持 FIT/CROP。不接受网址或 data URL |
| 复用现有图片 | `image: { "nodeId": "原图层ID", "scaleMode": "FIT" }`，只复用该图层第一个 IMAGE fill。`assetRef/nodeId` 二选一，图片节点不能同时设置 `props.fills` |
| SVG 图标 | `type: "SVG"`，`svg` 提供本地字符串。仅接受 svg/g/path/rect/circle/ellipse/line/polyline/polygon 静态几何；禁止脚本、事件、链接、style、外部资源和嵌入图片。SVG props 仅允许 name/x/y/width/height/opacity |

每次最多5000个节点、嵌套深度40；SVG 内部几何也计入预算。单张 PNG 最多4 MiB、宽高1–4096像素，每次最多30张；单个 SVG 最多32 KiB、100个几何元素。参数按 UTF-8 JSON 限制：`compose` 为12 MiB、`paintImage` 为8 MiB，其余命令为256 KiB；HTTP 请求总量限制16 MiB。较大的手机、手表场景应拆成两次命令。

插件会先检查整份结构、引用、属性、图片头和所有字体，再开始创建画布图层。Figma 运行时仍可能拒绝某项操作；出现 `partial: true` 时，回执保留已经创建的页面、节点 ID 与 refs，不自动删除或重新执行。应先检查实际画布，再发新的追加或修正命令。

升级桥接程序后，重启本地服务，并关闭再重新打开 Figma 开发插件；仅重新点击“连接”不会加载新代码。2026年11月10日新增的 `compose` 已通过模拟与 HTTP 测试，完整场景仍需在真实 Figma 中逐屏检查。

### 已创建画布的恢复与原型补连

如果界面已经出现完整画板，但最终回执失败，**不要重新执行整份 compose**。先用 `overview` 找到实际页面，再读取其图层。`inspect` 支持最多3000项、深度0–4，每项含 `parentId`，可根据父子关系、名称与顺序恢复图层映射：

```json
{ "rootId": "15:97", "depth": 4, "limit": 3000 }
```

单独使用 `wire` 为现有图层补上或重置原型连接。它只修改链接及流程起点，不创建页面或其他图层。请求示例中的 ID 应替换为刚读取的真实 ID：

```json
{
  "pageId": "15:97",
  "nodes": [{
    "id": "现有按钮ID",
    "reactions": [{ "trigger": "ON_CLICK", "navigation": "NAVIGATE", "targetId": "现有目标画板ID" }]
  }],
  "flowStartingPoints": [{ "nodeId": "现有首页画板ID", "name": "手机主流程" }]
}
```

```powershell
node .\tools\figma-local\cli.mjs command wire .\wire.json
```

所有源节点必须属于指定页，目标与起点必须是同页顶层 FRAME。一次最多1000个源节点、每个节点10条链接及100个起点，执行前整体验证。每个节点的 `reactions` 会被本次数组替换，传 `[]` 可清空；传入 `flowStartingPoints` 会替换该页全部起点，省略则保留。可用新的命令 ID 重复设置相同内容，不会增加重复图层或起点。

原型链接、流程起点及回执传输均有独立错误阶段。若画布修改已完成但结果传输失败，备用回执会标记 `partial` 并尽量保留已有 IDs、refs 和页面 ID，方便检查与恢复。

### 为现有药剂瓶图层更新图片

`paintImage` 只替换现有 FRAME、RECTANGLE 或 ELLIPSE 的填充，可将协调好的本地 PNG 渲染图贴到已有药剂瓶容器上。它不创建 UI 图层，也不隐藏或删除容器中的子节点；原有向量瓶身需要由另一条明确的 `patch` 单独隐藏。

```json
{
  "nodeId": "现有药剂瓶图层ID",
  "asset": { "mimeType": "image/png", "base64": "本地PNG的base64正文" },
  "scaleMode": "FIT"
}
```

```powershell
node .\tools\figma-local\cli.mjs command paintImage .\bottle-image.json
```

`scaleMode` 必须是 `FIT` 或 `FILL`。PNG 最多4 MiB、宽高1–4096像素，命令参数最多8 MiB；只接受 base64 正文，不接受网址或 data URL。执行前检查真实目标文件、节点类型和 PNG，再创建 Figma 图像并替换 fills。成功返回 `mutatedNodeIds`；写入中途失败会标记 `partial` 和可能受影响的节点 ID，重复同一命令 ID 不会再次执行。

## 支持的操作与失败处理

白名单操作为 `inspect`、`selection`、`fonts`、`patch`、`createText`、`createFrame`、`navigate`、`screenshot`、`overview`、`compose`、`wire`、`paintImage`。插件不接收任意 JavaScript，没有 `eval`、远程脚本执行或删除画布的命令入口。修改字段和枚举值有边界检查，写入前会检查目标、图层、参数及必要字体。

`FILL`、`HUG` 等排版模式必须有合法的自动布局上下文；不能靠修改字符串强行套用。批量修改会先校验和加载字体，但不承诺 Figma 画布事务：如果运行时在写入中途失败，结果会标记 `partial` 并保留可能受影响的图层 ID，必须重新检查画布。

命令未领取时默认等待最多60秒，过期后不会执行。命令一旦领取，就不会因回传失败或超时而自动再次派发；插件也会缓存已处理的命令 ID，防止相同命令重复执行。**超时不等于画布未改变，不要立刻重新发送同一项修改。**

CLI 会显示命令 ID。可先查询该命令结果：

```powershell
node .\tools\figma-local\cli.mjs result <命令ID>
```

如果仍是 `delivered`，先恢复连接、检查图层或截图，再决定是否发一个新的修改命令。重复回传相同结果是幂等的，不代表修改会重复执行。

## 常见问题

| 现象 | 处理方法 |
| --- | --- |
| 本地服务正常，客户端列表为空 | 打开桌面版中的开发插件，配对并保持窗口打开；仅打开设计文件不足以建立连接 |
| `Session token required` 或 HTTP 401 | 服务可能已重启；重新打开配对页面，复制当前口令后连接 |
| 连接失败或持续重连 | 检查服务是否运行、3847端口是否被占用、插件是否加载最新清单。不要为此开放局域网监听或关闭系统防护 |
| 插件提示网络访问被阻止或清单域名非法 | 本机实际导入时，Figma 拒绝把 `http://127.0.0.1:3847` 用作开发网络域名，因此清单及插件界面统一改为 `http://localhost:3847`。服务仍只绑定 `127.0.0.1`；修改清单后重新导入或重新运行 |
| 本机连接请求成功，但插件一直等待文件信息或绑定超时 | 已修复接收器对 `event.source === parent` 的硬过滤。Figma 可通过隔层转发消息；现在按官方 `event.data.pluginMessage` 协议校验消息结构、预期类型和待处理命令 ID。关闭再重新运行插件，单纯重新点连接不会加载新界面代码 |
| 文件键不可用、只读或目标不匹配 | 确保是正确的已保存云端文件、具有编辑权限，且开发清单保留 `enablePrivatePluginApi: true`；不要把真实文件键检查改成手动声称的值 |
| `Node not found` | 先重新检查画板和当前 ID；图层可能被复制、重建或删除 |
| 字体无法加载 | 先用 `fonts` 查可用字体。整段替换时明确指定新字体；保留原字体的编辑需要该字体在本机可用 |
| 显示 `partial` 或结果回传失败 | 停止继续改同一组图层，查询命令结果并检查实际画布；已派发写入不会自动重试 |
| 切换了服务端口后插件无法连接 | 当前插件清单和界面固定使用3847。若确需换端口，服务、界面 BASE 和清单白名单必须同步修改并重新导入 |

## 检查与维护

### 已完成的真实桌面验证

2026年11月9日，在目标 WashMyCar 文件中完成了以下验证：

- 插件读取真实文件键和图层，经过本机服务收取指令并回传结果。
- 对 `4:2055`、`4:2225`、`4:2121` 三个余量文字图层定向修改，使用 Inter Regular、38字号、44行高、固定文字框；三者的框宽分别为100、100、220，高度均为44。
- 导出了 `iphone-product-detail-local.png` 和 `watch-prewash-local.png`，检查了药剂详情的余量呈现与预洗步骤页面。

这是特定文件、特定操作和两个导出页面的实测记录。没有据此宣称 Watch 所有页面或通知、同步、Dynamic Type 等原生能力已经通过测试。

### 自动化测试

测试集共有36项：10项 HTTP 服务测试、22项 Plugin API 模拟测试、4项插件界面消息测试。2026年11月10日全部通过；涉及代码变更后应重跑，再以当次测试结果为准。compose 的图片解码、字体加载、原生图片创建和画布创建失败会带阶段与资源名称，避免泄露图片内容，并保留可靠的 partial 元数据。

本地自动检查可从项目根目录运行：

```powershell
node --test .\tools\figma-local\tests\server.test.mjs .\tools\figma-local\tests\plugin.test.mjs .\tools\figma-local\tests\ui.test.mjs
```

这些测试验证服务协议、命令派发、身份保护和模拟 Plugin API 行为，不能替代真实 Figma 桌面的字体、自动布局、图片导出及网络验证。真实连接状态以插件回执和当前画布检查为准。
