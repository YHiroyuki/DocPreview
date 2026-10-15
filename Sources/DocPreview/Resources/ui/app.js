'use strict';

const native = (action, extra = {}) =>
  window.webkit.messageHandlers.native.postMessage({ action, ...extra });

const $ = (id) => document.getElementById(id);
const state = {
  name: '', root: '', tree: null, comments: [],
  current: null, mtime: 0, treeSig: null,
  open: new Set(['']), pending: null, showHidden: false, loading: new Set(),
};
const frame = $('doc');
window.dpSettings = { theme: 'light', fontSize: 16, leftWidth: 260, rightWidth: 300 };
const CTX = 30; // 選択範囲の前後に保存する文脈の文字数

// ---------- ユーティリティ ----------
function toast(msg, ms = 3000) {
  const t = $('toast');
  t.textContent = msg; t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), ms);
}
const uid = () => Math.random().toString(36).slice(2, 10);
const docUrl = (p) => 'docpreview://app/doc/' + p.split('/').map(encodeURIComponent).join('/');
const pathFromUrl = (u) => decodeURIComponent(new URL(u).pathname.replace(/^\/doc\//, ''));

function saveComments() {
  native('saveComments', { json: JSON.stringify(state.comments) });
  renderTree();
  renderComments();
}
const fileComments = () => state.comments.filter((c) => c.file === state.current);

// ---------- ファイルツリー ----------
const svg = (d) => `<svg class="ic" viewBox="0 0 16 16" width="14" height="14" fill="currentColor" aria-hidden="true">${d}</svg>`;
const ICONS = {
  eye: svg('<path d="M8 3C4.4 3 1.7 5.4.5 8c1.2 2.6 3.9 5 7.5 5s6.3-2.4 7.5-5C14.3 5.4 11.6 3 8 3zm0 1.5A3.5 3.5 0 1 1 8 11.5 3.5 3.5 0 0 1 8 4.5zM8 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>'),
  chevron: svg('<path d="M6 3.5 10.5 8 6 12.5z"/>'),
  folder: svg('<path d="M1.75 2.5A1.75 1.75 0 0 0 0 4.25v7.5C0 12.72.78 13.5 1.75 13.5h12.5c.97 0 1.75-.78 1.75-1.75v-6.5c0-.97-.78-1.75-1.75-1.75H7.7L6.4 2.7a1.75 1.75 0 0 0-1.24-.2z"/>'),
  folderOpen: svg('<path d="M.5 3.75C.5 2.78 1.28 2 2.25 2h2.9c.46 0 .9.18 1.24.5L7.5 3.5h5.25c.97 0 1.75.78 1.75 1.75V6H3.4a1.75 1.75 0 0 0-1.67 1.22L.5 11.2zM2.2 7.5h12.9c.55 0 .93.54.74 1.05l-1.5 4.2a1.25 1.25 0 0 1-1.18.83H2A1.25 1.25 0 0 1 .8 12.1l1.2-3.7c.2-.5.65-.9 1.2-.9z"/>'),
  md: svg('<path d="M3.75 1A1.75 1.75 0 0 0 2 2.75v10.5C2 14.22 2.78 15 3.75 15h8.5c.97 0 1.75-.78 1.75-1.75V5.5L9.5 1zM9 2.5l3.5 3.5H10A1 1 0 0 1 9 5zM4.5 9h1.1l1 1.6L7.7 9h1.1v3.5H7.7v-1.8l-1.1 1.4-1-1.4v1.8H4.5zm5.2 0h1.1v1.7l.7-.8.8.6-1.6 1.9-1.5-1.9.8-.6.7.8z"/>'),
  html: svg('<path d="M3.75 1A1.75 1.75 0 0 0 2 2.75v10.5C2 14.22 2.78 15 3.75 15h8.5c.97 0 1.75-.78 1.75-1.75V5.5L9.5 1zM9 2.5l3.5 3.5H10A1 1 0 0 1 9 5zM6.2 8.2 4.4 10l1.8 1.8-.8.8L2.8 10l2.6-2.6zm3.6 0 .8-.8L13.2 10l-2.6 2.6-.8-.8L11.6 10z"/>'),
};
const fileIcon = (name) => (/\.html?$/i.test(name) ? ICONS.html : ICONS.md);

function renderTree() {
  $('sidebar-name').textContent = state.name;
  $('toggle-hidden').innerHTML = ICONS.eye;
  $('toggle-hidden').classList.toggle('on', state.showHidden);
  const counts = {};
  state.comments.filter((c) => !c.sent).forEach((c) => (counts[c.file] = (counts[c.file] || 0) + 1));

  const build = (node) => {
    const el = document.createElement('div');
    const label = document.createElement('div');
    label.className = 'node';
    label.title = node.path;
    const name = document.createElement('span');
    name.className = 'name'; name.textContent = node.name;
    const icon = document.createElement('span');
    icon.className = 'icon';
    if (node.type === 'dir') {
      const open = state.open.has(node.path);
      const chev = document.createElement('span');
      chev.className = 'chev'; chev.innerHTML = ICONS.chevron;
      icon.innerHTML = open ? ICONS.folderOpen : ICONS.folder;
      if (node.lazy && !node.loaded && open) loadChildren(node);
      if (state.loading.has(node.path)) {
        const l = document.createElement('span'); l.className = 'loading'; l.textContent = '読み込み中…';
        label.append(l);
      }
      icon.classList.add('folder');
      label.append(chev, icon, name);
      el.className = 'dir' + (open ? ' open' : '');
      label.onclick = () => {
        state.open.has(node.path) ? state.open.delete(node.path) : state.open.add(node.path);
        renderTree();
      };
      el.append(label);
      const kids = document.createElement('div');
      kids.className = 'children';
      node.children.forEach((c) => kids.append(build(c)));
      el.append(kids);
    } else {
      if (node.path === state.current) label.classList.add('active');
      icon.innerHTML = fileIcon(node.name);
      label.append(icon, name);
      if (counts[node.path]) {
        const b = document.createElement('span');
        b.className = 'badge'; b.textContent = counts[node.path];
        label.append(b);
      }
      label.onclick = () => openFile(node.path);
      el.append(label);
    }
    return el;
  };

  const tree = $('tree');
  tree.replaceChildren();
  // ルート直下は常に展開して子だけを並べる
  state.tree.children.forEach((c) => tree.append(build(c)));
}

// 隠しフォルダ（.claude など）の中身は、開いたときに初めて読み込む
async function loadChildren(node) {
  if (state.loading.has(node.path)) return;
  state.loading.add(node.path);
  try {
    node.children = await native('children', { path: node.path });
    node.loaded = true;
  } catch { node.loaded = true; }
  state.loading.delete(node.path);
  renderTree();
}

function expandTo(path) {
  const parts = path.split('/').slice(0, -1);
  let acc = '';
  parts.forEach((p) => { acc = acc ? acc + '/' + p : p; state.open.add(acc); });
}

function firstFile(node) {
  for (const c of node.children || []) {
    if (c.type === 'file') return c.path;
    const f = firstFile(c); if (f) return f;
  }
  return null;
}

// ---------- ドキュメント表示 ----------
const reportTitle = () => state.current && native('title', { name: state.current.split('/').pop() });

function openFile(path, scrollY = 0) {
  state.current = path;
  reportTitle();
  state.mtime = 0;
  state.scrollY = scrollY;
  expandTo(path);
  hideAddUi();
  $('empty').hidden = true;
  frame.hidden = false;
  frame.src = docUrl(path);
  renderTree();
  renderComments();
}

// Markdown は非同期に描画されるため、描画完了後に markdown-view.js が dpDocReady を呼ぶ
window.dpDocReady = () => onDocLoaded();
frame.addEventListener('load', () => {
  try {
    const d = frame.contentDocument;
    if (d && d.getElementById('content') && !frame.contentWindow.__RENDERED__) return;
  } catch { return; }
  onDocLoaded();
});

function onDocLoaded() {
  let doc, win;
  try { doc = frame.contentDocument; win = frame.contentWindow; if (!doc) return; } catch { return; }
  if (win.__HANDLED__) return;
  win.__HANDLED__ = true;
  // iframe 内のリンクで別ファイルに遷移した場合に追従する
  try {
    const p = pathFromUrl(win.location.href);
    if (p !== state.current) { state.current = p; reportTitle(); expandTo(p); renderTree(); renderComments(); }
  } catch {}

  const dark = dpSettings.theme === 'dark' || (dpSettings.theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  const style = doc.createElement('style');
  style.textContent = dark
    ? 'mark.dp-hl{background:#3d59a1;color:#c0caf5;cursor:pointer;border-radius:2px}mark.dp-hl.dp-focus{background:#6183bb}' +
      'mark.dp-find{background:#e0af68;color:#1a1b26;border-radius:2px}mark.dp-find.dp-cur{background:#ff9e64;outline:2px solid #ff9e64}'
    : 'mark.dp-hl{background:#e6c98b;color:#343b58;cursor:pointer;border-radius:2px}mark.dp-hl.dp-focus{background:#d9a95a}' +
      'mark.dp-find{background:#f0c36d;color:#343b58;border-radius:2px}mark.dp-find.dp-cur{background:#e98a3c;outline:2px solid #e98a3c}';
  doc.head.append(style);
  doc.addEventListener('mouseup', () => setTimeout(() => onSelect(doc, win), 0));
  doc.addEventListener('mousedown', hideAddUi);
  doc.addEventListener('click', (e) => {
    const m = e.target.closest && e.target.closest('mark.dp-hl');
    if (m) focusComment(m.dataset.cid, false);
  });
  applyHighlights();
  if (state.scrollY) win.scrollTo(0, state.scrollY);
  if (!$('findbar').hidden) runFind(false);
  native('poll', { path: state.current }).then((r) => (state.mtime = r.mtime));
}

// ---------- テキスト索引とハイライト ----------
function buildIndex(doc) {
  const nodes = []; let text = '';
  const w = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) => /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE)$/.test(n.parentNode.nodeName) || n.parentElement.closest('svg')
      ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  });
  for (let n; (n = w.nextNode());) { nodes.push({ node: n, start: text.length }); text += n.data; }
  return { nodes, text };
}

