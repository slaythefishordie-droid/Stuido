# 开发与构建问题日志

最新整理为 2026-11-21（北京时间）。本文件记录修复经验与未决问题。[开发日志](progress.md)记录版本与结果，[工作流](workflow.md)记录执行方法。

## 快速定位

| 现象 | 先检查 | 对应记录 |
| --- | --- | --- |
| Actions 一直 Queued、没有执行步骤 | runner 是否分配、检查注解 | BUILD-01 |
| In progress 多分钟不变 | 当前步骤与日志时间，不只看运行总状态 | BUILD-02 |
| 归档成功但没有 IPA | 打包步骤、签名权限导出、失败注解 | BUILD-03 |
| Safari 扩展嵌入校验失败 | 实际 `.appex` 中的 Info.plist 和资源层级 | BUILD-04 |
| API 可访问但日志或 IPA 下载失败 | 每个下载请求的重定向主机和 CONNECT 状态 | NET-01 |
| 面板按钮不再响应 | Native Messaging 是否结束或超时 | CODE-01 |
| 共享记录无法读取 | 重签后的组配置、文件状态、两端实际编号 | CODE-02 / DEVICE-01 |

## BUILD-01 · 托管 runner 未分配（已提供替代路径）

- **现象与证据：**运行 `44292208343` 首次尝试没有步骤执行，GitHub 注解为 `The job was not acquired by Runner of type hosted even after multiple attempts`，同时提示 macOS ARM64 容量不足。重试仍未取得机器，后由新运行的并发策略取消。
- **处理：**核对官方镜像包含 Xcode 26.2 和 iOS 26.2 后，改用标准 `macos-15-intel`；现已设为默认，`macos-26` 保留为手动备选。没有切到付费 larger runner。
- **验证：**Intel 运行 `44309054436` 已执行测试与归档；修复打包后，`44432216488` 全部成功。主机为 Intel 不改变设备 IPA 必须是 iPhoneOS arm64 的要求。
- **复用方法：**先查运行、job、步骤和注解，再决定切换 runner。两个标准池都不可用时等待 GitHub 恢复，或另行配置具有相同 Xcode 工具链的 Mac；Windows 不能替代 Xcode 归档。不要把未执行测试记作代码测试失败，也不要将云端域名白名单当成 GitHub 调度开关。

## BUILD-02 · 模拟器步骤长时间没有输出（已确认最终通过，内部慢启动原因未定）

- **现象与证据：**成功运行 `44432216488` 的模拟器步骤用时 12 分 09 秒；编译完成与测试启动之间有约 8 分 42 秒日志空档。随后 14 项测试全部通过，测试套件约 1.738 秒完成。前一次相同步骤约用时 6 分 52 秒。
- **处理：**保留正在执行的运行，核对步骤状态与失败注解，结束后读取完整日志。没有因界面暂时不变化而取消构建或删减测试。
- **边界：**日志足以定位等待发生在测试启动前，不足以确定模拟器内部慢启动的具体原因；不将它写成业务死锁或 GitHub 全局故障。
- **复用方法：**工作流把编译、模拟器启动、测试合在一个步骤中，并设有 25 分钟 job 超时。先判断 Queued、In progress、Failure 的差异。不要连续触发同分支构建：并发策略会取消前一次运行。若实际超时，保留失败日志后再决定重试或切换 runner。

## BUILD-03 · 为消除弃用提示而引入权限解析回归（已修复）

- **现象与证据：**提交 `be6bd2f` 把 `codesign -d --entitlements :-` 改成 `--entitlements -`。运行 `44309054436` 的 14 项模拟器测试及设备归档成功，但权限文件在 `plistlib.loads` 处抛出 `InvalidFileException`，因此没有 IPA。
- **原因与处理：**导出的数据格式不符合解析器要求。提交 `ea8ca26` 恢复此前已验证的 XML-only 导出方式，继续检查主 App、扩展的签名和精确的 App Groups 声明。
- **验证：**[运行 44432216488](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44432216488) 的权限解析、签名验证、IPA ZIP 校验和上传均成功。[失败证据](verification/native-run-44309054436.json) · [成功证据](verification/native-run-44432216488.json)
- **复用方法：**当前冒号弃用提示是非致命警告。在替代参数经过真实 macOS 工具链验证前保留已验证方式；不要仅为消除警告修改输出协议，不要删除权限断言来使构建变绿。Linux shell 语法检查不能验证 Apple codesign 输出。

