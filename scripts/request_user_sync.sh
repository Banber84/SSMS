#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/etc/ssms/sync.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/configs/sync.conf"
fi

usage() {
  cat <<'EOF'
用法：
  scripts/request_user_sync.sh USERNAME [--quota-gb GB] [--storage HOST] [--storage-user USER] [--storage-project DIR]

在 NodeA/NodeB 上发起用户同步请求。
脚本会通过 SSH 调用 Storage Server 上的 scripts/sync_user.sh，再由 Storage Server 同步到三方。

示例：
  scripts/request_user_sync.sh alice --quota-gb 1
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "缺少同步配置文件：$CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

USERNAME="$1"
shift
QUOTA_GB="${DEFAULT_SYNC_QUOTA_GB:-1}"
STORAGE_HOST="${STORAGE_SYNC_HOST:-}"
STORAGE_USER="${STORAGE_SYNC_USER:-}"
STORAGE_PROJECT_DIR="${STORAGE_SYNC_PROJECT_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quota-gb)
      QUOTA_GB="$2"
      shift 2
      ;;
    --storage)
      STORAGE_HOST="$2"
      shift 2
      ;;
    --storage-user)
      STORAGE_USER="$2"
      shift 2
      ;;
    --storage-project)
      STORAGE_PROJECT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "用户名非法：$USERNAME"
  exit 1
fi

if ! [[ "$QUOTA_GB" =~ ^[0-9]+$ ]] || [[ "$QUOTA_GB" -le 0 ]]; then
  echo "配额必须是正整数，单位为 GB。"
  exit 1
fi

if [[ -z "$STORAGE_HOST" || -z "$STORAGE_USER" || -z "$STORAGE_PROJECT_DIR" ]]; then
  echo "Storage Server 连接配置不完整，请检查 $CONFIG_FILE。"
  exit 1
fi

read -r -s -p "请输入 $USERNAME 的统一密码：" PASSWORD
echo
read -r -s -p "请再次输入密码：" PASSWORD_CONFIRM
echo

if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
  echo "两次输入的密码不一致。"
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  echo "密码不能为空。"
  exit 1
fi

REMOTE_SCRIPT="$STORAGE_PROJECT_DIR/scripts/sync_user.sh"
printf -v REMOTE_SCRIPT_Q '%q' "$REMOTE_SCRIPT"
printf -v USERNAME_Q '%q' "$USERNAME"

echo "向 Storage Server 发起用户同步：$STORAGE_USER@$STORAGE_HOST"
printf '%s\n' "$PASSWORD" | ssh "$STORAGE_USER@$STORAGE_HOST" \
  "sudo $REMOTE_SCRIPT_Q $USERNAME_Q --quota-gb $QUOTA_GB --password-stdin"

echo "节点发起的用户同步完成：$USERNAME"
