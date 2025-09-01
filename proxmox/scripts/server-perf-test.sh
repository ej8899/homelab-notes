#!/usr/bin/env bash
# bench-one.sh — dead-simple local CPU check with raw outputs (no parsing)

set -euo pipefail
INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

# Optional install (Debian/Ubuntu/Proxmox only)
if [[ $INSTALL -eq 1 ]] && command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  apt-get install -y -qq openssl sysbench p7zip-full >/dev/null 2>&1 || true
fi

echo "=== HOST ==="
echo "hostname: $(hostname -f 2>/dev/null || hostname -s)"
echo "kernel:   $(uname -r)"
echo

echo "=== CPU INFO (lscpu) ==="
if command -v lscpu >/dev/null 2>&1; then
  lscpu | egrep 'Model name|CPU\(s\)|Core\(s\) per socket|Socket\(s\)|CPU MHz|CPU max MHz' || true
else
  echo "lscpu not found"
fi
echo

echo "=== OpenSSL version ==="
if command -v openssl >/dev/null 2>&1; then
  openssl version
else
  echo "openssl not found"
fi
echo

echo "=== OpenSSL speed: sha256 (5s) ==="
if command -v openssl >/dev/null 2>&1; then
  openssl speed -elapsed -seconds 5 sha256 || true
else
  echo "openssl not found"
fi
echo

echo "=== OpenSSL speed: AES-256-GCM EVP (5s) ==="
if command -v openssl >/dev/null 2>&1; then
  # Use EVP to exercise AES-NI/VAES if present
  OPENSSL_ia32cap=~0 openssl speed -elapsed -seconds 5 -multi "$(nproc 2>/dev/null || echo 1)" -evp aes-256-gcm || true
else
  echo "openssl not found"
fi
echo

echo "=== sysbench cpu (10s) ==="
if command -v sysbench >/dev/null 2>&1; then
  sysbench cpu --threads="$(nproc 2>/dev/null || echo 1)" --time=10 run || true
else
  echo "sysbench not found"
fi
echo

echo "=== 7z benchmark (if installed) ==="
if command -v 7z >/dev/null 2>&1; then
  7z b -mmt="$(nproc 2>/dev/null || echo 1)" || true
else
  echo "7z not found"
fi
echo
