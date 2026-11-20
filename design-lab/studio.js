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
  { title: '岛屿的另一种读法', cover: '岛屿的<br>另一种<br>读法', roman: 'Island Notes', by: '林屿', type: 'epub', label: 'EPUB', color: 'plum', project: '城市与记忆', readable: true },
  { title: '城市的背面', cover: '城市的<br>背面', roman: 'The Other City', by: '周岸', type: 'pdf', label: 'PDF', color: 'sage', project: '城市与记忆' },
  { title: '论散步', cover: '论散步', roman: 'On Walking', by: '陈野', type: 'epub', label: 'EPUB', color: 'wheat', project: '阅读笔记' },
  { title: '街巷档案', cover: '街巷档案', roman: 'Street Archive', by: '叶令', type: 'pdf', label: 'PDF', color: 'clay', project: '城市与记忆' },
  { title: '谈光线与门廊', cover: '谈光线<br>与门廊', roman: 'Light & Thresholds', by: '书房访谈', type: 'video', label: '视频 · 12:48', color: 'video', project: '城市与记忆' },
  { title: '重新读一页', cover: '重新读<br>一页', roman: 'Another Page', by: '白羽', type: 'epub', label: 'EPUB', color: 'rose', project: '阅读笔记' }
];
const dialog = document.querySelector('#source-dialog');
const search = document.querySelector('#search');
let filter = 'all';
let project = '';

function tile(book) {
  const element = document.createElement(book.readable ? 'a' : 'button');
  element.className = 'book-tile';
  element.innerHTML = '<span class="cover-stage ' + book.type + '" aria-hidden="true"><span class="cover ' + book.color + '"><strong>' + book.cover +
    '</strong><em>' + book.roman + '</em><i></i></span></span><span class="book-title">' + book.title +
    '</span><span class="book-meta">' + book.by + ' · ' + book.label + '</span>';
  if (book.readable) {
    element.href = '#reader';
  } else {
    element.type = 'button';
    element.addEventListener('click', () => {
      document.querySelector('#source-kind').textContent = book.label;
      document.querySelector('#source-title').textContent = book.title;
      document.querySelector('#source-by').textContent = book.by;
      dialog.showModal();
    });
  }
  return element;
}

function renderLibrary() {
  const query = search.value.trim().toLowerCase();
  const matches = books.filter((book) => (!project || project === book.project)
    && (filter === 'all' || filter === book.type)
    && (book.title + ' ' + book.by + ' ' + book.roman).toLowerCase().includes(query));
  document.querySelector('#collection-books').replaceChildren(...matches.map(tile));
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

function jumpToPassage() {
  const passage = document.querySelector('#passage');
  passage.focus({ preventScroll: true });
  passage.scrollIntoView({ block: 'nearest' });
  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
    passage.animate([{ backgroundColor: '#c6dfbf' }, { backgroundColor: 'transparent' }], { duration: 450 });
  }
}

function route() {
  const [requested, detail = ''] = decodeURI(location.hash.slice(1)).split('/');
  const view = ['home', 'library', 'reader'].includes(requested) ? requested : 'home';
  document.querySelectorAll('[data-view]').forEach((element) => {
    element.hidden = element.dataset.view !== view;
  });
  document.querySelectorAll('[data-nav]').forEach((link) => {
    if (link.dataset.nav === view) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  });
  if (view === 'library') {
    project = ['城市与记忆', '阅读笔记'].includes(detail) ? detail : '';
    filter = 'all';
    search.value = '';
    renderLibrary();
  }
  document.body.dataset.activeView = view;
  document.title = 'Knowledge Studio · ' + { home: '书桌', library: '资料库', reader: '阅读器' }[view];
  window.scrollTo(0, 0);
  if (view === 'reader' && detail === 'anchor') jumpToPassage();
}

document.querySelector('#recent-books').replaceChildren(...books.slice(0, 3).map(tile));
document.querySelectorAll('[data-filter]').forEach((button) => {
  button.addEventListener('click', () => {
    filter = button.dataset.filter;
    renderLibrary();
  });
});
search.addEventListener('input', renderLibrary);
document.querySelector('#jump').addEventListener('click', jumpToPassage);
document.querySelector('#toggle-notes').addEventListener('click', (event) => {
  const notes = document.querySelector('#marginalia');
  notes.hidden = !notes.hidden;
  document.querySelector('#reader-grid').classList.toggle('single', notes.hidden);
  event.currentTarget.setAttribute('aria-expanded', !notes.hidden);
});
window.addEventListener('hashchange', route);
route();
