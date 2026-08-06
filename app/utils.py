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

    # Resize first to avoid massive memory usage on 4K images
    image.thumbnail(size, Image.Resampling.LANCZOS)
    
    # --- SIMULATE HEAVY AI PROCESSING (CPU STRESS) ---
    # Apply complex filters multiple times to simulate a heavy workload
    # like a Machine Learning pipeline (Feature Extraction, etc.)
    from PIL import ImageFilter
    for _ in range(5):
        image = image.filter(ImageFilter.GaussianBlur(radius=2))
        image = image.filter(ImageFilter.UnsharpMask(radius=2, percent=150))
    
    # Add a tight math loop to guarantee CPU spike per image
    for j in range(150000):
        _ = math.sqrt(j) * math.sin(j) * math.cos(j)
    # -------------------------------------------------

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


def _burn_cpu(duration_seconds: int):
    """Worker function that burns CPU for the given duration."""
    start = time.time()
    iterations = 0
    while (time.time() - start) < duration_seconds:
        # Tight loop with heavy math to max out CPU
        _ = math.sqrt(iterations) * math.sin(iterations) * math.cos(iterations)
        _ = math.pow(iterations % 1000, 3)
        iterations += 1
    return iterations


def cpu_stress_task(duration_seconds: int = 5) -> dict:
    """
    Perform a CPU-intensive computation for the given duration.

    Uses multiprocessing to spawn one worker per CPU core, ensuring
    100% CPU utilisation across ALL cores. This is critical for
    triggering AWS Auto Scaling policies.

    Args:
        duration_seconds: How long (in seconds) to run the heavy loop.

    Returns:
        A dict with timing and computation metadata.
    """
    import multiprocessing
    import os

    ctx = multiprocessing.get_context('spawn')
    num_workers = os.cpu_count() or 1
    start = time.time()

    # Spawn one process per CPU core, each burning CPU independently
    with ctx.Pool(processes=num_workers) as pool:
        results = pool.starmap(
            _burn_cpu,
            [(duration_seconds,)] * num_workers
        )

    total_iterations = sum(results)
    elapsed = round(time.time() - start, 2)
    return {
        "iterations_completed": total_iterations,
        "duration_seconds": elapsed,
        "workers": num_workers,
        "message": f"CPU stress test completed: {total_iterations:,} iterations across {num_workers} cores in {elapsed}s",
    }

