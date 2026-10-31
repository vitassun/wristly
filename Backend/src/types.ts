export interface Env {
  APP_ACCESS_TOKEN: string;
  LLM_API_KEY: string;
  LLM_BASE_URL: string;
  LLM_MODEL: string;
  SEARCH_API_KEY: string;
  ASR_APP_ID: string;
  ASR_ACCESS_TOKEN: string;
  ASR_RESOURCE_ID: string;
  RATE_LIMITER: DurableObjectNamespace;
}
export interface Message { role: "user" | "assistant"; content: string }
export interface Source { title: string; url: string; snippet: string }
export type Fetcher = typeof fetch;
export class APIError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}
