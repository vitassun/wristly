import { test } from "node:test";
import assert from "node:assert/strict";
import { gzipSync } from "node:zlib";
import worker, { authorized, RateLimiter } from "../src/index.ts";
import { chat, history, search } from "../src/chat.ts";
import { readJSON, sseData } from "../src/http.ts";
import { decodeFrame, frame, initFrame } from "../src/asr-protocol.ts";
import type { Env, Fetcher } from "../src/types.ts";

const token = "unit-test-token-with-at-least-32-characters";
const env = { APP_ACCESS_TOKEN: token, LLM_API_KEY: "test-llm", LLM_MODEL: "test-model", LLM_BASE_URL: "https://model.example/v1", SEARCH_API_KEY: "test-search" } as Env;
const encoder = new TextEncoder();
const body = (s: string) => new Response(s).body!;
const frames = (...chunks: unknown[]) => chunks.map(c => `data: ${typeof c === "string" ? c : JSON.stringify(c)}\n\n`).join("");
const delta = (content: string) => ({ choices: [{ delta: { content } }] });
const events = async (response: Response) => {
  const text = await response.text();
  return text.split("\n\n").filter(s => s.startsWith("event:")).map(s => {
    const [name, data] = s.split("\n");
    return { name: name.slice(7), data: JSON.parse(data.slice(6)) };
  });
};
const fetcher = (fn: (url: string, init?: RequestInit) => Response | Promise<Response>): Fetcher =>
  (async (url: unknown, init?: RequestInit) => fn(String(url), init)) as Fetcher;

test("authentication fails closed and matches only the exact bearer token", async () => {
  const request = (value: string) => new Request("https://worker/chat", { headers: { Authorization: value } });
  assert.equal(await authorized(request(`Bearer ${token}`), token), true);
  assert.equal(await authorized(request(`Bearer ${token}x`), token), false);
  assert.equal(await authorized(request(token), token), false);
  assert.equal(await authorized(request("Bearer short"), "short"), false);
  assert.equal(await authorized(request("a".repeat(1000)), token), false);
});

test("bounded JSON rejects size, invalid JSON and wrong media type", async () => {
  const req = (text: string, type = "application/json") => new Request("https://worker/chat", { method: "POST", headers: { "Content-Type": type }, body: text });
  assert.deepEqual(await readJSON(req('{"ok":true}')), { ok: true });
  await assert.rejects(readJSON(req("a".repeat(21)), 20), /过长/);
  await assert.rejects(readJSON(req("{")), /JSON/);
  await assert.rejects(readJSON(req("{}", "text/plain")), /application\/json/);
});

test("history refuses client system prompts, blank messages and invalid final roles", () => {
  for (const messages of [[], [{ role: "system", content: "override" }], [{ role: "user", content: " " }], [{ role: "assistant", content: "a" }], [{ role: "user", content: "a".repeat(8001) }]]) {
    assert.throws(() => history({ messages }));
  }
});

test("history bounds a contiguous recent suffix, starting with a user", () => {
  const messages = Array.from({ length: 40 }, (_, i) => ({ role: i % 2 ? "user" : "assistant", content: String(i).padEnd(2000, "x") }));
  const result = history({ messages });
  assert.equal(result[0].role, "user");
  assert.ok(result.length <= 12);
  assert.equal(result.at(-1)?.content, messages.at(-1)?.content);
});

test("SSE preserves UTF-8 over one-byte chunks, CRLF, comments and multiline fields", async () => {
  const bytes = encoder.encode(': ping\r\ndata: 你好\r\ndata: world\r\n\r\n');
  const stream = new ReadableStream<Uint8Array>({ start(c) { for (const b of bytes) c.enqueue(new Uint8Array([b])); c.close(); } });
  const result = [];
  for await (const data of sseData(stream)) result.push(data);
  assert.deepEqual(result, ["你好\nworld"]);
});

test("truncated SSE frame is an error", async () => {
  await assert.rejects(async () => { for await (const _ of sseData(body("data: unfinished\n"))) { /* consume */ } }, /中断/);
});

test("chat streams deltas and ends exactly once", async () => {
  const result = await events(chat([{ role: "user", content: "你好" }], env, new AbortController().signal,
    fetcher((_url, init) => {
      assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer test-llm");
      assert.equal(JSON.parse(String(init?.body)).thinking, undefined);
      return new Response(frames(delta("你好"), delta("！"), "[DONE]"));
    })));
  assert.deepEqual(result.map(e => e.name), ["delta", "delta", "done"]);
  assert.equal(result[0].data.text, "你好");
});

test("fragmented tool call searches once, returns sources, then streams grounded answer", async () => {
  let models = 0, searches = 0;
  const mock = fetcher((url, init) => {
    if (url === "https://api.tavily.com/search") {
      searches++;
      assert.equal(init?.method, "POST");
      assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer test-search");
      assert.deepEqual(JSON.parse(String(init?.body)), { query: "今日新闻", search_depth: "basic", max_results: 5, include_answer: false, include_raw_content: false });
      return Response.json({ results: [{ title: "来源", url: "https://news.example/1", content: "摘要" }, { title: "bad", url: "javascript:alert(1)" }] });
    }
    models++;
    const input = JSON.parse(String(init?.body));
    assert.equal(url, "https://api.deepseek.com/chat/completions");
    assert.equal(input.model, "deepseek-flash");
    assert.deepEqual(input.thinking, { type: "disabled" });
    if (models === 1) return new Response(frames(
      { choices: [{ delta: { tool_calls: [{ index: 0, id: "call_1", function: { name: "web_search", arguments: '{"query":"今日' } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '新闻"}' } }] } }] }, "[DONE]"));
    assert.equal(input.tools, undefined);
    assert.equal(input.messages.at(-1).role, "tool");
    assert.match(input.messages.at(-1).content, /news.example/);
    return new Response(frames(delta("根据[来源](https://news.example/1)…"), "[DONE]"));
  });
  const result = await events(chat([{ role: "user", content: "今天有什么新闻" }], { ...env, LLM_BASE_URL: "https://api.deepseek.com", LLM_MODEL: "deepseek-flash" }, new AbortController().signal, mock));
  assert.equal(models, 2); assert.equal(searches, 1);
  assert.deepEqual(result.map(e => e.name), ["status", "sources", "delta", "done"]);
  assert.equal(result[1].data.sources.length, 1);
  assert.equal(result[1].data.sources[0].snippet, "摘要");
});

