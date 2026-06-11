# 达梦数据库手动恢复指南

本文档详细说明如何手动执行达梦数据库恢复操作，适用于无法使用自动化脚本或需要精确控制恢复过程的场景。

---

## 目录

1. [前置条件检查](#1-前置条件检查)
2. [查看可恢复时间范围](#2-查看可恢复时间范围)
3. [停止数据库服务](#3-停止数据库服务)
4. [备份当前数据](#4-备份当前数据)
5. [启动 DMAP 服务](#5-启动-dmap-服务)
6. [恢复全量备份](#6-恢复全量备份)
7. [应用增量备份](#7-应用增量备份)
8. [应用归档日志](#8-应用归档日志)
9. [更新 DB_MAGIC](#9-更新-db_magic)
10. [修复数据目录权限](#10-修复数据目录权限)
11. [启动数据库服务](#11-启动数据库服务)
12. [验证数据库状态](#12-验证数据库状态)
13. [恢复后备份](#13-恢复后备份)

---

## 关键路径说明

本文档假设以下路径配置（请根据实际环境调整）：

| 变量 | 路径 | 说明 |
|------|------|------|
| DM_HOME | `/data/dm` | 达梦数据库安装目录 |
| DM_DATA | `/data/dmdata/DMTEST` | 数据文件目录 |
| DM_BAK | `/data/dmbak/DMTEST/bak` | 备份文件目录 |
| DM_ARCH | `/data/dmarch/DMTEST` | 归档日志目录 |
| DB_SERVICE | `DmServiceDMTEST` | 数据库服务名 |
| DB_PORT | `5236` | 数据库端口 |
| DB_USER | `SYSDBA` | 数据库用户名 |
| DB_PASS | `SYSDBA的密码` | 数据库密码 |

---

## 1. 前置条件检查

### 1.1 确认路径存在

```bash
# 检查达梦安装目录
ls -la /data/dm

# 检查数据目录
ls -la /data/dmdata/DMTEST

# 检查备份目录
ls -la /data/dmbak/DMTEST/bak

# 检查归档目录
ls -la /data/dmarch/DMTEST
```

### 1.2 确认 dm.ini 存在

```bash
ls -la /data/dmdata/DMTEST/dm.ini
```

### 1.3 确认 dmrman 工具可用

```bash
/data/dm/bin/dmrman
```

---

## 2. 查看可恢复时间范围

### 2.1 列出所有全量备份

```bash
ls -la /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_*
```

输出示例：

```
drwxr-xr-x 3 dmdba dmdba 4096 Jun 10 01:05  DB_DMTEST_FULL_2026_06_01_01_05_19
drwxr-xr-x 3 dmdba dmdba 4096 Jun 10 01:05  DB_DMTEST_FULL_2026_06_05_01_05_19
drwxr-xr-x 3 dmdba dmdba 4096 Jun 10 01:05  DB_DMTEST_FULL_2026_06_10_01_05_19
```

### 2.2 列出所有增量备份

```bash
ls -la /data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_*
```

### 2.3 列出所有归档日志

```bash
ls -la /data/dmarch/DMTEST/ARCHIVE_LOCAL1_*
```

### 2.4 查看备份集信息（可选）

```bash
/data/dm/bin/dmrman CTLSTMT="BACKUP INFO '/data/dmbak/DMTEST/bak/DB_DMTEST_FULL_2026_06_10_01_05_19';"
```

---

## 3. 停止数据库服务

### 3.1 使用 systemctl 停止

```bash
systemctl stop DmServiceDMTEST
```

### 3.2 验证数据库进程已停止

```bash
# 检查 dmserver 进程
pgrep -f "dmserver"

# 如果仍在运行，强制终止
pkill -9 -f "dmserver"
```

### 3.3 停止 DMAP 进程（如有）

```bash
pkill -9 -f "dmap"
```

### 3.4 确认所有进程已停止

```bash
pgrep -f "dmserver"
# 无输出表示已停止
```

---

## 4. 备份当前数据

### 4.1 创建备份目录

```bash
mkdir -p /data/dmdata/DMTEST_broken_$(date +%Y%m%d_%H%M%S)
```

### 4.2 复制所有数据文件

```bash
cp -r /data/dmdata/DMTEST/* /data/dmdata/DMTEST_broken_$(date +%Y%m%d_%H%M%S)/
```

### 4.3 验证备份完整性

```bash
ls -la /data/dmdata/DMTEST_broken_*/SYSTEM.DBF
```

---

## 5. 启动 DMAP 服务

DMAP 是达梦数据库的备份恢复辅助服务。

### 5.1 检查 DMAP 是否已在运行

```bash
pgrep -f "dmap"
```

### 5.2 启动 DMAP

```bash
/data/dm/bin/dmap &
```

### 5.3 等待 DMAP 启动完成

```bash
sleep 2
pgrep -f "dmap"
```

---

## 6. 恢复全量备份

### 6.1 确定要使用的全量备份

```bash
# 查看最新全量备份
latest_full=$(ls -d /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_* | sort | tail -1)
echo "最新全量备份: $latest_full"
```

### 6.2 校验备份集完整性（可选但推荐）

```bash
/data/dm/bin/dmrman CTLSTMT="CHECK BACKUPSET '$latest_full';"
```

### 6.3 执行全量恢复

```bash
/data/dm/bin/dmrman CTLSTMT="RESTORE DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$latest_full';"
```

### 6.4 带增量链的恢复（如有增量备份）

如果需要同时恢复全量和增量备份，使用 WITH BACKUPDIR 参数：

```bash
/data/dm/bin/dmrman CTLSTMT="RESTORE DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$latest_full' WITH BACKUPDIR '/data/dmbak/DMTEST/bak';"
```

---

## 7. 应用增量备份

如果第6步使用了 WITH BACKUPDIR，此步骤可跳过。

### 7.1 确定基座全量备份时间

```bash
full_date="2026_06_05"  # 基座全量备份日期
full_sec=$(date -d "${full_date//_/-} 01:05:19" +%s)
```

### 7.2 找出需要应用的增量备份

```bash
for bak in /data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_*; do
    inc_date=$(basename "$bak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    inc_sec=$(date -d "${inc_date//_/-} 01:05:19" +%s)
    if [ "$inc_sec" -gt "$full_sec" ]; then
        echo "待应用: $bak"
    fi
done
```

### 7.3 逐个应用增量备份

```bash
increment_bak="/data/dmbak/DMTEST/bak/DB_DMTEST_INCREMENT_2026_06_06_01_05_19"
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$increment_bak';"
```

---

## 8. 应用归档日志

### 8.1 恢复到最新状态

```bash
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' WITH ARCHIVEDIR '/data/dmarch/DMTEST';"
```

### 8.2 恢复到指定时间点

```bash
time_point="2026-06-10 12:00:00"
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' WITH ARCHIVEDIR '/data/dmarch/DMTEST' UNTIL TIME '$time_point';"
```

---

## 9. 更新 DB_MAGIC

```bash
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' UPDATE DB_MAGIC;"
```

---

## 10. 修复数据目录权限

恢复后的数据文件属于 root，需要修改为数据库运行用户。

### 10.1 确定数据库运行用户

```bash
grep '^User=' /etc/systemd/system/DmServiceDMTEST.service
```

### 10.2 修改数据目录所有者

```bash
chown -R dmdba:dmdba /data/dmdata/DMTEST
```

---

## 11. 启动数据库服务

### 11.1 使用 systemctl 启动

```bash
systemctl start DmServiceDMTEST
```

### 11.2 等待数据库启动

```bash
sleep 5
```

### 11.3 检查数据库进程

```bash
pgrep -f "dmserver.*DMTEST"
```

---

## 12. 验证数据库状态

### 12.1 检查端口监听

```bash
ss -tln | grep ":5236 "
```

### 12.2 连接数据库验证

```bash
/data/dm/bin/disql SYSDBA/'your_password'@localhost:5236 <<'SQLEOF'
SELECT '状态' 项目, STATUS$ || '-' || MODE$ 结果 FROM V$INSTANCE;
SELECT '时间' 项目, TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS') 结果 FROM DUAL;
SELECT '归档' 项目, ARCH_MODE 结果 FROM V$DATABASE;
ALTER DATABASE OPEN;
SELECT 'OPEN状态' 项目, STATUS$ || '-' || MODE$ 结果 FROM V$INSTANCE;
EXIT;
SQLEOF
```

### 12.3 验证结果判断

| 状态值 | 说明 |
|--------|------|
| `MOUNT-ACTIVE` | 数据库处于 mount 模式，未打开 |
| `OPEN-ACTIVE` | 数据库正常运行 |

---

## 13. 恢复后备份

恢复完成后，建议立即执行一次全量备份。

### 13.1 创建备份目录

```bash
backup_dir="/data/dmbak/DMTEST/bak/DB_DMTEST_FULL_$(date +%Y_%m_%d)_01_05_19"
mkdir -p "$backup_dir"
```

### 13.2 执行全量备份

```bash
/data/dm/bin/dmrman CTLSTMT="BACKUP DATABASE '/data/dmdata/DMTEST/dm.ini' FULL TO '$backup_dir' BACKUPINFO '恢复后手动备份';"
```

---

## 快速恢复命令汇总

以下是最常用的恢复到最新状态的完整命令序列：

```bash
# 1. 停止数据库
systemctl stop DmServiceDMTEST
pkill -9 -f "dmserver"

# 2. 备份当前数据
mkdir -p /data/dmdata/DMTEST_broken_$(date +%Y%m%d_%H%M%S)
cp -r /data/dmdata/DMTEST/* /data/dmdata/DMTEST_broken_*/

# 3. 启动 DMAP
/data/dm/bin/dmap &

# 4. 确定最新全量
latest_full=$(ls -d /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_* | sort | tail -1)

# 5. 恢复全量+增量
/data/dm/bin/dmrman CTLSTMT="RESTORE DATABASE '/data/dmdata/DMTEST/dm.ini' FROM BACKUPSET '$latest_full' WITH BACKUPDIR '/data/dmbak/DMTEST/bak';"

# 6. 应用归档
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' WITH ARCHIVEDIR '/data/dmarch/DMTEST';"

# 7. 更新 DB_MAGIC
/data/dm/bin/dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DMTEST/dm.ini' UPDATE DB_MAGIC;"

# 8. 修复权限
chown -R dmdba:dmdba /data/dmdata/DMTEST

# 9. 启动数据库
systemctl start DmServiceDMTEST

# 10. 验证
/data/dm/bin/disql SYSDBA/'your_password'@localhost:5236 <<'SQLEOF'
SELECT STATUS$ FROM V$INSTANCE;
ALTER DATABASE OPEN;
SELECT STATUS$ FROM V$INSTANCE;
EXIT;
SQLEOF
```

---

## 常见问题

### Q1: 恢复失败提示 "N_MAGIC 不匹配"

**原因**: 增量备份的基座全量与当前恢复的全量不一致。

**解决**: 确保使用正确的基座全量备份进行恢复。

### Q2: 归档日志应用失败

**原因**: 归档日志时间范围不连续或缺失。

**解决**: 检查归档日志完整性，确认备份链完整。

### Q3: 数据库启动后无法 OPEN

**原因**: 可能需要执行 `ALTER DATABASE OPEN`。

**解决**:
```bash
/data/dm/bin/disql SYSDBA/'password'@localhost:5236 <<'SQLEOF'
ALTER DATABASE OPEN;
EXIT;
SQLEOF
```

### Q4: 权限问题导致恢复失败

**原因**: dmrman 以 root 运行，恢复的文件属于 root，但服务以 dmdba 运行。

**解决**: 在启动服务前执行 `chown -R dmdba:dmdba /data/dmdata/DMTEST`

---

## 参考链接

- [达梦数据库官方文档](https://www.dameng.com/document)
- dmrman 工具使用说明
