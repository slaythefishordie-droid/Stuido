# 原生构建与 AltStore Classic

## 路径与工具

Windows / iPadOS 26.2 用户不需要实体 Mac 来下载 CI 产物。GitHub Actions 默认使用标准 `macos-15-intel` Runner（手动可选 `macos-26` ARM64），固定 `DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer`。官方 Runner 清单在 2026-11-18 核对列有 Xcode 26.2、iOS 26.2 SDK 和相应 iPad 模拟器；如果后续移除该工具链，工作流会明确失败，不静默换 SDK。

- [官方 Runner 清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- 因近期 ARM64 容量不足，自动与手动构建默认选择标准 `macos-15-intel`，仍使用 Xcode 26.2 / iOS 26.2 模拟器；`macos-26` 保留为手动备选。2026-11-18 已核对 [Intel 镜像清单](https://github.com/actions/runner-images/blob/d9c48363ed37529f6ef929845cda83bbdae0ef74/images/macos/macos-15-Readme.md) 含相同工具链。日志记录实际主机架构；设备归档始终验证为 iPhoneOS arm64。
- XcodeGen 2.44.1：从官方发行下载并校验已发布 SHA-256；`ios/project.yml` 是工程来源。
- Swift 6 语言模式，最低 iPadOS 17，iPad 单一设备族。
- `ios/Package.resolved` 锁定唯一 App 第三方依赖；CI 禁止自动解析到其他版本并比较锁文件。
- 第一版归档只包含主 App。新采集架构需要嵌入 Safari Web Extension，并验证主 App 和扩展在免费重签后实际共享 App Groups 数据。

## 自动触发与开销

`main` 的 Swift、iOS、构建脚本及工作流变更自动构建；PR 检查和手动 `Run workflow` 也可触发。文档修改不触发 macOS 构建。使用一个标准 macOS Job、25 分钟超时、同分支取消旧任务、7 天产物保留；不跑定时任务、不下载额外模拟器、不使用 larger runner。

用户最初描述 Private，但 API 返回 `private=false`；用户随后明确授权向当前 Public 仓库推送和运行。未改变仓库可见性。Public 仓库的标准托管 Runner 一般使用公开项目免费服务；若以后改为 Private，使用账户对应的 Actions 免费额度，macOS 消耗按 GitHub 当前计费规则计算。工作流无法保证账户永不超额；在 GitHub Billing 的 Actions budget 设置支出上限/停止超额用量。无需购买 macOS Runner。

## 下载和安装

已验证的旧主 App 版本为 `v0.1.0`（`7df6ef1`）。原生构建、模拟器测试、设备归档、IPA 校验及上传通过。[Native iPadOS #6](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227526926)

- 下载第一版可选择 [KnowledgeStudio-unsigned-ipa-6](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227526926/artifacts/14394892490)。对应的构建与测试结果见 [KnowledgeStudio-build-evidence-6](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227526926/artifacts/14394204187)。GitHub 保留产物 7 天，下载可能需要登录。
- 验收 Safari 方案时使用里程碑 1 生成的含扩展设备 IPA，并记录重签后扩展及共享权限的实际状态。

1. 仓库 → Actions → `Native iPadOS` → 成功的运行。
2. 下载 `KnowledgeStudio-unsigned-ipa-<run_number>` Artifact，先解压外层 Artifact ZIP，取得 `KnowledgeStudio-unsigned.ipa` 与 SHA-256 文件。
3. 可在 Windows PowerShell 运行 `Get-FileHash .\KnowledgeStudio-unsigned.ipa -Algorithm SHA256`，与 `.ipa.sha256` 的摘要比较。这是 IPA 文件摘要，不是外层 Artifact ZIP 的摘要。
4. Windows 保持 AltServer / 官方 iTunes、iCloud（以 AltStore 当前官方要求为准）正常工作；iPad 使用 AltStore Classic 的添加 App 功能导入 IPA。安装时由用户在 AltStore/AltServer 内登录自己的 Apple 账户并重签。不要把密码、证书或账户凭据交给 GitHub Actions。
5. iPad 根据系统提示启用 Developer Mode、信任开发者，并在免费签名有效期内使用 AltStore 刷新。免费账户通常有 7 天有效期和 App 数量限制；以实际 AltStore 提示及 Apple 当前政策为准。
6. 在含扩展的版本上记录主 App 启动、Safari 识别并启用扩展以及两端共享读写的独立结果。若 AltStore 提示保留或移除扩展，保留扩展并记录实际结果。[验收记录](device-validation.md)

不能直接把未签名 IPA 安装到 iPad，也不能通过 iTunes Wi-Fi 同步绕过签名。CI 不使用 `xcodebuild -exportArchive` 冒充已签名分发；它从 `generic/platform=iOS` 的真实 Release archive 取 `.app`，校验 arm64 / iPhoneOS / iPad 设备族，再封装 `Payload/KnowledgeStudio.app`。模拟器 `.app` 永不作为 IPA 来源。

## 各自独立的证据

`build-status.json` 记录 SPM、核心测试、模拟器测试、设备归档、IPA 打包的分别结果及 commit；`SimulatorTests.xcresult` 和 `simulator-summary.json` 保留测试数与失败情况。`package-report.json` 记录实际 Bundle ID、最低系统版本、SDK、设备族、设备构建和包结构验证，将 `altstore_installation` 与 `physical_ipad_validation` 固定为 `not_tested`，等待用户真实操作后另行记录。

失败时日志也会上传。没有 IPA Artifact 表示未完成打包，不要把日志 ZIP 或工程 ZIP 当成安装包。

## 本轮环境限制

本地机器为 Linux，Swift 6.2.1 官方工具链签名验证通过；核心测试可执行。Xcode、iPad 模拟器和设备归档只能由 macOS CI 验证。AltStore Classic 实际重签安装、Safari 识别扩展、App Groups 实际共享与网站采集仍需用户设备验证。

## Safari 里程碑 1 开发包

最新已验证构建：[Native iPadOS #14](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44432216488)，commit `ea8ca267db640c6d9996367ea6aebcb72f96aa3c`。核心 8 项、模拟器 14 项测试通过，设备归档及 IPA 打包校验通过。

**[下载 KnowledgeStudio-resignable-ipa-14](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44432216488/artifacts/14488745224)**（GitHub 登录后下载，保留至 2026-11-26）。外层 ZIP 的 SHA-256 为 `a349b8ab5d5bca5a30ff043b856bc2e5902c3d0e02935f1bd3db6144657b2d94`。IPA 本体摘要在包内 `.ipa.sha256` 中，两者不要混用。云端代理无法下载附件时，直接在用户自己的浏览器下载；本轮未完成本地 IPA 复验。

解压后，在 Windows PowerShell 执行 `Get-FileHash .\KnowledgeStudio-resignable.ipa -Algorithm SHA256`，与包内 `.ipa.sha256` 对比。再把 `.ipa` 传到 iPad「文件」，在 AltStore Classic → My Apps → ＋ 选择它，并保留 Safari 扩展。

在 `feature/safari-extension` 上手动运行 Native iPadOS。新产物名为 `KnowledgeStudio-resignable-ipa-<run_number>`，内含 `KnowledgeStudio-resignable.ipa`。归档后先验证嵌入的 SafariExtension.appex 的设备架构、扩展类型和 manifest，再用 ad-hoc 签名携带两端的 App Groups 声明。该签名没有 Apple 配置文件，安装仍由 AltStore Classic 免费账户重签。

Actions → Native iPadOS → Run workflow：分支选 `feature/safari-extension`，runner 默认 `macos-15-intel`。如果选择 ARM64 后运行没有执行任何步骤，且注解为 `The job was not acquired by Runner of type hosted even after multiple attempts`，改回 `macos-15-intel` 重试。如果 Intel 也无法分配，可稍后重试或手动选择 `macos-26`。这是调度失败，不等于代码或测试失败。命令行等价操作：`gh workflow run ipados.yml --ref feature/safari-extension -f runner=macos-15-intel`。

安装时保留 Safari 扩展。主 App 启动进入「Safari 扩展」验证页面。到 iPad 设置中的 Safari 扩展列表启用 Knowledge Studio，再在 Safari 页面菜单打开它。

1. 在 Safari 面板按「写入 Safari 验证记录」，记下编号。
2. 打开主 App，确认 Safari 记录编号相同。
3. 按「写入主 App 验证记录」，记下新的编号。
4. 回到 Safari 面板按「读取共享记录」，确认主 App 编号相同。
5. 关闭并重新打开主 App，复核两条记录仍可读取。

首次构建请求组名 `group.org.knowledge-studio.prototype`。AltStore 如果写入 `ALTAppGroups`，程序使用其中唯一的实际组名；空列表或多个组名会报告无法访问。出现错误时请记录原文和安装时对扩展的选项。可访问目录只证明当前进程能访问，两个方向的编号一致才证明共享成功。


## Actions 看似无响应时

先打开具体运行并区分以下状态，不要连续触发重复构建：

| 状态 | 含义和操作 |
| --- | --- |
| `Queued` 且没有步骤、没有 runner 名称 | GitHub 尚未分配机器。若注解提示 ARM64 容量不足，选择默认的 `macos-15-intel`。如果两个标准池都不可用，只能等待 GitHub 恢复，或使用另行配置且具有 Xcode 26.2 / iOS 26.2 的 Mac runner。Windows 无法本地执行原生 Xcode 归档。 |
| `In progress`，步骤持续推进 | runner 已工作。Intel 两次成功的完整模拟器步骤分别用时约 6 分 52 秒和 12 分 09 秒，包含编译、启动模拟器和测试，不代表测试本身运行了这么久。工作流有 25 分钟 job 超时。 |
| 红色失败且存在失败步骤 | 打开该步骤日志。运行 44309054436 的测试与归档都通过，但打包解析权限失败；已恢复 XML-only 导出语法。不要将这种脚本错误归咎于 runner 或云端域名规则。 |
| 成功运行但云端下载提示 Forbidden | 登录自己的 GitHub 浏览器，在运行页 Artifacts 下载；云端代理规则与用户浏览器网络分开。具体下载域名会变化，不能只验证 API 域名。 |

安装包只取成功运行中的 `KnowledgeStudio-resignable-ipa-*`，解压外层 ZIP 后导入 `.ipa`。日志和 xcresult 附件不能安装。当前 `codesign --entitlements :-` 的冒号弃用提示不导致失败；在替代方式经过实际工具链验证前保留该已验证导出路径。
