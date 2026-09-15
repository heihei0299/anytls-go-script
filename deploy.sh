#!/usr/bin/env bash
set -euo pipefail

PORT=443
HY2_PORT=""
DRY_RUN=false
PADDING_SCHEME='["stop=8","0=30-30","1=100-400","2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000","3=9-9,500-1000","4=500-1000","5=500-1000","6=500-1000","7=500-1000"]'
ENABLE_ANYTLS=true
ENABLE_HY2=true
CUSTOM_NAME=""
CUSTOM_PASSWORD=""
CUSTOM_HY2_PASSWORD=""
RENEW_CERT=false

require_value() {
  if [[ $# -lt 2 ]]; then
    echo "Missing value for $1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|--anytls-port)
      require_value "$@"
      PORT="$2"; shift 2 ;;
    --hy2-port)
      require_value "$@"
      HY2_PORT="$2"; shift 2 ;;
    --padding-scheme)
      require_value "$@"
      PADDING_SCHEME="$2"; shift 2 ;;
    --name)
      require_value "$@"
      CUSTOM_NAME="$2"; shift 2 ;;
    --password)
      require_value "$@"
      CUSTOM_PASSWORD="$2"; shift 2 ;;
    --hy2-password)
      require_value "$@"
      CUSTOM_HY2_PASSWORD="$2"; shift 2 ;;
    --no-hy2|--without-hy2|--anytls-only)
      ENABLE_HY2=false; shift ;;
    --no-anytls|--without-anytls|--hy2-only)
      ENABLE_ANYTLS=false; shift ;;
    --renew-cert)
      RENEW_CERT=true; shift ;;
    --dry-run|--dry)
      DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: sudo $0 [options]"
      echo ""
      echo "  --port <port>         anytls listen port (default: 443, hy2 defaults to same)"
      echo "  --anytls-port <port>  alias for --port"
      echo "  --hy2-port <port>     hysteria2 listen port (default: same as --port)"
      echo "  --padding-scheme <json>  custom anytls padding scheme JSON"
      echo "  --name <name>         base node name (default: hostname)"
      echo "                        anytls: <name>, hy2: <name>-hy2"
      echo "  --password <pwd>      custom anytls password (default: random)"
      echo "  --hy2-password <pwd>  custom hy2 password (default: random, independent)"
      echo "  --no-hy2              disable hysteria2 (anytls only)"
      echo "  --no-anytls           disable anytls (hy2 only)"
      echo "  --anytls-only         alias for --no-hy2"
      echo "  --hy2-only            alias for --no-anytls"
      echo "  --renew-cert          regenerate the self-signed TLS certificate"
      echo "  --dry-run, --dry      preview without executing"
      echo "  --help, -h            show this help"
      exit 0 ;;
    *)
      echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

if ! $DRY_RUN && [[ $EUID -ne 0 ]]; then
  echo "Run with sudo" >&2; exit 1
fi

# hy2 defaults to same port as anytls
if [[ -z "$HY2_PORT" ]]; then
  HY2_PORT="$PORT"
fi

if ! $ENABLE_ANYTLS && ! $ENABLE_HY2; then
  echo "Error: at least one of anytls/hy2 must be enabled" >&2; exit 1
fi

