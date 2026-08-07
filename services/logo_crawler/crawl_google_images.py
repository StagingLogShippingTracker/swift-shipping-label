#!/usr/bin/env python3
"""
Headless Google Images crawler for Swift Document Generator Find-logo.

Uses Playwright Chromium to:
  - Execute JS (bypass lazy-load shells that plain HTTP gets)
  - Scroll the results grid to force more tiles to load
  - Extract original high-res URLs (\"ou\" / originalUrl), not gstatic thumbs

CLI (Flutter Process bridge):
  python crawl_google_images.py --query "DHV logo" --max 30
  -> prints one JSON object on stdout: {"ok": true, "urls": [...], ...}

Optional HTTP (local/dev):
  python crawl_google_images.py --serve --port 8765
  POST /crawl  {"query": "DHV logo", "max": 30}
"""

from __future__ import annotations

import argparse
import json
import random
import re
import sys
import time
import urllib.parse
from typing import Any

# ---------------------------------------------------------------------------
# Anti-bot: rotating desktop Chrome / Edge profiles + standard fetch headers
# ---------------------------------------------------------------------------

_BROWSER_PROFILES: list[dict[str, str]] = [
    {
        "ua": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
        ),
        "sec_ch_ua": '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"',
        "platform": '"Windows"',
    },
    {
        "ua": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0"
        ),
        "sec_ch_ua": '"Microsoft Edge";v="135", "Chromium";v="135", "Not.A/Brand";v="99"',
        "platform": '"Windows"',
    },
    {
        "ua": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
        ),
        "sec_ch_ua": '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"',
        "platform": '"macOS"',
    },
]

_URL_PATTERNS = (
    re.compile(r'"ou"\s*:\s*"(https?://[^"\\]+)"'),
    re.compile(r'"originalUrl"\s*:\s*"(https?://[^"\\]+)"'),
    re.compile(r'"imageUrl"\s*:\s*"(https?://[^"\\]+)"'),
    re.compile(r'"url"\s*:\s*"(https?://[^"\\]+\.(?:png|jpe?g|webp|svg|gif)(?:\?[^"]*)?)"', re.I),
    re.compile(r'\bimgurl=(https?[^&"\']+)'),
    # Modern Google Images embeds many originals as plain quoted absolute URLs.
    re.compile(
        r'"(https?://(?!encrypted-tbn)[^"]+\.(?:png|jpe?g|webp|svg|gif)(?:\?[^"]*)?)"',
        re.I,
    ),
)

_SKIP_HOST_FRAGMENTS = (
    "gstatic.com/s/i/",
    "ssl.gstatic.com/gb/",
    "fonts.gstatic.com",
    "google.com/images",
    "googleusercontent.com/prox",
    "encrypted-tbn",
    "favicon",
    "data:image",
    "wikimedia.org/wiki/file:",
    "wikipedia.org/wiki/",
    "/search?",
)


def _pick_profile() -> dict[str, str]:
    return random.choice(_BROWSER_PROFILES)


def _sleep(a: float = 0.35, b: float = 1.1) -> None:
    time.sleep(random.uniform(a, b))


def _unescape_url(raw: str) -> str:
    u = raw.replace("\\u003d", "=").replace("\\u0026", "&").replace("\\/", "/")
    u = urllib.parse.unquote(u)
    return u.strip()


def _is_usable_image_url(url: str) -> bool:
    if not url.startswith("http"):
        return False
    low = url.lower()
    if any(frag in low for frag in _SKIP_HOST_FRAGMENTS):
        return False
    if low.endswith((".html", ".htm", ".php", ".asp", ".aspx")):
        return False
    # Drop Google chrome / UI assets
    if any(
        tok in low
        for tok in (
            "accounts.google",
            "policies.google",
            "support.google",
            "maps.gstatic",
            "www.google.com/logos",
        )
    ):
        return False
    return True


def extract_urls_from_html(html: str) -> list[str]:
    """Pull original image URLs from rendered Google Images HTML/JSON blobs."""
    found: list[str] = []
    seen: set[str] = set()
    for pat in _URL_PATTERNS:
        for m in pat.finditer(html):
            u = _unescape_url(m.group(1))
            if not _is_usable_image_url(u):
                continue
            key = u.split("?")[0].lower()
            if key in seen:
                continue
            seen.add(key)
            found.append(u)
    return found


