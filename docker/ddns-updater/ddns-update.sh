#!/bin/bash

# --- Configuration ---
# **REPLACE THIS WITH YOUR UNIQUE CPANEL URL**
DDNS_URL="https://ejmedia.ca/cpanelwebcall/xxxxxx"
IP_FILE="/tmp/.last_public_ip" # Stores the last known IP inside the container
# ---------------------

CURRENT_IP=$(/usr/bin/curl -s https://v4.ident.me)

# Check if the IP file exists; if not, set LAST_IP to a value that forces an update
if [ -f "$IP_FILE" ]; then
    LAST_IP=$(cat "$IP_FILE")
else
    LAST_IP="0.0.0.0"
fi

# Compare the current IP with the last recorded IP
if [ "$CURRENT_IP" = "$LAST_IP" ]; then
    # Output is critical for confirming the loop is running
    echo "$(date): IP is $CURRENT_IP. No update needed."
    exit 0
else
    # IP has changed, run the update URL
    echo "$(date): IP changed from $LAST_IP to $CURRENT_IP. Running DDNS update..."

    # Call the cPanel Webcall URL
    /usr/bin/curl -sf "$DDNS_URL" > /dev/null 2>&1

    # Check if the curl command was successful (exit code 0)
    if [ $? -eq 0 ]; then
        echo "=========================================================="
        echo "$(date): SUCCESS! DDNS updated and IP recorded: $CURRENT_IP"
        echo "=========================================================="
        echo "$CURRENT_IP" > "$IP_FILE"
    else
        echo "$(date): DDNS update FAILED (curl error). Will retry in 30 minutes."
    fi
fi