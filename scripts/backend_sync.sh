#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${BACKEND_CONFIG_FILE:-/etc/ssms/backend.conf}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$PROJECT_ROOT/configs/backend.conf"
fi

usage() {
  cat <<'EOF'
用法：
  scripts/backend_sync.sh health
  scripts/backend_sync.sh list-users [--format table|json]
  scripts/backend_sync.sh upsert-user USERNAME QUOTA_GB
  scripts/backend_sync.sh update-quota USERNAME QUOTA_GB
  scripts/backend_sync.sh sync-usage [--format-summary]
  scripts/backend_sync.sh delete-user USERNAME
  scripts/backend_sync.sh delete-server NODE_NAME

说明：
  该脚本只同步 Go 管理后台数据库，不创建或删除 Linux/Samba 系统用户。
  系统用户仍由 create_user.sh、sync_user.sh、sync_delete_user.sh 等脚本负责。
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
  echo "缺少后台配置文件：$CONFIG_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

API_BASE="${BACKEND_API_BASE%/}"
API_TIMEOUT="${BACKEND_API_TIMEOUT:-5}"
SYNC_ENABLED="${BACKEND_SYNC_ENABLED:-1}"
COMMAND="$1"
shift

if [[ "$SYNC_ENABLED" != "1" ]]; then
  echo "后台同步已关闭：BACKEND_SYNC_ENABLED=$SYNC_ENABLED"
  exit 0
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令：$1"
    exit 1
  fi
}

curl_api() {
  curl -sS --fail --max-time "$API_TIMEOUT" "$@"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

quota_gb_to_bytes() {
  local quota_gb="$1"
  if ! [[ "$quota_gb" =~ ^[0-9]+$ ]] || [[ "$quota_gb" -le 0 ]]; then
    echo "配额必须是正整数，单位为 GB。"
    exit 1
  fi
  printf '%s\n' $((quota_gb * 1024 * 1024 * 1024))
}

list_users() {
  local format="table"
  local payload

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format)
        format="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        return
        ;;
      *)
        echo "未知参数：$1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
  if [[ "$format" != "table" && "$format" != "json" ]]; then
    echo "格式必须是 table 或 json。" >&2
    exit 1
  fi

  payload="$(curl_api "$API_BASE/api/users")"
  if [[ "$format" == "json" ]]; then
    printf '%s\n' "$payload"
    return
  fi

  require_cmd python3
  printf '%s' "$payload" | python3 -c '
import json
import sys
import unicodedata

users = json.load(sys.stdin) or []

def clean(value):
    return str(value or "").replace("\t", " ").replace("\n", " ")

def display_width(value):
    return sum(
        2 if unicodedata.east_asian_width(char) in ("W", "F", "A") else 1
        for char in value
    )

def pad(value, width):
    return value + " " * (width - display_width(value))

headers = ["ID", "USERNAME", "FULL_NAME", "EMAIL", "QUOTA_GB", "UPDATED_AT"]
rows = []
for user in users:
    quota_gb = int(user.get("quota_bytes", 0)) / (1024 ** 3)
    rows.append([
        clean(user.get("id")),
        clean(user.get("username")),
        clean(user.get("full_name")),
        clean(user.get("email")),
        f"{quota_gb:.2f}",
        clean(user.get("updated_at")),
    ])

widths = [
    max([display_width(headers[index])] + [display_width(row[index]) for row in rows])
    for index in range(len(headers))
]
print("  ".join(pad(header, widths[index]) for index, header in enumerate(headers)))
for row in rows:
    print("  ".join(pad(value, widths[index]) for index, value in enumerate(row)))
'
}

username_valid() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

user_id_by_username() {
  local username="$1"
  curl_api "$API_BASE/api/users" | awk -v username="$username" '
    BEGIN {
      pattern = "\"username\":\"" username "\""
    }
    {
      text = $0
      while (match(text, /\{[^{}]*\}/)) {
        obj = substr(text, RSTART, RLENGTH)
        if (index(obj, pattern) > 0 && match(obj, /"id":[0-9]+/)) {
          print substr(obj, RSTART + 5, RLENGTH - 5)
          exit
        }
        text = substr(text, RSTART + RLENGTH)
      }
    }
  '
}

server_id_by_name() {
  local node_name="$1"
  curl_api "$API_BASE/api/servers" | awk -v node_name="$node_name" '
    BEGIN {
      pattern = "\"name\":\"" node_name "\""
    }
    {
      text = $0
      while (match(text, /\{[^{}]*\}/)) {
        obj = substr(text, RSTART, RLENGTH)
        if (index(obj, pattern) > 0 && match(obj, /"id":[0-9]+/)) {
          print substr(obj, RSTART + 5, RLENGTH - 5)
          exit
        }
        text = substr(text, RSTART + RLENGTH)
      }
    }
  '
}

