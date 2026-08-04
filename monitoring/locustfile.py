"""
locustfile.py — DCO Phase 4: Professional Load Testing Suite
=============================================================

Simulates realistic traffic patterns against the DCO Image Processing API
to stress-test CPU and memory, triggering CloudWatch metric spikes for
the Resource Optimizer analysis.

Usage:
  # Web UI mode (recommended for demos):
  locust -f locustfile.py --host http://<EC2_PUBLIC_IP>

  # Headless mode (for CI/automated runs):
  locust -f locustfile.py --host http://<EC2_PUBLIC_IP> \
    --headless -u 50 -r 5 --run-time 5m \
    --csv results/load_test

Requirements:
  pip install locust Pillow
"""

import io
import time
import random
from locust import HttpUser, task, between, events, tag
from PIL import Image


# =========================================================================
# Helper: Generate a random test image in memory
# =========================================================================
def generate_test_image(
    width: int = 512,
    height: int = 512,
    fmt: str = "JPEG",
) -> io.BytesIO:
    """Create a random-colored test image for upload testing."""
    color = (
        random.randint(0, 255),
        random.randint(0, 255),
        random.randint(0, 255),
    )
    img = Image.new("RGB", (width, height), color=color)
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    buf.seek(0)
    buf.name = f"loadtest_{int(time.time())}.jpg"
    return buf


# =========================================================================
# User Behavior 1: Health Check Traffic (Lightweight)
# =========================================================================
class HealthCheckUser(HttpUser):
    """
    Simulates monitoring/health-check traffic.
    High frequency, low impact — like a load balancer probe.
    """

    weight = 2  # Lower spawn weight
    wait_time = between(1, 3)

    @tag("health")
    @task
    def check_health(self):
        with self.client.get("/health", name="/health", catch_response=True) as resp:
            if resp.status_code == 200 and resp.json().get("status") == "UP":
                resp.success()
            else:
                resp.failure(f"Health check failed: {resp.status_code}")

    @tag("root")
    @task
    def check_root(self):
        self.client.get("/", name="/")


# =========================================================================
# User Behavior 2: CPU Stress Attacker (Heavy)
# =========================================================================
class CPUStressUser(HttpUser):
    """
    Simulates users triggering the /stress endpoint to spike CPU utilisation.
    This is the primary driver for CloudWatch CPU alarms.

    Each request pins a CPU core for 5–15 seconds. With multiple concurrent
    users, this quickly saturates a t2.micro/t3.micro instance.
    """

    weight = 6  # Higher spawn weight — most users will be stressors
    wait_time = between(2, 5)

    @tag("stress", "cpu")
    @task(10)
    def stress_medium(self):
        """Medium stress: 5-second CPU spike."""
        self.client.get(
            "/stress?duration=5",
            name="/stress [5s]",
            timeout=30,
        )

    @tag("stress", "cpu")
    @task(5)
    def stress_heavy(self):
        """Heavy stress: 10-second CPU spike."""
        self.client.get(
            "/stress?duration=10",
            name="/stress [10s]",
            timeout=30,
        )

    @tag("stress", "cpu")
    @task(2)
    def stress_extreme(self):
        """Extreme stress: 15-second CPU spike (less frequent)."""
        self.client.get(
            "/stress?duration=15",
            name="/stress [15s]",
            timeout=45,
        )

    @tag("health")
    @task(3)
    def health_between_stress(self):
        """Intersperse health checks between stress tests."""
        self.client.get("/health", name="/health")


# =========================================================================
# User Behavior 3: Image Upload User (Memory + I/O)
# =========================================================================
class ImageUploadUser(HttpUser):
    """
    Simulates users uploading images for processing.
    Stresses memory (Pillow image processing) and network I/O.

    NOTE: Requires the S3 backend to be configured on the server.
    If S3 is not configured, these requests will return 503 — that's
    fine for CPU/memory testing purposes.
    """

    weight = 2  # Lower weight
    wait_time = between(3, 8)

    @tag("upload", "memory")
    @task(5)
    def upload_small_image(self):
        """Upload a small 256x256 image."""
        img = generate_test_image(256, 256)
        self.client.post(
            "/upload",
            name="/upload [256x256]",
            files={"file": ("test.jpg", img, "image/jpeg")},
            timeout=15,
        )

    @tag("upload", "memory")
    @task(3)
    def upload_medium_image(self):
        """Upload a medium 1024x1024 image."""
        img = generate_test_image(1024, 1024)
        self.client.post(
            "/upload",
            name="/upload [1024x1024]",
            files={"file": ("test_large.jpg", img, "image/jpeg")},
            timeout=20,
        )

    @tag("upload", "memory")
    @task(1)
    def upload_large_image(self):
        """Upload a large 2048x2048 image — maximum memory pressure."""
        img = generate_test_image(2048, 2048)
        self.client.post(
            "/upload",
            name="/upload [2048x2048]",
            files={"file": ("test_xl.jpg", img, "image/jpeg")},
            timeout=30,
        )


# =========================================================================
# Event hooks — Print summary statistics
# =========================================================================
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print("=" * 60)
    print("  DCO Load Test Starting")
    print(f"  Target: {environment.host}")
    print("  User Types: HealthCheckUser, CPUStressUser, ImageUploadUser")
    print("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    print("=" * 60)
    print("  DCO Load Test Complete")
    print("  Check CloudWatch → DCO_Project_Metrics for results")
    print("=" * 60)
