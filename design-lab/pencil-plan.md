# Apple Pencil 2 原生阅读体验实施规划

首个可验收范围是同一份 PDF 上的原生文字高亮、独立笔迹和手指导航。复用冻结版的 `StudyPDFView`、`PDFHost`、`PDFSelection.studioLocator` 和四类 Mark 色。EPUB 继续使用当前 Readium navigator 与 Locator，新增的书写位置是绑定章段的页边注。实施须在原型与方案确认后另开开发分支。

## 输入与工具栏

| 模式 | Apple Pencil | 手指 |
| --- | --- | --- |
| 阅读／选择 | 轻点内容和工具，选字、拖选择手柄。需要用笔移动页面时，使用明确的「移动页面」动作 | 翻页、滚动、双指缩放、长按选文、操作工具、保存 Mark |
| PDF 勾画 | 普通笔、自由荧光笔或笔迹橡皮擦。扫描页可自由圈画，或切换「区域 Mark」选取范围 | 继续导航和缩放。批注仅在显式打开手指书写时接受单指笔迹，默认关闭，双指仍属于导航 |
| EPUB 页边笔记 | 书写面仅在笔记区激活。正文 Pencil 保留选择与导航能力 | 正常阅读、选文、打开或编辑文字笔记 |
| 知识白板 | 选择模式拖节点，连线模式从端口连到目标，勾画模式圈画或书写 | 平移、缩放画布。使用选择模式或节点菜单也可移动、连线和编辑 |

工具栏通过 Reader 的「批注」入口展开，在 44 pt 触控目标内呈现选择、笔、荧光笔、橡皮、Mark、语义色、撤销与重做。宽屏整组贴左或右，窄窗保持工具顺序并收纳次要设置，保留状态名和 VoiceOver 按钮标签。工具栏持久保存惯用侧，收起时恢复相关阅读焦点。四个语义色沿用蓝单词、黄语料、紫关键词、绿关键句。荧光笔是透明自由笔迹。通过「选择 → 高亮／Mark」生成真实文字高亮。橡皮仅作用于笔迹，删文字高亮经现有 Mark 操作。