def _dismiss_consent(page: Any) -> None:
    """Best-effort cookie/consent dismissal (EU interstitial)."""
    selectors = [
        'button:has-text("Accept all")',
        'button:has-text("I agree")',
        'button:has-text("Accept")',
        'button#L2AGLb',
        'div[role="dialog"] button:has-text("Accept")',
    ]
    for sel in selectors:
        try:
            btn = page.locator(sel).first
            if btn.count() and btn.is_visible(timeout=800):
                btn.click(timeout=1500)
                _sleep(0.2, 0.5)
                return
        except Exception:
            continue


def _scroll_results(page: Any, rounds: int = 6) -> None:
    """Scroll the image grid so lazy-loaded tiles hydrate."""
    for i in range(max(1, rounds)):
        try:
            page.evaluate(
                """() => {
                    const scroller = document.scrollingElement || document.documentElement;
                    scroller.scrollBy(0, Math.floor(window.innerHeight * 0.92));
                }"""
            )
        except Exception:
            try:
                page.mouse.wheel(0, 2800)
            except Exception:
                pass
        _sleep(0.55, 1.25)
        # Click "Show more results" if present
        if i in (2, 4):
            try:
                more = page.locator(
                    'input[value="Show more results"], a:has-text("More results")'
                ).first
                if more.count() and more.is_visible(timeout=400):
                    more.click(timeout=1200)
                    _sleep(0.6, 1.2)
            except Exception:
                pass


def _harvest_dom_urls(page: Any) -> list[str]:
    """Collect candidate URLs from live DOM attributes after scroll."""
    try:
        raw = page.evaluate(
            """() => {
                const out = [];
                const push = (u) => {
                  if (u && typeof u === 'string' && u.startsWith('http')) out.push(u);
                };
                document.querySelectorAll('img').forEach((img) => {
                  push(img.currentSrc || img.src);
                  push(img.getAttribute('data-src'));
                  push(img.getAttribute('data-iurl'));
                  push(img.getAttribute('data-ou'));
                });
                document.querySelectorAll('a[href*="imgurl="]').forEach((a) => {
                  try {
                    const u = new URL(a.href, location.origin);
                    const imgurl = u.searchParams.get('imgurl');
                    if (imgurl) push(imgurl);
                  } catch (_) {}
                });
                return out;
            }"""
        )
        if isinstance(raw, list):
            return [str(u) for u in raw]
    except Exception:
        pass
    return []


def _click_tiles_for_fullsize(page: Any, *, limit: int = 28) -> list[str]:
    """
    Open image tiles so Google hydrates the full-size viewer / side panel.
    Modern SERPs hide originals until a tile is activated.
    """
    found: list[str] = []
    seen: set[str] = set()

    def add(u: str | None) -> None:
        if not u:
            return
        u = _unescape_url(u)
        if not _is_usable_image_url(u):
            return
        # Prefer non-thumbnail sources; skip tiny gstatic if we already have better.
        key = u.split("?")[0].lower()
        if key in seen:
            return
        seen.add(key)
        found.append(u)

    # Candidate clickable tiles in the mosaic.
    tile_selectors = [
        'div[data-id] a',
        'a[jsname]',
        'div#islrg a',
        'div[role="listitem"] a',
    ]
    tiles = []
    for sel in tile_selectors:
        try:
            loc = page.locator(sel)
            n = min(loc.count(), limit)
            if n:
                tiles = [loc.nth(i) for i in range(n)]
                break
        except Exception:
            continue

    if not tiles:
        # Fallback: click result images that look like mosaic thumbs.
        try:
            loc = page.locator('img[src*="encrypted-tbn"]')
            n = min(loc.count(), limit)
            tiles = [loc.nth(i) for i in range(n)]
        except Exception:
            tiles = []

    preview_selectors = [
        "img.sFlh5c",
        "img.n3VNCb",
        "img.iPVvYb",
        "a[href*='imgurl=']",
        "img[jsname]",
    ]

    for tile in tiles:
        if len(found) >= limit:
            break
        try:
            tile.scroll_into_view_if_needed(timeout=1500)
            tile.click(timeout=2000, force=True)
            _sleep(0.25, 0.55)
            for sel in preview_selectors:
                try:
                    node = page.locator(sel).first
                    if not node.count():
                        continue
                    if sel.startswith("a"):
                        href = node.get_attribute("href") or ""
                        m = re.search(r"imgurl=([^&]+)", href)
                        if m:
                            add(urllib.parse.unquote(m.group(1)))
                    else:
                        add(node.get_attribute("src"))
                        add(node.get_attribute("data-src"))
                except Exception:
                    continue
            # Also scrape any newly injected quoted image URLs from a partial HTML slice.
            try:
                snippet = page.evaluate("() => document.body.innerHTML.slice(0, 250000)")
                if isinstance(snippet, str):
                    for u in extract_urls_from_html(snippet):
                        add(u)
            except Exception:
                pass
        except Exception:
            continue

    return found


