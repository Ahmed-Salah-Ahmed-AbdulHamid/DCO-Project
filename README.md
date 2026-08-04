# 🖼️ Image Processing API — DCO Phase 1

**Local Development & Containerization** for the DevOps-Enabled Cloud Resource Optimizer (DCO) system.

A FastAPI service that accepts image uploads, resizes them to 128×128 thumbnails using Pillow, and stores the results in AWS S3 via boto3. Includes a `/stress` endpoint for autoscaling and resource-optimiser testing.

---

## 📁 Project Structure

```
app/
├── main.py            # Core FastAPI application (all endpoints)
├── utils.py           # Image processing helpers & CPU stress function
├── requirements.txt   # Python dependencies
├── Dockerfile         # Production-ready container definition
├── .env.example       # Template for environment variables
└── .dockerignore      # Files excluded from Docker build context
```

---

## 🔌 API Endpoints

| Method | Path       | Purpose                                              |
|--------|------------|------------------------------------------------------|
| GET    | `/`        | Welcome message — confirms the API is reachable      |
| GET    | `/health`  | Returns `{"status": "UP"}` for CI/CD health checks   |
| POST   | `/upload`  | Upload an image → resize to 128×128 → store in S3    |
| GET    | `/stress`  | CPU stress test (query param `duration`, 1–30 sec)   |

Once running, interactive Swagger docs are available at **`/docs`**.

---

## 🚀 Option 1 — Run Locally (without Docker)

### Prerequisites
- Python 3.9+
- pip

### Steps

```bash
# 1. Navigate to the app directory
cd app

# 2. Create and activate a virtual environment
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment variables
#    Copy the template and fill in your real AWS credentials:
cp .env.example .env        # Linux/macOS
copy .env.example .env      # Windows

# 5. Start the development server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

The API is now live at **http://localhost:8000** — visit **http://localhost:8000/docs** for Swagger UI.

### Environment Variables

| Variable               | Default                        | Description                              |
|------------------------|--------------------------------|------------------------------------------|
| `AWS_REGION`           | `us-east-1`                    | AWS region for the S3 bucket             |
| `S3_BUCKET_NAME`       | `my-image-processing-bucket`   | Target S3 bucket name                    |
| `AWS_ACCESS_KEY_ID`    | *(none)*                       | IAM access key (or use IAM role)         |
| `AWS_SECRET_ACCESS_KEY`| *(none)*                       | IAM secret key (or use IAM role)         |

> **Note:** If running on an EC2 instance or ECS task with an attached IAM role, you can omit the access key variables entirely — boto3 will use the instance metadata service.

---

## 🐳 Option 2 — Build & Run with Docker

### Build the image

```bash
cd app
docker build -t image-processing-api:latest .
```

### Run the container

```bash
docker run -d \
  --name image-api \
  -p 8000:8000 \
  -e AWS_REGION=us-east-1 \
  -e S3_BUCKET_NAME=my-image-processing-bucket \
  -e AWS_ACCESS_KEY_ID=your-access-key-id \
  -e AWS_SECRET_ACCESS_KEY=your-secret-access-key \
  image-processing-api:latest
```

Or with an `.env` file:

```bash
docker run -d \
  --name image-api \
  -p 8000:8000 \
  --env-file .env \
  image-processing-api:latest
```

### Verify

```bash
# Health check
curl http://localhost:8000/health
# → {"status":"UP"}

# Stress test (5 seconds)
curl "http://localhost:8000/stress?duration=5"

# Upload an image
curl -X POST http://localhost:8000/upload \
  -F "file=@/path/to/your/image.jpg"
```

---

## 🧪 Quick Test Commands

```bash
# Welcome message
curl http://localhost:8000/

# Health check
curl http://localhost:8000/health

# Stress test — 10 second CPU spike
curl "http://localhost:8000/stress?duration=10"

# Upload an image (replace path with an actual image)
curl -X POST "http://localhost:8000/upload" \
  -H "accept: application/json" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@sample.jpg"
```

---

## 🔒 Dockerfile Best Practices Applied

| Practice                     | Implementation                                               |
|------------------------------|--------------------------------------------------------------|
| **Lightweight base image**   | `python:3.9-slim` (~120 MB vs ~900 MB for full)              |
| **Build cache optimisation** | `requirements.txt` copied and installed before app code       |
| **Non-root user**            | `appuser` created and switched to before CMD                  |
| **No .pyc / bytecode**       | `PYTHONDONTWRITEBYTECODE=1`                                   |
| **Real-time logs**           | `PYTHONUNBUFFERED=1` for immediate container log output       |
| **Minimal apt packages**     | `--no-install-recommends` + cache cleanup                     |
| **Explicit port**            | `EXPOSE 8000`                                                 |

---

## 📋 Next Phases (Preview)

- **Phase 2:** CI/CD pipeline (GitHub Actions) with automated build, test, and push to ECR
- **Phase 3:** Infrastructure as Code (Terraform) — VPC, ECS Fargate, ALB, S3
- **Phase 4:** CloudWatch monitoring, autoscaling policies triggered by `/stress`
- **Phase 5:** Cost optimisation dashboards and alerting
