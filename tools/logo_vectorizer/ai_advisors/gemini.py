"""Google Gemini vision advisor."""

from __future__ import annotations

import sys
from typing import Any

from PIL import Image

from .base import CritiqueResult, SourceHints, encode_png, env_key, extract_json, http_post_json

MODEL = "gemini-2.0-flash"

SOURCE_PROMPT = """Analyze this logo PNG for high-quality vector tracing.
Identify letter counters/holes (especially P letter eyes in wordmarks), straight vs curved strokes, and preprocessing needs.

Return JSON only:
{
  "has_holes": true,
  "hole_descriptions": ["P counters in SUPPLY wordmark"],
  "letter_regions": [{"name": "SUPPLY", "y_frac": [0.62, 0.92]}],
  "recommended_backends": ["opencv-tree", "potrace", "vtracer"],
  "recommended_preprocess": {"upscale": 4, "blur_radius": 1.2, "alpha_threshold": 80},
  "straight_vs_curve": "SWIFT bold curves; SUPPLY mostly straight stems with round P bowls",
  "notes": "preserve evenodd holes"
}"""

CRITIQUE_PROMPT = """Compare the logo reference (image 1) vs SVG trace render (image 2).
Metrics: backend={backend}, alpha_iou={alpha_iou:.3f}, p_hollow={p_hollow:.3f}, holes={holes}

Check: Are P letter counters transparent/open (not filled)? Jagged stairstep edges?

Return JSON only:
{
  "passes_qa": true,
  "missing_counters": false,
  "jagged_regions": false,
  "confidence": 0.9,
  "issues": [],
  "reject_candidate": false
}"""


def available() -> bool:
    return env_key("GOOGLE_API_KEY", "GEMINI_API_KEY") is not None


def _call_gemini(parts: list[dict[str, Any]]) -> str:
    key = env_key("GOOGLE_API_KEY", "GEMINI_API_KEY")
    if not key:
        raise RuntimeError("Gemini API key not set (GOOGLE_API_KEY or GEMINI_API_KEY)")

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={key}"
    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {"responseMimeType": "application/json", "temperature": 0.2},
    }
    data = http_post_json(url, payload, headers={})
    try:
        return data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"Unexpected Gemini response: {data!r}") from exc


def analyze_source(img: Image.Image) -> SourceHints | None:
    try:
        b64, mime = encode_png(img)
        text = _call_gemini(
            [
                {"text": SOURCE_PROMPT},
                {"inline_data": {"mime_type": mime, "data": b64}},
            ]
        )
        return SourceHints.from_dict(extract_json(text), provider="gemini")
    except Exception as exc:
        print(f"[ai/gemini] source analysis failed: {exc}", file=sys.stderr)
        return None


def critique_render(
    ref_img: Image.Image,
    render_img: Image.Image,
    *,
    backend: str,
    alpha_iou: float,
    p_hollow: float,
    holes: int,
) -> CritiqueResult | None:
    try:
        ref_b64, ref_mime = encode_png(ref_img)
        ren_b64, ren_mime = encode_png(render_img)
        prompt = CRITIQUE_PROMPT.format(
            backend=backend,
            alpha_iou=alpha_iou,
            p_hollow=p_hollow,
            holes=holes,
        )
        text = _call_gemini(
            [
                {"text": prompt},
                {"text": "Image 1 — reference PNG:"},
                {"inline_data": {"mime_type": ref_mime, "data": ref_b64}},
                {"text": "Image 2 — SVG render:"},
                {"inline_data": {"mime_type": ren_mime, "data": ren_b64}},
            ]
        )
        return CritiqueResult.from_dict(extract_json(text), provider="gemini")
    except Exception as exc:
        print(f"[ai/gemini] critique failed: {exc}", file=sys.stderr)
        return None
