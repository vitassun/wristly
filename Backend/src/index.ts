import { APIError, type Env } from "./types.ts";
import { readJSON } from "./http.ts";
import { chat, history } from "./chat.ts";
import { asr } from "./asr.ts";

export async function authorized(request: Request, token?: string): Promise<boolean> {
  if (!token || token.length < 32) return false;
  const supplied = request.headers.get("Authorization") ?? "";
  if (supplied.length > 300) return false;
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([`Bearer ${token}`, supplied].map(s => crypto.subtle.digest("SHA-256", encoder.encode(s))));
  const aa = new Uint8Array(a), bb = new Uint8Array(b);
  let difference = 0;
  for (let i = 0; i < aa.length; i++) difference |= aa[i] ^ bb[i];
  return difference === 0;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const path = new URL(request.url).pathname;
      if (path === "/health" && request.method === "GET") return Response.json({ status: "ok" });
      if (env.APP_ACCESS_TOKEN) {
        if (!await authorized(request, env.APP_ACCESS_TOKEN)) throw new APIError(401, "访问令牌无效");
      } else if (env.ALLOW_UNAUTHENTICATED !== "true") {
        throw new APIError(503, "尚未配置访问方式");
      }
      if (!((path === "/chat" && request.method === "POST") || (path === "/asr" && request.method === "GET"))) {
        throw new APIError(404, "接口不存在");
      }
      const id = env.RATE_LIMITER.idFromName("private-owner");
      const limit = await env.RATE_LIMITER.get(id).fetch("https://limiter/check", { method: "POST" });
      if (!limit.ok) return new Response(limit.body, { status: 429, headers: { "Content-Type": "application/json", "Retry-After": "60" } });
      if (path === "/chat") {
        if (!env.LLM_API_KEY || !env.LLM_MODEL) throw new APIError(503, "尚未配置模型服务");
        return chat(history(await readJSON(request)), env, request.signal);
      }
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") throw new APIError(426, "需要 WebSocket");
      return await asr(env);
    } catch (error) {
      return Response.json({ error: error instanceof APIError ? error.message : "后端服务暂不可用" },
        { status: error instanceof APIError ? error.status : 502, headers: { "Cache-Control": "no-store" } });
    }
  }
};

// Persistent, global private-use budget: 20 starts/minute and 300/day, including ASR.
// Only counters are stored; conversation and audio are never persisted on the Worker.
export class RateLimiter {
  state: DurableObjectState;
  constructor(state: DurableObjectState) { this.state = state; }
  async fetch(): Promise<Response> {
    const now = Date.now(), minute = Math.floor(now / 60_000), day = Math.floor(now / 86_400_000);
    const allowed = await this.state.storage.transaction(async storage => {
      const old = await storage.get<{ minute: number; day: number; minutes: number; days: number }>("budget");
      const minutes = old?.minute === minute ? old.minutes : 0;
      const days = old?.day === day ? old.days : 0;
      if (minutes >= 20 || days >= 300) return false;
      await storage.put("budget", { minute, day, minutes: minutes + 1, days: days + 1 });
      return true;
    });
    return Response.json(allowed ? { ok: true } : { error: "请求过于频繁或今日额度已用完" }, { status: allowed ? 200 : 429 });
  }
}