function boundaryOffset(idx, doc, container, off) {
  const b = doc.createRange(); b.setStart(container, off); b.collapse(true);
  for (const { node, start } of idx.nodes) {
    if (node === container) return start + off;
    if (b.comparePoint(node, 0) > 0) return start;
  }
  return idx.text.length;
}

function clearFind(doc) {
  doc.querySelectorAll('mark.dp-find').forEach((m) => {
    const p = m.parentNode;
    while (m.firstChild) p.insertBefore(m.firstChild, m);
    p.removeChild(m);
    p.normalize();
  });
}

function clearHighlights(doc) {
  doc.querySelectorAll('mark.dp-hl').forEach((m) => {
    const p = m.parentNode;
    while (m.firstChild) p.insertBefore(m.firstChild, m);
    p.removeChild(m);
    p.normalize();
  });
}

function locate(text, c) {
  let best = -1, bestScore = -1;
  for (let i = text.indexOf(c.quote); i !== -1; i = text.indexOf(c.quote, i + 1)) {
    let score = 0;
    const before = text.slice(Math.max(0, i - c.prefix.length), i);
    const after = text.slice(i + c.quote.length, i + c.quote.length + c.suffix.length);
    for (let k = 1; k <= Math.min(before.length, c.prefix.length); k++)
      if (before[before.length - k] === c.prefix[c.prefix.length - k]) score++; else break;
    for (let k = 0; k < Math.min(after.length, c.suffix.length); k++)
      if (after[k] === c.suffix[k]) score++; else break;
    if (score > bestScore) { best = i; bestScore = score; }
  }
  return best;
}

