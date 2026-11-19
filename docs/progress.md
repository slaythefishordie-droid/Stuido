# 开发日志与验证记录

本文件按时间记录开发工作与验证结果；重复问题的查找入口是[开发与构建问题日志](engineering-issues.md)。历史条目中的“当前”“下一步”只反映该条目的时间点，接续开发以 [PROJECT_STATUS.md](../PROJECT_STATUS.md)和现行路线图为准。

## 0.3 功能优先开发 · 2026-11-19（北京时间）

- 用户确认里程碑 1 IPA 真机 Safari／App 编号自动传输和对应成功；记录为用户报告通过，不追补未提供的设备型号、包摘要或安装细节。
- 用户确认本轮覆盖**产品阶段 1–4 与 Safari 路线图 1–4**，新增功能优先规范，见 AGENTS.md 与 release-0.3-plan.md。主开发分支保持 feature/safari-extension；默认分支修改请求被 GitHub 管理 API 403 拒绝，需有仓库管理权限的账号修改。
- 已实现开发代码：GRDB SQLite 事务存储、旧原型迁移、四类卡片编辑和全局 Quick Capture、My Inbox 整理、AI Inbox JSON 文件／粘贴／资料匹配／选择确认导入、项目资料关联、Data Manager 回收站与引用限制、版本化 ZIP 备份／摘要校验／恢复前快照／事务恢复。原生 JSONSchema 直接使用仓库 1.0 协议，重复字段和语义引用另行严格校验。
- PDFKit、Readium EPUB、AVKit 本地视频接入导入、阅读／播放、选文或时间 Mark、回到出处与保存位置。EPUB 保存 Readium locator，PDF 高亮保存在 Mark，不修改原始文件。扫描 PDF 不声称提供 OCR，DRM 不在范围。
- Safari 新增精听 ±1/2/3 秒、A–B 循环、历史检索／当前视频排序／分批显示、备注／复制链接／删除、旧书签 JSON 导入导出、个性化与逐站授权设置、文章选文及页面 audio 定位适配器。原生注解同步保留 ID，永久清理的接收 ID 保留 tombstone 防止被重复交接复活。
- 实际验证：本地 Swift 6.2.1 首轮核心 18/18 通过；后续新增共享注解及通用采集后，LibraryTests **7/7** 通过。Node.js 协议与 Safari **43/43** 通过。SwiftUI 语法解析通过，但不等于原生类型检查。备份路径穿越、恢复和删除引用测试已加入 iOS 测试，待本轮 macOS 稳定化执行。
- 所选依赖版本及完整许可证已锁定。Readium 与归档共用 ReadiumZIPFoundation 3.0.1，避免同名包冲突。工作区新建 Swift 工具链和 SQLite 头文件验证环境；没有修改系统软件目录。
- 尚待验证：本轮原生编译／模拟器／IPA、真实 PDF/EPUB/视频资料、Safari 的实际 DOM／授权／后台恢复、真实旧脚本备份。仓库只有旧脚本摘要和行为对照，没有原脚本或真实备份样例；兼容解析器目前用合成 v1 样例验证，不能声称已与用户旧备份完全互通。

## Safari Mark 到 My Inbox 开发 · 2026-11-19