def crawl_google_images(
    query: str,
    *,
    max_results: int = 30,
    scroll_rounds: int = 6,
    headless: bool = True,
    timeout_ms: int = 45000,
) -> dict[str, Any]:
    """
    Run a headless Google Images search and return original image URLs.

    Returns:
      {ok, query, urls, count, engine, error?}
    """
    query = (query or "").strip()
    if not query:
        return {"ok": False, "query": query, "urls": [], "count": 0, "error": "empty query"}

    try:
        from playwright.sync_api import sync_playwright
    except ImportError as e:
        return {
            "ok": False,
            "query": query,
            "urls": [],
            "count": 0,
            "error": f"playwright not installed: {e}",
        }

    profile = _pick_profile()
    params = {
        "q": query,
        "tbm": "isch",
        "hl": "en",
        "gl": "us",
        "safe": "off",
        "sclient": "img",
    }
    # Page through first tiles via ijn when needed (0 then 1).
    pages_to_hit = [0, 1] if max_results > 20 else [0]
    collected: list[str] = []
    seen: set[str] = set()
    last_error: str | None = None

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=headless,
            args=[
                "--disable-blink-features=AutomationControlled",
                "--no-sandbox",
                "--disable-dev-shm-usage",
            ],
        )
        context = browser.new_context(
            user_agent=profile["ua"],
            locale="en-US",
            viewport={"width": 1440, "height": 1100},
            extra_http_headers={
                "Accept": (
                    "text/html,application/xhtml+xml,application/xml;q=0.9,"
                    "image/avif,image/webp,image/apng,*/*;q=0.8"
                ),
                "Accept-Language": "en-US,en;q=0.9",
                "Cache-Control": "no-cache",
                "Pragma": "no-cache",
                "Sec-Ch-Ua": profile["sec_ch_ua"],
                "Sec-Ch-Ua-Mobile": "?0",
                "Sec-Ch-Ua-Platform": profile["platform"],
                "Sec-Fetch-Dest": "document",
                "Sec-Fetch-Mode": "navigate",
                "Sec-Fetch-Site": "none",
                "Sec-Fetch-User": "?1",
                "Upgrade-Insecure-Requests": "1",
            },
        )
        # Soften webdriver detection.
        context.add_init_script(
            "Object.defineProperty(navigator, 'webdriver', {get: () => undefined});"
        )
        page = context.new_page()
        page.set_default_timeout(timeout_ms)

        try:
            for ijn in pages_to_hit:
                if len(collected) >= max_results:
                    break
                qp = dict(params)
                if ijn:
                    qp["ijn"] = str(ijn)
                url = "https://www.google.com/search?" + urllib.parse.urlencode(qp)
                _sleep(0.25, 0.7)
                try:
                    page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
                except Exception as e:
                    last_error = f"goto failed: {e}"
                    continue

                _dismiss_consent(page)
                _sleep(0.4, 0.9)
                try:
                    page.wait_for_load_state("networkidle", timeout=8000)
                except Exception:
                    pass

                _scroll_results(page, rounds=scroll_rounds if ijn == 0 else max(3, scroll_rounds - 2))

                html = page.content()
                for u in extract_urls_from_html(html):
                    key = u.split("?")[0].lower()
                    if key in seen:
                        continue
                    seen.add(key)
                    collected.append(u)
                    if len(collected) >= max_results:
                        break

                # Activate tiles so Google hydrates full-size / side-panel originals.
                if len(collected) < max_results:
                    need = max_results - len(collected)
                    for u in _click_tiles_for_fullsize(page, limit=min(28, max(need + 8, 16))):
                        key = u.split("?")[0].lower()
                        if key in seen:
                            continue
                        seen.add(key)
                        collected.append(u)
                        if len(collected) >= max_results:
                            break

                if len(collected) < max_results:
                    for u in _harvest_dom_urls(page):
                        u = _unescape_url(u)
                        if not _is_usable_image_url(u):
                            continue
                        key = u.split("?")[0].lower()
                        if key in seen:
                            continue
                        seen.add(key)
                        collected.append(u)
                        if len(collected) >= max_results:
                            break

                # Soft pacing between paginated hits
                if ijn == 0 and len(collected) < max_results:
                    _sleep(0.6, 1.4)
        except Exception as e:
            last_error = str(e)
        finally:
            context.close()
            browser.close()

    urls = collected[:max_results]
    return {
        "ok": bool(urls),
        "query": query,
        "urls": urls,
        "count": len(urls),
        "engine": "playwright-google-images",
        **({"error": last_error} if last_error and not urls else {}),
        **({"warning": last_error} if last_error and urls else {}),
    }