function applyHighlights() {
  let doc; try { doc = frame.contentDocument; } catch { return; }
  if (!doc || !doc.body) return;
  clearHighlights(doc);
  state.orphans = new Set();
  for (const c of fileComments()) {
    const idx = buildIndex(doc);
    const s = c.quote ? locate(idx.text, c) : -1;
    if (s < 0) { state.orphans.add(c.id); continue; }
    const e = s + c.quote.length;
    for (const { node, start } of [...idx.nodes].reverse()) {
      const end = start + node.data.length;
      if (end <= s || start >= e) continue;
      const r = doc.createRange();
      r.setStart(node, Math.max(s, start) - start);
      r.setEnd(node, Math.min(e, end) - start);
      if (r.collapsed) continue;
      const m = doc.createElement('mark');
      m.className = 'dp-hl'; m.dataset.cid = c.id;
      r.surroundContents(m);
    }
  }
  renderComments();
  if (!$('findbar').hidden && find.matches !== undefined) runFind(false);
}

// ---------- 選択 → コメント追加 ----------
function hideAddUi() { $('add-btn').hidden = true; }

function onSelect(doc, win) {
  const sel = win.getSelection();
  if (!sel || sel.isCollapsed || !sel.toString().trim()) return hideAddUi();
  const r = sel.getRangeAt(0);
  const idx = buildIndex(doc);
  const s = boundaryOffset(idx, doc, r.startContainer, r.startOffset);
  const e = boundaryOffset(idx, doc, r.endContainer, r.endOffset);
  if (e <= s) return hideAddUi();
  state.pending = {
    quote: idx.text.slice(s, e),
    prefix: idx.text.slice(Math.max(0, s - CTX), s),
    suffix: idx.text.slice(e, e + CTX),
  };
  const fr = frame.getBoundingClientRect(), rr = r.getBoundingClientRect();
  const btn = $('add-btn');
  btn.hidden = false;
  btn.style.left = Math.min(window.innerWidth - 110, fr.left + rr.right) + 'px';
  btn.style.top = Math.min(window.innerHeight - 40, fr.top + rr.bottom + 6) + 'px';
}

