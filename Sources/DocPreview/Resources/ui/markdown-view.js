'use strict';
// Markdown を GitHub 風に描画する。親ウィンドウ(同一オリジン)の dpSettings を参照する。
(async () => {
  const settings = (window.parent && window.parent.dpSettings) || { theme: 'light', fontSize: 16 };
  const dark = settings.theme === 'dark' ||
    (settings.theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  const base = 'docpreview://app/ui/vendor/';
  const addCss = (href) => new Promise((ok) => {
    const l = document.createElement('link');
    l.rel = 'stylesheet'; l.href = href; l.onload = l.onerror = ok;
    document.head.append(l);
  });
  const addJs = (src) => new Promise((ok, ng) => {
    const s = document.createElement('script');
    s.src = src; s.onload = ok; s.onerror = ng;
    document.head.append(s);
  });

  await Promise.all([
    addCss(base + (dark ? 'github-markdown-dark.css' : 'github-markdown-light.css')),
    addCss(base + (dark ? 'github-dark.min.css' : 'github.min.css')),
  ]);
  await Promise.all([addJs(base + 'marked.min.js'), addJs(base + 'highlight.min.js')]);

  const article = document.getElementById('content');
  article.style.fontSize = settings.fontSize + 'px';
  article.innerHTML = marked.parse(window.__SOURCE__, { gfm: true });

  // GitHub 互換の見出しアンカー
  const seen = {};
  article.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach((h) => {
    let slug = h.textContent.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\p{M}\s_-]/gu, '').replace(/\s/g, '-');
    seen[slug] = (seen[slug] ?? -1) + 1;
    h.id = seen[slug] ? `${slug}-${seen[slug]}` : slug;
  });

  // コードのシンタックスハイライトと mermaid 図
  const diagrams = [];
  article.querySelectorAll('pre > code').forEach((code) => {
    if (/\blanguage-mermaid\b/.test(code.className)) {
      const div = document.createElement('div');
      div.className = 'mermaid'; div.textContent = code.textContent;
      code.parentElement.replaceWith(div);
      diagrams.push(div);
    } else {
      try { hljs.highlightElement(code); } catch {}
    }
  });

  // ページ背景を GitHub のテーマ色に合わせる
  document.body.style.background = getComputedStyle(article).backgroundColor;

  if (diagrams.length) {
    try {
      await addJs(base + 'mermaid.min.js');
      mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'strict' });
      await mermaid.run({ nodes: diagrams });
    } catch (e) {
      diagrams.forEach((d) => { if (!d.querySelector('svg')) d.classList.add('mermaid-error'); });
    }
  }
  window.__RENDERED__ = true;
  if (window.parent && window.parent.dpDocReady) window.parent.dpDocReady();
})();
