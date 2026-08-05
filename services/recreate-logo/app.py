"""Fly.io Recreate service — same Python pipeline Windows uses locally.

POST /recreate-logo with raw image bytes; returns the JSON shape expected by
mobile/lib/logo_recreate_cloud.dart (svg, png_base64, palette_hex, …).

Optional Gemini assist (GEMINI_API_KEY / GOOGLE_API_KEY) inspects the raster
before vectorization for brand colors / layout hints.
"""

from __future__ import annotations

import base64
import os
import tempfile
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from PIL import Image

from tools.logo_vectorizer.customer_recreate import recreate_customer_logo
from tools.logo_vectorizer.env_loader import load_env

load_env()

app = FastAPI(title="Swift Recreate Logo", version="1.1.0")

AUTH_TOKEN = os.environ.get("RECREATE_AUTH_TOKEN", "").strip()
MAX_UPLOAD_BYTES = int(os.environ.get("RECREATE_MAX_UPLOAD_BYTES", str(12 * 1024 * 1024)))
GEMINI_ENABLED = bool(
    os.environ.get("GEMINI_API_KEY", "").strip()
    or os.environ.get("GOOGLE_API_KEY", "").strip()
)


def _authorized(request: Request) -> bool:
    if not AUTH_TOKEN:
        # Misconfigured deploy — refuse rather than leave open.
        return False
    auth = (request.headers.get("authorization") or "").strip()
    apikey = (request.headers.get("apikey") or "").strip()
    bearer = ""
    if auth.lower().startswith("bearer "):
        bearer = auth[7:].strip()
    return bearer == AUTH_TOKEN or apikey == AUTH_TOKEN


@app.get("/health")
def health() -> dict[str, object]:
    return {
        "ok": True,
        "auth_configured": bool(AUTH_TOKEN),
        "gemini_configured": GEMINI_ENABLED,
        "gemini_project": os.environ.get("GEMINI_PROJECT_NUMBER", ""),
    }


@app.post("/recreate-logo")
async def recreate_logo(
    request: Request,
    render_width: int = Query(3000, ge=64, le=8000),
    max_colors: int = Query(6, ge=1, le=16),
    use_ai: bool = Query(True),
) -> JSONResponse:
    if not _authorized(request):
        raise HTTPException(status_code=401, detail="unauthorized")

    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="empty body")
    if len(body) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="image too large")

    suffix = _suffix_from_content_type(request.headers.get("content-type", ""))
    with tempfile.TemporaryDirectory(prefix="swift_recreate_") as tmp:
        tmp_path = Path(tmp)
        src = tmp_path / f"input{suffix}"
        svg_out = tmp_path / "out.svg"
        png_out = tmp_path / "out.png"
        src.write_bytes(body)

        try:
            with Image.open(src) as im:
                im.load()
                source_width, source_height = im.size
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"invalid image: {e}") from e

        try:
            result = recreate_customer_logo(
                src,
                output_svg=svg_out,
                output_png=png_out,
                max_colors=max_colors,
                render_width=render_width,
                render_background="transparent",
                use_ai=use_ai and GEMINI_ENABLED,
                ai_providers=["gemini"],
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"recreate failed: {e}") from e

        if not png_out.is_file():
            raise HTTPException(status_code=500, detail="recreate produced no PNG")

        png_b64 = base64.b64encode(png_out.read_bytes()).decode("ascii")
        gemini_notes = [n for n in result.notes if n.startswith("gemini_")]
        payload = {
            "svg": result.svg_text,
            "png_base64": png_b64,
            "palette_hex": result.palette_hex,
            "section_count": result.section_count,
            "bg_stripped": result.background_stripped,
            "source_width": source_width,
            "source_height": source_height,
            "render_width": render_width,
            "total_anchors": result.total_anchors,
            "backend": "python-logo-vectorizer",
            "gemini_assisted": bool(gemini_notes),
            "gemini_notes": gemini_notes,
        }
        return JSONResponse(payload)


def _suffix_from_content_type(content_type: str) -> str:
    ct = (content_type or "").lower().split(";")[0].strip()
    return {
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
        "image/gif": ".gif",
        "image/bmp": ".bmp",
    }.get(ct, ".png")
