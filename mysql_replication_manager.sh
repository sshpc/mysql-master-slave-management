#!/usr/bin/env bash
# mysql_replication_manager.sh
# 在从机上运行，用来查看/配置/控制 MySQL 主从同步（主从都在 Docker 容器中）

set -euo pipefail
IFS=$'\n\t'

# ---------------------- 默认配置 ----------------------
SLAVE_CONTAINER="mysql"
SLAVE_USER="root"
SLAVE_PASS="root"
MASTER_HOST="x.x.x.x"
MASTER_PORT=3306
MASTER_USER="root"
MASTER_PASS="root"

log(){ echo "[INFO] $*"; }
err(){ echo "[ERR] $*" >&2; }
usage(){ cat <<EOF
用法: $0 <command> [options]
命令:
  status                查看主库和从库同步状态
  start                 在从机执行 START SLAVE
  stop                  在从机执行 STOP SLAVE
  configure [options]   配置从机同步（自动读取主库日志位置）
  clear                 清除从机复制设置

选项:
  --master-host <host>
  --master-port <port>
  --master-user <user>
  --master-pass <password>
EOF
}

run_mysql_slave(){
  local sql="$1"
  docker exec -i "$SLAVE_CONTAINER" mysql -u"$SLAVE_USER" -p"$SLAVE_PASS" -e "$sql" 2>/dev/null
}

run_mysql_master(){
  local sql="$1"
  docker exec -i "$SLAVE_CONTAINER" mysql -h"$MASTER_HOST" -u"$SLAVE_USER" -p"$SLAVE_PASS" -e "$sql" 2>/dev/null
}

fetch_master_log_pos(){
  docker exec -i "$SLAVE_CONTAINER" mysql -h"$MASTER_HOST" -P"$MASTER_PORT" -u"$MASTER_USER" -p"$MASTER_PASS" -e "SHOW MASTER STATUS\\G" 2>/dev/null \
    | awk -F": " '/File:/{f=$2} /Position:/{p=$2} END{print f, p}'
}

cmd_status(){
  log "查询主库日志位置..."
  master_out=$(run_mysql_master "SHOW MASTER STATUS\\G")

  M_FILE=$(echo "$master_out" | awk -F": " '/File:/{print $2}')
  M_POS=$(echo "$master_out" | awk -F": " '/Position:/{print $2}')

  log "查询从机状态..."
  slave_out=$(run_mysql_slave "SHOW SLAVE STATUS\\G")

  SLAVE_IO=$(echo "$slave_out" | awk -F": " '/Slave_IO_Running:/{print $2}')
  SLAVE_SQL=$(echo "$slave_out" | awk -F": " '/Slave_SQL_Running:/{print $2}')
  SLAVE_FILE=$(echo "$slave_out" | awk -F": " '/Master_Log_File:/{print $2}')
  SLAVE_POS=$(echo "$slave_out" | awk -F": " '/Exec_Master_Log_Pos:/{print $2}')
  SLAVE_BEHIND=$(echo "$slave_out" | awk -F": " '/Seconds_Behind_Master:/{print $2}')

  echo "================= 主从同步状态 ================="
  printf "主库日志文件   : %s\\n" "$M_FILE"
  printf "主库日志位置   : %s\\n" "$M_POS"
  echo "-----------------------------------------------"
  printf "从库 IO 线程   : %s\\n" "$SLAVE_IO"
  printf "从库 SQL 线程  : %s\\n" "$SLAVE_SQL"
  printf "从库日志文件   : %s\\n" "$SLAVE_FILE"
  printf "从库执行位置   : %s\\n" "$SLAVE_POS"
  printf "延迟(秒)       : %s\\n" "$SLAVE_BEHIND"
  echo "================================================"
}

cmd_start(){
  log "在从机执行 START SLAVE"
  run_mysql_slave "START SLAVE;"
  cmd_status
}

cmd_stop(){
  log "在从机执行 STOP SLAVE"
  run_mysql_slave "STOP SLAVE;"
  cmd_status
}

cmd_clear(){
  log "清除从机复制设置"
  run_mysql_slave "STOP SLAVE; RESET SLAVE ALL;"
  log "已清除从机复制配置"
}

cmd_configure(){
  if [ -z "$MASTER_HOST" ]; then
    err "必须指定 --master-host"
    exit 1
  fi
  master_out=$(run_mysql_master "SHOW MASTER STATUS\\G")

  FILE=$(echo "$master_out" | awk -F": " '/File:/{print $2}')
  POS=$(echo "$master_out" | awk -F": " '/Position:/{print $2}')

  log "从主库获取到: $FILE $POS"

  SQL="CHANGE MASTER TO MASTER_HOST='${MASTER_HOST}', MASTER_PORT=${MASTER_PORT}, MASTER_USER='${MASTER_USER}', MASTER_PASSWORD='${MASTER_PASS}', MASTER_LOG_FILE='${FILE}', MASTER_LOG_POS=${POS};"
  run_mysql_slave "STOP SLAVE; ${SQL} START SLAVE;"
  log "配置完成"
  cmd_status
}

interactive_menu(){
  while true; do
    echo "================= MySQL 主从管理菜单 ================="
    echo "1) 查看主从状态"
    echo "2) 启动同步 (START SLAVE)"
    echo "3) 停止同步 (STOP SLAVE)"
    echo "4) 配置同步 (CHANGE MASTER TO)"
    echo "5) 清除同步配置 (RESET SLAVE ALL)"
    echo "0) 退出"
    echo "====================================================="
    read -p "请选择操作: " choice
    case "$choice" in
      1) cmd_status ;;
      2) cmd_start ;;
      3) cmd_stop ;;
      4) cmd_configure ;;
      5) cmd_clear ;;
      0) exit 0 ;;
      *) echo "无效选择，请重新输入" ;;
    esac
  done
}

# ---------------------- 参数解析 ----------------------
COMMAND=${1:-""}
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --master-host) MASTER_HOST="$2"; shift 2;;
    --master-port) MASTER_PORT="$2"; shift 2;;
    --master-user) MASTER_USER="$2"; shift 2;;
    --master-pass) MASTER_PASS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "未知参数: $1"; usage; exit 1;;
  esac
done

if [ -z "$COMMAND" ]; then
  interactive_menu
else
  case "$COMMAND" in
    status) cmd_status ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    configure) cmd_configure ;;
    clear) cmd_clear ;;
    *) err "未知命令: $COMMAND"; usage; exit 1;;
  esac
fi