$('add-btn').addEventListener('mousedown', (e) => e.preventDefault());
$('add-btn').onclick = () => {
  const btn = $('add-btn'), pop = $('popover');
  hideAddUi();
  $('pop-quote').textContent = state.pending.quote;
  $('pop-text').value = '';
  pop.hidden = false;
  pop.style.left = Math.max(8, Math.min(window.innerWidth - 340, parseFloat(btn.style.left) - 160)) + 'px';
  pop.style.top = Math.min(window.innerHeight - 220, parseFloat(btn.style.top)) + 'px';
  $('pop-text').focus();
};
const closePopover = () => { $('popover').hidden = true; state.pending = null; };
$('pop-cancel').onclick = closePopover;
$('pop-ok').onclick = () => {
  const text = $('pop-text').value.trim();
  if (!text || !state.pending) return;
  state.comments.push({
    id: uid(), file: state.current, ...state.pending,
    text, sent: false, createdAt: new Date().toISOString(),
  });
  closePopover();
  saveComments();
  applyHighlights();
};
$('pop-text').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) $('pop-ok').click();
  if (e.key === 'Escape') closePopover();
});

// ---------- コメント一覧 ----------
function renderComments() {
  const list = $('comment-list');
  const cs = fileComments();
  $('comment-count').textContent = cs.length ? `(${cs.length})` : '';
  const unsent = cs.filter((c) => !c.sent).length;
  $('send').disabled = !unsent;
  $('copy-prompt').disabled = !unsent;
  $('send').textContent = unsent ? `Claude Code に依頼 (${unsent})` : 'Claude Code に依頼';
  list.replaceChildren();
  if (!cs.length) {
    list.innerHTML = '<div style="color:var(--muted);padding:8px">本文の範囲を選択すると、コメントを追加できます。</div>';
    return;
  }
  for (const c of cs) {
    const el = document.createElement('div');
    el.className = 'comment' + (c.sent ? ' sent' : '') + (state.orphans && state.orphans.has(c.id) ? ' orphan' : '');
    el.dataset.cid = c.id;
    const q = document.createElement('div'); q.className = 'q'; q.textContent = c.quote;
    const t = document.createElement('div'); t.className = 't'; t.textContent = c.text;
    const meta = document.createElement('div'); meta.className = 'meta';
    const when = document.createElement('span');
    when.textContent = (c.sent ? '送信済み ・ ' : '') + new Date(c.createdAt).toLocaleString('ja-JP');
    const del = document.createElement('a'); del.textContent = '削除';
    del.onclick = (ev) => {
      ev.stopPropagation();
      state.comments = state.comments.filter((x) => x.id !== c.id);
      saveComments(); applyHighlights();
    };
    meta.append(when, del);
    el.append(q, t, meta);
    el.onclick = () => focusComment(c.id, true);
    list.append(el);
  }
}

