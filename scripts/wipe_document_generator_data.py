#!/usr/bin/env python3
"""Wipe Swift Document Generator cloud + local runtime data for a fresh start.

Clears:
  - Supabase tables: customer_presets, customer_logos, signatures
  - Supabase storage buckets: customer-logos, signatures
  - Optional: bol_serial_log + reset bol_serial_counter (shared BOL numbers)
  - Local AppStorage: presets, logos, signatures, PDFs, remembered contacts, settings

Does NOT touch Staging Tracker tables/buckets or dropdown_roster (employee directory).
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_anon() -> tuple[str, str]:
    cfg = (ROOT / "mobile" / "lib" / "app_config.dart").read_text(encoding="utf-8")
    url = re.search(r"supabaseUrl = '([^']+)'", cfg)
    key = re.search(r"supabaseAnonKey =\s*'([^']+)'", cfg)
    if not url or not key:
        raise SystemExit("Could not parse supabaseUrl / supabaseAnonKey from app_config.dart")
    return url.group(1).rstrip("/"), key.group(1)


def req(
    base: str,
    key: str,
    method: str,
    path: str,
    body=None,
    extra: dict | None = None,
) -> tuple[int, dict, bytes]:
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    if extra:
        headers.update(extra)
    data = None
    if body is not None:
        if isinstance(body, (bytes, bytearray)):
            data = body
        else:
            data = json.dumps(body).encode("utf-8")
            headers.setdefault("Content-Type", "application/json")
    request = urllib.request.Request(
        base + path, data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def content_range_total(headers: dict) -> str:
    for k, v in headers.items():
        if k.lower() == "content-range":
            return v
    return "?"


def count_table(base: str, key: str, table: str) -> int:
    st, h, _ = req(
        base,
        key,
        "GET",
        f"/rest/v1/{table}?select=*&limit=1",
        extra={"Prefer": "count=exact", "Range": "0-0"},
    )
    if st >= 400:
        return -1
    cr = content_range_total(h)
    # e.g. 0-0/28 or */0
    if "/" in cr:
        try:
            return int(cr.split("/")[-1])
        except ValueError:
            return -1
    return -1


def delete_all_rows(base: str, key: str, table: str, filter_q: str) -> int:
    """Delete all rows matching filter. Returns HTTP status."""
    st, h, raw = req(
        base,
        key,
        "DELETE",
        f"/rest/v1/{table}?{filter_q}",
        extra={"Prefer": "return=minimal"},
    )
    if st >= 400:
        print(f"  DELETE {table} FAILED {st}: {raw[:300]!r}")
    else:
        print(f"  DELETE {table} OK ({st}) filter={filter_q}")
    return st


def list_bucket(base: str, key: str, bucket: str, prefix: str = "") -> list[str]:
    st, _, raw = req(
        base,
        key,
        "POST",
        f"/storage/v1/object/list/{bucket}",
        body={"prefix": prefix, "limit": 1000, "offset": 0},
    )
    if st >= 400:
        print(f"  list {bucket}/{prefix!r} FAILED {st}: {raw[:200]!r}")
        return []
    items = json.loads(raw.decode("utf-8") or "[]")
    out: list[str] = []
    for it in items:
        name = it.get("name") or ""
        if not name:
            continue
        full = f"{prefix.rstrip('/')}/{name}" if prefix else name
        # Folder entries typically have null id/metadata
        if it.get("id") is None and it.get("metadata") is None:
            out.extend(list_bucket(base, key, bucket, full))
        else:
            out.append(full)
    return out


def delete_storage_objects(base: str, key: str, bucket: str, paths: list[str]) -> None:
    if not paths:
        print(f"  bucket {bucket}: already empty")
        return
    # API accepts batches
    batch = 100
    for i in range(0, len(paths), batch):
        chunk = paths[i : i + batch]
        st, _, raw = req(
            base,
            key,
            "DELETE",
            f"/storage/v1/object/{bucket}",
            body={"prefixes": chunk},
        )
        if st >= 400:
            print(f"  delete {bucket} batch FAILED {st}: {raw[:300]!r}")
        else:
            print(f"  deleted {len(chunk)} from {bucket}")


def wipe_supabase(reset_bol: bool) -> None:
    base, key = load_anon()
    print(f"Supabase: {base}")
    for t in (
        "customer_presets",
        "customer_logos",
        "signatures",
        "bol_serial_log",
        "bol_serial_counter",
        "dropdown_roster",
    ):
        print(f"  before {t}: {count_table(base, key, t)}")

    # Storage first (so orphaned bytes don't linger), then metadata tables.
    for bucket in ("customer-logos", "signatures"):
        objs = list_bucket(base, key, bucket)
        print(f"  bucket {bucket}: {len(objs)} objects")
        delete_storage_objects(base, key, bucket, objs)

    # Match-all filters (uuid / text PKs)
    delete_all_rows(base, key, "customer_presets", "id=not.is.null")
    delete_all_rows(base, key, "customer_logos", "id=not.is.null")
    delete_all_rows(base, key, "signatures", "id=neq.")

    if reset_bol:
        delete_all_rows(base, key, "bol_serial_log", "id=not.is.null")
        # Try update counter to 0 (schema may vary)
        st, _, raw = req(
            base,
            key,
            "GET",
            "/rest/v1/bol_serial_counter?select=*",
        )
        print(f"  bol_serial_counter rows: {st} {raw[:200]!r}")
        if st < 400:
            rows = json.loads(raw.decode() or "[]")
            for row in rows:
                # Prefer updating last_value if present
                pk_col = None
                for cand in ("id", "name", "counter_name", "key"):
                    if cand in row:
                        pk_col = cand
                        break
                patch = {}
                if "last_value" in row:
                    patch["last_value"] = 0
                if "value" in row:
                    patch["value"] = 0
                if not patch:
                    print(f"  skip counter reset; unknown schema keys={list(row)}")
                    continue
                if pk_col is None:
                    # update all
                    st2, _, raw2 = req(
                        base,
                        key,
                        "PATCH",
                        "/rest/v1/bol_serial_counter?last_value=gte.0",
                        body=patch,
                        extra={"Prefer": "return=representation", "Content-Type": "application/json"},
                    )
                else:
                    val = urllib_quote(str(row[pk_col]))
                    st2, _, raw2 = req(
                        base,
                        key,
                        "PATCH",
                        f"/rest/v1/bol_serial_counter?{pk_col}=eq.{val}",
                        body=patch,
                        extra={"Prefer": "return=representation", "Content-Type": "application/json"},
                    )
                print(f"  reset counter -> {st2} {raw2[:200]!r}")

    print("After wipe:")
    for t in (
        "customer_presets",
        "customer_logos",
        "signatures",
        "bol_serial_log",
        "bol_serial_counter",
        "dropdown_roster",
    ):
        print(f"  after {t}: {count_table(base, key, t)}")
    for bucket in ("customer-logos", "signatures"):
        print(f"  after bucket {bucket}: {len(list_bucket(base, key, bucket))} objects")


def urllib_quote(s: str) -> str:
    from urllib.parse import quote

    return quote(s, safe="")


def wipe_local(docs_root: Path, restore_empty_presets: bool) -> None:
    print(f"Local AppStorage: {docs_root}")
    # Files
    for name in (
        "presets.json",
        "signatures.json",
        "remembered_contacts.json",
        "settings.json",
        "update_schedule.json",
        "bol_serial.txt",
    ):
        p = docs_root / name
        if p.exists():
            p.unlink()
            print(f"  deleted file {p.name}")
        else:
            print(f"  missing {p.name}")

    if restore_empty_presets:
        (docs_root / "presets.json").write_text("{}\n", encoding="utf-8")
        print("  wrote empty presets.json")
    (docs_root / "remembered_contacts.json").write_text("[]\n", encoding="utf-8")
    print("  wrote empty remembered_contacts.json")
    (docs_root / "signatures.json").write_text(
        '{\n  "signatures": []\n}\n', encoding="utf-8"
    )
    print("  wrote empty signatures.json")

    for dirname in ("customer_logos", "signatures", "filled"):
        d = docs_root / dirname
        if not d.is_dir():
            d.mkdir(parents=True, exist_ok=True)
            print(f"  created empty {dirname}/")
            continue
        n = 0
        for child in list(d.iterdir()):
            if child.is_file():
                child.unlink()
                n += 1
            elif child.is_dir():
                shutil.rmtree(child)
                n += 1
        print(f"  cleared {dirname}/ ({n} entries)")

    # Legacy Python data
    legacy = Path.home() / "AppData" / "Local" / "SwiftShippingLabel"
    if legacy.is_dir():
        shutil.rmtree(legacy)
        print(f"  deleted legacy {legacy}")
    else:
        print("  no legacy %LOCALAPPDATA%\\SwiftShippingLabel")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--supabase-only", action="store_true")
    ap.add_argument("--local-only", action="store_true")
    ap.add_argument(
        "--reset-bol",
        action="store_true",
        default=True,
        help="Clear bol_serial_log and reset counter (default on)",
    )
    ap.add_argument("--keep-bol", action="store_true", help="Do not reset BOL serials")
    ap.add_argument(
        "--docs-root",
        type=Path,
        default=ROOT,
        help="AppStorage documents root (default: repo root on this PC)",
    )
    args = ap.parse_args()
    reset_bol = args.reset_bol and not args.keep_bol

    if not args.local_only:
        wipe_supabase(reset_bol=reset_bol)
    if not args.supabase_only:
        wipe_local(args.docs_root, restore_empty_presets=True)


if __name__ == "__main__":
    main()
