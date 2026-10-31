# MVP 验证记录

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
