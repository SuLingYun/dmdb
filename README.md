# DM-Database-Recovery

> 达梦数据库快速恢复工具集 | 文档由 Trae AI 辅助生成，代码经人工验证后用于生产环境

[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![Database](https://img.shields.io/badge/Database-DM%20Database-orange.svg)](https://www.dameng.com/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 目录

- [项目简介](#项目简介)
- [功能特性](#功能特性)
- [快速开始](#快速开始)
- [恢复模式](#恢复模式)
- [重新初始化](#重新初始化)
- [配置说明](#配置说明)
- [备份与归档命名规范](#备份与归档命名规范)
- [使用示例](#使用示例)
- [目录结构](#目录结构)
- [文档导航](#文档导航)
- [版本历史](#版本历史)
- [许可证](#许可证)
- [联系方式](#联系方式)

---

## 项目简介

**DM-Database-Recovery** 是达梦数据库的专业恢复工具集，专为生产环境设计。通过智能检测备份链、自动选择最优恢复策略，实现快速、可靠的数据库恢复。

### 核心价值

- ⚡ **快速恢复**：一键恢复到最新状态或指定时间点
- 🎯 **智能策略**：自动检测增量备份链，选择最优恢复路径
- 📊 **可视化进度**：实时显示恢复进度、速度和剩余时间
- 📝 **完整日志**：详细记录所有操作，便于审计和故障排查

### 适用场景

- 数据库故障恢复
- 数据误删除恢复
- 数据库迁移（同机/异机）
- 灾备演练
- 测试环境/生产基线实例重建
- 数据库参数规范化配置

---

## 功能特性

### 核心功能

| 功能 | 说明 |
|------|------|
| **三种恢复模式** | 恢复到最新状态、时间点恢复、仅恢复备份（支持无归档场景） |
| **两种备份模式** | dmrman 脱机全量备份、disql 联机全量备份 |
| **增量备份支持** | 自动检测并应用增量备份链，模式3支持手动选择部分增量 |
| **归档日志恢复** | 基于归档日志的精细化恢复，支持 UNTIL TIME 时间点恢复 |
| **WITH BACKUPDIR** | 一次性恢复全量+增量链，自动搜索增量备份 |
| **时间点恢复** | 精确恢复到指定时间点（YYYY-MM-DD HH:MI:SS） |
| **备份集校验** | 恢复前可选校验备份完整性（CHECK BACKUPSET） |

### 用户体验

| 功能 | 说明 |
|------|------|
| **可视化进度条** | 实时显示恢复进度、速度、剩余时间（解析 dmrman 输出） |
| **彩色终端输出** | 清晰的日志分级和颜色标识（INFO/WARN/ERROR/STEP） |
| **交互式恢复计划确认** | 执行前显示完整恢复计划，包括基座全量、增量列表、归档范围 |
| **详细日志记录** | 所有操作记录到带时间戳的日志文件（recover_YYYYMMDD_HHMMSS.log） |
| **智能基座选择** | 自动推荐最佳全量备份基座；如最新全量无归档覆盖，提示用户更换 |
| **安全确认机制** | 危险操作二次确认（备份集校验选择、恢复执行确认） |
| **可跳过数据备份** | 恢复前可选择是否备份当前数据目录，节省时间和空间 |
| **手动选择全量基座** | 支持在模式1/2中手动切换全量备份基座 |
| **增量选择（模式3）** | 支持全部增量/部分增量/不使用增量 三种选择 |

### 智能检测

- 自动检测增量备份并选择最优恢复策略（使用 WITH BACKUPDIR 或降级手动应用）
- 自动检测全量备份是否有归档覆盖（如最新全量晚于归档则提示更换）
- 自动识别最新归档时间（按文件名时间戳排序，不受文件修改时间影响）
- 自动选择适合目标时间点的全量基座（不晚于目标时间的最新全量）
- 自动检测 dmserver 和 dmap 进程状态，确保恢复前数据库已停止
- 自动检测数据目录权限并修复（root 恢复后修正为 dmdba 属主）

---

## 快速开始

### 前置条件

- 达梦数据库 V8 及以上
- dmrman 工具可用
- Bash 4.0+
- 有效的备份集和归档日志

### 执行恢复

```bash
# 1. 克隆或下载脚本
git clone <repository-url>
cd dmdb-recovery

# 2. 添加执行权限
chmod +x dm_recover.sh

# 3. 编辑配置（必须）
vim dm_recover.sh
# 修改 DB_USER, DB_PASS, DM_HOME, DM_DATA, DM_BAK, DM_ARCH 等参数

# 4. 执行恢复脚本
./dm_recover.sh
```

### 恢复流程

```
1. 环境检查
   ├── 验证 DM_HOME、备份目录、归档目录是否存在
   └── 检查 dm.ini 配置文件

2. 显示可恢复范围
   ├── 列出所有全量备份
   ├── 列出所有增量备份
   ├── 列出所有归档日志
   └── 计算可恢复时间范围

3. 选择恢复模式
   ├── 模式1: 恢复到最新状态
   ├── 模式2: 恢复到指定时间点
   ├── 模式3: 仅恢复备份，不应用归档（异机/无归档场景）
   ├── 模式4: 完整备份数据库（dmrman 脱机）
   └── 模式5: 完整备份数据库（disql 联机）

4. 执行恢复
   ├── 停止数据库
   ├── 启动 DMAP 服务
   ├── 选择是否备份当前数据（默认不备份，节省时间和空间）
   ├── 恢复全量备份
   ├── 应用增量备份
   ├── 应用归档日志（模式1/2）或 UPDATE DB_MAGIC（模式3）
   └── 更新 DB_MAGIC

5. 验证恢复
   ├── 启动数据库
   ├── 验证数据库状态
   └── 显示恢复摘要
```

---

## 恢复模式

### 模式1: 恢复到最新状态（推荐）

自动应用所有增量备份和归档日志，将数据库恢复到最新可用状态。

```
适用于：常规故障恢复、生产环境紧急恢复
```

**特点：**
- 使用 `RESTORE WITH BACKUPDIR` 一次性恢复全量+增量链
- 自动应用所有归档日志
- 全程自动化，用户只需确认

### 模式2: 恢复到指定时间点

精确恢复到用户指定的时间点，适用于数据误删除等场景。

```
适用于：数据误删除恢复、误操作恢复
```

**特点：**
- 自动选择最合适的全量备份基座
- 由归档日志精确推进到目标时间
- 跳过增量备份（由归档替代）

**时间格式：** `YYYY-MM-DD HH:MI:SS`

**示例：**
```
恢复时间点: 2026-06-10 12:00:00
```

### 模式3: 仅恢复备份

仅恢复数据文件，不应用归档日志，适用于归档损坏或不需要归档的场景。

```
适用于：归档日志损坏、仅需恢复数据文件
```

**特点：**
- 可选择是否应用增量备份
- 不应用归档日志
- 可手动选择部分增量

### 模式4: dmrman 脱机全量备份

在数据库关闭状态下，使用 dmrman 执行全量备份，适用于需要一致性备份的场景。

```
适用于：计划性全量备份、备份前确保数据一致
```

**特点：**
- 需要先停止数据库
- dmrman 脱机备份，数据一致性有保障
- 备份完成后自动启动数据库

### 模式5: disql 联机全量备份

在数据库运行状态下，使用 disql 执行联机全量备份，不需要停机。

```
适用于：生产环境不停机备份、每日例行备份
```

**特点：**
- 数据库保持运行，不影响业务
- 联机备份，自动包含备份期间产生的归档日志
- 备份过程中业务可正常访问

---

## 重新初始化

当现有的数据库实例需要**从零重建**（例如：基线环境出问题、迁移后参数不合规、或希望一次性重新规范参数 / 归档 / 备份作业）时，使用 `reset_dm.sh` 完成以下工作：

- 停止并卸载旧的 `DmService<DMSERVER>` 服务
- 将旧数据目录 / 归档目录备份为 `.bak.YYYYMMDD_HHMMSS` 后缀
- 调用 `dminit` 初始化全新的数据库实例（32K PAGE、1024M REDO LOG、SYSDBA / SYSAUDITOR 统一密码）
- 注册新的 systemd 服务
- 直接修改 `dm.ini`，打开 `ARCH_INI`，并设置 `COMPATIBLE_MODE=2`、`PK_WITH_CLUSTER=0`、`CHECK_CONS_NAME=0`
- 写入 `dmarch.ini`（LOCAL1 归档线程，单文件 1024MB，总归档上限 200GB）
- 启动数据库服务并验证归档生效（`ALTER SYSTEM SWITCH LOGFILE` 后可在 `/data/dmarch/DAMENG` 看到新归档）
- 通过 `SP_INIT_JOB_SYS` 初始化作业环境，并自动创建：
  - `bak_full`：每周六 01:05 执行全量备份，并清理超过 30 天的备份集
  - `bak_inc`：周日至周五 01:05 执行增量备份，失败则自动切回全量备份
- 最后汇总输出关键参数、数据 / 归档 / 备份目录、备份作业计划等信息

### 适用场景

- 测试环境 / 生产基线实例重建
- 从旧版本迁移后，重新用生产级规范初始化实例
- 希望在一台机器上规范 `DM_HOME=/data/dm`、数据目录 `/data/dmdata/DAMENG`、归档 `/data/dmarch/DAMENG`、备份 `/data/dmbak/DAMENG/bak` 的四目录结构

### 执行要求

- **必须以 root 执行**（脚本内部会 `su - dmdba` 调达梦命令，注册 systemd 服务也需要 root 权限）
- 目标目录 `/data/dm`、`/data/dmdata`、`/data/dmarch`、`/data/dmbak` 存在或可被脚本创建
- 磁盘预留至少 5GB 可用空间（`LOG_SIZE=1024MB` × 2 个日志文件 + 系统表空间 + 归档 / 备份的缓冲区）

### 执行步骤

```bash
# 1. 进入项目目录
cd /workspace

# 2. 授予执行权限
chmod +x reset_dm.sh

# 3. 根据需要修改脚本头部的「用户配置区」
vim reset_dm.sh
# ── 修改 DM_HOME / DATA_DIR / ARCH_DIR / BAK_DIR / SYSDBA_PWD / BACKUP_RETAIN_DAYS 等

# 4. 以 root 身份执行
./reset_dm.sh
```

执行成功后，输出末尾的汇总信息类似：

```
[INFO] 数据库重新初始化完成，所有参数符合生产环境要求。
[INFO] 服务名：DmServiceDMSERVER
[INFO] 连接地址：localhost:5236
[INFO] 数据目录：/data/dmdata/DAMENG
[INFO] 归档目录：/data/dmarch/DAMENG
[INFO] 归档配置：TYPE=LOCAL, FILE_SIZE=1024MB, SPACE_LIMIT=204800MB
[INFO] 备份目录：/data/dmbak/DAMENG/bak
[INFO] 备份策略：全量(周六) + 增量(周日~周五)，保留天数 30
```

### 验证方法

脚本会自动执行以下验证步骤，也可以手动执行确认：

```bash
# 1. 归档模式
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e "SELECT ARCH_MODE FROM V\$DATABASE;"
# 期望：Y

# 2. 归档目录列表
ls -lh /data/dmarch/DAMENG/
# 期望：存在 ARCHIVE_LOCAL1_...log 文件

# 3. 关键参数
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e "SELECT PARA_NAME, PARA_VALUE FROM V\$DM_INI WHERE PARA_NAME IN ('COMPATIBLE_MODE','PK_WITH_CLUSTER','CHECK_CONS_NAME','ARCH_INI');"
# 期望：2 / 0 / 0 / 1

# 4. 备份作业
/data/dm/bin/disql "SYSDBA/<密码>@localhost:5236" -e "SELECT NAME, ENABLE, NEXT_DATE FROM SYSJOBS;"
# 期望：BAK_FULL、BAK_INC 均为启用状态，下次执行时间已调度
```

> 详细的参数说明、故障排查、手动执行方式请参考 [RESET_GUIDE.md](RESET_GUIDE.md)。

---

## 配置说明

脚本头部提供可配置参数，请根据实际环境修改。

### 基础配置

```bash
# 数据库连接信息
DB_USER="SYSDBA"              # 数据库用户名
DB_PASS="your_password"        # 数据库密码（生产环境建议使用其他方式管理）

# 达梦数据库路径
DM_HOME="/data/dm"             # 达梦安装目录
DM_DATA="/data/dmdata/DAMENG" # 数据文件目录（包含 dm.ini）
DM_BAK="/data/dmbak/DAMENG/bak"  # 备份文件目录
DM_ARCH="/data/dmarch/DAMENG"  # 归档日志目录

# 数据库服务配置
DB_SERVICE="DmServiceDAMENG"   # systemd 服务名
DB_PORT="5236"                 # 数据库监听端口

# 备份/归档文件名模式（根据实际命名习惯修改）
FULL_BAK_PATTERN="DB_DAMENG_FULL_*"        # 全量备份目录名模式
INC_BAK_PATTERN="DB_DAMENG_INCREMENT_*"     # 增量备份目录名模式
ARCH_PATTERN="ARCHIVE_LOCAL*"              # 归档日志文件名模式
```

### 高级配置

```bash
# 恢复后自动备份 (yes/no)
AUTO_BACKUP="no"

# 日志文件路径
RECOVER_LOG="/data/dmbak/DAMENG/recover_$(date +%Y%m%d_%H%M%S).log"

# dmrman 超时时间（秒），默认 7200 秒（2小时）
# 设为 0 表示不超时
DMRMAN_TIMEOUT=7200
```

### 配置检查清单

- [ ] DM_HOME 目录存在且包含 bin/dmrman
- [ ] DM_DATA 目录存在且包含 dm.ini
- [ ] DM_BAK 目录存在且包含备份文件
- [ ] DM_ARCH 目录存在且包含归档日志
- [ ] DB_SERVICE 服务已注册
- [ ] DB_PORT 与 dm.ini 中配置一致

---

## 备份与归档命名规范

脚本通过文件名模式自动识别备份和归档文件。默认模式如下，如你的命名习惯不同，请修改脚本配置区的对应变量。

### 全量备份目录

| 项目 | 说明 |
|------|------|
| **配置变量** | `FULL_BAK_PATTERN` |
| **默认模式** | `DB_DAMENG_FULL_*` |
| **命名格式** | `DB_<库名>_FULL_YYYY_MM_DD[_HH_MI_SS]` |
| **示例** | `DB_DAMENG_FULL_2026_06_10`、`DB_DAMENG_FULL_2026_06_10_01_05_19` |

**说明：**
- 目录名中必须包含 `YYYY_MM_DD` 格式的日期（下划线分隔）
- 时间部分 `_HH_MI_SS` 可选，但如果存在，脚本仍能正确识别日期
- 脚本按目录名排序选择，建议使用标准日期格式以保证排序正确

### 增量备份目录

| 项目 | 说明 |
|------|------|
| **配置变量** | `INC_BAK_PATTERN` |
| **默认模式** | `DB_DAMENG_INCREMENT_*` |
| **命名格式** | `DB_<库名>_INCREMENT_YYYY_MM_DD[_HH_MI_SS]` |
| **示例** | `DB_DAMENG_INCREMENT_2026_06_11`、`DB_DAMENG_INCREMENT_2026_06_11_12_00_00` |

**说明：**
- 命名规则与全量备份相同，仅前缀区分
- 增量备份的日期必须晚于其基座全量备份的日期

### 归档日志文件

| 项目 | 说明 |
|------|------|
| **配置变量** | `ARCH_PATTERN` |
| **默认模式** | `ARCHIVE_LOCAL*` |
| **命名格式** | `ARCHIVE_LOCAL<N>_YYYY-MM-DD_HH-MI-SS[.log]` |
| **示例** | `ARCHIVE_LOCAL1_2026-06-10_14-30-00.log`、`ARCHIVE_LOCAL2_2026-06-10_15-00-00` |

**说明：**
- 文件名中必须包含 `YYYY-MM-DD_HH-MI-SS` 格式的日期时间（日期用横杠、时间用横杠分隔、中间用下划线）
- `<N>` 为归档线程编号，可以是 1、2、3...，默认模式 `ARCHIVE_LOCAL*` 自动匹配所有线程
- 如果你的归档仅配置了单线程（`LOCAL1`），可以将模式收窄为 `ARCHIVE_LOCAL1_*` 以提高搜索精度
- 文件扩展名 `.log` 可选，脚本通过文件名前缀识别，不依赖扩展名

### 命名规范对照表

| 类型 | 格式要求 | 日期格式 | 分隔符 |
|------|----------|----------|--------|
| 全量备份目录 | 必须包含日期 | `YYYY_MM_DD` | 下划线 `_` |
| 增量备份目录 | 必须包含日期 | `YYYY_MM_DD` | 下划线 `_` |
| 归档日志文件 | 必须包含日期+时间 | `YYYY-MM-DD_HH-MI-SS` | 日期横杠 `-`，时间横杠 `-`，中间下划线 `_` |

### 目录结构示例

```
/data/dmbak/DAMENG/bak/
├── DB_DAMENG_FULL_2026_06_01/        # 全量备份（6月1日）
│   └── ... (备份数据文件)
├── DB_DAMENG_FULL_2026_06_10/        # 全量备份（6月10日）
│   └── ...
├── DB_DAMENG_INCREMENT_2026_06_11/   # 增量备份（6月11日）
└── DB_DAMENG_INCREMENT_2026_06_12/   # 增量备份（6月12日）

/data/dmarch/DAMENG/
├── ARCHIVE_LOCAL1_2026-06-10_00-00-00.log
├── ARCHIVE_LOCAL1_2026-06-10_01-00-00.log
├── ARCHIVE_LOCAL1_2026-06-10_14-30-00.log
└── ...
```

### 自定义命名

如果你的备份/归档命名与默认模式不同，只需修改脚本配置区的三个变量：

```bash
# 示例：你的备份命名为 DAMENG_FULL_20260610（无下划线日期）
FULL_BAK_PATTERN="DAMENG_FULL_*"

# 示例：你的归档命名为 dm_arch_20260610_143000.log（紧凑格式）
# 注意：归档文件时间戳格式必须为 YYYY-MM-DD_HH-MI-SS，
# 如果你的格式不同，需要同时修改脚本中的日期解析正则
ARCH_PATTERN="dm_arch_*"
```

> **重要提示：** 归档文件中的时间戳使用正则 `[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}` 解析。如果你的归档日期时间格式不同（如紧凑格式 `20260610_143000`），除修改 `ARCH_PATTERN` 外，还需调整脚本中的正则表达式。

---

## 使用示例

### 示例1：恢复到最新状态

```bash
$ ./dm_recover.sh

========================================
    达梦数据库 DM 快速恢复脚本
========================================

========== 可恢复时间范围 ==========
  最新全量备份: DB_DAMENG_FULL_2026_06_10_01_05_19
  增量备份数量: 3个
  归档日志数量: 156
  可恢复时间范围:
    最早: 2026-06-01 01:05:19
    最晚: 2026-06-10 18:30:00
======================================

请选择恢复模式:
  1) 恢复到最新状态 (推荐)
  2) 恢复到指定时间点
  3) 仅恢复备份，不应用归档
  4) 完整备份数据库（dmrman脱机）
  5) 完整备份数据库（disql联机）

请输入选项 (1/2/3/4/5): 1

恢复计划确认...
  基座全量: DB_DAMENG_FULL_2026_06_10_01_05_19
  增量备份: 3 个 (通过 RESTORE WITH BACKUPDIR 自动应用)
  归档日志: 应用到最新

是否备份当前数据目录? (yes/no, 默认no):

警告: 此操作将覆盖现有数据！
确认执行恢复? (yes/no): yes
```

### 示例2：恢复到指定时间点

```bash
请输入选项 (1/2/3/4/5): 2

请输入恢复时间点，格式: YYYY-MM-DD HH:MI:SS
  示例: 2026-06-10 12:00:00
  有效范围: 2026-06-01 01:05:19 ~ 2026-06-10 18:30:00

恢复时间点: 2026-06-10 12:00:00
时间点 2026-06-10 12:00:00 校验通过
```

### 示例3：异机恢复配置

```bash
# 异机恢复时，需要修改以下配置
DM_HOME="/opt/dmdbms"              # 目标机器的达梦安装目录
DM_DATA="/data/dmdata/DAMENG"     # 目标机器的数据目录
DM_BAK="/backup/dmbak/DAMENG/bak"  # 目标机器的备份目录（需提前复制）
DM_ARCH="/backup/dmarch/DAMENG"    # 目标机器的归档目录（需提前复制）
```

---

## 目录结构

```
dmdb-recovery/
├── dm_recover.sh           # 主恢复脚本（支持五种模式：恢复到最新/时间点/仅备份/脱机备份/联机备份）
├── reset_dm.sh             # 重新初始化脚本（重置实例 + 归档配置 + 自动备份作业）
├── README.md               # 项目说明文档
├── RESET_GUIDE.md          # reset_dm.sh 使用指南
├── LICENSE                 # MIT 许可证
├── CHANGELOG.md            # 变更日志
├── CONTRIBUTING.md         # 贡献指南
├── MANUAL_RECOVERY.md      # 手动恢复详细指南
├── TROUBLESHOOTING.md      # 故障排查指南
├── CONFIGURATION.md        # 配置详解
└── SECURITY.md             # 安全说明
```

---

## 文档导航

| 文档 | 说明 |
|------|------|
| [README.md](README.md) | 项目主文档，包含概述和快速开始 |
| [MANUAL_RECOVERY.md](MANUAL_RECOVERY.md) | 手动执行恢复的详细步骤说明 |
| [CONFIGURATION.md](CONFIGURATION.md) | 配置参数详解 |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | 常见问题与解决方案 |
| [SECURITY.md](SECURITY.md) | 安全使用建议 |
| [CHANGELOG.md](CHANGELOG.md) | 版本变更记录 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南 |

---

## 版本历史

### v1.0.0 (2026-06-11)

- 初始版本发布
- 支持三种恢复模式
- 实现可视化进度条
- 支持 WITH BACKUPDIR 增量恢复
- 支持时间点恢复
- 完整的日志记录系统

---

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

---

## 联系方式

- 项目维护者：数据库管理员
- 生成工具：Trae AI
- 问题反馈：通过 GitHub Issues 提交

---

## 免责声明

本工具用于数据库恢复操作，使用前请确保：
1. 已备份当前数据
2. 已验证备份完整性
3. 充分理解恢复操作的影响
4. 在测试环境验证后再用于生产环境

**作者不对因使用本工具造成的任何数据损失负责。**
