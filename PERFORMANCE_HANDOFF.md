# 性能重构交接：下一模型必读

> 2026-11-27 第二轮已按新指示恢复验证，沿用本分支且不编译 IPA。最新状态以 [开发进度](docs/progress.md) 顶部为准；下列暂停决定属于上一轮。

## 上一轮结束方式

2026-11-27 用户明确调整任务：**先跳过测试和编译，完成代码优化并编写日志，随后换对话由其他模型接手。** 已停止新增测试/编译，取消当时仍在运行的 CI。最后一批代码只做人工静态审查与 diff 检查，没有运行 Swift parse、单元测试、基准或 Xcode。

这是**代码阶段交接，尚未通过原生验证的候选分支**。不能称为稳定版，不能把历史核心测试当作最终 App 验收，也不能自动发布。接手后首先阅读下列文件、核对工作区和用户新指示；如用户仍要求暂缓验证，不自行恢复 CI。

## 阅读顺序

1. [AGENTS.md](AGENTS.md)：产品和数据保护规则。
2. [docs/progress.md](docs/progress.md) 顶部：权威当前状态、历史运行与用户暂停决定。
3. [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md)：兼容性清单、各模块热点和保留理由。
4. [PERFORMANCE_RESULTS.md](PERFORMANCE_RESULTS.md)：具体实现、合成基准、收益边界及仍存在的问题。
5. [docs/engineering-issues.md](docs/engineering-issues.md) 的 PERF-03、BUILD-11、BUILD-12 / NET-03：失败证据和网络问题；[工作流](docs/workflow.md) 的性能验证章节。
6. [docs/performance/IPAD_TEST_GUIDE.md](docs/performance/IPAD_TEST_GUIDE.md)：真机低电量、大库、阅读、数据与长期内存验收。
7. 产品需求仍见 [产品计划](docs/product-spec.md)、[Safari 路线图](docs/web-capture-roadmap.md) 和 [v3.7 功能矩阵](docs/quality/v3.7.0.md)，性能重构没有取代产品需求。

## Git 定位与恢复

- 工作分支：`performance/v3.7-low-power`，所有性能代码都在此分支。
- 最后业务代码提交：`87fb4194e9ac2b8768a724a85ffcfaa9d01c001a`。随后可有交接文档提交；不要把文档 HEAD 误当成另一次构建通过。
- 性能重构基线：`1888dcb570093aba680f70baa403dcbc5fcd7f99`，来自 `release/v3.7.0`。
- 恢复标签：`baseline/v3.7-before-performance-20261121`，已推送，不移动它。
- 正式 v3.7.0 标签：`78e5f3f82e376a9287a2ea1be1f61b27ab7a106a`；基线相对发行标签只有文档整理。
- 未修改 main/发行分支、未发布新 Release/IPA、未重置或强推历史。

需要查看稳定代码时另建分支/工作树：

```sh
git switch -c recovery/v3.7 baseline/v3.7-before-performance-20261121
```

先保存现有工作，不用 reset --hard。代码恢复不是数据回滚；保留真实备份和原安装身份，不卸载真实用户 App。

## 改动阅读重点

| 文件/模块 | 需要理解的约束 |
|---|---|
| `LibraryRepository.swift` | 缓存只在 GRDB 串行连接访问；`data_version` 识别外部提交；IMMEDIATE 写锁内取旧值；实际变更完整校验；COMMIT 返回后才发布缓存；5 秒 busy 等待。不要把写后的版本再查一次套到旧快照上 |
| `StudioModel.swift` | Observation 按集合发布，`state` 仍是完整兼容快照；阅读位置合并，Mark/笔迹不丢弃；旧位置不能覆盖新定位；异步事务 revision 防陈旧发布；阅读保存注册、在途计数、后台执行断言、导出/恢复等待 |
| `SourceReaders.swift` / `PDFStudyInk.swift` / `EPUBInkNote.swift` | PDF 后台构建后主线程独占；标注差分；异步保存成功才清原选区；墨迹保留 expected 冲突检查与在途新笔画；离开页面断开呈现回调；已经接受的 EPUB 保存回调要独立留到完成 |
| `PendingSelectionSaves.swift` | 同一选区在一次保存完成前抑制重复点击，另一个新选区仍可提交；失败也必须释放门控。视频重复 QuickMark 不应用此规则 |
| `StudyCovers.swift` / `CoverDiskWorker.swift` | 原始、生成、自选模式不变；I/O/ImageIO 在 actor，ImageRenderer 在主线程；有界内存缓存、共享请求消费者计数、取消、代际失效；磁盘清理不触及原文或用户原图 |
| `PerformancePolicy.swift` / `PerformanceBudget.swift` | 官方通知统一改变非关键并发和缓存预算，不改变刷新率或核心功能；不要在策略初始化时反向读取尚未初始化完成的 shared 单例 |
| `LoungeModel.swift` | 30 秒检查点与实际截止时间驱动，不延迟用户倒计时；空纸条没有过期忙循环，失败重试有间隔 |
| `StudyHomeView.swift` / `TodayView.swift` | 最后收尾：同一 body 共用投影，计数用相同到期条件单次遍历；队列排序和用户自选规则保持原样 |

