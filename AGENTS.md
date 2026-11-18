# Knowledge Studio 开发约定

每个新 Codex 模型或新会话开始开发前，必须先读本文件、[PROJECT_STATUS.md](PROJECT_STATUS.md)、[开发计划与验收标准](docs/product-spec.md) 和[Safari 网页采集路线图及脚本迁移对照](docs/web-capture-roadmap.md)，再阅读 README.md、docs/progress.md 以及本次任务涉及的协议或模型文档。先核对当前分支、未提交改动和用户本轮目标。Safari 相关开发使用 `feature/safari-extension` 分支，提交前核对分支。

## 架构与技术栈

- 网页采集统一在 Safari 网站原页面，由主 App 随附的一个 Web Extension 和多个站点适配器承担。本地 Native Messaging 与 App Groups 完成交接。先验证免费重签、扩展识别和共享读写，再实现 QuickMark 到 My Inbox。
- 第一版基线中，`Sources/KnowledgeCore` 是 Swift 6 的 SwiftPM 包。`YouTubeVideoID` 校验输入，`MarkCapture` 管理会话和异步取时，`MarkStore` 验证快照并原子落盘。
- `ios/KnowledgeStudio` 是 SwiftUI 应用层。以下播放器类只描述 v0.1.0 旧原型。`YouTubeStudyView` 展示界面，`YouTubeStudyModel` 协调播放器和状态，`YouTubeClock` 通过核心层的 `VideoClock` 接口接入 YouTubePlayerKit。编辑 XcodeGen 的 `ios/project.yml` 维护工程配置。
- `schemas/` 维护 Draft 2020-12 导入协议。`tools/protocol/` 使用 Node.js 22+、Ajv、ajv-formats 和 jsonc-parser。文件和粘贴文本共用校验入口。`examples/import/` 提供可运行的协议样例。
- 原型快照格式、导入协议、未来的数据库迁移与备份格式分别演进。变更持久化或协议时，应验证现有数据能重新打开，以及失败后的数据完整性。

## 开发约定

- 使用中文沟通，代码标识符和 JSON 字段使用英文。
- 原生 SwiftUI，最低 iPadOS 17；先保持 macOS GitHub Actions 可编译再扩展功能。勿将项目替换为 Web App。
- 一级卡片只有 word / expression / keyword / key_sentence。发现来源、整理状态、复习状态分开；Mark 不自动建卡，收藏不自动复习。
- 不加入内置 AI 聊天、云同步、字典 API、完整浏览器或 YouTube 媒体直链提取。
- 不清空用户数据来修复数据库/迁移；保留稳定 ID、原始定位、字段 provenance。导入需要显式确认、引用重映射和事务。
- 依赖通过薄适配层隔离，锁定版本；修改依赖时更新 docs/dependencies.md、锁文件与许可证声明。
- 不提交 Apple 账户密码、证书、签名密钥、临时签名下载 URL。AltStore 在用户端重签，CI 产出经过设备架构检查、需要用户重新签名的 IPA 候选。扩展开发包以 ad-hoc 签名保存权限声明。

## 相关检查

- Swift 核心：`bash scripts/test-core.sh`（需要 Swift 6+）。
- 协议：`npm ci --ignore-scripts`，`npm test`，`npm run validate -- examples/import/valid-four-types.json`。
- 原生：`.github/workflows/ipados.yml`，固定标准 macos-26 (ARM64) / Xcode 26.2；本地 macOS 可用 `bash scripts/bootstrap-xcodegen.sh` 生成工程。
- 只运行与本次更改相称的检查。文档修改无需重复 macOS 构建。
- 分开记录核心测试、原生编译、模拟器测试、IPA 结构、AltStore 免费签名安装、Safari 识别扩展、App Groups 实际共享及真机交互。Mock 测试不是 YouTube 播放成功；Linux 不能验证 SwiftUI 或签名安装。

当前范围与交接事项见 PROJECT_STATUS.md，历次验证和限制见 docs/progress.md。每阶段更新进度、实际结果与阻塞，不把下一阶段计划写成已实现功能。
