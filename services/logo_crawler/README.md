# Swift Logo Crawler (Google Images)

Headless Playwright crawler used by Find-logo when local Python is available.

## Why

Plain HTTP scrapes of Google Images often receive a JS-only shell (lazy-loaded
tiles never hydrate). This service launches Chromium, scrolls the grid, and
extracts original high-res URLs (`ou` / `originalUrl`).

## Setup (Windows)

```powershell
cd services\logo_crawler
python -m pip install -r requirements.txt
python -m playwright install chromium
```

## CLI (Flutter Process bridge)

```powershell
python crawl_google_images.py --query "DHV logo" --max 30
```

Stdout is a single JSON object:

```json
{"ok": true, "query": "DHV logo", "urls": ["https://..."], "count": 28, "engine": "playwright-google-images"}
```

Multiple queries (merged / deduped):

```powershell
python crawl_google_images.py -q "DHV logo" -q "DHV company logo png" --max 30
```

## Optional HTTP API

```powershell
python crawl_google_images.py --serve --port 8765
# POST http://127.0.0.1:8765/crawl  {"query":"DHV logo","max":30}
```

## Anti-bot notes

- Rotating Chrome / Edge desktop User-Agents + Sec-CH-UA / Sec-Fetch headers
- Randomized delays between navigation / scroll
- `navigator.webdriver` masked
- Consent dialog dismissed when present
