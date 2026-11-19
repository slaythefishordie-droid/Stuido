(() => {
  if (['www.youtube.com', 'm.youtube.com', 'youtube.com'].includes(location.hostname) || document.getElementById('knowledge-page-capture')) return;
  const host = document.createElement('div'); host.id = 'knowledge-page-capture';
  const root = host.attachShadow({ mode: 'closed' });
  root.innerHTML = `<style>:host{position:fixed;bottom:calc(18px + env(safe-area-inset-bottom));right:12px;z-index:2147483647}div{background:#182529;color:white;padding:10px;border-radius:10px;max-width:260px;font:14px system-ui}button{min-height:44px;font:inherit;margin:3px}p{margin:4px}</style><div><button id="article">保存选文</button><button id="podcast">音频 Mark</button><button id="retry" hidden>重试上一条</button><p role="status" aria-live="polite">选文或音频定位将进入 My Inbox</p></div>`;
  document.documentElement.append(host);
  let pending, busy = false;
  const match = /^#t=(\d+(?:\.\d+)?)$/.exec(location.hash);
  if (match) {
    const seconds = Number(match[1]);
    const restoreAudio = () => { const audio = document.querySelector('audio'); if (audio && Number.isFinite(audio.duration) && seconds <= audio.duration) audio.currentTime = seconds; };
    restoreAudio(); document.addEventListener('loadedmetadata', restoreAudio, { capture: true, once: true });
  }
  const status = root.querySelector('p'), retry = root.querySelector('#retry');
  async function save(kind) {
    if (busy) return;
    let timer;
    try {
      if (!pending) {
        const selection = window.getSelection(), audio = document.querySelector('audio');
        if (kind === 'podcast' && !audio) throw new Error('此页面没有可读取的音频元素');
        pending = KnowledgeAdapters.capturePage({ url: location.href, title: document.title,
          text: kind === 'article' ? selection?.toString() ?? '' : '', paragraphID: selection?.anchorNode?.parentElement?.closest('[id]')?.id ?? '',
          ...(kind === 'podcast' ? { seconds: audio.currentTime, duration: audio.duration, readyState: audio.readyState } : {})
        }, crypto.randomUUID(), Date.now());
      }
      busy = true;
      const result = await Promise.race([browser.runtime.sendMessage({ action: 'capturePage', mark: pending }), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('保存待确认，请重试同一条记录')), 10000); })]);
      if (!result?.ok || result.id !== pending.id) throw new Error(result?.error || '保存未确认');
      pending = null; status.textContent = '已保存到 My Inbox';
    } catch (error) { status.textContent = error.message; }
    finally { clearTimeout(timer); busy = false; retry.hidden = !pending; }
  }
  root.querySelector('#article').onclick = () => save('article'); root.querySelector('#podcast').onclick = () => save('podcast'); retry.onclick = () => save();
})();
