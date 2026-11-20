const icons = {
  home: '<path d="m3 10 9-7 9 7v10H3z"/><path d="M9 20v-6h6v6"/>',
  books: '<path d="M3 4h4v16H3zm5 0h4v16H8zm6 2 4-1 4 14-4 1z"/>',
  book: '<path d="M12 6C9 3 5 3 2 4v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-3-1-7-1-10 2zm0 0v14"/>',
  time: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l4 2"/>',
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
  note: '<path d="M5 3h14v14l-4 4H5zm10 18v-4h4M8 8h8m-8 4h6"/>'
};
document.querySelectorAll('[data-icon]').forEach((element) => {
  element.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + icons[element.dataset.icon] + '</svg>';
});

const books = [
  { id: 'island', title: '岛屿的另一种读法', cover: '岛屿的<br>另一种<br>读法', roman: 'Island Notes', by: '林屿', type: 'epub', label: 'EPUB', color: 'plum', project: '城市与记忆', original: 'book-light.jpg', route: '#reader' },
  { id: 'city', title: '城市的背面', cover: '城市的<br>背面', roman: 'The Other City', by: '周岸', type: 'pdf', label: 'PDF', color: 'sage', project: '城市与记忆', route: '#reader/pdf' },
  { id: 'walk', title: '论散步', cover: '论散步', roman: 'On Walking', by: '陈野', type: 'epub', label: 'EPUB', color: 'wheat', project: '阅读笔记' },
  { id: 'street', title: '街巷档案', cover: '街巷档案', roman: 'Street Archive', by: '叶令', type: 'pdf', label: 'PDF', color: 'clay', project: '街头观察' },
  { id: 'light', title: '谈光线与门廊', cover: '谈光线<br>与门廊', roman: 'Light & Thresholds', by: '书房访谈', type: 'video', label: '视频 · 12:48', color: 'video', project: '城市与记忆' },
  { id: 'page-study', title: '重新读一页', cover: '重新读<br>一页', roman: 'Another Page', by: '白羽', type: 'epub', label: 'EPUB', color: 'rose', project: '阅读笔记' },
  { id: 'field', title: '街道的慢时间', cover: '街道的<br>慢时间', roman: 'Field Journal', by: '街角观察刊', type: 'web', label: '网页', color: 'slate', project: '街头观察' }
];

const cards = [
  { tone: 'green', kind: '关键句卡', style: 'featured', title: '重新走过一条街，才知道记忆也有自己的路径。', detail: '城市与记忆', note: '对照项目里关于「地方记忆」的研究笔记。重走同一条路线时，留意哪些事物没有出现在地图上。', source: '岛屿的另一种读法 · 第二章 · 第 3 段', route: '#reader/anchor' },
  { tone: 'purple', kind: '关键词卡', style: 'keyword', title: '过渡空间', detail: '从室内走向街道时，允许人停一下的地方。', note: '把门廊与车站入口分别作为样本。它们都在边界上，但等待的理由不同。', source: '城市的背面 · 第 24 页', route: '#reader/pdf-anchor' },
  { tone: 'blue', kind: '单词卡', style: 'word', title: 'threshold', detail: 'The porch is a threshold between the house and the street.', note: 'A point of entry or the boundary between two spaces.', source: '个人词汇笔记' },
  { tone: 'yellow', kind: '语料卡', style: 'expression', title: 'to see a place anew', detail: '重新认识一个地方 · 步行与观察', note: '下次写田野笔记时，用这一短语描述同一路线在清晨和傍晚给人的不同感觉。', source: '个人语料笔记' }
];
const search = document.querySelector('#search');
const coverDialog = document.querySelector('#cover-dialog');
const coverFile = document.querySelector('#cover-file');
const coverMessage = document.querySelector('#cover-message');
const cardDialog = document.querySelector('#card-dialog');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const transientCovers = new Map();
const cardNotes = new Map();
let filter = 'all';
let project = '';
let coverBook;
let openCard;
let coverRequest = 0;

function coverKey(book) {
  return 'knowledge-studio-cover-v2:' + book.id;
}

function customCover(book) {
  if (transientCovers.has(book.id)) return transientCovers.get(book.id);
  try { return localStorage.getItem(coverKey(book)); }
  catch { return null; }
}

function automaticTemplate(book) {
  const hash = Array.from(book.id).reduce((value, letter) => (value * 31 + letter.codePointAt(0)) >>> 0, 0);
  return ['template-arch', 'template-botanical', 'template-index'][hash % 3];
}

function showCoverSettings(book) {
  coverBook = book;
  coverFile.value = '';
  coverMessage.textContent = book.original ? '资料带有封面示例图。' : '当前资料支持编辑式占位封面。';
  document.querySelector('#cover-title').textContent = book.title;
  coverDialog.showModal();
}

