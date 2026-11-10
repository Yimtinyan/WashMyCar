# WashMyCar v2 — 官方尺寸、产品参考与设计转译

核验日期：2026-11-10。仅整理公开的一手来源与本项目设计建议；没有推荐药剂配比。用户提供的NIO研究是视觉方法参考，不是NIO官方规范或资产授权。

## 1. 画布与尺度

| 设备 | 设计逻辑画布（竖屏） | 原生像素 | 核验依据 |
| --- | --- | --- | --- |
| iPhone 16 Pro Max | **440 × 956 pt** | **1320 × 2868 px，@3x** | Apple中文HIG布局表直接列逻辑点及像素；Apple技术规格列同一像素分辨率 |
| Apple Watch Series 10，46 mm | **208 × 248 pt** | **416 × 496 px，@2x** | Apple规格/HIG列416×496 px；Apple HIG Images列watchOS @2x，因此逻辑点由像素÷2计算 |

务必区分Watch的`416×496 px`和`208×248 pt`，不能把前者当作逻辑点来堆放内容。Figma里以1单位对应1 pt制作，导出时再按倍率输出；设备外壳、表带、表冠属于画布外展示，不计入上述屏幕区域。

官方来源：

- [Apple中文HIG：布局](https://developer.apple.com/cn/design/human-interface-guidelines/layout)。检索可读版本明确列iPhone16 Pro Max为440×956点、1320×2868像素@3x；动态页面的自动读取有时仅显示需JavaScript提示。
- [Apple iPhone 16 Pro Max技术规格](https://support.apple.com/en-us/121032)。确认2868×1320像素、Dynamic Island及圆角屏幕。
- [Apple Watch Series 10技术规格](https://support.apple.com/en-au/121202)。46 mm机型为416×496像素。
- [Apple HIG：Images](https://developer.apple.com/design/human-interface-guidelines/images?language=_11)。确认watchOS图像倍率@2x；逻辑点除法是本项目换算，非该页逐型号列出的数据。

### Safe area：规则与本次稿件假设要分开

**官方规则：** 关键文字和交互须避开系统定义的安全区，避免被Dynamic Island、状态栏、工具栏、Tab栏或圆角遮挡；实际区域随系统、容器、方向和运行状态变化。原生实现应读取系统safe area，而不是依赖一个适用于所有机型的硬编码边距。

**Figma建议：** iPhone主内容横向内边距24 pt可作为本项目风格探索值；系统顶部和底部区域使用对应Apple设计资源或设备模板。若需要快速绘图，可暂留顶部约62 pt、底部约34 pt为原型占位，但这两个数值仅为本次草图假设，不应标成Apple跨版本固定规范。底部主要按钮应位于home indicator上方，长页面允许滚动，不能为了首屏齐整裁掉药剂全名。

**Watch建议：** 对208×248 pt屏幕单独排版，不缩放手机页面。先保留系统时间/导航区域，再放当前步骤；可探索约12–14 pt横向内容内边距和底部独立确认区，所有数值均属项目稿件建议。Apple建议同一行不超过三个图形按钮或两个短文字按钮，通常更适合全宽文字按钮。大尺寸表应把额外空间用来增大控件和内容，而不是增加更多控件。

官方来源：

- [Apple HIG：Layout](https://developer.apple.com/design/human-interface-guidelines/layout?changes=lat_3__1_2)。安全区、适配、Dynamic Type与watchOS行内控件建议。
- [Supporting multiple watch sizes](https://developer.apple.com/documentation/watchos-apps/supporting-multiple-watch-sizes?language=objc)。Series10/11的42/46 mm支持；46 mm默认Dynamic Type为XLarge，应测试所有文字尺寸。未重新编译的旧watchOS应用可能被系统letterbox，不能凭屏幕规格假定旧实现已经占满全屏。

## 2. Koch-Chemie Gentle Snow Foam瓶型参考

### 已核验的官方产品与图片入口

- [Koch-Chemie全球产品页面](https://www.koch-chemie.com/us/products?cHash=2838dd89ad9bbab4004aa6da709056bc&tx_kcproducts_produkte%5Baction%5D=show&tx_kcproducts_produkte%5Bprodukt%5D=727)。列1 L与5 L包装。
- [Koch-Chemie USA：Gentle Snow Foam](https://kcxusa.com/products/gentle-snow-foam-1l)。当前公开产品页与包装图入口，1 L/5 L选择。
- [USA官网产品图，1080宽](https://kcxusa.com/cdn/shop/files/Gentle_Snow_Foam.jpg?v=1745434999&width=1080)。由产品页Image链接直接得到。
- [同一图片原文件](https://kcxusa.com/cdn/shop/files/Gentle_Snow_Foam.jpg?v=1745434999)。保留地区和文件版本，不将区域包装图直接当作中国在售批次照片。

### 视觉采用边界

**已目视核对。** 主线程下载官方参考图后，本子任务亦通过`view_image`检查了[本地官方图](reference-images/kcx-gsf-official.jpg)。当前这张1 L USA包装图的视觉特征为：乳白色不透明塑料外观的细长圆柱瓶，圆润宽肩收至窄颈，**中灰/银灰色竖纹旋盖**，不是此前未经核对时推测的黑盖；上半段鲜明黄色标签、大号黑色`Gsf`，下半段较长的灰色标签，底部标1 L。设计应保留黄/灰标签的辨识度，不套用示例橙色WASH标签。

“HDPE”仅可用作建模材质的工作描述；图片目视不能独立证明聚合物成分。该包装图只证实对应地区/版本的外观，不代替中国在售瓶标或完整包装实测尺寸。图中包装商标不能被解释为WashMyCar与品牌存在合作关系。本任务生成的协调渲染仍须标记为示意，不冒充原厂摄影。

## 3. Fireball当代产品与图片参考

### 官方产品身份

| 产品 | 官方页与范围 | 设计用途 |
| --- | --- | --- |
| Hydro Shampoo | [Fireball韩国官网](https://www.fireballkorea.com/washing/hydro-shampoo)；[Fireball USA产品页](https://fireball-usa.shop/product/hydro-shampoo/) | 正洗/洗护类库存视觉样本，不由商品名生成用量 |
| Show car SHAMPOO | [Fireball韩国官网](https://www.fireballkorea.com/washing/showcar-shampoo) | 正洗类备选视觉样本 |
| Janus | [Fireball韩国官网](https://www.fireballkorea.com/dressings/janus)；[官方轮胎护理目录](https://www.fireballkorea.com/dressings) | **轮胎护理**产品，不应写成洗车液或正洗药剂 |

韩国官网[Washing目录](https://www.fireballkorea.com/washing)列Hydro Shampoo、Show car SHAMPOO等产品及500 mL/4 L等包装，Janus则位于Dressings目录。上述来源确认了产品和分类，不能据此推定不同地区的包装都相同。

### 韩国官网页面直接关联的图片URL

- Janus原图：[fe7082_2de60ff07d7741e1bf0845ea3a9da74d~mv2.jpg](https://static.wixstatic.com/media/fe7082_2de60ff07d7741e1bf0845ea3a9da74d~mv2.jpg)。
- Janus页面变换图：[750×666链接](https://static.wixstatic.com/media/fe7082_2de60ff07d7741e1bf0845ea3a9da74d~mv2.jpg/v1/fill/w_750%2Ch_666%2Cal_c%2Cq_85%2Cusm_0.66_1.00_0.01%2Cenc_avif%2Cquality_auto/Image-empty-state.jpg)。
- Hydro Shampoo原图：[fe7082_8f12a55710c8459fa769159921552f53~mv2.jpg](https://static.wixstatic.com/media/fe7082_8f12a55710c8459fa769159921552f53~mv2.jpg)。
- Show car SHAMPOO原图：[fe7082_e75ae59432594c0ca445def613f7ed03~mv2.jpg](https://static.wixstatic.com/media/fe7082_e75ae59432594c0ca445def613f7ed03~mv2.jpg)。

**Hydro Shampoo已目视核对。** 主线程下载官方参考图后，本子任务亦通过`view_image`检查了[本地官方图](reference-images/fireball-hydro-official.jpg)。视觉特征为：**透明祖母绿/青绿色细长圆柱瓶身，密集垂直肋纹，短肩窄颈，银色金属感圆柱旋盖，中上部灰色横向标签，大写白色`HYDRO SHAMPOO`及FIREBALL字样**。这张图不支持“黑瓶黑盖”的推测，应删除该方向。图片目视也不足以证明瓶材是PET还是玻璃；可描述为透明塑料感/玻璃感示意材质，但不要将材质推测当作制造商事实。

**链接与版本边界：** 上述URL来自对应韩国官网页面的Image链接。网页研究工具最初返回缓存缺失，但主线程已成功取得Hydro图并可视检查；不得把早期工具错误写成图片不存在。Wix末尾`Image-empty-state.jpg`只是文件名，不能据此判定内容为占位图。Janus及Show car SHAMPOO的具体包装本轮尚未目视复核，不把Hydro的瓶形移植为它们的已确认外观。本子任务只读取主线程已存参考图，没有下载或改动其他文件。

## 4. 用户NIO参考的适用边界

已读取用户文件`C:/Users/yimti/Downloads/NIO_蔚来设计风格研究与首页UI落地指南.docx`。它明确声明不是NIO官方品牌规范；其中Token是作者提出的项目建议。可延用其“克制、清晰、自然、有温度”的组织方式，不使用NIO标识或专属字体。

参考文档项目建议色：画布`#F8FAF9`、表面`#FFFFFF`、辅助表面`#F0F5F4`、主文字`#1D3137`、次文字`#586A71`、强调`#116A70`、轻高亮`#E3F0F0`、边框`#DEE7E7`。这些不是本次网络核验得到的NIO官方色值。

## 5. 本轮六项设计建议（项目推导）

1. **以内容制造奢华感，不堆装饰。** iPhone库存页用完整、光照统一的药剂物体作为主视觉；产品名、品牌、剩余量放在同一阅读轴。最多一处有表现力的材质区域，其余依靠空间和字阶。库存卡片保持轻边界，避免每个区块相同圆角、阴影和权重。
2. **建立双端独立字阶。** iPhone探索34 pt/600页标题、20–22 pt/600模块标题、17 pt正文、13–15 pt辅助信息；mL与数值对齐，关键剩余量可用28–32 pt。Watch以当前动作20–22 pt、关键数量18–20 pt、药剂/工具14–16 pt作为稿件起点；这些是设计建议，不是Apple固定字号。允许Dynamic Type增大后滚动或分层，不能为了精致而用低对比细字。
3. **一屏一项主动作。** 手机首页首屏聚焦“本次流程”及“查看准备清单”；选药剂和工具在同一编辑上下文内完成。Watch固定为“当前动作 → 药剂/数量 → 关键工具 → 完成此步”，不复制库存编辑和表单。
4. **文案短，但完整表达状态。** 手机可用“已保存这次安排”“尚未记录取用”“请核对这瓶的剩余量”；Watch用“第2步 · 车身正洗”“完成此步”“流程已暂停”。将“库存不足12 mL”与“调整用量”放在同一处，不仅用红色或抽象错误码表达。
5. **动效解释变化，不抢注意力。** 点击反馈约120–160 ms，步骤展开约200 ms，详情进入约260 ms；液位仅在记录成功后平滑下降约300–450 ms。Watch步骤切换保持主控件位置，不使用持续旋转的产品或无限呼吸灯。减少动态效果开启时，直接切换到最终状态。
6. **洗后彩蛋是一刻收尾，不是奖励系统。** 用户确认最后一步后，手机可用一次约600–900 ms的光泽扫过车身轮廓，随后定格“洗好了，刚刚好。”；下方保留可验证的“4个步骤已确认 · 本次取用已记录”。Watch只做一次简洁勾选过渡和“本次完成”，不弹满屏彩带、不虚构清洁分数、节水量或检测结果。此彩蛋为原创设计建议，不来自NIO或Apple官方规则。

## 6. 审核提示

- 目标尺寸不能替代真实safe area与Dynamic Type测试；高保真Figma图不是原生设备验收。
- 产品照片、原创示意渲染、交互三维模型应分别标记；不要把示意瓶内透明液位宣称为真实不可透瓶的视觉测量。
- 样本购入日期、地点、价格和剩余量需标为示例；本文件没有采集、下载或暴露用户私密数据。
- 本轮只写本参考文件，没有改动实现、Figma画布或其他交付内容。
