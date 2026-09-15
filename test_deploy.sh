#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR=$(mktemp -d)
NO_JQ_BIN=$(mktemp -d)
trap 'rm -rf "$WORK_DIR" "$NO_JQ_BIN"' EXIT

OUTPUT=$(cd "$WORK_DIR" && bash "$ROOT_DIR/deploy.sh" \
  --dry-run \
  --port 8443 \
  --hy2-port 9443 \
  --password plain-password \
  --hy2-password hy2-password)

[[ ! -e "$WORK_DIR/mihomo.yaml" ]]
[[ ! -e "$WORK_DIR/mihomo-anytls.yaml" ]]
[[ "$OUTPUT" == *"port 8443"* ]]
[[ "$OUTPUT" == *"port 9443"* ]]
[[ "$OUTPUT" == *"would save Mihomo config to: $WORK_DIR/mihomo.yaml"* ]]

SPECIAL_OUTPUT=$(cd "$WORK_DIR" && bash "$ROOT_DIR/deploy.sh" \
  --dry-run \
  --password 'a"b\c' \
  --hy2-password 'h"y\z')

EXPECTED_PASSWORD=$(jq -rn --arg value 'a"b\c' '$value | @json')
printf '%s\n' "$SPECIAL_OUTPUT" | rg -qF "\"password\": $EXPECTED_PASSWORD"
printf '%s\n' "$SPECIAL_OUTPUT" | rg -qF "password: $EXPECTED_PASSWORD"

if (cd "$WORK_DIR" && bash "$ROOT_DIR/deploy.sh" --dry-run --padding-scheme not-json) >"$WORK_DIR/invalid-padding.out" 2>&1; then
  exit 1
fi
rg -qF -- '--padding-scheme must be valid JSON' "$WORK_DIR/invalid-padding.out"

for command_name in openssl curl cat tr awk sed xargs; do
  ln -s "$(command -v "$command_name")" "$NO_JQ_BIN/$command_name"
done
NO_JQ_OUTPUT=$(cd "$WORK_DIR" && PATH="$NO_JQ_BIN" /bin/bash "$ROOT_DIR/deploy.sh" \
  --dry-run \
  --port 8443 \
  --hy2-port 9443 \
  --password 'a"b\c' \
  --hy2-password hy2-password)
EXPECTED_NO_JQ_PASSWORD=$(jq -rn --arg value 'a"b\c' '$value | @json')
printf '%s\n' "$NO_JQ_OUTPUT" | rg -qF '"listen_port": 8443'
printf '%s\n' "$NO_JQ_OUTPUT" | rg -qF "password: $EXPECTED_NO_JQ_PASSWORD"

RENEW_OUTPUT=$(cd "$WORK_DIR" && bash "$ROOT_DIR/deploy.sh" --dry-run --renew-cert)
[[ "$RENEW_OUTPUT" == *"would generate TLS certificate"* ]]

printf '%s\n' 'dry-run CLI check passed'
