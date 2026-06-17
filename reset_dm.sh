#!/bin/bash
# =============================================================================
# 脚本名称: reset_dm.sh
# 功能描述: 达梦数据库重新初始化脚本（强化归档 + 自动配置备份作业）
# 执行要求: root 用户执行
# =============================================================================

set -euo pipefail

# 日志函数（无需修改）
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}
log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}
cleanup() {
    log_error "脚本执行失败，请检查上述错误信息。"
    exit 1
}
trap cleanup ERR

# =============================================================================
# 用户配置区域 ———— 【请根据您的实际环境修改以下变量】
# =============================================================================

# 【必须修改】数据库名（例如：DAMENG、DMTEST、PROD 等）
# 影响：数据目录 /data/dmdata/数据库名、归档目录 /data/dmarch/数据库名、备份目录 /data/dmbak/数据库名/bak
DB_NAME="DAMENG"

# 【必须修改】实例名（例如：DMSERVER、DMTEST、PROD 等）
# 影响：服务名 DmService实例名、dm.ini 中的实例名
# 注意：实例名可以与数据库名不同，但建议保持相同便于识别
INSTANCE_NAME="DAMENG"

# 【可选，一般无需修改】旧服务名（仅用于卸载旧服务，如果之前实例名不同可在此指定）
OLD_SERVICE_NAME="DmServiceDMTEST"

# 【必须修改】达梦软件安装目录（根据实际安装路径填写）
DM_HOME="/data/dm"

# 【必须修改】数据文件存放的基目录（dminit 会自动创建 /基目录/数据库名 子目录）
DATA_DIR="/data/dmdata"

# 【必须修改】归档日志存放的基目录（脚本会创建 /基目录/数据库名 子目录）
ARCH_DIR="/data/dmarch"

# 【必须修改】备份文件存放的基目录（脚本会创建 /基目录/数据库名/bak 子目录）
BAK_DIR="/data/dmbak"

# 【必须修改】SYSDBA 用户密码（请设置符合安全要求的强密码）
SYSDBA_PWD='9xSI1rwm51NQ6$*{98G3'

# 【必须修改】SYSAUDITOR 用户密码（请设置符合安全要求的强密码）
SYSAUDITOR_PWD='9xSI1rwm51NQ6$*{98G3'

# 【可选】归档文件大小（单位 MB），默认 2048 MB
ARCH_FILE_SIZE=2048

# 【可选】归档空间总上限（单位 MB），默认 204800 MB（200GB）
ARCH_SPACE_LIMIT=204800

# 【可选】备份保留天数，默认 30 天
BACKUP_RETAIN_DAYS=30

# =============================================================================
# 以下为脚本自动生成的动态路径和变量（请勿修改）
# =============================================================================
DATA_DIR_PATH="${DATA_DIR}/${DB_NAME}"
ARCH_DIR_PATH="${ARCH_DIR}/${DB_NAME}"
BACKUP_BASE="${BAK_DIR}/${DB_NAME}/bak"
SERVICE_NAME="DmService${INSTANCE_NAME}"

# =============================================================================
# 1. 停止并清理旧服务
# =============================================================================
log_info "停止旧服务: ${OLD_SERVICE_NAME}"
systemctl stop "${OLD_SERVICE_NAME}" 2>/dev/null || true
systemctl disable "${OLD_SERVICE_NAME}" 2>/dev/null || true

if [ -f "${DM_HOME}/script/root/dm_service_uninstaller.sh" ]; then
    log_info "卸载旧服务: ${OLD_SERVICE_NAME}"
    echo "y" | ${DM_HOME}/script/root/dm_service_uninstaller.sh -n "${OLD_SERVICE_NAME}" 2>/dev/null || true
fi

# 如果新旧服务名不同，也清理可能存在的同名新服务
if [ "${OLD_SERVICE_NAME}" != "${SERVICE_NAME}" ]; then
    log_info "停止可能存在的同名新服务: ${SERVICE_NAME}"
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    if [ -f "${DM_HOME}/script/root/dm_service_uninstaller.sh" ]; then
        echo "y" | ${DM_HOME}/script/root/dm_service_uninstaller.sh -n "${SERVICE_NAME}" 2>/dev/null || true
    fi
fi

log_info "强制结束残留达梦进程"
pkill -9 dmserver 2>/dev/null || true
pkill -9 dmap 2>/dev/null || true

