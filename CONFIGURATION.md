# 配置详解

本文档详细说明 `dm_recover.sh` 脚本中所有配置参数的作用及配置方法。

---

## 配置位置

所有配置位于脚本头部的 **配置区** 部分（第 11-30 行）：

```bash
# =============================================================================
# 配置区（根据实际情况修改）
# =============================================================================
DB_USER="SYSDBA"
DB_PASS="..."
# ... 其他配置
# =============================================================================
```

---

## 基础配置

### DB_USER

数据库连接用户名。

```bash
DB_USER="SYSDBA"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `SYSDBA` |
| 必需 | 是 |
| 说明 | 达梦数据库管理员账户 |

### DB_PASS

数据库连接密码。

```bash
DB_PASS="ezzk%Od1H86qmMl9@P["
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | 生产环境建议使用其他方式管理密码 |

⚠️ **安全警告**：密码明文存储存在安全风险，建议参考 [SECURITY.md](SECURITY.md) 中的安全建议。

---

### DM_HOME

达梦数据库软件安装目录。

```bash
DM_HOME="/data/dm"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `/data/dm` |
| 必需 | 是 |
| 说明 | 必须包含 `bin/dmrman` 和 `bin/disql` |

**验证方法：**

```bash
ls -la $DM_HOME/bin/dmrman
# 应显示 dmrman 可执行文件
```

---

### DM_DATA

数据库数据文件目录，包含 `dm.ini` 配置文件。

```bash
DM_DATA="/data/dmdata/DAMENG"
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | 必须包含 `dm.ini` 配置文件 |

**验证方法：**

```bash
ls -la $DM_DATA/dm.ini
# 应显示 dm.ini 文件
```

---

### DM_BAK

备份文件存储目录。

```bash
DM_BAK="/data/dmbak/DAMENG/bak"
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | 包含全量备份和增量备份子目录 |

**备份目录结构：**

```
DM_BAK/
├── DB_DAMENG_FULL_2026_06_01_01_05_19/      # 全量备份
├── DB_DAMENG_FULL_2026_06_05_01_05_19/
├── DB_DAMENG_INCREMENT_2026_06_02_01_05_19/ # 增量备份
├── DB_DAMENG_INCREMENT_2026_06_03_01_05_19/
└── ...
```

---

### DM_ARCH

归档日志存储目录。

```bash
DM_ARCH="/data/dmarch/DAMENG"
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | 包含 `ARCHIVE_LOCAL1_*` 格式的归档文件 |

**归档目录结构：**

```
DM_ARCH/
├── ARCHIVE_LOCAL1_2026-06-01_01-05-19.log
├── ARCHIVE_LOCAL1_2026-06-01_02-10-15.log
└── ...
```

---

### DB_SERVICE

达梦数据库 systemd 服务名称。

```bash
DB_SERVICE="DmServiceDAMENG"
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | 用于 systemctl 启停数据库 |

**验证方法：**

```bash
systemctl status $DB_SERVICE
```

---

### DB_PORT

数据库监听端口。

```bash
DB_PORT="5236"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `5236` |
| 必需 | 是 |
| 说明 | 必须与 dm.ini 中 `PORT_NUM` 配置一致 |

**验证方法：**

```bash
grep "PORT_NUM" $DM_DATA/dm.ini
```

---

## 高级配置

### AUTO_BACKUP

恢复完成后是否自动执行全量备份。

```bash
AUTO_BACKUP="no"
```

| 属性 | 可选值 | 说明 |
|------|--------|------|
| 默认值 | `no` | 不自动备份 |
| 说明 | `yes`/`no` | 生产环境建议设为 `no`，手动确认后再备份 |

---

### RECOVER_LOG

恢复日志文件路径。

```bash
RECOVER_LOG="/data/dmbak/DAMENG/recover_$(date +%Y%m%d_%H%M%S).log"
```

| 属性 | 值 |
|------|-----|
| 默认值 | 带时间戳的日志文件 |
| 必需 | 否 |
| 说明 | 每次运行生成新的日志文件 |

**日志内容：**

```
=== 恢复日志 ===
[INFO] 10:30:15 恢复全量备份...
[STEP] 10:30:16 停止数据库...
[INFO] 10:30:19 数据库已停止
...
```

---

### DMRMAN_TIMEOUT

dmrman 操作超时时间（秒）。

```bash
DMRMAN_TIMEOUT=7200
```

| 属性 | 值 | 说明 |
|------|-----|------|
| 默认值 | `7200` | 2小时 |
| 说明 | 正整数 | 设为 `0` 表示永不超时 |
| 适用场景 | 大备份集恢复 | 备份文件过大时需要增加此值 |

**场景建议：**

| 备份大小 | 建议超时值 |
|----------|-----------|
| < 100GB | 3600 (1小时) |
| 100GB - 500GB | 7200 (2小时) |
| 500GB - 1TB | 14400 (4小时) |
| > 1TB | 0 (不超时) |