def crawl_queries(
    queries: list[str],
    *,
    max_results: int = 30,
    scroll_rounds: int = 6,
    headless: bool = True,
) -> dict[str, Any]:
    """Run one or more queries until [max_results] unique URLs are collected."""
    merged: list[str] = []
    seen: set[str] = set()
    details: list[dict[str, Any]] = []
    for q in queries:
        q = (q or "").strip()
        if not q:
            continue
        need = max_results - len(merged)
        if need <= 0:
            break
        result = crawl_google_images(
            q,
            max_results=max(need, 12),
            scroll_rounds=scroll_rounds,
            headless=headless,
        )
        details.append({"query": q, "count": result.get("count", 0), "ok": result.get("ok")})
        for u in result.get("urls") or []:
            key = u.split("?")[0].lower()
            if key in seen:
                continue
            seen.add(key)
            merged.append(u)
            if len(merged) >= max_results:
                break
        if len(merged) >= max_results:
            break
        _sleep(0.5, 1.2)

    return {
        "ok": bool(merged),
        "queries": [d["query"] for d in details],
        "urls": merged[:max_results],
        "count": len(merged[:max_results]),
        "engine": "playwright-google-images",
        "details": details,
    }


def _serve(host: str, port: int) -> None:
    from fastapi import FastAPI
    from pydantic import BaseModel, Field
    import uvicorn

    app = FastAPI(title="Swift Logo Crawler", version="1.0.0")

    class CrawlBody(BaseModel):
        query: str | None = None
        queries: list[str] | None = None
        max: int = Field(default=30, ge=1, le=80)
        scroll_rounds: int = Field(default=6, ge=1, le=15)
        headless: bool = True

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "engine": "playwright-google-images"}

    @app.post("/crawl")
    def crawl(body: CrawlBody) -> dict[str, Any]:
        qs = [q for q in (body.queries or []) if (q or "").strip()]
        if body.query and body.query.strip():
            qs = [body.query.strip(), *qs]
        if not qs:
            return {"ok": False, "urls": [], "count": 0, "error": "query required"}
        if len(qs) == 1:
            return crawl_google_images(
                qs[0],
                max_results=body.max,
                scroll_rounds=body.scroll_rounds,
                headless=body.headless,
            )
        return crawl_queries(
            qs,
            max_results=body.max,
            scroll_rounds=body.scroll_rounds,
            headless=body.headless,
        )

    uvicorn.run(app, host=host, port=port, log_level="info")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Headless Google Images logo crawler")
    parser.add_argument("--query", "-q", action="append", default=[], help="Search query (repeatable)")
    parser.add_argument("--max", type=int, default=30, help="Max URLs to return")
    parser.add_argument("--scroll-rounds", type=int, default=6, help="Lazy-load scroll passes")
    parser.add_argument("--headed", action="store_true", help="Show browser window (debug)")
    parser.add_argument("--serve", action="store_true", help="Run local HTTP API")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args(argv)

    if args.serve:
        _serve(args.host, args.port)
        return 0

    queries = [q.strip() for q in args.query if q and q.strip()]
    if not queries:
        # Also accept a single positional-free stdin JSON: {"query":"..."} or {"queries":[...]}
        if not sys.stdin.isatty():
            try:
                payload = json.loads(sys.stdin.read() or "{}")
                if isinstance(payload, dict):
                    if payload.get("query"):
                        queries.append(str(payload["query"]).strip())
                    for q in payload.get("queries") or []:
                        if str(q).strip():
                            queries.append(str(q).strip())
                    if payload.get("max"):
                        args.max = int(payload["max"])
            except Exception:
                pass
    if not queries:
        print(json.dumps({"ok": False, "urls": [], "count": 0, "error": "missing --query"}))
        return 2

    if len(queries) == 1:
        result = crawl_google_images(
            queries[0],
            max_results=args.max,
            scroll_rounds=args.scroll_rounds,
            headless=not args.headed,
        )
    else:
        result = crawl_queries(
            queries,
            max_results=args.max,
            scroll_rounds=args.scroll_rounds,
            headless=not args.headed,
        )
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
