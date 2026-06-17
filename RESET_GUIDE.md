# reset_dm.sh 使用指南

本文档详细介绍 `reset_dm.sh` 脚本的功能、配置参数及使用方法。

---

## 目录

- [脚本简介](#脚本简介)
- [适用场景](#适用场景)
- [执行要求](#执行要求)
- [配置参数](#配置参数)
- [执行流程](#执行流程)
- [验证方法](#验证方法)
- [故障排查](#故障排查)

---

## 脚本简介

`reset_dm.sh` 是达梦数据库重新初始化脚本，用于在已安装达梦软件的服务器上**完全重建数据库实例**，并自动配置生产级参数、归档和备份作业。

**核心功能：**

- 停止并卸载旧的达梦服务
- 备份旧数据目录和归档目录
- 调用 `dminit` 初始化新实例（32K PAGE、1024M REDO LOG）
- 注册 systemd 服务
- 修改 `dm.ini` 参数（`COMPATIBLE_MODE=2`、`ARCH_INI=1` 等）
- 创建 `dmarch.ini` 归档配置（LOCAL1 线程，200GB 归档上限）
- 初始化作业环境，创建全量备份和增量备份作业

---

## 适用场景

- 测试环境 / 生产基线实例重建
- 从旧版本迁移后，用生产级规范重新初始化实例
- 需要在一台机器上规范四目录结构：
  - `DM_HOME=/data/dm`
  - 数据目录 `/data/dmdata/DAMENG`
  - 归档目录 `/data/dmarch/DAMENG`
  - 备份目录 `/data/dmbak/DAMENG/bak`

---

## 执行要求

- **必须以 root 执行**（脚本内部会 `su - dmdba` 调达梦命令，注册 systemd 服务也需要 root 权限）
- 目标目录 `/data/dm`、`/data/dmdata`、`/data/dmarch`、`/data/dmbak` 存在或可被脚本创建
- 磁盘预留至少 5GB 可用空间
- `dmdba` 用户和 `dinstall` 组已存在

---

## 配置参数

脚本头部「用户配置区」中的参数说明：

### 必改参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `OLD_SERVICE_NAME` | 旧的 systemd 服务名 | `DmServiceDMSERVER` |
| `NEW_SERVICE_NAME` | 新的 systemd 服务名（通常与旧名相同） | `DmServiceDMSERVER` |
| `DM_HOME` | 达梦安装目录 | `/data/dm` |
| `DATA_DIR` | 数据文件根目录 | `/data/dmdata` |
| `ARCH_DIR` | 归档日志根目录 | `/data/dmarch` |
| `BAK_DIR` | 备份文件根目录 | `/data/dmbak` |
| `SYSDBA_PWD` | SYSDBA 密码 | （必改，请设置强密码） |
| `SYSAUDITOR_PWD` | SYSAUDITOR 密码 | （必改，请设置强密码） |

### 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `ARCH_FILE_SIZE` | 单个归档文件大小（MB） | `1024` |
| `ARCH_SPACE_LIMIT` | 归档空间总限制（MB） | `204800`（200GB） |
| `BACKUP_RETAIN_DAYS` | 备份保留天数 | `30` |

### dminit 初始化参数（固定值，勿轻易修改）

| 参数 | 值 | 说明 |
|------|-----|------|
| `PAGE_SIZE` | 32 | 页大小 32KB |
| `EXTENT_SIZE` | 32 | 簇大小 32 页 |
| `LOG_SIZE` | 1024 | 日志文件 1024MB |
| `CASE_SENSITIVE` | 1 | 大小写敏感 |
| `CHARSET` | 1 | UTF-8 字符集 |
| `AUTO_OVERWRITE` | 2 | 自动覆盖冲突文件 |
| `PORT_NUM` | 5236 | 监听端口 |

---

## 执行流程

```
1. 停止并清理旧服务
   ├── systemctl stop/disable
   ├── dm_service_uninstaller.sh
   └── pkill -9 dmserver/dmap

2. 备份旧数据目录
   └── mv /data/dmdata/DAMENG → /data/dmdata/DAMENG.bak.YYYYMMDD_HHMMSS

3. 创建目录并设置权限
   └── mkdir -p + chown dmdba:dinstall

4. 初始化数据库实例
   └── dminit PATH=/data/dmdata DB_NAME=DAMENG ...

5. 注册 systemd 服务
   └── dm_service_installer.sh -t dmserver -dm_ini ...

6. 修改 dm.ini 参数
   ├── COMPATIBLE_MODE=2
   ├── PK_WITH_CLUSTER=0
   ├── CHECK_CONS_NAME=0
   └── ARCH_INI=1

7. 创建 dmarch.ini 归档配置

8. 启动数据库服务

9. 验证归档配置
   └── disql 执行 SWITCH LOGFILE，验证归档目录有文件

10. 配置备份作业
    ├── SP_INIT_JOB_SYS 初始化作业环境
    ├── bak_full：每周六 01:05 全量备份，清理超过 30 天备份
    └── bak_inc：周日至周五 01:05 增量备份，失败转全量

11. 验证数据库关键参数
    └── PAGE_SIZE、COMPATIBLE_MODE、ARCH_MODE 等
```

---

## 验证方法

脚本执行完成后，可手动验证以下内容：

### 1. 数据库状态

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e "SELECT STATUS$ FROM V\$INSTANCE;"
# 期望输出：OPEN
```

### 2. 归档模式

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e "SELECT ARCH_MODE FROM V\$DATABASE;"
# 期望输出：Y
```

### 3. 归档目录文件

```bash
ls -lh /data/dmarch/DAMENG/
# 期望：存在 ARCHIVE_LOCAL1_...log 文件
```

### 4. 关键参数

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e \
  "SELECT PARA_NAME, PARA_VALUE FROM V\$DM_INI \
   WHERE PARA_NAME IN ('COMPATIBLE_MODE','PK_WITH_CLUSTER','CHECK_CONS_NAME','ARCH_INI');"
# 期望：COMPATIBLE_MODE=2, PK_WITH_CLUSTER=0, CHECK_CONS_NAME=0, ARCH_INI=1
```

### 5. 备份作业

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e \
  "SELECT NAME, DESCRIBE FROM SYSJOB.SYSJOBS WHERE NAME IN ('BAK_FULL','BAK_INC');"
# 期望：两条记录均存在
```

---

## 故障排查

### 1. dminit 初始化失败

**症状：** 脚本在"初始化数据库实例"步骤退出。

**可能原因：**

- 数据目录权限不对（`dmdba` 无写权限）
- 磁盘空间不足
- 端口 5236 已被占用

**排查方法：**

```bash
ls -la /data/dmdata/
df -h /data/dmdata
netstat -tlnp | grep 5236
```

### 2. dmarch.ini 创建后归档不生效

**症状：** `V$DATABASE.ARCH_MODE` 显示 `N`。

**原因：** 仅创建 `dmarch.ini` 和设置 `ARCH_INI=1` 还不够，数据库必须在 **MOUNT 状态**下执行 `ALTER DATABASE ARCHIVELOG` 才能真正开启归档模式。

**注意：** 当前脚本通过 `ALTER SYSTEM SWITCH LOGFILE` 触发归档，如果 `ARCH_MODE` 为 `N`，需要手动执行：

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" <<'EOF'
SP_SET_PARA_VALUE(1, 'ARCH_INI', 1);
ALTER DATABASE MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
EOF
```

### 3. 备份作业未创建成功

**症状：** `SYSJOB.SYSJOBS` 中没有 `BAK_FULL` 和 `BAK_INC` 记录。

**排查方法：**

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e \
  "SELECT COUNT(1) FROM DBA_OBJECTS WHERE OBJECT_TYPE='SCH' AND OBJECT_NAME='SYSJOB';"
# 返回 0 表示作业环境未初始化
```

**解决方法：** 手动执行作业环境初始化：

```bash
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e "SP_INIT_JOB_SYS(1);"
```

### 4. 服务启动失败

**症状：** `systemctl start DmServiceDMSERVER` 失败。

**排查方法：**

```bash
systemctl status DmServiceDMSERVER -l --no-pager
cat /data/dmdata/DAMENG/dm.ini | grep -E "PORT|INSTANCE_NAME"
```

### 5. 密码含特殊字符导致 disql 连接失败

**症状：** `disql` 报错 `conn fail` 或认证失败。

**原因：** 密码中含 `@` 字符，与 `user/pwd@host` 连接串格式冲突。

**解决方法：** 修改 `SYSDBA_PWD`，将密码中的 `@` 替换为其他字符。

---

## 相关文档

- [README.md](README.md) — 项目主文档，包含快速开始和常见问题
- [dm_recover.sh](dm_recover.sh) — 数据库恢复脚本
