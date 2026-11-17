# 数据模型与技术决定

状态：阶段 0 的正式架构约定。当前代码只实现视频 Source/Mark 的小型原型存储；以下正式数据库和导入事务在阶段 1–2 实现。

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

SwiftUI View → 应用服务（capture/import/review/backup）→ 领域对象与 Repository 协议 → 持久化适配层。多个页面查询同一存储：Dictionary 过滤 word/keyword，Corpus 过滤 expression/key_sentence；双 Inbox 按来源和阶段筛选。当前 `VideoClock` 将第三方播放器隔离，`MarkCapture` 处理会话，`MarkStore` 负责原子落盘。应用本身不建 Web 浏览器、不调用 ChatGPT、不获取 YouTube 媒体直链。

阶段 1 优先 GRDB/SQLite，原因是显式事务、外键、迁移、备份快照和 Linux 验证便利。正式接入前跑迁移/失败回滚/备份恢复验证，并锁版本。当前 prototype-v1.json 是可迁移记录：UUID、sourceID 和原始秒数保持不变；数据库迁移成功前保留原文件，失败不能清空重建。它还不提供正式 Data Manager 或用户备份能力。

备份将使用版本化 manifest、每个文件 SHA-256、数据库一致快照与 ZIP 归档。恢复先在临时目录校验路径、大小、摘要、对象/关系引用、版本，再原子切换；拒绝路径穿越和解压炸弹。缺失原始资料保留 Card 与出处并标 unavailable。备份不能声称包含在线视频文件。

## 可调整的复习展示提案

- word：正面英文例句，背面英文释义；学习主体不新增中文栏。
- expression：正面原句，背面出处与用户已有笔记。
- keyword：正面 term，背面已有 explanation 和出处。
- key_sentence：正面原句，背面已有 explanation 和出处。

展示策略独立于内容数据，待用户实际体验后调整。进入 Review 必须用户主动选择，收藏不会自动入队。FSRS 适配层持有算法版本、参数与时区决定，调度状态和 ReviewRecord 分开事务保存。未实现正反面或每日任务，不把提案当作验收结果。
