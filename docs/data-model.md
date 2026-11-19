# 数据模型与技术决定

现行设计覆盖 Safari 网页采集和主 App 的本地知识库。第一版保留视频 Source/Mark 原型；0.3 开发代码已接入 Safari 交接、SQLite 事务知识库与确认导入，验证范围见项目状态。

## 独立维度

`Card.type = word | expression | keyword | key_sentence`；`discovery_origin = self | ai | both`；`organization_status = inbox | saved | archived`；`review_status = not_enrolled | active | paused`。内容类型、发现来源、整理状态、复习状态不可互相推导。是否在回收站用独立 `deleted_at`。合并发现来源用集合并集，不改写内容作者。

`content` 按类型严格编码；`provenance` 保留字段级 original/ai_explanation/ai_generated/user_input 和出处引用。`personal_note`、`import_annotation` 分开。共用 UUID、language、tags、created_at、updated_at。word 的学习主体仅显示英文例句与英文释义，word 是记录标识；其他三类保留出处入口。

## 正式对象和关联

| 对象 | 关键字段/规则 |
|---|---|
| Project | UUID、title、description、timestamps；删除项目不删除卡片或文件。 |
| Source | UUID、kind、title、URL、content_hash、local_asset_id、availability；文件按 hash 单份保存。在线 Source 只备份链接和元数据。 |
| Mark | UUID、source_id、typed locator、excerpt 可选、note、created_at；定位由阅读器/播放器产生，不自动变成 Card。 |
| Card | 独立于 Project；通过 CardSourceRef / CardMarkRef 关联出处，支持无出处的手工内容。 |
| Relation | UUID、from_card_id、to_card_id、kind、note；图谱位置不在关系里。 |
| ReviewRecord | UUID、card_id、rating、reviewed_at、elapsed_ms、调度器版本和参数摘要；历史追加保存。 |
| ReviewState | 独立 card_id、status、due、FSRS state/stability/difficulty/last_review 等；退出复习不删除卡片。 |
| ImportBatch / PendingItem | 原始包摘要、版本、指纹、决策、映射、状态；AI Inbox 仅展示未确认候选，不形成第二套知识库。 |
| GraphNode / GraphLayout | project_id、card_id、position、pinned、viewport；删除节点只影响布局和显示。 |

关联表 `ProjectSource/ProjectCard/ProjectRelation` 独立存储。解除关联、移除布局节点、软删除对象和永久清理是不同业务命令。默认外键限制隐式级联；删除预览查询入边、出边、出处、项目、复习与布局影响。软删除保留对象 ID 与关联，恢复时验证端点完整；永久清理必须另行确认范围。

## 分层与依赖边界

SwiftUI View → 应用服务（capture/import/review/backup）→ 领域对象与 Repository 协议 → 持久化适配层。多个页面查询同一存储：Dictionary 过滤 word/keyword，Corpus 过滤 expression/key_sentence；双 Inbox 按来源和阶段筛选。网页标记属于用户自行发现的内容，进入 My Inbox；AI Inbox 继续接收用户手动导入的候选卡片。

### Safari 扩展与主 App 的职责

- 一个随主 App 分发的 Safari Web Extension 承载多个网站适配器。适配器在原页面识别资料，读取页面真实定位并承接站点变化。YouTube 首先使用出处链接和秒数；文章、播客后续按资料类型提供定位。通用知识库使用 Source、Mark 及其关联。
- 采集和交接经本地 Native Messaging 与 App Groups。只有持久化成功才提示已保存；主 App 未运行时仍可采集。切回 App 后自动接收，交接中断可重试；同一唯一 ID 重送只出现一次。采集时不暂停精听、不弹编辑表单、不切换 App。
- QuickMark 回溯作用于新书签保存的位置。旧原型的 Mark 在迁移时保留原始 ID、定位与秒数，已有记录不重新套用回溯设置。
- Native Messaging 的具体消息流程、共享存储格式、代码结构和接口由实施时决定。ChatGPT 导入 Schema 与 QuickMark 旧书签备份各自服务于原来的用途。[网页采集路线图](web-capture-roadmap.md)

阶段 1 优先 GRDB/SQLite，原因是显式事务、外键、迁移、备份快照和 Linux 验证便利。正式接入前跑迁移/失败回滚/备份恢复验证，并锁版本。当前 prototype-v1.json 是可迁移记录：UUID、sourceID 和原始秒数保持不变；数据库迁移成功前保留原文件，失败不能清空重建。它还不提供正式 Data Manager 或用户备份能力。

