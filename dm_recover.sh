#!/bin/bash

###############################################################################
# 达梦数据库 DM 快速恢复脚本 v3.5
# 用途: 同机/异机快速恢复，显示可恢复时间范围
# 修复: 流程优化 —— 先显示菜单，再根据模式选择全量备份，避免菜单前中断
# 说明: 配置区已详细标注必改项，更换环境时仅需修改标记 ★ 的参数
###############################################################################

# =============================================================================
# ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
#  【配置区】更换环境时，请修改以下标记 ★ 的参数
# ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
# =============================================================================

# -----------------------------------------------------------------------------
# ★ 必改：数据库连接信息（用于选项5联机备份和验证）
# -----------------------------------------------------------------------------
DB_USER="SYSDBA"                 # 数据库用户名
DB_PASS='9xSI1rwm51NQ6$*{98G3'   # 数据库密码（选项5必须正确，选项4不需要）【单引号防止Shell解析】

# -----------------------------------------------------------------------------
# ★ 必改：达梦安装目录
# -----------------------------------------------------------------------------
DM_HOME="/data/dm"               # 例：/opt/dmdbms 或 /data/dm

# -----------------------------------------------------------------------------
# ★ 必改：数据文件目录（包含 dm.ini）
# -----------------------------------------------------------------------------
DM_DATA="/data/dmdata/DAMENG"    # 例：/data/dmdata/DAMENG

# -----------------------------------------------------------------------------
# ★ 必改：备份集存放目录
# -----------------------------------------------------------------------------
DM_BAK="/data/backup/dmbak/DAMENG/bak"  # 例：/data/dmbak/DAMENG/bak

# -----------------------------------------------------------------------------
# ★ 必改：归档日志目录
# -----------------------------------------------------------------------------
DM_ARCH="/data/backup/dmarch/DAMENG"    # 例：/data/dmarch/DAMENG

# -----------------------------------------------------------------------------
# ★ 必改：数据库服务名（systemd 服务名）
# -----------------------------------------------------------------------------
DB_SERVICE="DmServiceDAMENG"     # 例：DmServiceDAMENG

# -----------------------------------------------------------------------------
# ★ 必改：数据库监听端口
# -----------------------------------------------------------------------------
DB_PORT="5236"                   # 默认 5236

# -----------------------------------------------------------------------------
# 可选：备份文件命名模式（根据实际备份习惯调整）
# -----------------------------------------------------------------------------
FULL_BAK_PATTERN="DB_DAMENG_FULL_*"        # 全量备份目录名匹配模式
INC_BAK_PATTERN="DB_DAMENG_INCREMENT_*"    # 增量备份目录名匹配模式
ARCH_PATTERN="ARCHIVE_LOCAL*"              # 归档文件名匹配模式（无需修改）

# -----------------------------------------------------------------------------
# 可选：其他参数
# -----------------------------------------------------------------------------
AUTO_BACKUP="no"                 # 恢复后自动执行全量备份（yes/no）
RECOVER_LOG="$(pwd)/recover_$(date +%Y%m%d_%H%M%S).log"  # 日志文件路径
DMRMAN_TIMEOUT=7200              # dmrman 超时时间（秒），0 表示不超时

# =============================================================================
# 颜色定义
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'
NC='\033[0m'

# =============================================================================
# 日志函数
# =============================================================================
log_init() { mkdir -p "$(dirname "$RECOVER_LOG")" 2>/dev/null; echo "=== 恢复日志 ===" > "$RECOVER_LOG"; }
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; echo "[INFO] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; echo "[WARN] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; echo "[ERROR] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; echo "[STEP] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_detail(){ echo -e "${GRAY}  -> $1${NC}"; echo "[DETAIL] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_title() { echo ""; echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}========================================${NC}"; echo ""; }

