# Python Recreate service — same tools/logo_vectorizer pipeline as Windows.
# Build context must be the repo root:
#   fly deploy --dockerfile services/recreate-logo/Dockerfile --config services/recreate-logo/fly.toml
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
        libcairo2 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libgdk-pixbuf-2.0-0 \
        libffi8 \
        shared-mime-info \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY services/recreate-logo/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

COPY tools /app/tools
# Ensure `tools` is a package for `from tools.logo_vectorizer...`
RUN touch /app/tools/__init__.py
COPY services/recreate-logo/app.py /app/app.py

EXPOSE 8080

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-keep-alive", "75"]