# =============================================================================
# 2. 备份并重建数据/归档目录
# =============================================================================
log_info "备份旧数据目录"
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)
if [ -d "${DATA_DIR_PATH}" ]; then
    mv "${DATA_DIR_PATH}" "${DATA_DIR_PATH}.bak.${BACKUP_SUFFIX}"
    log_info "备份完成: ${DATA_DIR_PATH} -> ${DATA_DIR_PATH}.bak.${BACKUP_SUFFIX}"
fi
if [ -d "${ARCH_DIR_PATH}" ]; then
    mv "${ARCH_DIR_PATH}" "${ARCH_DIR_PATH}.bak.${BACKUP_SUFFIX}" 2>/dev/null || true
    log_info "备份完成: ${ARCH_DIR_PATH} -> ${ARCH_DIR_PATH}.bak.${BACKUP_SUFFIX}"
fi

log_info "创建必要目录并设置权限"
mkdir -p "${DATA_DIR}"
mkdir -p "${ARCH_DIR_PATH}"
mkdir -p "${BACKUP_BASE}"
chown -R dmdba:dinstall "${DATA_DIR}" "${ARCH_DIR}" "${BAK_DIR}"

# =============================================================================
# 3. 初始化数据库实例
# =============================================================================
log_info "开始初始化数据库实例（实例名: ${INSTANCE_NAME}，数据库名: ${DB_NAME}）"
su - dmdba -c "${DM_HOME}/bin/dminit \
    PATH=${DATA_DIR} \
    DB_NAME=${DB_NAME} \
    INSTANCE_NAME=${INSTANCE_NAME} \
    PORT_NUM=5236 \
    PAGE_SIZE=32 \
    EXTENT_SIZE=32 \
    CASE_SENSITIVE=1 \
    CHARSET=1 \
    LOG_SIZE=2048 \
    AUTO_OVERWRITE=2 \
    SYSDBA_PWD='${SYSDBA_PWD}' \
    SYSAUDITOR_PWD='${SYSAUDITOR_PWD}'"

# =============================================================================
# 4. 注册数据库系统服务
# =============================================================================
log_info "注册数据库服务: ${SERVICE_NAME}"
${DM_HOME}/script/root/dm_service_installer.sh \
    -t dmserver \
    -dm_ini "${DATA_DIR_PATH}/dm.ini" \
    -p ${INSTANCE_NAME}

# =============================================================================
# 5. 修改 dm.ini 参数（兼容模式 + 强制开启归档）
# =============================================================================
log_info "修改 dm.ini 参数"
systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
DM_INI="${DATA_DIR_PATH}/dm.ini"

for param in "COMPATIBLE_MODE=2" "PK_WITH_CLUSTER=0" "CHECK_CONS_NAME=0"; do
    key="${param%=*}"
    value="${param#*=}"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${DM_INI}"; then
        sed -i "s/^[[:space:]]*${key}[[:space:]]*=.*/${key}        = ${value}/" "${DM_INI}"
    else
        echo "${key}        = ${value}" >> "${DM_INI}"
    fi
done

if grep -qE "^[[:space:]]*ARCH_INI[[:space:]]*=" "${DM_INI}"; then
    sed -i "s/^[[:space:]]*ARCH_INI[[:space:]]*=.*/ARCH_INI        = 1/" "${DM_INI}"
else
    echo "ARCH_INI        = 1" >> "${DM_INI}"
fi

log_info "dm.ini 修改完成，关键参数如下："
grep -E "COMPATIBLE_MODE|PK_WITH_CLUSTER|CHECK_CONS_NAME|ARCH_INI" "${DM_INI}" || true

# =============================================================================
# 6. 手动创建 dmarch.ini 归档配置文件
# =============================================================================
log_info "手动创建 dmarch.ini 归档配置文件"
ARCH_INI_FILE="${DATA_DIR_PATH}/dmarch.ini"
cat > "${ARCH_INI_FILE}" <<EOF
[ARCHIVE_LOCAL1]
ARCH_TYPE = LOCAL
ARCH_DEST = ${ARCH_DIR_PATH}
ARCH_FILE_SIZE = ${ARCH_FILE_SIZE}
ARCH_SPACE_LIMIT = ${ARCH_SPACE_LIMIT}
EOF
chown dmdba:dinstall "${ARCH_INI_FILE}"
chmod 644 "${ARCH_INI_FILE}"
log_info "dmarch.ini 内容："
cat "${ARCH_INI_FILE}"

