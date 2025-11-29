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

- **Keeps cameras private** — RTSP remains on the LAN
- **Works with any IP camera** that exposes RTSP
- **Integrates easily** with alerting/email workflows
- **Lightweight** — no video storage, just snapshots
- **Portable** — Docker-based, runs anywhere

---

## Requirements

### On the Host Machine

- Docker installed
- Network access to:
  - The RTSP stream of the camera
  - The HTTP/HTTPS endpoint receiving uploads

### Inside the Container

The image already includes:

- `ffmpeg`
- `bash`
- `curl`
- `ca-certificates`

No external dependencies required.

---

## Environment Variables

| Variable            | Required | Description                                            |
|---------------------|:--------:|--------------------------------------------------------|
| `RTSP_URL`          |   ✔      | RTSP URL for the camera                                |
| `UPLOAD_URL`        |   ✔      | Endpoint that accepts the image upload                 |
| `API_SECRET`        |   ✔      | Shared secret included with upload requests            |
| `INTERVAL_SECONDS`  |   ✖      | Snapshot interval in seconds (default: 600 = 10 mins)  |
| `SNAPSHOT_FILE`     |   ✖      | Temporary path used for capture (default: /tmp/snap.jpg)|

---

## Running the Container

Replace placeholders with real values:

```bash
docker run -d \
  --name snowcam-uploader \
  -e RTSP_URL="rtsp://user:pass@192.168.1.25:554/cam/stream" \
  -e UPLOAD_URL="https://yourserver.com/snowcam-endpoint.php" \
  -e API_SECRET="YOUR_SHARED_SECRET" \
  -e INTERVAL_SECONDS=900 \
  snowcam-uploader
```

### Notes

- `-d` runs the container in detached/background mode
- The RTSP URL **must** be reachable from the Docker host
- The endpoint must accept:
  - `POST multipart/form-data`
  - Field `snapshot` containing JPEG data
  - Field `api_secret` matching your configured secret

---

## Stopping & Removing the Container

```bash
docker stop snowcam-uploader
docker rm snowcam-uploader
```

---

## Checking Logs

```bash
docker logs -f snowcam-uploader
```

Expected output:

```
[snowcam] Starting capture loop. Interval=900s
[snowcam] 2025-12-01T06:00:01 - Captured frame
[snowcam] 2025-12-01T06:00:02 - Upload OK (HTTP 200)
```

---

## Use Case Example

A server-side alert system sends weather or site-condition notifications.  
Including a **fresh on-site image** makes those alerts actionable without exposing camera access externally.

This uploader enables that workflow securely.

---

## Quick Setup Checklist

✔ Camera supports RTSP  
✔ Docker host can reach the camera stream  
✔ Upload endpoint accepts JPEG + secret  
✔ API secret matches client + server  
✔ Container is running with correct variables  

---

## License

You are free to use and modify this tool as needed.
