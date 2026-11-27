# v3.7 性能审计

基线：`1888dcb570093aba680f70baa403dcbc5fcd7f99`（`release/v3.7.0`，相对 `v3.7.0` 标签只有文档整理）。恢复标签：`baseline/v3.7-before-performance-20261121`。独立分支：`performance/v3.7-low-power`。初始工作区干净，原 `work` 分支保留。

首轮暂停决定见 [PERFORMANCE_HANDOFF.md](PERFORMANCE_HANDOFF.md)；第二轮已恢复验证，最新状态见 docs/progress.md。

## 验证边界

Linux 可运行 Swift 6.2.4 Release 核心基准和功能测试；SwiftUI、PDFKit、Readium 集成由 macOS Actions 检查。当前没有连接 iPad、Instruments、Energy Log。下表静态发现不等于已经测得卡顿或耗电。时间数据与最终处理见 PERFORMANCE_RESULTS.md。

## 兼容性清单

必须保留：四种卡片、用户自选 FSRS 复习、双 Inbox、ChatGPT JSON 导入、Project/Source/Card/Mark/Relation/Review 的 ID 与关系、软删除/恢复/影响确认、备份/资源文件、Settings；三个封面模式；PDF 精确定位/高亮/墨迹/OCR、EPUB 定位/批注、视频跳转与 A–B；Boards、Lounge；Safari QuickMark 全功能、Share Extension、Native Messaging、App Groups 重签配置、去重和失败重试。

不改变 SQLite `library-v1` 表、JSON/Codable 格式、Schema、App Group 名称、扩展消息协议和最低 iPadOS 17。无数据库迁移，不清理用户数据。GRDB 7.12.0、Readium 3.11.1 等锁定依赖沿用。保留现有同步编辑成功/失败语义。

## 按风险与用户影响排序

| 优先级 | 模块与证据（基线） | 根因与处理方向 |
|---|---|---|
| 高 | LibraryRepository.read/updateAndRead 每次 SELECT、JSON 解码、完整校验；小阅读位置更新再次编码整个库 | 热读、无变化事务重复 O(N) 解码。缓存经验证的快照，SQLite 版本失效；保留事务和每次实际写入的全量校验。跨连接一致性、回滚必须测试 |
| 高 | StudioModel ObservableObject 发布整个 state，所有 EnvironmentObject 消费者收到任意变化 | 通知范围大；使用系统 Observation 按集合追踪，避免阅读位置/消息改变触发卡片页无关观察 |
| 高 | StudyThumbnails 的磁盘读取、PDF 元数据读取、JPEG 编码在 MainActor；自选封面在 body 内 UIImage(data:) | 把非 UI 资源工作移出主线程，异步缓存与取消；ImageRenderer 保留在主线程。缓存有预算并响应系统压力 |
| 高 | 阅读位置保存同步进入完整库写事务；初始化同步打开库 | 阅读器回调可能阻塞渲染。后台有序写入并保障生命周期；启动同步路径单列剩余限制 |
| 中 | Lounge 前台无倒计时也每秒唤醒，实际持久化周期为 30 秒 | 按下一检查点/倒计时/抽取截止时间睡眠；不延迟计时器提醒，不减少数据保存频率 |
| 中 | 阅读器按 sourceID 对所有 marks 过滤，列表/Board 多次线性查找 | 重用集合索引，按集合改变失效；不引入新数据库或图形引擎 |
| 中 | PDFHost 已按页差分，但每次 updateUIView 先重建全部标注分组 | 保留已正确的页差分，跳过输入完全相同的投影 |
| 中 | 备份恢复仍在主线程编码恢复前快照与执行数据库恢复 | 需要原子保护并发编辑；不能仅 detached 后宣称正确。保留恢复安全语义，后续优化须测试并发恢复 |
| 中 | Safari 激活时枚举并解码所有队列文件；Library 接收每次整体扫描 | 保留 flock、原子落盘、更新修订与错误报告；不以跳过校验换速度。数据库热缓存降低无变化接收成本，文件增量索引另行评估 |
| 中 | 大型 Data Manager 影响分析、搜索、Library 排序、Board 全节点布局 | 确认是内存集合扫描而非 SQL N+1。先收窄状态失效；真机分析后再选择分页/后台投影/可视区域裁剪，避免改变选择、排序和全局搜索语义 |
| 低 | 视频 A–B 已用 AVPlayer boundary observer；EPUB 已比较 decorations；PDF 已逐页差分；稳定对象 ID | 保留，不无差别重写；视频进度并未驱动全 App 每帧刷新 |

## 测量方法

`scripts/benchmark-performance.sh` 在临时目录生成 100 / 2,000 / 10,000 卡片及两倍 Mark，各操作 7 次，记录全部样本、median/max、规模、checksum，最后重开验证卡片和阅读位置。基线及优化使用相同机器、Release 和数据形状。它不测触控 P95、帧率、真机能耗；7 个样本不能推断生产 P95。首次打开和整个库实际写入仍为 O(N)。
