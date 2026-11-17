# 开发进度与验证记录

## 2026-11-17 · 阶段 0

起点：仓库 `a4c48fc26db834045e8bd9a681ff7aa95de96255` 只有 README，无工程、AGENTS.md 或现有依赖。选择 SwiftUI，最低 iPadOS 17，Swift 6 语言模式；当前用户设备 iPadOS 26.2。用户只有 Windows 和 iPad，使用免费 Apple 账户及 AltStore Classic。

完成内容：

- 保存原始需求、独立状态/对象模型、版本和事务约定、依赖评估、ChatGPT 提示词。
- Draft 2020-12 Schema 与共享校验入口；四类内容、字段 provenance、Source/Relation 引用、具体错误、重复批次和内容预览；未实现正式导入事务或 AI Inbox UI。
- SwiftUI YouTube 最小工程，固定 SPM 版本；原生 Mark/时间回跳/最近视频/原子原型存储/失败提示/超时/会话隔离。未扩展 PDF、EPUB、图谱等复杂界面。
- macOS 15 + Xcode 26.2 Actions，核心测试、iPad 模拟器测试、真实 iphoneos archive、未签名 IPA 结构校验、日志/xcresult/产物上传与独立结果记录。
- 网络诊断：四个目标域名 HTTPS 200/TLS 校验通过；平台提供的当前白名单已含 API 和 Google 开发文档。没有关闭验证或改写代理。

## 当前验证证据

| 检查 | 结果 | 范围 |
|---|---|---|
| Swift 核心 | 8/8 通过 | Linux Swift 6.2.1，真实文件读写和异步竞态；非 iOS 运行验证 |
| 导入协议 | 25/25 通过 | Node.js 24.22.1，Schema/语义/重复/错误/边界；没有写正式数据库 |
| swift-fsrs v6.0.0 上游 | 105/105 通过，24 suites | Linux Swift Testing；App 尚未接入复习 |
| 工作流静态检查 | actionlint 1.7.12 通过 | 不等于 GitHub Runner 已执行 |
| Shell 语法 | bash -n 通过 | 不等于 macOS 打包成功 |
| GitHub 协议 CI | 成功 | [run 44077240571](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44077240571)，commit `e9b42987189de313ec85f026c6b6b6acd4bf8b9c`，日志 Artifact 已上传 |
| 原生 CI 的 SPM / 核心测试 | 成功 | [run 44077503279](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44077503279)，commit `eac8adb4dfd3d00ac6782d7c5aee268ded4ff64a`；实际 macos-15-intel / Xcode 26.2 |
| 原生 App 编译与模拟器测试 | 成功 | 同次 CI 的 simulator 步骤通过，强制断言至少 10 个测试、0 失败；包含 8 个核心和 2 个 App 测试 |
| device archive | 命令成功 | generic/platform=iOS Release archive 通过；后续 IPA 校验尚未通过 |
| unsigned IPA 打包校验 | **失败，待日志诊断** | IPA 未上传；构建证据 Artifact `KnowledgeStudio-build-evidence-2` 已上传。未把普通归档称为可安装包 |
| AltStore 重签安装 | 未执行 | 必须用用户实际设备验证 |
| iPad 真实播放/Mark/回跳/恢复 | 未执行 | 见 device-validation.md |

工具链来源：官方 Swift 6.2.1 Ubuntu 24.04 tarball，在 Debian 13 可运行；GPG 验证通过，签名指纹 `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`，密钥从 swiftlang 官方仓库通过 TLS 获取。缓存通过脚本指定到可写 `.build`，未改 HOME 或系统 CA。

## 当前限制与下步

1. 优先修复 IPA 打包校验：当前云环境访问 Artifact 的 `productionresultssa4.blob.core.windows.net` 和日志的 `results-receiver.actions.githubusercontent.com` 被策略拒绝。已将两个精确域名增量保存到网络配置草稿，**尚未应用/发布**；需要用户在环境设置保存并发布后，重新核实状态并读取失败日志。不要无依据修改校验来放行产物。
2. 阶段 0 只有 YouTube 纵向原型；没有虚构 Today/Library/Dictionary 等已实现页面。严格导入工具可执行，但原生 JSONSchema 适配层、Source 匹配 UI 与数据库事务仍属阶段 2。
3. 通过 CI 后，请用户下载未签名 IPA 在 AltStore Classic 重签，并按真机清单报告实际结果；CI 不需要 Apple 密码、证书或签名密钥。
4. 原生构建流程确认后进入阶段 1：数据库迁移、原型 Mark 迁入、回收站、备份恢复与失败回滚。继续保留所有稳定 ID 与原始秒数，不清空原型文件。
5. 待产品体验后决定复习正反面；提案在 data-model.md，可调整。FSRS 日界与用户时区差异在依赖评估中记录。

仓库实际为 Public，用户已明确授权推送和运行；未改变可见性。当前工作流不需要 Actions 管理接口的写权限，管理接口 403 不应被误判成网络不可达。

首次 native run 44075633839 在 `macos-15` 队列中等待，后由并发策略取消。发现该标签目前对应 ARM64、先前核对的镜像清单对应 Intel，因此固定为官方标准 `macos-15-intel` 后实际运行成功进入编译。没有使用付费 larger runner；不把标签差异直接断言为排队根因。
