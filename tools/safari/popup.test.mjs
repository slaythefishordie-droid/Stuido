import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../../ios/SafariExtension/Resources/popup.js', import.meta.url), 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));

function openPopup(sendNativeMessage) {
  const elements = new Map();
  for (const id of ['write', 'read', 'app', 'safari', 'status']) {
    elements.set('#' + id, {
      disabled: false,
      textContent: '',
      addEventListener(_, handler) { this.click = handler; }
    });
  }
  const timers = new Map();
  let nextTimer = 0;
  vm.runInNewContext(source, {
    document: { querySelector: selector => elements.get(selector) },
    browser: { runtime: { sendNativeMessage } },
    setTimeout(callback) { timers.set(++nextTimer, callback); return nextTimer; },
    clearTimeout(id) { timers.delete(id); }
  });
  return { elements, timers };
}

test('timeout releases buttons and a late response cannot overwrite a newer read', async () => {
  let resolveFirst;
  let calls = 0;
  const popup = openPopup(() => {
    calls++;
    if (calls === 1) return new Promise(resolve => { resolveFirst = resolve; });
    return Promise.resolve({ ok: true, app: 'current-app', safari: 'current-safari' });
  });
  await popup.elements.get('#write').click();
  assert.equal(calls, 1);
  popup.timers.values().next().value();
  await flush();
  assert.equal(popup.elements.get('#read').disabled, false);
  assert.match(popup.elements.get('#status').textContent, /超时/);
  await popup.elements.get('#read').click();
  resolveFirst({ ok: true, app: 'stale', safari: 'stale' });
  await flush();
  assert.equal(popup.elements.get('#app').textContent, 'current-app');
  assert.equal(popup.timers.size, 0);
});

test('incomplete native success response reports a readable error', async () => {
  const popup = openPopup(() => Promise.resolve({ ok: true }));
  await flush();
  assert.match(popup.elements.get('#status').textContent, /响应格式无效/);
  assert.equal(popup.elements.get('#write').disabled, false);
  assert.equal(popup.timers.size, 0);
});

test('null rejection recovers and allows a subsequent successful write', async () => {
  let calls = 0;
  const popup = openPopup(() => {
    if (++calls === 1) return Promise.reject(null);
    return Promise.resolve({ ok: true, app: 'app-id', safari: 'safari-id' });
  });
  await flush();
  assert.match(popup.elements.get('#status').textContent, /共享请求失败/);
  await popup.elements.get('#write').click();
  assert.equal(popup.elements.get('#safari').textContent, 'safari-id');
  assert.equal(popup.timers.size, 0);
});

test('synchronous native exception also restores the controls', async () => {
  const popup = openPopup(() => { throw new Error('native unavailable'); });
  await flush();
  assert.equal(popup.elements.get('#status').textContent, 'native unavailable');
  assert.equal(popup.elements.get('#write').disabled, false);
  assert.equal(popup.timers.size, 0);
});
