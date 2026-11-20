(() => {
  if (document.getElementById('knowledge-quickmark')) return;
  const host = document.createElement('div');
  host.id = 'knowledge-quickmark';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `<style>
    :host { position:fixed; right:12px; bottom:calc(16px + env(safe-area-inset-bottom)); z-index:2147483647; }
    section { max-width:260px; padding:10px; border-radius:12px; background:#3c2637; color:#ffedd5; font:14px system-ui; box-shadow:0 2px 12px #0006; }
    button,select { min-height:44px; font:inherit; border-radius:8px; margin:3px; }
    p { margin:6px 2px; } button { padding:8px 16px; }
  </style><section aria-label="Knowledge Studio"><button>标记</button><label>回溯 <select aria-label="标记回溯秒数"><option value="0">0 秒</option><option value="1">1 秒</option><option value="2" selected>2 秒</option><option value="3">3 秒</option></select></label><p role="status" aria-live="polite">标记后可在 收集箱 整理</p></section>`;
  document.documentElement.append(host);
  globalThis.KnowledgeQuickMarkUI = { root };
  const button = root.querySelector('button'), status = root.querySelector('p'), select = root.querySelector('select');
  let pending = null, busy = false, navigating = false;
  browser.storage.local.get('preRoll').then(value => {
    if ([0, 1, 2, 3].includes(value.preRoll)) select.value = String(value.preRoll);
  }).catch(() => {});
  select.addEventListener('change', () => {
    browser.storage.local.set({ preRoll: Number(select.value) }).catch(() => { status.textContent = '回溯偏好未保存。'; });
  });
  document.addEventListener('yt-navigate-start', () => { navigating = true; });
  document.addEventListener('loadedmetadata', event => {
    if (event.target instanceof HTMLVideoElement) navigating = false;
  }, true);
  button.addEventListener('click', async () => {
    if (busy) return;
    let timer;
    try {
      if (!pending) {
        const video = document.querySelector('video');
        if (!video || navigating) throw new Error('页面正在切换或视频未就绪，请稍后重试。');
        const metadataID = document.querySelector('meta[itemprop="videoId"]')?.content;
        if (metadataID && metadataID !== KnowledgeCapture.videoID(location.href)) {
          throw new Error('视频出处正在更新，请稍后重试。');
        }
        pending = KnowledgeCapture.capture({ url: location.href,
          title: document.querySelector('h1 yt-formatted-string, h1.title, .slim-video-metadata-title')?.textContent || document.title.replace(/ - YouTube$/, ''),
          seconds: video.currentTime, duration: video.duration, readyState: video.readyState,
          ad: !!document.querySelector('.ad-showing, .ad-interrupting'),
          live: !!document.querySelector('.ytp-live'),
          preRoll: Number(select.value)
        }, crypto.randomUUID(), Date.now());
      }
      busy = true; button.disabled = true;
      status.textContent = '正在保存…';
      const result = await Promise.race([
        browser.runtime.sendMessage({ action: 'captureMark', mark: pending }),
        new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('保存结果待确认，请重试；不会重复建档。')), 10_000); })
      ]);
      if (result?.ok !== true || result.id !== pending.id) throw new Error(result?.error || '保存结果未确认，请重试。');
      status.textContent = `已保存 ${pending.seconds} 秒，返回 收集箱 查看。`;
      pending = null;
    } catch (error) { status.textContent = error.message; }
    finally {
      clearTimeout(timer); busy = false; button.disabled = false;
      button.textContent = pending ? '重试上一条标记' : '标记';
    }
  });
})();
