import { APIError } from "./types.ts";

export async function readJSON(request: Request, limit = 64_000): Promise<unknown> {
  if (!request.headers.get("content-type")?.includes("application/json")) {
    throw new APIError(415, "需要 application/json 请求");
  }
  if (!request.body) throw new APIError(400, "请求为空");
  const reader = request.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new APIError(413, "消息过长"); }
      parts.push(value);
    }
  } finally { reader.releaseLock(); }
  try {
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch { throw new APIError(400, "JSON 格式错误"); }
}

// Parses frames across arbitrary network boundaries, CRLF, comments, multi-line data.
export async function* sseData(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let data: string[] = [];
  try {
    while (true) {
      const { value, done } = await reader.read();
      buffer += done ? decoder.decode() : decoder.decode(value, { stream: true });
      let end: number;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end).replace(/\r$/, "");
        buffer = buffer.slice(end + 1);
        if (!line) {
          if (data.length) yield data.join("\n");
          data = [];
        } else if (line.startsWith("data:")) data.push(line.slice(5).replace(/^ /, ""));
      }
      if (buffer.length > 512_000) throw new APIError(502, "模型流帧过大");
      if (done) break;
    }
    // A complete SSE event must end with a blank line. A truncated frame is an error.
    if (data.length || buffer.trim()) throw new APIError(502, "模型流意外中断");
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}

export function event(name: string, data: unknown): Uint8Array {
  return new TextEncoder().encode(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
}
