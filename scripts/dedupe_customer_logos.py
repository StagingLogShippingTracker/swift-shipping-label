#!/usr/bin/env python3
"""Collapse duplicate customer logos (name + size + visual scan).

Mirrors mobile/lib/logo_dedupe.dart. Default: dry-run. Use --apply to delete.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image
import numpy as np

HASH_SIZE = 8
MAX_HAMMING = 10
MAX_ASPECT_DELTA = 0.22
COPY_NOISE = re.compile(
    r"(\(\d+\)|_\d+_?|-copy(?:\s*\(\d+\))?|_restored(?:_hr)?|_copy)$",
    re.I,
)
CLUTTER = re.compile(r"(\(\d+\)|_\d+_|- copy|history_|_restored)", re.I)
SKIP_NAMES = {
    "logo_restore_cache.json",
    "logo_restore_lessons.json",
}


def normalize_stem(name: str) -> str:
    stem = Path(name).stem.strip().lower()
    for _ in range(6):
        nxt = COPY_NOISE.sub("", stem).strip()
        if nxt == stem:
            break
        stem = nxt
    return re.sub(r"[^a-z0-9]+", "", stem)


def stems_related(a: str, b: str) -> bool:
    na, nb = normalize_stem(a), normalize_stem(b)
    if not na or not nb:
        return False
    if na == nb:
        return True
    if len(na) >= 4 and len(nb) >= 4 and (na in nb or nb in na):
        return True
    return False


def fingerprint(path: Path) -> dict | None:
    try:
        im = Image.open(path).convert("RGBA")
    except Exception:
        return None
    arr = np.asarray(im)
    rgb = arr[:, :, :3].astype(np.int16)
    a = arr[:, :, 3]
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    lum = rgb.mean(axis=2)
    ink = (a >= 80) & ~((lum >= 232) & (sat <= 18)) & ~((lum <= 18) & (sat <= 12))
    if int(ink.sum()) < 12:
        ink = a >= 40
    ys, xs = np.where(ink)
    if len(xs) == 0:
        return None
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    crop = rgb[y0 : y1 + 1, x0 : x1 + 1]
    small = Image.fromarray(crop.astype(np.uint8)).resize(
        (HASH_SIZE, HASH_SIZE), Image.Resampling.BOX
    )
    gray = np.asarray(small).mean(axis=2)
    mean = float(gray.mean())
    bits = (gray.reshape(-1) >= mean).astype(np.uint8)
    h = 0
    for i, bit in enumerate(bits):
        if bit:
            h |= 1 << int(i)
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    return {
        "hash": h,
        "aspect": cw / max(1, ch),
        "ink": int(ink.sum()),
        "w": im.size[0],
        "h": im.size[1],
        "bytes": path.stat().st_size,
    }


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def visual_match(a: dict, b: dict) -> bool:
    if hamming(a["hash"], b["hash"]) > MAX_HAMMING:
        return False
    aspect_delta = abs(a["aspect"] - b["aspect"]) / max(a["aspect"], b["aspect"])
    if aspect_delta > MAX_ASPECT_DELTA:
        return False
    ink_max = max(a["ink"], b["ink"])
    if ink_max and abs(a["ink"] - b["ink"]) / ink_max > 0.55:
        return False
    return True


PREFERRED = {
    "Arc Resources LTD.png",
    "Trialta Projects.png",
    "ARJAE.png",
    "Propak-Energy-Services-Logo.png",
    "GCM logo2.png",
    "bird_source.png",
    "bfl fabricators.png",
    "bfl_google_source.png",
    "murrays_trucking.png",
    "SMJV_Alpha.png",
    "WPW Pipeline and Facility Construction.png",
    "Spartan Delta Corp.png",
    "Worley logo.png",
    "Worley Cord LP.png",
}


def keep_score(path: Path, fp: dict) -> float:
    name = path.name
    score = math.log(max(16, fp["ink"])) * 10
    score += math.log(max(16, fp["w"] * fp["h"])) * 4
    if name in PREFERRED:
        score += 80
    if not CLUTTER.search(name):
        score += 24
    if any(c.isupper() for c in name) and " " in name:
        score += 6
    if "history_" in name.lower():
        score -= 40
    if "copy" in name.lower():
        score -= 18
    if re.search(r"\(\d+\)|_\d+_", name):
        score -= 12
    if "restored" in name.lower() and fp["w"] * fp["h"] > 2_000_000:
        score -= 30
    return score


def plan(files: list[tuple[Path, dict]]) -> list[dict]:
    n = len(files)
    parent = list(range(n))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for i in range(n):
        for j in range(i + 1, n):
            if visual_match(files[i][1], files[j][1]):
                union(i, j)

    buckets: dict[int, list[tuple[Path, dict]]] = defaultdict(list)
    for i, item in enumerate(files):
        buckets[find(i)].append(item)

    groups = []
    for bucket in buckets.values():
        if len(bucket) < 2:
            continue
        versions = _split(bucket)
        for version in versions:
            if len(version) < 2:
                continue
            version.sort(key=lambda it: keep_score(it[0], it[1]), reverse=True)
            keep, drop = version[0][0], [it[0] for it in version[1:]]
            groups.append({"keep": keep, "delete": drop})
    return groups


def _split(bucket: list[tuple[Path, dict]]) -> list[list[tuple[Path, dict]]]:
    seeds: list[tuple[Path, dict]] = []
    for item in bucket:
        is_new = True
        for seed in seeds:
            aspect_delta = abs(item[1]["aspect"] - seed[1]["aspect"]) / max(
                item[1]["aspect"], seed[1]["aspect"]
            )
            canvas_a = item[1]["w"] / max(1, item[1]["h"])
            canvas_b = seed[1]["w"] / max(1, seed[1]["h"])
            canvas_delta = abs(canvas_a - canvas_b) / max(canvas_a, canvas_b)
            ink_max = max(item[1]["ink"], seed[1]["ink"])
            ink_delta = abs(item[1]["ink"] - seed[1]["ink"]) / ink_max if ink_max else 0
            same = (
                hamming(item[1]["hash"], seed[1]["hash"]) <= MAX_HAMMING
                and aspect_delta <= 0.28
                and canvas_delta <= 0.18
                and ink_delta <= 0.28
            )
            if same:
                is_new = False
                break
        if is_new:
            seeds.append(item)
    if len(seeds) <= 1:
        return [bucket]
    groups = [[] for _ in seeds]
    for item in bucket:
        best_i, best_d = 0, 64
        for i, seed in enumerate(seeds):
            d = hamming(item[1]["hash"], seed[1]["hash"])
            if d < best_d:
                best_d, best_i = d, i
        groups[best_i].append(item)
    return [g for g in groups if g]


def remap_presets(presets_path: Path, mapping: dict[str, str]) -> int:
    if not presets_path.exists() or not mapping:
        return 0
    data = json.loads(presets_path.read_text(encoding="utf-8"))
    customers = data.get("customers")
    if not isinstance(customers, dict):
        return 0
    changed = 0
    for preset in customers.values():
        if not isinstance(preset, dict):
            continue
        logos = preset.get("logos") or []
        if not isinstance(logos, list):
            continue
        nxt: list[str] = []
        for name in logos:
            mapped = mapping.get(name, name)
            if mapped not in nxt:
                nxt.append(mapped)
        if nxt != logos:
            preset["logos"] = nxt
            if nxt:
                preset["logo"] = nxt[0]
            elif "logo" in preset:
                preset["logo"] = ""
            changed += 1
    if changed:
        presets_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return changed


def run(folder: Path, apply: bool, protect: set[str]) -> int:
    files: list[tuple[Path, dict]] = []
    for path in sorted(folder.glob("*.png")):
        if path.name in SKIP_NAMES:
            continue
        fp = fingerprint(path)
        if fp:
            files.append((path, fp))
    groups = plan(files)
    # Restored dumps of a mark we already keep are clutter even if upscale
    # changes the hash enough to miss the visual cluster.
    by_stem: dict[str, list[Path]] = defaultdict(list)
    for path, _fp in files:
        by_stem[normalize_stem(path.name)].append(path)
    for stem, paths in by_stem.items():
        sources = [p for p in paths if "_restored" not in p.name.lower()]
        restored = [p for p in paths if "_restored" in p.name.lower()]
        if sources and restored:
            keep = max(sources, key=lambda p: keep_score(p, fingerprint(p) or {"ink": 1, "w": 1, "h": 1}))
            groups.append({"keep": keep, "delete": restored})
    mapping: dict[str, str] = {}
    deleted = 0
    print(f"dir  {folder}")
    print(f"n    {len(files)}  clusters_with_dupes={len(groups)}")
    for g in groups:
        keep = g["keep"]
        drop = [p for p in g["delete"] if p.name not in protect]
        if keep.name in protect:
            # Never delete a protected test fixture; drop the others.
            pass
        print(f"KEEP {keep.name}")
        for d in drop:
            print(f"  DEL {d.name}")
            mapping[d.name] = keep.name
            if apply:
                d.unlink(missing_ok=True)
                deleted += 1
    presets = folder.parent / "presets.json"
    remapped = remap_presets(presets, mapping) if apply else 0
    print(f"deleted={deleted}  presets_remapped={remapped}  apply={apply}")
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument(
        "folder",
        nargs="?",
        help="customer_logos directory (default: Documents + repo)",
    )
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()
    protect = set(PREFERRED)
    if args.folder:
        return run(Path(args.folder), args.apply, protect if "Projects" in args.folder else set())
    root = Path(__file__).resolve().parents[1]
    docs = Path.home() / "OneDrive" / "Documents" / "swift_document_generator" / "customer_logos"
    run(root / "customer_logos", args.apply, protect)
    if docs.is_dir():
        run(docs, args.apply, set())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