function focusComment(id, scrollDoc) {
  let doc; try { doc = frame.contentDocument; } catch { return; }
  doc.querySelectorAll('mark.dp-focus').forEach((m) => m.classList.remove('dp-focus'));
  const marks = doc.querySelectorAll(`mark[data-cid="${id}"]`);
  marks.forEach((m) => m.classList.add('dp-focus'));
  if (scrollDoc && marks[0]) marks[0].scrollIntoView({ block: 'center', behavior: 'smooth' });
  const el = document.querySelector(`.comment[data-cid="${id}"]`);
  if (el && !scrollDoc) el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

// ---------- Claude Code 連携 ----------
function buildPrompt(cs) {
  const abs = state.root + '/' + state.current;
  const body = cs.map((c, i) => [
    `### コメント ${i + 1}`,
    '対象の引用（プレビュー上の表示テキスト）:',
    ...c.quote.split('\n').map((l) => '> ' + l),
    `前後の文脈: …${c.prefix.replace(/\n/g, ' ')}【${c.quote.replace(/\n/g, ' ')}】${c.suffix.replace(/\n/g, ' ')}…`,
    `コメント: ${c.text}`,
  ].join('\n')).join('\n\n');
  return [
    `DocPreview で次のファイルにレビューコメントを付けました: ${abs}`,
    '',
    '各コメントは、プレビュー上でテキストを選択して付けたものです。引用はレンダリング後のテキストなので、',
    'Markdown の記法（強調記号やリンク記法など）は含まれていない場合があります。該当箇所をソースから探してください。',
    '',
    'すべてのコメントの内容に従って、このファイルを編集して対応してください。',
    '意図が曖昧なコメントがあれば、編集する前に質問してください。',
    '',
    body,
  ].join('\n');
}

// cmux を使わず、依頼文をクリップボードに置く（任意の Claude Code セッションに貼り付けて使う）。
// 送信済みにはしない（実際に渡ったかどうかは分からないため）。
$('copy-prompt').onclick = async () => {
  const cs = fileComments().filter((c) => !c.sent);
  if (!cs.length) return;
  try {
    await native('copyText', { text: buildPrompt(cs) });
    toast(`依頼文をコピーしました（コメント ${cs.length} 件）`);
  } catch (e) {
    toast(String(e.message || e), 6000);
  }
};

$('send').onclick = async () => {
  const cs = fileComments().filter((c) => !c.sent);
  if (!cs.length) return;
  $('send').disabled = true;
  try {
    await native('launchClaude', { prompt: buildPrompt(cs) });
    cs.forEach((c) => (c.sent = true));
    saveComments();
    toast('cmux で Claude Code を起動しました');
  } catch (e) {
    toast(String(e.message || e), 6000);
  }
  renderComments();
};

// ---------- 変更の監視（Claude Code による編集を自動反映） ----------
setInterval(async () => {
  if (!state.root) return;
  try {
    const r = await native('poll', { path: state.current || '' });
    if (state.treeSig !== null && r.tree !== state.treeSig) {
      state.tree = await native('tree'); renderTree();
    }
    state.treeSig = r.tree;
    if (state.current && state.mtime && r.mtime !== state.mtime && $('popover').hidden) {
      let y = 0; try { y = frame.contentWindow.scrollY; } catch {}
      state.scrollY = y; state.mtime = r.mtime;
      frame.contentWindow.location.reload();
    }
  } catch {}
}, 1500);

// ---------- ファイル内検索 (⌘F) ----------
const find = { matches: undefined, cur: -1, caseSensitive: false, regex: false };
const FIND_LIMIT = 5000;

function openFind() {
  const bar = $('findbar'), input = $('find-input');
  let sel = '';
  try { sel = frame.contentWindow.getSelection().toString(); } catch {}
  if (sel && !sel.includes('\n')) input.value = sel;
  bar.hidden = false;
  input.focus(); input.select();
  runFind(true);
}
function closeFind() {
  $('findbar').hidden = true;
  try { clearFind(frame.contentDocument); } catch {}
  find.matches = undefined;
}

function buildMatcher() {
  const q = $('find-input').value;
  if (!q) return null;
  const src = find.regex ? q : q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(src, 'g' + (find.caseSensitive ? '' : 'i') + 'u');
}

function runFind(jump) {
  let doc; try { doc = frame.contentDocument; } catch { return; }
  if (!doc || !doc.body) return;
  clearFind(doc);
  const input = $('find-input'), count = $('find-count');
  input.classList.remove('invalid');
  find.matches = []; find.cur = -1;
  let re;
  try { re = buildMatcher(); } catch (e) {
    input.classList.add('invalid'); count.textContent = '正規表現が不正'; return;
  }
  if (!re) { count.textContent = ''; return; }

  const idx = buildIndex(doc);
  for (let m; (m = re.exec(idx.text)) && find.matches.length < FIND_LIMIT;) {
    if (m[0].length === 0) { re.lastIndex++; continue; } // 空マッチは無視
    find.matches.push([m.index, m.index + m[0].length]);
  }
  // 後ろのマッチから順にラップする（前方のオフセットが崩れない）
  for (let i = find.matches.length - 1; i >= 0; i--) {
    const [s, e] = find.matches[i];
    for (const { node, start } of [...idx.nodes].reverse()) {
      const end = start + node.data.length;
      if (end <= s || start >= e) continue;
      const r = doc.createRange();
      r.setStart(node, Math.max(s, start) - start);
      r.setEnd(node, Math.min(e, end) - start);
      if (r.collapsed) continue;
      const mk = doc.createElement('mark');
      mk.className = 'dp-find'; mk.dataset.fid = i;
      r.surroundContents(mk);
    }
  }
  if (find.matches.length) gotoMatch(find.cur >= 0 ? find.cur : 0, jump);
  else count.textContent = '見つかりません';
}

function gotoMatch(i, scroll = true) {
  const n = find.matches.length;
  if (!n) return;
  find.cur = (i + n) % n;
  let doc; try { doc = frame.contentDocument; } catch { return; }
  doc.querySelectorAll('mark.dp-cur').forEach((m) => m.classList.remove('dp-cur'));
  const marks = doc.querySelectorAll(`mark.dp-find[data-fid="${find.cur}"]`);
  marks.forEach((m) => m.classList.add('dp-cur'));
  if (scroll && marks[0]) marks[0].scrollIntoView({ block: 'center' });
  $('find-count').textContent = `${find.cur + 1} / ${n}${n >= FIND_LIMIT ? '+' : ''}`;
}
const findNext = () => { if (find.matches === undefined) return openFind(); gotoMatch(find.cur + 1); };
const findPrev = () => { if (find.matches === undefined) return openFind(); gotoMatch(find.cur - 1); };

let findTimer;
$('find-input').addEventListener('input', () => { clearTimeout(findTimer); findTimer = setTimeout(() => runFind(true), 120); });
$('find-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); e.shiftKey ? findPrev() : findNext(); }
  if (e.key === 'Escape') closeFind();
});
$('find-next').onclick = findNext;
$('find-prev').onclick = findPrev;
$('find-close').onclick = closeFind;
$('find-case').onclick = (e) => { find.caseSensitive = !find.caseSensitive; e.currentTarget.classList.toggle('on', find.caseSensitive); runFind(true); };
$('find-regex').onclick = (e) => { find.regex = !find.regex; e.currentTarget.classList.toggle('on', find.regex); runFind(true); };

