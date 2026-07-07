#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SITE_SRC="${SITE_SRC:-${REPO_ROOT}/ops/legal-site}"
DEPLOY_HOST="${DEPLOY_HOST:-sangsang-prod}"
REMOTE_SITE_ROOT="${REMOTE_SITE_ROOT:-/var/www/sangsang.online}"
DOMAIN_PRIMARY="${DOMAIN_PRIMARY:-sangsang.online}"
DOMAIN_WWW="${DOMAIN_WWW:-www.sangsang.online}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1" >&2
    exit 1
  fi
}

require_cmd ssh
require_cmd rsync
require_cmd curl

if [[ ! -d "${SITE_SRC}" ]]; then
  echo "网站源目录不存在: ${SITE_SRC}" >&2
  exit 1
fi

REMOTE_TMP="/tmp/legal-site-deploy-$(date +%s)"
REMOTE_BACKUP="${REMOTE_SITE_ROOT}.bak.$(date +%Y%m%d-%H%M%S)"

echo "==> 部署目标: ${DEPLOY_HOST}:${REMOTE_SITE_ROOT}"
echo "==> 本地源目录: ${SITE_SRC}"

echo "==> [1/5] 创建远端临时目录"
ssh "${DEPLOY_HOST}" "mkdir -p '${REMOTE_TMP}'"

echo "==> [2/5] 同步文件到远端临时目录"
rsync -az --delete "${SITE_SRC}/" "${DEPLOY_HOST}:${REMOTE_TMP}/"

echo "==> [3/5] 远端发布 + 备份 + reload nginx"
ssh "${DEPLOY_HOST}" "bash -lc '
set -euo pipefail
if [[ -d \"${REMOTE_SITE_ROOT}\" ]]; then
  cp -a \"${REMOTE_SITE_ROOT}\" \"${REMOTE_BACKUP}\"
fi
rsync -a --delete \"${REMOTE_TMP}/\" \"${REMOTE_SITE_ROOT}/\"
nginx -t
systemctl reload nginx
rm -rf \"${REMOTE_TMP}\"
echo \"备份目录: ${REMOTE_BACKUP}\"
'"

echo "==> [4/5] 远端本机健康检查"
ssh "${DEPLOY_HOST}" "bash -lc '
set -euo pipefail
curl -fsSIL \"http://127.0.0.1/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/privacy/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/user-agreement/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/vip-agreement/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/contact/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/en/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/en/privacy/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/en/user-agreement/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/en/vip-agreement/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
curl -fsSIL \"http://127.0.0.1/en/contact/\" -H \"Host: ${DOMAIN_PRIMARY}\" >/dev/null
'"

echo "==> [5/5] 公网 HTTPS 健康检查"
curl -fsSIL "https://${DOMAIN_PRIMARY}/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/privacy/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/user-agreement/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/vip-agreement/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/contact/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/en/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/en/privacy/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/en/user-agreement/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/en/vip-agreement/" >/dev/null
curl -fsSIL "https://${DOMAIN_PRIMARY}/en/contact/" >/dev/null
curl -fsSIL "https://${DOMAIN_WWW}/" >/dev/null

echo "✅ 部署完成"
echo "   - https://${DOMAIN_PRIMARY}/"
echo "   - https://${DOMAIN_PRIMARY}/privacy/"
echo "   - https://${DOMAIN_PRIMARY}/user-agreement/"
echo "   - https://${DOMAIN_PRIMARY}/vip-agreement/"
echo "   - https://${DOMAIN_PRIMARY}/contact/"
echo "   - https://${DOMAIN_PRIMARY}/en/"
echo "   - https://${DOMAIN_PRIMARY}/en/privacy/"
echo "   - https://${DOMAIN_PRIMARY}/en/user-agreement/"
echo "   - https://${DOMAIN_PRIMARY}/en/vip-agreement/"
echo "   - https://${DOMAIN_PRIMARY}/en/contact/"
