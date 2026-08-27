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

// Add home link to navbar (left of dark mode toggle)
document.addEventListener('DOMContentLoaded', function() {
  var navbar = document.querySelector('.navbar-nav, .navbar-collapse, .navbar');
  if (navbar && !document.querySelector('.navbar-home-link')) {
    // Find the right spot — before the light switch or at the start of nav
    var navContainer = document.querySelector('.navbar-nav');
    if (navContainer) {
      var homeItem = document.createElement('li');
      homeItem.className = 'nav-item navbar-home-link';
      var homeLink = document.createElement('a');
      homeLink.className = 'nav-link';
      homeLink.href = 'index.html';
      homeLink.title = 'Home';
      homeLink.textContent = 'Home';
      homeItem.appendChild(homeLink);
      navContainer.insertBefore(homeItem, navContainer.firstChild);
    }
  }
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
