// Shared JS for all historicaldata vignettes

// Default to dark mode
if (!localStorage.getItem('quarto-color-scheme')) {
  document.documentElement.setAttribute('data-bs-theme', 'dark');
}

// Click-to-zoom on plots (not captions, not tables)
document.addEventListener('click', function(e) {
  var overlay = e.target.closest('.fullscreen-overlay');
  if (overlay) {
    overlay.classList.remove('fullscreen-overlay');
    overlay.style.cssText = '';
    return;
  }
  var img = e.target.closest('img');
  if (!img) return;
  var cell = img.closest('.cell-output-display');
  if (!cell) return;
  var div = document.createElement('div');
  div.className = 'fullscreen-overlay';
  div.innerHTML = '<img src="' + img.src + '">';
  div.addEventListener('click', function() { div.remove(); });
  document.body.appendChild(div);
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