## BUILD-04 · Safari 扩展资源层级不正确（已修复）

- **现象与证据：**旧运行 `44244882996` 在嵌入扩展时报告 `Couldn't load Info dictionary ... SafariExtension.appex`。后续核对并修正 XcodeGen 的资源组织，`Resources` 从 folder 引用改为 group，使 manifest 等网页资源位于扩展包根目录。
- **验证：**提交 `547eaf4` 对应运行 `44245690553` 通过模拟器、设备归档和扩展打包检查；后来取回的完整日志再次确认成功。[历史日志复核](verification/log-review-2026-11-18.json)
- **复用方法：**修改 `ios/project.yml`，不手改生成的 Xcode 工程来掩盖配置问题。检查实际 `.appex`，不能仅凭源目录中存在 manifest 判定 Safari 能识别扩展。构建成功仍须与真机 Safari 识别分别验收。

## CODE-01 · Native Messaging 无返回导致面板永久禁用（已修复）

- **现象：**等待原生响应期间禁用按钮，原生请求不结束时缺少恢复路径。
- **处理：**提交 `831c391` 添加 10 秒超时、请求重入保护和响应格式校验，在结束路径统一恢复按钮；迟到响应不能覆盖后续读取结果。
- **验证：**4 项面板测试覆盖超时恢复、迟到响应、无效响应、拒绝及同步异常；与协议测试一起 31/31 通过。[协议与面板 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44292215642)
- **复用方法：**UI 超时不代表原生写入已取消。提示先读取核实，再决定重试；正式 Mark 流程仍需按唯一 ID 去重，不能直接把诊断面板的重试行为当作正式交接队列。

## CODE-02 · 无效共享组配置静默回退、读取错误不明确（已修复）

- **现象：**AltStore 元数据类型异常时，条件转换可能落入旧配置路径，访问错误的共享组；读取前的存在性查询也不能证明随后的读取成功。
- **处理：**提交 `831c391` 要求存在的 `ALTAppGroups` 必须为包含唯一、非空字符串的数组，否则明确报错；只有该字段不存在时才使用 `SharedAppGroup`。直接读取并仅把文件不存在作为空记录，其他错误继续报告，保留损坏文件。
- **验证：**共享存储测试覆盖独立写入重开、损坏文件保留、组配置优先级与异常、缺失文件、来源不符及读取目录等边界，已纳入 14 项模拟器测试。
- **复用方法：**不要以清空数据或静默切换共享目录处理配置错误。增加第二个共享组前必须重新设计选择规则，不能随意取数组第一项。

## PERF-01 · 导入去重排序重复序列化（已优化，保持兼容）

- **现象与处理：**排序比较中反复规范化并序列化相同元素。提交 `831c391` 改为每个元素先计算一次排序键，再排序和提取原值。
- **验证：**为既有合法样例固定优化前指纹，确认结果保持一致。10,000 条合成关系、5 次运行的本地中位耗时约从 46 ms 降至 23 ms；这是局部微基准，不代表整个 App 提速一倍。
- **复用方法：**优化先保留协议和指纹语义，再减少重复工作；不能通过修改预期指纹来掩盖兼容性回归。相关入口为 `tools/protocol/validator.mjs` 与其测试。

## NET-01 · 配置草稿不等于运行策略（历史经验）

过去草稿 41 条、实例 8 条导致附件下载失败；这些数字只描述当时状态，不作为当前配置。核对 observations_current、enforced 与实际重定向主机，再测试真实客户端。日志/API 成功不证明附件成功。保持代理和 TLS，不保存签名 URL。[历史证据](verification/network-allowlist-audit-2026-11-19.json)。v1.0.0 已通过连接器下载实包，上传另见 NET-02。

## DEVICE-01 · 自动测试与真机权限分别记录

用户已确认里程碑 1 双向编号共享；新增流程仍待验，统一见[进度验收](progress.md)。模拟器 NOT_CODESIGNED 与临时目录单测不能证明 AltStore 重签权限。不能把旧诊断包结果推广到新功能。

## ADMIN-01 · 默认分支（受阻）

用户已授权设为 feature/safari-extension，但管理 API 返回 Resource not accessible by integration（403）。需要仓库管理员修改默认分支；权限不变不重复调用。开发继续使用 Safari 分支。

## 待办与已知边界

