# Knowledge Studio

iPad 优先、本地优先的个人知识整理工具，采用 SwiftUI。当前进行阶段 0：协议与依赖评估、YouTube Mark 原型、原生自动构建。只保留四类卡片，不接入 AI 聊天或云同步。

## 当前可执行内容

- `Sources/KnowledgeCore`：YouTube 链接校验、会话隔离、带版本的原子 Mark 存储。
- `ios/`：SwiftUI YouTube 播放 / Mark / 回跳 / 最近视频原型。SPM 锁定 YouTubePlayerKit 2.0.5。
- `.github/workflows/ipados.yml`：标准 macOS 26 ARM64 / Xcode 26.2，SPM 检查、核心测试、iPad 模拟器测试、未签名设备归档和 IPA 结构校验。
- 本地核心测试：Swift 6.0+ 下运行 `bash scripts/test-core.sh`。
- 协议验证：Node.js 22+ 下运行 `npm ci --ignore-scripts && npm test`；`npm run validate -- examples/import/valid-four-types.json`。

macOS 上运行 `bash scripts/bootstrap-xcodegen.sh` 生成 `ios/KnowledgeStudio.xcodeproj`，然后打开项目。最低 iPadOS 17；CI 使用 SDK 26.2。无 Apple ID、证书或密码进入 CI。

参见 [构建与 AltStore 安装](docs/build-and-install.md)、[网络诊断](docs/network.md)。编译成功、模拟器测试成功、重签安装成功和真机功能验证是不同状态。当前验证记录会随实际运行更新；不能用未签名 IPA 推断安装成功。

需求与接续文档：[原始产品规范](docs/product-spec.md)、[数据模型](docs/data-model.md)、[导入协议](docs/protocol.md)、[ChatGPT 提示词](docs/chatgpt-prompt.zh.md)、[依赖评估](docs/dependencies.md)、[进度与阻塞](docs/progress.md)、[真机验收](docs/device-validation.md)。
