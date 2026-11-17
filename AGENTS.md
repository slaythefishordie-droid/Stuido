# Knowledge Studio 开发约定

先阅读 README.md、docs/progress.md 和与任务相关的协议/模型文档。使用当前 checkout；每个云任务已隔离，不默认创建 Git worktree。

- 使用中文沟通，代码标识符和 JSON 字段使用英文。
- 原生 SwiftUI，最低 iPadOS 17；先保持 macOS GitHub Actions 可编译再扩展功能。勿将项目替换为 Web App。
- 一级卡片只有 word / expression / keyword / key_sentence。发现来源、整理状态、复习状态分开；Mark 不自动建卡，收藏不自动复习。
- 不加入内置 AI 聊天、云同步、字典 API、完整浏览器或 YouTube 媒体直链提取。
- 不清空用户数据来修复数据库/迁移；保留稳定 ID、原始定位、字段 provenance。导入需要显式确认、引用重映射和事务。
- 依赖通过薄适配层隔离，锁定版本；修改依赖时更新 docs/dependencies.md、锁文件与许可证声明。
- 不提交 Apple 账户密码、证书、签名密钥、临时签名下载 URL。AltStore 在用户端重签，CI 只产出经过设备架构检查的未签名 IPA 候选。

## 相关检查

- Swift 核心：`bash scripts/test-core.sh`（需要 Swift 6+）。
- 协议：`npm ci --ignore-scripts`，`npm test`，`npm run validate -- examples/import/valid-four-types.json`。
- 原生：`.github/workflows/ipados.yml`，固定标准 macos-15-intel / Xcode 26.2；本地 macOS 可用 `bash scripts/bootstrap-xcodegen.sh` 生成工程。
- 只运行与本次更改相称的检查。文档修改无需重复 macOS 构建。
- 分开记录核心测试、原生编译、模拟器测试、IPA 结构、AltStore 安装、真机播放/交互。Mock 测试不是 YouTube 播放成功；Linux 不能验证 SwiftUI 或签名安装。

当前阶段和未验证项以 docs/progress.md 为准。每阶段更新进度、实际结果与阻塞，不把下一阶段计划写成已实现功能。
