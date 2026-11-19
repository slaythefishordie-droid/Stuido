// Persist an outbox before native delivery; delete only after an ID-matching durable ack.
const prefix = 'pendingMark:';
async function deliver(mark) {
  const key = prefix + mark.id;
  let timer, result;
  try {
    result = await Promise.race([
      browser.runtime.sendNativeMessage('org.knowledge-studio.prototype', { action: mark.kind ? 'savePageMark' : 'saveMark', mark }),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('原生保存超时，待发记录保留')), 10_000); })
    ]);
  } finally { clearTimeout(timer); }
  if (result?.ok !== true || result.id !== mark.id.toLowerCase()) {
    throw new Error(result?.error || '保存结果未确认，请重试同一标记。');
  }
  await browser.storage.local.remove(key);
  return result;
}
async function captureMessage(message, sender) {
  if (message?.action !== 'captureMark') return;
  try {
    const source = new URL(sender.url);
    if (source.protocol !== 'https:' || !['www.youtube.com', 'm.youtube.com', 'youtube.com'].includes(source.hostname) ||
        source.pathname !== '/watch' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(message.mark?.id ?? '')) {
      throw new Error('来源页面或标记编号无效。');
    }
    const key = prefix + message.mark.id;
    const existing = (await browser.storage.local.get(key))[key];
    if (!existing && source.searchParams.get('v') !== message.mark.videoID) throw new Error('视频出处已改变，请重新标记。');
    if (existing && JSON.stringify(existing) !== JSON.stringify(message.mark)) throw new Error('标记编号冲突，原记录已保留。');
    await browser.storage.local.set({ [key]: message.mark });
    return await deliver(message.mark);
  } catch (error) { return { ok: false, error: error?.message || '本地保存失败，请重试。' }; }
}
async function retryPending() {
  const entries = await browser.storage.local.get(null);
  for (const [key, mark] of Object.entries(entries)) {
    if (key.startsWith(prefix)) {
      try { await deliver(mark); } catch { /* Keep pending data for the next wake or explicit retry. */ }
    }
  }
}
void retryPending().catch(() => {});

async function historyMessage(message, sender) {
  if (!['listMarks', 'annotateMark', 'importLegacy'].includes(message?.action)) return;
  const url = new URL(sender.url);
  if (url.protocol !== 'safari-web-extension:' && !(url.protocol === 'https:' && ['www.youtube.com', 'm.youtube.com', 'youtube.com'].includes(url.hostname))) return { ok: false, error: '来源无效' };
  try {
    if (message.action === 'importLegacy') {
      const records = KnowledgeLegacy.parse(message.text);
      const current = await browser.runtime.sendNativeMessage('org.knowledge-studio.prototype', { action: 'listMarks' });
      if (!current.ok) return current;
      const seen = new Set(current.marks.map(mark => `${mark.videoID}:${mark.seconds}`));
      let imported = 0;
      for (const record of records) {
        const key = `${record.videoID}:${record.seconds}`;
        if (seen.has(key)) continue;
        const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`KnowledgeStudio:legacy:${record.videoID}:${record.seconds}`));
        const hex = Array.from(new Uint8Array(digest)).map(byte => byte.toString(16).padStart(2, '0')).join('');
        const id = `${hex.slice(0,8)}-${hex.slice(8,12)}-5${hex.slice(13,16)}-a${hex.slice(17,20)}-${hex.slice(20,32)}`;
        const saved = (await browser.storage.local.get(prefix + id))[prefix + id];
        const mark = saved ?? { ...record, id };
        await browser.storage.local.set({ [prefix + mark.id]: mark });
        await deliver(mark); seen.add(key); imported++;
      }
      return { ok: true, imported, skipped: records.length - imported };
    }
    return await browser.runtime.sendNativeMessage('org.knowledge-studio.prototype', message);
  } catch (error) { return { ok: false, error: error?.message || '操作失败' }; }
}

browser.runtime.onMessage.addListener((message, sender) => {
  if (message?.action === 'captureMark') return captureMessage(message, sender);
  if (message?.action === 'capturePage') return pageMessage(message, sender);
  if (['listMarks', 'annotateMark', 'importLegacy'].includes(message?.action)) return historyMessage(message, sender);
});

async function pageMessage(message, sender) {
  try {
    const url = new URL(sender.url), mark = message.mark;
    if (url.protocol !== 'https:' || !['article', 'podcast'].includes(mark.kind) || !/^[0-9a-f-]{36}$/i.test(mark.id)) throw new Error('网页采集来源无效');
    const key = prefix + mark.id;
    const existing = (await browser.storage.local.get(key))[key];
    if (!existing && mark.sourceURL !== url.href.split('#')[0]) throw new Error('网页出处已改变');
    if (existing && JSON.stringify(existing) !== JSON.stringify(mark)) throw new Error('采集编号冲突');
    await browser.storage.local.set({ [key]: mark });
    return await deliver(mark);
  } catch (error) { return { ok: false, error: error?.message || '网页保存失败' }; }
}
