(() => {
  // Site adapters return one shared source/locator envelope; no media URL extraction.
  function capturePage({ url, title, text = '', paragraphID = '', seconds, duration, readyState }, id, now) {
    const source = new URL(url);
    if (source.protocol !== 'https:' || source.username || source.password || !title.trim()) throw new Error('网页出处或标题无效');
    source.hash = '';
    const podcast = seconds !== undefined;
    if (podcast && (!Number.isFinite(seconds) || seconds < 0 || !Number.isFinite(duration) || duration <= 0 || seconds > duration || readyState < 2)) throw new Error('音频未提供有效时间');
    if (!podcast && !text.trim()) throw new Error('请先选择文章中的原文');
    if (new TextEncoder().encode(text).length > 20_000) throw new Error('选文过长，请缩短选区');
    const kind = podcast ? 'podcast' : 'article';
    return { version: 1, id, kind, sourceURL: source.href, title: title.trim(), excerpt: text, createdAt: now,
      locator: { kind, seconds: podcast ? seconds : null, href: paragraphID || null, rectangles: [], nativeJSON: JSON.stringify({ textQuote: text, paragraphID }) } };
  }
  globalThis.KnowledgeAdapters = { capturePage };
})();
