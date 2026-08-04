# ==========================================================================
# Dockerfile — Image Processing API (DCO Phase 1)
# Multi-stage-friendly, production-ready, minimal image.
# ==========================================================================

# ---------- Base image ----------------------------------------------------
FROM python:3.9-slim AS base

# Prevent Python from writing .pyc files and enable unbuffered stdout/stderr
# so container logs appear in real time.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ---------- System dependencies -------------------------------------------
# Pillow needs a few native libraries for image codec support.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libjpeg62-turbo-dev \
        zlib1g-dev \
        libwebp-dev && \
    rm -rf /var/lib/apt/lists/*

# ---------- Working directory ---------------------------------------------
WORKDIR /app

# ---------- Python dependencies (cached layer) ----------------------------
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ---------- Application code ----------------------------------------------
COPY . .

# ---------- Non-root user (security best practice) ------------------------
RUN adduser --disabled-password --no-create-home appuser
USER appuser

# ---------- Expose & run --------------------------------------------------
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
