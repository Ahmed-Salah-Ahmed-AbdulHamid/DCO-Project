"""
test_main.py — Unit tests for the DCO Image Processing API.

These tests run in the CI pipeline (Job 1) to validate core endpoints
before building and deploying the Docker image.

Uses FastAPI's TestClient (backed by httpx) for synchronous testing.
"""

import io
import pytest
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

# Mock the S3 client before importing the app, so lifespan doesn't fail
with patch("main.boto3") as mock_boto3:
    mock_boto3.client.return_value = MagicMock()
    from main import app

client = TestClient(app)


# =========================================================================
# GET / — Welcome endpoint
# =========================================================================
class TestRootEndpoint:
    """Tests for the welcome / root endpoint (Frontend)."""

    def test_root_returns_200(self):
        response = client.get("/")
        assert response.status_code == 200

    def test_root_returns_html(self):
        response = client.get("/")
        assert "text/html" in response.headers.get("content-type", "")
        assert "DCO Optimizer" in response.text


# =========================================================================
# GET /health — Health check endpoint
# =========================================================================
class TestHealthEndpoint:
    """Tests for the CI/CD health check endpoint."""

    def test_health_returns_200(self):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_returns_status_up(self):
        response = client.get("/health")
        data = response.json()
        assert data == {"status": "UP"}


# =========================================================================
# GET /stress — CPU stress endpoint
# =========================================================================
class TestStressEndpoint:
    """Tests for the CPU stress / resource optimizer endpoint."""

    def test_stress_returns_200(self):
        # Use a very short duration so tests don't take long
        response = client.get("/stress?duration=1")
        assert response.status_code == 200

    def test_stress_returns_expected_fields(self):
        response = client.get("/stress?duration=1")
        data = response.json()
        assert "iterations_completed" in data
        assert "duration_seconds" in data
        assert "message" in data

    def test_stress_respects_duration(self):
        response = client.get("/stress?duration=1")
        data = response.json()
        # Allow some tolerance — should be roughly 1 second
        assert 0.5 <= data["duration_seconds"] <= 3.0

    def test_stress_rejects_invalid_duration(self):
        # Duration must be 1–30
        response = client.get("/stress?duration=0")
        assert response.status_code == 422

    def test_stress_rejects_excessive_duration(self):
        response = client.get("/stress?duration=100")
        assert response.status_code == 422


# =========================================================================
# POST /upload — Image upload endpoint
# =========================================================================
class TestUploadEndpoint:
    """Tests for the image upload and S3 storage endpoint."""

    @pytest.fixture(autouse=True)
    def mock_s3_client(self):
        """
        Ensure `main.s3_client` is a MagicMock for every test in this class.

        The real client is only created inside the FastAPI `lifespan`
        context manager, which never runs against a plain `TestClient(app)`
        instance — so without this fixture, `main.s3_client` stays `None`
        and any test that reaches the S3-availability guard gets a 503
        instead of whatever status the test actually meant to check.
        """
        with patch("main.s3_client", MagicMock()) as mock_s3:
            yield mock_s3

    def _create_test_image(self, format: str = "PNG") -> io.BytesIO:
        """Generate a small in-memory test image."""
        from PIL import Image

        img = Image.new("RGB", (256, 256), color="red")
        buf = io.BytesIO()
        img.save(buf, format=format)
        buf.seek(0)
        return buf

    def test_upload_rejects_non_image(self):
        response = client.post(
            "/upload",
            files={"file": ("test.txt", b"not an image", "text/plain")},
        )
        assert response.status_code == 400
        assert "Unsupported file type" in response.json()["detail"]

    def test_upload_success(self, mock_s3_client):
        """Test successful upload with a mocked S3 client."""
        mock_s3_client.put_object.return_value = {}
        mock_s3_client.generate_presigned_url.return_value = "https://mock-presigned-url"
        image_buf = self._create_test_image()

        response = client.post(
            "/upload",
            files={"file": ("test.png", image_buf, "image/png")},
        )

        assert response.status_code == 201
        data = response.json()
        assert data["message"] == "Image processed and uploaded successfully."
        assert data["original_filename"] == "test.png"
        assert data["thumbnail_size"] == "128x128"
        assert "s3_url" in data
        assert "s3_key" in data

    def test_upload_returns_correct_s3_key_prefix(self, mock_s3_client):
        mock_s3_client.put_object.return_value = {}
        mock_s3_client.generate_presigned_url.return_value = "https://mock-presigned-url"
        image_buf = self._create_test_image()

        response = client.post(
            "/upload",
            files={"file": ("photo.jpg", image_buf, "image/jpeg")},
        )

        data = response.json()
        assert data["s3_key"].startswith("thumbnails/")
        assert "photo" in data["s3_key"]


# =========================================================================
# GET /resources — Live Metrics
# =========================================================================
class TestResourcesEndpoint:
    """Tests for the live resource metrics dashboard endpoint."""

    @patch("main.psutil")
    def test_resources_returns_200(self, mock_psutil):
        mock_psutil.cpu_percent.return_value = 15.0
        mock_psutil.virtual_memory.return_value.percent = 45.0
        
        response = client.get("/resources")
        assert response.status_code == 200
        
        data = response.json()
        assert data["cpu_percent"] == 15.0
        assert data["memory_percent"] == 45.0


# =========================================================================
# Utility function tests
# =========================================================================
class TestUtils:
    """Tests for helper functions in utils.py."""

    def test_resize_produces_thumbnail(self):
        from PIL import Image
        from utils import resize_image_to_thumbnail

        # Create a 512x512 image
        img = Image.new("RGB", (512, 512), color="blue")
        buf = io.BytesIO()
        img.save(buf, format="PNG")

        result = resize_image_to_thumbnail(buf.getvalue(), size=(128, 128))

        # Verify the output is a valid image of the right size
        output_img = Image.open(result)
        assert output_img.size[0] <= 128
        assert output_img.size[1] <= 128

    def test_generate_s3_key_format(self):
        from utils import generate_s3_key

        key = generate_s3_key("vacation_photo.jpg")
        assert key.startswith("thumbnails/")
        assert key.endswith(".png")
        assert "vacation_photo" in key

    def test_cpu_stress_runs_for_duration(self):
        from utils import cpu_stress_task

        result = cpu_stress_task(duration_seconds=1)
        assert result["iterations_completed"] > 0
        assert 0.5 <= result["duration_seconds"] <= 3.0