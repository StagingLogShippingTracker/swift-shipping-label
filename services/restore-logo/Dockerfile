# Logo restore service — RealESRGAN (CPU PyTorch) + FastAPI.
# Build context must be the repo root:
#   fly deploy . --config services/restore-logo/fly.toml
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=8080

RUN apt-get update && apt-get install -y libgl1-mesa-glx libglib2.0-0 \
    || apt-get install -y libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN pip install --no-cache-dir torch torchvision \
        --index-url https://download.pytorch.org/whl/cpu

RUN pip install --no-cache-dir \
        fastapi \
        python-multipart \
        uvicorn \
        opencv-python-headless \
        realesrgan \
        basicsr \
        numpy \
        Pillow

COPY logo_restorer.py /app/logo_restorer.py
COPY services/restore-logo/main.py /app/main.py

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-keep-alive", "120"]
