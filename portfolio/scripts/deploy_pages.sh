#!/usr/bin/env bash
# Redeploy GitHub Pages from local Flutter web builds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER="${FLUTTER:-$ROOT/../.tools/flutter/bin/flutter}"
if [[ ! -x "$FLUTTER" ]]; then FLUTTER=flutter; fi

(cd "$ROOT/apps/sdg_web_demo" && "$FLUTTER" pub get && "$FLUTTER" build web --release --base-href "/portfolio/demos/sdg/")
(cd "$ROOT/apps/slst_web_demo" && "$FLUTTER" pub get && "$FLUTTER" build web --release --base-href "/portfolio/demos/slst/")

SITE="$ROOT/_site"
rm -rf "$SITE"
mkdir -p "$SITE/demos/sdg" "$SITE/demos/slst"
cp "$ROOT/site/index.html" "$SITE/index.html"
cp -R "$ROOT/apps/sdg_web_demo/build/web/." "$SITE/demos/sdg/"
cp -R "$ROOT/apps/slst_web_demo/build/web/." "$SITE/demos/slst/"

TMP="$(mktemp -d)"
cp -R "$SITE/." "$TMP/"
cd "$TMP"
git init
git config user.name "StagingLogShippingTracker"
git config user.email "289869979+StagingLogShippingTracker@users.noreply.github.com"
git checkout -b gh-pages
git add .
git commit -m "Deploy portfolio GitHub Pages site"
git remote add origin https://github.com/StagingLogShippingTracker/portfolio.git
git push -f origin gh-pages
echo "Published: https://staginglogshippingtracker.github.io/portfolio/"
