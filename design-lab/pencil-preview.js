const pdf = document.querySelector('#pdf-paper');
const canvas = document.querySelector('#ink-canvas');
const context = canvas.getContext('2d');
const controls = document.querySelector('#pencil-controls');
const statusLine = document.querySelector('#reader-input-status');
const undo = document.querySelector('#undo');
const redo = document.querySelector('#redo');
const markButton = document.querySelector('#mark-text');
const underline = document.querySelector('#underline-text');
const tones = {
  blue: ['#356780', '#dcebf3'], yellow: ['#775516', '#f3e4b7'],
  purple: ['#6d4d86', '#e9def2'], green: ['#3d6750', '#dce9d8']
};
const lastSelection = new Map();
const addedMarks = new Map();
const inkHistory = [];
const inkRedo = [];
const sampleHidden = new Set();
let strokes = [];
let activeStroke;
let format = 'epub';
let activeTool = 'pen';
let tone = 'purple';
let left = false;

function renderTools(message) {
  const isPDF = format === 'pdf';
  pdf.classList.toggle('inking', isPDF && activeTool !== 'select');
  controls.dataset.side = left ? 'left' : 'right';
  controls.querySelectorAll('[data-tool]').forEach((button) => {
    button.hidden = !isPDF && button.dataset.tool !== 'select';
    button.setAttribute('aria-pressed', button.dataset.tool === (isPDF ? activeTool : 'select'));
  });
  controls.querySelectorAll('[data-tone]').forEach((button) => {
    button.setAttribute('aria-pressed', button.dataset.tone === tone);
  });
  undo.hidden = redo.hidden = !isPDF;
  undo.disabled = !inkHistory.length;
  redo.disabled = !inkRedo.length;
  underline.hidden = isPDF;
  markButton.disabled = isPDF && activeTool !== 'select';
  statusLine.textContent = message || (isPDF
    ? activeTool === 'select' ? '选择模式 · 选取文字后按 Mark；手指滚动与缩放。' : '勾画模式 · 笔迹独立于选文；原型可用鼠标试写。'
    : '文本随排版重排 · 选文后高亮或加下划线，笔记留在对应段落的页边。');
}

function updateAside() {
  const item = addedMarks.get(format);
  const card = document.querySelector('#added-mark');
  card.hidden = !item;
  if (item) {
    card.className = 'excerpt tone-' + item.tone;
    card.querySelector('blockquote').textContent = item.text;
  }
}

document.addEventListener('reader-format', (event) => {
  format = event.detail;
  const isPDF = format === 'pdf';
  pdf.hidden = document.querySelector('#pdf-notes').hidden = !isPDF;
  document.querySelector('#epub-paper').hidden = document.querySelector('#epub-note').hidden = isPDF;
  const view = document.querySelector('[data-view=reader]');
  view.setAttribute('aria-labelledby', isPDF ? 'pdf-title' : 'reader-title');
  view.querySelectorAll('.reader-formats a').forEach((link) => {
    const selected = link.hash.endsWith('/pdf') === isPDF;
    link.setAttribute('aria-current', selected ? 'true' : 'false');
  });
  updateAside();
  renderTools();
  if (isPDF) requestAnimationFrame(drawInk);
});

controls.querySelectorAll('[data-tool]').forEach((button) => {
  button.addEventListener('click', () => {
    activeTool = button.dataset.tool;
    renderTools();
  });
});
controls.querySelectorAll('[data-tone]').forEach((button) => {
  button.addEventListener('click', () => {
    tone = button.dataset.tone;
    renderTools('语义色 · ' + button.getAttribute('aria-label'));
  });
});
document.querySelector('#tool-side').addEventListener('click', (event) => {
  left = !left;
  event.target.textContent = left ? '靠左 · 工具' : '靠右 · 工具';
  event.target.setAttribute('aria-pressed', left);
  renderTools();
});

document.addEventListener('selectionchange', () => {
  const selection = getSelection();
  if (!selection.rangeCount || selection.isCollapsed) return;
  const range = selection.getRangeAt(0);
  if (range.toString().trim() && (format === 'pdf' ? pdf : document.querySelector('#epub-paper')).contains(range.commonAncestorContainer)) {
    lastSelection.set(format, range.cloneRange());
  }
});

function saveSelection(isUnderline) {
  const range = lastSelection.get(format);
  if (!range) {
    renderTools('请先选择原文中的文字。');
    return;
  }
  const name = 'ks-' + (isUnderline ? 'underline' : tone);
  const supportsHighlight = CSS.highlights && window.Highlight;
  if (supportsHighlight) {
    if (!CSS.highlights.has(name)) CSS.highlights.set(name, new Highlight());
    CSS.highlights.get(name).add(range);
  }
  addedMarks.set(format, { text: range.toString(), tone });
  lastSelection.delete(format);
  getSelection().removeAllRanges();
  updateAside();
  if (!supportsHighlight) renderTools('已添加选文 Mark。此浏览器仅显示页边批注。');
  else renderTools(isUnderline ? '已加下划线 · 页边批注' : '已高亮选文并添加 Mark。');
}

