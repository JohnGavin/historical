// Shared JS for all historicaldata vignettes

// Default to dark mode
if (!localStorage.getItem('quarto-color-scheme')) {
  document.documentElement.setAttribute('data-bs-theme', 'dark');
}

// Keep the live `color-scheme` signal in sync with the active bslib theme
// (historical#0b412a9c). The page's STATIC <meta name="color-scheme"> and
// CSS (see docs/_quarto.yml's project-level include-in-header) always say
// "dark" -- that is what check_dashboard_color_scheme.sh greps for in the
// post-render gate, and per Chrome's Auto Dark Mode heuristic ANY
// color-scheme declaration suppresses the auto-invert behavior regardless
// of which value it names. This keeps the LIVE value accurate to what is
// actually on screen (native scrollbar/form-control chrome, and the same
// suppression) once the user toggles to the light theme.
(function () {
  function hdSyncColorScheme() {
    var theme = document.documentElement.getAttribute('data-bs-theme') || 'dark';
    document.documentElement.style.setProperty('color-scheme', theme);
    var meta = document.querySelector('meta[name="color-scheme"]');
    if (meta) meta.setAttribute('content', theme);
  }
  hdSyncColorScheme();
  if (window.MutationObserver) {
    new MutationObserver(hdSyncColorScheme).observe(document.documentElement, {
      attributes: true, attributeFilter: ['data-bs-theme']
    });
  }
})();

// Quarto's own dark/light toggle swaps the Bootstrap stylesheet and sets
// body.quarto-light / body.quarto-dark, but never touches data-bs-theme. The
// default-to-dark line above leaves data-bs-theme="dark" behind, so after a
// toggle to light the page kept Bootstrap's DARK colour variables (dark body
// background and pale text under a light header) and every
// [data-bs-theme="light"] rule in vignette-shared.css stayed inactive. Mirror
// the body class onto data-bs-theme so the two signals agree.
document.addEventListener('DOMContentLoaded', function () {
  function hdSyncThemeFromBody() {
    var cl = document.body.classList;
    if (cl.contains('quarto-light')) {
      document.documentElement.setAttribute('data-bs-theme', 'light');
    } else if (cl.contains('quarto-dark')) {
      document.documentElement.setAttribute('data-bs-theme', 'dark');
    }
  }
  hdSyncThemeFromBody();
  if (window.MutationObserver) {
    new MutationObserver(hdSyncThemeFromBody).observe(document.body, {
      attributes: true, attributeFilter: ['class']
    });
  }
});

// Font size +/- controls (historical#0b412a9c). Steps a CSS custom property
// (see body { font-size: var(--base-font-size) } in vignette-shared.css)
// rather than rewriting element styles directly, and persists the choice
// across pages via localStorage so it survives navigation.
(function () {
  var MIN_FONT = 0.8, MAX_FONT = 2.0, STEP = 0.1, DEFAULT_FONT = 1.3;
  var STORAGE_KEY = 'hd-base-font-size';

  function getFontSize() {
    var stored = parseFloat(localStorage.getItem(STORAGE_KEY));
    return isNaN(stored) ? DEFAULT_FONT : stored;
  }
  function applyFontSize(size) {
    document.documentElement.style.setProperty('--base-font-size', size + 'em');
  }
  // Apply immediately (before DOMContentLoaded) to avoid a flash of the default size.
  applyFontSize(getFontSize());

  window.hdAdjustFontSize = function (delta) {
    var size = getFontSize();
    size = Math.min(MAX_FONT, Math.max(MIN_FONT, Math.round((size + delta) * 10) / 10));
    localStorage.setItem(STORAGE_KEY, size);
    applyFontSize(size);
  };
})();

// Add font +/- buttons next to the built-in dark/light toggle, and label
// the toggle for screen readers (it ships from Quarto with no aria-label).
document.addEventListener('DOMContentLoaded', function () {
  var toggle = document.querySelector('.quarto-color-scheme-toggle');
  if (!toggle) return;

  if (!toggle.getAttribute('aria-label')) {
    toggle.setAttribute('aria-label', 'Toggle dark or light mode');
    toggle.setAttribute('title', 'Toggle dark/light mode');
  }

  if (document.querySelector('.hd-font-controls')) return;

  var wrap = document.createElement('span');
  wrap.className = 'hd-font-controls';

  var minusBtn = document.createElement('a');
  minusBtn.href = '#';
  minusBtn.className = 'hd-font-btn';
  minusBtn.setAttribute('aria-label', 'Decrease font size');
  minusBtn.title = 'Decrease font size';
  minusBtn.textContent = 'A−';
  minusBtn.addEventListener('click', function (e) {
    e.preventDefault();
    window.hdAdjustFontSize(-0.1);
  });

  var plusBtn = document.createElement('a');
  plusBtn.href = '#';
  plusBtn.className = 'hd-font-btn';
  plusBtn.setAttribute('aria-label', 'Increase font size');
  plusBtn.title = 'Increase font size';
  plusBtn.textContent = 'A+';
  plusBtn.addEventListener('click', function (e) {
    e.preventDefault();
    window.hdAdjustFontSize(0.1);
  });

  wrap.appendChild(minusBtn);
  wrap.appendChild(plusBtn);
  toggle.insertAdjacentElement('afterend', wrap);
});

