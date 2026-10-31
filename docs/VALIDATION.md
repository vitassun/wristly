# MVP 验证记录

部署后文字聊天检查发现：`/health` 返回 200，但有效聊天请求只返回通用 SSE 错误。在本地真实 workerd 中重现并确认，模型、搜索和语音请求使用的 `redirect: "error"` 不受 Workers 支持，抛出 TypeError，模型请求尚未发出。

修复改为 `redirect: "manual"`，继续通过 HTTP 状态/语音 101 状态判断成功，拒绝跟随重定向。新增 4 项 workerd 运行时回归测试，执行部署 bundle，覆盖文字回答、Tavily 工具往返、模型重定向拒绝、搜索重定向拒绝；本地全部通过，并加入 CI。测试使用隔离服务，无真实 API Key。线上文字聊天需部署此修复后再次验证；豆包语音按用户要求暂缓真实联调。

后续配置调整（PR #2）：默认 DeepSeek + Tavily；豆包改为一句话识别 2.0（`bigmodel_nostream`、`volc.seedasr.sauc.duration`），支持新控制台单个 `ASR_API_KEY`。按用户要求显式启用免私人令牌模式，保留全局限流；配置 `APP_ACCESS_TOKEN` 后仍要求私人鉴权。公开地址可被他人调用并消耗上游额度。

该调整已在 Linux 上通过 TypeScript 检查、20 项后端测试及 Wrangler dry run；新增 Watch 请求测试覆盖免令牌与私人令牌两种请求方式。以下原始 MVP 的 CI 记录保留作历史证据，最新构建结果以 PR 检查为准。真实上游调用仍需用户配置密钥验证。

开发环境：Codex Cloud Linux，Node.js 24.19.0；没有 Xcode 或 Swift 编译器。

已在当前环境实际完成：

- `npm run check`：TypeScript 检查通过。
- `npm test`：17 项后端测试执行并全部通过，不含真实上游调用。
- `npm run build`：Wrangler 4.156.0 部署 dry run 成功；未发布到 Cloudflare。
- `wrangler dev --local`：真实 workerd 中 `/health` 200、无令牌 401、未配置模型 503、20 次请求后 Durable Object 返回 429。
- 依据 Apple SDK 头文件确认 AVAudioEngine/AVAudioConverter 在 watchOS 的可用性，移除不可用于 watchOS 的文字选择 API。
- 依据 GitHub 官方 runner-images 清单选择有 watchOS 27 SDK 的 `xcode-27` runner。
- 已推送提交 `f61c756`；[GitHub Actions #1](https://github.com/vitassun/wristly/actions/runs/41216463868) 总状态 **Success**。后端任务 20 秒、Watch 任务 1 分 21 秒，包含 Swift 核心测试和无需签名的 Watch 模拟器构建，上传 `backend-validation` 与 `watch-build-and-logs` 两个产物。
- CI 状态和产物由公开 Actions 页面确认；当前 API 访问被拒绝，无法下载需要登录的原始日志/产物。页面仅显示 Node action runtime 弃用提示与 Ubuntu 镜像迁移提示。

尚未验证：

- 模型、Brave Search、豆包真实调用需要用户自己的 Secrets；协议单元测试不验证账号授权、供应商当前响应或真实录音。
- 真机签名、安装、权限、音频质量和小屏交互需要后续真机测试。

PR 创建已尝试，GitHub API `POST /graphql` 返回 Forbidden，未创建成功。Git 推送授权可用不代表 API 写入授权可用。PR 正文准备在 [PULL_REQUEST.md](PULL_REQUEST.md)，恢复 API 权限后可用 `gh pr create --base main --head feat/wristly-mvp --title 'feat: standalone watchOS AI chat MVP' --body-file docs/PULL_REQUEST.md` 创建。