# =============================================================================
# 7. 启动数据库服务
# =============================================================================
log_info "启动数据库服务 ${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"
sleep 3
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log_info "服务 ${SERVICE_NAME} 启动成功"
else
    log_error "服务启动失败"
    systemctl status "${SERVICE_NAME}" --no-pager
    exit 1
fi

# =============================================================================
# 8. 验证归档配置
# =============================================================================
log_info "验证归档配置生效情况"
VERIFY_SQL="/tmp/dm_verify_arch_$$.sql"
cat > ${VERIFY_SQL} <<EOF
SET LINESHOW OFF;
SELECT 'ARCH_MODE:' || ARCH_MODE FROM V\$DATABASE;
SELECT 'ARCH_TYPE:' || ARCH_TYPE FROM V\$DM_ARCH_INI;
SELECT 'ARCH_DEST:' || ARCH_DEST FROM V\$DM_ARCH_INI;
SELECT 'ARCH_FILE_SIZE(MB):' || ARCH_FILE_SIZE FROM V\$DM_ARCH_INI;
SELECT 'ARCH_SPACE_LIMIT(MB):' || ARCH_SPACE_LIMIT FROM V\$DM_ARCH_INI;
EXIT;
EOF
${DM_HOME}/bin/disql "SYSDBA/\"${SYSDBA_PWD}\"@localhost:5236" < ${VERIFY_SQL}
rm -f ${VERIFY_SQL}

# =============================================================================
# 9. 测试归档（切换日志）
# =============================================================================
log_info "测试归档：执行 ALTER SYSTEM SWITCH LOGFILE"
TEST_SQL="/tmp/dm_switch_log_$$.sql"
cat > ${TEST_SQL} <<EOF
ALTER SYSTEM SWITCH LOGFILE;
EXIT;
EOF
${DM_HOME}/bin/disql "SYSDBA/\"${SYSDBA_PWD}\"@localhost:5236" < ${TEST_SQL} > /dev/null
rm -f ${TEST_SQL}
sleep 2
log_info "当前归档目录文件列表："
ls -lh "${ARCH_DIR_PATH}/" || true

# =============================================================================
# 10. 配置备份作业
# =============================================================================
log_info "开始配置备份作业"
chown -R dmdba:dinstall "${BAK_DIR}"

BACKUP_SQL="/tmp/dm_config_backup_$$.sql"
cat > ${BACKUP_SQL} <<EOF
SET LINESHOW OFF;
DECLARE
    V_COUNT INT;
BEGIN
    SELECT COUNT(1) INTO V_COUNT FROM DBA_OBJECTS WHERE OBJECT_TYPE = 'SCH' AND OBJECT_NAME = 'SYSJOB';
    IF V_COUNT = 0 THEN
        SP_INIT_JOB_SYS(1);
    END IF;
END;
/
DECLARE
    job_name VARCHAR(100);
BEGIN
    job_name := 'bak_full';
    BEGIN
        SP_DROP_JOB(job_name);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    job_name := 'bak_inc';
    BEGIN
        SP_DROP_JOB(job_name);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END;
