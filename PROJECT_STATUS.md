# Knowledge Studio 项目状态与交接

新模型须先读 [AGENTS.md](AGENTS.md)、本文件、[现行产品需求](docs/product-spec.md)和[Safari 路线图](docs/web-capture-roadmap.md)。网页采集采用随 App 分发的 Safari Web Extension。

## 当前状态 · 2026-11-19

- **开发方向：**`feature/safari-extension`。本轮实现两份计划阶段 1–4，并按用户要求整理为 v1.0.0；历史开发清单文件名仍为 [release-0.3-plan.md](docs/release-0.3-plan.md)。
- **真机基线：**用户确认里程碑 1 Safari 与 App 双向数据编号传输对应成功；新增功能真机验收单独记录。
- **v1.0.0：**d0938a5，版本 1.0.0 / build 4。原生运行 [44484104854](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44484104854) 全部通过：核心 21/21、iPad 模拟器 32/32、设备归档与 IPA 校验。协议/Safari 43/43 通过。[发布与下载](https://github.com/slaythefishordie-droid/Stuido/releases/tag/v1.0.0) · [完整证据](docs/verification/native-run-44484104854.json)。
- **功能实现：**数据底座、卡片和双 Inbox、确认 JSON 导入、Data Manager 与备份恢复、Library/PDF/EPUB/本地视频、Safari 精听/历史/设置/通用采集。
- **集中优化：**批量查询索引化、无变化不写库、文件复制/摘要/ZIP 后台执行、统一新增 Swift 模块格式。验证结果见 [开发日志](docs/progress.md)。
- **默认分支阻塞：**用户已授权修改默认分支，但 GitHub 管理 API 返回 integration 403；远端默认分支仍为 main。主开发继续在 Safari 分支。

## 功能与验证边界

- 数据底座：GRDB 事务聚合快照、稳定 ID、旧 prototype-v1.json 非破坏迁移、引用校验、回收站、ZIP 备份恢复。
- 卡片和双 Inbox：四类型编辑与出处、独立整理/复习状态、Safari/阅读 Mark 整理为卡片、JSON 文件/粘贴校验、来源匹配、重复提示和确认导入。
- Library：项目资料关联、PDF 高亮与回跳、Readium EPUB 定位、本地视频时间 Mark、词典外链。
- Safari：QuickMark 可靠交接、精听 ±1/2/3 秒、A–B 循环、历史搜索/备注/删除/导出、旧格式兼容解析、个性化与逐站授权的文章/页面音频采集。
- 新增功能的真机流程仍待验证；旧书签兼容仅使用合成 v1 样例，真实旧文件尚未提供。扫描 PDF 不含 OCR，EPUB 不接 DRM，非标准网站音频需适配。
- v0.1.0 标签保留旧 YouTube 原型；当前入口已经替换为完整工作区。详细历史结果保留于开发日志，不作为新增功能的验证证据。

## 后续开发必须保留的决策

- 采用原生 SwiftUI，最低 iPadOS 17，本地优先。网页数据由 Safari 原页面采集，以本地 Native Messaging 和 App Groups 交接，按唯一 ID 去重。[依赖评估](docs/dependencies.md)
- 只有 word、expression、keyword、key_sentence 四类卡片。发现来源、字段作者身份、整理状态、复习状态分别保存。标记、收藏和加入复习各由独立操作触发。[数据模型](docs/data-model.md)
- ChatGPT 在 App 外使用。导入需要用户预览、确认、引用重映射和原子写入。项目归属、个人笔记和复习状态由用户控制。[导入协议](docs/protocol.md)

## 后续工作

按 [真机清单](docs/device-validation.md) 验证本次新增工作流和实际旧备份；记录站点变体及真实资料兼容问题。产品阶段 5–6 的知识图谱和复习调度仍在后续计划。默认分支需有仓库管理权限的账号修改，主开发继续使用 Safari 分支。
