# Demo v0.2 design specification

Two coordinated generated concepts: inventory-concept.png and planner-concept.png. Built-in Image Gen prompts describe a white/cool-grey Chinese personal wash planner with warm orange controls, inventory bottles, purchase label inspector, step editor and watch preview. No raster screenshot is used as application UI.

Tokens: white #ffffff, sidebar #f0f2f4, ink #17202a, muted #77808b, border #e2e5e9, accent #ec7436, selected #fff5ee. System Chinese sans-serif; headings 32px/1.3, body 14px/1.6, controls 14px, labels 12–14px. Sidebar 208px, detail rail 340px, editor row 84px. 12px panel corners, 8px input corners, no ornamental hero.

Inventory: heading, add action, brand and use filters, search, six modeled bottles with quantity and percentage; inspect panel with rotation, actual logged fill, purchase date/place/price and explicit record-use form. Planner: editable title/vehicle, numbered ordered rows, drug/amount/water/tools/note editor, preparation checklist, watch display with one confirmation action.

Functional additions to concept: explicit sample-data notice, water field, editable purchase details, local storage warning, reorder buttons, preparation transaction confirmation, completed-session state. Required to satisfy requested behavior and avoid pretending the sample inventory is real. Purchase prices/dates/places are demo values. Drug amounts are editable illustrative inputs, not inferred recipes. Physical bottle shapes and labels are representative models rather than exact manufacturer packaging. Code-native Three.js geometry is intentional because real dynamic liquid levels and rotation are required. Use can be recorded on individual bottle, or at session preparation exactly once; planning alone never debits inventory.

Responsive: below 1050px detail rail becomes modal/bottom drawer; below 700px sidebar becomes header navigation, product grid two columns, planner and watch stack; controls retain 44px touch targets.

Validation: Browser plugin absent in this session; use bundled Playwright Chromium for screenshots, console checks, desktop/mobile interactions and local-file portability checks. Comparison ledger and test results will be recorded in demo README after verification.

## 2026-11-10 · 精修版 v0.3

共享规范：canvas #F7F8F5、ink #223032、secondary #6B7872、action #163E3C、line #E0E6DF。手机440×956，水平边距28；标题34/46、正文17/26、元信息13/20；主按钮56高、圆角14。底部主要入口为洗车、药剂、记录，设置在右上角。

新增完整主页概念`refinement-home-concept.png`，由内置Image Gen生成；银车与两款瓶子素材与本轮Figma稿共用，复制至`src/assets/`。真实文字与控件仍为可交互DOM。

| 对照项 | 概念与渲染证据 | 落地与有意扩展 |
| --- | --- | --- |
| 首屏次序 | 品牌/标题/银车/车辆/方案/两行步骤/准备动作/三项导航 | 保持相同层级和次序，增加必要编辑入口 |
| 字体 | 34主标题、17步骤名、较小元信息 | 统一角色字阶，中等标题字重，内容不挤满 |
| 色彩 | 暖白底、深墨绿主动作、灰绿说明 | 同一组语义变量适配浅色和深色 |
| 容器 | 开放留白与细分隔 | 流程、记录、履历采用开放行列，不堆叠嵌套卡片 |
| 图像 | 银色爱车自然融入背景 | 车型视角改用与Figma共用资产，是有意统一 |
| 动态 | 完成后爱车闪光 | 三种随机变体保存至本次流程，尊重减少动态效果 |
| 药剂 | 品牌参考瓶型与通用瓶型 | 默认品牌外观图，三维检视单独切换；不透明瓶另有液位示意 |
| 数据闭环 | 准备/腕上确认/完成记录 | 单次扣库存，历史快照与当前编辑独立 |

QA使用Playwright+本机Edge（本次未提供Browser插件）。已检查440×956、390×844、1440×1100与Watch208×248，19项交互路径通过，相关运行错误0。目视核查主页、库存、检视、手表完成、记录、深色设置；6项账本测试通过。此结果不等同原生设备、Dynamic Type或真实通知验证。