// ---------- 隠しフォルダの表示切替 ----------
$('toggle-hidden').onclick = async () => {
  state.showHidden = !state.showHidden;
  state.tree = await native('setShowHidden', { value: state.showHidden });
  renderTree();
};

// ---------- 設定 (⌘,) ----------
function applySettings() {
  document.documentElement.dataset.theme = dpSettings.theme;
  document.documentElement.style.fontSize = '';
}
function openSettings() {
  $('set-theme').value = dpSettings.theme;
  $('set-font').value = dpSettings.fontSize;
  $('modal').hidden = false;
}
function changeSettings() {
  const size = Math.min(32, Math.max(10, parseInt($('set-font').value, 10) || 16));
  dpSettings.theme = $('set-theme').value;
  dpSettings.fontSize = size;
  native('saveSettings', { settings: dpSettings });
  applySettings();
  if (state.current && !frame.hidden) {
    let y = 0; try { y = frame.contentWindow.scrollY; } catch {}
    state.scrollY = y;
    frame.contentWindow.location.reload();
  }
}
$('set-theme').onchange = changeSettings;
$('set-font').onchange = changeSettings;
$('set-close').onclick = () => ($('modal').hidden = true);
$('modal').onclick = (e) => { if (e.target.id === 'modal') $('modal').hidden = true; };
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { $('modal').hidden = true; if (!$('findbar').hidden) closeFind(); } });