- 真实旧脚本/备份缺失，合成 youtube-time-marks v1 测试不能证明实际互通；取得样本后复验，不改原件。
- SQLite 为事务聚合快照；分表/索引迁移按真实数据规模另行评估。不是已实现 SQL 外键表结构。
- Safari DOM、动态脚本注册/权限、Readium 真书定位待真机验证；无可读 audio 元素不承诺音频时间采集；扫描 PDF 无 OCR，EPUB 无 DRM。
- 备份上限单文件 4 GiB、合计 8 GiB、20,002 项，清单/知识库各 64 MiB。后台操作已实现，细粒度进度/取消留后续。
- 本地系统安装曾受限，已有工作区 Swift/SQLite 工具链可用；恢复环境时先查现状，不重复系统安装。

## BUILD-05 · SwiftUI 属性包装器多变量声明（已修复）

运行 44475088781 的依赖解析、锁文件和核心测试通过；App 编译报 `property wrapper can only apply to a single variable`，位置在 ManagementViews/StudioView 的 @State 声明。改为每个属性单独声明。Linux `swiftc -frontend -parse` 不执行该层类型检查，不能替代 Xcode 编译。运行 44484104854 原生编译和模拟器测试通过；不重跑未变更的 Node 测试。

## BUILD-06 · Readium 3.11.1 定位桥接类型（已修复）

运行 44482131742 已消除 @State 声明问题，依赖和核心测试通过；App 编译定位到 SourceReaders 的两处差异：Locator 要求 ReadiumShared.JSONValue，不接收 [String: Any]；Link.href 是 String，而 Locator.href 才是 AnyURL。已按锁定版本源码转换 JSONValue 并直接比较 Link.href，不改动依赖版本。运行 44484104854 原生编译和模拟器测试已通过；[失败记录](verification/native-run-44482131742.json) 保留原始步骤结果。

## PERF-02 · 大量交接与大文件操作（原生测试已通过）

- WebMark/PageCapture 交接使用临时 ID/来源字典和已接收集合，将循环中的线性查找改为索引查找；事务状态未变化时跳过 UPDATE。导入预览按来源 ID、卡片内容签名建立索引，保持重复判定规则。
- 文件导入使用 1 MiB 分块复制并计算摘要，复核副本后移动为不可变资料；备份、校验及恢复资料复制在后台任务执行。最终数据库替换仍在应用服务边界提交，保留恢复前快照和失败回滚。
- 代码统一为四空格、110 列的 Swift 格式；仅处理本轮新增/修改模块，没有重排无关播放器代码。
- 本地 LibraryTests 8/8 通过，含 1,000 条标记首次与重复交接、来源类型分离。耗时是本地合成场景，不代表 iPad 真机吞吐；不为性能删减摘要或引用检查。

## BUILD-07 · XcodeGen 设备族声明覆盖（非阻塞待办）

v1.0.0 的 project.yml 全局设置为 TARGETED_DEVICE_FAMILY=2，但生成工程的目标平台默认值覆盖它，实际 Info.plist 与 package-report 为 [1,2]。CI 明确检查包含 iPad，32 项 iPad 模拟器测试与设备归档均通过。本版不承诺 iPhone 布局兼容。后续在各 target 明确设置后验证产物；不为此重复本次完整构建。

## NET-02 · 本地附件上传受限（v3.7.0 已完成附件交付）

v1.0.0 的本地客户端访问 `uploads.github.com` 返回 403，Release 使用 Actions 产物链接和已校验的实包交付。原始观测见 [网络证据](verification/network-allowlist-audit-2026-11-19.json)。

v3.7.0 从 GitHub 托管 runner 下载已通过测试的原始产物。上传前对照标签提交和 SHA-256，随后将 IPA、摘要及打包报告附到 Release。该操作复用了原归档。[附件上传日志](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44919350658)

## UX-01 · 设计章程落地（待实施核对，2026-11-19）

来源：用户 Product Design Charter，规范已并入 product-spec.md。本条记录实施边界，不把未经界面核对的假设称为已发现缺陷。

