// Persist an outbox before native delivery; delete only after an ID-matching durable ack.
const prefix = 'pendingMark:';
async function deliver(mark) {
  const key = prefix + mark.id;
  const result = await browser.runtime.sendNativeMessage('org.knowledge-studio.prototype', { action: 'saveMark', mark });
  if (result?.ok !== true || result.id !== mark.id.toLowerCase()) {
    throw new Error(result?.error || '保存结果未确认，请重试同一标记。');
  }
  await browser.storage.local.remove(key);
  return result;
}
browser.runtime.onMessage.addListener(async (message, sender) => {
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
});
async function retryPending() {
  const entries = await browser.storage.local.get(null);
  for (const [key, mark] of Object.entries(entries)) {
    if (key.startsWith(prefix)) {
      try { await deliver(mark); } catch { /* Keep pending data for the next wake or explicit retry. */ }
    }
  }
}
void retryPending().catch(() => {});