---

## 完整配置示例

### 生产环境配置

```bash
# =============================================================================
# 配置区（生产环境）
# =============================================================================
DB_USER="SYSDBA"
DB_PASS="your_secure_password"
DM_HOME="/data/dm"
DM_DATA="/data/dmdata/DAMENG"
DM_BAK="/backup/dmbak/DAMENG/bak"
DM_ARCH="/backup/dmarch/DAMENG"
DB_SERVICE="DmServiceDAMENG"
DB_PORT="5236"

# 高级配置
AUTO_BACKUP="no"
RECOVER_LOG="/backup/dmbak/DAMENG/logs/recover_$(date +%Y%m%d_%H%M%S).log"
DMRMAN_TIMEOUT=7200
```

### 测试环境配置

```bash
# =============================================================================
# 配置区（测试环境）
# =============================================================================
DB_USER="SYSDBA"
DB_PASS="SYSDBA"
DM_HOME="/opt/dmdbms"
DM_DATA="/home/dmdba/data/DAMENG"
DM_BAK="/home/dmdba/backup/DAMENG/bak"
DM_ARCH="/home/dmdba/backup/DAMENG/arch"
DB_SERVICE="DmServiceDAMENG"
DB_PORT="5236"

# 高级配置
AUTO_BACKUP="yes"
RECOVER_LOG="/home/dmdba/backup/DAMENG/logs/recover_$(date +%Y%m%d_%H%M%S).log"
DMRMAN_TIMEOUT=3600
```

---

## 配置检查清单

执行恢复前，请确认以下配置正确：

- [ ] `DB_USER` - 数据库用户名正确
- [ ] `DB_PASS` - 数据库密码正确
- [ ] `DM_HOME` - 目录存在且包含 dmrman
- [ ] `DM_DATA` - 目录存在且包含 dm.ini
- [ ] `DM_BAK` - 目录存在且包含备份
- [ ] `DM_ARCH` - 目录存在且包含归档
- [ ] `DB_SERVICE` - 服务名称正确
- [ ] `DB_PORT` - 端口与 dm.ini 一致

---

## 路径规范

### 绝对路径

所有路径配置必须使用 **绝对路径**，不可使用相对路径：

```bash
# 正确
DM_HOME="/data/dm"
DM_DATA="/data/dmdata/DAMENG"

# 错误
DM_HOME="./dm"
DM_DATA="../data/dmtrain"
```

### 路径权限

确保运行脚本的用户有足够权限访问以下路径：

| 路径 | 所需权限 | 说明 |
|------|----------|------|
| `DM_HOME` | 读+执行 | 读取 dmrman 等工具 |
| `DM_DATA` | 读写 | 恢复数据文件 |
| `DM_BAK` | 读 | 读取备份文件 |
| `DM_ARCH` | 读 | 读取归档日志 |
| `RECOVER_LOG` 目录 | 写 | 创建日志文件 |

---

## 环境变量

脚本会自动设置以下环境：

| 变量 | 说明 |
|------|------|
| `DB_USER` | 数据库用户 |
| `DB_PASS` | 数据库密码 |
| `DM_HOME` | 达梦安装目录 |
| `DM_DATA` | 数据目录 |
| `DM_BAK` | 备份目录 |
| `DM_ARCH` | 归档目录 |
| `DB_SERVICE` | 服务名 |
| `DB_PORT` | 端口号 |
| `AUTO_BACKUP` | 自动备份开关 |
| `RECOVER_LOG` | 日志路径 |
| `DMRMAN_TIMEOUT` | 超时时间 |
| `RECOVER_EARLIEST_TIME` | 可恢复最早时间 |
| `RECOVER_LATEST_TIME` | 可恢复最晚时间 |

---

## reset_dm.sh 配置说明

### 配置位置

所有配置位于脚本头部的 **用户配置区** 部分（第 26-42 行）：

```bash
# =============================================================================
# 用户配置区域（根据实际环境修改）
# =============================================================================
OLD_SERVICE_NAME="DmServiceDMSERVER"
NEW_SERVICE_NAME="DmServiceDMSERVER"
DM_HOME="/data/dm"
# ... 其他配置
# =============================================================================
```

### 基础配置

#### OLD_SERVICE_NAME

旧的 systemd 服务名称，用于停止和卸载。

```bash
OLD_SERVICE_NAME="DmServiceDMSERVER"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `DmServiceDMSERVER` |
| 必需 | 是 |
| 说明 | 需要卸载的旧服务名 |

#### NEW_SERVICE_NAME

新的 systemd 服务名称。

```bash
NEW_SERVICE_NAME="DmServiceDMSERVER"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `DmServiceDMSERVER` |
| 必需 | 是 |
| 说明 | 新注册的服务名，通常与旧名相同 |

#### DM_HOME

达梦数据库软件安装目录。

