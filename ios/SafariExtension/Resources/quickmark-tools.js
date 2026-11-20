(() => {
  const root = globalThis.KnowledgeQuickMarkUI?.root;
  if (!root) return;
  const section = root.querySelector('section');
  const tools = document.createElement('div');
  tools.innerHTML = `<section class="pane" id="listening" aria-label="精听" hidden style="width:auto;background:#f5e8d8;color:#3c2637;box-shadow:none">
    <h2>精听</h2>
    <div id="adjust" class="step-row"></div>
    <p id="loop" role="status">未启用循环</p>
    <div class="loop-row"><button id="a">设 A</button><button id="b" disabled>设 B</button><button id="clear" disabled>清除</button></div>
    </section>
    <section class="pane" id="history" aria-label="标记历史" hidden style="width:auto;background:#f5e8d8;color:#3c2637;box-shadow:none">
    <h2>标记历史</h2>
    <div class="history-filter"><input type="search" id="search" placeholder="搜索标题、备注或时间" aria-label="搜索历史"></div>
    <div class="history-filter"><label><input type="checkbox" id="current">仅当前视频</label><button id="refresh">刷新</button></div>
    <p id="count"></p><div id="rows" style="max-height:29vh;overflow:auto"></div><button id="more">显示更多</button>
    <details><summary>导入与导出</summary><button id="export">导出书签 JSON</button>
    <label>导入旧书签<input id="import" type="file" accept="application/json,.json"></label></details></section>`;
  section.querySelector('.panes').append(tools);
  const preRollLabel = section.querySelector(':scope > label');
  if (preRollLabel) tools.querySelector('#listening').append(preRollLabel);
  const find = id => tools.querySelector('#' + id), feedback = section.querySelector('.feedback');
  const bar = section.querySelector('.quickbar');
  function panelButton(id, title, onOpen) {
    const button = document.createElement('button');
    button.textContent = title;
    button.setAttribute('aria-controls', id);
    button.setAttribute('aria-expanded', 'false');
    button.onclick = () => {
      const open = find(id).hidden;
      for (const pane of tools.querySelectorAll('.pane')) pane.hidden = true;
      for (const control of bar.querySelectorAll('[aria-expanded]')) control.setAttribute('aria-expanded', 'false');
      if (open) {
        find(id).hidden = false;
        button.setAttribute('aria-expanded', 'true');
        onOpen?.();
      }
    };
    bar.append(button);
    return button;
  }
  const listeningButton = panelButton('listening', '精听');
  panelButton('history', '历史', () => refresh());
  let a = null, b = null, boundVideo = null, marks = [], limit = 50;
  function drawLoop() {
    find('b').disabled = a == null;
    find('clear').disabled = a == null;
    listeningButton.textContent = b == null ? '精听' : '精听 ↻';
    find('loop').textContent = a == null ? '未启用循环' : b == null
      ? `A ${a.toFixed(1)} 秒 · 等待 B`
      : `A ${a.toFixed(1)} → B ${b.toFixed(1)} 秒`;
  }
  const clear = () => { a = b = null; drawLoop(); };
  const video = () => {
    const element = document.querySelector('video');
    if (!element || element.readyState < 2 || !Number.isFinite(element.duration) || document.querySelector('.ad-showing, .ad-interrupting, .ytp-live')) throw new Error('视频未就绪或当前不支持精听');
    if (boundVideo !== element) {
      boundVideo = element; clear();
      element.addEventListener('timeupdate', () => {
        if (boundVideo === element && a != null && b != null && element.currentTime >= b) element.currentTime = a;
      });
    }
    return element;
  };
  function act(action) { try { action(); } catch (error) { feedback.textContent = error.message; } }
  for (const seconds of [-3, -1, 1, 3]) {
    const button = document.createElement('button'); button.textContent = `${seconds > 0 ? '+' : ''}${seconds} 秒`;
    button.addEventListener('click', () => act(() => {
      const element = video(), target = Math.max(0, Math.min(element.duration, element.currentTime + seconds));
      if (a != null && (target < a || (b != null && target > b))) clear();
      element.currentTime = target;
    })); find('adjust').append(button);
  }
  find('a').onclick = () => act(() => { a = video().currentTime; b = null; drawLoop(); });
  find('b').onclick = () => act(() => { const element = video(); if (a == null || element.currentTime <= a) throw new Error('B 必须晚于 A'); b = element.currentTime; element.currentTime = a; drawLoop(); });
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
      const row = document.createElement('div'); row.className = 'history-row';
      const text = document.createElement('p'); text.textContent = `${mark.title} · ${mark.seconds} 秒${mark.note ? '\n' + mark.note : ''}`; row.append(text);
      const actions = document.createElement('div'); actions.className = 'history-actions'; row.append(actions);
      function button(label, action) { const button = document.createElement('button'); button.textContent = label; button.onclick = async () => { try { await action(); } catch (error) { feedback.textContent = error.message; } }; actions.append(button); }
      button('回看', () => { clear(); if (mark.videoID === id) video().currentTime = mark.seconds; else location.assign(`https://www.youtube.com/watch?v=${mark.videoID}&t=${mark.seconds}s`); });
      button('备注', async () => { const note = prompt('书签备注', mark.note ?? ''); if (note !== null) { await request({ action: 'annotateMark', id: mark.id, note }); await refresh(); } });
      button('复制链接', async () => { await navigator.clipboard.writeText(`https://www.youtube.com/watch?v=${mark.videoID}&t=${mark.seconds}s`); feedback.textContent = '已复制出处链接'; });
      button('删除', async () => { if (confirm('将此书签移入回收站？可在 应用的数据管理 恢复。')) { await request({ action: 'annotateMark', id: mark.id, deleted: true }); await refresh(); } });
      find('rows').append(row);
    }
  }
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
    if (settings.collapsed === false && find('listening').hidden) listeningButton.click();
  }).catch(() => {});
})();
