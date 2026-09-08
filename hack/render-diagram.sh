#!/usr/bin/env bash
# render-diagram.sh — turn the canonical ASCII diagram into a clean, projector-
# friendly HTML page you can pop up in a browser during the talk.
#
# Source of truth: docs/rollout-diagram.txt (same text showtime.sh prints and the
# stage notes embed). This script only re-skins it — it never edits the diagram.
#
# Usage:
#   ./hack/render-diagram.sh          # regenerate docs/rollout-diagram.html
#   ./hack/render-diagram.sh --open   # regenerate, then open it in your browser
#   ./hack/render-diagram.sh --png    # also render docs/rollout-diagram.png (needs Chrome)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/docs/rollout-diagram.txt"
OUT="${REPO_ROOT}/docs/rollout-diagram.html"
PNG="${REPO_ROOT}/docs/rollout-diagram.png"

if [ ! -f "${SRC}" ]; then
  echo "Canonical diagram not found: ${SRC}" >&2
  exit 1
fi

# HTML-escape the diagram body (&, <, > — the diagram uses none today, but be safe).
BODY="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "${SRC}")"

cat > "${OUT}" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>meanwhile, the hub is doing the work</title>
<style>
  :root { color-scheme: light; }
  html, body {
    margin: 0; height: 100%;
    background: #f4f5f7;
    display: flex; align-items: center; justify-content: center;
    font-family: ui-sans-serif, -apple-system, "Segoe UI", sans-serif;
  }
  .card {
    background: #ffffff;
    border-radius: 16px;
    box-shadow: 0 20px 60px rgba(20, 24, 40, 0.18), 0 2px 6px rgba(20,24,40,0.08);
    padding: 44px 56px 40px;
    max-width: min(92vw, 1200px);
  }
  .dot { height: 12px; width: 12px; border-radius: 50%; display: inline-block; margin-right: 8px; }
  .dots { margin-bottom: 22px; }
  .r { background: #ff5f57; } .y { background: #febc2e; } .g { background: #28c840; }
  pre {
    margin: 0;
    font-family: "SF Mono", "JetBrains Mono", "Fira Code", Menlo, Consolas, monospace;
    font-size: clamp(11px, 1.55vw, 20px);
    line-height: 1.5;
    color: #12203a;
    white-space: pre;
    overflow-x: auto;
    tab-size: 4;
  }
  /* subtle emphasis without touching the source text */
  @media (prefers-color-scheme: dark) {
    html, body { background: #0f1220; }
    .card { background: #171a2b; box-shadow: 0 24px 70px rgba(0,0,0,0.55); }
    pre { color: #e8ecf6; }
  }
</style>
</head>
<body>
  <div class="card">
    <div class="dots"><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span></div>
    <pre>${BODY}</pre>
  </div>
</body>
</html>
HTML

echo "Wrote ${OUT}"

# --png: screenshot the HTML with headless Chrome into a crisp 2x PNG for slides.
if [ "${1:-}" = "--png" ]; then
  CHROME=""
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    [ -x "$c" ] && CHROME="$c" && break
  done
  if [ -z "${CHROME}" ]; then
    echo "No Chrome/Chromium/Edge found — skipping PNG. The HTML render is at ${OUT}" >&2
  else
    "${CHROME}" --headless=new --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=2 --window-size=1500,760 \
      --screenshot="${PNG}" "file://${OUT}" >/dev/null 2>&1 || true
    if [ -f "${PNG}" ]; then
      echo "Wrote ${PNG}"
    else
      echo "PNG render failed; use the HTML: ${OUT}" >&2
    fi
  fi
fi

if [ "${1:-}" = "--open" ]; then
  if command -v open >/dev/null 2>&1; then
    open "${OUT}"
  else
    echo "Open it in a browser: ${OUT}"
  fi
fi
