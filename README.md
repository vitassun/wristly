# Wristly

Apple Watch 上的私人 AI 聊天客户端。原生 SwiftUI，最低 **watchOS 27.0**；Cloudflare Workers 后端；默认 DeepSeek，也支持其他 OpenAI-compatible Chat Completions 接口，搭配 Tavily Search 和火山引擎豆包流式语音识别。

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

手表通过 HTTPS `/chat` 接收 SSE，通过 WSS `/asr` 将 16 kHz、16 bit、小端单声道 PCM 实时发往 Worker，Worker 转发到豆包官方一句话识别 2.0 接口。结束录音后返回整段识别结果，不要求边录边出字。识别文本不会自动发送给模型，需要在手表确认或编辑后再发送。系统文字输入同时使用 watchOS 提供的键盘、听写等能力，具体可用方式由设备、语言和系统决定。

模型自主选择是否调用唯一工具 `web_search`。Worker 最多执行一次 Tavily 搜索，再把结果作为 tool message 交给模型生成回答，返回最多 5 个来源。兼容接口必须支持 **streaming Chat Completions + function tool calls**；仅提供文字补全的接口不满足搜索要求。没有配置搜索 Key 时会明确告知模型无法查询实时信息。

## 配置与部署后端

需要 Node.js 24+、Cloudflare Workers 账号（启用 SQLite Durable Objects），以及自己的模型、Tavily、火山引擎语音服务权限。部署会创建 Worker 和用于计数的 Durable Object；需要在自己的 Cloudflare 账号操作。

```sh
cd Backend
npm ci
npx wrangler login
```

在 `wrangler.toml` 设置非秘密配置：

| 配置 | 含义 |
| --- | --- |
| `LLM_BASE_URL` | HTTPS API 根地址，默认 `https://api.deepseek.com`；代码会追加 `/chat/completions` |
| `LLM_MODEL` | 默认 `deepseek-flash`；可更换为支持流与工具调用的模型 ID |
| `ASR_RESOURCE_ID` | 默认 2.0 小时版资源 `volc.seedasr.sauc.duration`；必须与实际授权一致 |
| `ALLOW_UNAUTHENTICATED` | 默认字符串 `"true"`，允许不填私人访问令牌；仍保留全局限流。配置 `APP_ACCESS_TOKEN` 后优先要求鉴权 |