备份将使用版本化 manifest、每个文件 SHA-256、数据库一致快照与 ZIP 归档。恢复先在临时目录校验路径、大小、摘要、对象/关系引用、版本，再原子切换；拒绝路径穿越和解压炸弹。缺失原始资料保留 Card 与出处并标 unavailable。备份不能声称包含在线视频文件。

## 可调整的复习展示提案

- word：正面英文例句，背面英文释义；学习主体不新增中文栏。
- expression：正面原句，背面出处与用户已有笔记。
- keyword：正面 term，背面已有 explanation 和出处。
- key_sentence：正面原句，背面已有 explanation 和出处。

展示策略独立于内容数据，待用户实际体验后调整。进入 Review 必须用户主动选择，收藏不会自动入队。FSRS 适配层持有算法版本、参数与时区决定，调度状态和 ReviewRecord 分开事务保存。未实现正反面或每日任务，不把提案当作验收结果。


### 里程碑 1 验证实现

主 App 激活时和 Safari 扩展面板请求时读取共享目录。当前只保存双向诊断记录，各端写自己的 JSON 文件并原子替换，用 UUID 核对来源与重启恢复。此诊断格式独立于未来 Mark 交接协议。Safari 的 UI 页面调用 native messaging，原生 SafariServices 处理器执行读写。

分发时以 ad-hoc 签名保存请求的 App Groups 权限，AltStore 重签后优先解析其 ALTAppGroups 元数据。需要用真机确认该版本 AltStore 的实际行为。

## 里程碑 2 交接实现

`WebMark` v1 是不可变交接记录，独立于 ChatGPT Schema、旧原型和未来数据库。共享组中 `WebMarks-v1/<UUID>.json` 同时供扩展写入、My Inbox 读取；以 `videoID` 推导规范 HTTPS 出处，正式 Source 表尚未迁入。`capturedSeconds` 是原始秒数，`seconds = max(0, floor(capturedSeconds - preRoll))` 是新 QuickMark 回溯定位；`createdAt` 使用 Unix 毫秒。现有原型不重新套用回溯。

扩展先将完整记录写入 `browser.storage.local` 的 `pendingMark:<UUID>`，再通过 Native Messaging 发出 `saveMark`。只有原生原子落盘并回传匹配 UUID 才清除待发。重复 ID 内容必须相同；不同内容或损坏文件拒绝覆盖。原生使用共享目录内 `.lock` 的跨进程 flock 序列化访问。后台每次启动重试待发，网页超时后保留同一条记录供用户重试。主 App 不消费删除队列，启动/前台直接读同一份记录，因此不会出现“已确认但未入 Inbox”的交接窗口。

此格式是最小采集底座，不提供数据库事务迁移、删除/编辑或备份功能。共享权限异常不回退到私有目录，读取异常展示错误并保留原数据。网页 DOM 识别仍需真机回归。

## 0.3 SQLite 与应用服务

`LibraryRepository` 使用 GRDB DatabaseMigrator 建立 library-v1。当前以一个版本化聚合快照 BLOB 保存正式 Source/Mark/Card/Project/Relation、待确认批次、复习历史和独立复习状态；每次写入在 SQLite 事务中读取、变更、校验所有稳定 ID 与引用后提交。此阶段选择小规模本地库的显式原子性，不宣称已经实现关系表索引或大规模查询优化。未来分表迁移须保留当前对象 ID，不能清库重建。

My Inbox 和卡片/Dictionary/Corpus 都查询该库。Safari 原始交接文件仍不可破坏，已接收 UUID 单独保留以防永久清理后被重送复活；历史备注与软删除通过更新修订同步。旧 prototype-v1 事务迁入后只标记完成，不删除原文件。

备份使用一致的事务读取快照和内容摘要命名的本地资料，逐文件 SHA-256 清单，ZIP CRC、文件集合、路径/类型/大小和对象引用验证后才能确认恢复。恢复前先写入本地快照，先复制不可变资料再以事务替换库；失败时原库不变，多复制的无引用文件可后续清理。网络资料仅保存出处，不备份在线视频。

## 设计章程的待实施模型约束 · 2026-11-19

同一 Source 跨 Project 默认共享原文件、高亮与 Mark；项目研究笔记、解释和工作语境独立，未来可选独立副本。此为用户已确定的产品语义，不表示现有聚合快照已实现项目语境字段。具体结构及迁移需单独设计，重大调整按工作流取得同意，覆盖备份恢复与删除关联验证。自由白板允许混合对象，但不扩展四类 Card，也不将移除节点当作删除内容。实施待办统一见工程问题 UX-01。