- 项目独立笔记/解释/语境需要与共享 Source、Mark、高亮分清作用域；现有数据结构是否满足在实施前核对。存储方案须说明跨项目可见性、解除关联/删除、导入、备份和恢复行为；重大迁移须获同意并验证，禁止仅改 UI 冒充独立语境。
- 自由白板需表达概念、卡片、资料、笔记，保留四类一级 Card；节点移除不等于删除原对象。具体结构/关系变更先方案与必要授权，图谱不追记为 v1.0.0 已交付。
- 直接移入回收站无需归档；仍保留引用保护、可恢复性及永久删除的必要确认。减少无意义弹窗不等于绕过数据安全机制。
- QuickMark 新常驻/展开布局保留 ±2 秒既有功能；±1/3 秒和 A–B 优先可见，不将用户未提及的旧能力默认删除。
- Home、多栏/密度、项目树、阅读对照和 Inbox 分组按具体页面分批落地；每批用“打开资料到继续思考”的实际路径验收，记录尚未完成和真机边界。确认满足后按项关闭，不做无关全 App 重构。

## READER-01 · EPUB 选文、定位与高亮（修复候选，待原生及真机验证）

用户报告注释/高亮/定位/跳转存在问题。源码确认：底部保存动作会在没有选区时退化为页面位置，缺少菜单内保存；高亮写死黄色；仅离开时保存阅读进度，部分非显式定位入口未提供恢复回退。并非已复现所有真实书籍故障。

修复：选区菜单内立即取完整 Locator.text 上下文与位置，单独区分页位置标记；翻页代理持久化位置；增加可选 cardKind，统一蓝/黄/紫/绿；旧字段缺失保持黄色；点击装饰查看备注。Readium NavigatorDelegate 的 presentError 必须实现，不能仅靠 Linux parse 判断协议符合。仅有章节回退时明确精度不足。

验证证据统一见进度本次条目。真实重复文本、书籍 CSS/固定版式与选区交互仍待设备复验；不得以存储往返测试宣称阅读器画面或回跳已真机通过。非阻塞：大量高亮的装饰重建可在真实大书测量后优化，不删减定位信息换性能。

## DEV-01 · 自动审批服务额度限制（2026-11-20）

查询原生 CI 的 require_escalated 命令被自动审批服务阻止：usage limit，审核无法完成；并非认定操作不安全。未绕过审批；当时未取得结果。后续本轮连接器已取得旧运行结果，网络推送也已恢复；无需继续将该额度限制列为当前阻塞。旧原生失败见 BUILD-08，不为查询结果重打包。

## PDF-02 / MAP-01 · V2 实现与待验边界

手动区域、OCR、指纹/上下文/坐标锚点、FSRS、Home、项目分组和独立语境、混合白板均已有候选实现；不再把早期缺口清单作为当前状态。PDF 的跨页区域拖动需分次保存，复杂字形用可靠视觉区域兜底。白板已补文字/连线编辑、撤销及临时节点索引，实时拖动预览与可访问性移动动作已有代码；实际手势、辅助操作和大量节点性能仍待设备验证。实际检查见进度，剩余限制统一见 V2-01。

## BUILD-08 · Readium 选文容器与 V2 原生验证

旧运行 44551316214 最终失败于 `StudyEPUBNavigator cannot be constructed`。核对锁定 Readium 源码发现公开便利初始化器委托给私有指定初始化器，不能被该子类继承。已移除子类，直接实例化 EPUBNavigatorViewController，用父 UIViewController 加入选文响应链；并修复批量删除误传 Array 而接口要求 Set。运行 44680990806 已通过 App 源码编译，Readium 初始化错误消除；后续失败在测试夹具（见 BUILD-09），不宣称模拟器测试通过。

## V2-01 · 当前验证与非阻塞边界

- PDFKit 行包围框构成矩形四边形；复杂倾斜/异常文本层优先使用手动区域或 OCR，不保证字形轮廓。文件指纹不符禁止精确跳转；旧无指纹记录仅承诺页面。OCR 映射与旋转须真实扫描 PDF 验收。
- Readium 重排/重复文字定位依赖完整 Locator 的选文及前后文，原生菜单响应链、固定版式与单双页需真机验收。
- Commons 并非完整发音库；只播放许可/来源可确认的可解码资源，离线缓存或 TTS 兜底。录音口音按文件实际信息标示；同形异音词暂无义项选择。
- FSRS 旧记录若缺失调度状态，停止该卡调度，保留历史；不猜测重建。未来算法升级需明确兼容策略，不以库版本号推断算法版本。
- 本轮结束也不构建 IPA；真机、签名、安装、真实大文件性能均延期。不得将功能候选当稳定正式版。