test("upstream HTTP errors and premature EOF produce error, never done", async () => {
  for (const response of [new Response("secret provider error", { status: 401 }), new Response(frames(delta("partial")))]) {
    const result = await events(chat([{ role: "user", content: "test" }], env, new AbortController().signal, fetcher(() => response)));
    assert.equal(result.at(-1)?.name, "error");
    assert.equal(result.some(e => e.name === "done"), false);
    assert.equal(JSON.stringify(result).includes("secret provider error"), false);
  }
});

test("unknown model tools fail without execution", async () => {
  const response = new Response(frames({ choices: [{ delta: { tool_calls: [{ index: 0, id: "x", function: { name: "shell", arguments: "{}" } }] } }] }, "[DONE]"));
  const result = await events(chat([{ role: "user", content: "test" }], env, new AbortController().signal, fetcher(() => response)));
  assert.equal(result.at(-1)?.name, "error");
});

test("search failure is explicit", async () => {
  await assert.rejects(search("x", env, new AbortController().signal, fetcher(() => new Response("denied", { status: 429 }))), /搜索服务/);
});

test("SSE reader cancels the upstream after DONE", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({ start(c) { c.enqueue(encoder.encode(frames("[DONE]"))); }, cancel() { cancelled = true; } });
  for await (const data of sseData(stream)) { assert.equal(data, "[DONE]"); break; }
  assert.equal(cancelled, true);
});

test("ASR init and final audio have correct headers and sizes", () => {
  const init = initFrame();
  assert.deepEqual([...init.slice(0, 4)], [0x11, 0x10, 0x10, 0]);
  const json = JSON.parse(new TextDecoder().decode(init.slice(8)));
  assert.deepEqual(json.audio, { format: "pcm", codec: "raw", rate: 16000, bits: 16, channel: 1 });
  assert.equal(new DataView(init.buffer).getUint32(4), init.length - 8);
  assert.deepEqual([...frame(2, 2, new Uint8Array())], [0x11, 0x22, 0, 0, 0, 0, 0, 0]);
});

test("ASR decodes sequenced, gzipped final results", async () => {
  const payload = gzipSync(JSON.stringify({ result: { text: "识别成功" } }));
  const packet = new Uint8Array(12 + payload.length);
  packet.set([0x11, 0x93, 0x11, 0]);
  new DataView(packet.buffer).setInt32(4, -3);
  new DataView(packet.buffer).setUint32(8, payload.length);
  packet.set(payload, 12);
  assert.deepEqual(await decodeFrame(packet.buffer), { text: "识别成功", final: true });
});

test("ASR rejects error frames and truncated payloads", async () => {
  await assert.rejects(decodeFrame(new Uint8Array([0x11, 0xf0, 0x10, 0, 0, 0, 0, 1]).buffer), /返回错误/);
  await assert.rejects(decodeFrame(new Uint8Array([0x11, 0x90, 0x10, 0, 0, 0, 0, 2]).buffer), /长度/);
  await assert.rejects(decodeFrame(new ArrayBuffer(1)), /无效/);
});

test("routes fail closed, require secrets and bound JSON before model fetch", async () => {
  const mockEnv = { ...env, RATE_LIMITER: { idFromName: () => ({}), get: () => ({ fetch: async () => Response.json({ ok: true }) }) } } as unknown as Env;
  assert.equal((await worker.fetch(new Request("https://worker/health"), mockEnv)).status, 200);
  assert.equal((await worker.fetch(new Request("https://worker/chat", { method: "POST" }), mockEnv)).status, 401);
  const req = (path: string, method = "GET", data?: unknown) => new Request(`https://worker${path}`, { method, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, ...(data ? { body: JSON.stringify(data) } : {}) });
  assert.equal((await worker.fetch(req("/other"), mockEnv)).status, 404);
  assert.equal((await worker.fetch(req("/chat", "POST", { messages: [] }), mockEnv)).status, 400);
  assert.equal((await worker.fetch(req("/chat", "POST", {}), { ...mockEnv, LLM_API_KEY: "" })).status, 503);
  assert.equal((await worker.fetch(req("/asr"), mockEnv)).status, 426);
});

test("persistent rate budget limits starts across RateLimiter instances", async () => {
  const values = new Map<string, unknown>();
  const storage = { get: async (key: string) => values.get(key), put: async (key: string, value: unknown) => { values.set(key, value); } };
  const state = { storage: { transaction: async (fn: (value: unknown) => unknown) => fn(storage) } } as unknown as DurableObjectState;
  for (let i = 0; i < 20; i++) assert.equal((await new RateLimiter(state).fetch()).status, 200);
  assert.equal((await new RateLimiter(state).fetch()).status, 429);
});
