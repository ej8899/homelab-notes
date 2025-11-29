# SnowCam Uploader

## Overview

**SnowCam Uploader** captures a single frame from an **RTSP camera feed** at scheduled intervals and uploads it to a remote HTTP endpoint.

This allows any external system (weather alerting, dashboards, email notifications, etc.) to include a **recent snapshot** without exposing the camera or RTSP stream to the Internet.

The Docker container performs:

1. Capture a frame from an RTSP stream using `ffmpeg`
2. (Optional) resize the frame for email/web delivery
3. Upload the frame to your chosen HTTPS endpoint via `curl`
4. Repeat forever at a configurable interval

---

## Why Use This

- **Keeps cameras private** — no inbound exposure of RTSP
- **Works with any IP camera** that supports RTSP
- **Integrates cleanly** with alerting/email workflows
- **Lightweight** — no video recording stack, just snapshots
- **Dockerized** — portable, minimal setup

---

## Requirements

### On the Host Machine

- Docker installed
- Network access to:
  - The RTSP stream of the camera
  - The HTTP/HTTPS endpoint that receives uploads

### Inside the Container

Already provided:

- `ffmpeg`
- `curl`
- `bash`
- `ca-certificates`

No extra libraries are needed.

---

## Environment Variables

| Variable           | Required | Description                                          |
|-------------------|:--------:|------------------------------------------------------|
| `RTSP_URL`        |   ✔      | Full RTSP stream URL for the camera                 |
| `UPLOAD_URL`      |   ✔      | HTTP/HTTPS endpoint that accepts the image upload   |
| `API_SECRET`      |   ✔      | Shared secret sent with each POST                   |
| `INTERVAL_SECONDS`|   ✖      | Seconds between snapshots (default: 600 / 10 mins)  |
| `SNAPSHOT_FILE`   |   ✖      | Path used inside container (default: /tmp/snap.jpg) |

---

## Running the Container

Replace placeholder values with your own:

```bash
docker run -d \
  --name snowcam-uploader \
  -e RTSP_URL="rtsp://user:pass@192.168.1.25:554/cam/stream" \
  -e UPLOAD_URL="https://yourserver.com/snowcam-endpoint.php" \
  -e API_SECRET="YOUR_SHARED_SECRET" \
  -e INTERVAL_SECONDS=900 \
  snowcam-uploader