# =============================================================================
# run_dmrman（实时显示进度）
# =============================================================================
run_dmrman() {
    local desc="$1"
    local cmd="$2"
    local show_detail="${3:-no}"
    local timeout_sec=$DMRMAN_TIMEOUT
    local tmpfile=$(mktemp /tmp/dmrman_XXXXXX.log)
    
    log_info "$desc..."
    echo "[CMD] $cmd" >> "$RECOVER_LOG"
    
    if [ "$show_detail" = "yes" ]; then
        echo -e "${GRAY}---------- $desc ----------${NC}"
        if [ "$timeout_sec" -gt 0 ] 2>/dev/null; then
            timeout $timeout_sec bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" | tee "$tmpfile"
        else
            bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" | tee "$tmpfile"
        fi
        local rc=${PIPESTATUS[0]}
    else
        echo -e "${GRAY}  ▏ $desc ...${NC}"
        if [ "$timeout_sec" -gt 0 ] 2>/dev/null; then
            (set -o pipefail; timeout $timeout_sec bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" > "$tmpfile") &
        else
            (set -o pipefail; bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" > "$tmpfile") &
        fi
        local pid=$!
        local printed=0
        local last_size=0
        local max_display=30
        local header_printed=0
        local progress_shown=0
        
        while kill -0 $pid 2>/dev/null; do
            local total=$(wc -l < "$tmpfile" 2>/dev/null || echo 0)
            local current_size=$(stat -c %s "$tmpfile" 2>/dev/null || echo 0)
            if [ "$total" -gt "$printed" ]; then
                if [ "$progress_shown" -eq 1 ]; then echo "" && progress_shown=0; fi
                sed -n "$((printed+1)),${total}p" "$tmpfile" 2>/dev/null | while IFS= read -r line; do
                    printf "${GRAY}  ▏ %s${NC}\n" "$line"
                done
                printed=$total
                last_size=$current_size
            elif [ "$current_size" -ne "$last_size" ]; then
                local raw=$(tail -c 500 "$tmpfile" 2>/dev/null | awk 'BEGIN{RS="\r"} {last=$0} END{print last}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$raw" ] && last_size=$current_size && sleep 2 && continue
                if echo "$raw" | grep -qE '\[Percent:[0-9.]+%\]'; then
                    if [ "$header_printed" -eq 0 ]; then
                        local cmd_display=$(echo "$cmd" | sed 's|/data/dm/bin/dmrman ||;s|CTLSTMT="||;s|"$||' | tr -d '"')
                        local cmd_op=$(echo "$cmd_display" | grep -oE '^[A-Z]+ [A-Z]+' || echo "$desc")
                        echo -e "${GRAY}  ▏ ─── ${cmd_op}${GRAY} ──────────────────────────────────${NC}"
                        header_printed=1
                    fi
                    local pct=$(echo "$raw" | grep -oE '[0-9.]+' | head -1)
                    local speed=$(echo "$raw" | grep -o '\[Speed:[^]]*' | sed 's/\[Speed://')
                    local cost=$(echo "$raw" | grep -o '\[Cost:[^]]*' | sed 's/\[Cost://')
                    local remain=$(echo "$raw" | grep -o '\[Remaining:[^]]*' | sed 's/\[Remaining://')
                    local pct_int=$(printf "%.0f" "$pct" 2>/dev/null || echo 0)
                    local filled=$(( pct_int * 20 / 100 ))
                    [ "$filled" -gt 20 ] && filled=20
                    local bar=""
                    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
                    for ((i=filled; i<20; i++)); do bar="${bar}░"; done
                    printf "\r${GRAY}  ▏ ${bar} ${CYAN}${pct}%%${NC}${GRAY}  ${speed}  已用: ${cost}  剩余: ${remain}   ${NC}"
                    progress_shown=1
                else
                    [ "$progress_shown" -eq 1 ] && printf "\r${GRAY}  ▏ %s${NC}" "$raw"
                    [ "$progress_shown" -eq 0 ] && printf "${GRAY}  ▏ %s${NC}" "$raw"
                    progress_shown=1
                fi
                last_size=$current_size
            fi
            sleep 2
        done
        wait $pid
        local rc=$?
        if [ "$progress_shown" -eq 1 ]; then
            if [ $rc -eq 0 ]; then
                printf "\r${GRAY}  ▏ ${GREEN}✓ 完成${NC}${GRAY}                                               ${NC}\n"
            else
                printf "\r${GRAY}  ▏ ${RED}✗ 失败（退出码: $rc）${NC}${GRAY}                               ${NC}\n"
            fi
        fi
        local final_total=$(wc -l < "$tmpfile" 2>/dev/null || echo 0)
        if [ "$final_total" -gt "$printed" ]; then
            local remain=$(( final_total - printed ))
            local show_from=$(( printed + 1 ))
            [ "$remain" -gt "$max_display" ] && show_from=$(( final_total - max_display + 1 ))
            sed -n "${show_from},${final_total}p" "$tmpfile" 2>/dev/null | while IFS= read -r line; do
                printf "${GRAY}  ▏ %s${NC}\n" "$line"
            done
        fi
    fi
    if [ $rc -eq 124 ]; then
        log_error "操作超时（${timeout_sec}秒）"
        rm -f "$tmpfile"
        return $rc
    fi
    if [ $rc -ne 0 ]; then
        local err_line=$(grep -E '错误|失败|error|Error|ERROR|[-][0-9]+' "$tmpfile" 2>/dev/null | tail -3)
        [ -n "$err_line" ] && log_error "错误信息: $err_line"
        rm -f "$tmpfile"
        log_error "操作失败（退出码: $rc）"
        return $rc
    fi
    rm -f "$tmpfile"
    return 0
}

# =============================================================================
# 全局变量
# =============================================================================
RECOVER_EARLIEST_TIME=""
RECOVER_LATEST_TIME=""
BACKUP_DB_MAGIC=""
SELECTED_FULL=""                 # 用户选择的全量备份路径

# =============================================================================
# 辅助函数
# =============================================================================
parse_backup_date() {
    local ymd="$1"
    [ -z "$ymd" ] && return 1
    local disp="${ymd//_/-} 00:00:00"
    date -d "$disp" +%s >/dev/null 2>&1 || return 1
    echo "$disp"
    return 0
}

parse_backup_datetime() {
    local name="$1"
    [ -z "$name" ] && return 1
    local raw=$(echo "$name" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}')
    if [ -n "$raw" ]; then
        local date_part="${raw:0:10}"
        local time_part="${raw:11:8}"
        local disp="${date_part//_/-} ${time_part//_/:}"
        date -d "$disp" +%s >/dev/null 2>&1 && { echo "$disp"; return 0; }
    fi
    local ymd=$(echo "$name" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    [ -z "$ymd" ] && return 1
    local disp="${ymd//_/-} 00:00:00"
    date -d "$disp" +%s >/dev/null 2>&1 || return 1
    echo "$disp"
    return 0
}

# =============================================================================
# 提取 DB_MAGIC
# =============================================================================
extract_db_magic_from_backup() {
    local backup_path="$1"
    if [ -z "$backup_path" ] || [ ! -d "$backup_path" ]; then
        log_warn "备份集路径无效，无法提取 DB_MAGIC: $backup_path" >&2
        return 1
    fi
    log_info "正在从备份集提取 DB_MAGIC: $(basename "$backup_path")" >&2
    local tmp_out=$(mktemp /tmp/dm_show_XXXXXX)
    "$DM_HOME/bin/dmrman" CTLSTMT="SHOW BACKUPSET '$backup_path' INFO DB;" > "$tmp_out" 2>&1
    local magic=$(grep -E "db_magic:" "$tmp_out" | awk '{print $2}' | head -1)
    if [ -z "$magic" ]; then
        log_warn "提取失败，dmrman 输出内容（前5行）：" >&2
        head -5 "$tmp_out" | while IFS= read -r line; do log_warn "  $line" >&2; done
    fi
    rm -f "$tmp_out"
    if [ -n "$magic" ] && [ "$magic" -gt 0 ] 2>/dev/null; then
        log_info "成功提取到 DB_MAGIC = $magic" >&2
        echo "$magic"
        return 0
    else
        log_warn "提取 DB_MAGIC 失败" >&2
        return 1
    fi
}

# =============================================================================
# 启动 DMAP（屏蔽输出）
# =============================================================================
start_dmap() {
    log_step "启动 DMAP 服务（达梦备份归档管理进程）..."
    # DMAP 是达梦的备份归档管理辅助进程，负责备份集的校验、并行读写等操作
    if pgrep -f "dmap" > /dev/null 2>&1; then
        local dmap_pid=$(pgrep -f "dmap" | head -1)
        log_info "DMAP 服务已在运行（PID: $dmap_pid）"
        return 0
    fi
    if [ -f "$DM_HOME/bin/dmap" ]; then
        $DM_HOME/bin/dmap > /dev/null 2>&1 &
        sleep 2
        if pgrep -f "dmap" > /dev/null 2>&1; then
            local dmap_pid=$(pgrep -f "dmap" | head -1)
            log_info "DMAP 服务启动成功（PID: $dmap_pid）"
            return 0
        else
            log_warn "DMAP 启动失败，将使用内置模式（性能可能较低）"
            return 1
        fi
    else
        log_warn "DMAP 程序不存在，将使用内置模式"
        return 1
    fi
}

# =============================================================================
# 显示可恢复时间范围
# =============================================================================
show_recoverable_range() {
    echo ""
    echo -e "${CYAN}---------- 可恢复时间范围分析 ----------${NC}"
    local full_baks=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort)
    [ -z "$full_baks" ] && log_error "未找到全量备份！" && exit 1
    local latest_full=$(echo "$full_baks" | tail -1)
    local latest_date=$(basename "$latest_full" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    
    local arch_files=$(find "$DM_ARCH" -type f -name "$ARCH_PATTERN" 2>/dev/null)
    if [ -n "$arch_files" ]; then
        local arch_tmp=$(mktemp /tmp/dm_arch_sort_XXXXXX.txt)
        for arch_f in $arch_files; do
            [ -f "$arch_f" ] || continue
            local arch_raw=$(basename "$arch_f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}')
            [ -z "$arch_raw" ] && continue
            local arch_sort_key="${arch_raw:0:4}${arch_raw:5:2}${arch_raw:8:2}${arch_raw:11:2}${arch_raw:14:2}${arch_raw:17:2}"
            echo "$arch_sort_key|$arch_raw|$arch_f" >> "$arch_tmp"
        done
        arch_files=$(sort -t'|' -k1 "$arch_tmp" | cut -d'|' -f3)
        local latest_entry=$(sort -t'|' -k1 "$arch_tmp" | tail -1)
        local latest_raw=$(echo "$latest_entry" | cut -d'|' -f2)
        if [ -n "$latest_raw" ]; then
            local date_part="${latest_raw:0:10}"
            local time_part="${latest_raw:11}"
            RECOVER_LATEST_TIME="${date_part} ${time_part//-/:}"
        else
            log_warn "归档文件名时间解析失败"
        fi
        rm -f "$arch_tmp"
    fi
    [ -z "$RECOVER_LATEST_TIME" ] && RECOVER_LATEST_TIME="$(date '+%Y-%m-%d %H:%M:%S')" && log_warn "未找到归档日志，最晚可恢复时间设为当前时间"
    
    local latest_arch_sec=$(date -d "${RECOVER_LATEST_TIME}" +%s 2>/dev/null || echo 0)
    local oldest_good_full=""
    local latest_good_full=""
    local oldest_full_any=""
    for fbak in $(echo "$full_baks" | sort); do
        local fd_disp=$(parse_backup_datetime "$(basename "$fbak")")
        [ -z "$fd_disp" ] && { log_warn "备份目录名日期解析失败: $(basename "$fbak")，跳过"; continue; }
        local fd_sec=$(date -d "$fd_disp" +%s 2>/dev/null || echo 0)
        [ -z "$oldest_full_any" ] && oldest_full_any="$fbak"
        if [ "$fd_sec" -gt 0 ] && [ "$latest_arch_sec" -gt 0 ] && [ "$fd_sec" -le "$latest_arch_sec" ]; then
            [ -z "$oldest_good_full" ] && oldest_good_full="$fbak"
            latest_good_full="$fbak"
        fi
    done
    if [ -n "$oldest_good_full" ]; then
        local oldest_date=$(basename "$oldest_good_full" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
        local good_disp=$(parse_backup_date "$oldest_date")
        [ -n "$good_disp" ] && RECOVER_EARLIEST_TIME="$good_disp"
    fi
    if [ -z "$RECOVER_EARLIEST_TIME" ] && [ -n "$oldest_full_any" ]; then
        local oldest_any_date=$(basename "$oldest_full_any" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
        local any_disp=$(parse_backup_date "$oldest_any_date")
        [ -n "$any_disp" ] && RECOVER_EARLIEST_TIME="$any_disp"
    fi
    [ -z "$RECOVER_EARLIEST_TIME" ] && RECOVER_EARLIEST_TIME="${latest_date//_/-} 00:00:00"
    
    echo -e "  最新全量备份: ${GREEN}$(basename "$latest_full")${NC}"
    [ "$latest_full" != "$latest_good_full" ] && echo -e "  ${YELLOW}  ⚠ $(basename "$latest_full") 无归档覆盖，仅模式3可用${NC}"
    [ -n "$latest_good_full" ] && [ "$latest_good_full" != "$latest_full" ] && echo -e "  ${GREEN}  ✓ 推荐基座: $(basename "$latest_good_full")${NC}"
    
    local inc_all=$(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort)
    local inc_total=$(echo "$inc_all" | grep -c . 2>/dev/null | tr -d '\n' || echo 0)
    local latest_full_datetime=$(parse_backup_datetime "$(basename "$latest_full")")
    local latest_full_sec=0
    [ -n "$latest_full_datetime" ] && latest_full_sec=$(date -d "$latest_full_datetime" +%s 2>/dev/null || echo 0)
    local inc_count=0
    local inc_to_apply_list=""
    for bak in $inc_all; do
        local fullname=$(basename "$bak")
        local d_datetime=$(parse_backup_datetime "$fullname")
        if [ -n "$d_datetime" ]; then
            local d_sec=$(date -d "$d_datetime" +%s 2>/dev/null || echo 0)
            [ "$d_sec" -gt "$latest_full_sec" ] && { inc_to_apply_list="$inc_to_apply_list $bak"; inc_count=$((inc_count + 1)); }
        fi
    done
    if [ "$inc_count" -eq 0 ]; then
        [ "$inc_total" -gt 0 ] && echo -e "  增量备份数量: ${YELLOW}0${NC} (目录下共 $inc_total 个，将被自动跳过)" || echo -e "  增量备份数量: ${YELLOW}0${NC}"
    else
        echo -e "  增量备份数量: ${GREEN}${inc_count} 个${NC} (仅基于最新全量的，会被应用)"
        for bak in $inc_to_apply_list; do echo -e "    -> $(basename "$bak")"; done
    fi
    if [ -n "$arch_files" ]; then
        local first_arch=$(echo "$arch_files" | head -1)
        local last_arch=$(echo "$arch_files" | tail -1)
        local arch_count=$(echo "$arch_files" | wc -l)
        echo -e "  归档日志范围: ${GREEN}$(basename "$first_arch")${NC} ~ ${GREEN}$(basename "$last_arch")${NC}"
        echo -e "  归档日志数量: ${GREEN}${arch_count}${NC} (dmrman 自动按时间顺序应用)"
    else
        log_warn "未找到归档日志"
        RECOVER_LATEST_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
    fi
    echo ""
    echo -e "  ${YELLOW}可恢复时间范围:${NC}"
    echo -e "    最早: ${GREEN}${RECOVER_EARLIEST_TIME}${NC} (最旧全量备份时间)"
    echo -e "    最晚: ${GREEN}${RECOVER_LATEST_TIME}${NC} (最新归档日志时间)"
    local full_count=$(echo "$full_baks" | grep -c . 2>/dev/null || echo 0)
    echo -e "  ${YELLOW}说明:${NC}"
    echo -e "    - 全量备份: ${full_count} 个"
    echo -e "    - 增量备份: ${inc_count} 个 (模式1/3由 RESTORE WITH BACKUPDIR 自动应用，模式2由归档推进)"
    echo -e "    - 归档日志: dmrman 自动按 LSN 顺序应用，有 UNTIL TIME 时自动停止"
    echo -e "${CYAN}-----------------------------------------${NC}"
    echo ""
}

# =============================================================================
# 校验时间点
# =============================================================================
validate_time_point() {
    local tp="$1"
    if ! echo "$tp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
        log_error "时间格式错误: $tp"; return 1
    fi
    local date_part="${tp%% *}"
    local normalized=$(date -d "$tp" +%Y-%m-%d 2>/dev/null)
    [ "$normalized" != "$date_part" ] && { log_error "日期不合法: $date_part"; return 1; }
    date -d "$tp" +%s >/dev/null 2>&1 || { log_error "时间不合法"; return 1; }
    local tp_sec=$(date -d "$tp" +%s 2>/dev/null)
    local earliest_sec=$(date -d "$RECOVER_EARLIEST_TIME" +%s 2>/dev/null)
    local latest_sec=$(date -d "$RECOVER_LATEST_TIME" +%s 2>/dev/null)
    [ -z "$tp_sec" ] || [ -z "$earliest_sec" ] || [ -z "$latest_sec" ] && return 0
    if [ "$tp_sec" -lt "$earliest_sec" ]; then
        log_error "时间点 $tp 早于最早可恢复时间 ${RECOVER_EARLIEST_TIME}"; return 1
    fi
    if [ "$tp_sec" -gt "$latest_sec" ]; then
        log_error "时间点 $tp 晚于最新归档时间 ${RECOVER_LATEST_TIME}"; return 1
    fi
    log_info "时间点 $tp 校验通过"
    return 0
}

# =============================================================================
# 停止数据库
# =============================================================================
stop_db() {
    log_step "停止数据库服务..."
    if command -v systemctl &>/dev/null; then
        log_info "使用 systemctl 停止 $DB_SERVICE..."
        systemctl stop $DB_SERVICE 2>/dev/null
    else
        log_info "使用服务脚本停止 $DB_SERVICE..."
        su - dmdba -c "$DM_HOME/bin/$DB_SERVICE stop" 2>/dev/null
    fi
    sleep 3
    local pid=$(pgrep -f "dmserver.*$DM_DATA" | head -1)
    if [ -n "$pid" ]; then
        log_warn "数据库进程仍在运行（PID: $pid），强制停止..."
        kill -9 $pid 2>/dev/null
        sleep 2
    fi
    if pgrep -f "dmserver.*$DM_DATA" > /dev/null 2>&1; then
        log_error "数据库进程无法停止，请手动检查"
        exit 1
    fi
    log_info "数据库已停止"
}

# =============================================================================
# 启动数据库
# =============================================================================
start_db() {
    log_step "启动数据库服务..."
    local dm_user=$(grep '^User=' /etc/systemd/system/${DB_SERVICE}.service 2>/dev/null | sed 's/User=//')
    [ -z "$dm_user" ] && dm_user="dmdba"
    local need_chown=0
    [ -d "$DM_DATA" ] && [ "$(stat -c %U "$DM_DATA" 2>/dev/null)" != "$dm_user" ] && need_chown=1
    for dbfile in SYSTEM.DBF ROLL.DBF MAIN.DBF TEMP.DBF; do
        [ -f "$DM_DATA/$dbfile" ] && [ "$(stat -c %U "$DM_DATA/$dbfile" 2>/dev/null)" != "$dm_user" ] && need_chown=1 && break
    done
    [ $need_chown -eq 0 ] && for dbfile in $(ls "$DM_DATA"/*.DBF 2>/dev/null); do
        [ "$(stat -c %U "$dbfile" 2>/dev/null)" != "$dm_user" ] && need_chown=1 && break
    done
    if [ $need_chown -eq 1 ]; then
        log_info "修复数据目录权限（属主: ${dm_user}）..."
        chown -R "${dm_user}":"${dm_user}" "$DM_DATA" 2>/dev/null || chown -R "${dm_user}" "$DM_DATA" 2>/dev/null
    fi
    SECONDS=0
    if command -v systemctl &>/dev/null; then
        systemctl start $DB_SERVICE
    else
        su - dmdba -c "$DM_HOME/bin/$DB_SERVICE start" 2>/dev/null
    fi
    sleep 5
    if pgrep -f "dmserver.*$DM_DATA" > /dev/null; then
        local elapsed=$SECONDS
        log_info "数据库启动成功，耗时 ${elapsed} 秒"
        return 0
    else
        log_error "数据库启动失败，请查看日志: journalctl -u $DB_SERVICE -n 30"
        return 1
    fi
}

# =============================================================================
# 备份当前数据
# =============================================================================
backup_current() {
    echo ""
    read -p "是否备份当前数据目录? (yes/no, 默认no): " do_backup_current
    if [ "$do_backup_current" != "yes" ] && [ "$do_backup_current" != "y" ]; then
        log_warn "跳过当前数据备份"
        return 0
    fi
    log_step "备份当前数据..."
    local broken="${DM_DATA}_broken_$(date +%Y%m%d_%H%M%S)"
    if [ -d "$DM_DATA" ] && [ -n "$(ls -A $DM_DATA 2>/dev/null)" ]; then
        mkdir -p "$broken"
        cp -r "$DM_DATA"/* "$broken/" 2>/dev/null
        log_info "当前数据已复制备份到: $broken"
    fi
}

# =============================================================================
# 恢复全量备份
# =============================================================================
restore_full() {
    local mode="${1:-latest}"
    log_title "阶段1：恢复全量备份"
    local latest=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort | tail -1)
    [ -z "$latest" ] && log_error "未找到全量备份" && exit 1
    [ -n "$SELECTED_FULL" ] && latest="$SELECTED_FULL"
    log_info "使用全量备份: $(basename "$latest")"
    echo ""
    read -p "是否校验备份集完整性? (yes/no, 默认no): " check_bak
    if [ "$check_bak" = "yes" ] || [ "$check_bak" = "y" ]; then
        run_dmrman "校验备份集" "$DM_HOME/bin/dmrman CTLSTMT=\"CHECK BACKUPSET '$latest';\"" "yes"
        [ $? -ne 0 ] && { log_error "备份集校验失败！"; read -p "是否继续? (yes/no): " force_continue; [ "$force_continue" != "yes" ] && exit 1; }
    else
        log_info "跳过备份集校验"
    fi
    local restore_ok=0
    if [ "$mode" != "time" ] && [ "${INC_MODE:-all}" != "none" ] && [ "${INC_MODE:-all}" != "select" ]; then
        local full_disp=$(parse_backup_datetime "$(basename "$latest")")
        local full_sec=0
        [ -n "$full_disp" ] && full_sec=$(date -d "$full_disp" +%s 2>/dev/null || echo 0)
        local has_inc=0; local inc_count_check=0
        for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
            local d_disp=$(parse_backup_datetime "$(basename "$bak")")
            local d_sec=0
            [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
            [ "$d_sec" -gt "$full_sec" ] && { has_inc=1; inc_count_check=$((inc_count_check + 1)); }
        done
        if [ "$has_inc" -eq 1 ]; then
            log_info "检测到 $inc_count_check 个增量备份，使用 WITH BACKUPDIR 模式一次性恢复全量+增量..."
            SECONDS=0
            run_dmrman "恢复全量+增量链（WITH BACKUPDIR）" "$DM_HOME/bin/dmrman CTLSTMT=\"RESTORE DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$latest' WITH BACKUPDIR '$DM_BAK' PARALLEL 8;\""
            local elapsed=$SECONDS
            log_info "RESTORE 耗时: ${elapsed} 秒"
            [ $? -eq 0 ] && { restore_ok=1; log_info "全量+增量链恢复成功"; } || log_warn "WITH BACKUPDIR 恢复失败，将降级为纯全量恢复"
        fi
    fi
    if [ "$restore_ok" -eq 0 ]; then
        log_info "执行纯全量恢复（不自动应用增量）"
        SECONDS=0
        run_dmrman "恢复全量备份" "$DM_HOME/bin/dmrman CTLSTMT=\"RESTORE DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$latest' PARALLEL 8;\""
        local elapsed=$SECONDS
        log_info "RESTORE 耗时: ${elapsed} 秒"
        [ $? -ne 0 ] && log_error "全量恢复失败" && exit 1
        log_info "全量恢复完成"
        [ "${INC_MODE:-all}" = "select" ] && log_info "手动选择增量模式，全量已恢复，后续将逐个应用"
    fi
    export RESTORE_INC_DONE=$restore_ok
}

# =============================================================================
# 应用增量备份
# =============================================================================
apply_incremental() {
    local mode="${1:-latest}"
    [ "${RESTORE_INC_DONE:-0}" -eq 1 ] && log_info "增量已在 RESTORE 阶段处理完毕，跳过" && return 0
    [ "$mode" = "time" ] && { log_info "时间点恢复模式，跳过增量（由归档推进）"; return 0; }
    [ "${INC_MODE:-all}" = "none" ] && { log_info "不使用增量，跳过"; return 0; }
    log_title "阶段2：应用增量备份"
    local to_apply=""; local total=0
    if [ "${INC_MODE:-all}" = "select" ]; then
        to_apply="${INC_SELECTED}"
        total=$(echo "$to_apply" | grep -c . 2>/dev/null || echo 0)
        log_info "手动选择增量，共 $total 个"
    else
        local latest_full=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort | tail -1)
        [ -n "$SELECTED_FULL" ] && latest_full="$SELECTED_FULL"
        local full_disp=$(parse_backup_datetime "$(basename "$latest_full")")
        local full_sec=0
        [ -n "$full_disp" ] && full_sec=$(date -d "$full_disp" +%s 2>/dev/null || echo 0)
        for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
            local d_disp=$(parse_backup_datetime "$(basename "$bak")")
            local d_sec=0
            [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
            [ "$d_sec" -gt "$full_sec" ] && { total=$((total + 1)); to_apply="$to_apply
$bak"; }
        done
    fi
    [ -z "$to_apply" ] || [ "$total" -eq 0 ] && { log_info "无增量备份，跳过"; return 0; }
    log_info "共 $total 个增量备份待应用"
    local applied=0; local succeeded=0; local skipped=0
    for bak in $to_apply; do
        [ -z "$bak" ] && continue
        applied=$((applied + 1))
        SECONDS=0
        run_dmrman "增量[$applied/$total] $(basename "$bak")" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$bak';\""
        local elapsed=$SECONDS
        log_info "RECOVER 耗时: ${elapsed} 秒"
        [ $? -eq 0 ] && succeeded=$((succeeded + 1)) || { skipped=$((skipped + 1)); log_warn "$(basename "$bak") 跳过"; }
    done
    if [ "$succeeded" -eq 0 ] && [ "$total" -gt 0 ]; then
        log_error "所有增量均未成功应用！"
        read -p "是否继续? (yes/no, 默认no): " force_inc_continue
        [ "$force_inc_continue" != "yes" ] && exit 1
    elif [ "$skipped" -gt 0 ]; then
        log_warn "增量备份完成：成功 $succeeded 个，跳过 $skipped 个"
    else
        log_info "所有 $succeeded 个增量备份成功应用"
    fi
}

# =============================================================================
# 应用归档
# =============================================================================
apply_archives() {
    local mode="$1"
    local time_point="$2"
    log_title "阶段3：应用归档日志"
    local arch_count=$(find "$DM_ARCH" -type f -name "$ARCH_PATTERN" 2>/dev/null | wc -l | tr -d ' ')
    if [ -z "$arch_count" ] || [ "$arch_count" -eq 0 ] 2>/dev/null; then
        log_warn "归档目录为空，自动降级为 WITH BACKUPDIR 方式"
        local backup_dir=$(dirname "${SELECTED_FULL:-$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r | head -1)}")
        run_dmrman "RECOVER WITH BACKUPDIR（降级）" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' WITH BACKUPDIR '$backup_dir';\""
        [ $? -ne 0 ] && log_warn "RECOVER WITH BACKUPDIR 失败"
        run_dmrman "UPDATE DB_MAGIC（降级）" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;\""
        export ARCH_APPLY_MAGIC_DONE=1
        log_info "归档应用完成（降级模式）"
        return 0
    fi
    local use_magic=""
    if [ -n "$BACKUP_DB_MAGIC" ] && [ "$BACKUP_DB_MAGIC" -gt 0 ] 2>/dev/null; then
        use_magic=" USE DB_MAGIC $BACKUP_DB_MAGIC"
        log_info "将使用源库 DB_MAGIC = $BACKUP_DB_MAGIC 应用归档"
    else
        log_info "未提取到 DB_MAGIC，将使用目标库当前 DB_MAGIC（本机场景）"
    fi
    SECONDS=0
    if [ "$mode" = "time" ] && [ -n "$time_point" ]; then
        log_info "恢复到指定时间点: $time_point"
        run_dmrman "恢复到时间点 $time_point" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' WITH ARCHIVEDIR '$DM_ARCH' UNTIL TIME '$time_point'$use_magic;\""
    else
        log_info "恢复到最新状态"
        run_dmrman "恢复到最新状态" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' WITH ARCHIVEDIR '$DM_ARCH'$use_magic;\""
    fi
    local elapsed=$SECONDS
    log_info "RECOVER 耗时: ${elapsed} 秒"
    [ $? -ne 0 ] && log_error "归档应用失败" && exit 1
    log_info "归档应用完成"
}

# =============================================================================
# 更新 DB_MAGIC
# =============================================================================
update_magic() {
    [ "${ARCH_APPLY_MAGIC_DONE:-0}" -eq 1 ] && { log_info "DB_MAGIC 已在归档阶段更新，跳过"; return 0; }
    log_title "阶段4：更新 DB_MAGIC"
    SECONDS=0
    run_dmrman "UPDATE DB_MAGIC" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;\""
    local elapsed=$SECONDS
    log_info "UPDATE DB_MAGIC 耗时: ${elapsed} 秒"
    [ $? -ne 0 ] && log_error "DB_MAGIC 更新失败" && exit 1
    log_info "DB_MAGIC 更新完成"
}

# =============================================================================
# 验证数据库
# =============================================================================
verify_db() {
    log_step "等待数据库就绪并验证..."
    local retry=0; local max_retry=15; local port_ready=0
    while [ $retry -lt $max_retry ]; do
        retry=$((retry + 1))
        echo -n -e "${GRAY}  ▏ 等待数据库就绪 ($retry/$max_retry)...${NC}\r"
        if command -v ss &>/dev/null; then
            ss -tln 2>/dev/null | grep -q ":${DB_PORT} " && port_ready=1 && break
        elif command -v nc &>/dev/null; then
            nc -z localhost $DB_PORT 2>/dev/null && port_ready=1 && break
        elif command -v lsof &>/dev/null; then
            lsof -i :$DB_PORT 2>/dev/null | grep -q LISTEN && port_ready=1 && break
        fi
        pgrep -f "dmserver.*$DM_DATA" > /dev/null 2>&1 || { echo ""; log_error "数据库进程已退出"; return 1; }
        sleep 2
    done
    echo ""
    if [ "$port_ready" -eq 1 ]; then
        log_info "数据库端口已就绪（$DB_PORT）"
    else
        log_warn "数据库端口未就绪，但进程仍在运行，请手动检查"
    fi
    log_info "数据库验证完成"
}

# =============================================================================
# 完整备份（脱机）——物理备份，使用 dmrman，无需数据库密码
# =============================================================================
full_backup() {
    log_step "执行脱机完整备份（物理备份）..."
    local bak_dir="$DM_BAK/DB_DAMENG_FULL_$(date +%Y_%m_%d_%H_%M_%S)"
    echo ""
    echo -e "${CYAN}========== 脱机完整备份（物理） ==========${NC}"
    echo -e "  备份路径: ${GREEN}$bak_dir${NC}"
    echo -e "  数据库:   ${GREEN}$DB_SERVICE${NC}"
    echo -e "  数据目录: ${GREEN}$DM_DATA${NC}"
    echo -e "  ${YELLOW}注意: 需要停止数据库${NC}"
    echo ""
    read -p "确认执行完整备份? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { log_info "已取消"; exit 0; }
    stop_db
    start_dmap
    log_info "开始脱机备份..."
    echo -e "${GRAY}---------- 备份进行中 ----------${NC}"
    local tmp_cmd_file=$(mktemp /tmp/dmrman_cmd_XXXXXX.txt)
    echo "BACKUP DATABASE '$DM_DATA/dm.ini' FULL BACKUPSET '$bak_dir' COMPRESSED LEVEL 1;" > "$tmp_cmd_file"
    echo "[CMD] $DM_HOME/bin/dmrman CTLFILE=$tmp_cmd_file" >> "$RECOVER_LOG"
    $DM_HOME/bin/dmrman CTLFILE="$tmp_cmd_file" 2>&1 | tee -a "$RECOVER_LOG"
    local bak_rc=${PIPESTATUS[0]}
    rm -f "$tmp_cmd_file"
    echo ""
    if [ $bak_rc -eq 0 ]; then
        [ -d "$bak_dir" ] && [ -n "$(ls -A "$bak_dir")" ] || { log_error "备份目录不存在"; start_db; exit 1; }
        # 修正备份集属主
        local dm_user=$(grep '^User=' /etc/systemd/system/${DB_SERVICE}.service 2>/dev/null | sed 's/User=//')
        [ -z "$dm_user" ] && dm_user="dmdba"
        chown -R "${dm_user}:dinstall" "$bak_dir" 2>/dev/null
        local bak_size=$(du -sh "$bak_dir" 2>/dev/null | awk '{print $1}')
        echo ""
        echo -e "${GREEN}========== 备份完成 ==========${NC}"
        echo -e "  备份目录: ${GREEN}$bak_dir${NC}"
        echo -e "  备份大小: ${GREEN}${bak_size}${NC}"
        echo -e "  备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================="
        log_info "备份完成"
        start_db
    else
        log_error "备份失败（退出码: $bak_rc）"; start_db; exit 1
    fi
}

# =============================================================================
# 联机完整备份（物理备份）——使用 disql，需要数据库密码
# =============================================================================
online_full_backup() {
    log_step "执行联机完整备份（物理备份）..."
    local bak_dir="$DM_BAK/DB_DAMENG_FULL_$(date +%Y_%m_%d_%H_%M_%S)"
    echo ""
    echo -e "${CYAN}========== 联机完整备份（物理） ==========${NC}"
    echo -e "  备份路径: ${GREEN}$bak_dir${NC}"
    echo -e "  数据库:   ${GREEN}$DB_SERVICE${NC}"
    echo -e "  数据目录: ${GREEN}$DM_DATA${NC}"
    echo -e "  ${YELLOW}注意: 需要数据库处于 OPEN 状态且已开启归档${NC}"
    echo ""
    read -p "确认执行联机完整备份? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { log_info "已取消"; exit 0; }
    start_dmap
    log_info "开始联机备份..."
    echo -e "${GRAY}---------- 备份进行中 ----------${NC}"
    local tmp_sql_file=$(mktemp /tmp/disql_bak_XXXXXX.sql)
    echo "BACKUP DATABASE FULL BACKUPSET '$bak_dir' COMPRESSED LEVEL 1;" > "$tmp_sql_file"
    echo "EXIT;" >> "$tmp_sql_file"
    echo "[CMD] ${DM_HOME}/bin/disql SYSDBA/***@localhost:${DB_PORT} @${tmp_sql_file}" >> "$RECOVER_LOG"
    ${DM_HOME}/bin/disql "SYSDBA/\"${DB_PASS}\"@localhost:${DB_PORT}" @"${tmp_sql_file}" 2>&1 | tee -a "$RECOVER_LOG"
    local bak_rc=${PIPESTATUS[0]}
    rm -f "$tmp_sql_file"
    echo ""
    if [ $bak_rc -eq 0 ]; then
        [ -d "$bak_dir" ] && [ -n "$(ls -A "$bak_dir")" ] || { log_error "备份目录不存在"; exit 1; }
        # 修正备份集属主为 dmdba
        local dm_user=$(grep '^User=' /etc/systemd/system/${DB_SERVICE}.service 2>/dev/null | sed 's/User=//')
        [ -z "$dm_user" ] && dm_user="dmdba"
        chown -R "${dm_user}:dinstall" "$bak_dir" 2>/dev/null
        local bak_size=$(du -sh "$bak_dir" 2>/dev/null | awk '{print $1}')
        echo ""
        echo -e "${GREEN}========== 备份完成 ==========${NC}"
        echo -e "  备份目录: ${GREEN}$bak_dir${NC}"
        echo -e "  备份大小: ${GREEN}${bak_size}${NC}"
        echo -e "  备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================="
        log_info "联机备份完成"
    else
        log_error "联机备份失败（退出码: $bak_rc）"; exit 1
    fi
}

# =============================================================================
# 恢复后备份
# =============================================================================
post_backup() {
    [ "$AUTO_BACKUP" != "yes" ] && return 0
    log_step "执行恢复后全量备份..."
    local dir="$DM_BAK/${FULL_BAK_PATTERN%\*}$(date +%Y_%m_%d)_01_05_19"
    run_dmrman "执行恢复后备份" "$DM_HOME/bin/dmrman <<EOF
BACKUP DATABASE '$DM_DATA/dm.ini' FULL TO '$dir' BACKUPINFO '恢复后自动备份';
EOF"
    [ $? -eq 0 ] && log_info "恢复后备份完成: $(basename "$dir")"
}

# =============================================================================
# 环境检查
# =============================================================================
environment_check() {
    log_title "环境检查"
    log_info "日志文件: $RECOVER_LOG"
    echo ""
    log_info "  目录配置:"
    log_info "    DM_HOME   = $DM_HOME   （达梦安装目录）"
    log_info "    DM_DATA   = $DM_DATA   （数据文件目录）"
    log_info "    DM_BAK    = $DM_BAK    （备份集存放目录）"
    log_info "    DM_ARCH   = $DM_ARCH   （归档日志目录）"
    log_info "    DB_SERVICE = $DB_SERVICE （数据库服务名）"
    log_info "    DB_PORT   = $DB_PORT   （数据库监听端口）"
    echo ""
    local all_ok=0
    [ -d "$DM_HOME" ] || { log_error "  ✗ DM_HOME 不存在"; all_ok=1; }
    [ -d "$DM_DATA" ] || { log_error "  ✗ DM_DATA 不存在"; all_ok=1; }
    [ -d "$DM_BAK" ] || { log_error "  ✗ DM_BAK 不存在"; all_ok=1; }
    [ -d "$DM_ARCH" ] || { log_error "  ✗ DM_ARCH 不存在"; all_ok=1; }
    [ -f "$DM_DATA/dm.ini" ] || { log_error "  ✗ dm.ini 不存在"; all_ok=1; }
    if [ $all_ok -eq 0 ]; then
        log_info "环境检查通过"
    else
        log_error "环境检查失败，请修正后重试"
        exit 1
    fi
    echo ""
}

# =============================================================================
# 【新增】检查并选择全量备份（仅在需要恢复且当前全量晚于归档时调用）
# =============================================================================
select_full_backup_if_needed() {
    # 获取所有全量备份列表（按时间排序）
    local all_full=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort)
    local latest_full=$(echo "$all_full" | tail -1)
    
    # 如果已经通过其他方式选定了（如模式2自动选择），则跳过
    if [ -n "$SELECTED_FULL" ]; then
        return 0
    fi
    
    # 默认使用最新全量
    SELECTED_FULL="$latest_full"
    
    # 检查最新全量是否晚于归档
    local latest_full_disp=$(parse_backup_datetime "$(basename "$latest_full")")
    [ -z "$latest_full_disp" ] && latest_full_disp="$(echo "$(basename "$latest_full")" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}' | tr '_' '-') 00:00:00"
    local latest_full_sec=$(date -d "$latest_full_disp" +%s 2>/dev/null || echo 0)
    local latest_arch_sec=$(date -d "${RECOVER_LATEST_TIME}" +%s 2>/dev/null || echo 0)
    
    if [ "$latest_full_sec" -gt 0 ] && [ "$latest_arch_sec" -gt 0 ] && [ "$latest_full_sec" -gt "$latest_arch_sec" ]; then
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}  注意：最新全量备份晚于最新归档日志${NC}"
        echo -e "${YELLOW}  最新全量: ${latest_full_disp}${NC}"
        echo -e "${YELLOW}  最新归档: ${RECOVER_LATEST_TIME}${NC}"
        echo -e "${YELLOW}  请选择可用的全量备份（需早于归档时间）${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
        echo -e "${CYAN}可用的全量备份:${NC}"
        local idx=0
        local full_list=""
        for fbak in $all_full; do
            idx=$((idx + 1))
            local fdate=$(basename "$fbak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}' | tr '_' '-')
            echo -e "  ${GREEN}${idx})${NC} $(basename "$fbak")  (${fdate})"
            full_list="$full_list $fbak"
        done
        echo ""
        read -p "请选择全量备份序号 (默认 1=最新, 共 ${idx} 个): " full_choice
        [ -z "$full_choice" ] && full_choice=1
        local selected_idx=0
        for fbak in $full_list; do
            selected_idx=$((selected_idx + 1))
            if [ "$selected_idx" -eq "$full_choice" ] 2>/dev/null; then
                SELECTED_FULL="$fbak"
                log_info "已选择全量备份: $(basename "$fbak")"
                break
            fi
        done
        # 更新 RECOVER_EARLIEST_TIME 为所选备份的日期
        if [ -n "$SELECTED_FULL" ]; then
            local selected_date=$(basename "$SELECTED_FULL" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
            local sel_disp=$(parse_backup_date "$selected_date")
            [ -n "$sel_disp" ] && RECOVER_EARLIEST_TIME="$sel_disp"
        fi
        echo ""
    fi
}

# =============================================================================
# 主程序
# =============================================================================
main() {
    echo "========================================"
    echo "    达梦数据库 DM 快速恢复脚本 v3.5"
    echo "========================================"
    echo ""
    log_init
    environment_check

    start_dmap

    show_recoverable_range

    # ============================================================
    # 【优化】先显示菜单，再根据模式选择全量备份
    # ============================================================
    local mode="latest"; local time_point=""
    while true; do
        echo -e "${CYAN}请选择恢复模式:${NC}"
        echo -e "  ${GREEN}1)${NC} 恢复到最新状态 (推荐)"
        echo -e "  ${GREEN}2)${NC} 恢复到指定时间点"
        echo -e "  ${GREEN}3)${NC} 仅恢复备份，不应用归档"
        echo -e "  ${GREEN}4)${NC} 完整备份数据库（物理备份/dmrman脱机）"
        echo -e "  ${GREEN}5)${NC} 完整备份数据库（物理备份/disql联机）"
        echo ""
        read -p "请输入选项 (1/2/3/4/5): " choice
        echo ""
        case "$choice" in
            1) mode="latest"; break ;;
            2) mode="time"
                echo -e "${CYAN}请输入恢复时间点，格式: YYYY-MM-DD HH:MI:SS${NC}"
                echo -e "${GRAY}  示例: 2026-06-10 12:00:00${NC}"
                echo -e "${YELLOW}  有效范围: ${RECOVER_EARLIEST_TIME} ~ ${RECOVER_LATEST_TIME}${NC}"
                echo ""
                read -p "恢复时间点: " time_point
                [ -z "$time_point" ] && log_error "未输入时间点" && exit 1
                validate_time_point "$time_point" || { echo ""; echo -e "${YELLOW}输入有误，请重新选择${NC}"; echo ""; continue; }
                break ;;
            3) mode="reset"; log_warn "选择模式3：仅恢复备份，不应用归档"; break ;;
            4) mode="backup"; break ;;
            5) mode="backup_online"; break ;;
            *) echo -e "${YELLOW}无效选项，请输入 1、2、3、4 或 5${NC}"; echo ""; continue ;;
        esac
    done

    # 如果是备份模式（4/5），直接执行并退出
    if [ "$mode" = "backup" ]; then
        full_backup
        exit 0
    fi
    if [ "$mode" = "backup_online" ]; then
        online_full_backup
        exit 0
    fi

    # ============================================================
    # 【优化】根据模式选择全量备份
    # ============================================================
    # 如果是时间点恢复，自动选择最合适的全量备份（最晚不晚于目标时间）
    if [ "$mode" = "time" ] && [ -n "$time_point" ]; then
        local tp_sec=$(date -d "$time_point" +%s 2>/dev/null || echo 0)
        if [ "$tp_sec" -gt 0 ]; then
            local best_full=""
            for fbak in $(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort); do
                local fd_disp=$(parse_backup_datetime "$(basename "$fbak")")
                local fd_sec=0
                [ -n "$fd_disp" ] && fd_sec=$(date -d "$fd_disp" +%s 2>/dev/null || echo 0)
                [ "$fd_sec" -gt 0 ] && [ "$fd_sec" -le "$tp_sec" ] && best_full="$fbak"
            done
            if [ -n "$best_full" ]; then
                SELECTED_FULL="$best_full"
                log_info "目标时间 $time_point，自动选择全量基座: $(basename "$best_full")"
            else
                log_error "没有早于 $time_point 的全量备份，无法恢复"
                exit 1
            fi
        fi
    fi

    # 如果还未选定全量备份（模式1/3），则检查是否需要选择（最新全量晚于归档时）
    if [ -z "$SELECTED_FULL" ]; then
        select_full_backup_if_needed
    fi

    # 如果仍然未选定，则使用最新全量（兜底）
    if [ -z "$SELECTED_FULL" ]; then
        SELECTED_FULL=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort | tail -1)
        log_info "使用默认最新全量备份: $(basename "$SELECTED_FULL")"
    fi

    # 全量备份确认与更换选项（用户可手动更换）
    echo ""
    echo -e "${CYAN}当前选择的全量备份:${NC} ${GREEN}$(basename "$SELECTED_FULL")${NC}"
    read -p "是否更换全量备份? (yes/no, 默认no): " change_full
    if [ "$change_full" = "yes" ] || [ "$change_full" = "y" ]; then
        local all_full=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r)
        local idx=0; local full_list=""
        echo -e "${CYAN}可用的全量备份:${NC}"
        for fbak in $all_full; do
            idx=$((idx + 1))
            echo -e "  ${GREEN}${idx})${NC} $(basename "$fbak")"
            full_list="$full_list $fbak"
        done
        echo ""
        read -p "请选择序号 (1-${idx}): " full_choice
        local selected_idx=0
        for fbak in $full_list; do
            selected_idx=$((selected_idx + 1))
            if [ "$selected_idx" -eq "$full_choice" ] 2>/dev/null; then
                SELECTED_FULL="$fbak"
                log_info "已切换全量备份: $(basename "$fbak")"
                # 更新 RECOVER_EARLIEST_TIME
                local selected_date=$(basename "$fbak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
                local sel_disp=$(parse_backup_date "$selected_date")
                [ -n "$sel_disp" ] && RECOVER_EARLIEST_TIME="$sel_disp"
                break
            fi
        done
    fi

    # 提取 DB_MAGIC（需 DMAP 已启动）
    log_title "提取备份集 DB_MAGIC"
    BACKUP_DB_MAGIC=$(extract_db_magic_from_backup "$SELECTED_FULL")
    if [ -n "$BACKUP_DB_MAGIC" ]; then
        if [ "$mode" != "reset" ]; then
            log_info "备份集 DB_MAGIC = $BACKUP_DB_MAGIC，将在归档恢复时使用"
        else
            log_info "备份集 DB_MAGIC = $BACKUP_DB_MAGIC（模式3不应用归档，仅记录）"
        fi
    else
        log_warn "未能提取 DB_MAGIC，归档恢复时将不添加 USE DB_MAGIC 参数"
    fi

    # 增量选择（模式3）
    local current_full_name=$(basename "$SELECTED_FULL")
    local current_full_disp=$(parse_backup_datetime "$current_full_name")
    local current_full_sec=0
    [ -n "$current_full_disp" ] && current_full_sec=$(date -d "$current_full_disp" +%s 2>/dev/null || echo 0)
    local inc_options=""; local inc_opt_count=0
    for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
        local d_disp=$(parse_backup_datetime "$(basename "$bak")")
        local d_sec=0
        [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
        [ "$d_sec" -gt "$current_full_sec" ] && { inc_opt_count=$((inc_opt_count + 1)); inc_options="$inc_options
$bak"; }
    done
    export INC_MODE="all"; export INC_SELECTED=""
    if [ "$mode" = "reset" ] && [ "$inc_opt_count" -gt 0 ]; then
        echo ""
        echo -e "${CYAN}增量备份选择（模式3）:${NC}"
        echo -e "  基座全量之后共有 ${inc_opt_count} 个增量备份:"
        echo "$inc_options" | while IFS= read -r bak; do [ -n "$bak" ] && echo -e "    ${GREEN}  -> $(basename "$bak")${NC}"; done
        echo ""
        echo -e "  ${GREEN}A)${NC} 全部增量（推荐）"
        echo -e "  ${GREEN}B)${NC} 选择部分增量"
        echo -e "  ${GREEN}C)${NC} 不使用增量"
        echo ""
        read -p "请选择 (A/B/C, 默认A): " inc_choice
        inc_choice=$(echo "$inc_choice" | tr '[:lower:]' '[:upper:]')
        if [ "$inc_choice" = "B" ]; then
            export INC_MODE="select"
            echo -e "${GRAY}  请输入要使用的增量序号（逗号分隔，如 1,3,5）:${NC}"
            echo -e "${GRAY}  可选范围: 1-${inc_opt_count}${NC}"
            echo "$inc_options" | nl -w1 -s') ' | sed 's/^[[:space:]]*/    /'
            read -p "增量选择: " inc_sel_input
            local inc_arr=()
            while IFS= read -r bak; do [ -n "$bak" ] && inc_arr+=("$bak"); done <<< "$inc_options"
            local inc_selected_list=""
            for idx in $(seq 1 ${#inc_arr[@]}); do
                echo ",$inc_sel_input," | grep -q ",$idx," && inc_selected_list="$inc_selected_list
${inc_arr[$((idx-1))]}"
            done
            export INC_SELECTED="$inc_selected_list"
            local sel_cnt=$(echo "$inc_selected_list" | grep -c . 2>/dev/null || echo 0)
            echo -e "${GREEN}  已选择 $sel_cnt 个增量${NC}"
        elif [ "$inc_choice" = "C" ]; then
            export INC_MODE="none"
            echo -e "${YELLOW}  不使用增量，仅恢复全量${NC}"
        else
            echo -e "${GREEN}  将恢复全量及全部 $inc_opt_count 个增量${NC}"
        fi
    fi

    # 恢复计划摘要
    echo ""
    echo -e "${CYAN}---------- 恢复计划摘要 ----------${NC}"
    echo -e "  基座全量: ${GREEN}$(basename "$SELECTED_FULL")${NC}"
    if [ "$mode" = "time" ]; then
        echo -e "  增量备份: ${YELLOW}跳过（由归档推进）${NC}"
    else
        local inc_count=0
        for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
            local d_disp=$(parse_backup_datetime "$(basename "$bak")")
            local d_sec=0
            [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
            [ "$d_sec" -gt "$current_full_sec" ] && inc_count=$((inc_count + 1))
        done
        if [ "$inc_count" -eq 0 ]; then
            echo -e "  增量备份: ${YELLOW}无${NC}"
        elif [ "$mode" = "latest" ]; then
            echo -e "  增量备份: ${GREEN}$inc_count 个 (自动应用)${NC}"
        else
            if [ "${INC_MODE:-all}" = "none" ]; then
                echo -e "  增量备份: ${YELLOW}不使用${NC}"
            elif [ "${INC_MODE:-all}" = "select" ]; then
                echo -e "  增量备份: ${GREEN}手动选择${NC}"
            else
                echo -e "  增量备份: ${GREEN}$inc_count 个 (自动应用)${NC}"
            fi
        fi
    fi
    if [ "$mode" = "reset" ]; then
        echo -e "  归档日志: ${YELLOW}不应用${NC}"
    else
        # ========== 修复点：正确计算归档日志数量 ==========
        local arch_count=0
        for f in $(find "$DM_ARCH" -type f -name "$ARCH_PATTERN" 2>/dev/null); do
            local ts=$(basename "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}')
            [ -z "$ts" ] && continue
            # 拆分日期和时间部分
            local date_part="${ts:0:10}"
            local time_part="${ts:11}"
            # 将时间部分中的 '-' 替换为 ':'
            time_part="${time_part//-/:}"
            local ts_sec=$(date -d "${date_part} ${time_part}" +%s 2>/dev/null || echo 0)
            [ "$ts_sec" -eq 0 ] && continue
            [ "$ts_sec" -gt "$current_full_sec" ] && arch_count=$((arch_count + 1))
        done
        if [ "$arch_count" -gt 0 ]; then
            echo -e "  归档日志: ${GREEN}应用到最新 (共 $arch_count 个)${NC}"
        else
            echo -e "  归档日志: ${RED}窗口内无归档${NC}"
        fi
        # ========== 修复结束 ==========
    fi
    echo -e "${CYAN}════════════════════════════${NC}"
    local mode_desc=""
    case "$mode" in latest) mode_desc="恢复到最新状态";; time) mode_desc="恢复到指定时间点";; reset) mode_desc="仅恢复备份，不应用归档";; esac
    echo -e "  恢复模式: ${GREEN}$mode_desc${NC}"
    echo -e "${CYAN}════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}警告: 此操作将覆盖现有数据！${NC}"
    read -p "确认执行恢复? (yes/no): " confirm
    [ "$confirm" != "yes" ] && { log_info "已取消"; exit 0; }
    echo ""

    # ============================================================
    # 执行恢复
    # ============================================================
    stop_db
    start_dmap   # 恢复前确保 DMAP 运行
    backup_current
    restore_full "$mode"
    apply_incremental "$mode"

    if [ "$mode" != "reset" ]; then
        apply_archives "$mode" "$time_point"
    else
        log_warn "跳过归档日志应用"
        log_title "阶段3（替代）：重做备份集日志"
        run_dmrman "从备份集恢复一致性" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$SELECTED_FULL';\""
        [ $? -ne 0 ] && { log_error "重做备份集日志失败"; exit 1; }
        run_dmrman "更新 DB_MAGIC" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;\""
        [ $? -ne 0 ] && { log_error "UPDATE DB_MAGIC 失败"; exit 1; }
        log_info "数据库恢复完成（无归档模式）"
    fi

    [ "$mode" != "reset" ] && update_magic

    start_db || { log_error "数据库启动失败"; exit 1; }
    verify_db
    post_backup

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}        恢复完成${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "恢复时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "恢复模式: $mode"
    [ -n "$time_point" ] && echo "时间点: $time_point"
    echo "日志文件: $RECOVER_LOG"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "1. 原数据已备份到 ${DM_DATA}_broken_*（如果选择备份）"
    echo "2. 确认正常后可删除备份释放空间"
    echo "========================================"
}

main