upsert_user() {
  local username="$1"
  local quota_gb="$2"
  local quota_bytes user_id safe_username

  if ! username_valid "$username"; then
    echo "用户名非法：$username"
    exit 1
  fi

  quota_bytes="$(quota_gb_to_bytes "$quota_gb")"
  user_id="$(user_id_by_username "$username")"
  safe_username="$(json_escape "$username")"

  if [[ -n "$user_id" ]]; then
    curl_api -X PUT "$API_BASE/api/users/username/$username/quota" \
      -H 'Content-Type: application/json' \
      -d "{\"quota_bytes\":$quota_bytes}" >/dev/null
    echo "后台用户已存在，已同步配额：$username"
  else
    curl_api -X POST "$API_BASE/api/users" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$safe_username\",\"full_name\":\"$safe_username\",\"email\":\"$safe_username@example.local\",\"quota_bytes\":$quota_bytes}" >/dev/null
    echo "后台用户已创建：$username"
  fi
}

update_quota() {
  local username="$1"
  local quota_gb="$2"
  local quota_bytes

  if ! username_valid "$username"; then
    echo "用户名非法：$username"
    exit 1
  fi

  quota_bytes="$(quota_gb_to_bytes "$quota_gb")"
  curl_api -X PUT "$API_BASE/api/users/username/$username/quota" \
    -H 'Content-Type: application/json' \
    -d "{\"quota_bytes\":$quota_bytes}" >/dev/null
  echo "后台配额已同步：$username"
}

sync_usage() {
  local summary="${1:-}"
  local synced_count=0
  local skipped_count=0
  local username path used_kb used_bytes safe_username safe_path
  require_cmd awk

  if [[ $EUID -ne 0 ]]; then
    echo "同步存储用量需要读取用户目录，请使用 root 权限执行。"
    exit 1
  fi

  while IFS=, read -r username path used_kb; do
    if [[ -z "$username" || -z "$path" || -z "$used_kb" ]]; then
      continue
    fi

    if [[ -z "$(user_id_by_username "$username")" ]]; then
      echo "跳过后台未登记用户：$username（请先执行：sudo scripts/backend_sync.sh upsert-user $username QUOTA_GB）" >&2
      skipped_count=$((skipped_count + 1))
      continue
    fi

    used_bytes=$((used_kb * 1024))
    safe_username="$(json_escape "$username")"
    safe_path="$(json_escape "$path")"
    curl_api -X POST "$API_BASE/api/storage/username" \
      -H 'Content-Type: application/json' \
      -d "{\"username\":\"$safe_username\",\"used_bytes\":$used_bytes,\"path\":\"$safe_path\"}" >/dev/null
    synced_count=$((synced_count + 1))
    if [[ "$summary" == "--format-summary" ]]; then
      echo "已同步用量：$username $used_bytes bytes"
    fi
  done < <("$SCRIPT_DIR/storage_usage_report.sh" --format csv | tail -n +2)

  if [[ "$summary" == "--format-summary" ]]; then
    echo "用量同步完成：成功 $synced_count，跳过 $skipped_count"
  fi
}

delete_user_backend() {
  local username="$1"
  local user_id

  if ! username_valid "$username"; then
    echo "用户名非法：$username"
    exit 1
  fi

  user_id="$(user_id_by_username "$username")"
  if [[ -z "$user_id" ]]; then
    echo "后台用户不存在：$username"
    exit 0
  fi

  curl_api -X DELETE "$API_BASE/api/users/$user_id" >/dev/null
  echo "后台用户已删除：$username"
}

delete_server_backend() {
  local node_name="$1"
  local server_id

  if [[ ! "$node_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "节点名非法：$node_name"
    exit 1
  fi

  server_id="$(server_id_by_name "$node_name")"
  if [[ -z "$server_id" ]]; then
    echo "后台节点不存在：$node_name"
    exit 0
  fi

  curl_api -X DELETE "$API_BASE/api/servers/$server_id" >/dev/null
  echo "后台节点已删除：$node_name"
}

case "$COMMAND" in
  health)
    curl_api "$API_BASE/api/health"
    echo
    ;;
  list-users)
    list_users "$@"
    ;;
  upsert-user)
    if [[ $# -ne 2 ]]; then
      usage
      exit 1
    fi
    upsert_user "$1" "$2"
    ;;
  update-quota)
    if [[ $# -ne 2 ]]; then
      usage
      exit 1
    fi
    update_quota "$1" "$2"
    ;;
  sync-usage)
    sync_usage "${1:-}"
    ;;
  delete-user)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    delete_user_backend "$1"
    ;;
  delete-server)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    delete_server_backend "$1"
    ;;
  *)
    echo "未知命令：$COMMAND"
    usage
    exit 1
    ;;
esac
