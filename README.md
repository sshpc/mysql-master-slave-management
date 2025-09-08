# MySQL 主从同步方案

本方案提供 **不停机完成主从同步** 的实现方式，默认基于以下环境：  
- **MySQL 版本**：`5.7`（Docker 部署）  
- **备份工具**：`percona/percona-xtrabackup:2.4`  

---

## 环境要求

   - 已开启 **binlog** （可参考本目录 `my.cnf` binlog部分），并指定需要同步的数据库。  
   - 主库与从库的 **server-id** 必须不同。  


## 操作步骤
1. 主库备份

修改 mysql_bak.sh 中的 主数据库配置，特别是 DATA_DIR，确保其正确对应 MySQL 的数据目录。

```bash
bash mysql_bak.sh backup
```

等待备份完成后，备份文件会生成在 sqlbak 目录下。

2. 将备份拷贝至从库

将 整个备份目录 拷贝到从库 将sqlbak 里的文件移动至上级目录。

确认 DATA_DIR 配置正确后，在从库执行恢复：
```bash
bash mysql_bak.sh restore <文件.tar.gz>
```

>注意：该步骤会清空从库的 data 目录。

3. 从库配置同步

修改从库的 mysql_replication_manager.sh 配置文件。

执行脚本，进入交互式管理菜单，配置同步：
```bash
bash mysql_replication_manager.sh
```

### 管理菜单示例
```
================= MySQL 主从管理菜单 =================
1) 查看主从状态
2) 启动同步 (START SLAVE)
3) 停止同步 (STOP SLAVE)
4) 配置同步 (CHANGE MASTER TO)
5) 清除同步配置 (RESET SLAVE ALL)
0) 退出
=====================================================
请选择操作: 
```
