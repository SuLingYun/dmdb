# rsync + inotify 实时文件同步工具

本文档详细介绍 `rsync-inotify-sync.sh` 脚本的功能、配置及使用方法。

---

## 目录

- [脚本简介](#脚本简介)
- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [配置说明](#配置说明)
- [使用指南](#使用指南)
- [systemd 服务管理](#systemd-服务管理)
- [故障排查](#故障排查)

---

## 脚本简介

`rsync-inotify-sync.sh` 是一款轻量级的实时文件同步工具，通过 rsync + inotify 实现文件变更的实时同步。支持本地服务器（数据源）和备份服务器（接收端）两种部署模式，可同时管理多台服务器的备份任务。

**核心场景：**
- 数据库数据目录实时同步到备份服务器
- 应用文件实时备份
- 多服务器文件一致性同步

---

## 功能特性

### 两种工作模式

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **本地服务器（模式1）** | 监控本地目录变化，实时同步到远程备份服务器 | 数据源服务器 |
| **备份服务器（模式2）** | 接收多个本地服务器的同步数据 | 备份中心服务器 |

### 核心功能

| 功能 | 说明 |
|------|------|
| **实时同步** | inotify 监控文件变化，rsync 实时推送变更 |
| **增量同步** | 仅传输变更的文件内容，带宽占用低 |
| **断点续传** | rsync 支持断点续传，网络中断不影响 |
| **systemd 管理** | 支持 systemctl 管理服务，开机自启 |
| **多平台支持** | 麒麟V10、CentOS/RHEL 7-9、Ubuntu、Debian、Alpine 等 |
| **自动安装依赖** | 自动检测并安装 rsync、inotify-tools |
| **多模块管理** | 备份服务器支持多个数据源模块 |
| **日志记录** | 完整操作日志，便于排查问题 |

### 安全特性

- 密码文件权限 600，仅 root 可访问
- rsyncd 认证用户 + 密码双重验证
- IP 白名单控制（hosts allow）
- chroot 隔离

---

## 系统要求

### 操作系统

- 麒麟 V10
- CentOS/RHEL 7-9
- Ubuntu 18.04+
- Debian 9+
- Alpine Linux
- 其他 Linux 发行版

### 依赖组件

| 组件 | 说明 | 安装方式 |
|------|------|----------|
| rsync | 文件同步工具 | 系统包管理器 |
| inotify-tools | 文件监控工具 | 脚本自动安装/源码编译 |

### 硬件要求

- CPU: 1核+
- 内存: 512MB+
- 磁盘: 根据备份数据量

---

## 快速开始

### 1. 下载脚本

```bash
# 克隆仓库
git clone <repository-url>
cd dmdb-recovery

# 添加执行权限
chmod +x rsync-inotify-sync.sh
```

### 2. 以 root 身份运行

```bash
./rsync-inotify-sync.sh
```

### 3. 选择角色

```
╔═══════════════════════════════════════════════════════════════╗
║         rsync + inotify 实时文件同步工具 v3.4                ║
║                                                               ║
║   模式1: 本地服务器（数据源）                                 ║
║   模式2: 备份服务器（接收端）- 支持多个数据源                  ║
║                                                               ║
║   两种模式均通过 systemd 管理                                  ║
╚═══════════════════════════════════════════════════════════════╝

选择角色：
  1 - 本地服务器（数据源）
  2 - 备份服务器（接收端）
```

### 4. 配置示例

#### 场景一：配置本地服务器（数据源）

```bash
► IP [192.168.1.100]: 192.168.1.200
► 端口 [873]:
► 模块名 [backup]: db_backup
► 本地同步目录 [/data/backup/]: /data/dmdata/DAMENG
► 用户名 [rsync_backup]:
► 密码: ********
► 确认: ********
► 监听事件 [modify,delete,create,attrib,move]:
► rsync参数 [-azP --delete]:
► 排除文件（回车跳过）: *.tmp *.swp
```

#### 场景二：配置备份服务器（接收端）

```bash
► 模块名 [backup]: db_backup
► 目录 [/data/backup/]: /data/backup/dmdata
► 端口 [873]:
► 用户名 [rsync_backup]:
► 密码: ********
► 确认: ********
► IP [192.168.0.0/16]: 192.168.1.0/24
```

---

## 配置说明

### 本地服务器配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 备份服务器 IP | rsync 目标服务器地址 | 192.168.1.100 |
| 端口 | rsync 服务端口 | 873 |
| 模块名称 | 备份服务器定义的模块名 | backup |
| 本地目录 | 要同步的本地目录 | /data/backup/ |
| 用户名 | rsync 认证用户 | rsync_backup |
| 密码 | rsync 认证密码 | （用户输入） |
| 监听事件 | inotify 监听的事件 | modify,delete,create,attrib,move |
| rsync 参数 | rsync 同步参数 | -azP --delete |
| 排除文件 | 不同步的文件模式 | （可空白） |

### 备份服务器配置项

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| 模块名称 | 本地服务器的模块标识 | backup |
| 存储目录 | 接收文件的存储路径 | /data/backup/ |
| 端口 | rsyncd 服务端口 | 873 |
| 用户名 | rsync 认证用户 | rsync_backup |
| 密码 | rsync 认证密码 | （用户输入） |
| 允许 IP | 允许连接的客户端 IP | 192.168.0.0/16 |

### 监听事件类型

| 事件 | 说明 |
|------|------|
| modify | 文件内容被修改 |
| create | 文件被创建 |
| delete | 文件被删除 |
| attrib | 文件属性变更（权限、时间等） |
| move | 文件被移动 |

### rsync 参数说明

| 参数 | 说明 |
|------|------|
| -a | 归档模式（保留权限、时间等） |
| -z | 压缩传输 |
| -P | 显示进度 |
| --delete | 删除目标目录中多余的文件 |

---

## 使用指南

### 首次配置

```bash
# 1. 运行脚本
./rsync-inotify-sync.sh

# 2. 选择模式（1=本地服务器，2=备份服务器）
# 3. 按提示完成配置
# 4. 确认配置并启动服务
```

### 已有配置的操作

```bash
# 本地服务器已有配置时
./rsync-inotify-sync.sh
# 会提示：
#   1 - 查看服务状态和日志
#   2 - 重新配置（覆盖当前配置）
#   3 - 卸载
#   q - 退出
```

### 常用命令

```bash
# 启动服务
./rsync-inotify-sync.sh start

# 停止服务
./rsync-inotify-sync.sh stop

# 重启服务
./rsync-inotify-sync.sh restart

# 查看状态
./rsync-inotify-sync.sh status

# 查看日志
./rsync-inotify-sync.sh logs

# 卸载
./rsync-inotify-sync.sh uninstall
```

---

## systemd 服务管理

### 本地服务器

```bash
# 启动
systemctl start rsync-sync

# 停止
systemctl stop rsync-sync

# 重启
systemctl restart rsync-sync

# 状态
systemctl status rsync-sync

# 开机自启
systemctl enable rsync-sync

# 禁用开机自启
systemctl disable rsync-sync
```

### 备份服务器

```bash
# 启动
systemctl start rsyncd

# 停止
systemctl stop rsyncd

# 重启
systemctl restart rsyncd

# 状态
systemctl status rsyncd

# 开机自启
systemctl enable rsyncd

# 禁用开机自启
systemctl disable rsyncd
```

### 日志位置

| 服务 | 日志文件 |
|------|----------|
| rsync-sync（本地） | /opt/rsync-sync/sync.log |
| rsyncd（备份） | /var/log/rsyncd.log |

---

## 故障排查

### 问题1：rsync 命令不存在

**错误信息：**
```
rsync: command not found
```

**解决方案：**
```bash
# CentOS/RHEL
yum install -y rsync

# Ubuntu/Debian
apt-get install -y rsync

# Alpine
apk add rsync
```

---

### 问题2：inotifywait 命令不存在

**错误信息：**
```
inotifywait: command not found
```

**解决方案：**

脚本会自动尝试安装，如果自动安装失败：

```bash
# CentOS/RHEL（需要 EPEL）
yum install -y epel-release
yum install -y inotify-tools

# Ubuntu/Debian
apt-get install -y inotify-tools

# Alpine
apk add inotify-tools
```

---

### 问题3：连接失败

**错误信息：**
```
@ERROR: auth failed on module xxx
```

**可能原因：**
1. 用户名或密码不正确
2. 备份服务器模块名不匹配
3. IP 不在允许列表中

**解决方案：**
```bash
# 1. 检查用户名密码
cat /etc/rsyncd.secrets

# 2. 检查模块名
grep "^\[module_name\]" /etc/rsyncd.conf

# 3. 检查 IP 允许列表
grep "hosts allow" /etc/rsyncd.conf
```

---

### 问题4：权限拒绝

**错误信息：**
```
permission denied: xxx
```

**解决方案：**
```bash
# 1. 检查目录权限
ls -la /data/backup/

# 2. 确保属主正确
chown -R root:root /data/backup/

# 3. 检查密码文件权限
chmod 600 /etc/rsync.password
chmod 600 /etc/rsyncd.secrets
```

---

### 问题5：磁盘空间不足

**错误信息：**
```
No space left on device
```

**解决方案：**
```bash
# 1. 检查磁盘空间
df -h

# 2. 清理不需要的文件
rm -rf /data/backup/old/*

# 3. 扩展磁盘空间
```

---

### 问题6：同步延迟或不同步

**可能原因：**
1. 网络问题
2. 文件变化太频繁
3. inotify watch limit 达到上限

**解决方案：**
```bash
# 1. 检查网络
ping <backup_server_ip>

# 2. 查看日志
tail -f /opt/rsync-sync/sync.log

# 3. 增加 inotify watch limit
echo 65536 > /proc/sys/fs/inotify/max_user_watches
```

---

### 问题7：服务启动失败

**错误信息：**
```
Failed to start rsync-sync.service
```

**解决方案：**
```bash
# 1. 查看详细错误
journalctl -u rsync-sync -n 50

# 2. 检查配置文件
cat /opt/rsync-sync/sync.conf

# 3. 重新配置
./rsync-inotify-sync.sh
# 选择重新配置
```

---

## 高级配置

### 排除特定文件

在配置时设置排除模式：

```bash
# 示例：排除临时文件和日志
*.tmp *.log *.swp .git/
```

### 调整 inotify watch 数量

```bash
# 临时调整
echo 65536 > /proc/sys/fs/inotify/max_user_watches

# 永久调整（/etc/sysctl.conf）
echo "fs.inotify.max_user_watches = 65536" >> /etc/sysctl.conf
sysctl -p
```

### 调整 rsync 带宽限制

```bash
# 添加 --bwlimit 参数
# rsync参数 [-azP --delete --bwlimit=5000]
# 单位 KB/s
```

---

## 目录结构

```
/opt/rsync-sync/              # 本地服务器安装目录
├── sync.conf                 # 配置文件
├── sync-daemon.sh            # 同步守护进程
└── sync.log                  # 日志文件

/etc/rsync.password           # 本地服务器密码文件
/etc/rsyncd.secrets          # 备份服务器密码文件
/etc/rsyncd.conf             # 备份服务器配置文件
/etc/systemd/system/rsync-sync.service  # 本地服务器 systemd 服务
/etc/systemd/system/rsyncd.service       # 备份服务器 systemd 服务
```

---

## 相关文档

- [README.md](README.md) — 项目主文档
- [dm_recover.sh](dm_recover.sh) — 数据库恢复脚本
- [reset_dm.sh](reset_dm.sh) — 数据库初始化脚本
- [达梦数据库官方文档](https://www.dameng.com/document)
