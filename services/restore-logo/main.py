"""Fly.io FastAPI service — restore low-res logos via logo_restorer.restore_logo."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import Response

ROOT = Path(__file__).resolve().parent
for candidate in (ROOT, *ROOT.parents):
    if (candidate / "logo_restorer.py").is_file():
        if str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))
        break
else:
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))

from logo_restorer import restore_logo  # noqa: E402

app = FastAPI(title="Swift Restore Logo", version="1.0.0")

MAX_UPLOAD_BYTES = 12 * 1024 * 1024
ALLOWED_SUFFIXES = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/bmp": ".bmp",
}


@app.get("/health")
def health() -> dict[str, object]:
    return {"ok": True, "service": "restore-logo"}


@app.post("/api/v1/restore-logo")
async def restore_logo_endpoint(
    file: UploadFile = File(...),
) -> Response:
    content_type = (file.content_type or "").split(";")[0].strip().lower()
    suffix = ALLOWED_SUFFIXES.get(content_type, ".png")
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty file")
    if len(raw) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="image too large")

    with tempfile.TemporaryDirectory(prefix="swift_restore_") as tmp:
        tmp_path = Path(tmp)
        src = tmp_path / f"input{suffix}"
        dest = tmp_path / "restored.png"
        src.write_bytes(raw)
        try:
            restore_logo(str(src), str(dest), min_dimension=3000)
        except FileNotFoundError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"restore failed: {e}") from e
        if not dest.is_file():
            raise HTTPException(status_code=500, detail="restore produced no PNG")
        png_bytes = dest.read_bytes()

    return Response(content=png_bytes, media_type="image/png")