/
CALL SP_CREATE_JOB('bak_full',1,0,'',0,0,'',0,'每周六凌晨01:05做全量备份，并删除${BACKUP_RETAIN_DAYS}天之前的备份。');
CALL SP_JOB_CONFIG_START('bak_full');
CALL SP_JOB_SET_EP_SEQNO('bak_full', 0);
CALL SP_ADD_JOB_STEP('bak_full', 'bak_full', 6, '01000000${BACKUP_BASE}', 3, 1, 0, 0, NULL, 0);
CALL SP_ADD_JOB_STEP('bak_full', 'bak_del', 0, 'CALL SF_BAKSET_BACKUP_DIR_ADD(''DISK'',''${BACKUP_BASE}'');
CALL SP_DB_BAKSET_REMOVE_BATCH(''DISK'',NOW()-${BACKUP_RETAIN_DAYS});', 1, 1, 0, 0, NULL, 0);
CALL SP_ADD_JOB_SCHEDULE('bak_full', 'bak_full', 1, 2, 1, 64, 0, '01:05:00', NULL, '2020-01-01 00:00:00', NULL, '');
CALL SP_JOB_CONFIG_COMMIT('bak_full');
CALL SP_CREATE_JOB('bak_inc',1,0,'',0,0,'',0,'周日至周五凌晨01:05做增量备份，失败则转为全量备份');
CALL SP_JOB_CONFIG_START('bak_inc');
CALL SP_ADD_JOB_STEP('bak_inc', 'bak_inc', 6, '11000000${BACKUP_BASE}|${BACKUP_BASE}', 1, 3, 2, 6, NULL, 0);
CALL SP_ADD_JOB_STEP('bak_inc', 'switch_bak_full', 6, '01000000${BACKUP_BASE}', 1, 1, 0, 0, NULL, 0);
CALL SP_ADD_JOB_SCHEDULE('bak_inc', 'bak_inc', 1, 2, 1, 63, 0, '01:05:00', NULL, '2020-01-01 00:00:00', NULL, '');
CALL SP_JOB_CONFIG_COMMIT('bak_inc');
SELECT NAME, DESCRIBE FROM SYSJOB.SYSJOBS WHERE NAME IN ('BAK_FULL','BAK_INC');
EXIT;
EOF

log_info "执行备份作业配置 SQL..."
${DM_HOME}/bin/disql "SYSDBA/\"${SYSDBA_PWD}\"@localhost:5236" < ${BACKUP_SQL}
rm -f ${BACKUP_SQL}

log_info "备份作业配置完成。"
log_info "  - 全量备份：每周六 01:05，路径 ${BACKUP_BASE}，保留 ${BACKUP_RETAIN_DAYS} 天"
log_info "  - 增量备份：周日至周五 01:05，失败时自动转为全量备份"

# =============================================================================
# 11. 验证数据库参数
# =============================================================================
SQL_FILE="/tmp/dm_check_params_$$.sql"
cat > ${SQL_FILE} <<'EOF'
SET LINESHOW OFF;
SELECT 'PAGE_SIZE(KB):' || (PAGE()/1024) FROM DUAL;
SELECT 'EXTENT_SIZE(PAGES):' || SF_GET_EXTENT_SIZE() FROM DUAL;
SELECT 'CASE_SENSITIVE:' || SF_GET_CASE_SENSITIVE_FLAG() FROM DUAL;
SELECT 'CHARSET_FLAG(1=UTF8):' || SF_GET_UNICODE_FLAG() FROM DUAL;
SELECT 'PK_WITH_CLUSTER:' || PARA_VALUE FROM V$DM_INI WHERE PARA_NAME='PK_WITH_CLUSTER';
SELECT 'COMPATIBLE_MODE:' || PARA_VALUE FROM V$DM_INI WHERE PARA_NAME='COMPATIBLE_MODE';
SELECT 'LENGTH_IN_CHAR:' || PARA_VALUE FROM V$DM_INI WHERE PARA_NAME='LENGTH_IN_CHAR';
SELECT 'CHECK_CONS_NAME:' || PARA_VALUE FROM V$DM_INI WHERE PARA_NAME='CHECK_CONS_NAME';
EXIT;
EOF

log_info "数据库关键参数："
${DM_HOME}/bin/disql "SYSDBA/\"${SYSDBA_PWD}\"@localhost:5236" < ${SQL_FILE}
rm -f ${SQL_FILE}

log_info "数据库状态："
${DM_HOME}/bin/disql "SYSDBA/\"${SYSDBA_PWD}\"@localhost:5236" -e "SELECT STATUS$ FROM V\$INSTANCE;"

log_info "数据库版本："
${DM_HOME}/bin/disql "SYSDBA/\"${SYSDBA_PWD}\"@localhost:5236" -e "SELECT ID_CODE FROM V\$VERSION;"

# =============================================================================
# 12. 完成信息汇总
# =============================================================================
echo "================================================================================"
log_info "数据库重新初始化完成。"
log_info "数据库名：${DB_NAME} | 实例名：${INSTANCE_NAME} | 服务名：${SERVICE_NAME}"
log_info "连接地址：localhost:5236"
log_info "SYSDBA 密码：${SYSDBA_PWD}"
log_info "SYSAUDITOR 密码：${SYSAUDITOR_PWD}"
log_info "数据目录：${DATA_DIR_PATH}"
log_info "归档目录：${ARCH_DIR_PATH} (文件大小 ${ARCH_FILE_SIZE}MB，总上限 ${ARCH_SPACE_LIMIT}MB)"
log_info "备份目录：${BACKUP_BASE} (保留 ${BACKUP_RETAIN_DAYS} 天)"
echo "================================================================================"