#!/usr/bin/env python3
"""Delete generated_documents rows that have no form.json snapshot.

Covers shipping, receiving, bol. Leaves rows that have local-unrelated
cloud `{kind}/{id}/form.json`. Uses AppConfig supabase URL + anon key.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KINDS = ("shipping", "receiving", "bol")
BUCKET = "generated-documents"


def load_anon() -> tuple[str, str]:
    cfg = (ROOT / "mobile" / "lib" / "app_config.dart").read_text(encoding="utf-8")
    url = re.search(r"supabaseUrl = '([^']+)'", cfg)
    key = re.search(r"supabaseAnonKey =\s*'([^']+)'", cfg)
    if not url or not key:
        raise SystemExit("Could not parse supabaseUrl / supabaseAnonKey from app_config.dart")
    return url.group(1).rstrip("/"), key.group(1)


def req(base: str, key: str, method: str, path: str, body=None) -> tuple[int, bytes]:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def list_prefix(base: str, key: str, prefix: str) -> list[str]:
    st, raw = req(
        base,
        key,
        "POST",
        f"/storage/v1/object/list/{BUCKET}",
        {"prefix": prefix, "limit": 100, "offset": 0},
    )
    if st == 404 or st >= 400:
        return []
    items = json.loads(raw.decode("utf-8") or "[]")
    out: list[str] = []
    for it in items:
        name = (it.get("name") or "").strip()
        if not name:
            continue
        if it.get("id") is None and it.get("metadata") is None:
            continue
        out.append(f"{prefix}/{name}")
    return out


def _missing_json(text: str) -> bool:
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return False
    if not isinstance(data, dict):
        return False
    sc = str(data.get("statusCode") or "")
    code = str(data.get("code") or "")
    err = str(data.get("error") or "")
    return sc == "404" or code == "NoSuchKey" or err == "not_found"


def has_form(base: str, key: str, kind: str, doc_id: str) -> bool:
    path = f"{kind}/{doc_id}/form.json"
    encoded = "/".join(urllib.request.quote(p, safe="") for p in path.split("/"))
    st, raw = req(base, key, "GET", f"/storage/v1/object/public/{BUCKET}/{encoded}")
    text = raw.decode("utf-8", errors="replace")
    if st == 404 or _missing_json(text):
        return False
    if st < 200 or st >= 300:
        print(f"  keep {kind}/{doc_id} (form GET {st})")
        return True
    try:
        data = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return True
    return isinstance(data, dict)


def delete_row(base: str, key: str, doc_id: str, storage_path: str, kind: str) -> None:
    prefix = f"{kind}/{doc_id}"
    paths = list_prefix(base, key, prefix)
    paths = list({*paths, f"{prefix}/form.json", storage_path, prefix} - {""})
    for path in paths:
        encoded = "/".join(urllib.request.quote(p, safe="") for p in path.split("/"))
        st, raw = req(base, key, "DELETE", f"/storage/v1/object/{BUCKET}/{encoded}")
        if st != 404 and st >= 400:
            st2, raw2 = req(
                base,
                key,
                "DELETE",
                f"/storage/v1/object/{BUCKET}",
                {"prefixes": [path]},
            )
            if st2 != 404 and st2 >= 400:
                print(f"  storage delete {path} FAILED {st}/{st2}: {raw[:120]!r} {raw2[:120]!r}")
    st, raw = req(
        base,
        key,
        "DELETE",
        f"/rest/v1/generated_documents?id=eq.{urllib.request.quote(doc_id)}",
    )
    if st != 404 and st >= 400:
        print(f"  row delete {doc_id} FAILED {st}: {raw[:200]!r}")


def main() -> int:
    base, key = load_anon()
    print(f"Supabase: {base}")
    removed = 0
    kept = 0
    for kind in KINDS:
        st, raw = req(
            base,
            key,
            "GET",
            f"/rest/v1/generated_documents?kind=eq.{kind}"
            "&select=id,kind,storage_path,file_name,created_at"
            "&order=created_at.desc&limit=1000",
        )
        if st >= 400:
            print(f"  list {kind} FAILED {st}: {raw[:200]!r}")
            continue
        rows = json.loads(raw.decode("utf-8") or "[]")
        print(f"{kind}: {len(rows)} rows")
        for row in rows:
            doc_id = str(row.get("id") or "").strip()
            path = str(row.get("storage_path") or "").strip()
            if not doc_id:
                continue
            if has_form(base, key, kind, doc_id):
                kept += 1
                continue
            print(f"  delete {kind}/{doc_id} ({row.get('file_name')})")
            delete_row(base, key, doc_id, path, kind)
            removed += 1
    print(f"done: deleted {removed}, kept {kept} with snapshots")
    return 0


if __name__ == "__main__":
    sys.exit(main())
