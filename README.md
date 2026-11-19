# Knowledge Studio

iPad 优先、本地优先的个人知识整理工具，采用 SwiftUI。网页学习采用随 App 提供的 Safari Web Extension，首个适配器为 YouTube。用户已确认里程碑 1 真机双向共享成功。v1.0.0 实现了数据管理、卡片与导入、本地阅读和完整 Safari QuickMark；新功能验证状态见项目状态与开发日志。只保留四类卡片，不接入 AI 聊天或云同步。

使用说明见 [阶段 1–4 操作指南](docs/0.3-user-guide.md)，版本详情见 [v1.0.0 发布说明](docs/releases/v1.0.0.md)。

新模型开始前先读 [AGENTS.md](AGENTS.md)、[项目状态](PROJECT_STATUS.md)、[产品需求](docs/product-spec.md) 和[四个里程碑](docs/web-capture-roadmap.md)。

## 构建与开发

- `Sources/KnowledgeCore`：GRDB 事务存储、对象与引用校验、迁移、严格 JSON 导入和共享采集存储。
- `ios/`：SwiftUI 卡片与双 Inbox、管理与备份、PDFKit / Readium / AVKit 阅读播放，以及随 App 分发的 Safari 扩展。
- `.github/workflows/ipados.yml`：标准 macos-15-intel / Xcode 26.2（可选 macos-26 ARM64），SPM 检查、核心测试、iPad 模拟器测试、未签名设备归档和 IPA 结构校验。
- 本地核心测试：Swift 6.1+ 下运行 `bash scripts/test-core.sh`。
- 协议验证：Node.js 22+ 下运行 `npm ci --ignore-scripts && npm test`；`npm run validate -- examples/import/valid-four-types.json`。

macOS 上运行 `bash scripts/bootstrap-xcodegen.sh` 生成 `ios/KnowledgeStudio.xcodeproj`，然后打开项目。最低 iPadOS 17；CI 使用 SDK 26.2。无 Apple ID、证书或密码进入 CI。

第一版标签 `v0.1.0` 已通过 [Native iPadOS #6](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227526926)：依赖检查、核心与 iPad 模拟器测试、设备归档、未签名 IPA 打包和产物上传。AltStore 重签安装及真机交互仍待用户设备验证。

参见 [构建与 AltStore 安装](docs/build-and-install.md)、[网络诊断](docs/network.md)。编译成功、模拟器测试成功、重签安装成功和真机功能验证是不同状态。当前验证记录会随实际运行更新；不能用未签名 IPA 推断安装成功。

需求与接续文档：[现行产品需求](docs/product-spec.md)、[数据模型](docs/data-model.md)、[导入协议](docs/protocol.md)、[ChatGPT 提示词](docs/chatgpt-prompt.zh.md)、[依赖评估](docs/dependencies.md)、[开发日志](docs/progress.md)、[开发与构建问题日志](docs/engineering-issues.md)、[真机验收](docs/device-validation.md)。
