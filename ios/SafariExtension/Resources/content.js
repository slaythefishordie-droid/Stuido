(() => {
  if (document.getElementById('knowledge-quickmark')) return;
  const host = document.createElement('div');
  host.id = 'knowledge-quickmark';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `<style>
    :host { position:fixed; right:12px; bottom:calc(16px + env(safe-area-inset-bottom)); z-index:2147483647; }
    section { width:min(310px,calc(100vw - 24px)); box-sizing:border-box; padding:8px; border-radius:14px; background:#392735; color:#ffeace; font:14px system-ui; box-shadow:0 3px 18px #0006; }
    button,select,input,summary { font:inherit; }
    button,select { min-height:44px; border-radius:8px; padding:5px 10px; border:1px solid #8b6977; color:inherit; background:#4a3446; }
    button[disabled] { opacity:.5; }
    .quickbar,.step-row,.loop-row,.history-actions { display:flex; gap:5px; }
    .quickbar button,.step-row button,.loop-row button { flex:1; }
    .primary { color:#392735; background:#e3bd94; border-color:#e3bd94; font-weight:700; }
    .pane { background:#f5e8d8; color:#3c2637; padding:10px; margin-bottom:7px; border-radius:9px; max-height:53vh; overflow:auto; }
    .pane button,.pane select { color:inherit; background:#fff5e8; border-color:#c6af9f; }
    .pane h2 { font-size:15px; margin:0 0 9px; } .pane p { margin:6px 0; }
    .lead,.history-filter { display:flex; align-items:center; justify-content:space-between; gap:6px; margin-top:8px; }
    .history-filter input[type=search] { box-sizing:border-box; width:100%; min-height:44px; }
    .history-row { border-top:1px solid #c6af9f; padding:7px 0; overflow-wrap:anywhere; }
    .history-actions { flex-wrap:wrap; }
    .feedback { display:block; margin:5px 2px 0; font-size:.86em; }
    .feedback:empty { display:none; }
  </style><section aria-label="Knowledge Studio">
    <div class="panes"></div>
    <div class="quickbar"><button class="primary" id="quick-save">＋标记</button></div>
    <p class="feedback" role="status" aria-live="polite"></p>
    <label class="lead">标记提前量 <select aria-label="标记回溯秒数"><option value="0">0 秒</option><option value="1">1 秒</option><option value="2" selected>2 秒</option><option value="3">3 秒</option></select></label>
  </section>`;
  document.documentElement.append(host);
  globalThis.KnowledgeQuickMarkUI = { root };
  const button = root.querySelector('#quick-save'), status = root.querySelector('.feedback'), select = root.querySelector('select');
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
      status.textContent = `已标记 ${pending.seconds} 秒`;
      pending = null;
    } catch (error) { status.textContent = error.message; }
    finally {
      clearTimeout(timer); busy = false; button.disabled = false;
      button.textContent = pending ? '重试上一条标记' : '＋标记';
    }
  });
})();