// Click-to-zoom on plots (not captions, not tables)
document.addEventListener('click', function(e) {
  // Exit fullscreen: click anywhere on overlay or its child img
  var overlay = e.target.closest('.fullscreen-overlay');
  if (overlay) {
    overlay.remove();
    return;
  }
  var img = e.target.closest('.cell-output-display img');
  if (!img) return;
  var div = document.createElement('div');
  div.className = 'fullscreen-overlay';
  var clone = document.createElement('img');
  clone.src = img.src;
  div.appendChild(clone);
  document.body.appendChild(div);
});

// Site-wide navigation, in pipeline order:
//   Data -> Strategies -> Testing -> Verdict -> Failures, then an Appendix of
// exploratory pages. This array is the ONE home of the site's page list: every
// page loads this script, so adding or renaming a page is a one-line edit here.
// The bar is built at runtime (not a Quarto navbar) because the site mixes
// `format: dashboard` and `format: html` pages and renders them one at a time
// (scripts/build.sh), so a project-level website navbar is not available.
// `pages` lists the file names that mark an entry as the current page.
var HD_SITE_NAV = [
  { label: 'Overview', href: 'index.html', pages: ['index.html'] },
  { label: 'Data', href: 'index.html#datasets', hash: '#datasets' },
  { label: 'Strategies', items: [
    { label: 'Stock backtests', href: 'stock-backtest.html' },
    { label: 'Macro defense rotation', href: 'macro-defense-rotation.html' },
    { label: 'Momentum pre-peak', href: 'momentum-prepeak.html' }
  ] },
  { label: 'Testing', items: [
    { label: 'Falsification', href: 'falsification.html' },
    { label: 'Evidence', href: 'evidence.html' }
  ] },
  { label: 'Verdict', href: 'leaderboard.html' },
  { label: 'Failures', href: 'failures.html' },
  { label: 'Appendix', items: [
    { label: 'European overlay', href: 'european-overlay.html' },
    { label: 'Avoid worst days', href: 'avoid-worst-days.html' },
    { label: 'BDBB SOL', href: 'bdbb-sol.html' },
    { label: 'Quiz: which is real?', href: 'quiz.html' },
    { label: 'API reference', href: 'api-historicaldata.html' }
  ] }
];

(function () {
  function currentFile() {
    var p = window.location.pathname.split('/').pop();
    return p === '' ? 'index.html' : p;
  }
  function fileOf(href) { return href.split('#')[0]; }

  function isCurrent(entry, file, hash) {
    if (!entry.href) return false;
    var onIndex = file === 'index.html';
    if (entry.hash) return onIndex && hash === entry.hash;
    if (fileOf(entry.href) === 'index.html') return onIndex && hash !== '#datasets';
    return fileOf(entry.href) === file;
  }

  function link(entry, file, hash) {
    var a = document.createElement('a');
    a.href = entry.href;
    a.textContent = entry.label;
    if (isCurrent(entry, file, hash)) {
      a.className = 'hd-current';
      a.setAttribute('aria-current', 'page');
    }
    return a;
  }

  function build() {
    if (document.querySelector('.hd-sitenav')) return;
    var file = currentFile();
    var hash = window.location.hash;
    var nav = document.createElement('nav');
    nav.className = 'hd-sitenav';
    nav.setAttribute('aria-label', 'Site');
    var brand = document.createElement('span');
    brand.className = 'hd-sitenav-brand';
    brand.textContent = 'historicaldata';
    nav.appendChild(brand);
    var list = document.createElement('div');
    list.className = 'hd-sitenav-list';
    HD_SITE_NAV.forEach(function (entry, i) {
      if (!entry.items) {
        var single = link(entry, file, hash);
        single.classList.add('hd-sitenav-top');
        list.appendChild(single);
        return;
      }
      var d = document.createElement('details');
      d.className = 'hd-sitenav-group';
      var s = document.createElement('summary');
      s.textContent = entry.label;
      var active = entry.items.some(function (it) { return isCurrent(it, file, hash); });
      if (active) { s.className = 'hd-current'; }
      d.appendChild(s);
      var menu = document.createElement('div');
      menu.className = 'hd-sitenav-menu';
      entry.items.forEach(function (it) { menu.appendChild(link(it, file, hash)); });
      d.appendChild(menu);
      list.appendChild(d);
    });
    nav.appendChild(list);
    document.body.insertBefore(nav, document.body.firstChild);
    // The bar wraps to two rows on a phone; publish its height so fixed
    // toolbars (#ui-controls) sit below it instead of covering its last row.
    function setNavHeight() {
      document.documentElement.style.setProperty('--hd-nav-h', nav.offsetHeight + 'px');
    }
    setNavHeight();
    window.addEventListener('resize', setNavHeight);

    // Only one dropdown open at a time; click elsewhere or Escape closes it.
    nav.addEventListener('toggle', function (e) {
      if (!e.target.open) return;
      nav.querySelectorAll('details[open]').forEach(function (o) {
        if (o !== e.target) o.open = false;
      });
    }, true);
    document.addEventListener('click', function (e) {
      if (!e.target.closest('.hd-sitenav-group')) {
        nav.querySelectorAll('details[open]').forEach(function (o) { o.open = false; });
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        nav.querySelectorAll('details[open]').forEach(function (o) { o.open = false; });
      }
    });
    window.addEventListener('hashchange', function () {
      nav.querySelectorAll('a.hd-sitenav-top').forEach(function (a) {
        var entry = HD_SITE_NAV.filter(function (x) { return x.href === a.getAttribute('href'); })[0];
        var cur = entry && isCurrent(entry, currentFile(), window.location.hash);
        a.classList.toggle('hd-current', !!cur);
      });
    });
  }
  document.addEventListener('DOMContentLoaded', build);
})();

