// Shared by the content script and Node tests; no page-provided code is executed.
(() => {
  const videoID = value => {
    const url = new URL(value);
    const ids = url.searchParams.getAll('v');
    if (url.protocol !== 'https:' || !['www.youtube.com', 'm.youtube.com', 'youtube.com'].includes(url.hostname) ||
        url.username || url.password || url.port || url.pathname !== '/watch' || ids.length !== 1 ||
        !/^[A-Za-z0-9_-]{11}$/.test(ids[0])) throw new Error('仅支持 YouTube 普通视频页面。');
    return ids[0];
  };
  function capture({ url, title, seconds, duration, readyState, ad, live, preRoll = 2 }, id, now) {
    if (ad || live || readyState < 2 || !Number.isFinite(duration) || duration <= 0 ||
        !Number.isFinite(seconds) || seconds < 0 || seconds > duration || seconds > 3_155_760_000 ||
        ![0, 1, 2, 3].includes(preRoll)) throw new Error('视频未就绪、正在播放广告或为直播，本次未标记。');
    title = title.trim();
    if (!title || new TextEncoder().encode(title).length > 4096) throw new Error('无法取得有效视频标题。');
    return { version: 1, id, videoID: videoID(url), title, capturedSeconds: seconds,
      preRoll, seconds: Math.max(0, Math.floor(seconds - preRoll)), createdAt: now };
  }
  globalThis.KnowledgeCapture = { capture, videoID };
})();
