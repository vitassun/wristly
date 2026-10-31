# MVP 验证记录

开发环境：Codex Cloud Linux，Node.js 24.19.0；没有 Xcode 或 Swift 编译器。

已在当前环境实际完成：

- `npm run check`：TypeScript 检查通过。
- `npm test`：17 项后端测试执行并全部通过，不含真实上游调用。
- `npm run build`：Wrangler 4.156.0 部署 dry run 成功；未发布到 Cloudflare。
- `wrangler dev --local`：真实 workerd 中 `/health` 200、无令牌 401、未配置模型 503、20 次请求后 Durable Object 返回 429。
- 依据 Apple SDK 头文件确认 AVAudioEngine/AVAudioConverter 在 watchOS 的可用性，移除不可用于 watchOS 的文字选择 API。
- 依据 GitHub 官方 runner-images 清单选择有 watchOS 27 SDK 的 `xcode-27` runner。

尚未验证：

- Swift 核心测试与 Watch App 编译需要 macOS/Xcode CI 实际执行；不能由 TypeScript 检查替代。
- 模型、Brave Search、豆包真实调用需要用户自己的 Secrets；协议单元测试不验证账号授权、供应商当前响应或真实录音。
- 真机签名、安装、权限、音频质量和小屏交互需要后续真机测试。

GitHub 推送、PR、Actions 执行结果以本次任务最终报告和真实远程记录为准，不能仅凭 workflow 文件宣称 CI 通过。
