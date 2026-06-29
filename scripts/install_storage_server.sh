#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/configs/system.conf}"
BACKEND_CONFIG_FILE="${BACKEND_CONFIG_FILE:-$PROJECT_ROOT/configs/backend.conf}"
BOOTSTRAP_MODE="${BOOTSTRAP_MODE:-0}"

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "缺少配置文件：$CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y samba smbclient quota acl

install -d -m 0755 /etc/ssms
if [[ -e /etc/ssms/system.conf && "$CONFIG_FILE" -ef /etc/ssms/system.conf ]]; then
  chmod 0644 /etc/ssms/system.conf
else
  install -m 0644 "$CONFIG_FILE" /etc/ssms/system.conf
fi
if [[ -f "$BACKEND_CONFIG_FILE" ]]; then
  if [[ -e /etc/ssms/backend.conf && "$BACKEND_CONFIG_FILE" -ef /etc/ssms/backend.conf ]]; then
    chmod 0644 /etc/ssms/backend.conf
  else
    install -m 0644 "$BACKEND_CONFIG_FILE" /etc/ssms/backend.conf
  fi
fi
install -m 0755 "$PROJECT_ROOT/scripts/ssmsctl" /usr/local/bin/ssmsctl

if ! getent group "$STORAGE_GROUP" >/dev/null; then
  groupadd --system "$STORAGE_GROUP"
fi

install -d -o root -g "$STORAGE_GROUP" -m 0711 "$STORAGE_ROOT"

if [[ -f /etc/samba/smb.conf ]]; then
  cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
fi

install -m 0644 "$PROJECT_ROOT/configs/smb.conf" /etc/samba/smb.conf
sed -i \
  -e "s/^\\s*workgroup = .*/   workgroup = $SMB_WORKGROUP/" \
  -e "s/^\\s*netbios name = .*/   netbios name = $SMB_NETBIOS_NAME/" \
  /etc/samba/smb.conf

testparm -s
systemctl enable --now smbd nmbd
systemctl restart smbd nmbd

cat <<EOF
Storage Server 基础安装完成。

统一管理命令：ssmsctl --help
EOF

if [[ "$BOOTSTRAP_MODE" == "1" ]]; then
  echo "bootstrap 将继续配置 quota、管理后台和 Storage Agent。"
else
  cat <<EOF

下一步：
1. 为 $STORAGE_ROOT 所在文件系统启用 quota 挂载参数。
2. 执行：sudo ssmsctl quota enable
3. 创建用户：sudo ssmsctl user create USERNAME --quota-gb $DEFAULT_QUOTA_GB
EOF
fi
