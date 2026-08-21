"""Fetch customer logos via Serper + Clearbit — same APIs the app LogoFinder uses."""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "qa_logs" / "logo_restore_marathon" / "crawl_cache"

COMPANIES = [
    ("Allied Fitting", "alliedfitting.com"),
    ("PVF Canada", "pvfcanada.com"),
    ("Comco Pipe", "comco.ca"),
    ("5MPFF", ""),
    ("CCTF Corp", ""),
    ("Paragon Oilfield Supply", ""),
    ("Apex Valves", "apexvalve.com"),
    ("Warren Valve", "warrenvalve.com"),
    ("Quest Gasket", ""),
    ("Flexitallic", "flexitallic.com"),
]


def load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    for name in (".env", ".env.local"):
        p = ROOT / name
        if not p.exists():
            continue
        for raw in p.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip().strip('"').strip("'")
            env[k.strip()] = v
    return env


def stem(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def http_json(url: str, data: bytes | None = None, headers: dict | None = None) -> dict:
    req = urllib.request.Request(url, data=data, headers=headers or {}, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=25) as res:
        return json.loads(res.read().decode("utf-8"))


def download(url: str) -> bytes | None:
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Mozilla/5.0 SwiftDocumentGeneratorLogoQA/1.0"},
        )
        with urllib.request.urlopen(req, timeout=25) as res:
            body = res.read()
            ctype = (res.headers.get("Content-Type") or "").lower()
            if len(body) < 800:
                return None
            if "svg" in ctype or body[:4] == b"<svg" or body[:5] == b"<?xml":
                return None
            return body
    except Exception:
        return None


def serper_urls(key: str, query: str) -> list[str]:
    payload = json.dumps({"q": query, "gl": "us", "hl": "en"}).encode()
    try:
        data = http_json(
            "https://google.serper.dev/images",
            data=payload,
            headers={"X-API-KEY": key, "Content-Type": "application/json"},
        )
    except Exception as e:
        print(f"  serper fail {query!r}: {e}", flush=True)
        return []
    urls: list[str] = []
    for item in data.get("images") or []:
        if not isinstance(item, dict):
            continue
        for k in ("imageUrl", "thumbnailUrl"):
            u = str(item.get(k) or "").strip()
            if u.startswith("http"):
                urls.append(u)
    return urls


def main() -> int:
    env = load_env()
    key = env.get("SERPER_API_KEY") or os.environ.get("SERPER_API_KEY", "")
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    for name, domain in COMPANIES:
        s = stem(name)
        dest = OUT / f"{s}.png"
        meta = {"name": name, "domain": domain, "ok": False}
        print(f"== {name}", flush=True)
        candidates: list[str] = []
        if domain:
            candidates.append(f"https://logo.clearbit.com/{domain}")
            candidates.append(f"https://logo.clearbit.com/{domain}?size=512")
        if key:
            for q in (
                f"{name} logo high resolution transparent",
                f"{name} official brand logo png",
                f"{name} company logo",
            ):
                candidates.extend(serper_urls(key, q)[:8])
        seen: set[str] = set()
        saved = None
        for url in candidates:
            if url in seen:
                continue
            seen.add(url)
            body = download(url)
            if not body:
                continue
            dest.write_bytes(body)
            saved = url
            print(f"  saved {dest.name} {len(body)}b from {url[:90]}", flush=True)
            break
        meta["ok"] = saved is not None
        meta["url"] = saved
        meta["bytes"] = dest.stat().st_size if dest.exists() else 0
        report.append(meta)
        if not saved:
            print("  NO IMAGE", flush=True)
    (OUT / "crawl_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    ok = sum(1 for r in report if r["ok"])
    print(f"crawl {ok}/{len(report)} -> {OUT}", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