```bash
DM_HOME="/data/dm"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `/data/dm` |
| 必需 | 是 |
| 说明 | 必须包含 `bin/dminit`、`bin/dmrman`、`bin/disql` |

#### DATA_DIR

数据文件根目录（不含实例名）。

```bash
DATA_DIR="/data/dmdata"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `/data/dmdata` |
| 必需 | 是 |
| 说明 | 脚本会在该目录下创建 `DAMENG` 子目录 |

#### ARCH_DIR

归档日志根目录。

```bash
ARCH_DIR="/data/dmarch"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `/data/dmarch` |
| 必需 | 是 |
| 说明 | 脚本会在该目录下创建 `DAMENG` 子目录 |

#### BAK_DIR

备份文件根目录。

```bash
BAK_DIR="/data/dmbak"
```

| 属性 | 值 |
|------|-----|
| 默认值 | `/data/dmbak` |
| 必需 | 是 |
| 说明 | 脚本会在该目录下创建 `DAMENG/bak` 子目录 |

#### SYSDBA_PWD

SYSDBA 用户密码。

```bash
SYSDBA_PWD='your_secure_password'
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | **生产环境必须修改**，建议使用强密码 |

#### SYSAUDITOR_PWD

SYSAUDITOR 用户密码。

```bash
SYSAUDITOR_PWD='your_secure_password'
```

| 属性 | 值 |
|------|-----|
| 默认值 | 无 |
| 必需 | 是 |
| 说明 | **生产环境必须修改** |

### 高级配置

#### ARCH_FILE_SIZE

单个归档文件大小（MB）。

```bash
ARCH_FILE_SIZE=1024
```

| 属性 | 值 | 说明 |
|------|-----|------|
| 默认值 | `1024` | 1GB |
| 说明 | 正整数 | 单个归档文件大小上限 |

#### ARCH_SPACE_LIMIT

归档空间总限制（MB）。

```bash
ARCH_SPACE_LIMIT=204800
```

| 属性 | 值 | 说明 |
|------|-----|------|
| 默认值 | `204800` | 200GB |
| 说明 | 正整数 | 归档空间满后自动覆盖旧归档 |

#### BACKUP_RETAIN_DAYS

备份保留天数。

```bash
BACKUP_RETAIN_DAYS=30
```

| 属性 | 值 | 说明 |
|------|-----|------|
| 默认值 | `30` | 30天 |
| 说明 | 正整数 | 超过此天数的备份将被自动清理 |

### 完整配置示例

#### 生产环境配置

```bash
# =============================================================================
# 用户配置区域（生产环境）
# =============================================================================
OLD_SERVICE_NAME="DmServiceDMSERVER"
NEW_SERVICE_NAME="DmServiceDMSERVER"
DM_HOME="/data/dm"
DATA_DIR="/data/dmdata"
ARCH_DIR="/data/dmarch"
BAK_DIR="/data/dmbak"
SYSDBA_PWD='StrongPassword123!'
SYSAUDITOR_PWD='StrongPassword123!'

ARCH_FILE_SIZE=1024
ARCH_SPACE_LIMIT=204800
BACKUP_RETAIN_DAYS=30
```

#### 测试环境配置

```bash
# =============================================================================
# 用户配置区域（测试环境）
# =============================================================================
OLD_SERVICE_NAME="DmServiceDMSERVER"
NEW_SERVICE_NAME="DmServiceDMSERVER"
DM_HOME="/opt/dmdbms"
DATA_DIR="/home/dmdba/data"
ARCH_DIR="/home/dmdba/arch"
BAK_DIR="/home/dmdba/backup"
SYSDBA_PWD='TEST123'
SYSAUDITOR_PWD='TEST123'

ARCH_FILE_SIZE=512
ARCH_SPACE_LIMIT=102400
BACKUP_RETAIN_DAYS=7
```

### 配置检查清单

执行初始化前，请确认以下配置正确：

- [ ] `DM_HOME` - 目录存在且包含 dminit
- [ ] `DATA_DIR` - 目录存在且可写
- [ ] `ARCH_DIR` - 目录存在且可写
- [ ] `BAK_DIR` - 目录存在且可写
- [ ] `SYSDBA_PWD` - 已设置强密码
- [ ] `SYSAUDITOR_PWD` - 已设置强密码
- [ ] `OLD_SERVICE_NAME` - 正确的旧服务名
- [ ] `NEW_SERVICE_NAME` - 正确的新服务名

### dminit 初始化参数（固定值）

脚本使用以下固定参数初始化数据库实例，**勿轻易修改**：

| 参数 | 值 | 说明 |
|------|-----|------|
| `PAGE_SIZE` | 32 | 页大小 32KB |
| `EXTENT_SIZE` | 32 | 簇大小 32 页 |
| `LOG_SIZE` | 1024 | 日志文件 1024MB |
| `CASE_SENSITIVE` | 1 | 大小写敏感 |
| `CHARSET` | 1 | UTF-8 字符集 |
| `PORT_NUM` | 5236 | 监听端口 |
