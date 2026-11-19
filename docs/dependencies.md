# 依赖评估与决定

检查日期：2026-11-17。实际读取 GitHub README、LICENSE、Package.swift/包清单、相关源码/Tests、Releases 和 Issues；没有按 star 排名。初始 GitHub API/Google 文档 CONNECT 403，环境恢复后已能读取 API 和 YouTube 官方要求。以下区分已接入、推荐候选、尚未做原型验证；未把项目宣传当作真机成功证据。

## EPUB 阅读与定位

| 候选 | 检查版本/commit | 许可证与兼容性 | 能力、证据和决定 |
|---|---|---|---|
| [Readium Swift Toolkit](https://github.com/readium/swift-toolkit) | 稳定 3.11.1，`9a8c094b72245fd27043c9d298005e5c78b32a01`；也检查 main `a60b0ed26ce5f35a5e73d9afdf8debcf8187009b` 的 4.0.0-alpha.3 | BSD-3-Clause；3.11.1 manifest Swift 5.10 / iOS 15 | 有 EPUBNavigator、Selection.locator、Decoration、SwiftUI 指南和样例 App。高亮的保存责任仍在本项目。3.11.1 的依赖包括 SwiftSoup、Fuzi、两套 ZIP、CryptoSwift、DifferenceKit、GCDWebServer、SQLite.swift（部分为适配/可选 target）；不能低估体积。推荐阶段 4 用稳定版且只链接所需产品，不接 DRM/OPDS。未运行 iPad EPUB 定位。 |
| [FolioReaderKit](https://github.com/FolioReader/FolioReaderKit) | `e67424be15ce8c6f5ce2d16872acab5c2953f76b`，2019-08-28；发行页 1.4.0 | BSD-3-Clause；旧 SwiftPM manifest | 依赖旧 Realm、多种 UI/ZIP 库，维护与现代 SwiftUI 路线不合；不采用。 |

Readium [#884](https://github.com/readium/swift-toolkit/issues/884) 报告拖动结束在 decoration 上影响点击，另有 [#927](https://github.com/readium/swift-toolkit/issues/927) ZIP 对齐问题、[#897](https://github.com/readium/swift-toolkit/issues/897) 依赖体积问题。后续必须用真实 EPUB 验证选文、保存、重开定位和分屏；当前仅完成资料/源码评估，未将它加入 App 依赖。

## 网页采集与历史播放器依赖

正式采集采用随主 App 提供的 Safari Web Extension、Native Messaging 与 App Groups。用户提供的「YouTube 随手时间书签」2.0.0 作为迁移行为基准，原脚本使用第三方 Userscripts 的 GM 存储；新方案独立安装。仓库只记录功能对照，原脚本未声明许可证。后续若复用其代码，应先核实授权。[迁移对照](web-capture-roadmap.md)

v0.1.0 的旧原型实际锁定 YouTubePlayerKit 2.0.5（MIT），因此继续保留锁文件及许可证。其嵌入式播放器、Referer 配置与相关测试只适用于该版本。此前对官方 helper 和 YouTubePlayerKit 的比较可在[第一版评估记录](https://github.com/slaythefishordie-droid/Stuido/blob/v0.1.0/docs/dependencies.md)查阅。

## FSRS

| 候选 | 检查版本/commit | 许可证/兼容性 | 决定与验证 |
|---|---|---|---|
| [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) | v6.0.0，`74cb02977ba94dd505aa2a13149238b5f5d48a1b`，2026-11-12 | MIT；Swift tools 5.10，iOS 14+；无外部依赖 | 优先候选，尚未接入用户复习。实际用 Linux Swift 6.2.1 编译并运行上游 **105 个测试/24 suites，全部通过**，包括 FSRS-6/5、序列 oracle、并发、Codable 兼容和 rollback。 |
| [ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs) | main `1edb96b1dd6e3d4ad6068bbb1f795b2636e2a618`；发行页 v6.0.0 | MIT；TypeScript/Node，monorepo 开发工具链 Node 24+ | 作为跨实现对照候选；不把 Node runtime 嵌进原生 App。未运行其测试。 |

swift-fsrs README 明确默认 `FSRSParameters()` 仍为 FSRS-5（19 权重），FSRS-6 需显式 21 权重。阶段 6 必须保存版本与参数，不能因依赖名含 6 就默认为 FSRS-6。[#36](https://github.com/open-spaced-repetition/swift-fsrs/issues/36) 指出按 UTC 日界计算；用户 Asia/Shanghai 的 Today 日期视图和算法日界须单独决定。卡片自选入队，不把库的 Card 作为本项目 Card。

## 图谱布局

| 候选 | 版本/许可证 | 证据与决定 |
|---|---|---|
| SwiftUI Canvas + 手势（官方） | iPadOS 17 SDK；Apple SDK 条款 | 适合可编辑、手动放置的项目关键词图，无额外网络与包。优先做阶段 5 的最小手动布局，节点位置与 Relation 分离。尚未实现或测试。 |
| [Grape](https://github.com/SwiftGraphs/Grape) | `bdfad750d2a973af48159119eaf90530d0e30ea7`，2025-05-19；MIT；Swift 5.9 / iOS 17 | 已读 ForceDirectedGraph/NodeMark/LinkMark 示例和 ForceSimulation/KDTree 测试。只有 docc 插件外部依赖，运行时本地；发行页未列稳定 release。Issues [#75](https://github.com/SwiftGraphs/Grape/issues/75) 拖动重绘、#77 SDK 27 兼容需回归。作为后续力导向布局候选，不现在添加未验证依赖。 |

## JSON Schema

| 候选 | 版本/许可证 | 证据与决定 |
|---|---|---|
| [Ajv](https://github.com/ajv-validator/ajv) | v8.17.1，`9050ba1359fb87cd7c143f3c79513ea7624ea443`；MIT | **已用于跨平台协议工具**，Ajv2020 严格模式 + ajv-formats 3.0.1；npm lockfile 含完整性摘要。24 项协议测试先通过，后续边界测试数量见进度记录。不会打包进 SwiftUI App。 |
| [swift-json-schema](https://github.com/ajevans99/swift-json-schema) | v0.15.0，`a00dde585b7f55b343214cece9afcfeb613e7899`；MIT；Swift 6.1 / iOS 16 | 支持 Draft 2020-12、OrderedJSON 和官方 JSON-Schema-Test-Suite；原生阶段 2 首选验证候选。只需 JSONSchema runtime 产品；builder/macro 会引入 SwiftSyntax，必须审查解析/构建成本。未运行完整上游 suite，尚未接入。 |
| [JSONSchema.swift](https://github.com/kylef/JSONSchema.swift) | main `8c7ec156dde09715d8d2ed83cc8fe6b1ba90648c`，2022-05-21；发行 0.6.0（2021-03-28）；BSD-3-Clause | README 声明支持 2020-12，但明确有新关键字缺口；源码将 unevaluatedItems/unevaluatedProperties 标为 unsupported。不是完全不支持新草案。考虑发行节奏、#228 的新版本请求及后续协议扩展，优先评估另一个原生候选；本轮未运行此库的协议样例。 |

额外开发依赖 [jsonc-parser](https://github.com/microsoft/node-jsonc-parser) 3.3.1（MIT）仅用于严格 JSON 的语法树和重复键检测，明确禁用注释与尾逗号；不接受 JSONC。所有 schema 来自本仓库，不联网加载远程 `$ref`。

## 数据库、迁移、压缩

| 候选 | 版本/许可证 | 决定与证据 |
|---|---|---|
| SwiftData（官方） | iOS 17+；Apple SDK 条款 | 与 SwiftUI 贴近，无额外包；正式导入的复杂事务、备份和可移植测试更适合显式 SQLite 路线，保留为可选方案。未做数据迁移原型，不宣称存在确定缺陷。 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | v7.12.0，`92a554cd0d5e8d67cb18993c6054e73fe42c066c`；MIT；Swift 6.1，iOS 13+，SQLite | 阶段 1 优先候选：DatabaseMigrator、事务、SQLite backup、FTS。标准运行库无额外 Swift 包（平台 SQLite）；docc/SQLCipher 可选。已读清单/README/Tests/Issues；[#1899](https://github.com/groue/GRDB.swift/issues/1899) 取消异步读的 query_only 问题需规避/回归。此轮没有运行其数据库 suite。 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 稳定 0.9.20，commit `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`；MIT | 阶段 1 归档首选候选。Apple Compression / Linux zlib 后端，无云服务。不要直接采用 main 的未来 Swift 6.4/Xcode 27 清单；锁稳定版本后验证 ZIP CRC、文件 hash、路径穿越及原子恢复。[#413](https://github.com/weichsel/ZIPFoundation/issues/413) 归档移除 entry 偏移问题：备份采用新建完整归档，避免原地修改。此轮未跑 ZIP suite。 |
| Apple Compression（官方） | SDK | 提供压缩算法，不是完整 ZIP 文件容器；不能替代归档管理，适合做 ZIPFoundation 后端。 |

PDF 使用官方 PDFKit，本地视频使用 AVKit，SwiftUI 通过薄适配层接入，不做无意义组件搜索。扫描 PDF 无文字层需要明确提示，OCR 不在本轮范围。

## 分发与体积

当前 App 只引入 YouTubePlayerKit；MIT 全文随 App 的 `THIRD_PARTY_NOTICES.md` 资源保留。构建用 XcodeGen 2.44.1 也保留 MIT 声明。Ajv/jsonc-parser/ajv-formats 及传递依赖仅用于开发工具，许可证全文同时保存在 `tools/protocol/THIRD_PARTY_NOTICES.md`。未复制第三方业务源码。

其余推荐候选尚未接入，不因此承担其全部依赖体积；进入对应阶段时必须锁定正式版本、补齐传递依赖许可证和实际验证。所有本地内容管理应可离线；只有 YouTube 网络播放会访问第三方服务。YouTubePlayerKit 当前默认使用 WebKit 持久化站点数据存储，可能保留播放器 cookies/cache；本项目的 Mark JSON 独立留在 App 容器。没有评估或批准无许可证/分发条件不明代码。

## Safari 里程碑 1 实施参考

使用 Apple SafariServices 的原生扩展处理器，扩展页面通过 native messaging 请求原生扩展读写共享目录。Apple 文档允许扩展 UI 页面发出原生消息，iOS 主 App 无法直接向 JavaScript 推送消息，所以本轮在主 App 激活时、Safari 面板打开或点击读取时刷新。[Apple 消息与 App Groups 文档](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)

核对 AltStore 的 ResignAppOperation 和 Bundle 扩展后，使用重签时写入的 ALTAppGroups 解析组标识。这里只使用其声明的数据键，未引入新的第三方运行库。[AltStore 重签实现](https://github.com/altstoreio/AltStore/blob/marketplace/AltStore/Operations/ResignAppOperation.swift) · [Info 字段定义](https://github.com/altstoreio/AltStore/blob/marketplace/Shared/Extensions/Bundle%2BAltStore.swift)

## 0.3 实际接入（2026-11-19）

GRDB 7.12.0 用于显式 SQLite 迁移和事务；JSONSchema 0.15.0 只链接 runtime，不链接 builder/macro。先用严格扫描拒绝重复键，再执行现有 1.0 Schema 和引用语义校验。Readium 3.11.1 只链接 Shared/Streamer/Navigator，不接 DRM/OPDS。为避免同名包身份冲突，归档使用 Readium 同仓库依赖的 ZIPFoundation fork 3.0.1（MIT，异步 Archive API），不再额外引入 weichsel 0.9.20。PDFKit/AVKit/CryptoKit 使用系统 SDK。已读取所选源码 API 和完整 LICENSE，许可证随 App 打包。

SwiftPM 解析生成 ios/Package.resolved，根 Package.resolved 锁核心依赖；以下是本轮实际解析版本（未列为全部上游测试通过）：

| 包 | 版本 | revision |
|---|---|---|
| cryptoswift | 1.10.0 | `f2a627b84c1ff96f21ac2fcb623ab36142dd5512` |
| csqlite | 3.53.4 | `3fecd9f88f50c3a9baf3456e7d4af1b16e71dc23` |
| differencekit | 1.3.0 | `073b9671ce2b9b5b96398611427a1f929927e428` |
| fuzi | 4.0.1 | `173ec944ca6f2e8024ceb7324bcb8a3cc95a0661` |
| gcdwebserver | 4.0.1 | `584db89a4c3c3be27206cce6afde037b2b6e38d8` |
| grdb.swift | 7.12.0 | `92a554cd0d5e8d67cb18993c6054e73fe42c066c` |
| sqlite.swift | 0.17.0 | `4114679379eeb4538638f49ec14e1854dd9cf73c` |
| swift-collections | 1.7.6 | `88754449ab766a739610b660e117762115fabc9c` |
| swift-json-schema | 0.15.0 | `a00dde585b7f55b343214cece9afcfeb613e7899` |
| swift-syntax | 604.0.0 | `050f1a346fbbac0ca2cfb15a95274f7bd1cf0ccf` |
| swift-toolkit | 3.11.1 | `9a8c094b72245fd27043c9d298005e5c78b32a01` |
| swiftsoup | 2.14.4 | `8397a860c6955924b584c50c5265c6aac0970015` |
| youtubeplayerkit | 2.0.5 | `1ae827573024ab13dd6adea33b25d3eef6ff667c` |
| zip | 2.1.2 | `67fa55813b9e7b3b9acee9c0ae501def28746d76` |
| zipfoundation | 3.0.1 | `adb49c8bfe060cc187370b12fa081012a6440b86` |