- 从远端 `feature/safari-extension` 的 `438dc23` 接续。复核 #14 全部成功；免费重签、Safari 识别和共享权限仍待真机验证。依据产品需求“不因单个功能受阻而停止全部开发”，推进里程碑 2 的可独立实现部分，不宣称里程碑 1 真机验收完成。
- 增加 YouTube 普通 watch 页 QuickMark、0–3 秒回溯（默认 2 秒）、本地待发记录、Native Messaging 保存与匹配 ID 回执。失败/超时重试同一 ID，后台重启重送尚未确认的记录；不暂停视频、不自动建卡或加入复习。
- 主 App 新增 My Inbox，启动与回到前台时重新读取同一共享目录；保留扩展诊断页。每条不可变 Mark 使用独立文件、跨进程文件锁和原子替换，重复送达幂等，冲突或损坏报错并保留文件。保留原始秒数、回溯值、最终定位、标题、videoID、UUID 和创建时间。旧 prototype-v1.json 不改动。
- 本地 Node.js 24.22.1：协议与 Safari 测试 **37/37 通过**。新增 5 项 Swift 存储测试覆盖重开、重复/冲突、损坏保留、非法字段、写入失败、并发交接，等待 macOS CI 执行；当前 Linux 没有 Swift，执行核心测试明确报 `swift: command not found`。Shell 语法和 diff 空白检查通过。
- 待验证：本次原生编译/模拟器/IPA；实际 Safari 页面注入、广告/直播识别和同标签页切换；免费重签共享、关闭主 App 后保存、重启恢复。完整精听、历史编辑和旧备份导入仍属里程碑 3，未实现。

## 文档归档与环境白名单核验 · 2026-11-19

- **目标与范围：**汇总本轮代码审查、Safari 扩展打包、runner 调度和 IPA 交付的经验，便于新模型接续。代码与成功构建基线仍为 `ea8ca26` / Native iPadOS #14，本轮未修改业务代码或构建脚本。
- **文档交付：**新建 `engineering-issues.md`，为面板异常恢复、共享组配置、导入排序、扩展资源层级、runner 排队、模拟器无输出、codesign 回归、下载网络和真机验证分别记录证据、处理与边界。更新 AGENTS.md 的必读入口、项目状态和 README 索引。
- **环境结果：**读取当前配置草稿与运行实例，逐项对照约定的 41 条自定义规则；草稿 revision 5 为 41/41，缺失 0；运行实例为 8/41，缺失 33，`observations_current=true`、`policy_state=enforced`。`package_managers` 预设保留且另计。本轮没有再次改写草稿、发布环境或声称完成 41 个站点的连通测试。[核验记录](verification/network-allowlist-audit-2026-11-19.json)
- **验证范围：**检查本轮文档的相对链接、JSON 结构、白名单集合差异和 Git 空白错误。文档更新不重复运行已通过的 Node / 原生测试，不重新生成 IPA。
- **未决与下一步：**应用已保存的网络配置并连接到相应版本，再验证真实附件下载；在 iPad 上完成免费重签、Safari 识别和双向共享验收。通过后按计划推进 Mark → My Inbox。保留当前数据格式、四类卡片、双 Inbox、ChatGPT JSON 导入和用户自选复习要求。

## IPA 构建恢复 · 2026-11-19

