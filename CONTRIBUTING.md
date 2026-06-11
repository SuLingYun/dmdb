# 贡献指南

感谢您对 DM-Database-Recovery 项目的兴趣！我们欢迎任何形式的贡献。

---

## 如何贡献

### 报告问题

如果您发现任何问题或有功能建议，请通过 GitHub Issues 提交：

1. 搜索现有 Issues，确保问题未被报告
2. 创建新 Issue，选择合适的模板
3. 详细描述问题或建议
4. 提供复现步骤（如适用）

### 提交代码

1. **Fork 本仓库**
2. **创建特性分支**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **提交更改**
   ```bash
   git commit -m "Add: 添加新功能描述"
   ```
4. **推送到分支**
   ```bash
   git push origin feature/your-feature-name
   ```
5. **创建 Pull Request**

---

## 代码规范

### Shell 脚本规范

- 使用 `#!/bin/bash` 作为脚本解释器
- 变量名使用大写字母
- 函数名使用下划线分隔的小写字母
- 总是使用 `local` 声明局部变量
- 使用双引号包裹变量引用
- 使用 `set -e` 会在命令失败时退出

### 提交信息规范

采用 conventional commits 格式：

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

**Type 类型：**

| Type | Description |
|------|-------------|
| `feat` | 新功能 |
| `fix` | 问题修复 |
| `docs` | 文档变更 |
| `style` | 代码格式（不影响功能） |
| `refactor` | 代码重构 |
| `test` | 测试相关 |
| `chore` | 构建/工具变更 |

**示例：**

```
feat(recovery): 添加异机恢复支持

- 支持配置目标机器路径
- 添加跨平台路径处理

Closes #123
```

---

## 开发设置

### 环境要求

- Bash 4.0+
- 达梦数据库 DM 8.0+
- Linux 操作系统

### 本地测试

```bash
# 克隆仓库
git clone https://github.com/your-username/dmdb-recovery.git
cd dmdb-recovery

# 添加执行权限
chmod +x dm_recover.sh

# 编辑配置（测试环境）
vim dm_recover.sh

# 执行测试
./dm_recover.sh
```

---

## 分支管理

- `main`: 主分支，稳定版本
- `develop`: 开发分支
- `feature/*`: 特性分支
- `fix/*`: 修复分支
- `hotfix/*`: 紧急修复分支

---

## 测试指南

### 测试场景

1. **恢复到最新状态**
   - 单全量无增量
   - 全量+多增量
   - 增量链完整

2. **时间点恢复**
   - 有效时间点
   - 边界时间点
   - 无效时间点

3. **仅恢复备份**
   - 全量+全部增量
   - 全量+部分增量
   - 仅全量

4. **错误处理**
   - 备份集损坏
   - 归档缺失
   - 权限问题

---

## 问题解答

### 可以贡献哪些内容？

- 代码优化
- Bug 修复
- 文档完善
- 测试用例
- 使用案例分享

### 如何获取开发相关的帮助？

- 查看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- 查看 [文档](README.md#文档导航)
- 通过 GitHub Issues 提问

---

## 行为准则

- 尊重所有参与者
- 使用友好和包容的语言
- 专注于提供建设性的反馈
- 尊重不同观点和经验

---

感谢您的贡献！
