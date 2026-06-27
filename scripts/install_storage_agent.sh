#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_CONFIG="${SITE_CONFIG:-$PROJECT_ROOT/configs/site.env}"

usage() {
  cat <<'EOF'
用法：
  sudo scripts/install_storage_agent.sh

说明：
  在当前机器安装 Storage Agent：
    1. 检查 bin/storage-agent 是否已编译
    2. 检查 configs/site.env 是否存在并已填写
    3. 生成 /etc/ssms/storage-agent.env
    4. 校验 Agent 必填环境变量
    5. 安装并启动 storage-agent.service

执行前请先在仓库根目录编译：
  go build -o bin/storage-agent ./agent

并为当前机器填写统一部署配置：
  cp configs/site.env.example configs/site.env
  vim configs/site.env

注意：
  当前后端是 HTTP 服务，SSMS_SERVER_URL 应使用 http://，不要写 https://。
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 权限执行：sudo $0" >&2
  exit 1
fi

if [[ ! -x "$PROJECT_ROOT/bin/storage-agent" ]]; then
  echo "缺少可执行文件：$PROJECT_ROOT/bin/storage-agent" >&2
  echo "请先执行：go build -o bin/storage-agent ./agent" >&2
  exit 1
fi

if [[ ! -f "$SITE_CONFIG" ]]; then
  echo "缺少统一部署配置：$SITE_CONFIG" >&2
  echo "请先执行：cp configs/site.env.example configs/site.env，并填写当前机器的真实部署信息" >&2
  exit 1
fi

install -d -m 0755 /etc/ssms
"$PROJECT_ROOT/scripts/apply_site_config.sh" --config "$SITE_CONFIG" --output-dir /etc/ssms

AGENT_ENV="/etc/ssms/storage-agent.env"
if [[ ! -f "$AGENT_ENV" ]]; then
  echo "生成失败：缺少 $AGENT_ENV" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$AGENT_ENV"

missing=0
for name in SSMS_SERVER_URL SSMS_AGENT_NAME SSMS_AGENT_ADDRESS SSMS_AGENT_DISK SSMS_AGENT_INTERVAL; do
  value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "Agent 环境变量缺失：$name" >&2
    missing=1
  fi
done

case "${SSMS_SERVER_URL:-}" in
  http://*)
    ;;
  https://*)
    echo "SSMS_SERVER_URL 当前为 HTTPS：$SSMS_SERVER_URL" >&2
    echo "当前 Go 后端未启用 TLS，请改为 http://..." >&2
    missing=1
    ;;
  *)
    echo "SSMS_SERVER_URL 必须以 http:// 开头：${SSMS_SERVER_URL:-<empty>}" >&2
    missing=1
    ;;
esac

if [[ "$missing" -ne 0 ]]; then
  echo "请修正 $SITE_CONFIG 后重新执行安装脚本。" >&2
  exit 1
fi

install -m 0755 "$PROJECT_ROOT/bin/storage-agent" /usr/local/bin/storage-agent
install -m 0644 "$PROJECT_ROOT/configs/storage-agent.service" /etc/systemd/system/storage-agent.service

systemctl daemon-reload
systemctl enable --now storage-agent

cat <<EOF
Storage Agent 安装完成。

节点名称：$SSMS_AGENT_NAME
节点地址：$SSMS_AGENT_ADDRESS
后台地址：$SSMS_SERVER_URL

服务状态：sudo systemctl status storage-agent
查看日志：journalctl -u storage-agent -f
EOF
