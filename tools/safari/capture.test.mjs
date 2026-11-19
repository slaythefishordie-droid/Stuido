import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const resources = new URL('../../ios/SafariExtension/Resources/', import.meta.url);
const captureContext = vm.createContext({ URL, TextEncoder });
vm.runInContext(readFileSync(new URL('capture.js', resources), 'utf8'), captureContext);
const { capture } = captureContext.KnowledgeCapture;
const input = { url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', title: 'Lesson', seconds: 12.8, duration: 100, readyState: 4 };
const id = '12345678-1234-4234-8234-123456789abc';
const mark = capture(input, id, 1000);

test('QuickMark preserves original seconds and applies 0–3 second pre-roll', () => {
  for (let preRoll = 0; preRoll <= 3; preRoll++) {
    const result = capture({ ...input, preRoll }, id, 1000);
    assert.equal(result.capturedSeconds, 12.8);
    assert.equal(result.seconds, 12 - preRoll);
    assert.equal(result.id, id);
  }
  assert.equal(capture({ ...input, seconds: 0 }, id, 1000).seconds, 0);
});

test('ads, live, unavailable time and non-watch URLs cannot produce marks', () => {
  for (const change of [{ ad: true }, { live: true }, { readyState: 1 }, { seconds: NaN },
    { seconds: -1 }, { duration: Infinity }, { seconds: 101 }, { preRoll: 4 }, { title: ' ' },
    { url: 'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ' },
    { url: 'https://m.youtube.com/shorts/dQw4w9WgXcQ' },
    { url: input.url + '&v=abcdefghijk' }]) {
    assert.throws(() => capture({ ...input, ...change }, id, 1000));
  }
  assert.equal(capture({ ...input, url: input.url.replace('www.', 'm.') }, id, 1000).videoID, mark.videoID);
});

async function background(native, initial = {}) {
  const data = structuredClone(initial);
  let listener;
  const context = vm.createContext({ URL, setTimeout, clearTimeout, browser: {
    runtime: { onMessage: { addListener(fn) { listener = fn; } }, sendNativeMessage: native },
    storage: { local: {
      async get(key) { return key === null ? { ...data } : { [key]: data[key] }; },
      async set(values) { Object.assign(data, structuredClone(values)); },
      async remove(key) { delete data[key]; }
    } }
  } });
  vm.runInContext(readFileSync(new URL('background.js', resources), 'utf8'), context);
  await new Promise(resolve => setImmediate(resolve));
  return { data, send: (record = mark, url = input.url) => listener({ action: 'captureMark', mark: record }, { url }) };
}

test('native failure keeps durable outbox; retry uses the same ID and clears only after ack', async () => {
  let calls = 0;
  const worker = await background(async (_, request) => {
    assert.equal(request.mark.id, id);
    if (++calls === 1) throw new Error('offline');
    return { ok: true, id };
  });
  assert.equal((await worker.send()).ok, false);
  assert.equal(worker.data['pendingMark:' + id].id, id);
  assert.equal((await worker.send()).ok, true);
  assert.deepEqual(worker.data, {});
});

test('background restart retries durable pending data', async () => {
  let delivered;
  const worker = await background(async (_, request) => { delivered = request.mark; return { ok: true, id }; }, { ['pendingMark:' + id]: mark });
  assert.equal(delivered.id, id);
  assert.deepEqual(worker.data, {});
});

test('wrong acknowledgements, conflicting IDs and untrusted pages do not clear pending data', async () => {
  const worker = await background(async () => ({ ok: true, id: 'wrong' }));
  assert.equal((await worker.send()).ok, false);
  assert.equal((await worker.send({ ...mark, title: 'changed' })).ok, false);
  assert.equal(worker.data['pendingMark:' + id].title, 'Lesson');
  assert.equal((await worker.send(mark, 'https://example.com/watch?v=dQw4w9WgXcQ')).ok, false);
});

 test('pending Mark remains retryable after same-tab navigation', async () => {
  let calls = 0;
  const worker = await background(async () => ++calls === 1 ? { ok: false } : { ok: true, id });
  await worker.send();
  assert.equal((await worker.send(mark, 'https://www.youtube.com/watch?v=abcdefghijk')).ok, true);
});

function contentHarness(send) {
  const handlers = {};
  const elements = Object.fromEntries(['button', 'p', 'select'].map(name => [name, {
    value: '2', textContent: '', disabled: false,
    addEventListener(event, fn) { handlers[name + ':' + event] = fn; }
  }]));
  const video = { currentTime: 12.8, duration: 100, readyState: 4,
    pause() { throw new Error('Capture must not pause playback'); } };
  const root = { innerHTML: '', querySelector: name => elements[name] };
  const context = vm.createContext({ URL, TextEncoder, setTimeout, clearTimeout,
    HTMLVideoElement: class {}, crypto: { randomUUID: () => id }, location: { href: input.url },
    browser: { runtime: { sendMessage: send }, storage: { local: { async get() { return {}; }, async set() {} } } },
    document: {
      title: 'Lesson - YouTube', getElementById() { return null; },
      createElement() { return { attachShadow: () => root }; },
      documentElement: { append() {} },
      addEventListener(event, fn) { handlers[event] = fn; },
      querySelector(selector) { return selector === 'video' ? video : null; }
    }
  });
  vm.runInContext(readFileSync(new URL('capture.js', resources), 'utf8'), context);
  vm.runInContext(readFileSync(new URL('content.js', resources), 'utf8'), context);
  return { click: () => handlers['button:click'](), elements, video, handlers };
}

test('page button saves without pausing playback and acknowledges the captured position', async () => {
  let sent;
  const page = contentHarness(async message => { sent = message.mark; return { ok: true, id }; });
  await page.click();
  assert.equal(sent.seconds, 10);
  assert.equal(page.elements.button.disabled, false);
  assert.equal(page.elements.button.textContent, 'QuickMark');
  assert.match(page.elements.p.textContent, /已保存 10 秒/);
});

test('failed page delivery retries its original position even after playback advances', async () => {
  const sent = [];
  const page = contentHarness(async message => {
    sent.push(structuredClone(message.mark));
    return sent.length === 1 ? { ok: false, error: 'offline' } : { ok: true, id };
  });
  await page.click();
  assert.equal(page.elements.button.textContent, '重试上一条 Mark');
  page.video.currentTime = 50;
  await page.click();
  assert.deepEqual(sent[0], sent[1]);
  assert.equal(page.elements.button.textContent, 'QuickMark');
});

test('navigation blocks capture before replacement video metadata is ready', async () => {
  let sent = false;
  const page = contentHarness(async () => { sent = true; });
  page.handlers['yt-navigate-start']();
  await page.click();
  assert.equal(sent, false);
  assert.match(page.elements.p.textContent, /页面正在切换/);
});