采用 `PKCanvasView` 和 `PKInkingTool` 的笔／记号笔、`PKEraserTool`，默认 `.pencilOnly`。由现有 `UIViewRepresentable` Coordinator 持有 overlay provider、活动页面的 canvas 和工具状态。阅读模式让覆盖层退出触控命中，避免抢选文和链接。`PKCanvasView` 本身是滚动视图，原生实验要核对绘图识别器、PDFView 翻页／缩放与嵌套滚动的关系。只协调公开手势或属性，包括评估 `isInMarkupMode`。`.pencilOnly` 约束笔迹来源，手指事件是否自然传到文档仍要实测。若实测同一瞬间的缩放会破坏笔迹坐标，优先完成笔画，再应用页面变换。若某支持系统无法稳定使用页上输入，先保留可靠文字高亮与区域 Mark，并提供同页独立书写面，等通过验证后再启用页上勾画。[PKCanvasView](https://developer.apple.com/documentation/pencilkit/pkcanvasview) · [PDFKit 覆盖层与手势](https://developer.apple.com/videos/play/wwdc2022/10089/) · [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview) · [SwiftUI UIKit 集成](https://developer.apple.com/tutorials/swiftui/interfacing-with-uikit)

双击绑定到当前可编辑 Reader，使用 `UIPencilInteraction.preferredTapAction`。按系统设置切换橡皮或上一工具，或显示当前颜色面板。关闭／忽略时保持原状态，其他系统偏好仅在支持且行为匹配时接入。iPadOS 17.5 起用 `didReceiveTap`，17.0–17.4 保留旧 delegate 回调。原生实验比较紧凑自定义栏和按场景持有的 `PKToolPicker()` 的焦点、遮挡与事件行为，确保同一双击只由一个入口处理。双击在阅读模式不创建 Mark，不会因切页或多窗写入另一个文档。所有操作有可见触控入口。[Apple Pencil 双击](https://developer.apple.com/documentation/applepencil/handling-double-taps-from-apple-pencil) · [系统双击偏好](https://developer.apple.com/documentation/uikit/uipencilinteraction/preferredtapaction) · [PKToolPicker](https://developer.apple.com/documentation/pencilkit/pktoolpicker)

## PDF 的锚点、注释和笔迹

| 对象 | 身份和存储 | 显示、重开与回跳 |
| --- | --- | --- |
| Anchor / Mark | 沿用 `Source` ID、文件指纹、现有从 1 开始的页码、`ReadingLocator`。`PDFTextAnchor` 继续表示页内 UTF-16 范围、选文和前后文。扫描页以页内区域及可选 OCR 摘录表达 | 校验指纹、页码和文本范围，旧记录沿现有安全回退。指纹不符或文字无法唯一定位时显示精度提示。区域 Mark 以实际图像区域回跳 |
| Annotation | 由 Mark 推导显示。文字选区按页、按行，用现有矩形／四边点生成内存中的 `PDFAnnotation(.highlight)`，继续映射 CardKind | 按页更新自有标记，保留原 PDF 自带注释。使用 `PDFSelection` 的文本范围、`selectionsByLine()` 和 `quadrilateralPoints`，按 SDK 的注释坐标约定转换并测试；矩形可作为旧记录和复杂字形的保守回退 |
| Ink | 候选为独立、版本化的 `PKDrawing` 记录，按 Source ID ＋指纹＋页码定位，可选关联 Mark ID，不要求每笔都生成 Mark | PDFKit 按可见页创建／回收画布，笔迹直接由 PencilKit 渲染。笔画结束、离页和 App 进入后台时提交待保存变更。读取失败保留原数据并提示 |

统一的 PDF 笔迹空间以未旋转 CropBox 的左上为原点，单位为 PDF point，向右、向下。保留有效的页面尺寸和坐标方案版本作为校验信息。给定同一页，从 CropBox 左上和 x、y 两个单位偏移构造三个不共线的点，用公开的 `PDFView.convert(_:from:)` 转到 PDFView，再用 UIKit 转到 overlay 局部坐标。三点确定仿射变换，保存时把 drawing 的副本乘逆变换，显示时从原始 canonical drawing 乘当前变换。每次布局从原始记录重算，避免多次缩放产生累积误差。验证 PDFKit 对 overlay 的旋转已体现在转换链中，应用层避免额外补旋。页码转换集中处理，严格拒绝未知坐标版本、无效尺寸和不可逆变换。旋转 0/90/180/270、非零 CropBox、单双页和不同缩放要用一组标定点做往返验证。[PDFView 坐标转换](https://developer.apple.com/documentation/pdfkit/pdfview) · [PDFAnnotation](https://developer.apple.com/documentation/pdfkit/pdfannotation) · [PDFSelection](https://developer.apple.com/documentation/pdfkit/pdfselection) · [PencilKit](https://developer.apple.com/documentation/pencilkit/)

拟用现有数据库中的独立增量存储保存页笔迹及之后的笔记附件，扩展现有 LibraryRepository 与备份校验，不改 Source、Card、Mark、Anchor 的既有语义。先为持久化试验定义一页一个活动绘图的修订号，延迟写入不得覆盖更新版。单次撤销栈位于当前文档／窗口，离页保留已提交内容，重开无需恢复撤销历史。备份需要覆盖笔迹、摘要校验、恢复失败回滚和旧包无笔迹的兼容。删除行为沿用当前软删除、恢复与永久清理规则。原 PDF 字节保持不变。后续显式导出可以生成新 PDF 副本，标准文字高亮写为注释，自由笔迹可导出为可见外观或压平到副本。保留可编辑的 PencilKit 原件由应用备份承载，第三方 PDF 阅读器的笔迹可编辑性须独立验证。[Apple PDFKit 导出示例](https://developer.apple.com/videos/play/wwdc2022/10089/)

## EPUB 的可重排批注

读取现有 `currentSelection` 和完整 Readium Locator。以资源 href 和可用的 fragment 指明章段，保留选文及前后文来核对重复文字。Locator 的 progression 用于粗略回到章节，精确展示需要可验证的文本匹配。没有选文、内容指纹变化或多个候选都匹配时，保留原笔记并提示仅能回到章节，等待用户重新绑定。针对同一原文，字体、字号、页边距、单双页变更后通过 Navigator 重建高亮与下划线 Decoration。

Pencil 的精确选文先实测当前 Readium/WebKit 的系统选择和手柄。若某版本不向正文暴露可靠的 Pencil 选区，保持手指长按与移动选区，再用 Pencil 操作邻近工具栏。「写批注」打开独立 PencilKit 笔记面，以同一个 Mark/Locator 关联。笔记面有自己的版面坐标和尺寸，正文只显示页边指示与可点击入口。它会跟随章段重新出现，自由笔迹仍保留在笔记内。固定版式 EPUB 也先采用同一可靠方案。保留现有原文和词典选单。[Readium Locator](https://readium.org/architecture/models/locators/) · [W3C 文本引用选择器](https://www.w3.org/TR/annotation-model/#text-quote-selector)

## 组件和增量整合顺序

1. **Home 与 Cards。** 在 `StudyAppearance` 延伸纸面、墨色、卡片语义色、字级、间距和左右工具栏偏好。复用系统自适应颜色、Dynamic Type、NavigationSplitView 与键盘焦点。把 `StudyHomeView` 的 Card、Source、Project 查询装进可复用的页面容器、卡面、继续读入口及项目行。Home 用稳定模块 ID 和适用宽度描述排序和尺寸，首批沿用定稿默认布局，之后可放进独立 UI 偏好。卡片展开保留色线和题句。结合 Reduce Motion，使用轻淡入或即时切换，回原文后将无障碍焦点交给定位目标。
2. **Library 和自动封面。** 统一 `SourceCover`，优先用户封面，再用源内可验证的资源。EPUB 优先包内 cover，PDF 用合适首页／Quick Look 缩略图，视频用已有海报或本地 AVAsset 帧，网页使用已授权采集到的预览图。缺图按平台排版，以 Source 稳定 ID 选择模板和配色。按 ID、资源版本或摘要、标题摘要、模板版本与输出尺寸缓存。列表先显示占位，后台缩小图片、合并重复生成请求。派生缩略图可清理，用户自选封面须复制到可备份的应用数据。读取或验证失败使用模板。保留现有导入、列表、搜索、项目和显式多选。[Quick Look Thumbnailing](https://developer.apple.com/documentation/quicklookthumbnailing)
3. **Reader。** 先在现有 PDF reader 验证覆盖层、笔迹存储、原生选文和手指导航，再逐步接入工具栏、四类高亮和笔迹备份。PDF 内容保持原版式。通过可靠性验收后再接 EPUB 重排与页边注。书封动画在 Reader 标题区收束为来源识别，导航与绘制生命周期互相独立。
4. **Knowledge Map 与 Cards 的笔记面。** 先验证现有 `ProjectBoardView` 的选择和拖动，把 Pencil 作为选择／移动方式。连线与自由勾画分模式，节点移动提交位置，笔迹另存画布世界坐标，画布平移和缩放仅影响视图。后续复用页边笔记的绘图容器到卡片笔记，保留现有纯文本编辑。
5. **全局检查。** iPad 横竖屏、分屏、多窗口、左右手、触控、可访问字号与 VoiceOver。只在阶段改动需要时触发对应原生验证。

## 验收与关键风险

- **自动验证。** 使用已知标定坐标验证不同旋转、CropBox 和缩放下写入／重显往返，检查页间和文档间隔离。覆盖损坏笔迹的读取、较新修订防覆盖、旧备份兼容、删前备份与恢复失败回滚，以及原 PDF 摘要。EPUB 用重复选文与不同版面验证同一 Locator 的回跳、笔记关联和歧义退化。通过冻结版既有高亮、项目关系以及复习数据回归。
- **Apple Pencil 2 真机。** 以兼容 iPad 比较 PencilKit 的成笔延迟、快速划线与细字、手掌误触、手指翻页和捏合、落笔期间的页面变换及中断恢复。验证双击的擦除、上一工具、色盘和关闭，全程核对两手操作。轮测快速滚动后的页面复用、横竖切换、重开、大 PDF 和扫描 PDF。同一笔迹须回到原内容位置。动画与工具栏不可挡住选区手柄或焦点。
- **放行条件。** 先看原文定位和数据完整，再看成笔手感。真机确认前，PDF 页上勾画、双击、防误触、笔迹延迟与 EPUB Pencil 选区均为待验状态。Pencil Pro 挤压和硬件悬停不进入 Pencil 2 验收条件。
