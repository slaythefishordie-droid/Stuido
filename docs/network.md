# 云环境网络诊断

2026-11-17，本次检查始终使用平台原有 HTTPS 代理与 CA，未关闭 TLS 验证、未替换代理、未修改生效网络策略。

| 地址 | 初始观察 | 最新 HTTPS 结果 |
|---|---|---|
| `github.com` | 仓库、Releases 可访问 | CONNECT 200，站点 200 |
| `api.github.com` | 代理 CONNECT 403，curl 56 | CONNECT 200，站点 200，仓库 API 可读 |
| `developer.android.com` | 初始未单独测试 | CONNECT 200，站点 200 |
| `developers.google.com` | 代理 CONNECT 403 | CONNECT 200，站点 200，IFrame API 和嵌入要求已读取 |

当前环境状态报告 `restricted` / `enforced`，自定义允许域名已经包含 `api.github.com`、`developer.android.com`、`developers.google.com`。这是环境提供的现状，不是本次代码修改的结果。`github.com`、`raw.githubusercontent.com`、发行资产域名等在既有 package_managers 预设内。

四个域名本机 `getaddrinfo` 均出现临时 DNS 失败，但继承代理的 HTTPS 均成功，TLS `ssl_verify_result=0`。代理负责目的地址解析；不能据此把本机 DNS 报错当成服务不可达或 TLS 故障。

## 区分错误层

- CONNECT 403、HTTP code 000、TLS 尚未建立：平台代理/策略拒绝，不是 GitHub 密码错误。
- TLS 验证失败通常对应 curl 60；本轮没有观察到。
- 目标站点 HTTP 401/403：检查响应权限说明。`GET /repos/.../actions/permissions` 返回 `Resource not accessible by integration`，是 GitHub 集成对管理接口权限不足；不证明 Actions 运行、Git push 或 API 全部不可用。
- Git read 与 GitHub API 读已经单独测试。变量仅检查名称/是否存在，未输出认证值。
- Public 仓库的页面可访问与 Private API 权限是不同事实。目标仓库实际 `private=false`，已由用户确认允许公开推送。

## 需要的白名单与手动设置

当前四个目标已通，无需重复添加。若在其他环境复现，增量加入 `api.github.com`（Actions 查询）、`developers.google.com`（YouTube 官方文档）；`developer.android.com` 仅用于跨平台官方资料检查，非 iPad App 构建必要依赖。保留既有域名，不用这些域名替换整份名单。

可选文档仍被当前策略阻止：`developer.apple.com`（Xcode/签名官方文档）、`docs.github.com`（Actions/额度）、`faq.altstore.io`（Classic 安装说明）。如需在此环境直接核对这些资料，请在环境设置的 Internet access 允许域名中增量加入这三个精确域名并保存，再重试。这里未声称已添加。

下载 `protocol-evidence-1` Artifact 时发现实际重定向目标 `productionresultssa4.blob.core.windows.net` 被平台拒绝；原生失败日志入口 `results-receiver.actions.githubusercontent.com` 也被拒绝。需要增量允许这两个精确域名，才能在当前云环境读取失败细节；它们与 `api.github.com` 的授权分开。已保留原有三项白名单并把这两项写入配置**草稿**，工具确认保存，但未应用当前网络、未发布。用户在环境设置审核保存并按界面发布后，需要重新测试访问。没有添加通配整个 Azure Storage 的权限，也没有把临时签名下载 URL 写入仓库。未来若 GitHub 使用不同的具体存储主机，再依据实际重定向补充。Windows 浏览器下载不使用本云环境白名单。

真实 YouTube 播放还需要 iPad 自身能访问 YouTube；云环境文档白名单不等于 iPad 网络可播放，也不等于 GitHub macOS Runner 的网络策略。