没有迁移数据库、改 Schema、升级依赖、改 App Group/Bundle ID 或扩展消息格式。四类卡片、双 Inbox、JSON 导入、FSRS、资料/墨迹/封面、来源锚点与复习历史继续受现有校验保护。

## 下一模型优先排查：不是全部验证已通过

**第一阻塞是原生链接，不是已证实的 UI 测试失败。**

- `44969553523`：首轮测试直接 import GRDB 导致 undefined symbols，改成系统 SQLite 故障注入；Linux 核心通过。
- `44970616821`：后续 Debug 运行失败，完整日志当前无法下载；不要猜测具体断言或超时。
- `45928043579`（`d660572`）：Release 核心通过，原生 **linker command failed**，xcresult 明确 **0 tests**。当前精确缺失符号尚未取到。不能宣称改用 SQLite 已彻底解除所有链接问题。
- `45929590952`（`b6d4861`）：按用户要求取消，取消不是通过或代码失败。

获得用户恢复验证的指示后：

1. 先取得完整 `Undefined symbols` 块，确定失败的是 App 还是测试 bundle、哪个架构、哪些对象引用符号。再调整相应 target 的直接依赖或代码，不能猜测添加库、删除断言、跳过测试。
2. 新版 `scripts/report-native-tests.py` 会把链接符号块、测试计数/失败写入 GitHub annotations，并保留 xcresult/log artifact。脚本已用本地保留的首次失败日志验证能提取 GRDB 符号；新候选尚未完成一次端到端运行。
3. 原生测试命令已支持 `configuration=Release`、`ENABLE_TESTABILITY=YES`、`ONLY_ACTIVE_ARCH=YES`，并仅为测试启用 `STUDIO_TEST_SUPPORT` 以保留临时目录夹具。正式 archive 不带测试编译条件；保留原 IPA 手动门控。
4. 完整原生检查通过后，确认原有 3 条 UI 流程和全部新增测试确实执行；不要只看 exit code 或旧的 64 项 v3.7 结果。
5. 最后按真机指南验证 Low Power Mode 和大库；没有 Instruments/设备就继续明确标记未测。

## 最后一批未验证代码：必须关注

`87fb419` 没有运行测试/编译，需验证：

- 原始封面排队等待时取消，continuation 恰好恢复一次；取消发生在获准前/后都不泄漏 permit、不触发 activeLoads 负数。
- 并发 2→1→2、内存警告、缓存清理、所有消费者退出和快速滚动；等待者立即释放，正在运行的工作正常结束。
- Home 宽/窄两种 ViewThatFits 布局、特色卡/相关卡、最近来源与项目顺序，均与 v3.7 一致。
- `countDue(cards, date)` 与 `due(cards, date).count` 对删除/未入队/未来到期/无 schedule 等边界一致；队列顺序不改变。

`b6d4861` 的选区防重、阅读器释放、Release 测试夹具改动也还没有原生运行通过。新增测试已经写在 `ios/Tests/PerformanceAppTests.swift`，需要实际执行，不能以文件存在作为通过证据。

## 网络与工具接续

草稿已有 41 条规则，含 `*.blob.core.windows.net`；当前实例配置报告仍是 8 条自定义规则。旧运行 artifact/log 实际主机为 `productionresultssa13.blob.core.windows.net`、`productionresultssa6.blob.core.windows.net`，访问被拒绝。当前工具只能读运行配置/编辑草稿，不能直接应用草稿。用户本次选择跳过验证，未确认网络已改变。不要重复申请同一授权或宣称网络已修好。

新对话先核对它自己的实际配置/目录，不继承旧网络状态。设置生效后再正常重试；保持代理和 TLS，不改域名绕过策略，不提交临时签名 URL。

当前工作区的临时工具（新环境可能不存在）：Swift 6.2.4 位于 `/tmp/ks-performance-tools/swift/usr/bin`；SQLite 头在 `/tmp/ks-performance-tools/sqlite/root/usr/include`，库在其 `usr/lib/x86_64-linux-gnu`。npm 缓存在 `/tmp/ks-performance-tools/npm-cache`。历史完整首轮失败日志为 `/tmp/ks-performance-tools/native-first-failure.log`。后续失败/拒绝日志可能含短时签名 URL，不提交这些临时文件。

核心 42 项 Debug/Release、Node 43 项的历史结果以及 fixture v2 Release 原始基准均已入库；详见结果文档和 `docs/performance/local-verification.json`。这些结果不覆盖最后的原生 UI 收尾，不等于全部性能目标达成。
