#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：
  sudo scripts/create_node_user.sh USERNAME [--password-stdin]

在 Node01/Node02 上创建 Linux 登录用户。
请使用与 Storage Server 上 Samba 用户一致的密码。
使用 --password-stdin 时，从标准输入读取一行密码，适合同步脚本远程调用。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

USERNAME="$1"
shift
PASSWORD_STDIN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --password-stdin)
      PASSWORD_STDIN="1"
      shift
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

if [[ "$PASSWORD_STDIN" == "1" ]]; then
  IFS= read -r PASSWORD
  if [[ -z "$PASSWORD" ]]; then
    echo "密码不能为空。"
    exit 1
  fi
fi

if id "$USERNAME" >/dev/null 2>&1; then
  usermod --shell /bin/bash "$USERNAME"
  if [[ "$PASSWORD_STDIN" == "1" ]]; then
    printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
    echo "用户已存在，已同步节点登录密码：$USERNAME"
  else
    echo "用户已存在：$USERNAME"
  fi
  exit 0
fi

if [[ "$PASSWORD_STDIN" == "1" ]]; then
  useradd --create-home --user-group --shell /bin/bash "$USERNAME"
  printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
else
  adduser "$USERNAME"
fi

echo "已创建节点登录用户：$USERNAME"
