import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { Miniflare, Log, LogLevel, convertV4MiniflareOptions } from 'miniflare';

// Run the deployment bundle inside workerd, including the actual global fetch.
// Outbound providers are isolated test services; no real keys or paid calls.
function runtime(outboundService) {
  return new Miniflare(convertV4MiniflareOptions({
    log: new Log(LogLevel.ERROR),
    workers: [{
      name: 'wristly-runtime-test', modules: true,
      scriptPath: fileURLToPath(new URL('../dist/index.js', import.meta.url)),
      compatibilityDate: '2026-10-01',
      bindings: {
        ALLOW_UNAUTHENTICATED: 'true', LLM_API_KEY: 'fake-model-key',
        LLM_BASE_URL: 'https://api.deepseek.com', LLM_MODEL: 'deepseek-flash',
        SEARCH_API_KEY: 'fake-search-key'
      },
      durableObjects: { RATE_LIMITER: { className: 'RateLimiter', useSQLite: true } },
      outboundService
    }]
  }));
}
const delta = text => ({ choices: [{ delta: { content: text } }] });
function modelResponse(...chunks) {
  return new Response([...chunks, '[DONE]'].map(chunk => `data: ${typeof chunk === 'string' ? chunk : JSON.stringify(chunk)}\n\n`).join(''),
    { headers: { 'Content-Type': 'text/event-stream' } });
}
const tool = () => modelResponse({ choices: [{ delta: { tool_calls: [{ index: 0, id: 'search-1',
  function: { name: 'web_search', arguments: '{"query":"test query"}' } }] } }] });
async function chat(mf) {
  const response = await mf.dispatchFetch('https://worker.example/chat', { method: 'POST',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ messages: [{ role: 'user', content: 'test' }] }) });
  assert.equal(response.status, 200);
  const events = [];
  for (const block of (await response.text()).split('\n\n')) {
    const lines = block.split('\n');
    const event = lines.find(line => line.startsWith('event: '))?.slice(7);
    const data = lines.find(line => line.startsWith('data: '))?.slice(6);
    if (event && data) events.push({ event, data: JSON.parse(data) });
  }
  return events;
}

test('workerd fetch reaches the model and streams an answer', async () => {
  let calls = 0;
  const mf = runtime(async request => {
    calls++;
    assert.equal(request.url, 'https://api.deepseek.com/chat/completions');
    assert.equal(request.headers.get('Authorization'), 'Bearer fake-model-key');
    return modelResponse(delta('连接成功'));
  });
  try {
    const events = await chat(mf);
    assert.deepEqual(events.map(e => e.event), ['delta', 'done']);
    assert.equal(events[0].data.text, '连接成功');
    assert.equal(calls, 1);
  } finally { await mf.dispose(); }
});

test('workerd executes Tavily search then streams the grounded model answer', async () => {
  let models = 0, searches = 0;
  const mf = runtime(async request => {
    if (new URL(request.url).hostname === 'api.tavily.com') {
      searches++;
      assert.equal(request.headers.get('Authorization'), 'Bearer fake-search-key');
      assert.equal((await request.json()).query, 'test query');
      return Response.json({ results: [{ title: 'Source', url: 'https://source.example', content: 'Snippet' }] });
    }
    models++;
    if (models === 1) return tool();
    const input = await request.json();
    assert.equal(input.messages.at(-1).role, 'tool');
    return modelResponse(delta('Answer with source'));
  });
  try {
    const events = await chat(mf);
    assert.deepEqual(events.map(e => e.event), ['status', 'sources', 'delta', 'done']);
    assert.equal(events[1].data.sources[0].url, 'https://source.example');
    assert.equal(models, 2); assert.equal(searches, 1);
  } finally { await mf.dispose(); }
});

for (const provider of ['model', 'search']) {
  test(`workerd rejects ${provider} redirects without forwarding credentials`, async () => {
    const hosts = [];
    const mf = runtime(async request => {
      const host = new URL(request.url).hostname;
      hosts.push(host);
      assert.notEqual(host, 'redirect.example');
      if (provider === 'search' && host === 'api.deepseek.com') return tool();
      return new Response(null, { status: 307, headers: { Location: 'https://redirect.example/collect' } });
    });
    try {
      const events = await chat(mf);
      assert.equal(events.at(-1)?.event, 'error');
      assert.equal(events.some(e => e.event === 'done'), false);
      assert.deepEqual(hosts, provider === 'model' ? ['api.deepseek.com'] : ['api.deepseek.com', 'api.tavily.com']);
    } finally { await mf.dispose(); }
  });
}
