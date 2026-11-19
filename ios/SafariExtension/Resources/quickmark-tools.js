(() => {
  const root = globalThis.KnowledgeQuickMarkUI?.root;
  if (!root) return;
  const section = root.querySelector('section');
  const tools = document.createElement('details');
  tools.innerHTML = `<summary style="padding:10px;cursor:pointer">精听与历史</summary>
    <div id="adjust"></div><div><button id="a">设 A</button><button id="b">设 B</button><button id="clear">清除循环</button></div>
    <p id="loop" role="status">未启用循环</p><details id="history"><summary style="padding:10px">历史书签</summary>
    <input id="search" placeholder="搜索标题、备注或时间" aria-label="搜索历史" style="width:90%;min-height:40px">
    <label><input type="checkbox" id="current">仅当前视频</label><button id="refresh">刷新</button>
    <p id="count"></p><div id="rows" style="max-height:35vh;overflow:auto"></div><button id="more">显示更多</button>
    <button id="export">导出书签 JSON</button><label>导入旧书签<input id="import" type="file" accept="application/json,.json"></label></details>
    <p id="feedback" role="status" aria-live="polite"></p>`;
  section.append(tools);
  const find = id => tools.querySelector('#' + id), feedback = find('feedback');
  let a = null, b = null, boundVideo = null, marks = [], limit = 50;
  const clear = () => { a = b = null; find('loop').textContent = '未启用循环'; };
  const video = () => {
    const element = document.querySelector('video');
    if (!element || element.readyState < 2 || !Number.isFinite(element.duration) || document.querySelector('.ad-showing, .ad-interrupting, .ytp-live')) throw new Error('视频未就绪或当前不支持精听');
    if (boundVideo !== element) {
      boundVideo = element; clear();
      element.addEventListener('timeupdate', () => { if (a != null && b != null && element.currentTime >= b) element.currentTime = a; });
    }
    return element;
  };
  function act(action) { try { action(); } catch (error) { feedback.textContent = error.message; } }
  for (const seconds of [-3, -2, -1, 1, 2, 3]) {
    const button = document.createElement('button'); button.textContent = `${seconds > 0 ? '+' : ''}${seconds} 秒`;
    button.addEventListener('click', () => act(() => {
      const element = video(), target = Math.max(0, Math.min(element.duration, element.currentTime + seconds));
      if (a != null && (target < a || (b != null && target > b))) clear();
      element.currentTime = target;
    })); find('adjust').append(button);
  }
  find('a').onclick = () => act(() => { a = video().currentTime; b = null; find('loop').textContent = `A = ${a.toFixed(1)} 秒，请设置 B`; });
  find('b').onclick = () => act(() => { const element = video(); if (a == null || element.currentTime <= a) throw new Error('B 必须晚于 A'); b = element.currentTime; element.currentTime = a; find('loop').textContent = `循环 ${a.toFixed(1)}–${b.toFixed(1)} 秒`; });
  find('clear').onclick = clear;
  document.addEventListener('yt-navigate-start', clear);
  async function request(message) {
    let timer;
    try {
      const result = await Promise.race([browser.runtime.sendMessage(message), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('请求超时，先刷新确认结果后重试。')), 10000); })]);
      if (!result?.ok) throw new Error(result?.error || '扩展未确认操作');
      return result;
    } finally { clearTimeout(timer); }
  }
  async function refresh() {
    try { marks = (await request({ action: 'listMarks' })).marks.filter(mark => mark.deletedAt == null); render(); feedback.textContent = '历史已刷新'; }
    catch (error) { feedback.textContent = error.message; }
  }
  function render() {
    const query = find('search').value.toLowerCase();
    let id; try { id = KnowledgeCapture.videoID(location.href); } catch { id = null; }
    const current = find('current').checked;
    const rows = marks.filter(mark => (!current || mark.videoID === id) && `${mark.title} ${mark.note ?? ''} ${mark.seconds} ${Math.floor(mark.seconds / 60)}:${String(mark.seconds % 60).padStart(2, '0')}`.toLowerCase().includes(query))
      .sort((x, y) => current ? x.seconds - y.seconds : y.createdAt - x.createdAt);
    find('count').textContent = `${rows.length} 条，已显示 ${Math.min(limit, rows.length)} 条`; find('rows').replaceChildren();
    find('more').hidden = rows.length <= limit;
    for (const mark of rows.slice(0, limit)) {
      const row = document.createElement('div'); row.style.cssText = 'border-top:1px solid #567;padding:8px 0';
      const text = document.createElement('p'); text.textContent = `${mark.title} · ${mark.seconds} 秒${mark.note ? '\n' + mark.note : ''}`; row.append(text);
      function button(label, action) { const button = document.createElement('button'); button.textContent = label; button.onclick = async () => { try { await action(); } catch (error) { feedback.textContent = error.message; } }; row.append(button); }
      button('回看', () => { clear(); if (mark.videoID === id) video().currentTime = mark.seconds; else location.assign(`https://www.youtube.com/watch?v=${mark.videoID}&t=${mark.seconds}s`); });
      button('备注', async () => { const note = prompt('书签备注', mark.note ?? ''); if (note !== null) { await request({ action: 'annotateMark', id: mark.id, note }); await refresh(); } });
      button('复制链接', async () => { await navigator.clipboard.writeText(`https://www.youtube.com/watch?v=${mark.videoID}&t=${mark.seconds}s`); feedback.textContent = '已复制出处链接'; });
      button('删除', async () => { if (confirm('将此书签移入回收站？可在 App Data Manager 恢复。')) { await request({ action: 'annotateMark', id: mark.id, deleted: true }); await refresh(); } });
      find('rows').append(row);
    }
  }
  find('history').addEventListener('toggle', () => { if (find('history').open) refresh(); });
  find('refresh').onclick = refresh;
  find('search').oninput = () => { limit = 50; render(); };
  find('current').onchange = () => { limit = 50; render(); };
  find('more').onclick = () => { limit += 50; render(); };
  find('export').onclick = async () => {
    await refresh();
    const url = URL.createObjectURL(new Blob([KnowledgeLegacy.serialize(marks)], { type: 'application/json' }));
    const link = document.createElement('a'); link.href = url; link.download = 'youtube-time-marks.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 60000);
  };
  find('import').onchange = async event => {
    try {
      const file = event.target.files[0]; if (!file) return; if (file.size > 10 * 1024 * 1024) throw new Error('备份超过 10 MiB');
      const text = await file.text(), records = KnowledgeLegacy.parse(text);
      if (!confirm(`导入 ${records.length} 条候选？相同视频与秒数会跳过，并保留已有备注。`)) return;
      const result = await request({ action: 'importLegacy', text }); await refresh(); feedback.textContent = `已导入 ${result.imported} 条，跳过 ${result.skipped} 条`;
    } catch (error) { feedback.textContent = error.message; }
    finally { event.target.value = ''; }
  };
  browser.storage.local.get(['fontSize', 'buttonSide', 'collapsed', 'youtubeEnabled']).then(settings => {
    if (settings.youtubeEnabled === false) { root.host.hidden = true; return; }
    if ([12, 14, 16, 18].includes(settings.fontSize)) section.style.fontSize = `${settings.fontSize}px`;
    if (settings.buttonSide === 'left') { root.host.style.left = '12px'; root.host.style.right = 'auto'; }
    tools.open = settings.collapsed === false;
  }).catch(() => {});
})();
