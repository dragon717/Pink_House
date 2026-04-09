#!/usr/bin/env bash
set -euo pipefail

HOST_ALIAS="${HOST_ALIAS:-sangsang-prod}"
HOST_NAME="${HOST_NAME:-146.56.207.253}"
HOST_USER="${HOST_USER:-root}"

# 如果你有专用私钥，可通过环境变量指定：
# IDENTITY_FILE=~/.ssh/your_private_key ./scripts/setup_sangsang_ssh.sh
IDENTITY_FILE="${IDENTITY_FILE:-}"

SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
BEGIN_MARK="# >>> pink-house ${HOST_ALIAS} >>>"
END_MARK="# <<< pink-house ${HOST_ALIAS} <<<"

mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
touch "${SSH_CONFIG}"
chmod 600 "${SSH_CONFIG}"

TMP_FILE="$(mktemp)"

# 先移除旧块，保证幂等
awk -v b="${BEGIN_MARK}" -v e="${END_MARK}" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}
' "${SSH_CONFIG}" > "${TMP_FILE}"

{
  cat "${TMP_FILE}"
  echo
  echo "${BEGIN_MARK}"
  echo "Host ${HOST_ALIAS}"
  echo "  HostName ${HOST_NAME}"
  echo "  User ${HOST_USER}"
  if [[ -n "${IDENTITY_FILE}" ]]; then
    echo "  IdentityFile ${IDENTITY_FILE}"
  fi
  cat <<'EOF'
  ServerAliveInterval 30
  ServerAliveCountMax 6
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
EOF
  echo "${END_MARK}"
} > "${SSH_CONFIG}"

rm -f "${TMP_FILE}"

echo "✅ 已写入 SSH 配置别名: ${HOST_ALIAS}"
echo "   配置文件: ${SSH_CONFIG}"
echo
echo "下一步建议："
echo "1) 测试连接: ssh ${HOST_ALIAS} \"hostname && date\""
echo "2) 一键发布: ./scripts/deploy_legal_site.sh"
