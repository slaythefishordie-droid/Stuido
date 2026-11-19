# 构建与安装指南

当前版本、测试结果、IPA 下载和到期日统一见[开发进度](progress.md)，失败排查见[工程问题](engineering-issues.md)。本文件只维护操作方法。

## 构建

- 原生 SwiftUI，最低 iPadOS 17，Xcode 26.2、XcodeGen 2.44.1；工程来源为 ios/project.yml，勿修改生成工程。
- macOS 运行 `bash scripts/bootstrap-xcodegen.sh`，打开生成的工程。Swift 包按 ios/Package.resolved 锁定；核心测试需要 Swift 6.1+。
- CI 为 .github/workflows/ipados.yml，默认标准 macos-15-intel，手动可选 macos-26。包含锁文件检查、核心/iPad 模拟器、设备归档和 IPA 校验，25 分钟超时，Artifact 保留 7 天。
- main 相关代码变更、面向 main 的 PR 和手动触发运行；文档不触发原生流程。不要重复触发正在运行的同分支构建。
- 不把模拟器 App 当 IPA，不使用 Apple 账户秘密。设备包经 arm64/iPhoneOS、嵌入扩展、签名权限、ZIP 校验；ad-hoc 签名仅保留重签所需声明，不提供 Apple 安装授权。

## 安装

1. 从进度日志的实际入口获取 IPA 和摘要；Actions Artifact 需先解压外层 ZIP。Release 是否已有附件以进度记录为准。
2. Windows PowerShell 用 `Get-FileHash .\KnowledgeStudio-v1.0.0.ipa -Algorithm SHA256` 核对本体摘要（按实际文件名替换），不要比较外层 ZIP 的摘要。
3. 按 AltStore 当前官方要求配置 Windows AltServer、iTunes/iCloud；在 iPad AltStore Classic 添加 IPA，保留 Safari 扩展，账户凭据仅在用户设备输入。
4. 按系统提示启用开发者模式、信任开发者并定期刷新签名；免费账户有效期和 App 数量限制以实际提示为准。保持相同应用身份以延续数据，升级前保留独立备份。
5. 主 App 进入 My Inbox；设置中保留 Safari 双向诊断。Safari 设置中启用扩展、授权网站，再按进度日志中的新增真机清单验收。

CI 的 build-status.json、simulator-summary.json、package-report.json 分别记录步骤、测试、实际包信息。编译、重签安装、Safari 识别、真实共享与网站交互分别判定，不能互相替代。
