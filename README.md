# Wristly

Apple Watch 上的私人 AI 聊天客户端。原生 SwiftUI，最低 **watchOS 27.0**；Cloudflare Workers 后端；OpenAI-compatible Chat Completions 流、Brave Search 和火山引擎豆包流式语音识别。

第一版只做文字聊天、联网搜索、系统文字输入、豆包语音输入和当前会话。不包含 TTS、账号、付费、长期记忆或其他 Agent 工具。

## 目录与工作方式

```text
WatchApp/          SwiftUI App、PCM 录音、Keychain、流式网络、本地会话
Backend/           TypeScript Worker、SSE、搜索、豆包 WebSocket、限流 DO
Tests/             可独立运行的 Swift 核心逻辑测试
project.yml        XcodeGen 项目定义（生成 Wristly.xcodeproj）
scripts/           SDK 检查和无需签名的构建脚本
.github/workflows/ Push / Pull Request / 手动 CI
```

手表通过 HTTPS `/chat` 接收 SSE，通过 WSS `/asr` 将 16 kHz、16 bit、小端单声道 PCM 实时发往 Worker，Worker 转发到豆包官方流式接口。识别文本不会自动发送给模型，需要在手表确认或编辑后再发送。系统文字输入同时使用 watchOS 提供的键盘、听写等能力，具体可用方式由设备、语言和系统决定。

模型自主选择是否调用唯一工具 `web_search`。Worker 最多执行一次 Brave 搜索，再把结果作为 tool message 交给模型生成回答，返回最多 5 个来源。兼容接口必须支持 **streaming Chat Completions + function tool calls**；仅提供文字补全的接口不满足搜索要求。没有配置搜索 Key 时会明确告知模型无法查询实时信息。

## 配置与部署后端

需要 Node.js 24+、Cloudflare Workers 账号（启用 SQLite Durable Objects），以及自己的模型、Brave Search、火山引擎语音服务权限。部署会创建 Worker 和用于计数的 Durable Object；需要在自己的 Cloudflare 账号操作。

```sh
cd Backend
npm ci
npx wrangler login
```

在 `wrangler.toml` 设置非秘密配置：

| 配置 | 含义 |
| --- | --- |
| `LLM_BASE_URL` | HTTPS API 根地址，默认 `https://api.openai.com/v1`；代码会追加 `/chat/completions` |
| `LLM_MODEL` | 支持流与工具调用的模型 ID |
| `ASR_RESOURCE_ID` | 豆包已开通的资源 ID，默认按时长计费 `volc.bigasr.sauc.duration`；必须与实际授权一致 |

通过交互命令保存 Secrets，**不要把真实值写进代码、命令历史、GitHub 或客户端**：

```sh
npx wrangler secret put APP_ACCESS_TOKEN
npx wrangler secret put LLM_API_KEY
npx wrangler secret put SEARCH_API_KEY
npx wrangler secret put ASR_APP_ID
npx wrangler secret put ASR_ACCESS_TOKEN
npm run deploy
```

- `APP_ACCESS_TOKEN`：自己生成的高熵私人访问令牌，例如用密码管理器生成 64 位随机十六进制字符串（32–256 字节）。手表中输入相同值。它只是你的后端访问凭据，不是任何上游 API Key。
- `SEARCH_API_KEY`：Brave Search Web Search API 的订阅 Key，发送至 `api.search.brave.com`。可不配置，此时联网功能不可用。
- `ASR_APP_ID`：火山引擎语音应用的 APP ID，对应上游 `X-Api-App-Key` 头。
- `ASR_ACCESS_TOKEN`：该语音应用的 Access Token，对应 `X-Api-Access-Key`；不是火山引擎账号 AK/SK。需在控制台开通豆包流式语音识别并授权资源。
- 语音目的地为 `openspeech.bytedance.com/api/v3/sauc/bigmodel`。使用官方 API，不使用豆包输入法接口。

Workers 默认出站联网即可访问上述服务。若运行开发或部署命令的环境限制网络，需要放行 npm、Cloudflare API，以及你配置的模型主机、`api.search.brave.com`、`openspeech.bytedance.com`。不要关闭 TLS、签名或校验。

本地开发：复制 `Backend/.dev.vars.example` 为 `.dev.vars`，只在本机填写；它已被 Git 忽略。运行 `npm run dev`。Watch 客户端要求 HTTPS，连接本地 Worker 时请使用自己可信的 HTTPS 开发地址，不要提交隧道凭证或关闭 ATS。

