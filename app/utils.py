"""
utils.py - Helper functions for image processing operations.

Part of the DCO (DevOps-Enabled Cloud Resource Optimizer) system.
"""

from __future__ import annotations

import io
import math
import time
from PIL import Image


def resize_image_to_thumbnail(
    image_bytes: bytes,
    size: tuple[int, int] = (128, 128),
) -> io.BytesIO:
    """
    Resize an image to the specified thumbnail dimensions.

    Args:
        image_bytes: Raw bytes of the uploaded image.
        size: Target dimensions as (width, height). Defaults to 128x128.

    Returns:
        A BytesIO buffer containing the resized image in PNG format.
    """
    image = Image.open(io.BytesIO(image_bytes))

    # Convert to RGB if the image has an alpha channel or is in a mode
    # incompatible with certain output formats.
    if image.mode in ("RGBA", "P", "LA"):
        image = image.convert("RGB")

    image.thumbnail(size, Image.Resampling.LANCZOS)

    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    buffer.seek(0)
    return buffer


def generate_s3_key(original_filename: str) -> str:
    """
    Generate a unique S3 object key based on the original filename and a
    timestamp to avoid collisions.

    Args:
        original_filename: The name of the originally uploaded file.

    Returns:
        A string like 'thumbnails/1690000000_photo.png'.
    """
    timestamp = int(time.time())
    base_name = original_filename.rsplit(".", 1)[0] if "." in original_filename else original_filename
    return f"thumbnails/{timestamp}_{base_name}.png"


def cpu_stress_task(duration_seconds: int = 5) -> dict:
    """
    Perform a CPU-intensive computation for the given duration.

    This deliberately pins a CPU core to simulate high utilisation, which is
    used to trigger autoscaling alerts and test the Resource Optimizer
    component of the DCO system.

    Args:
        duration_seconds: How long (in seconds) to run the heavy loop.

    Returns:
        A dict with timing and computation metadata.
    """
    start = time.time()
    iterations = 0

    # Heavy math loop — runs until the wall-clock duration is exceeded.
    while (time.time() - start) < duration_seconds:
        # Intentionally expensive: trigonometric + power operations.
        _ = math.sqrt(iterations) * math.sin(iterations) * math.cos(iterations)
        _ = math.pow(iterations % 1000, 3)
        iterations += 1

    elapsed = round(time.time() - start, 2)
    return {
        "iterations_completed": iterations,
        "duration_seconds": elapsed,
        "message": f"CPU stress test completed: {iterations:,} iterations in {elapsed}s",
    }
