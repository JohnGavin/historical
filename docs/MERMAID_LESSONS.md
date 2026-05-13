# Mermaid in Quarto Dashboards: Lessons Learnt

## What works

| Approach | Works? | Why |
|----------|:------:|-----|
| External `.js` file via `<script src="file.js">` in include-in-header | **Yes** | Quarto preserves src references |
| JS strings stored in `.js` file (no HTML escaping) | **Yes** | Avoids Pandoc `-->` to `--&gt;` escaping |
| `mermaid.render(id, text)` per diagram individually | **Yes** | One failure doesn't block others |
| Skip hidden tabs, render on `shown.bs.tab` event | **Yes** | Hidden tabs cause silent render failure |
| `mermaid-test.html` standalone page | **Yes** | No Quarto processing involved |

## What does NOT work

| Approach | Fails because |
|----------|---------------|
| `{=html}` blocks with `<script>` | Quarto 1.8 strips raw HTML from dashboard format |
| `cat('<pre class="mermaid">...')` with `results: asis` | Pandoc escapes `-->` to `--&gt;` inside `<pre>` |
| Inline `<script type="module">` in include-in-header | Quarto strips inline script content (but preserves `<script src>`) |
| `include-after-body: file.html` in dashboard format | Silently dropped — content never appears in rendered HTML |
| `<br/>` or `<br>` in node labels | Mermaid 11 syntax error |
| Em dash `—` (UTF-8 multi-byte) in node labels | Mermaid 11 syntax error |
| Parenthetical descriptions in labels `Signal (description)` | Sometimes works, sometimes causes syntax error depending on content |
| Elk layout engine `defaultRenderer: "elk"` | Requires separate CDN import not included in mermaid@11 bundle |
| Batch `mermaid.run({querySelector: ...})` on hidden tabs | First hidden diagram fails, blocks all remaining |

## Correct pattern (proven working)

### 1. External JS file (`causal-diagrams.js`)

```javascript
import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
mermaid.initialize({startOnLoad:false, securityLevel:"loose", theme:"dark"});

var dagDefs = {
  "mount-id": "graph TD\n  A[\"Node A\"] --> B[\"Node B\"]"
};

async function renderDiagrams() {
  for (var mountId in dagDefs) {
    var mount = document.getElementById(mountId);
    if (!mount || mount.querySelector('svg')) continue;
    if (mount.offsetParent === null) continue; // skip hidden tabs
    var pre = document.createElement('pre');
    mount.appendChild(pre);
    try {
      var result = await mermaid.render('id-' + mountId, dagDefs[mountId]);
      pre.innerHTML = result.svg;
    } catch(e) {
      pre.textContent = 'Error: ' + e.message;
      pre.style.color = '#ff4444';
    }
  }
}

document.addEventListener('DOMContentLoaded', () => setTimeout(renderDiagrams, 800));
document.addEventListener('shown.bs.tab', () => setTimeout(renderDiagrams, 300));
```

### 2. Reference in .qmd header

```yaml
include-in-header:
  - text: |
      <script type="module" src="causal-diagrams.js"></script>
```

### 3. Mount points in tabs (via R cat)

```r
cat('<div id="dag-full-mount"></div>')
```

## Node label rules

| Rule | Example |
|------|---------|
| Plain ASCII text only | `HML["HML Value"]` |
| No HTML tags | NOT `HML["HML <br> Value"]` |
| No multi-byte Unicode | NOT `HML["HML — Value"]` |
| No parentheses with special chars | `DRIF["DRIF Signal"]` not `DRIF["DRIF Signal (desc)"]` |
| Descriptions go in tab prose | Below the diagram, not inside nodes |

## Theme-aware CSS rules

| Element | Dark mode | Light mode |
|---------|-----------|------------|
| Body/card text | `color: #e0e0e0` | `color: #1a1a1a` |
| DT table bg | `#1a1a2e` | `#fff` |
| DT header bg | `#16213e` | `#f8f9fa` |
| Caption text | Inherits from card-body | Inherits from card-body |

Always use `[data-bs-theme="dark"]` and `[data-bs-theme="light"]` selectors, never hardcode colours without a theme selector.

## QA scripts

| Script | What it tests | Catches |
|--------|--------------|---------|
| `scripts/qa_deployed_url.sh` | curl + grep for error patterns | Static HTML defects |
| `scripts/qa_mermaid_syntax.sh` | mmdc CLI + Chrome headless | Diagram syntax errors |
| Browser test (manual) | Visual inspection | Theme issues, hidden tab rendering |

## Unlabeled edge interactivity (implemented in #140 Option B)

Mermaid v11 renders unlabeled edges as `<path class="flowchart-link">` elements with
deterministic ids: `id="L_<SRC>_<DST>_<idx>"` (e.g. `L_Mkt_RF_LTR_R_0`).

Key facts:
- `data-points` attribute contains a base64-encoded JSON array of `{x,y}` waypoints
  in SVG space. Decode with `atob()` then `JSON.parse()` to get the midpoint.
- Node IDs may contain underscores (`Mkt_RF`). The path id body is therefore
  ambiguous (e.g. `L_Mkt_RF_LTR_R_0` — is the src `Mkt` or `Mkt_RF`?).
- Resolution: parse the body (`Mkt_RF_LTR_R`), try every split from longest src first.
  Validate both halves against the diagram's known node-ID set (extracted from `dagDefs`
  by `nodeIdsFromDagDef()`). The first split where both halves are valid nodes wins.
- A single shared popup `<div class="edge-popup">` is appended to `<body>` and reused
  for all edges. CSS uses `--bs-*` vars for Bootstrap dark/light theming.
- Hover-bridge: `mouseleave` on a path schedules a 200ms hide; `mouseenter` on the
  popup cancels the timeout so users can click the source link.
- `position: fixed` (not `absolute`) on the popup prevents scroll jitter.

## Adding a new diagram

1. Add diagram text to `docs/causal-diagrams.js` in `dagDefs` object
2. Add mount point `<div id="dag-xxx-mount">` via R `cat()` in the .qmd tab
3. Run `scripts/qa_mermaid_syntax.sh` to validate
4. Deploy and test in browser (both dark and light mode)
5. Check hidden tab renders on click
6. For every new **labeled** edge, add an entry to `edgeMetadata` keyed by the exact
   label text (e.g. `"r=-0.17 VIOLATED"`).
   For every **unlabeled** edge, add a `"SRC->DST"` entry (e.g. `"Mkt_RF->LTR_R"`).
   Tooltip text MUST cite the specific R function or `tar_target` name — grep `R/`
   to verify before writing the tooltip. Never invent line numbers.
