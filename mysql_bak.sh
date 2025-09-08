#!/bin/bash
# MySQL 全量备份/恢复脚本
# 环境: MySQL 5.7, XtraBackup 2.4

### ===== 配置区 =====
MYSQL_HOST="x.x.x.x"
MYSQL_PORT=3306
MYSQL_USER="root"
MYSQL_PASSWORD="root"

DATA_DIR="/home/docker/mysql/data"
BACKUP_BASE="/home/docker/xtrabackup/sqlbak"
LOG_DIR="/home/docker/xtrabackup/log"

LOG_FILE="$LOG_DIR/backup-$(date '+%Y%m%d').log"
### =================

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

full_backup() {
    TS=$(date '+%Y%m%d_%H%M%S')
    BACKUP_DIR="$BACKUP_BASE/full_$TS"
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"

    log "开始全量备份 -> $BACKUP_DIR"

    docker run --rm \
      --user root \
      --network=host \
      -v "$BACKUP_DIR":/backup \
      -v "$DATA_DIR":/var/lib/mysql:ro \
      percona/percona-xtrabackup:2.4 \
      xtrabackup --backup \
        --target-dir=/backup \
        --host=$MYSQL_HOST \
        --port=$MYSQL_PORT \
        --user=$MYSQL_USER \
        --password=$MYSQL_PASSWORD 2>&1 | tee -a "$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "全量备份完成: $BACKUP_DIR"

        # 打包压缩
        tar -czf "${BACKUP_DIR}.tar.gz" -C "$BACKUP_BASE" "full_$TS"
        rm -rf "$BACKUP_DIR"
        log "已压缩备份: ${BACKUP_DIR}.tar.gz"
    else
        log "全量备份失败"
    fi
}

restore_backup() {
    TAR_FILE="$1"
    if [ -z "$TAR_FILE" ]; then
        echo "用法: $0 restore <备份文件.tar.gz>"
        exit 1
    fi
    if [ ! -f "$TAR_FILE" ]; then
        log "备份文件不存在: $TAR_FILE"
        exit 1
    fi

    RESTORE_DIR="$BACKUP_BASE/restore_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$RESTORE_DIR"

    log "解压备份文件: $TAR_FILE -> $RESTORE_DIR"
    tar -xzf "$TAR_FILE" -C "$RESTORE_DIR"

    INNER_DIR=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name "full_*" | head -n1)

    log "开始恢复 -> $INNER_DIR"

    # prepare
    docker run --rm \
      --user root \
      -v "$INNER_DIR":/backup \
      percona/percona-xtrabackup:2.4 \
      xtrabackup --prepare --target-dir=/backup 2>&1 | tee -a "$LOG_FILE"

    # 停止 MySQL 容器
    docker stop mysql 2>/dev/null
    log "已停止 mysql 容器"

    # 清空数据目录
    # rm -rf "$DATA_DIR"/*
    rm -rf "$DATA_DIR"
    mkdir -p "$DATA_DIR"
    chown 999:999 "$DATA_DIR"

    log "已清空 MySQL 数据目录"

    # copy-back
    docker run --rm \
      --user root \
      -v "$INNER_DIR":/backup \
      -v "$DATA_DIR":/var/lib/mysql \
      percona/percona-xtrabackup:2.4 \
      xtrabackup --copy-back --target-dir=/backup --datadir=/var/lib/mysql 2>&1 | tee -a "$LOG_FILE"

    chown -R 999:999 "$DATA_DIR"
    log "恢复完成，权限已修复"

    docker start mysql
    log "已尝试启动 mysql 容器"
}

case "$1" in
    backup)
        full_backup
        ;;
    restore)
        restore_backup "$2"
        ;;
    *)
        echo "用法: $0 {backup|restore <文件.tar.gz>}"
        exit 1
        ;;
esac

