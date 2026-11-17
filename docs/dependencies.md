# 依赖评估与决定

检查日期：2026-11-17。实际读取 GitHub README、LICENSE、Package.swift/包清单、相关源码/Tests、Releases 和 Issues；没有按 star 排名。初始 GitHub API/Google 文档 CONNECT 403，环境恢复后已能读取 API 和 YouTube 官方要求。以下区分已接入、推荐候选、尚未做原型验证；未把项目宣传当作真机成功证据。

## EPUB 阅读与定位

| 候选 | 检查版本/commit | 许可证与兼容性 | 能力、证据和决定 |
|---|---|---|---|
| [Readium Swift Toolkit](https://github.com/readium/swift-toolkit) | 稳定 3.11.1，`9a8c094b72245fd27043c9d298005e5c78b32a01`；也检查 main `a60b0ed26ce5f35a5e73d9afdf8debcf8187009b` 的 4.0.0-alpha.3 | BSD-3-Clause；3.11.1 manifest Swift 5.10 / iOS 15 | 有 EPUBNavigator、Selection.locator、Decoration、SwiftUI 指南和样例 App。高亮的保存责任仍在本项目。3.11.1 的依赖包括 SwiftSoup、Fuzi、两套 ZIP、CryptoSwift、DifferenceKit、GCDWebServer、SQLite.swift（部分为适配/可选 target）；不能低估体积。推荐阶段 4 用稳定版且只链接所需产品，不接 DRM/OPDS。未运行 iPad EPUB 定位。 |
| [FolioReaderKit](https://github.com/FolioReader/FolioReaderKit) | `e67424be15ce8c6f5ce2d16872acab5c2953f76b`，2019-08-28；发行页 1.4.0 | BSD-3-Clause；旧 SwiftPM manifest | 依赖旧 Realm、多种 UI/ZIP 库，维护与现代 SwiftUI 路线不合；不采用。 |

Readium [#884](https://github.com/readium/swift-toolkit/issues/884) 报告拖动结束在 decoration 上影响点击，另有 [#927](https://github.com/readium/swift-toolkit/issues/927) ZIP 对齐问题、[#897](https://github.com/readium/swift-toolkit/issues/897) 依赖体积问题。后续必须用真实 EPUB 验证选文、保存、重开定位和分屏；当前仅完成资料/源码评估，未将它加入 App 依赖。

## YouTube 与 SwiftUI

| 候选 | 检查版本/commit | 许可证/兼容性 | 决定与验证 |
|---|---|---|---|
| [YouTubePlayerKit](https://github.com/SvenTiigi/YouTubePlayerKit) | 2.0.5，`1ae827573024ab13dd6adea33b25d3eef6ff667c`，2025-11-30 | MIT；Swift tools 6.0，iOS 15+；无第三方传递依赖 | **已用 SPM exact 接入**。源码核实 WKWebView inline、getCurrentTime、seekTo、statePublisher、autoplayBlockedPublisher、错误 101/150/153 和 Bundle ID origin。用 VideoClock 隔离，包不会定义我们的 Card/Mark。原生编译交给 CI，真实播放仍待 iPad。 |
| [官方 youtube-ios-player-helper](https://github.com/youtube/youtube-ios-player-helper) | 1.0.4，`f57129cd4380ec0a74dd3a59da3270a1d653d59b`，2021-12-10 | Apache-2.0；ObjC/WKWebView、iOS 10+ | 官方但发行较旧，SwiftUI/async 适配成本更高，未选。Issues 有登录要求和停止播放泄漏报告；不能因“官方”就假定全部情形可靠。 |

已读取 [IFrame API](https://developers.google.com/youtube/iframe_api_reference) 和 [Required Minimum Functionality](https://developers.google.com/youtube/terms/required-minimum-functionality)：必须提供 Referer；本地 HTML 可通过 `loadHTMLString:baseURL:` 设置；替代安装渠道使用系统安装的真实 app ID。原型显式把运行时 Bundle ID 生成的 HTTPS origin 传入包装层，避免 AltStore 重签后硬编码失效。`widget_referrer` 不是 HTTP Referer 的替代品；需真机确认请求身份没有被 WebKit 抑制。

已知 [YouTubePlayerKit #165](https://github.com/SvenTiigi/YouTubePlayerKit/issues/165)：cued 状态可能从头播放，故回跳验收必须覆盖首次播放、暂停和重新进入，不能只测 playing。原型关闭自动播放、系统全屏按钮和 PiP，保留 App 内放大及原生 Mark，不提取媒体 URL。核心 8 项测试验证了失败/0 秒/落盘/竞态，但不验证 YouTube 服务本身。

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
| [JSONSchema.swift](https://github.com/kylef/JSONSchema.swift) | main `8c7ec156dde09715d8d2ed83cc8fe6b1ba90648c`，2022-05-21；发行 0.6.0；BSD-3-Clause | 老版本草案支持与当前协议不匹配，发行请求 issue #228；不采用。 |

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

当前 App 只引入 YouTubePlayerKit；MIT 全文随 App 的 `THIRD_PARTY_NOTICES.md` 资源保留。构建用 XcodeGen 2.44.1 也保留 MIT 声明。Ajv/jsonc-parser/ajv-formats 及传递依赖仅用于开发工具，LICENSE 保留在 npm 包中并在 notice 文档列出。未复制第三方业务源码。

其余推荐候选尚未接入，不因此承担其全部依赖体积；进入对应阶段时必须锁定正式版本、补齐传递依赖许可证和实际验证。所有本地内容管理应可离线；只有 YouTube 网络播放会访问第三方服务。没有评估或批准无许可证/分发条件不明代码。