function paintCover(element, book) {
  const custom = customCover(book);
  const artwork = custom || book.original;
  element.classList.toggle('override', Boolean(artwork));
  element.style.backgroundImage = artwork ? 'url("' + artwork + '")' : '';
  return custom ? '自定义封面' : book.original ? '资料封面' : '自动封面';
}

function tile(book, inLibrary = false) {
  const group = document.createElement('div');
  group.className = 'cover-cell';
  const element = document.createElement(book.route ? 'a' : 'button');
  element.className = 'book-tile';
  element.innerHTML = '<span class="cover-stage ' + book.type + '" aria-hidden="true"><span class="cover ' +
    book.color + ' ' + automaticTemplate(book) + '"><strong>' + book.cover + '</strong><em>' +
    book.roman + '</em><i></i></span></span><span class="book-title">' + book.title +
    '</span><span class="book-meta">' + book.by + ' · ' + book.label + '</span>';
  const cover = element.querySelector('.cover');
  const coverType = paintCover(cover, book);
  if (book.route) {
    element.href = book.route;
    element.dataset.openBook = book.id;
  } else {
    element.type = 'button';
    element.addEventListener('click', () => {
      document.querySelector('#source-kind').textContent = book.label;
      document.querySelector('#source-title').textContent = book.title;
      document.querySelector('#source-by').textContent = book.by + ' · ' + coverType;
      document.querySelector('#source-dialog').showModal();
    });
  }
  group.append(element);
  if (inLibrary) {
    const button = document.createElement('button');
    button.className = 'cover-control';
    button.textContent = coverType + ' · 更换';
    button.setAttribute('aria-label', '更换封面 · ' + book.title);
    button.addEventListener('click', () => showCoverSettings(book));
    group.append(button);
  }
  return group;
}

function renderLibrary() {
  const query = search.value.trim().toLowerCase();
  const matches = books.filter((book) => (!project || project === book.project)
    && (filter === 'all' || filter === book.type)
    && (book.title + ' ' + book.by + ' ' + book.roman).toLowerCase().includes(query));
  document.querySelector('#collection-books').replaceChildren(...matches.map((book) => tile(book, true)));
  document.querySelector('#library-status').textContent = matches.length ? matches.length + ' 项资料' : '没有找到匹配的资料';
  document.querySelector('#collection-title').textContent = project || '全部资料';
  document.querySelectorAll('[data-filter]').forEach((button) => {
    button.setAttribute('aria-pressed', button.dataset.filter === filter);
  });
  document.querySelectorAll('.project-nav a').forEach((link) => {
    const [, target = ''] = decodeURI(link.hash).split('/');
    if (target === project) link.setAttribute('aria-current', 'true');
    else link.removeAttribute('aria-current');
  });
}

function renderRecent() {
  document.querySelector('#recent-books').replaceChildren(...['island', 'city', 'light', 'field'].map(
    (id) => tile(books.find((book) => book.id === id))
  ));
  paintCover(document.querySelector('.resume-cover'), books[0]);
}

async function resizeCover(file) {
  const bitmap = await createImageBitmap(file);
  try {
    const ratio = Math.min(1, 420 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(bitmap.width * ratio));
    canvas.height = Math.max(1, Math.round(bitmap.height * ratio));
    const context = canvas.getContext('2d', { alpha: false });
    context.fillStyle = '#f6f1e8';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/jpeg', .77);
  } finally { bitmap.close(); }
}

function replaceCover(book, image) {
  transientCovers.set(book.id, image);
  try {
    if (image) localStorage.setItem(coverKey(book), image);
    else localStorage.removeItem(coverKey(book));
    coverMessage.textContent = image ? '自定义封面已保存。' : '已恢复资料封面或自动模板。';
  } catch {
    coverMessage.textContent = '封面已更新。当前浏览器仅保留到关闭页面。';
  }
  renderRecent();
  renderLibrary();
}

coverFile.addEventListener('change', async () => {
  const file = coverFile.files[0];
  const book = coverBook;
  const request = ++coverRequest;
  if (!file) return;
  if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 8 * 1024 * 1024) {
    coverMessage.textContent = '请选择 8 MB 以内的 PNG、JPEG 或 WebP。';
    return;
  }
  try {
    const image = await resizeCover(file);
    if (coverDialog.open && request === coverRequest) replaceCover(book, image);
  } catch {
    if (request === coverRequest) coverMessage.textContent = '图片无法读取，请选择另一张图片。';
  }
});
coverDialog.addEventListener('close', () => { coverRequest += 1; });
document.querySelector('#reset-cover').addEventListener('click', () => {
  coverRequest += 1;
  coverFile.value = '';
  replaceCover(coverBook, null);
});