V2-01 网络证据补充：2026-11-20 通过网页检索核对公开录音与许可；执行环境直连 Commons API 返回代理 403，未取得 live API fixture。不绕过网络策略，不将合成元数据单元测试称为在线播放通过。应用代码已实现标准 API 查询/回退，真实请求与播放待允许网络或设备验收。


## BUILD-09 · 备份测试夹具误插入

首批 V2 运行 44680990806：依赖锁和核心测试通过，App 源码编译通过；测试目标编译因 LibraryAppTests 的恶意 ZIP 测试误插入另一测试的 source/card 夹具而失败。原因是批量文本替换匹配了两处 `let original`，已只移除误插入块，保留正常备份测试的新数据覆盖。修复后与本轮收尾代码集中验证。后续结构性改动限定函数边界，parse 不能发现作用域错误。归档和 IPA 步骤均跳过。


## BUILD-10 · 白板 SwiftUI 类型推断超时

运行 44681986690（e6a2bd2）：锁文件、核心 30 项通过；白板 body 加入拖动和可访问性操作后，Xcode 报 `unable to type-check this expression in reasonable time`，模拟器测试未执行。将大 body 拆为 controls/canvas/node/menu/sheets，并合并重复连线逻辑；不删除功能、不改持久化。此为该问题第一次修复，待原生复验。归档与 IPA 均跳过。


BUILD-10 接续：运行 44691897830 的核心 30 项通过，白板拆分后不再报该位置错误；编译继续定位到 StudioView 的 InboxView.body 类型推断超时。按相同职责拆分分组/标记行/操作栏，并一次构建来源索引和分组，避免原嵌套表达式重复过滤。没有反复修改同一个未进展的表达式；本次为收集箱首次修复。仍待最终原生测试，不将编译进展标为测试通过。


## PERF-03 · v3.7 整库热路径与主线程工作（2026-11-22）

- 证据：固定 fixture v2 的一万卡片库热读约 502 ms、阅读位置写入约 1004 ms（Linux Release，非 iPad）。同一聚合 JSON 重复解码/校验、ObservableObject 全局广播、主线程封面 I/O 和笔迹/标记整库写入叠加。
- 处理：GRDB 队列内有版本失效的缓存、提交后发布、按集合 Observation、有序后台阅读写入和批量等待、ImageIO actor 与有界预算。完整根因、测量和残余风险在 PERFORMANCE_AUDIT.md / PERFORMANCE_RESULTS.md，避免在这里重复全部表格。
- 回归发现：默认 SQLite busy 策略让两个连接的并发测试报 `database is locked`，改为 5 秒有限等待；测试覆盖 80 个并发更新、回滚、损坏、外部恢复与重开。生产同步入口等待风险仍需真机分析。
- 解除条件：原生完整回归通过后，继续完成低电量、大库、实际触控/能耗/长时内存验收；不能凭 Linux 热读数字宣布整 App 达标。

## BUILD-11 · 原生测试直接调用传递依赖的链接符号（2026-11-22）

- `44969553523` 的 App/扩展编译成功，但 RepositoryCacheTests 直接 import GRDB 后，原生测试链接出现 GRDB.Configuration / DatabaseQueue 等 undefined symbol。SwiftPM 核心测试通过并不代表宿主测试具备相同链接可见性。
- 保留故障覆盖，改用系统 SQLite C API 创建外部连接、注入拒绝 UPDATE 的 trigger 和损坏 payload；未删测试、未向产品引入第二份 GRDB，也未更换原生工作流。原生复验结果见进度。

## DEV-02 · 性能夹具和 Cloud 本地工具（2026-11-22）

- 基准比较发现 snapshot_bytes 有少量差异：Card 的默认时间仍为 Date()。固定 Card 时间和 CardReference UUID，增加 fixture_version 与严格规模/字节数/checksum 比较，基线与候选成对重跑。首次原始数据保留，但不与最终夹具混比。
- 本环境没有 Swift/SQLite 开发头；使用签名校验的 Swift 6.2.4 工具链与本地解包的 Debian SQLite 头文件完成核心测试，没有改系统目录或项目依赖。
- npm 默认缓存目录不可写，改用 `/tmp/ks-performance-tools/npm-cache`，保留 lockfile，执行 `npm ci --ignore-scripts`。不要为沙箱缓存错误升级依赖。


## BUILD-12 / NET-03 · 失败测试摘要与运行策略（2026-11-27）