if $ENABLE_ANYTLS; then
  if ! [[ $PORT =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
    echo "Invalid port: $PORT" >&2; exit 1
  fi
fi
if $ENABLE_HY2; then
  if ! [[ $HY2_PORT =~ ^[0-9]+$ ]] || (( HY2_PORT < 1 || HY2_PORT > 65535 )); then
    echo "Invalid hy2 port: $HY2_PORT" >&2; exit 1
  fi
fi

# --- hostname -> base name ---
get_base_name() {
  local raw=""
  local h=""
  if [[ -n "$CUSTOM_NAME" ]]; then
    raw="$CUSTOM_NAME"
    h=$(echo "$raw" | tr -d '\r\n' | xargs 2>/dev/null || echo "$raw")
    if [[ -n "$h" ]]; then
      # take first label before dot for consistency
      h=$(echo "$h" | awk -F. '{print $1}' 2>/dev/null || echo "$h")
      h=$(echo "$h" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    fi
    if [[ -z "$h" ]]; then
      h="sing-box"
    fi
    echo "$h"
    return
  fi
  h=""
  if command -v hostname &>/dev/null; then
    h=$(hostname 2>/dev/null | tr -d '\n' || true)
    if [[ -z "$h" ]]; then
      h=$(hostname -s 2>/dev/null | tr -d '\n' || true)
    fi
  fi
  if [[ -z "$h" && -f /proc/sys/kernel/hostname ]]; then
    h=$(tr -d '\n\r' < /proc/sys/kernel/hostname 2>/dev/null || true)
  fi
  if [[ -z "$h" && -f /etc/hostname ]]; then
    h=$(tr -d '\n\r' < /etc/hostname 2>/dev/null | head -n1 || true)
  fi
  if [[ -z "$h" && -n "${HOSTNAME:-}" ]]; then
    h="$HOSTNAME"
  fi
  # take short name before dot, trim
  h=$(echo "$h" | awk -F. '{print $1}' 2>/dev/null || echo "$h")
  h=$(echo "$h" | tr -d '\r\n' | xargs 2>/dev/null || echo "$h")
  if [[ -z "$h" ]]; then
    h="sing-box"
  fi
  # sanitize: keep alnum, -, _, replace others with -
  h=$(echo "$h" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  if [[ -z "$h" ]]; then
    h="sing-box"
  fi
  echo "$h"
}

BASE_NAME=$(get_base_name)
ANYTLS_NAME="$BASE_NAME"
ANYTLS_IPV6_NAME="${BASE_NAME}-ipv6"
HY2_NAME="${BASE_NAME}-hy2"
HY2_IPV6_NAME="${BASE_NAME}-hy2-ipv6"

echo "[1/6] Checking dependencies..."
DEPS=(openssl curl jq)
MISSING=()
for cmd in "${DEPS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  if $DRY_RUN; then
    echo "  [dry-run] would install: ${MISSING[*]}"
  else
    echo "  installing: ${MISSING[*]}"
    apt-get update
    apt-get install -y "${MISSING[@]}"
  fi
else
  echo "  all ok"
fi

if [[ -n "$CUSTOM_PASSWORD" ]]; then
  PASSWORD="$CUSTOM_PASSWORD"
elif $DRY_RUN; then
  PASSWORD="<generated-at-runtime>"
else
  PASSWORD=$(openssl rand -base64 16)
fi
if [[ -n "$CUSTOM_HY2_PASSWORD" ]]; then
  HY2_PASSWORD="$CUSTOM_HY2_PASSWORD"
elif $DRY_RUN; then
  HY2_PASSWORD="<generated-at-runtime>"
else
  HY2_PASSWORD=$(openssl rand -base64 16)
fi

echo "[2/6] Installing sing-box..."
if command -v sing-box &>/dev/null; then
  echo "  already installed"
elif $DRY_RUN; then
  echo "  [dry-run] would configure apt repo and install sing-box:"
  echo "  [dry-run]   curl -fsSL --connect-timeout 10 --max-time 60 https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc"
  echo "  [dry-run]   write /etc/apt/sources.list.d/sagernet.sources"
  echo "  [dry-run]   apt-get update && apt-get install -y sing-box"
else
  mkdir -p /etc/apt/keyrings
  curl -fsSL --connect-timeout 10 --max-time 60 https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
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

echo "[3/6] Checking TLS cert..."
CERT_DIR=/etc/sing-box
CONFIG_FILE="$CERT_DIR/config.json"
if [[ -f "$CERT_DIR/key.pem" && -f "$CERT_DIR/cert.pem" && "$RENEW_CERT" == false ]]; then
  echo "  existing TLS certificate found; reusing"
elif $DRY_RUN; then
  echo "  [dry-run] would generate TLS certificate in $CERT_DIR"
  echo "  [dry-run] mkdir -p $CERT_DIR"
  echo "  [dry-run] openssl ecparam -genkey -name prime256v1 -out $CERT_DIR/key.pem"
  echo "  [dry-run] openssl req -x509 -days 36500 -key $CERT_DIR/key.pem -out $CERT_DIR/cert.pem -subj /CN=anytls-server"
else
  mkdir -p "$CERT_DIR"
  (
    umask 077
    openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/key.pem"
    openssl req -x509 -days 36500 -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
      -subj "/CN=anytls-server"
  )
fi
if ! $DRY_RUN; then
  SERVICE_GROUP=$(id -gn sing-box 2>/dev/null || true)
  if [[ -n "$SERVICE_GROUP" ]]; then
    chgrp "$SERVICE_GROUP" "$CERT_DIR/key.pem"
    chmod 640 "$CERT_DIR/key.pem"
  else
    chmod 600 "$CERT_DIR/key.pem"
  fi
  chmod 644 "$CERT_DIR/cert.pem"
fi

echo "[4/6] Writing sing-box config..."

ANYTLS_INBOUND=""
HY2_INBOUND=""

json_quote() {
  if command -v jq &>/dev/null; then
    jq -rn --arg value "$1" '$value | @json'
    return
  fi

  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  value=${value//$'\b'/\\b}
  value=${value//$'\f'/\\f}
  printf '"%s"' "$value"
}

if command -v jq &>/dev/null; then
  if $ENABLE_ANYTLS; then
    if ! ANYTLS_INBOUND=$(jq -n \
      --arg password "$PASSWORD" \
      --arg cert "$CERT_DIR/cert.pem" \
      --arg key "$CERT_DIR/key.pem" \
      --argjson port "$PORT" \
      --argjson padding "$PADDING_SCHEME" \
      '{
        "type": "anytls",
        "tag": "anytls-in",
        "listen": "::",
        "listen_port": $port,
        "users": [{ "name": "user1", "password": $password }],
        "padding_scheme": $padding,
        "tls": {
          "enabled": true,
          "certificate_path": $cert,
          "key_path": $key
        }
      }'); then
      echo "Error: --padding-scheme must be valid JSON" >&2
      exit 1
    fi
  fi

  if $ENABLE_HY2; then
    HY2_INBOUND=$(jq -n \
      --arg password "$HY2_PASSWORD" \
      --arg cert "$CERT_DIR/cert.pem" \
      --arg key "$CERT_DIR/key.pem" \
      --argjson port "$HY2_PORT" \
      '{
        "type": "hysteria2",
        "tag": "hy2-in",
        "listen": "::",
        "listen_port": $port,
        "users": [{ "name": "user1", "password": $password }],
        "tls": {
          "enabled": true,
          "certificate_path": $cert,
          "key_path": $key
        }
      }')
  fi
elif $DRY_RUN; then
  if $ENABLE_ANYTLS; then
    ANYTLS_INBOUND=$(cat <<JSON
{
  "type": "anytls",
  "tag": "anytls-in",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    { "name": "user1", "password": $(json_quote "$PASSWORD") }
  ],
  "padding_scheme": $PADDING_SCHEME,
  "tls": {
    "enabled": true,
    "certificate_path": $(json_quote "$CERT_DIR/cert.pem"),
    "key_path": $(json_quote "$CERT_DIR/key.pem")
  }
}
JSON
)
  fi
  if $ENABLE_HY2; then
    HY2_INBOUND=$(cat <<JSON
{
  "type": "hysteria2",
  "tag": "hy2-in",
  "listen": "::",
  "listen_port": $HY2_PORT,
  "users": [
    { "name": "user1", "password": $(json_quote "$HY2_PASSWORD") }
  ],
  "tls": {
    "enabled": true,
    "certificate_path": $(json_quote "$CERT_DIR/cert.pem"),
    "key_path": $(json_quote "$CERT_DIR/key.pem")
  }
}
JSON
)
  fi
else
  echo "Error: jq is required but not installed" >&2
  exit 1
fi

# Build inbounds array for jq (with fallback for dry-run without jq)
INBOUNDS_JSON="[]"
if command -v jq &>/dev/null; then
  if $ENABLE_ANYTLS && $ENABLE_HY2; then
    INBOUNDS_JSON=$(jq -n --argjson a "$ANYTLS_INBOUND" --argjson b "$HY2_INBOUND" '[$a, $b]')
  elif $ENABLE_ANYTLS; then
    INBOUNDS_JSON=$(jq -n --argjson a "$ANYTLS_INBOUND" '[$a]')
  elif $ENABLE_HY2; then
    INBOUNDS_JSON=$(jq -n --argjson b "$HY2_INBOUND" '[$b]')
  fi
else
  if $DRY_RUN; then
    if $ENABLE_ANYTLS && $ENABLE_HY2; then
      INBOUNDS_JSON="[$ANYTLS_INBOUND,$HY2_INBOUND]"
    elif $ENABLE_ANYTLS; then
      INBOUNDS_JSON="[$ANYTLS_INBOUND]"
    elif $ENABLE_HY2; then
      INBOUNDS_JSON="[$HY2_INBOUND]"
    fi
  else
    echo "Error: jq is required but not installed" >&2
    exit 1
  fi
fi

if $DRY_RUN; then
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "  [dry-run] would merge inbounds into existing config (tags: anytls-in, hy2-in)"
    echo "  [dry-run] inbounds to be ensured:"
    if command -v jq &>/dev/null; then
      echo "$INBOUNDS_JSON" | jq .
    else
      echo "$INBOUNDS_JSON"
    fi
  else
    echo "  [dry-run] would write new config to $CERT_DIR/config.json:"
    if command -v jq &>/dev/null; then
      echo "$INBOUNDS_JSON" | jq .
    else
      echo "$INBOUNDS_JSON"
    fi
  fi
else
  if [[ -f "$CONFIG_FILE" ]]; then
    jq --argjson inbounds "$INBOUNDS_JSON" \
      '.inbounds = [(.inbounds // [])[] | select(.tag != "anytls-in" and .tag != "hy2-in")] + $inbounds' \
      "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
    cp -p "$CONFIG_FILE" "$CONFIG_FILE.bak"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    jq -n --argjson inbounds "$INBOUNDS_JSON" \
      '{ "log": { "level": "info" }, "inbounds": $inbounds }' > "$CONFIG_FILE"
  fi

  echo "[5/6] Starting sing-box service..."
  systemctl enable sing-box
  systemctl restart sing-box
fi

# For dry-run, also print [5/6] step
if $DRY_RUN; then
  echo "[5/6] Starting sing-box service..."
  echo "  [dry-run] systemctl enable sing-box && systemctl restart sing-box"
fi

echo "[6/6] Detecting server IP..."
if $DRY_RUN; then
  IPV4="x.x.x.x"
  IPV6="::1"
else
  IPV4=$(curl -fs4 --connect-timeout 5 --max-time 10 ifconfig.me 2>/dev/null || echo "")
  IPV6=$(curl -fs6 --connect-timeout 5 --max-time 10 ifconfig.me 2>/dev/null || echo "")
fi

if [[ -z "$IPV4" && -z "$IPV6" ]]; then
  IPV4="unknown"
  echo "Warning: failed to detect any public IP; using unknown" >&2
fi

if $DRY_RUN; then
  echo ""
  echo "  Base name:   $BASE_NAME"
  if $ENABLE_ANYTLS; then
    echo "  AnyTLS:      $ANYTLS_NAME / $ANYTLS_IPV6_NAME  port $PORT  password $PASSWORD"
  else
    echo "  AnyTLS:      disabled"
  fi
  if $ENABLE_HY2; then
    echo "  Hy2:         $HY2_NAME / $HY2_IPV6_NAME  port $HY2_PORT  password $HY2_PASSWORD"
  else
    echo "  Hy2:         disabled"
  fi
  echo "  IPv4:        $IPV4 (placeholder)"
  echo "  IPv6:        $IPV6 (placeholder)"
  echo ""
  echo "  [dry-run] would save Mihomo config to: $(pwd)/mihomo.yaml (compat: mihomo-anytls.yaml)"
  echo ""
fi

yaml_quote() {
  json_quote "$1"
}

OUTPUT_FILE="mihomo.yaml"
render_proxy() {
  local server="$1"
  local anytls_name="$2"
  local hy2_name="$3"

  if $ENABLE_ANYTLS; then
    echo "  - name: $anytls_name"
    echo "    type: anytls"
    echo "    server: $server"
    echo "    port: $PORT"
    echo "    password: $(yaml_quote "$PASSWORD")"
    echo "    client-fingerprint: chrome"
    echo "    udp: false"
    echo "    skip-cert-verify: true"
  fi
  if $ENABLE_HY2; then
    echo "  - name: $hy2_name"
    echo "    type: hysteria2"
    echo "    server: $server"
    echo "    port: $HY2_PORT"
    echo "    password: $(yaml_quote "$HY2_PASSWORD")"
    echo "    sni: $server"
    echo "    skip-cert-verify: true"
    echo "    alpn:"
    echo "      - h3"
  fi
}

render_mihomo_config() {
  echo "proxies:"
  if [[ -n "$IPV4" ]]; then
    render_proxy "$IPV4" "$ANYTLS_NAME" "$HY2_NAME"
  fi
  if [[ -n "$IPV6" ]]; then
    render_proxy "$IPV6" "$ANYTLS_IPV6_NAME" "$HY2_IPV6_NAME"
  fi
}
if $DRY_RUN; then
  echo "  [dry-run] Mihomo config preview:"
  render_mihomo_config
else
  render_mihomo_config > "$OUTPUT_FILE"
fi

# compat symlink/copy for old path
if ! $DRY_RUN && [[ "$OUTPUT_FILE" != "mihomo-anytls.yaml" ]]; then
  cp -f "$OUTPUT_FILE" mihomo-anytls.yaml 2>/dev/null || true
fi

if ! $DRY_RUN; then
  cat "$OUTPUT_FILE"
fi
