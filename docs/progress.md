# 开发进度日志

本文件是交付状态、版本变更和真机结果的唯一入口。操作规则见[工作流](workflow.md)，错误与待办见[工程问题](engineering-issues.md)。日期使用北京时间；实现、自动验证、真机验收分别记录。

## 当前交接 · 性能代码收尾，验证暂停 · 2026-11-27

按用户最新指示“先跳过测试和编译，完成代码优化，编写日志供其他模型接手”，本轮停止新的测试/编译，取消了正在运行的 [45929590952](https://github.com/slaythefishordie-droid/Stuido/actions/runs/45929590952)（`b6d4861`）。此取消不代表测试结果。当前是未完成原生验收的候选分支，不发布 Release/IPA，不合并发行分支。

工作分支 `performance/v3.7-low-power`，最后业务代码 `87fb4194e9ac2b8768a724a85ffcfaa9d01c001a`。后续提交仅整理交接文档。新模型必须先读 [PERFORMANCE_HANDOFF.md](../PERFORMANCE_HANDOFF.md)，再按新对话的用户指示开展工作，不能擅自把“暂缓验证”写成“已通过”。

代码收尾包括：阅读器呈现回调断开、接受的 EPUB 保存意图保留、同选区在途防重复、可取消的封面等待队列、预算改变时唤醒等待者、Home 单次投影、复习计数去掉排序。最后三项所在提交只做人工静态审查和 diff 检查，遵从用户要求未执行测试或编译。

已知证据：Linux 核心 Debug/Release 各 42 项通过（Release 于 2026-11-27 补验），协议/Safari 43 项通过。Release 原生 [45928043579](https://github.com/slaythefishordie-droid/Stuido/actions/runs/45928043579) 在链接阶段失败，摘要记录 0 tests，精确缺失符号仍待定位；之前 Debug [44970616821](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44970616821) 的完整错误也未取到。当前网络对两次日志所在 Blob 主机拒绝访问，41 条规则仅确认存在于草稿，未确认应用。新的 CI 诊断已可通过 GitHub annotations 输出计数/错误，后续候选补充链接符号块。

稳定恢复基线、合成基准和原 v3.7 正式发行信息仍保留下方。代码实现完成与真机/原生验收完成必须分开；剩余热点和完整接续步骤见交接与结果文档。

## 性能重构阶段记录 · 2026-11-22

用户授权以 v3.7 为基础进行独立性能重构，当前工作分支为 `performance/v3.7-low-power`。基线是 `1888dcb570093aba680f70baa403dcbc5fcd7f99`（相对发行标签只有文档整理），已推送恢复标签 `baseline/v3.7-before-performance-20261121`。原本干净的 `work` 分支及 main、release/v3.7.0、v3.7.0 均保留；没有重置、强推或发布新版本。

首阶段 `285825291a8a05db9c7602c6d346572d4f2a7064` 实现快照缓存、集合观察、阅读位置后台合并、资源策略、封面管线、PDF 后台打开和截止调度。后续补齐标记/墨迹异步保存、恢复/导出等待边界、测试故障注入修正。详细证据与限制集中在 [性能审计](../PERFORMANCE_AUDIT.md)、[性能结果](../PERFORMANCE_RESULTS.md) 和 [真机指南](performance/IPAD_TEST_GUIDE.md)。保持原数据格式、权限、UI 布局和功能，未引入依赖升级。

Linux Swift 6.2.4 核心 42/42；固定夹具 Release 基准在同一当前环境重跑：一万卡片热读约 502.077→0.012 ms，阅读位置事务约 1003.617→519.062 ms，Source 的 Marks 查询索引约 238.909→0.244 ms。这是合成核心结果，非 iPad 响应/能耗实测。首次基准日期未固定的问题及比较脚本见结果文档。

[首次原生检查](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44969553523) 核心通过、App 与扩展编译通过，测试直接依赖 GRDB 导致链接失败；已用系统 SQLite 做故障注入；后续运行与当前暂停决定见顶部，不再沿用当时的等待状态。未启用 IPA 打包。本轮尚未完成真机低电量、长时内存、触控和阅读压力验收，不标记稳定版。

## 当前交付 · v3.7.0 · 2026-11-21

当前维护分支为 `release/v3.7.0`。正式版于北京时间 23:30 发布。发行标签对应 `78e5f3f82e376a9287a2ea1be1f61b27ab7a106a`，build 10。本轮补全收集箱编辑与归档、回收站、EPUB 正文设置、PDF 回跳、Lounge 后台音频及 Files 分享。各模块的实际检查与真机待验项见 [60 项验收记录](quality/v3.7.0.md)。

设备归档与 IPA 校验成功。原生 Swift 核心 34/34，iPad（A16）模拟器 64/64（含 3 条界面流程），协议与 Safari 43/43。实包 9,345,498 字节，SHA-256 `fcef38a3d30155c746799f2d022de86cd6e77a1d4dcd34951e1e69ff66589027`。[下载 IPA](https://github.com/slaythefishordie-droid/Stuido/releases/download/v3.7.0/KnowledgeStudio-resignable.ipa) · [Release](https://github.com/slaythefishordie-droid/Stuido/releases/tag/v3.7.0) · [构建日志](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44917375916) · [IPA 构建产物备份](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44917375916/artifacts/14713156896)

AltStore Classic 使用原签名身份覆盖安装，保留 Safari Web Extension 和 Share Extension。原位升级、真实 App Groups、Lounge 锁屏播放与控制、耳机中断、Pencil、窗口布局和旧书锚点待实机。构建产物备份保留至北京时间 2026-11-28 23:26。安装步骤见 [安装指南](build-and-install.md)。

### 近期发行记录

| 版本与日期（北京时间） | Build / 提交 | 实际交付与验证 | 日志 |
|---|---|---|---|
| [v3.6.0](https://github.com/slaythefishordie-droid/Stuido/releases/tag/v3.6.0) · 2026-11-21 | 9 / `08c4ac0` | 首版 Lounge、本地音频解码导入、资料改名、回收站、视频分组历史。核心 34、模拟器 59、协议与 Safari 43。 | [iPadOS 构建](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44879654347) |
| [v3.5.0](https://github.com/slaythefishordie-droid/Stuido/releases/tag/v3.5.0) · 2026-11-21 | 8 / `1e5223d` | 本地视频 QuickMark、Files 打开、三种封面模式、卡片队列。核心 31、模拟器 52、协议与 Safari 43。 | [iPadOS 构建](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44796137820) |
| [v3.0.0](https://github.com/slaythefishordie-droid/Stuido/releases/tag/v3.0.0) · 2026-11-20 | 7 / `c8cc249` | 书房原生视觉、SwiftUI 优化、Safari 扩展随包。核心 31、模拟器 49、协议与 Safari 43。 | [iPadOS 构建](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44715715405) |

## 页边书房原生集成 · 2026-11-20

独立开发分支 `feature/v2-reading-room` 从 `36d8d4aa2a26c42d64154ad593bb9b5fa55a12a7` 开始。美术基准为[第二版原型](https://github.com/slaythefishordie-droid/Stuido/blob/aaa9d4314ac9dce785cb3f94fc9ac7ece5b99518/design-lab/README.md)。既有冻结证据是原生编译成功、核心 30/30、模拟器 46/46，协议与 Safari 43/43。[既有原生运行](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44693478738) · [既有协议运行](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44693478678)

| 功能范围 | 现有代码和本轮集成 | 逐模块验收 |
| --- | --- | --- |
| 导航与 Home | `StudioView` 统一深梅栏。固定展开、自动、紧凑，窄窗菜单与 Reader 沉浸切换。Home 使用真实卡片、最近阅读位置和项目 | 同一资料在 11/13 英寸 iPad 横竖屏和分屏中保持阅读导航，核对字号与 Reduce Motion |
| Library 与 Source | 保留导入、搜索、列表、多选和直接打开。加入出版式封面、Readium 内嵌 EPUB 封面、系统本地缩略图及手动更换／恢复／重建 | 无源图资料使用可复现模板，拒绝无效图片。网页与 YouTube 走已有来源数据，缺图可自选；共享资料的封面跨项目一致 |
| Project | 资料、卡片、地图、语义关系分别进入。资料分组可展开，项目资料笔记编辑仍由 `ProjectSourceNoteView` 处理 | 同一 Source 加入两个项目，核对项目笔记独立、关联解绑无损。语义关系来自已关联的导入内容，与白板布局连线分开 |
| Cards | 四类卡片共用有语义色的版式，类别、搜索、编辑、来源、并排原文、词典、发音、复习仍可进入 | 现有卡片字段、标记及复习历史读写无损，来源跳转仍传既有 locator |
| PDF | 原版式、单双页、连续滚动、封面和 RTL 偏好，自适应窗口，恢复 PDF 当前页坐标。保留文字锚点、高亮、区域和 OCR，并加入 PencilKit 覆盖层和浮动导航 | 核对黑底扫描页、非零 CropBox、四种页旋转、单双页和精确回跳。Pencil 2 延迟、手掌、双指缩放、翻页和系统双击须实机 |
| EPUB | Readium 重排、字号、边距、主题和窗口分页。四类选文 Mark 保持完整 Locator，独立页边手写面由原 Mark 定位 | 中文/英文、重复选文、换页和更改字号后验证原文与笔记，固定版式单独看。Pencil 与系统选文手柄须实机 |
| 视频／外链 | 本地 `VideoPlayer` 保留系统时间轴、字幕选择和播放，Mark 与可展开历史置于画面下方。YouTube、网页、播客继续通过原 Safari 位置打开 | 真机核对字幕、时间跳转、后台和 Safari ↔ App 冷启动闭环 |
| My Inbox／AI Inbox | 原 Native Messaging/App Groups 交接和去重。标记按资料分组，有书房卡面。AI 批次、JSON 校验、匹配、预览、确认事务和关系导入均保留 | 同 ID 重试、重复卡筛选、批量归档及导入时的关系完整性 |
| Knowledge Map | 项目仍使用现有单白板数据，保留节点、连线、编辑、移除、撤销及辅助移动。由实际节点生成封面，可覆盖为用户图片 | 空白板、真实白板和自定义图都可从项目打开。验证拖动、连接与原对象引用。白板 Pencil 自由绘制尚未纳入本轮 |
| Review / FSRS | 当前、稍后、自评和历史继续使用原 FSRS-6 和事务。主题、到期卡片和设置接入视觉系统 | 复习排期、退出及暂停历史兼容，四类卡视图稳定 |
| Data Manager / Trash / Backup | 独立维护入口、筛选、确认和保护原数据的恢复流程。自定义封面、PDF Ink 及 EPUB 手写作为可选数据进入同一份备份；派生缩略图留在缓存 | 旧快照缺少新字段可解码。恢复前验证、失败回滚、项目和复习关系以及原始 PDF 字节须保持 |
| Safari / QuickMark / 词典／发音 | SwiftUI 设置分离常用选项与共享诊断，扩展沿用原 JS 的精听、回溯、标记、重送和旧备份。扩展弹层使用共享配色。词典、许可真人录音与 TTS 服务路径保持 | 自动用例与真实 Safari 权限分别记录。真机验证网页适配器、A–B、资料交接、词典弹窗、离线及实际音源 |

### 集成分支验证

- 首次 Xcode 检查 `15e3213` 的原生依赖与核心 31/31 通过。App 模块编译时，PDFKit 的 overlay delegate 协议缺少主线程标注，Swift 6 拒绝主 actor 的实现。后续提交将兼容边界限定在该旧协议，所有 UIKit 与笔迹状态仍由主 actor 管理。归档与 IPA 均由无打包配置跳过。[首次原生运行](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44708867255)
- 原生候选 `32d96702e6091b2508f39f1d3b6ba27c0424b0ca` 经 Xcode 26.2 编译，核心 31/31、iPad 模拟器 48/48。通过用例包括窗口分页规则、带封面和墨迹的备份回滚／恢复、原资料字节校验、锚点及笔迹持久化。2026-11-20 北京时间约 17:41 完成，归档、IPA 打包和上传均跳过。Linux Swift 6.2.4 核心复核也为 31/31。模拟器共享容器仍出现未签名提示，AltStore 和真实 Safari 双向共享继续单独验收。[原生复验](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44710511106/job/136200708617)
- 本地协议与 Safari 用例 43/43。对实际扩展设置弹出面板进行了浅色、深色与诊断展开渲染检查。iPad 屏幕和真实 Pencil 输入仍以实机验收为准。

### 图标

[图标提案与小尺寸对比](../design-lab/app-icon/icon-concepts.png)。A「页边书签」将暖纸拱页与古铜页签叠在深梅底推荐为主图标。B「打开的书」突出跨页阅读，C「一页批注」突出阅读转为自己的笔记。可分别查看 [A](../design-lab/app-icon/icon-a.png)、[B](../design-lab/app-icon/icon-b.png)、[C](../design-lab/app-icon/icon-c.png) 的 1024 × 1024 sRGB 不透明方形母版。操作系统应用主屏遮罩。选定后再接 AppIcon asset catalog 并检查 iPad 主屏及系统外观。[Apple App Icon 资产规范](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)

## V2 冻结期开发记录 · 2026-11-20

当时的 V2 冻结目标为 2.0.0/build 6。当期仅做原生检查，IPA 在后续发行版本按用户安排手动构建。

| 原计划 | 本轮实际实现 | 验收边界 |
| --- | --- | --- |
| 当前阅读完善 | PDF 文件指纹、跨行/页坐标、文字范围及上下文、矩形四边形、手动区域、单页 Vision OCR、四类选文高亮/批注/词典/发音；EPUB 改容器承载选文、显式单双页与页边距 | PDF 四边形来自 PDFKit 行包围框，不宣称复杂倾斜字形的逐字轮廓；OCR 永远按区域定位。重排、触控菜单、旋转、复杂文字层须真实资料验收 |
| 阶段 5：知识组织 | 词汇库/语料库聚合、四类筛选与全文字段搜索；混合白板布局/连线/编辑/移除/撤销；项目分组及独立资料研究笔记；宽屏项目栏/直接打开/批量回收站 | 核心引用、笔记隔离、移除分组保留对象测试通过；手势与分屏待验。图谱连线是布局关系，不改知识对象语义 |
| 阶段 6：复习与 Today | swift-fsrs 6.0.0 显式 FSRS-6 参数；今日到期/稍后、自评记录、调度与完整历史原子保存、参数/版本/修订号；目标保持率、暂停/退出保留历史 | 不新增题型。幂等、冲突、重开与退出通过核心测试；旧编辑防覆盖新增原生测试待执行；有旧历史而无调度状态时拒绝静默重排 |
| 阶段 7：真机打磨与交付 | 备份兼容扩展、离线语音缓存/TTS、阅读与管理分屏、第三方及使用说明、无 IPA 原生检查 | 阶段原始目标见 product-spec 第 391 行附近；真实 iPad、大文件、异常退出、升级恢复验收延期，不能写为全部通过 |

### 发音实现与研究

保留 Apple 系统词典。统一服务从维基词典文件引用查询 Commons，核对明确录音者/录制说明、允许的开放许可、实际口音和 HTTPS 来源；优先支持 Commons 提供的 MP3 转码。缓存包含音频、署名和许可，先离线命中，再联网；失败使用 AVSpeechSynthesizer，不将合成语音冒充真人。缓存有数量/体积限制，不进入知识库备份。开放录音覆盖不完整，同形异音词由来源录音决定，不能承诺全部词义/口音覆盖。

FSRS-7 的官方 TypeScript 文档已有相关实现与迁移说明；本轮固定经评估的 Swift FSRS-6 适配，不把其他语言的新版本直接当作已验证 Swift 升级。来源与许可证见 dependencies。

### 实际验证与接续

- 完整本地 Swift 核心 30/30 通过（提交 d8d4764）；其后非法 PDF 页序防护与阅读时间字段的 LibraryTests 12/12 通过。协议 CI 44680990864 成功。
- 首批 V2 提交 d8d4764 已推送，原生检查 44680990806 的依赖、核心与 App 编译通过；测试目标夹具编译失败，已修复（BUILD-09）。归档/IPA 跳过。收尾提交 e6a2bd2 的运行 44681986690 核心 30 项通过，但白板类型推断超时（BUILD-10）；白板拆分后的 44691897830 继续定位到收集箱类型推断超时；收集箱也按职责拆分并减少重复过滤，等待最终复验。
- 已通过修改 Swift 文件的语法解析及 `git diff --check`；这不等于 Xcode 类型检查。
- 查明旧原生运行 44551316214 失败：Readium 子类没有可继承初始化器。本轮改为原生 navigator + 父容器响应链，见 BUILD-08。不能沿用旧日志中的“尚在执行”。
- 新增 PDFKit 原生范围/上下文往返测试，并扩展备份恢复测试覆盖项目笔记、分组和复习状态；尚待原生执行。
- 本轮收尾补充：导入/关联使用勾选行；白板拖动实时预览、松手持久化、可访问性移动动作和节点索引；发音完成后释放音频会话；书桌按 lastReadAt 排序，相同位置短时间不重复落盘。指南、模型和工作流同步，仍只维护三份日志。
- 后续处理原生检查中的阻塞，保存最终提交与证据；不构建 IPA。设备交互统一标记待真机验证。

以下为历史交付记录，不代表当前 V2 的验收结果。

## 设计重构接续 · 2026-11-19

历史要求是修复后重构再交付 IPA；已被 2026-11-20“完成本轮也不构建 IPA”覆盖。现有功能范围内接入书房侧栏、暖纸动态背景、紧凑/舒展、四类筛选、项目直接打开、长按快捷删除、明确批量选择、回收站范围切换和宽屏卡片/原文对照。未新增 Home 或图谱，不改对象关系与删除/恢复规则。候选版本 1.0.1/build 5，原 v1.0.0 标签保留。

本轮基于已知成熟交互模式进行原生实现，尚无真实界面截图/真机验收，不能仅凭语法解析认定布局通过。完成修复阶段 Xcode 检查后提交最终重构候选进行原生验证；最终结果在此补充。

## 阅读与体验修复开发 · 2026-11-19

依据用户真机反馈，先修 EPUB/高亮，再整理现有交互，不新增产品模块，不修改 v1.0.0 标签。

- 阶段一：Readium 选文菜单直接保存四类高亮；完整 locator（包含选文上下文）落盘，阅读位置在翻页及离开时保存，未显式指定出处时恢复 Source.lastLocation。缺少完整选文定位时只承诺章节/进度并提示。点已有高亮可编辑备注与颜色。可选 cardKind 字段兼容旧记录，旧高亮默认保持黄色；PDF/EPUB/标记/收集箱/卡片共用四类映射。
- 阶段二：阅读设置持久保存字体、字号、行距、纸白/暖纸/夜读、自动宽屏双页；保留书籍固定版式限制。界面显示名集中转换为中文，协议字段不改。收集箱按 Source 分组并支持显式选择批量归档/回收站；项目内容直接打开，关联设置独立展开；管理选择使用勾选而非开关；QuickMark 回溯收进控制区，保留全部精听档位。
- 实际检查：本地 LibraryTests 9/9，包含新字段与完整 EPUB 定位/备注重开及旧数据兼容；Node 43/43。新增原生 locator 上下文往返和颜色映射测试。最终候选 80d2adc 的协议运行 44551316178 成功；原生运行 44551316214 最终失败（Readium 子类初始化，见 BUILD-08）。前两候选因更新取消，不算原生通过。Swift 语法解析不替代 Xcode 类型检查。
- 未验证：真实书籍的选文菜单、重复文本定位、跨章节/重开、笔记编辑、旋转/分屏双页、PDF 颜色和 Safari 控件。现有阅读器与管理页做局部改善，这条记录描述修复阶段；用户随后授权的侧栏/对照重构见上方接续条目。用户资料和现有功能保留。
- 设计依据：采用已有 Apple Books 式书页/字号/行距、Finder 式直接打开、显式选择批量操作的知识，并核对锁定 Readium 3.11.1 源码接口；本轮未进行外部产品实机调研，不冒称浏览研究已完成。

## 设计方向更新 · 2026-11-19

已融合用户 Product Design Charter，完整目标见[产品计划](product-spec.md)的设计章程，执行边界见[工作流](workflow.md)。此次仅更新规范和日志，未重构页面、变更数据模型或生成新 IPA；以下 v1.0.0 验证结果不构成新设计验收。

后续 UI 工作以私人数字书房、内容优先和直接操作为基准：Home 书桌、Library 项目树、可进入的 Project、Reader 选文工具与并排对照、按 Source 分组的 Inbox、清晰四类卡片与自由白板、专业 Data Manager、克制的 QuickMark 常驻控件。紧凑/舒展及 iPad 多栏贯穿各模块。实现差距需在具体任务中核对，不因写入章程标为完成。

项目共享 Source 与独立研究语境、地图混合节点、直接回收站及 QuickMark 能力保留的实施边界见 UX-01。后续先针对用户选定的界面给简短方案，核心关系/迁移的重大调整按授权边界确认；本条不是自动开启全部界面重做。

## v1.0.0 交付基线 · 2026-11-19

- 当时的开发分支为 `feature/safari-extension`（远端默认分支的历史操作见 ADMIN-01）。
- [v1.0.0 已公开发布](https://github.com/slaythefishordie-droid/Stuido/releases/tag/v1.0.0)，2026-11-19 21:15:51，非草稿、非预发布。标签提交 b82e4ed；功能提交 d0938a5；CI PR 合并提交 f7dae1954dd44b497806e0335962a824998af652。后续提交仅文档维护。
- 版本 1.0.0 / build 4；原生运行 [44484104854](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44484104854)：核心 21/21、iPad 模拟器 32/32、设备归档、签名权限和 IPA 校验通过。协议/Safari 运行 44484104729：43/43。
- 实包 8,005,262 字节；SHA-256 `c4de7372a639e8c9da5fa3dfc5ea3f5d8b78d81261163d207cf67ffe69749244`。下载后 ZIP、版本及 iPhoneOS 平台复核通过。
- Release 安装包附件尚未上传（NET-02）；已通过对话文件与 [Actions Artifact](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44484104854/artifacts/14510239330) 交付，Artifact 到期日 2026-11-26。不要为上传重建 IPA。
- [原生证据](verification/native-run-44484104854.json) · [发布证据](verification/release-v1.0.0.json) · [安装指南](build-and-install.md)

## 两份计划阶段 1–4 的交付

| 范围 | 已实现 | 验证边界 |
| --- | --- | --- |
| 产品阶段 1 | GRDB 事务快照、稳定 ID、非破坏迁移、Data Manager、回收站、ZIP 备份恢复 | 迁移、引用保护、恢复及恶意 ZIP 自动测试通过；真实资料恢复待验 |
| 产品阶段 2 | 四类卡片、Quick Capture、双 Inbox、JSON 文件/粘贴、匹配/去重/预览/确认导入 | 协议与事务测试通过；完整触控流程待验 |
| 产品阶段 3 | Library、Project、PDF 阅读、高亮、Mark 建卡与回跳 | 原生编译通过；真实 PDF 闭环待验 |
| 产品阶段 4 | Readium EPUB、本地视频、位置恢复、词典外链 | 原生编译通过；真实书籍/视频待验 |
| Safari 里程碑 1 | 扩展随 App 分发、双向共享诊断 | 用户报告真机编号自动传输对应成功；未提供型号/包摘要，不补造 |
| Safari 里程碑 2 | QuickMark、持久待发、同 ID 重试、My Inbox | 存储与模拟消息测试通过；冷启动/真实 Safari 交接待验 |
| Safari 里程碑 3 | 回溯、±1/2/3 秒、A–B、历史、备注/删除/备份、个性化 | 自动测试通过；真实旧备份与页面触控待验 |
| Safari 里程碑 4 | 逐站授权、文章段落/选文与页面音频定位适配 | 模型/适配测试通过；Safari 权限与 DOM 变体待验 |

已完成可读性与效率整理：新增 Swift 模块统一格式，交接/导入建立临时索引，无变化不写库，1 MiB 分块复制和摘要、ZIP 工作后台执行。不将本地合成测试宣称为真机性能提升。当时阶段 5–6 尚未实施；最新进展以顶部 V2 基线为准。

## v1.0.0 发布时的验收清单

1. 发布附件永久归档、默认分支管理：处理 NET-02 / ADMIN-01，权限变化前不重复尝试。
2. 真机记录型号、系统、包 SHA、AltStore 版本及结果：保留扩展安装 → Safari 识别 → 双向共享；继承用户已确认的里程碑 1 结果，不要求无理由重测。
3. 新增闭环：App 关闭时 QuickMark → 冷启动 Inbox → 建卡 → 回跳；重复/中断重送仅一条 UUID。12.8 秒回溯 2 秒落在 10 秒，播放继续。
4. 四类 JSON 导入与重复导入、PDF/EPUB/视频标记回跳、备份恢复、删除恢复；失败时保留原件与错误，不清库。
5. Safari 横竖屏/分屏、桌面/移动 watch 页、同标签换视频、广告/直播/Shorts、A–B 与历史跳转、网站授权撤回、真实旧书签。系统全屏/PiP、无 audio 元素等边界按实测记录。

## 精简历史

| 时间/基线 | 结果与追溯 |
| --- | --- |
| v0.1.0 / 7df6ef1 | 旧 YouTube 播放、时间 Mark、回跳、本地原型与导入协议；无 Safari 扩展。原生运行 44227526926 成功，旧原型保留在标签 |
| Safari 分发 / ea8ca26 | 44432216488 成功，核心 8、模拟器 14；随后用户确认里程碑 1 双向共享。见 verification 同名记录 |
| QuickMark / 94841ea | 44437247550 成功，打通最小 Inbox；不能作为后续新增功能的验证证据 |
| 阶段 1–4 / 0c70210、648a631 | 44475088781 因 SwiftUI 声明失败；44482131742 因 Readium 类型桥接失败；均保留 JSON，修复见 BUILD-05/06 |
| v1.0.0 / d0938a5 | 44484104854 全部成功，以上当前基线取代历史“待构建”状态 |
| 2026-11-19 日志整合 | 合并状态、更新、验收与旧发布清单；网络历史并入工程问题。保留三份维护日志与原始 JSON，文档改动只查链接和差异，不跑业务测试 |

## 后续记录格式

每个交付追加一条：日期 / 对应计划 / 功能与关键模块 / 实际检查及 SHA、运行链接 / 未验证项 / 下一步。失败尝试仅引用工程问题 ID，不复制整段日志；阶段结束更新顶部基线。旧全文可从整合前提交 362a3b5 的 Git 历史追溯。
