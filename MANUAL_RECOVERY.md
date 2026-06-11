# 达梦数据库手动恢复指南

本文档详细说明如何手动执行达梦数据库恢复操作，适用于无法使用自动化脚本或需要精确控制恢复过程的场景。

---

## 目录

1. [文档概述](#文档概述)
2. [前置条件检查](#1-前置条件检查)
3. [查看可恢复时间范围](#2-查看可恢复时间范围)
4. [停止数据库服务](#3-停止数据库服务)
5. [备份当前数据](#4-备份当前数据)
6. [启动 DMAP 服务](#5-启动-dmap-服务)
7. [恢复全量备份](#6-恢复全量备份)
8. [应用增量备份](#7-应用增量备份)
9. [应用归档日志](#8-应用归档日志)
10. [更新 DB_MAGIC](#9-更新-db_magic)
11. [修复数据目录权限](#10-修复数据目录权限)
12. [启动数据库服务](#11-启动数据库服务)
13. [验证数据库状态](#12-验证数据库状态)
14. [恢复后备份](#13-恢复后备份)
15. [快速恢复命令汇总](#快速恢复命令汇总)
16. [常见问题](#常见问题)
17. [安全注意事项](#安全注意事项)

---

## 文档概述

### 适用范围

本指南适用于以下场景：

- 无法使用 `dm_recover.sh` 自动化脚本时
- 需要精确控制恢复过程的恢复操作
- 异机恢复场景
- 学习和理解恢复原理
- 故障排查和验证

### 前提知识

- Linux 操作系统基础
- 达梦数据库基础概念
- dmrman 工具使用
- 数据库备份恢复原理

### 关键路径变量

本文档使用以下变量（请根据实际环境替换）：

| 变量 | 示例值 | 说明 |
|------|--------|------|
| `DM_HOME` | `/data/dm` | 达梦数据库安装目录 |
| `DM_DATA` | `/data/dmdata/DMTEST` | 数据文件目录 |
| `DM_BAK` | `/data/dmbak/DMTEST/bak` | 备份文件目录 |
| `DM_ARCH` | `/data/dmarch/DMTEST` | 归档日志目录 |
| `DB_SERVICE` | `DmServiceDMTEST` | 数据库服务名 |
| `DB_PORT` | `5236` | 数据库端口 |
| `DB_USER` | `SYSDBA` | 数据库用户名 |
| `DB_PASS` | `SYSDBA的密码` | 数据库密码 |

---

## 1. 前置条件检查

### 1.1 检查达梦安装目录

```bash
# 检查 DM_HOME 目录是否存在
ls -la /data/dm

# 检查 dmrman 工具
ls -la /data/dm/bin/dmrman

# 检查 disql 工具
ls -la /data/dm/bin/disql
```

**预期输出：** 显示目录内容和工具文件。

### 1.2 检查数据目录

```bash
# 检查数据目录
ls -la /data/dmdata/DMTEST

# 检查 dm.ini 配置文件
ls -la /data/dmdata/DMTEST/dm.ini
```

**预期输出：** 包含 dm.ini 和其他数据文件（SYSTEM.DBF, MAIN.DBF 等）。

### 1.3 检查备份目录

```bash
# 检查备份目录
ls -la /data/dmbak/DMTEST/bak

# 统计备份文件数量
find /data/dmbak/DMTEST/bak -type d | wc -l
```

### 1.4 检查归档目录

```bash
# 检查归档目录
ls -la /data/dmarch/DMTEST

# 统计归档日志数量
find /data/dmarch/DMTEST -name "ARCHIVE_LOCAL1_*" | wc -l
```

### 1.5 检查 dmrman 可用性

```bash
# 测试 dmrman 命令
/data/dm/bin/dmrman
```

**预期输出：** 显示 dmrman 版本信息和帮助。

---

## 2. 查看可恢复时间范围

### 2.1 列出全量备份

```bash
# 列出所有全量备份（按时间排序）
ls -lt /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_*

# 格式说明：DB_DMTEST_FULL_YYYY_MM_DD_HH_MM_SS
```

**示例输出：**

```
drwxr-xr-x 3 dmdba dmdba 4096 Jun 10 01:05  DB_DMTEST_FULL_2026_06_01_01_05_19
drwxr-xr-x 3 dmdba dmdba 4096 Jun 10 01:05  DB_DMTEST_FULL_2026_06_05_01_05_19
drwxr-xr-x 3 dmdba dmdba 4096 Jun 10 01:05  DB_DMTEST_FULL_2026_06_10_01_05_19
```

### 2.2 列出增量备份

```bash
# 列出所有增量备份
ls -lt /data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_*

# 格式说明：DB_DMTEST_INCREMENT_YYYY_MM_DD_HH_MM_SS
```

### 2.3 列出归档日志

```bash
# 列出所有归档日志
ls -lt /data/dmarch/DMTEST/ARCHIVE_LOCAL1_*

# 格式说明：ARCHIVE_LOCAL1_YYYY-MM-DD_HH-MM-SS.log
```

### 2.4 查看备份集详情

```bash
# 查看备份集信息
/data/dm/bin/dmrman CTLSTMT="BACKUP INFO '/data/dmbak/DMTEST/bak/DB_DMTEST_FULL_2026_06_10_01_05_19';"
```

**输出包含：**
- 备份集类型（全量/增量）
- 备份集大小
- 备份集创建时间
- 备份集包含的表空间
- 备份集校验信息

### 2.5 计算可恢复时间范围

根据备份和归档情况，确定可恢复的时间范围：

| 条件 | 最早可恢复时间 | 最晚可恢复时间 |
|------|---------------|---------------|
| 有全量和归档 | 最旧全量备份时间 | 最新归档日志时间 |
| 只有全量 | 全量备份时间 | 全量备份时间 |
| 全量和归档但无增量 | 全量备份时间 | 最新归档时间 |

---

## 3. 停止数据库服务

### 3.1 使用 systemctl 停止

```bash
# 停止数据库服务
systemctl stop DmServiceDMTEST

# 验证服务状态
systemctl status DmServiceDMTEST
```

### 3.2 使用 service 命令停止（备用）

```bash
# 停止数据库服务
service DmServiceDMTEST stop

# 或直接使用 dmdba 用户
su - dmdba -c "$DM_HOME/bin/DmServiceDMTEST stop"
```

### 3.3 验证数据库进程已停止

```bash
# 检查 dmserver 进程
ps -ef | grep dmserver

# 或使用 pgrep
pgrep -f "dmserver"
```

**预期结果：** 无输出或无 dmserver 相关进程。

### 3.4 强制终止（如有必要）

```bash
# 强制终止 dmserver 进程
pkill -9 -f "dmserver"

# 等待进程退出
sleep 3

# 确认已终止
pgrep -f "dmserver"
```

### 3.5 停止 DMAP 进程

```bash
# 检查 DMAP 进程
pgrep -f "dmap"

# 停止 DMAP
pkill -9 -f "dmap"

# 确认已停止
pgrep -f "dmap"
```

---

## 4. 备份当前数据

### 4.1 创建备份目录

```bash
# 创建备份目录（带时间戳）
BACKUP_DIR="/data/dmdata/DMTEST_broken_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "备份目录: $BACKUP_DIR"
```

### 4.2 复制数据文件

```bash
# 复制所有数据文件
cp -r /data/dmdata/DMTEST/* "$BACKUP_DIR/"

# 验证复制完成
ls -la "$BACKUP_DIR/"
```

### 4.3 验证备份完整性

```bash
# 检查关键文件
ls -la "$BACKUP_DIR/SYSTEM.DBF"
ls -la "$BACKUP_DIR/main.dbf"
ls -la "$BACKUP_DIR/dm.ini"

# 检查文件数量
find "$BACKUP_DIR" -name "*.dbf" | wc -l
```

### 4.4 记录备份信息

```bash
# 记录备份信息
echo "数据备份完成" | tee /tmp/backup_info.txt
echo "时间: $(date)" | tee -a /tmp/backup_info.txt
echo "源目录: /data/dmdata/DMTEST" | tee -a /tmp/backup_info.txt
echo "备份目录: $BACKUP_DIR" | tee -a /tmp/backup_info.txt
echo "备份大小: $(du -sh $BACKUP_DIR)" | tee -a /tmp/backup_info.txt
```

---

## 5. 启动 DMAP 服务

### 5.1 DMAP 服务说明

DMAP（DM Archive Service）是达梦数据库的备份恢复辅助服务，负责管理备份集的元数据和校验。

### 5.2 检查 DMAP 状态

```bash
# 检查 DMAP 是否已在运行
pgrep -f "dmap"
```

### 5.3 启动 DMAP

```bash
# 启动 DMAP 服务
/data/dm/bin/dmap &

# 等待启动完成
sleep 2

# 验证 DMAP 已启动
ps -ef | grep dmap
```

### 5.4 DMAP 启动失败处理

如果 DMAP 启动失败，dmrman 可以使用内置模式运行：

```bash
# 检查 DMAP 程序是否存在
ls -la /data/dm/bin/dmap

# 如果不存在，手动启动一次
nohup /data/dm/bin/dmap > /dev/null 2>&1 &

# 检查端口（DMAP 默认使用 5237）
netstat -tln | grep 5237
```

---

## 6. 恢复全量备份

### 6.1 确定全量备份路径

```bash
# 查找最新的全量备份
latest_full=$(ls -d /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_* | sort | tail -1)
echo "最新全量备份: $latest_full"

# 指定特定的全量备份
# full_backup="/data/dmbak/DMTEST/bak/DB_DMTEST_FULL_2026_06_05_01_05_19"
```

### 6.2 校验备份集（可选但推荐）

```bash
# 校验备份集完整性
/data/dm/bin/dmrman CTLSTMT="CHECK BACKUPSET '$latest_full';"
```

**校验输出示例：**

```
check backupset $latest_full
file h: backup set $latest_full, level: 0
backupset $latest_full, check all the media files, time: 8
the backupset is valid
```

### 6.3 简单全量恢复

```bash
# 执行全量恢复
/data/dm/bin/dmrman CTLSTMT="RESTORE DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$latest_full';"
```

### 6.4 带增量链的全量恢复（推荐）

如果有增量备份，使用 WITH BACKUPDIR 参数可以一次性恢复全量和所有增量：

```bash
# 执行全量+增量恢复
/data/dm/bin/dmrman CTLSTMT="RESTORE DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$latest_full' WITH BACKUPDIR '/data/dmbak/DMTEST/bak';"
```

**WITH BACKUPDIR 优点：**
- 自动搜索并应用所有增量备份
- 一次命令完成全量+增量恢复
- 无需手动逐个应用增量

### 6.5 恢复命令参数说明

| 参数 | 说明 |
|------|------|
| `RESTORE DATABASE` | 恢复数据库命令 |
| `'dm.ini路径'` | 数据库配置文件路径 |
| `FROM BACKUPSET` | 指定备份集来源 |
| `'备份集路径'` | 具体备份集目录 |
| `WITH BACKUPDIR` | 搜索备份的目录 |

### 6.6 恢复过程说明

```
恢复过程：
1. 读取备份集元数据
2. 分配恢复区间
3. 读取备份数据
4. 写入数据文件
5. 更新控制文件
6. 验证恢复结果
```

---

## 7. 应用增量备份

如果第6步使用了 WITH BACKUPDIR，此步骤可跳过。

### 7.1 判断是否需要手动应用

```bash
# 检查是否已通过 WITH BACKUPDIR 处理
# 如果第6步使用了 WITH BACKUPDIR，则跳过此步骤
```

### 7.2 确定基座全量备份

```bash
# 基座全量备份日期
full_date="2026_06_05"
full_sec=$(date -d "${full_date//_/-} 01:05:19" +%s)
echo "基座全量时间戳: $full_sec"
```

### 7.3 筛选需要应用的增量

```bash
# 列出所有增量备份
for bak in /data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_*; do
    inc_date=$(basename "$bak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    inc_sec=$(date -d "${inc_date//_/-} 01:05:19" +%s)

    if [ "$inc_sec" -gt "$full_sec" ]; then
        echo "待应用: $bak"
        echo "  日期: $inc_date"
        echo "  时间戳: $inc_sec"
    fi
done
```

### 7.4 逐个应用增量备份

```bash
# 逐个应用增量备份（按时间顺序）
increment_bak="/data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_2026_06_06_01_05_19"

/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$increment_bak';"
```

### 7.5 批量应用增量脚本

```bash
#!/bin/bash
# 批量应用增量备份脚本

full_date="2026_06_05"
full_sec=$(date -d "${full_date//_/-} 01:05:19" +%s)

for bak in $(ls -d /data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_* | sort); do
    inc_date=$(basename "$bak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    inc_sec=$(date -d "${inc_date//_/-} 01:05:19" +%s)

    if [ "$inc_sec" -gt "$full_sec" ]; then
        echo "应用增量: $(basename $bak)"
        /data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$bak';"
    fi
done

echo "增量应用完成"
```

---

## 8. 应用归档日志

### 8.1 恢复到最新状态

```bash
# 应用所有归档日志，恢复到最新状态
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' WITH ARCHIVEDIR '/data/dmarch/DMTEST';"
```

### 8.2 恢复到指定时间点

```bash
# 定义目标时间点
time_point="2026-06-10 12:00:00"

# 恢复到指定时间点
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' WITH ARCHIVEDIR '/data/dmarch/DMTEST' UNTIL TIME '$time_point';"
```

### 8.3 时间点恢复说明

```
时间点恢复原理：
1. 从指定的全量备份恢复数据文件
2. 从归档日志按时间顺序重做（REDO）
3. UNTIL TIME 参数指定停止时间
4. 自动处理 LSN 链
```

### 8.4 UNTIL TIME 参数说明

| 参数 | 说明 |
|------|------|
| `UNTIL TIME '时间点'` | 恢复到指定时间点 |
| 时间格式 | `'YYYY-MM-DD HH:MI:SS'` |
| 精度 | 秒级精度 |

### 8.5 归档应用过程

```
归档应用过程：
1. 读取归档日志目录
2. 按时间顺序扫描归档文件
3. 对每个归档执行 REDO
4. 直到达到目标时间点
5. 生成恢复点标记
```

---

## 9. 更新 DB_MAGIC

### 9.1 DB_MAGIC 说明

DB_MAGIC 是达梦数据库实例的唯一标识符，用于标识数据库实例的生命周期。每次恢复后需要更新。

### 9.2 执行更新

```bash
# 更新 DB_MAGIC
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' UPDATE DB_MAGIC;"
```

### 9.3 更新过程说明

```
DB_MAGIC 更新过程：
1. 生成新的 DB_MAGIC
2. 更新 SYSTEM.DBF 中的系统表
3. 更新控制文件
4. 确认更新成功
```

---

## 10. 修复数据目录权限

### 10.1 权限问题说明

dmrman 以 root 用户运行时，恢复的文件属于 root。但达梦数据库服务通常以 dmdba 用户运行，会导致权限不足。

### 10.2 确定数据库运行用户

```bash
# 从 systemd 服务文件读取
grep '^User=' /etc/systemd/system/DmServiceDMTEST.service

# 或检查服务配置
cat /etc/systemd/system/DmServiceDMTEST.service | grep User
```

### 10.3 修改数据目录权限

```bash
# 确认当前属主
ls -la /data/dmdata/DMTEST/SYSTEM.DBF

# 修改为 dmdba 用户和组
chown -R dmdba:dmdba /data/dmdata/DMTEST

# 验证修改
ls -la /data/dmdata/DMTEST/SYSTEM.DBF
```

### 10.4 常见用户配置

| 用户 | 说明 |
|------|------|
| `dmdba` | 达梦数据库默认安装用户 |
| `root` | 强制以 root 运行 |
| `oracle` | 兼容 Oracle 习惯 |

---

## 11. 启动数据库服务

### 11.1 使用 systemctl 启动

```bash
# 启动数据库服务
systemctl start DmServiceDMTEST

# 检查服务状态
systemctl status DmServiceDMTEST
```

### 11.2 验证数据库进程

```bash
# 检查 dmserver 进程
ps -ef | grep dmserver

# 检查端口监听
ss -tln | grep ":5236 "
```

### 11.3 启动失败排查

```bash
# 查看服务日志
journalctl -u DmServiceDMTEST -n 50

# 检查数据目录权限
ls -la /data/dmdata/DMTEST/

# 检查 dm.ini 配置
grep "PORT_NUM" /data/dmdata/DMTEST/dm.ini
```

---

## 12. 验证数据库状态

### 12.1 检查端口连接

```bash
# 使用 ss 检查端口
ss -tln | grep 5236

# 使用 nc 检查
nc -z localhost 5236

# 使用 telnet 检查
telnet localhost 5236
```

### 12.2 连接数据库验证

```bash
# 连接数据库
/data/dm/bin/disql SYSDBA/'your_password'@localhost:5236
```

### 12.3 执行验证 SQL

```sql
-- 检查数据库状态
SELECT '状态' 项目, STATUS$ || '-' || MODE$ 结果 FROM V$INSTANCE;

-- 检查数据库时间
SELECT '时间' 项目, TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') 结果 FROM DUAL;

-- 检查归档模式
SELECT '归档' 项目, ARCH_MODE 结果 FROM V$DATABASE;

-- 打开数据库（如处于 MOUNT 状态）
ALTER DATABASE OPEN;

-- 再次检查状态
SELECT 'OPEN状态' 项目, STATUS$ || '-' || MODE$ 结果 FROM V$INSTANCE;

-- 退出
EXIT;
```

### 12.4 非交互式验证

```bash
# 使用 heredoc 执行 SQL
/data/dm/bin/disql SYSDBA/'your_password'@localhost:5236 <<'SQLEOF'
SELECT '状态' 项目, STATUS$ || '-' || MODE$ 结果 FROM V$INSTANCE;
SELECT '时间' 项目, TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') 结果 FROM DUAL;
SELECT '归档' 项目, ARCH_MODE 结果 FROM V$DATABASE;
ALTER DATABASE OPEN;
SELECT 'OPEN状态' 项目, STATUS$ || '-' || MODE$ 结果 FROM V$INSTANCE;
EXIT;
SQLEOF
```

### 12.5 状态值说明

| 状态值 | 说明 | 处理方式 |
|--------|------|----------|
| `MOUNT` | 数据库处于挂载状态 | 需执行 `ALTER DATABASE OPEN` |
| `OPEN` | 数据库已打开 | 正常运行 |
| `MOUNT-ACTIVE` | 挂载状态且活动 | 执行 OPEN |
| `OPEN-ACTIVE` | 打开状态且活动 | 正常 |

---

## 13. 恢复后备份

### 13.1 备份建议

恢复完成后，建议立即执行一次全量备份，确保有最新的干净备份点。

### 13.2 创建备份目录

```bash
# 创建备份目录
backup_dir="/data/dmbak/DMTEST/bak/DB_DMTEST_FULL_$(date +%Y_%m_%d)_01_05_19"
mkdir -p "$backup_dir"

echo "备份目录: $backup_dir"
```

### 13.3 执行全量备份

```bash
# 执行全量备份
/data/dm/bin/dmrman CTLSTMT="BACKUP DATABASE '/data/dmdata/DMTEST/dm.ini' FULL TO '$backup_dir' BACKUPINFO '恢复后手动备份';"
```

### 13.4 备份验证

```bash
# 检查备份集
ls -la "$backup_dir"

# 校验备份集
/data/dm/bin/dmrman CTLSTMT="CHECK BACKUPSET '$backup_dir';"
```

---

## 快速恢复命令汇总

### 恢复到最新状态（推荐）

```bash
#!/bin/bash
# 完整恢复流程 - 恢复到最新状态

# ========== 配置区 ==========
DM_HOME="/data/dm"
DM_DATA="/data/dmdata/DMTEST"
DM_BAK="/data/dmbak/DMTEST/bak"
DM_ARCH="/data/dmarch/DMTEST"
DB_SERVICE="DmServiceDMTEST"
DB_USER="SYSDBA"
DB_PASS="your_password"
DB_PORT="5236"
# ============================

# 1. 停止数据库
echo "[1/10] 停止数据库..."
systemctl stop $DB_SERVICE
pkill -9 -f "dmserver" 2>/dev/null
sleep 3

# 2. 备份当前数据
echo "[2/10] 备份当前数据..."
BACKUP_DIR="${DM_DATA}_broken_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r $DM_DATA/* "$BACKUP_DIR/"
echo "已备份到: $BACKUP_DIR"

# 3. 启动 DMAP
echo "[3/10] 启动 DMAP..."
/data/dm/bin/dmap &
sleep 2

# 4. 确定最新全量
echo "[4/10] 确定全量备份..."
latest_full=$(ls -d $DM_BAK/DB_DMTEST_FULL_* | sort | tail -1)
echo "使用全量: $latest_full"

# 5. 恢复全量+增量
echo "[5/10] 恢复全量+增量..."
$DM_HOME/bin/dmrman CTLSTMT="RESTORE DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$latest_full' WITH BACKUPDIR '$DM_BAK';"

# 6. 应用归档
echo "[6/10] 应用归档日志..."
$DM_HOME/bin/dmrman CTLSTMT="RECOVER DATABASE '$DM_DATA/dm.ini' WITH ARCHIVEDIR '$DM_ARCH';"

# 7. 更新 DB_MAGIC
echo "[7/10] 更新 DB_MAGIC..."
$DM_HOME/bin/dmrman CTLSTMT="RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;"

# 8. 修复权限
echo "[8/10] 修复权限..."
chown -R dmdba:dmdba $DM_DATA

# 9. 启动数据库
echo "[9/10] 启动数据库..."
systemctl start $DB_SERVICE
sleep 5

# 10. 验证
echo "[10/10] 验证数据库..."
$DM_HOME/bin/disql $DB_USER/"$DB_PASS"@localhost:$DB_PORT <<'SQLEOF'
ALTER DATABASE OPEN;
SELECT STATUS$ FROM V$INSTANCE;
EXIT;
SQLEOF

echo "========== 恢复完成 =========="
```

### 恢复到指定时间点

```bash
#!/bin/bash
# 恢复到指定时间点

time_point="2026-06-10 12:00:00"

# 停止数据库
systemctl stop DmServiceDMTEST
pkill -9 -f "dmserver"

# 备份
BACKUP_DIR="/data/dmdata/DMTEST_broken_$(date +%Y%m%d_%H%M%S)"
cp -r /data/dmdata/DMTEST/* "$BACKUP_DIR/"

# 启动 DMAP
/data/dm/bin/dmap &

# 找到目标时间前的最新全量
tp_sec=$(date -d "$time_point" +%s)
best_full=""
for fbak in $(ls -d /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_* | sort); do
    fd=$(basename "$fbak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    fd_sec=$(date -d "${fd//_/-} 01:05:19" +%s)
    [ "$fd_sec" -le "$tp_sec" ] && best_full="$fbak"
done

# 恢复
$DM_HOME/bin/dmrman CTLSTMT="RESTORE DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$best_full';"

# 应用归档到时间点
$DM_HOME/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' WITH ARCHIVEDIR '/data/dmarch/DMTEST' UNTIL TIME '$time_point';"

# 更新 DB_MAGIC
$DM_HOME/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' UPDATE DB_MAGIC;"

# 修复权限并启动
chown -R dmdba:dmdba /data/dmdata/DMTEST
systemctl start DmServiceDMTEST

echo "恢复完成，恢复到时间点: $time_point"
```

---

## 常见问题

### Q1: 恢复失败提示 "备份集校验失败"

**原因：** 备份文件损坏或不完整。

**解决：**
1. 使用其他备份集
2. 检查备份文件完整性
3. 使用 `CHECK BACKUPSET` 手动校验

### Q2: 归档日志应用失败

**原因：** 归档日志缺失或格式错误。

**解决：**
1. 检查归档目录
2. 确认归档文件完整
3. 使用 `ALTER DATABASE OPEN` 强制打开

### Q3: 数据库无法 OPEN

**原因：** 数据库处于 MOUNT 状态。

**解决：**
```sql
ALTER DATABASE OPEN;
```

### Q4: N_MAGIC 不匹配

**原因：** 增量备份与全量基座不一致。

**解决：** 确保使用正确的基座全量备份，或使用 WITH BACKUPDIR 自动处理。

### Q5: 权限问题

**原因：** dmrman 以 root 运行，恢复文件属主为 root。

**解决：**
```bash
chown -R dmdba:dmdba /data/dmdata/DMTEST
```

### Q6: 超时问题

**原因：** 备份文件过大。

**解决：** 增加超时时间或使用 `DMRMAN_TIMEOUT=0` 不超时。

---

## 安全注意事项

### 恢复前

- [ ] 确认已备份当前数据
- [ ] 验证备份完整性
- [ ] 记录操作人员信息
- [ ] 通知相关人员

### 恢复中

- [ ] 确保操作在维护窗口期
- [ ] 监控恢复进度
- [ ] 记录所有操作命令

### 恢复后

- [ ] 验证数据完整性
- [ ] 检查数据库状态
- [ ] 执行新的备份
- [ ] 更新维护文档

---

## 参考信息

### dmrman 命令帮助

```bash
/data/dm/bin/dmrman help
```

### 相关文档

- [达梦数据库官方文档](https://www.dameng.com/document)
- dmrman 工具使用手册
- 达梦数据库备份恢复章节

---

## 修订历史

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| 1.0 | 2026-06-11 | 初始版本 |
