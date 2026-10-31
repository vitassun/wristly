import { APIError } from "./types.ts";

// Volcengine bigmodel binary protocol v1. No compression on client frames.
export function frame(type: number, flags: number, payload: Uint8Array, json = false): Uint8Array {
  const bytes = new Uint8Array(8 + payload.byteLength);
  bytes.set([0x11, (type << 4) | flags, json ? 0x10 : 0, 0]);
  new DataView(bytes.buffer).setUint32(4, payload.byteLength);
  bytes.set(payload, 8);
  return bytes;
}
export function initFrame(): Uint8Array {
  return frame(1, 0, new TextEncoder().encode(JSON.stringify({
    user: { uid: "wristly" },
    audio: { format: "pcm", codec: "raw", rate: 16000, bits: 16, channel: 1 },
    request: { model_name: "bigmodel", enable_itn: true, enable_punc: true, result_type: "full" }
  })), true);
}
export async function decodeFrame(data: ArrayBuffer): Promise<{ text?: string; final: boolean }> {
  if (data.byteLength < 8 || data.byteLength > 512_000) throw new APIError(502, "语音响应帧无效");
  const b = new Uint8Array(data), view = new DataView(data);
  const header = (b[0] & 15) * 4, type = b[1] >> 4, flags = b[1] & 15;
  if (b[0] >> 4 !== 1 || header < 4 || header + 4 > b.length) throw new APIError(502, "语音协议版本不支持");
  let offset = header;
  if (type === 15) throw new APIError(502, "豆包识别服务返回错误，请检查后端凭证及资源授权");
  if (type !== 9) throw new APIError(502, "未知语音响应");
  if (flags & 1) offset += 4; // sequence field
  if (offset + 4 > b.length) throw new APIError(502, "语音响应截断");
  const length = view.getUint32(offset); offset += 4;
  if (length !== b.length - offset) throw new APIError(502, "语音响应长度错误");
  let payload: Uint8Array = b.slice(offset);
  const compression = b[2] & 15;
  if (compression === 1) {
    const reader = new Blob([payload]).stream().pipeThrough(new DecompressionStream("gzip")).getReader();
    const parts: Uint8Array[] = []; let size = 0;
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > 512_000) { await reader.cancel(); throw new APIError(502, "语音响应过大"); }
      parts.push(value);
    }
    payload = new Uint8Array(size); let cursor = 0;
    for (const part of parts) { payload.set(part, cursor); cursor += part.length; }
  } else if (compression !== 0) throw new APIError(502, "未知语音压缩格式");
  if (b[2] >> 4 !== 1) throw new APIError(502, "语音响应不是 JSON");
  const json = JSON.parse(new TextDecoder().decode(payload));
  if (json.code && ![1000, 20000000].includes(json.code)) throw new APIError(502, "豆包语音识别失败");
  return { text: typeof json.result?.text === "string" ? json.result.text : undefined, final: Boolean(flags & 2) };
}
