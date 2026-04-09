#!/usr/bin/env bash
set -euo pipefail

DEPLOY_HOST="${DEPLOY_HOST:-root@146.56.207.253}"

if [[ $# -eq 0 ]]; then
  exec ssh "${DEPLOY_HOST}"
else
  exec ssh "${DEPLOY_HOST}" "$@"
fi
