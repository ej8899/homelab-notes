FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY capture_and_upload.sh /app/capture_and_upload.sh

RUN chmod +x /app/capture_and_upload.sh

ENV INTERVAL_SECONDS=600

CMD ["/app/capture_and_upload.sh"]