- `44970616821` 的核心阶段通过，模拟器阶段 exit 65。原流程在 xcodebuild 失败后提前退出，未提取 xcresult 摘要；原错误扫描又输出无关 plist 构建命令，现有 annotations 不足以定位根因，不推断这是业务错误或测试超时。
- 旧日志和 artifact 实际重定向到 `productionresultssa13.blob.core.windows.net`，请求被拒绝。当前配置报告自定义 8 域名，草稿仍有 41 条且含 `*.blob.core.windows.net`，运行实例与草稿基版本不同。仅看到草稿不能宣称已应用；本轮不绕过代理或 TLS，也不改已正确的草稿。
- 新增 always 执行的原生诊断脚本，保留完整 artifact，并将测试计数、失败条目或启动失败尾部写入 GitHub check annotations。这样可以通过正常 GitHub API 阅读关键诊断。配置新增 Release 测试选择，当前 Debug 默认和 IPA 门控保留。
- 旧附件恢复访问仍需在当前聊天的环境设置应用已有域名配置（至少允许实际主机），设置生效后才能重试。网络阻塞不作为测试通过证据。

### BUILD-12 · 追加定位（2026-11-27）

Release 运行 `45928043579` 通过核心阶段，但链接失败，xcresult 明确为 0 个测试；不应把它解释为 UI 流程失败。摘要脚本已证明能从 GitHub annotations 读取结果，但初版仍漏掉多行 Undefined symbols 块，已补充并用保留的首轮失败日志回放验证。新运行日志主机为 `productionresultssa6.blob.core.windows.net`，仍受当前运行配置限制。

另查出原验收夹具只有 DEBUG 编译条件，Release UI 测试需要单独的 `STUDIO_TEST_SUPPORT`；仅测试命令启用，正式归档不启用。Release 模拟器默认同时编译 arm64/x86_64，测试命令现明确 ONLY_ACTIVE_ARCH=YES，按选中 runner 的目标模拟器架构验证；设备归档参数保持原样。


### PERF-03 / BUILD-12 · 本轮交接界限（2026-11-27）

用户选择跳过剩余测试与编译，`45929590952` 已取消。最后代码 `87fb419` 完成封面排队取消、首页投影共用和复习计数，未经运行验证；此前 `b6d4861` 的呈现回调释放、选区防重复与 Release 夹具也未完成原生验证。当前原生链接失败没有被宣称修复。交接中列出下一模型需确认的 continuation/permit、选区意图、数据保存和 UI 行为边界，见根目录 PERFORMANCE_HANDOFF.md。

### 第二轮复验 · 2026-11-27

`7ae4501` 的原生运行 45968880076 已通过 App/扩展编译及链接，执行 85 项测试、83 通过、2 失败、0 跳过；未归档或打包 IPA。BUILD-12 原缺失符号已定位并消除（证据 `verification/native-link-45928043579.json`），但完整验收仍阻塞于 PerformanceAppTests/testAsyncInkSavesPreserveConflictProtectionAndReopen 的 unavailableGroup，以及回收站 UI 查询超时。前者夹具另有 EPUB 空摘录，后续应独立修正夹具与共享容器隔离并保留冲突断言；后者须取 xcresult/界面快照复现，不直接认定为业务回归或放宽超时掩盖。


### 跨模块复验 · 2026-11-28

`84b6ed8` 的 Release 运行 `46080900306`：编译/链接通过，87 项中 86 通过、1 失败、0 跳过；84 项核心/App 全通过，笔迹冲突/重开测试已通过，归档和 IPA 跳过。回收站 UI 本次在首次点击 `storage.actions.可移除资料` 后找不到“移入回收站”（StudyAcceptanceTests.swift:86，约 31 秒结束），不同于上次永久删除阶段超时。日志不足以区分菜单呈现、可访问性查询或刷新竞争；不据此认定为数据删除错误，也不调整超时掩盖。

摘要和 failureText 已保存在 `verification/native-full-pass-46080900306.json`。完整 xcresult artifact `15237244814` 已由 CI 上传，但当前下载至 `productionresultssa7.blob.core.windows.net` 被 Forbidden 阻塞；未取得界面附件。后续需在可访问附件且具备 xcresulttool 的 macOS 环境检查失败快照，复现首次菜单和永久删除两处，再做针对性修复。保留 UI 断言，不把本轮标为完整验收通过。
