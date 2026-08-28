#!/usr/bin/env bash
set -euo pipefail
# Deprecated wrapper — kept for backward compatibility.
# New entry point is deploy.sh (sing-box-deploy).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "WARNING: deploy-anytls.sh is deprecated, please use deploy.sh (sing-box-deploy)" >&2
echo "         Forwarding to deploy.sh ..." >&2
exec bash "$SCRIPT_DIR/deploy.sh" "$@"