DeepSeek 官方主机使用 `thinking: { type: "disabled" }` 非思考模式，适合 Watch 的短回答，并让搜索后的工具结果可以直接继续生成。其他兼容接口不发送这个 DeepSeek 专用参数。当前模型名称与参数参考 [DeepSeek 官方快速开始](https://api-docs.deepseek.com/quick_start) 和 [Chat Completions 文档](https://api-docs.deepseek.com/api/create-chat-completion)。

### Cloudflare 网页配置：先让文字聊天可用

进入 `Workers & Pages → wristly → Settings → Variables and Secrets`。这里配置的是 Worker 运行时使用的参数：普通变量（Variable）保存公开设置，秘密变量（Secret）保存密码或密钥。构建页面里的 `NODE_VERSION=24` 是另一处设置，仅用于安装和打包。

先添加 **Secret** `LLM_API_KEY`，保存并部署，即可开始测试 DeepSeek 文字聊天。默认不需要生成或填写私人访问令牌：

| 名称 | 值从哪里来 |
| --- | --- |
| `LLM_API_KEY` | 在 [DeepSeek 开放平台](https://platform.deepseek.com/) 的 API Keys 页面创建；API 账户需有可用额度，不能用聊天网站的登录密码 |
| `SEARCH_API_KEY` | [Tavily 控制台](https://app.tavily.com/) 创建的 Key，用于联网搜索，可以稍后添加 |
| `ASR_API_KEY` | [火山引擎语音 API Key 管理](https://console.volcengine.com/speech/new/setting/apikeys?projectName=default) 创建的 Key，需已开通对应语音资源，可以稍后添加 |

`LLM_BASE_URL` 与 `LLM_MODEL` 已由仓库中的 `wrangler.toml` 配好，不用再在网页重复填写。修改这两项时请改仓库，以免下次 Git 部署覆盖网页修改。

关于搜索与语音凭据：

- `SEARCH_API_KEY` 来自 [Tavily 控制台](https://app.tavily.com/)，是给模型查网页用的服务，API Key 通常以 `tvly-` 开头。没有它时仍可聊天，但不能联网搜索。
- 豆包新控制台使用单个 `ASR_API_KEY`，通过 `X-Api-Key` 请求头鉴权，不需要 APP ID。需开通一句话识别 2.0 对应资源；未配置时仅豆包语音入口不可用，系统文字输入仍可用。
- 同时兼容旧控制台的 `ASR_APP_ID` + `ASR_ACCESS_TOKEN` 组合；这两项来自同一个语音应用。新接入优先使用单个 API Key，已配置 `ASR_API_KEY` 时忽略旧组合。
- 如果以前填写过 `APP_ACCESS_TOKEN`，要使用免令牌模式，需在 Worker 运行时 Secrets 删除这一项并部署；手表上的令牌可以留空。免令牌模式下，知道 Worker 地址的人可使用你的服务并消耗 API 额度，限流不能代替鉴权。

通过交互命令保存 Secrets，**不要把真实值写进代码、命令历史、GitHub 或客户端**：

```sh
npx wrangler secret put LLM_API_KEY
npx wrangler secret put SEARCH_API_KEY
npx wrangler secret put ASR_API_KEY
npm run deploy
```

- `APP_ACCESS_TOKEN`：可选。需要恢复私人鉴权时才设置高熵令牌（32–256 字节），手表填写相同值。缺少令牌且 `ALLOW_UNAUTHENTICATED` 未设为字符串 `"true"` 时，后端拒绝业务请求，避免意外公开。
- `SEARCH_API_KEY`：Tavily Search API 的 Key，通过 Bearer 鉴权发送至 `api.tavily.com`。使用 basic 搜索、最多 5 个结果，不调用 Tavily 的额外答案生成功能。可不配置，此时联网功能不可用。
- `ASR_API_KEY`：豆包语音控制台生成的 API Key，对应 `X-Api-Key`，不是火山引擎账号 AK/SK。需开通豆包一句话识别 2.0 并授权资源。
- 语音目的地为 `openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream`。使用官方 API，不使用豆包输入法接口。接口及凭据参考：[一句话识别官方文档](https://www.volcengine.com/docs/doubao-voice/unidirectional-streaming-automatic-speech-recognition-websocket?lang=zh)、[API Key 使用](https://www.volcengine.com/docs/doubao-voice/api-key-usage?lang=zh)。

Workers 默认出站联网即可访问上述服务。若运行开发或部署命令的环境限制网络，需要放行 npm、Cloudflare API，以及你配置的模型主机、`api.tavily.com`、`openspeech.bytedance.com`。不要关闭 TLS、签名或校验。

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

项目定义生成的是独立 watchOS App，无需 iPhone companion。首次打开时，在“连接”页面输入 Worker HTTPS 根地址，私人令牌默认留空；如后端启用了私人鉴权再填写。可选令牌存在本机 Keychain，地址存在 UserDefaults。模型、搜索和语音 API Key 永远不进入 App。

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

- 仓库默认明确启用免令牌模式，适用于不想在手表填写私人令牌的部署。地址可被他人调用并消耗上游额度。设置 `APP_ACCESS_TOKEN` 可恢复私人鉴权；配置后会拒绝缺失/过短/错误令牌。不会在 URL、日志或响应中传递密钥。
- 持久化全局限流：20 次开始请求/分钟、300 次/UTC 日，聊天和 ASR 共用。私人部署可在 `RateLimiter` 中调整；令牌泄露时应在 Worker 和手表中同时轮换。此共享令牌适合私人使用，不是多用户账户系统。
- 客户端最多保留当前会话 60 条消息，写入受系统文件保护的本机文件；新建对话覆盖为空。发送最近最多 24 条、合计 24,000 UTF-16 单元；单条最多 8,000。失败的 AI 半截回答不加入下一次上下文。后端再次验证、截断。
- Workers 不保存聊天或音频；Durable Object 只存计数。上游模型、Tavily 和火山引擎仍会接收请求内容，保留政策以各服务条款为准。
- Worker 限制请求体、模型轮数、回答长度、音频字节和超时；客户端取消会关闭语音或模型连接。后台运行不在 MVP 目标内。

## 后续真机安装（本阶段不包含）

在自己的 Mac 上生成并打开项目，选择 Apple Developer Team、修改 Bundle Identifier、配置 watchOS 签名和已配对的真机，再从 Xcode 安装。需要 watchOS 27+。模拟器产物不能直接安装到手表；分发需要单独的签名设备构建。本阶段未配置证书、Provisioning Profile、TestFlight 或自动真机部署。

真机验收需覆盖：中文/英文系统输入、麦克风权限拒绝、60 秒录音、取消、真实豆包最终识别、文字确认、模型连续追问、实时搜索与来源、断网、退后台、长回答滚动、新建对话后不继承上下文。上游凭证缺失前不能声称这些端到端验收已通过。
