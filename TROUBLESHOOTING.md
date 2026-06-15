# 故障排查指南

本文档收集了常见问题及其解决方案。

---

## 目录

- [环境问题](#环境问题)
- [连接问题](#连接问题)
- [恢复问题](#恢复问题)
- [权限问题](#权限问题)
- [超时问题](#超时问题)
- [归档问题](#归档问题)
- [增量备份问题](#增量备份问题)

---

## 环境问题

### 问题1：DM_HOME 不存在

**错误信息：**

```
[ERROR] DM_HOME 不存在: /data/dm
```

**原因：** 配置的 DM_HOME 路径不正确或目录不存在。

**解决方案：**

```bash
# 1. 检查目录是否存在
ls -la /data/dm

# 2. 检查达梦安装目录
ls -la /opt/dmdbms

# 3. 更新脚本中的 DM_HOME 配置
vim dm_recover.sh
# 修改 DM_HOME="/opt/dmdbms"
```

---

### 问题2：dmrman 命令不存在

**错误信息：**

```
dmrman: command not found
```

**原因：** DM_HOME 配置错误或 dmrman 未安装。

**解决方案：**

```bash
# 1. 查找 dmrman 位置
find / -name dmrman -type f 2>/dev/null

# 2. 确认 DM_HOME 配置
echo $DM_HOME
ls -la $DM_HOME/bin/dmrman
```

---

### 问题3：dm.ini 不存在

**错误信息：**

```
[ERROR] dm.ini 不存在: /data/dmdata/DMTEST/dm.ini
```

**原因：** 数据目录配置错误或 dm.ini 文件丢失。

**解决方案：**

```bash
# 1. 查找 dm.ini 位置
find /data -name dm.ini 2>/dev/null

# 2. 检查数据目录
ls -la /data/dmdata/DMTEST/
```

---

## 连接问题

### 问题4：数据库端口未就绪

**错误信息：**

```
[STEP] 等待数据库就绪并验证...
  ▏ 等待数据库就绪 (15/15)...
[ERROR] 数据库进程已退出
```

**原因：** 数据库启动失败或端口配置不匹配。

**解决方案：**

```bash
# 1. 检查端口配置
grep "PORT_NUM" $DM_DATA/dm.ini

# 2. 检查端口监听
ss -tln | grep 5236

# 3. 检查数据库进程
ps -ef | grep dmserver

# 4. 查看数据库日志
journalctl -u DmServiceDMTEST -n 50
```

---

### 问题5：disql 连接失败

**错误信息：**

```
[-70036]: Connected to an inactive instance
```

**原因：** 数据库处于 MOUNT 状态。

**解决方案：**

```bash
# 连接并打开数据库
disql SYSDBA/'password'@localhost:5236
SQL> ALTER DATABASE OPEN;
SQL> SELECT STATUS$ FROM V$INSTANCE;
```

---

## 恢复问题

### 问题6：恢复失败 - 备份集校验不通过

**错误信息：**

```
[ERROR] 备份集校验失败！
```

**原因：** 备份文件损坏或版本不兼容。

**解决方案：**

```bash
# 1. 手动校验备份集
dmrman CTLSTMT="CHECK BACKUPSET '/path/to/backup';"

# 2. 使用其他备份集恢复
# 编辑脚本，选择其他全量备份

# 3. 如果有备份集备份，校验备份集本身
dmrman CTLSTMT="BACKUP INFO '/path/to/backup';"
```

---

### 问题7：N_MAGIC 不匹配

**错误信息：**

```
[ERROR] N_MAGIC mismatch
```

**原因：** 增量备份的基座全量与恢复的全量不一致。

**解决方案：**

```bash
# 1. 检查增量备份的基座信息
dmrman CTLSTMT="BACKUP INFO '/path/to/increment';"

# 2. 确保使用正确的基座全量
# 在脚本中选择正确的全量备份基座

# 3. 或使用 WITH BACKUPDIR 模式自动处理
# 选择模式1（恢复到最新状态），脚本会自动处理
```

---

### 问题8：REDO 值不匹配

**错误信息：**

```
[ERROR] REDO value mismatch
```

**原因：** 归档日志与恢复的数据不同步。

**解决方案：**

```bash
# 1. 确保选择了正确的全量备份
# 2. 检查归档日志是否完整
ls -la $DM_ARCH/

# 3. 使用模式3（仅恢复备份）跳过归档
# 或使用模式2（时间点恢复）配合正确的基座
```

---

## 权限问题

### 问题9：权限不足导致恢复失败

**错误信息：**

```
[ERROR] Permission denied
```

**原因：** 运行脚本的用户没有数据目录写权限。

**解决方案：**

```bash
# 1. 使用 root 或 dmdba 用户运行
# 2. 检查目录权限
ls -la /data/dmdata/DMTEST/

# 3. 修改权限
chown -R dmdba:dmdba /data/dmdata/DMTEST

# 4. 如果是恢复后的权限问题，脚本会自动修复
# 检查 start_db 函数中的权限修复逻辑
```

---

### 问题10：恢复后数据文件属主错误

**错误信息：**

```
[ERROR] 数据库启动失败
```

**原因：** dmrman 以 root 运行，恢复的文件属于 root，但服务以 dmdba 运行。

**解决方案：**

```bash
# 1. 手动修改权限
chown -R dmdba:dmdba /data/dmdata/DMTEST

# 2. 检查 systemd 服务配置
grep '^User=' /etc/systemd/system/DmServiceDMTEST.service

# 3. 重启服务
systemctl restart DmServiceDMTEST
```

---

## 超时问题

### 问题11：dmrman 操作超时

**错误信息：**

```
[ERROR] 操作超时（7200秒），可能是备份文件过大或磁盘性能问题
```

**原因：** 备份文件过大或磁盘性能不足。

**解决方案：**

```bash
# 1. 增加超时时间
vim dm_recover.sh
# 修改 DMRMAN_TIMEOUT=14400  # 4小时

# 2. 或设置为不超时
DMRMAN_TIMEOUT=0

# 3. 检查磁盘性能
hdparm -t /dev/sda
df -h

# 4. 考虑使用更快的存储
# SSD 或 NVMe 存储
```

---

### 问题12：DMAP 服务启动失败

**错误信息：**

```
[WARN] DMAP 服务启动失败，尝试使用内置模式...
```

**原因：** DMAP 程序不存在或启动异常。

**解决方案：**

```bash
# 1. 检查 dmap 程序
ls -la $DM_HOME/bin/dmap

# 2. 手动启动 DMAP
$DM_HOME/bin/dmap &

# 3. 检查 DMAP 进程
ps -ef | grep dmap

# 4. 脚本会自动降级到内置模式
```

---

## 归档问题

### 问题13：未找到归档日志

**错误信息：**

```
[WARN] 未找到归档日志
```

**原因：** 归档目录配置错误或归档被清理。

**解决方案：**

```bash
# 1. 检查归档目录
ls -la /data/dmarch/DMTEST/

# 2. 确认归档配置
grep "ARCH_MODE" $DM_DATA/dm.ini

# 3. 检查归档目录配置
grep "ARCH_DIR" $DM_DATA/dm.ini

# 4. 可以使用模式3（仅恢复备份）
```

---

### 问题14：归档日志不连续

**错误信息：**

```
[ERROR] 归档日志应用失败
```

**原因：** 归档日志缺失或被删除。

**解决方案：**

```bash
# 1. 检查归档文件是否完整
ls -la $DM_ARCH/ | head -20
ls -la $DM_ARCH/ | tail -20

# 2. 检查归档序列
# 归档文件应连续，不应有缺失

# 3. 如果归档确实不完整
# - 使用模式3（仅恢复备份）
# - 或恢复到最后一个完整归档的时间点
```

---

## 增量备份问题

### 问题15：未找到增量备份

**错误信息：**

```
增量备份数量: 0
```

**原因：** 增量备份目录配置错误或没有增量备份。

**解决方案：**

```bash
# 1. 检查备份目录
ls -la /data/dmbak/DMTEST/bak/

# 2. 查找增量备份
find /data/dmbak -name "DB_DMTEST_INCREMENT_*"

# 3. 确认增量备份命名规范
# 格式: DB_DMTEST_INCREMENT_YYYY_MM_DD_HH_MM_SS
```

---

### 问题16：增量备份未自动应用

**原因：** 使用了不正确的恢复模式。

**解决方案：**

```bash
# 1. 使用模式1（恢复到最新状态）
# 脚本会自动使用 WITH BACKUPDIR 应用所有增量

# 2. 或在模式3中选择"全部增量"选项
```

---

## 数据库状态问题

### 问题17：数据库处于 MOUNT 状态

**错误信息：**

```
STATUS$ = MOUNT
```

**解决方案：**

```bash
# 连接数据库
disql SYSDBA/'password'@localhost:5236

# 打开数据库
SQL> ALTER DATABASE OPEN;

# 验证状态
SQL> SELECT STATUS$ FROM V$INSTANCE;
```

---

### 问题18：数据库无法打开

**错误信息：**

```
[ERROR] Database opened, but not open successfully
```

**原因：** 可能需要执行恢复后打开操作。

**解决方案：**

```bash
# 强制打开数据库
disql SYSDBA/'password'@localhost:5236
SQL> ALTER DATABASE OPEN FORCE;

# 如果仍有问题，检查日志
SQL> SELECT * FROM V$TRX;
SQL> SELECT * FROM V$LOCK;
```

---

## 日志分析

### 查看恢复日志

```bash
# 1. 找到最新的日志文件
ls -lt /data/dmbak/DMTEST/*.log | head -5

# 2. 查看日志内容
cat /data/dmbak/DMTEST/recover_20260611_103015.log

# 3. 搜索错误信息
grep -E "ERROR|error|失败" /data/dmbak/DMTEST/recover_*.log
```

### 查看系统日志

```bash
# 数据库服务日志
journalctl -u DmServiceDMTEST -n 100

# 内核日志
dmesg | grep -i dm

# 系统日志
tail -f /var/log/messages
```

---

### 问题19：异机恢复时报错 DM[-8374] 归档路径无效

**错误信息：**

```
DM[-8374]:归档文件路径下未收集到有效的归档文件
```

**原因：** 异机恢复时，目标机器上没有原机器的归档日志。模式3正确配置后已无需处理此问题。

**解决方案：**

脚本已修复此场景。使用模式3「仅恢复备份，不应用归档」，脚本会自动处理：

1. 先执行 `RECOVER DATABASE`（无归档会报错，忽略）
2. 再执行 `RECOVER DATABASE UPDATE DB_MAGIC`（更新 DB_MAGIC 让库可启动）

如果手动执行 dmrman，命令如下：

```bash
# 1. 先执行普通恢复（无归档会失败，忽略即可）
dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DAMENG/dm.ini';"

# 2. 再执行 UPDATE DB_MAGIC
dmrman CTLSTMT="RECOVER DATABASE '/data/dmdata/DAMENG/dm.ini' UPDATE DB_MAGIC;"
```

---

### 问题20：达梦要求先执行 RECOVER 再执行 UPDATE DB_MAGIC

**错误信息：**

```
RMAN[-8308]:需要先执行RECOVER DATABASE操作，再执行RECOVER DATABASE UPDATE DB_MAGIC操作
```

**原因：** 达梦要求必须先执行不带参数的 `RECOVER DATABASE`，再执行 `UPDATE DB_MAGIC`，两步缺一不可。

**解决方案：**

按照问题19中的两步命令顺序执行，先普通恢复，再 UPDATE DB_MAGIC。脚本已按此顺序正确处理。

---

## 获取帮助

如果问题仍未解决：

1. 收集以下信息：
   - 完整的错误信息
   - 恢复日志文件
   - dm.ini 配置
   - 数据库版本信息

2. 通过 GitHub Issues 提交问题

3. 参考 [达梦官方文档](https://www.dameng.com/document)
