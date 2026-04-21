// Shared JS for all historicaldata vignettes

// Default to dark mode
if (!localStorage.getItem('quarto-color-scheme')) {
  document.documentElement.setAttribute('data-bs-theme', 'dark');
}

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
      homeItem.innerHTML = '<a class="nav-link" href="index.html" title="Home">Home</a>';
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
