import { APIError, type Env } from "./types.ts";
import { decodeFrame, frame, initFrame } from "./asr-protocol.ts";

export function asrConnection(env: Env): { url: string; headers: Record<string, string> } {
  const id = crypto.randomUUID();
  const headers: Record<string, string> = {
    Upgrade: "websocket", "X-Api-Resource-Id": env.ASR_RESOURCE_ID,
    "X-Api-Request-Id": id, "X-Api-Connect-Id": id
  };
  if (env.ASR_API_KEY) headers["X-Api-Key"] = env.ASR_API_KEY;
  else if (env.ASR_APP_ID && env.ASR_ACCESS_TOKEN) {
    headers["X-Api-App-Key"] = env.ASR_APP_ID;
    headers["X-Api-Access-Key"] = env.ASR_ACCESS_TOKEN;
  } else throw new APIError(503, "尚未配置豆包语音 API Key");
  return { url: "https://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream", headers };
}

export async function asr(env: Env): Promise<Response> {
  const config = asrConnection(env);
  const response = await fetch(config.url, {
    headers: config.headers, signal: AbortSignal.timeout(10_000), redirect: "error"
  });
  const upstream = response.webSocket;
  if (response.status !== 101 || !upstream) throw new APIError(502, "无法连接豆包语音服务，请检查后端配置");
  const pair = new WebSocketPair();
  const [client, server] = [pair[0], pair[1]];
  upstream.accept(); server.accept();
  let closed = false, ended = false, bytes = 0;
  let queue = Promise.resolve();
  const close = () => {
    if (closed) return;
    closed = true; clearTimeout(deadline);
    try { upstream.close(1000, "Finished"); } catch { /* already closed */ }
    try { server.close(1000, "Finished"); } catch { /* already closed */ }
  };
  const send = (data: unknown) => { if (!closed) server.send(JSON.stringify(data)); };
  const fail = (message: string) => { send({ type: "error", message }); close(); };
  const deadline = setTimeout(() => fail("语音会话超时（最长录音 60 秒）"), 75_000);
  upstream.addEventListener("message", e => {
    queue = queue.then(async () => {
      if (closed) return;
      if (!(e.data instanceof ArrayBuffer)) throw new Error("Nonbinary upstream");
      const result = await decodeFrame(e.data);
      if (result.text !== undefined) send({ type: "transcript", text: result.text, final: result.final });
      if (result.final) { send({ type: "done" }); close(); }
    }).catch(error => fail(error instanceof APIError ? error.message : "语音响应格式错误"));
  });
  upstream.addEventListener("error", () => fail("语音网络连接失败"));
  upstream.addEventListener("close", () => {
    void queue.then(() => { if (!closed) fail("语音连接提前关闭，请重试"); });
  });
  server.addEventListener("message", e => {
    if (closed) return;
    try {
      if (e.data instanceof ArrayBuffer) {
        bytes += e.data.byteLength;
        if (ended || e.data.byteLength === 0 || e.data.byteLength > 32_000 || e.data.byteLength % 2 || bytes > 1_920_000) {
          fail("录音过长或音频格式错误"); return;
        }
        upstream.send(frame(2, 0, new Uint8Array(e.data)));
      } else if (e.data === "end" && !ended) {
        ended = true; upstream.send(frame(2, 2, new Uint8Array()));
      } else if (e.data === "cancel") close();
      else fail("无效语音控制消息");
    } catch { fail("语音发送失败"); }
  });
  server.addEventListener("close", close);
  server.addEventListener("error", close);
  upstream.send(initFrame());
  send({ type: "ready" });
  return new Response(null, { status: 101, webSocket: client });
}