部署后先验证 `/health` 返回 `{"status":"ok"}`。它仅代表 Worker 在线，不代表上游密钥有效。模型、搜索和语音必须用实际 Secrets 分别验证。

## 构建 Watch App

需要 macOS、**Xcode 27+（含 watchOS 27 SDK）**、XcodeGen 2.44.1+：

```sh
brew install xcodegen
xcodegen generate
open Wristly.xcodeproj
# 或执行 CI 相同的核心测试与无需签名构建
bash scripts/build-watch.sh
```

项目定义生成的是独立 watchOS App，无需 iPhone companion。首次打开时，在“连接”页面输入 Worker HTTPS 根地址和私人令牌。令牌存在本机 Keychain，地址存在 UserDefaults。模型、搜索和语音 API Key 永远不进入 App。

文字输入后点击发送；麦克风入口打开语音页，点击开始录音、结束录音，再点“使用文字”回到输入框，确认后发送。录音最长 60 秒，取消、退到后台、音频中断都会释放麦克风和连接。失败可重录。模型生成可停止或重试，新建对话会取消旧请求并清除本机上下文。基础 Markdown 支持强调、行内代码和链接，保留换行；不提供完整表格或 HTML 排版。

## CI 与验证

每次 Push 和 Pull Request 会运行：

1. Ubuntu：`npm ci`、TypeScript 类型检查、Node 测试、Workers 部署 dry run；**不发布后端，不需要生产 Secrets**。
2. 官方 `xcode-27` 预览 runner：选择 `/Applications/Xcode_27.app`，验证 watchOS Simulator SDK ≥ 27，执行 Swift 核心测试，生成 Xcode 项目，以 `CODE_SIGNING_ALLOWED=NO` 构建 watchOS Simulator App。
3. 上传测试日志、SDK 信息、`.xcresult`、生成的项目和模拟器 `.app` zip。构建日志保留真实失败退出状态。

GitHub 官方镜像说明：[Xcode 27 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)。预览 runner 的可用性由 GitHub 决定；若仓库无法使用，可在仓库 Actions Variables 设置 `WATCHOS_RUNNER` 为装有相同 Xcode 路径和 watchOS 27 SDK 的 runner 标签。没有兼容 SDK 时 CI 会报错，不降级验证。

本地后端验证：

```sh
cd Backend
npm ci
npm run check
npm test
npm run build
```

测试覆盖 UTF-8 分帧、SSE 截断、工具调用分片与来源、上游错误、消息大小和上下文边界、鉴权、限流以及豆包二进制/压缩响应。它们用明确的测试桩隔离收费上游，不代表真实模型、搜索或豆包账号已连通。

当前执行证据及未验证项见 [docs/VALIDATION.md](docs/VALIDATION.md)。**未签名模拟器构建不等于真机安装或录音验证。**

## 数据与访问控制

- 后端默认拒绝缺失/过短令牌，鉴权在代理上游之前进行；不在 URL、日志或响应中传递密钥。
- 持久化全局限流：20 次开始请求/分钟、300 次/UTC 日，聊天和 ASR 共用。私人部署可在 `RateLimiter` 中调整；令牌泄露时应在 Worker 和手表中同时轮换。此共享令牌适合私人使用，不是多用户账户系统。
- 客户端最多保留当前会话 60 条消息，写入受系统文件保护的本机文件；新建对话覆盖为空。发送最近最多 24 条、合计 24,000 UTF-16 单元；单条最多 8,000。失败的 AI 半截回答不加入下一次上下文。后端再次验证、截断。
- Workers 不保存聊天或音频；Durable Object 只存计数。上游模型、Brave 和火山引擎仍会接收请求内容，保留政策以各服务条款为准。
- Worker 限制请求体、模型轮数、回答长度、音频字节和超时；客户端取消会关闭语音或模型连接。后台运行不在 MVP 目标内。

## 后续真机安装（本阶段不包含）

在自己的 Mac 上生成并打开项目，选择 Apple Developer Team、修改 Bundle Identifier、配置 watchOS 签名和已配对的真机，再从 Xcode 安装。需要 watchOS 27+。模拟器产物不能直接安装到手表；分发需要单独的签名设备构建。本阶段未配置证书、Provisioning Profile、TestFlight 或自动真机部署。

真机验收需覆盖：中文/英文系统输入、麦克风权限拒绝、60 秒录音、取消、真实豆包最终识别、文字确认、模型连续追问、实时搜索与来源、断网、退后台、长回答滚动、新建对话后不继承上下文。上游凭证缺失前不能声称这些端到端验收已通过。
