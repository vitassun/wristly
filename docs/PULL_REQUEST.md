实现可独立运行的 watchOS 27 AI 聊天 MVP 和 Cloudflare Workers 后端。手表支持系统文字输入、流式文字回答、基础 Markdown、本机会话、新建对话，以及豆包流式语音识别后编辑确认发送。所有上游 API 密钥只在 Worker 中配置，手表的私人访问令牌保存到 Keychain。

后端支持可配置 OpenAI-compatible Chat Completions、单轮 Brave Search 工具和来源链接、豆包官方 WebSocket 协议桥接。加入持久化私人限流、输入/上下文边界、取消和超时处理。使用 XcodeGen 生成独立 Watch App；CI 在 push/PR 构建并上传日志和模拟器产物。

验证：

- TypeScript 类型检查、17 项后端测试和 Wrangler 部署 dry run 在 Codex Linux 上通过。
- 真实本地 workerd 验证健康检查、鉴权、缺失服务配置以及 Durable Object 限流。
- [GitHub Actions #1](https://github.com/vitassun/wristly/actions/runs/41216463868) 通过后端任务、Swift 核心测试和 Xcode 27 无签名 Watch 模拟器构建，上传两份产物。

用户仍需配置 Worker Secrets 并部署。真实模型/搜索/豆包调用、真机录音、签名和安装尚未验证；没有使用测试桩冒充真实服务。配置、部署与后续真机验收见 README。