[markButton, underline].forEach((button) => button.addEventListener('mousedown', (event) => event.preventDefault()));
markButton.addEventListener('click', () => saveSelection(false));
underline.addEventListener('click', () => saveSelection(true));

function samples() {
  const page = pdf.getBoundingClientRect();
  const word = document.querySelector('#pdf-ink-target').getBoundingClientRect();
  const tail = Array.from(document.querySelector('#pdf-ink-tail').getClientRects()).at(-1);
  const x = word.left - page.left + word.width / 2;
  const y = word.top - page.top + word.height / 2;
  const circle = Array.from({ length: 37 }, (_, index) => {
    const angle = index * Math.PI / 18 - .75;
    return [
      (x + (word.width / 2 + 11 + Math.sin(index * .8)) * Math.cos(angle)) / page.width,
      (y + (word.height / 2 + 5) * Math.sin(angle) - 4 * Math.cos(angle)) / page.height
    ];
  });
  const line = Array.from({ length: 23 }, (_, index) => [
    (tail.left - page.left + tail.width * index / 22) / page.width,
    (tail.bottom - page.top + 1 + Math.sin(index * .32) * 2) / page.height
  ]);
  return [
    { sample: 'circle', points: circle, color: '#8d4b52', width: 2.6 },
    { sample: 'underline', points: line, color: '#885049', width: 2.6 }
  ];
}

function drawInk() {
  if (pdf.hidden || !canvas.clientWidth) return;
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  const scale = devicePixelRatio || 1;
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  context.scale(scale, scale);
  const all = [...samples().filter((stroke) => !sampleHidden.has(stroke.sample)), ...strokes];
  if (activeStroke) all.push(activeStroke);
  for (const stroke of all) {
    context.beginPath();
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.lineWidth = stroke.width;
    context.strokeStyle = stroke.color;
    context.globalAlpha = stroke.alpha ?? .95;
    stroke.points.forEach(([x, y], index) => {
      if (!index) context.moveTo(x * width, y * height);
      else context.lineTo(x * width, y * height);
    });
    context.stroke();
  }
}

function snapshot() {
  return { strokes: [...strokes], hidden: [...sampleHidden] };
}

function restore(state) {
  strokes = state.strokes;
  sampleHidden.clear();
  state.hidden.forEach((name) => sampleHidden.add(name));
  drawInk();
  renderTools();
}

function commitInk() {
  inkHistory.push(snapshot());
  inkRedo.length = 0;
}

function pointFor(event) {
  const rect = canvas.getBoundingClientRect();
  return [(event.clientX - rect.left) / rect.width, (event.clientY - rect.top) / rect.height];
}

function nearestInk([x, y]) {
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  const all = [...strokes].reverse().concat(samples().filter((stroke) => !sampleHidden.has(stroke.sample)));
  return all.find((stroke) =>
    stroke.points.some(([px, py]) => Math.hypot((px - x) * w, (py - y) * h) <= 15)
  );
}

canvas.addEventListener('pointerdown', (event) => {
  if (event.pointerType === 'touch' || event.button !== 0 || activeStroke) return;
  const point = pointFor(event);
  if (activeTool === 'eraser') {
    const stroke = nearestInk(point);
    if (stroke) {
      commitInk();
      if (stroke.sample) sampleHidden.add(stroke.sample);
      else strokes = strokes.filter((item) => item !== stroke);
      drawInk();
      renderTools('已擦除一笔。');
    }
    return;
  }
  const marker = activeTool === 'marker';
  activeStroke = {
    pointer: event.pointerId, points: [point], color: tones[tone][0], width: marker ? 14 : 2.5, alpha: marker ? .27 : .92
  };
  canvas.setPointerCapture(event.pointerId);
});
canvas.addEventListener('pointermove', (event) => {
  if (!activeStroke || activeStroke.pointer !== event.pointerId) return;
  activeStroke.points.push(pointFor(event));
  drawInk();
});
canvas.addEventListener('pointerup', (event) => {
  if (!activeStroke || activeStroke.pointer !== event.pointerId) return;
  activeStroke.points.push(pointFor(event));
  commitInk();
  strokes.push(activeStroke);
  activeStroke = null;
  drawInk();
  renderTools('已添加一笔 · 第 24 页。');
});
canvas.addEventListener('pointercancel', () => { activeStroke = null; drawInk(); });
undo.addEventListener('click', () => { inkRedo.push(snapshot()); restore(inkHistory.pop()); });
redo.addEventListener('click', () => { inkHistory.push(snapshot()); restore(inkRedo.pop()); });
new ResizeObserver(drawInk).observe(pdf);

route();
