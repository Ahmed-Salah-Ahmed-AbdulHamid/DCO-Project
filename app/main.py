"""
main.py - Core FastAPI application for the Image Processing API.

Part of the DCO (DevOps-Enabled Cloud Resource Optimizer) system.
This service provides image upload + thumbnail generation with S3 storage,
along with a /stress endpoint used for autoscaling and resource-optimiser testing.
"""

import os
import logging
from contextlib import asynccontextmanager

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
from fastapi.responses import JSONResponse
import psutil

from utils import cpu_stress_task, generate_s3_key, resize_image_to_thumbnail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
load_dotenv()  # Load .env file when running locally

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "my-image-processing-bucket")
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp"}
MAX_UPLOAD_SIZE_MB = 10

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# S3 client initialisation (lazy — created once at startup)
# ---------------------------------------------------------------------------
s3_client = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialise shared resources on startup and tear them down on shutdown."""
    global s3_client
    try:
        session_kwargs = {"region_name": AWS_REGION}
        if AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY:
            session_kwargs["aws_access_key_id"] = AWS_ACCESS_KEY_ID
            session_kwargs["aws_secret_access_key"] = AWS_SECRET_ACCESS_KEY

        s3_client = boto3.client("s3", **session_kwargs)
        logger.info("S3 client initialised (region=%s, bucket=%s)", AWS_REGION, S3_BUCKET_NAME)
    except Exception as exc:
        logger.warning("S3 client could not be initialised: %s. /upload will be unavailable.", exc)

    yield  # Application is running

    # Shutdown — nothing to clean up for boto3
    logger.info("Application shutting down.")


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Image Processing API",
    description=(
        "A FastAPI service that resizes images to thumbnails and uploads them to AWS S3. "
        "Part of the DevOps-Enabled Cloud Resource Optimizer (DCO) system."
    ),
    version="1.0.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
import pathlib
from fastapi.responses import HTMLResponse

@app.get("/", tags=["General"], response_class=HTMLResponse)
async def root():
    """Welcome endpoint — returns the modern HTML frontend."""
    html_path = pathlib.Path(__file__).parent / "frontend.html"
    if html_path.exists():
        return HTMLResponse(content=html_path.read_text(encoding="utf-8"), status_code=200)
    return HTMLResponse(content="<h1>Frontend UI not found</h1>", status_code=404)


@app.get("/health", tags=["General"])
async def health_check():
    """
    Health-check endpoint consumed by load balancers, CI/CD pipelines,
    and container orchestrators (ECS, Kubernetes).
    """
    return {"status": "UP"}


@app.post("/upload", tags=["Image Processing"])
async def upload_image(file: UploadFile = File(..., description="Image file to process and upload")):
    """
    Accept an image upload, resize it to a 128×128 thumbnail, and store the
    result in AWS S3.

    **Supported formats:** JPEG, PNG, GIF, WebP, BMP

    Returns the public S3 URL of the uploaded thumbnail.
    """
    # --- Validate content type (input validation first) ---------------------
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type '{file.content_type}'. Allowed: {', '.join(sorted(ALLOWED_CONTENT_TYPES))}",
        )

    # --- Read and validate size --------------------------------------------
    image_bytes = await file.read()
    size_mb = len(image_bytes) / (1024 * 1024)
    if size_mb > MAX_UPLOAD_SIZE_MB:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({size_mb:.1f} MB). Maximum allowed is {MAX_UPLOAD_SIZE_MB} MB.",
        )

    # --- Guard: S3 client must be available --------------------------------
    if s3_client is None:
        raise HTTPException(
            status_code=503,
            detail="S3 client is not configured. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY.",
        )

    # --- Resize to thumbnail -----------------------------------------------
    try:
        thumbnail_buffer = resize_image_to_thumbnail(image_bytes, size=(128, 128))
    except Exception as exc:
        logger.error("Image processing failed: %s", exc)
        raise HTTPException(status_code=422, detail=f"Failed to process image: {exc}")

    # --- Upload to S3 -------------------------------------------------------
    s3_key = generate_s3_key(file.filename or "image")
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=thumbnail_buffer.getvalue(),
            ContentType="image/png",
        )
    except (BotoCoreError, ClientError) as exc:
        logger.error("S3 upload failed: %s", exc)
        raise HTTPException(status_code=502, detail=f"S3 upload failed: {exc}")

    # Generate presigned URL for secure frontend access
    try:
        s3_url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': S3_BUCKET_NAME, 'Key': s3_key},
            ExpiresIn=3600
        )
    except Exception as exc:
        logger.error("Failed to generate presigned URL: %s", exc)
        s3_url = f"https://{S3_BUCKET_NAME}.s3.{AWS_REGION}.amazonaws.com/{s3_key}"

    logger.info("Thumbnail uploaded → %s", s3_key)

    return JSONResponse(
        status_code=201,
        content={
            "message": "Image processed and uploaded successfully.",
            "original_filename": file.filename,
            "thumbnail_size": "128x128",
            "s3_url": s3_url,
            "s3_key": s3_key,
        },
    )


@app.get("/stress", tags=["DevOps / Testing"])
def stress_test(
    duration: int = Query(
        default=5,
        ge=1,
        le=30,
        description="Duration in seconds for the CPU stress test (1–30).",
    ),
):
    """
    **CPU Stress Endpoint** — used by the DCO Resource Optimizer.

    Runs a tight mathematical loop for the requested duration to spike CPU
    utilisation.  This allows testing of:

    - CloudWatch alarms / metrics-based autoscaling
    - ECS or Kubernetes HPA scale-out triggers
    - Cost-optimisation alerting pipelines
    """
    logger.info("Starting CPU stress test for %d seconds …", duration)
    result = cpu_stress_task(duration_seconds=duration)
    logger.info("Stress test finished: %s", result["message"])
    return result


@app.get("/resources", tags=["DevOps / Testing"])
async def get_resources():
    """Returns live CPU and Memory utilization for the dashboard."""
    return {
        "cpu_percent": psutil.cpu_percent(interval=0.1),
        "memory_percent": psutil.virtual_memory().percent
    }