function showCard(card, trigger) {
  openCard = card;
  cardDialog.className = 'full-card tone-' + card.tone;
  document.querySelector('#card-kind').textContent = card.kind;
  document.querySelector('#card-title').textContent = card.title;
  document.querySelector('#card-detail').textContent = card.detail;
  document.querySelector('#card-note').value = cardNotes.get(card) ?? card.note;
  const origin = document.querySelector('#card-origin');
  origin.hidden = !card.route;
  origin.href = card.route || '#home';
  origin.textContent = card.source + ' ↗';
  const start = trigger.getBoundingClientRect();
  cardDialog.showModal();
  if (!reducedMotion.matches) {
    const end = cardDialog.getBoundingClientRect();
    cardDialog.animate([
      { transformOrigin: 'top left', transform: 'translate(' + (start.left - end.left) + 'px,' +
        (start.top - end.top) + 'px) scale(' + Math.min(start.width / end.width, 1) + ')', opacity: .6 },
      { transformOrigin: 'top left', transform: 'none', opacity: 1 }
    ], { duration: 270, easing: 'cubic-bezier(.2,.75,.25,1)' });
  }
}

document.querySelector('#thought-grid').replaceChildren(...cards.map((card) => {
  const button = document.createElement('button');
  button.className = 'thought-card ' + card.style + ' tone-' + card.tone;
  button.innerHTML = '<span class="type-label">' + card.kind + '</span><span class="thought-title">' + card.title +
    '</span><span class="thought-detail">' + card.detail + '</span><span class="thought-footer"><span>' +
    (card.style === 'featured' ? '展开思考笔记' : '打开卡片') + '</span><span aria-hidden="true">↗</span></span>';
  button.addEventListener('click', () => showCard(card, button));
  return button;
}));
document.querySelector('#card-note').addEventListener('input', (event) => cardNotes.set(openCard, event.target.value));
document.querySelector('#card-origin').addEventListener('click', () => cardDialog.close());

function jumpToPassage(element) {
  element.focus({ preventScroll: true });
  element.scrollIntoView({ block: 'nearest' });
  if (!reducedMotion.matches) {
    const color = element.id === 'pdf-anchor' ? '#e9def2' : '#c6dfbf';
    element.animate([{ backgroundColor: color }, { backgroundColor: 'transparent' }], { duration: 450 });
  }
}

function route(hash = location.hash) {
  const [requested, detail = ''] = decodeURI(hash.slice(1)).split('/');
  const view = ['home', 'library', 'reader'].includes(requested) ? requested : 'home';
  document.querySelectorAll('[data-view]').forEach((element) => {
    element.hidden = element.dataset.view !== view;
  });
  document.querySelectorAll('[data-nav]').forEach((link) => {
    if (link.dataset.nav === view) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  });
  if (view === 'library') {
    project = books.some((book) => book.project === detail) ? detail : '';
    filter = 'all';
    search.value = '';
    renderLibrary();
  }
  if (view === 'reader') {
    const pdf = detail.startsWith('pdf');
    const source = books[pdf ? 1 : 0];
    paintCover(document.querySelector('.reader-cover'), source);
    document.querySelector('#reader-book').textContent = source.title;
    document.dispatchEvent(new CustomEvent('reader-format', { detail: pdf ? 'pdf' : 'epub' }));
  }
  document.body.dataset.activeView = view;
  document.title = 'Knowledge Studio · ' + { home: '书桌', library: '资料库', reader: '阅读器' }[view];
  window.scrollTo(0, 0);
  if (detail === 'anchor') jumpToPassage(document.querySelector('#passage'));
  if (detail === 'pdf-anchor') jumpToPassage(document.querySelector('#pdf-anchor'));
}

renderRecent();
document.addEventListener('click', (event) => {
  const link = event.target.closest('[data-open-book]');
  if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
      reducedMotion.matches || !document.startViewTransition) return;
  const cover = link.querySelector('.cover, .resume-cover');
  const target = document.querySelector('.reader-cover');
  target.style.viewTransitionName = '';
  cover.style.viewTransitionName = 'open-book';
  event.preventDefault();
  const transition = document.startViewTransition(() => {
    history.pushState(null, '', link.hash);
    route(link.hash);
    cover.style.viewTransitionName = '';
    target.style.viewTransitionName = 'open-book';
  });
  transition.finished.finally(() => { target.style.viewTransitionName = ''; });
});

document.querySelectorAll('[data-filter]').forEach((button) => {
  button.addEventListener('click', () => {
    filter = button.dataset.filter;
    renderLibrary();
  });
});
search.addEventListener('input', renderLibrary);
document.querySelector('#jump').addEventListener('click', () => jumpToPassage(document.querySelector('#passage')));
document.querySelector('#pdf-jump').addEventListener('click', () => jumpToPassage(document.querySelector('#pdf-anchor')));
document.querySelector('#toggle-notes').addEventListener('click', (event) => {
  const notes = document.querySelector('#marginalia');
  notes.hidden = !notes.hidden;
  document.querySelector('#reader-grid').classList.toggle('single', notes.hidden);
  event.currentTarget.setAttribute('aria-expanded', !notes.hidden);
});
window.addEventListener('hashchange', () => route());
