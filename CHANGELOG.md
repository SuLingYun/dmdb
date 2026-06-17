# 变更日志

所有重要的项目变更都将记录在此文件中。

## [v1.2.0] - 2026-06-17

### Added

- 新增 `rsync-inotify-sync.sh` 实时文件同步工具
  - 支持本地服务器（数据源）和备份服务器（接收端）两种模式
  - 支持 systemd 服务管理（rsync-sync / rsyncd）
  - 兼容麒麟V10、CentOS/RHEL 7-9、Ubuntu/Debian、Alpine 等系统
  - 自动安装 rsync 和 inotify-tools 依赖
  - 支持多模块管理，可同时接收多个数据源
- 新增 `inotify-tools-3.22.1.0.tar.gz` 源码包（同步工具依赖）
- 新增 `RSYNC_SYNC.md` 同步工具使用指南
- README 新增适用场景：文件实时同步备份

### Changed

- README 目录结构更新，添加 rsync-inotify-sync.sh 和压缩包说明
- README 文档导航新增 RSYNC_SYNC.md 链接

---

## [v1.1.1] - 2026-06-17

### Added

- README 新增适用场景说明（测试环境/生产基线实例重建、数据库参数规范化配置）
- README 目录结构更新，明确脚本支持五种模式
- README 功能特性更新，补充增量选择（模式3）说明

### Changed

- 优化 README 文档结构，提高可读性
- 更新目录结构描述，与实际脚本功能保持一致

---

## [v1.1.0] - 2026-06-15

### Added

- `reset_dm.sh` 重新初始化脚本上线：初始化实例 + 配置归档 + 自动备份作业
- README 新增「重新初始化」章节
- 新增 `RESET_GUIDE.md` 使用指南文档
- 新增模式4（dmrman 脱机全量备份）和模式5（disql 联机全量备份）
- 恢复流程新增「是否备份当前数据目录」交互选项，默认备份，可选跳过节省时间
- TROUBLESHOOTING 新增异机恢复 DM[-8374] 和 RMAN[-8308] 故障排查
- README 配置区新增 5 种场景说明（库名不同、异机、命名习惯等）
- README 功能特性新增「两种备份模式」和「可跳过数据备份」说明

### Changed

- 模式3（仅恢复备份）改为先执行 `RECOVER DATABASE` 再 `UPDATE DB_MAGIC`，符合达梦要求
- 模式3跳过后续 `update_magic()` 调用，避免重复执行 UPDATE DB_MAGIC
- 修复 `inc_total` 变量含换行符导致的整数比较报错

### Fixed

- 修复模式3在无归档时 dmrman 报错 DM[-8374] 的问题（脚本已正确处理，文档同步更新）

---

## [v1.0.0] - 2026-06-11

### Added

- 初始版本发布
- 三种数据库恢复模式：
  - 恢复到最新状态
  - 恢复到指定时间点
  - 仅恢复备份
- `RESTORE WITH BACKUPDIR` 支持，一次性恢复全量+增量链
- 可视化进度条显示
- 实时滚动输出 dmrman 进度信息
- 完整的日志记录系统
- 备份集完整性校验功能
- 自动检测增量备份并智能选择恢复策略
- 自动检测全量备份归档覆盖情况
- 自动识别最新归档时间
- 自动选择适合目标时间点的全量基座
- 交互式恢复计划确认
- 数据库状态自动验证
- 支持恢复后自动备份
- dmrman 超时控制
- 颜色化终端输出
- 详细的手动恢复指南
- 完整的配置说明文档
- 安全使用指南
- 故障排查指南

### Changed

- 优化 dmrman 输出解析，提高进度条准确性
- 改进错误处理机制
- 优化日志格式

### Fixed

- 修复了 `plan_full_date_yyyymmdd` 未定义 bug
- 修复了时间点校验边界条件

---

## 版本命名规范

采用语义化版本 (Semantic Versioning)：

```
v{MAJOR}.{MINOR}.{PATCH}
```

- **MAJOR**: 主版本号，不兼容的 API 变更
- **MINOR**: 次版本号，向后兼容的功能新增
- **PATCH**: 修订号，向后兼容的问题修复

---

## 发布类型

- `Added`: 新功能
- `Changed`: 功能变更
- `Deprecated`: 已废弃功能
- `Removed`: 已移除功能
- `Fixed`: 问题修复
- `Security`: 安全相关修复