// ---------- ペイン幅の調整 ----------
const PANE = { left: { min: 160, max: 600, def: 260 }, right: { min: 220, max: 700, def: 300 } };
function applyPaneWidths() {
  $('app').style.setProperty('--left', dpSettings.leftWidth + 'px');
  $('app').style.setProperty('--right', dpSettings.rightWidth + 'px');
}
function setupResizer(id, side) {
  const el = $(id), cfg = PANE[side], key = side + 'Width';
  el.addEventListener('pointerdown', (e) => {
    el.setPointerCapture(e.pointerId); // iframe 上でもドラッグを追従する
    el.classList.add('dragging');
    document.body.style.userSelect = 'none';
  });
  el.addEventListener('pointermove', (e) => {
    if (!el.hasPointerCapture(e.pointerId)) return;
    const w = side === 'left' ? e.clientX : window.innerWidth - e.clientX;
    // 本文が潰れないよう、反対側の幅と本文の最小幅(320px)を考慮して上限を決める
    const other = side === 'left' ? dpSettings.rightWidth : dpSettings.leftWidth;
    const max = Math.min(cfg.max, window.innerWidth - other - 320);
    dpSettings[key] = Math.round(Math.max(cfg.min, Math.min(max, w)));
    applyPaneWidths();
  });
  const end = (e) => {
    if (!el.classList.contains('dragging')) return;
    el.classList.remove('dragging');
    document.body.style.userSelect = '';
    native('saveSettings', { settings: dpSettings });
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
  el.addEventListener('dblclick', () => {
    dpSettings[key] = cfg.def; applyPaneWidths();
    native('saveSettings', { settings: dpSettings });
  });
}
setupResizer('rz-left', 'left');
setupResizer('rz-right', 'right');

// ---------- 起動 ----------
(async () => {
  const init = await native('init');
  Object.assign(state, { name: init.name, root: init.root, tree: init.tree, showHidden: init.showHidden, comments: JSON.parse(init.comments || '[]') });
  Object.assign(dpSettings, init.settings || {});
  applySettings();
  applyPaneWidths();
  renderTree();
  renderComments();
  let first = init.initialFile;
  if (!first && init.initialDir) {
    // ディレクトリ指定で開いた場合は、その場所を展開して配下の最初のファイルを開く
    state.open.add(init.initialDir);
    expandTo(init.initialDir + '/x');
    const find = (n) => (n.path === init.initialDir ? n : (n.children || []).map(find).find(Boolean));
    const dirNode = find(init.tree);
    first = dirNode && firstFile(dirNode);
  }
  first = first || firstFile(init.tree);
  if (first) openFile(first);
})();
