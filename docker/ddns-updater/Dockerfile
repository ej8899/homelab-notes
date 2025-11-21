FROM alpine:3.18

# Installs
RUN apk add --no-cache curl bash

# Copy the script and make it executable
COPY ddns_update.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ddns_update.sh

# runs in infinite loop to execute every 30 minutes (1800s)
# Runs in the foreground, guaranteeing log visibility in Portainer.
CMD while true; do /usr/local/bin/ddns_update.sh; sleep 1800; done