// Arriving at index.html#datasets (from the site nav) must open that dashboard
// page; the browser alone does not, because inactive pages are hidden tab panes.
document.addEventListener('DOMContentLoaded', function () {
  var h = window.location.hash;
  if (!h || h.length < 2 || typeof bootstrap === 'undefined') return;
  var navLink = document.querySelector(
    '.nav-link[data-bs-toggle="tab"][data-bs-target="' + h + '"]'
  );
  if (navLink) new bootstrap.Tab(navLink).show();
});

// Prevent tab clicks from jumping to page top
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.nav-link[data-bs-toggle="tab"]').forEach(function(tab) {
    tab.addEventListener('click', function(e) {
      e.preventDefault();
      // Scroll the tabset into view at the top of the viewport
      var tabset = this.closest('.nav');
      if (tabset) {
        var rect = tabset.getBoundingClientRect();
        if (rect.top < 0 || rect.top > window.innerHeight * 0.3) {
          tabset.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      }
      // Activate the tab via Bootstrap API
      var bsTab = new bootstrap.Tab(this);
      bsTab.show();
    });
  });
});

// Cross-page content links (e.g. "[Biases and Caveats](#biases-and-caveats)"
// inside a callout or table caption, historical#dashboard-output-first
// consolidation). A dashboard PAGE is really a Bootstrap tab pane with
// display:none while inactive, so a plain in-content <a href="#some-id">
// pointing at one does NOT make it visible -- only clicking its nav-link (or
// calling the Bootstrap Tab API, as the handler above does) does. This finds
// the nav-link whose data-bs-target matches the clicked link's href and
// activates it the same way, then scrolls to the target. Links that don't
// target a dashboard page (e.g. a footnote anchor within the current page)
// fall through to normal browser anchor behaviour untouched.
document.addEventListener('click', function (e) {
  var link = e.target.closest('a[href^="#"]');
  if (!link || link.matches('.nav-link[data-bs-toggle="tab"]')) return;
  var targetSel = link.getAttribute('href');
  if (!targetSel || targetSel.length < 2) return;
  var navLink = document.querySelector(
    '.nav-link[data-bs-toggle="tab"][data-bs-target="' + targetSel + '"]'
  );
  if (!navLink) return; // not a dashboard-page link; let default anchor behaviour happen
  e.preventDefault();
  new bootstrap.Tab(navLink).show();
  var target = document.querySelector(targetSel);
  if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
});

// Hover/focus popovers on elements built by R/column_popover.R (#788, #959).
// ONE delegated listener instead of one Bootstrap Popover per element: the
// popover is instantiated on first hover/focus and cached by Bootstrap's
// getOrCreateInstance, so a page with hundreds of labelled headers pays only
// for the ones actually touched. Content is built server-side and carries
// data-bs-html="true"; links inside it survive Bootstrap's sanitizer (a[href]
// https). Colours come from Bootstrap CSS variables, so the popover follows
// data-bs-theme (light and dark) with nothing hardcoded here.
(function () {
  var seen = new WeakSet();
  function onFirstTouch(e) {
    if (typeof bootstrap === 'undefined' || !e.target || !e.target.closest) return;
    var el = e.target.closest('.hd-popover[data-bs-toggle="popover"]');
    if (!el || seen.has(el)) return;
    seen.add(el);
    var pop = bootstrap.Popover.getOrCreateInstance(el, {
      container: 'body',
      customClass: 'hd-popover-wide',
      trigger: 'hover focus'
    });
    // This first event arrives before Bootstrap has attached its own
    // listeners, so show it explicitly this once.
    pop.show();
  }
  document.addEventListener('mouseover', onFirstTouch);
  document.addEventListener('focusin', onFirstTouch);
})();