修复后的 [Native iPadOS #14](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44432216488) 已全部通过，代码提交为 `ea8ca267db640c6d9996367ea6aebcb72f96aa3c`。核心 8/8、iPad 模拟器 14/14 通过，设备归档、两端签名与 App Groups 声明检查、IPA ZIP 校验及上传成功。[机器验证记录](verification/native-run-44432216488.json)

[下载 Safari 共享验证版 IPA 产物](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44432216488/artifacts/14488745224)：`KnowledgeStudio-resignable-ipa-14`，保留至 2026-11-26。解压外层 ZIP 后，用 AltStore Classic 重签其中的 `KnowledgeStudio-resignable.ipa`。这是里程碑 1 诊断包，完整 QuickMark / My Inbox 尚未实现；免费重签、Safari 识别和双向共享仍待真机验证。

本次模拟器步骤总耗时 12 分 09 秒；完整日志显示编译后、测试启动前存在 8 分 42 秒的日志空档，随后测试套件约 1.738 秒完成。没有证据把空档认定为业务测试死锁，日志也不足以进一步确定模拟器启动慢的内部原因。未签名模拟器出现 App Group `NOT_CODESIGNED`，不能用临时目录的单元测试代替真实跨进程共享验收。

完整日志 ZIP 已取回并通过 CRC；IPA 和 xcresult 附件的下载被当前云端代理拒绝，重定向主机为 `productionresultssa31.blob.core.windows.net`。当前只完成了 CI 内的 IPA 校验，未声称已在本地重新验包。用户浏览器可从上述 GitHub 入口下载。

已经区分两类故障并在 `feature/safari-extension` 修复构建配置：

- 运行 `44292208343` 的首次尝试没有取得 ARM64 runner，GitHub 注解为 `The job was not acquired by Runner of type hosted even after multiple attempts`，并提示 ARM64 容量不足。没有任何测试步骤执行。重试也未取得机器，后被同分支的新运行取消。
- Intel 运行 `44309054436` 正常取得 runner；Swift 核心 8/8、iPad 模拟器 14/14 通过，设备归档成功。模拟器步骤总耗时约 6 分 52 秒。失败发生在打包阶段：将 `codesign --entitlements :-` 改为 `--entitlements -` 后，输出无法由 `plistlib` 解析，产生 `InvalidFileException`。这不是调度或网络失败。[日志与测试证据](verification/native-run-44309054436.json)

修复提交 `ea8ca267db640c6d9996367ea6aebcb72f96aa3c` 恢复 XML-only 导出方式，保留签名、设备架构和 App Groups 声明检查；冒号弃用提示暂作为非致命警告保留。工作流默认使用标准 `macos-15-intel`，手动仍可选择 `macos-26`，两者固定 Xcode 26.2 / iOS 26.2 和同样的测试门槛。没有使用付费 larger runner，也没有修改业务功能。

已取回旧失败与成功运行的完整日志，并更新网络诊断和手动排障说明。日志与附件的可访问性要分别验证；云实例仍报告原来的 8 条名单，草稿 41 条不等于运行实例已应用。[网络记录](network.md) · [安装与排障](build-and-install.md)

## 代码审查与维护整理 · 2026-11-18

代码提交 `831c391caacfef61221448b90c9b53d3e83ab8cc`，位于 `feature/safari-extension`。采用局部修复，保留现有持久化格式、导入协议和依赖版本；当前小规模共享诊断无需额外引入数据库或并发框架。

- Safari 面板的 Native Messaging 增加 10 秒超时和请求重入保护，异常或无效响应后恢复按钮。迟到响应不能覆盖后续读取结果。超时不会取消原生写入，因此提示先读取确认，再决定是否重试。
- 共享组配置采用明确的错误类型。AltStore 元数据存在却格式错误、为空或包含多个组时报告错误，不再默默使用旧组。读取直接处理文件缺失，减少一次文件系统查询；损坏数据、来源不符及其他读取错误继续上报并保留原文件。
- 导入去重排序为每个元素只生成一次规范化排序键，避免每次比较反复序列化。固定已有样例的指纹作为回归基线，确认结果兼容。10,000 条合成关系、5 次运行的本地中位数为优化前约 46 ms、优化后约 23 ms；这是局部微基准，不代表整个 App 的性能提升。

本地 Node 测试 31/31 通过，包含 27 项协议测试和 4 项 Safari 面板恢复测试；[GitHub 协议及面板 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44292215642) 同样通过。修改的 Swift 文件通过语法解析；新增两项原生测试，覆盖组配置和读取异常，模拟器通过门槛由至少 12 项提高至至少 14 项。

[首次原生 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44292208343) 后续确认因托管 runner 无法分配而未执行；上述 Swift 改动已在 Intel 运行 `44309054436` 通过原生编译与 14 项模拟器测试，但该运行的打包阶段失败。修复和后续结果见本文件顶部。免费重签、Safari 识别和实际 App Groups 共享仍须在 iPad 上分别验证。本轮未推进 QuickMark / My Inbox 功能或修改 main 与 v0.1.0。

## Safari 里程碑 1 · 2026-11-18

`feature/safari-extension` 的提交 `547eaf4020001c0a4462263a36a03dfe2a277905` 已通过原生 CI。核心测试、iPad 模拟器测试、设备归档和含 Safari 扩展的 IPA 校验均成功。模拟器门槛提升为至少 12 个测试且失败数为 0，包含新增的独立写入重开和损坏记录保留测试。Linux 核心测试另行复跑 8 项通过。[原生运行](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44245690553) · [验证元数据](verification/safari-m1-run-44245690553.json)

主 App 入口为 Safari 共享验证页，Safari 扩展弹出面板通过 Native Messaging 写入或读取两端诊断编号。修正了扩展资源的打包层级，manifest 位于包根目录。归档以 ad-hoc 签名保留 App Groups 声明，产物名为 KnowledgeStudio-resignable-ipa-11。

真机免费重签、Safari 识别和双向共享仍待执行。当前运行环境缺少 GitHub 日志与产物的新存储域名，新增 sa30、sa18 的配置草稿已保存，待发布应用。API 可核实构建步骤成功，完整产物尚未本地复验。[安装和双向验证步骤](build-and-install.md)

## 第一版交接与网页采集架构更新

`v0.1.0` 的提交为 `7df6ef182b73131878a07e568cf6799fc543cf0c`。本地 Swift 核心测试 8 项通过，导入协议测试 26 项通过。该提交的 GitHub 原生构建、模拟器测试、设备归档及 IPA 校验成功，协议 CI 成功。原始 CI 产物包括 `KnowledgeStudio-build-evidence-6`、`KnowledgeStudio-unsigned-ipa-6` 和 `protocol-evidence-3`。[原生 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227526926) · [协议 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227553771)

上述运行只覆盖旧主 App。现行开发从含 Safari 扩展的构建和免费签名可行性开始。新计划与真机证据分别维护；以下日期条目保留为旧原型历史记录，其中的“下一步”和待办仅反映当时状态。[当前路线图](web-capture-roadmap.md) · [验证记录](device-validation.md)

## 2026-11-18 · 阶段 0 草稿复核

- 当前草稿基于 `7322edd`。另一个提交 `a37dce8` 的原生 CI 已通过 iPad 模拟器测试、设备归档、IPA 校验并上传 `KnowledgeStudio-unsigned-ipa-4`。该产物早于本轮代码修改。[GitHub Actions 运行](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44203023658)
- 根据 YouTubePlayerKit 2.0.5 源码修正了 SwiftUI 播放器的视图标识，切换视频与重连都会替换显示用的 WKWebView。打开新视频只提交一次，恢复或重连当前视频可复用已保存的选择。视频 ID 改为全文匹配，拒绝尾随换行。
- 修正导入校验器返回的字段出处错误路径，可定位到具体无效引用。新增缺少必填 `source_refs` 的样例。
- 本轮验证使用 Linux Swift 6.2.1，核心 8 项通过，覆盖重启恢复、重复选择的文件修改时间、错误链接、零秒及过期会话。协议 26 项通过，四类联合样例经 CLI 校验为 4 张候选卡、0 条警告。
- 本轮 SwiftUI 文件通过语法解析，仍需 macOS 编译及 iPad 安装后用实际学习视频检验播放、切换、Mark 和回跳。下一阶段为原型 Source 与 Mark 的事务迁移。

## 2026-11-17 · 阶段 0

起点：仓库 `a4c48fc26db834045e8bd9a681ff7aa95de96255` 只有 README，无工程、AGENTS.md 或现有依赖。选择 SwiftUI，最低 iPadOS 17，Swift 6 语言模式；当前用户设备 iPadOS 26.2。用户只有 Windows 和 iPad，使用免费 Apple 账户及 AltStore Classic。

完成内容：

- 保存原始需求、独立状态/对象模型、版本和事务约定、依赖评估、ChatGPT 提示词。
- Draft 2020-12 Schema 与共享校验入口；四类内容、字段 provenance、Source/Relation 引用、具体错误、重复批次和内容预览；未实现正式导入事务或 AI Inbox UI。
- SwiftUI YouTube 最小工程，固定 SPM 版本；原生 Mark/时间回跳/最近视频/原子原型存储/失败提示/超时/会话隔离。未扩展 PDF、EPUB、图谱等复杂界面。
- 标准 macOS 26 ARM64 + Xcode 26.2 Actions，核心测试、iPad 模拟器测试、真实 iphoneos archive、未签名 IPA 结构校验、日志/xcresult/产物上传与独立结果记录。
- 网络诊断：四个目标域名 HTTPS 200/TLS 校验通过；平台提供的当前白名单已含 API 和 Google 开发文档。没有关闭验证或改写代理。

## 阶段 0 当时的验证证据（历史）

| 检查 | 结果 | 范围 |
|---|---|---|
| Swift 核心 | 8/8 通过 | Linux Swift 6.2.1，真实文件读写和异步竞态；非 iOS 运行验证 |
| 导入协议 | 25/25 通过 | Node.js 24.22.1，Schema/语义/重复/错误/边界；没有写正式数据库 |
| swift-fsrs v6.0.0 上游 | 105/105 通过，24 suites | Linux Swift Testing；App 尚未接入复习 |
| 工作流静态检查 | actionlint 1.7.12 通过 | 不等于 GitHub Runner 已执行 |
| Shell 语法 | bash -n 通过 | 不等于 macOS 打包成功 |
| GitHub 协议 CI | 成功 | [run 44077240571](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44077240571)，commit `e9b42987189de313ec85f026c6b6b6acd4bf8b9c`，日志 Artifact 已上传 |
| 原生 CI 的 SPM / 核心测试 | 成功 | [run 44203023658](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44203023658)，commit `a37dce8cf1ca47e8a70befa36808eb8f9f82632e`；标准 macos-26 ARM64 / Xcode 26.2 |
| 原生 App 编译与模拟器测试 | 成功 | 同次 CI 的 simulator 步骤通过，强制断言至少 10 个测试、0 失败；工程包含 8 个核心和 2 个 App 测试。完整 xcresult 尚未下载到本云环境 |
| device archive | 成功 | generic/platform=iOS Release archive 通过；后续确认 arm64 / iPhoneOS / iPad 设备族及未签名状态 |
| unsigned IPA 打包校验 | **成功，已上传候选 IPA** | `KnowledgeStudio-unsigned-ipa-4`；Payload 结构、ZIP CRC 和 SHA-256 生成步骤通过；不等于 AltStore 安装成功 |
| 日志与测试证据上传 | 成功 | `KnowledgeStudio-build-evidence-4`；本云环境下载仍被网络策略拒绝，当前记录依据 Actions API 的逐步结果与产物元数据 |
| AltStore 重签安装 | 未执行 | 必须用用户实际设备验证 |
| iPad 真实播放/Mark/回跳/恢复 | 未执行 | 见 device-validation.md |

工具链来源：官方 Swift 6.2.1 Ubuntu 24.04 tarball，在 Debian 13 可运行；GPG 验证通过，签名指纹 `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`，密钥从 swiftlang 官方仓库通过 TLS 获取。缓存通过脚本指定到可写 `.build`，未改 HOME 或系统 CA。

## 阶段 0 当时的限制与下步（历史）

1. IPA 打包修复已通过实际 CI：旧脚本把输入文件放在 `lipo -verify_arch arm64` 之后；Apple cctools 参数解析源码确认这会把文件路径当作架构名称。已改为 `lipo <binary> -verify_arch arm64`，保留全部架构/平台/签名/ZIP 检查，并为失败增加 GitHub 原生错误注解。完整旧日志仍受网络限制，因此不追认这是旧运行的唯一失败原因。
2. 当前生效白名单仍是原来的三个域名，草稿另有 `productionresultssa4.blob.core.windows.net`、`productionresultssa5.blob.core.windows.net` 和 `results-receiver.actions.githubusercontent.com`，**草稿未应用到运行实例**。新的 IPA 实际下载跳转到了 `productionresultssa5`，再次返回 Forbidden。待环境设置保存并发布后重试；用户 Windows 浏览器不受本云环境白名单影响。
3. 阶段 0 只有 YouTube 纵向原型；没有虚构 Today/Library/Dictionary 等已实现页面。严格导入工具可执行，但原生 JSONSchema 适配层、Source 匹配 UI 与数据库事务仍属阶段 2。
4. CI 已通过，请用户下载未签名 IPA 在 AltStore Classic 重签，并按真机清单记录实际结果；CI 不需要 Apple 密码、证书或签名密钥。当前只能确认未签名设备 App 的构建与打包，不宣称已验证 AltStore / iPadOS 26.2 安装兼容性。
5. 原生构建流程确认后进入阶段 1：数据库迁移、原型 Mark 迁入、回收站、备份恢复与失败回滚。继续保留所有稳定 ID 与原始秒数，不清空原型文件。
6. 待产品体验后决定复习正反面；提案在 data-model.md，可调整。FSRS 日界与用户时区差异在依赖评估中记录。

仓库实际为 Public，用户已明确授权推送和运行；未改变可见性。当前工作流不需要 Actions 管理接口的写权限，管理接口 403 不应被误判成网络不可达。

首次 native run 44075633839 在 `macos-15` 队列中等待，后由并发策略取消。发现该标签目前对应 ARM64、先前核对的镜像清单对应 Intel，因此固定为官方标准 `macos-15-intel` 后实际运行成功进入编译。没有使用付费 larger runner；不把标签差异直接断言为排队根因。

打包修复依据：[Apple cctools lipo.c](https://github.com/apple-oss-distributions/cctools/blob/e0d56624eca2a76c2ace4c21850df9e666de4ca5/misc/lipo.c#L444) 的 `verify_arch` 分支消费后续所有参数；[lipo 手册](https://github.com/apple-oss-distributions/cctools/blob/e0d56624eca2a76c2ace4c21850df9e666de4ca5/man/lipo.1) 明确 `lipo input_file command [option ...]`。

## 2026-11-18 · 构建调度与网络复查

修复提交 `7322edda9371f017acd5c76d0187e7937ed67783` 对应 [run 44081549150](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44081549150) 未执行任何步骤。GitHub 注解明确为 `The job was not acquired by Runner of type hosted even after multiple attempts`，是托管 Runner 调度失败，不能记为新代码编译失败或测试失败。改用经官方 ARM64 镜像清单核实的标准 `macos-26`，继续固定 Xcode 26.2 / iOS 26.2 模拟器；新 run `44203023658` 已全部成功，详见 [机器记录](verification/native-run-44203023658.json)。没有切换到付费 larger runner。

云实例已恢复为 running。当前生效白名单仍为原来三项；本次绑定的新草稿 revision 1 没有自定义域名，旧草稿的两项追加没有出现在新草稿中。已经保留原有三项、重新加入两项旧下载域名，再根据本次实际跳转追加 `productionresultssa5.blob.core.windows.net`；当前草稿 revision 3 共六项。保存不等于发布，完整日志和 IPA 下载仍受限。见 [网络记录](verification/network-2026-11-18.json)。

最新运行的 IPA Artifact 大小为 331,594 字节，证据 Artifact 为 152,314 字节；这是外层 Artifact ZIP 大小，API 返回的 digest 也仅属于外层 ZIP。IPA 本身的 SHA-256 在产物内的 `.ipa.sha256` 文件中，本云环境尚未取到文件，未伪造其摘要。两个 Artifact 均保留 7 天，下载入口见 [构建与安装](build-and-install.md)。

运行另有两个非失败注解：固定的 checkout / upload-artifact 版本声明 Node 20，GitHub 已用 Node 24 执行且步骤成功；标准 macOS ARM64 容量紧张可能导致排队。它们没有导致本次构建失败，不为消除提示重复触发 macOS 构建。
