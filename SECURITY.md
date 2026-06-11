# 安全说明

本文档提供达梦数据库恢复脚本的安全使用建议。

---

## 目录

- [密码安全](#密码安全)
- [文件权限](#文件权限)
- [日志安全](#日志安全)
- [网络安全](#网络安全)
- [备份安全](#备份安全)
- [审计追踪](#审计追踪)

---

## 密码安全

### 问题

脚本中明文存储数据库密码存在安全风险：

```bash
DB_PASS="ezzk%Od1H86qmMl9@P["
```

### 建议措施

#### 方案1：使用环境变量

```bash
# 在 /etc/profile 或 ~/.bashrc 中添加
export DM_DB_PASS="your_secure_password"

# 脚本中使用
DB_PASS="${DM_DB_PASS}"
```

#### 方案2：使用密码文件

```bash
# 创建密码文件（600权限）
echo "your_password" > ~/.dm_pass
chmod 600 ~/.dm_pass

# 脚本中读取
DB_PASS=$(cat ~/.dm_pass)
```

#### 方案3：使用 keyring

```bash
# 使用 secret-tool（Linux）或 keychain
DB_PASS=$(secret-tool lookup database password)
```

#### 方案4：交互式输入

修改脚本，使用 `read -s` 交互式输入密码：

```bash
read -s -p "请输入数据库密码: " DB_PASS
```

---

## 文件权限

### 脚本权限

```bash
# 脚本权限：755（所有者可执行）
chmod 755 dm_recover.sh

# 密码文件权限：600（仅所有者可读写）
chmod 600 ~/.dm_pass
```

### 数据目录权限

```bash
# 数据目录：700（仅 dmdba 用户可访问）
chmod 700 /data/dmdata/DMTEST

# 备份目录：700
chmod 700 /data/dmbak/DMTEST/bak

# 归档目录：700
chmod 700 /data/dmarch/DMTEST
```

### 属主设置

```bash
# 数据目录属于 dmdba 用户和组
chown -R dmdba:dmdba /data/dmdata/DMTEST
chown -R dmdba:dmdba /data/dmbak
chown -R dmdba:dmdba /data/dmarch
```

---

## 日志安全

### 日志包含敏感信息

恢复日志可能包含：
- 数据库密码（如果记录了 SQL 语句）
- 数据库结构信息
- 文件路径

### 建议措施

```bash
# 1. 日志目录权限
chmod 700 /data/dmbak/DMTEST/logs

# 2. 定期清理旧日志
find /data/dmbak/DMTEST/logs -name "recover_*.log" -mtime +30 -delete

# 3. 日志脱敏处理
# 脚本已在 SQL 输出中使用了不同的连接方式

# 4. 日志审计
# 记录谁、何时执行了恢复操作
echo "$(date) - $(whoami) - $(hostname)" >> /var/log/dm_recover_audit.log
```

---

## 网络安全

### 本地连接优先

```bash
# 使用本地 socket 或 localhost
disql SYSDBA/'password'@localhost:5236

# 避免使用远程连接
# 如果必须远程连接，使用 SSH 隧道
ssh -L 5236:localhost:5236 user@remote_host
```

### 防火墙配置

```bash
# 仅允许本地访问数据库端口
iptables -A INPUT -s 127.0.0.1 -p tcp --dport 5236 -j ACCEPT
iptables -A INPUT -p tcp --dport 5236 -j DROP
```

---

## 备份安全

### 备份文件权限

```bash
# 备份文件权限：600
chmod 600 /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_*

# 备份目录权限：700
chmod 700 /data/dmbak/DMTEST/bak
```

### 备份加密

```bash
# 使用 GPG 加密备份（示例）
gpg --symmetric --cipher-algo AES256 backup_file

# 或使用 LUKS 加密磁盘
cryptsetup luksFormat /dev/sdb1
```

### 备份完整性校验

```bash
# 生成校验和
sha256sum /data/dmbak/DMTEST/bak/DB_DMTEST_FULL_* > checksums.sha256

# 验证备份
sha256sum -c checksums.sha256
```

---

## 审计追踪

### 操作审计

建议在执行恢复前记录审计信息：

```bash
# 创建审计日志
AUDIT_LOG="/var/log/dm_recover_audit.log"

echo "========================================" >> $AUDIT_LOG
echo "恢复操作审计" >> $AUDIT_LOG
echo "时间: $(date)" >> $AUDIT_LOG
echo "用户: $(whoami)" >> $AUDIT_LOG
echo "主机: $(hostname)" >> $AUDIT_LOG
echo "恢复模式: $mode" >> $AUDIT_LOG
echo "目标时间点: $time_point" >> $AUDIT_LOG
echo "========================================" >> $AUDIT_LOG
```

### 数据库审计

启用达梦数据库审计功能：

```sql
-- 开启审计
SP_INIT_AUDIT_SYS(1);

-- 创建审计策略
CREATE AUDIT POLICY DB_RECOVERY_POLICY
    ACTIONS RECOVER, RESTORE, BACKUP
    WHEN '1=1';

-- 启用审计策略
ALTER AUDIT POLICY DB_RECOVERY_POLICY ENABLE;
```

---

## 安全检查清单

执行恢复操作前，请确认：

### 环境安全

- [ ] 运行脚本的用户权限最小化
- [ ] 数据目录权限正确设置
- [ ] 备份目录权限正确设置
- [ ] 密码已从脚本中移除或保护

### 操作安全

- [ ] 已备份当前数据
- [ ] 已验证备份完整性
- [ ] 已记录审计信息
- [ ] 已通知相关人员

### 恢复后安全

- [ ] 删除临时文件
- [ ] 验证数据库状态
- [ ] 检查访问日志
- [ ] 更新备份

---

## 应急响应

### 发现安全问题

1. **立即停止操作**
2. **评估影响范围**
3. **保护现场证据**
4. **报告安全事件**
5. **修复安全漏洞**

### 数据泄露响应

如果怀疑密码泄露：

```bash
# 1. 立即修改密码
disql SYSDBA/'old_password'@localhost:5236
SQL> ALTER USER SYSDBA IDENTIFIED BY 'new_password';

# 2. 检查访问日志
grep "SYSDBA" $DM_HOME/log/SYSTEM.log

# 3. 评估泄露范围
# 4. 通知受影响方
```

---

## 合规建议

### 数据保护

- 遵守组织的数据保护政策
- 记录数据恢复操作
- 限制恢复权限给授权人员

### 备份保留

- 遵循备份保留策略
- 安全处置旧备份
- 加密长期保存的备份

### 访问控制

- 最小权限原则
- 定期审查权限
- 使用特权访问管理

---

## 参考标准

- ISO 27001 信息安全管理
- NIST 网络安全框架
- GDPR 数据保护要求
- 行业特定的合规要求
