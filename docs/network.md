# 云环境网络诊断

最新复查：2026-11-19（北京时间）。通过环境状态接口、真实 HTTPS 请求和 GitHub 日志 / Artifact 下载分别核实。始终使用平台原有 HTTPS 代理与 CA，不关闭 TLS 校验、不更改代理或绕过网络策略。

## 当前生效状态

11 月 18 日实例报告 `running`、`observations_current=true`、网络 `restricted/enforced`。11 月 19 日接口仍报告相同的 **8 条**自定义名单，但网络状态为 `unknown`，不能仅凭配置断言所有规则已生效；以具体请求结果为准：

```text
api.github.com
developer.android.com
developer.apple.com
developers.google.com
docs.swift.org
productionresultssa4.blob.core.windows.net
productionresultssa5.blob.core.windows.net
results-receiver.actions.githubusercontent.com
```

`package_managers` 预设保留，包含 GitHub 源码、发行资产及常用包管理器域名。配置草稿第 5 版有 **41 条**自定义规则，包含 `*.blob.core.windows.net`、`*.actions.githubusercontent.com`、`*.githubusercontent.com` 及项目文档 / YouTube 相关域名；草稿已保存不代表当前实例已应用。完整两份名单与实测记录见 [本轮网络证据](verification/network-recheck-2026-11-18.json)。

11 月 19 日已下载运行 `44309054436` 的完整日志；其测试附件仍被 `productionresultssa17.blob.core.windows.net` 拒绝。最新成功运行 `44432216488` 的完整日志同样下载成功，但 IPA 与测试附件被 `productionresultssa31.blob.core.windows.net` 拒绝。已有草稿的 `*.blob.core.windows.net` 包含这两个目标，但不能据此宣称当前连接已放行。见 [最新状态](verification/network-recheck-2026-11-19.json)和[成功运行下载证据](verification/native-run-44432216488.json)。

## 11 月 18 日实测结果

| 请求 | 结果 | 能说明什么 |
| --- | --- | --- |
| `github.com`、`api.github.com`、`developer.apple.com`、`docs.swift.org` | HTTPS 200 | 这些入口可访问；GitHub API 可查询构建、重试和手动触发工作流 |
| `docs.github.com`、`developer.mozilla.org`、`altstore.io`、`youtube.com` | CONNECT 403，curl 56 / HTTP 000 | 代理拒绝连接，尚未开始目标 TLS；不是目标站点账户错误 |
| `productionresultssa18.blob.core.windows.net`、`productionresultssa30.blob.core.windows.net` | CONNECT 403 | 草稿中的新增存储规则仍未在此实例生效 |
| 原生运行 `44245690553`、`44244882996` 的完整日志 ZIP | 下载成功，ZIP CRC 通过 | 这两条实际日志下载路径已可用，已读日志核实测试和旧错误 |
| 运行 `44245690553` 的 IPA 和测试 Artifact | 下载被拒，跳转主机为 `productionresultssa18.blob.core.windows.net` | 日志可下载不意味着附件也可下载 |
| 第一版 `v0.1.0` 的 IPA Artifact `14394892490` | 下载被拒，跳转主机为 `productionresultssa16.blob.core.windows.net` | 存储主机会随产物变化；已保存的通配规则覆盖该主机，但运行实例尚未应用 |

日志复核与下载结果见 [本轮日志证据](verification/log-review-2026-11-18.json)。不把一次入口请求成功推广为所有子域名、重定向或 App 真机网络都可用。

## 如何应用已经保存的规则

在环境设置的 Internet access 中保留现有规则和 `package_managers` 预设，审阅、保存草稿，然后发布环境配置，并确认后续任务连接到该配置版本。当前代理工具可以读配置和保存草稿，不提供发布或直接切换运行实例配置的操作；不能通过重新保存同一草稿宣称规则已经生效。

新的实例连接后，检查生效名单是否包含新增域名，再重试真实日志和 IPA 下载。不要只凭草稿列表或环境启动成功作判断。`*.blob.core.windows.net` 可覆盖变化的 GitHub Actions 存储主机，同时也放行该域下其他 Azure 存储站点。

如果暂时无法更新此云实例，可以在自己的浏览器登录 GitHub，从成功运行的 Artifacts 下载。该浏览器不使用本云环境的代理规则。[IPA 下载和安装](build-and-install.md)

## 区分其他失败

- GitHub API 返回 `Resource not accessible by integration`：对应接口权限不足，不等于网络不可达。源码读取、工作流触发和管理接口权限要分别验证。
- GitHub 注解 `The job was not acquired by Runner of type hosted even after multiple attempts`：托管 runner 调度失败，与本云环境白名单无关；尚未执行的测试不能算失败或通过。工作流现在提供标准 Intel runner 手动备选。
- 本机 DNS 查询失败不等于代理请求失败，保持平台提供的代理和 CA 配置。
- iPad 播放 YouTube、AltStore 免费重签、Safari 识别和 App Groups 共享均需用户设备单独验证，云端 HTTPS 成功不能替代这些结果。

早期网络和构建记录保留在 [进度历史](progress.md) 与 [早期网络证据](verification/network-2026-11-18.json)；以本文件和本轮证据判断当前状态。
