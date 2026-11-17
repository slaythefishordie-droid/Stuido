# 原生构建与 AltStore Classic

## 路径与工具

Windows / iPadOS 26.2 用户不需要实体 Mac 来下载 CI 产物。GitHub Actions 使用标准 `macos-26` ARM64 Runner，固定 `DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer`。官方 Runner 清单在 2026-11-18 核对列有 Xcode 26.2、iOS 26.2 SDK 和相应 iPad 模拟器；如果后续移除该工具链，工作流会明确失败，不静默换 SDK。

- [官方 Runner 清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- XcodeGen 2.44.1：从官方发行下载并校验已发布 SHA-256；`ios/project.yml` 是工程来源。
- Swift 6 语言模式，最低 iPadOS 17，iPad 单一设备族。
- `ios/Package.resolved` 锁定唯一 App 第三方依赖；CI 禁止自动解析到其他版本并比较锁文件。
- 无付费能力、推送通知、iCloud、App Group、扩展或内置证书。

## 自动触发与开销

`main` 的 Swift、iOS、构建脚本及工作流变更自动构建；PR 检查和手动 `Run workflow` 也可触发。文档修改不触发 macOS 构建。使用一个标准 macOS Job、25 分钟超时、同分支取消旧任务、7 天产物保留；不跑定时任务、不下载额外模拟器、不使用 larger runner。

用户最初描述 Private，但 API 返回 `private=false`；用户随后明确授权向当前 Public 仓库推送和运行。未改变仓库可见性。Public 仓库的标准托管 Runner 一般使用公开项目免费服务；若以后改为 Private，使用账户对应的 Actions 免费额度，macOS 消耗按 GitHub 当前计费规则计算。工作流无法保证账户永不超额；在 GitHub Billing 的 Actions budget 设置支出上限/停止超额用量。无需购买 macOS Runner。

## 下载和安装

1. 仓库 → Actions → `Native iPadOS` → 成功的运行。
2. 下载 `KnowledgeStudio-unsigned-ipa-<run_number>` Artifact，先解压外层 Artifact ZIP，取得 `KnowledgeStudio-unsigned.ipa` 与 SHA-256 文件。
3. 可在 Windows PowerShell 运行 `Get-FileHash .\KnowledgeStudio-unsigned.ipa -Algorithm SHA256`，与 `.ipa.sha256` 的摘要比较。这是 IPA 文件摘要，不是外层 Artifact ZIP 的摘要。
4. Windows 保持 AltServer / 官方 iTunes、iCloud（以 AltStore 当前官方要求为准）正常工作；iPad 使用 AltStore Classic 的添加 App 功能导入 IPA。安装时由用户在 AltStore/AltServer 内登录自己的 Apple 账户并重签。不要把密码、证书或账户凭据交给 GitHub Actions。
5. iPad 根据系统提示启用 Developer Mode、信任开发者，并在免费签名有效期内使用 AltStore 刷新。免费账户通常有 7 天有效期和 App 数量限制；以实际 AltStore 提示及 Apple 当前政策为准。
6. 首先确认 App 能打开，再按真机清单检查 YouTube 播放、Mark、回跳及重新进入。重签可能改变 Bundle ID；播放器的 origin/Referer 从运行时 `Bundle.main.bundleIdentifier` 生成，不能硬编码开发时标识。

不能直接把未签名 IPA 安装到 iPad，也不能通过 iTunes Wi-Fi 同步绕过签名。CI 不使用 `xcodebuild -exportArchive` 冒充已签名分发；它从 `generic/platform=iOS` 的真实 Release archive 取 `.app`，校验 arm64 / iPhoneOS / iPad 设备族，再封装 `Payload/KnowledgeStudio.app`。模拟器 `.app` 永不作为 IPA 来源。

## 各自独立的证据

`build-status.json` 记录 SPM、核心测试、模拟器测试、设备归档、IPA 打包的分别结果及 commit；`SimulatorTests.xcresult` 和 `simulator-summary.json` 保留测试数与失败情况。`package-report.json` 记录实际 Bundle ID、最低系统版本、SDK、设备族、设备构建和包结构验证，将 `altstore_installation` 与 `physical_ipad_validation` 固定为 `not_tested`，等待用户真实操作后另行记录。

失败时日志也会上传。没有 IPA Artifact 表示未完成打包，不要把日志 ZIP 或工程 ZIP 当成安装包。

## 本轮环境限制

本地机器为 Linux，Swift 6.2.1 官方工具链签名验证通过；核心测试可执行。Xcode、iPad 模拟器和设备归档只能由 macOS CI 验证。AltStore Classic 实际重签安装、iPadOS 26.2 上播放与交互仍需用户设备验证。
