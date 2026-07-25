#!/usr/bin/env bash
set -euo pipefail

PORT=443
DRY_RUN=false
PADDING_SCHEME='["stop=8","0=30-30","1=100-400","2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000","3=9-9,500-1000","4=500-1000","5=500-1000","6=500-1000","7=500-1000"]'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"; shift 2 ;;
    --padding-scheme)
      PADDING_SCHEME="$2"; shift 2 ;;
    --dry-run|--dry)
      DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: sudo $0 [--port <port>] [--padding-scheme <json>] [--dry-run]"
      echo ""
      echo "  --port              Listen port (default: 443)"
      echo "  --padding-scheme    Custom padding scheme JSON (default: standard)"
      echo "  --dry-run, --dry    Print what would be done without executing"
      echo "  --help, -h          Show this help"
      exit 0 ;;
    *)
      echo "Unknown: $1"; exit 1 ;;
  esac
done

if ! $DRY_RUN && [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2; exit 1
fi

if ! [[ $PORT =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Invalid port: $PORT" >&2; exit 1
fi

PASSWORD=$(openssl rand -base64 16)

dry() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "[1/5] Installing sing-box..."
if command -v sing-box &>/dev/null; then
  echo "  already installed"
elif $DRY_RUN; then
  echo "  [dry-run] would configure apt repo and install sing-box:"
  echo "  [dry-run]   curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc"
  echo "  [dry-run]   write /etc/apt/sources.list.d/sagernet.sources"
  echo "  [dry-run]   apt-get update && apt-get install -y sing-box"
else
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  chmod a+r /etc/apt/keyrings/sagernet.asc
  cat > /etc/apt/sources.list.d/sagernet.sources <<APT
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
APT
  apt-get update
  apt-get install -y sing-box
fi

echo "[2/5] Generating self-signed TLS cert..."
CERT_DIR=/etc/sing-box
if $DRY_RUN; then
  echo "  [dry-run] mkdir -p $CERT_DIR"
  echo "  [dry-run] openssl ecparam -genkey -name prime256v1 -out $CERT_DIR/key.pem"
  echo "  [dry-run] openssl req -x509 -days 36500 -key $CERT_DIR/key.pem -out $CERT_DIR/cert.pem -subj /CN=anytls-server"
else
  mkdir -p "$CERT_DIR"
  openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/key.pem"
  openssl req -x509 -days 36500 -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
    -subj "/CN=anytls-server"
fi

echo "[3/5] Writing sing-box config..."
if $DRY_RUN; then
  echo "  [dry-run] would write to $CERT_DIR/config.json:"
else
  cat > /etc/sing-box/config.json <<JSON
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        { "name": "user1", "password": "$PASSWORD" }
      ],
      "padding_scheme": $PADDING_SCHEME,
      "tls": {
        "enabled": true,
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/key.pem"
      }
    }
  ]
}
JSON

  echo "[4/5] Starting sing-box service..."
  systemctl enable sing-box
  systemctl restart sing-box
fi

echo "[5/5] Detecting server IP..."
if $DRY_RUN; then
  SERVER_IP="x.x.x.x"
else
  SERVER_IP=$(curl -fs4 ifconfig.me 2>/dev/null || curl -fs6 ifconfig.me 2>/dev/null || echo "unknown")
fi

if $DRY_RUN; then
  echo ""
  echo "  Password:    $PASSWORD"
  echo "  Port:        $PORT"
  echo "  Server IP:   $SERVER_IP (placeholder)"
  echo ""
  echo "  Mihomo config would be saved to: $(pwd)/mihomo-anytls.yaml"
  echo ""
fi

cat > mihomo-anytls.yaml <<YAML
proxies:
  - name: anytls
    type: anytls
    server: $SERVER_IP
    port: $PORT
    password: "$PASSWORD"
    client-fingerprint: chrome
    udp: false
    skip-cert-verify: true
YAML

cat mihomo-anytls.yaml
