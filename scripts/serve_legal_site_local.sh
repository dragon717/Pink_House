#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SITE_DIR="${SITE_DIR:-${REPO_ROOT}/ops/legal-site}"
PORT="${PORT:-8787}"

if [[ ! -d "${SITE_DIR}" ]]; then
  echo "网站目录不存在: ${SITE_DIR}" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "未找到 python3，请先安装 Python 3" >&2
  exit 1
fi

echo "启动本地站点: ${SITE_DIR}"
echo "访问地址: http://127.0.0.1:${PORT}/"
echo "停止服务: Ctrl+C"

cd "${SITE_DIR}"
exec python3 -m http.server "${PORT}"
