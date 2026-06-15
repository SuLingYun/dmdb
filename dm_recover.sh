#!/bin/bash

###############################################################################
# 达梦数据库 DM 快速恢复脚本
# 用途: 同机/异机快速恢复，显示可恢复时间范围
# 作者: 数据库管理员
# 日期: 2026-06-11
###############################################################################

# =============================================================================
# 配置区（根据实际情况修改）
# =============================================================================
#
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  场景一：本机同名恢复（DAMENG 实例，数据/备份/归档目录均为 /data/dmdata/     │
# │         DAMENG 等，直接使用默认值即可）                                       │
# │  场景二：本机恢复但库名不同（如 DMPROD 实例）                                │
# │  场景三：异机恢复（备份从其他服务器拷贝过来）                                │
# │  场景四：不同备份命名习惯（如 FULL_ → FULLbak_）                           │
# │  场景五：DM_HOME 安装路径不同（如 /opt/dmdbms）                            │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# === 必改项（无论哪种场景，以下参数必须与目标环境一致）===
#
# 数据库连接信息（仅用于验证恢复结果，disql 连接用）
DB_USER="SYSDBA"                 # ← 场景一二三四五：数据库用户名
DB_PASS="ezzk%Od1H86qmMl9@P["    # ← 场景一二三四五：数据库密码（生产环境建议从环境变量或配置文件读取）
DM_HOME="/data/dm"               # ← 场景五：修改为实际 DM 安装目录（需包含 bin/dmrman、bin/disql）
DM_DATA="/data/dmdata/DAMENG"    # ← 默认已为 DAMENG（标准实例名）
                                 # ← 场景二三四：改为实际数据目录（/data/dmdata/<你的库名>）
DM_BAK="/data/dmbak/DAMENG/bak"  # ← 默认已为 DAMENG/bak（标准实例名）
                                 # ← 场景二三：改为实际备份目录路径
DM_ARCH="/data/dmarch/DAMENG"    # ← 默认已为 DAMENG（标准实例名）
                                 # ← 场景二三：改为实际归档目录路径
DB_SERVICE="DmServiceDAMENG"     # ← 默认已为 DmServiceDAMENG（标准服务名）
                                 # ← 场景二：改为你的 systemd 服务名
DB_PORT="5236"                   # ← 场景一二三四五：改为实际监听端口

# === 必改项（根据备份文件实际命名习惯）===
#
# 全量备份目录名模式：如 DB_DAMENG_FULL_2026_06_10
#   → 默认已为 DB_DAMENG_FULL_*（标准实例名）
#   → 场景二：改为 DB_<你的库名>_FULL_*
#   → 场景四：改为你的实际命名格式（如 FULLBAK_* 或 BACKUP_*）
FULL_BAK_PATTERN="DB_DAMENG_FULL_*"

# 增量备份目录名模式：如 DB_DAMENG_INCREMENT_2026_06_11
#   → 默认已为 DB_DAMENG_INCREMENT_*（标准实例名）
#   → 场景二：改为 DB_<你的库名>_INCREMENT_*
#   → 场景四：改为你的实际命名格式
INC_BAK_PATTERN="DB_DAMENG_INCREMENT_*"

# 归档日志文件名模式：如 ARCHIVE_LOCAL1_2026-06-10_14-30-00.log
#   → 大多数情况下默认的 ARCHIVE_LOCAL* 可以匹配，异机恢复时需要确认
#   → 如果有多个归档线程（如 LOCAL1/LOCAL2），保持 ARCHIVE_LOCAL* 即可
ARCH_PATTERN="ARCHIVE_LOCAL*"

# === 可选项 ===
#
# 恢复后是否自动执行全量备份 (yes/no)
AUTO_BACKUP="no"

# 日志文件（自动创建子目录）
RECOVER_LOG="/data/dmbak/DAMENG/recover_$(date +%Y%m%d_%H%M%S).log"
#   → 默认已为 /data/dmbak/DAMENG/recover_...（标准实例名）
#   → 场景二三四：改为实际备份目录下的 recover 日志

# dmrman 超时时间（秒），默认 7200 秒（2小时），设为 0 表示不超时
DMRMAN_TIMEOUT=7200

# =============================================================================
# 颜色
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'
NC='\033[0m'

# =============================================================================
# 日志
# =============================================================================
log_init() { mkdir -p "$(dirname "$RECOVER_LOG")" 2>/dev/null; echo "=== 恢复日志 ===" > "$RECOVER_LOG"; }
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; echo "[INFO] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; echo "[WARN] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; echo "[ERROR] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; echo "[STEP] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }
log_detail(){ echo -e "${GRAY}  -> $1${NC}"; echo "[DETAIL] $(date '+%H:%M:%S') $1" >> "$RECOVER_LOG"; }

# 实时滚动显示 dmrman 输出（简化版，无复杂 ANSI 控制）
# 用法: run_dmrman "描述" "命令" [是否显示详情]
run_dmrman() {
    local desc="$1"
    local cmd="$2"
    local show_detail="${3:-no}"
    local timeout_sec=$DMRMAN_TIMEOUT
    local tmpfile=$(mktemp /tmp/dmrman_XXXXXX.log)
    
    log_info "$desc..."
    echo "[CMD] $cmd" >> "$RECOVER_LOG"
    
    if [ "$show_detail" = "yes" ]; then
        # 详细模式：直接输出全部内容
        echo -e "${GRAY}---------- $desc ----------${NC}"
        if [ "$timeout_sec" -gt 0 ] 2>/dev/null; then
            timeout $timeout_sec bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" | tee "$tmpfile"
        else
            bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" | tee "$tmpfile"
        fi
        local rc=${PIPESTATUS[0]}
    else
        # 简洁模式：后台运行 + 实时进度显示（只用 \r，兼容所有终端）
        echo -e "${GRAY}  ▏ $desc ...${NC}"
        
        # 启动后台进程（用 subshell + pipefail 确保正确捕获 dmrman 退出码）
        if [ "$timeout_sec" -gt 0 ] 2>/dev/null; then
            (set -o pipefail; timeout $timeout_sec bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" > "$tmpfile") &
        else
            (set -o pipefail; bash -c "$cmd" 2>&1 | tee -a "$RECOVER_LOG" > "$tmpfile") &
        fi
        local pid=$!
        local printed=0         # 已打印的 \n 行数
        local last_size=0       # 上次文件大小（检测 \r 进度）
        local max_display=30    # 最终显示最大行数
        local header_printed=0  # 命令摘要是否已打印
        local progress_shown=0  # 是否正在显示进度行
        
        # 从命令中提取摘要信息
        local cmd_display=$(echo "$cmd" | sed 's|/data/dm/bin/dmrman ||;s|CTLSTMT="||;s|"$||' | tr -d '"')
        local cmd_op=$(echo "$cmd_display" | grep -oE '^[A-Z]+ [A-Z]+' || echo "$desc")
        local cmd_target=$(echo "$cmd_display" | grep -oE "'[^']+\.ini'" | tr -d "'")
        local cmd_source=$(echo "$cmd_display" | grep -oE "BACKUPSET '[^']+'" | sed "s/BACKUPSET '//;s/'$//" | grep -oE '[^/]+$')
        
        while kill -0 $pid 2>/dev/null; do
            local total=$(wc -l < "$tmpfile" 2>/dev/null || echo 0)
            local current_size=$(stat -c %s "$tmpfile" 2>/dev/null || echo 0)
            
            if [ "$total" -gt "$printed" ]; then
                # 有新行（banner、错误信息等）
                if [ "$progress_shown" -eq 1 ]; then
                    echo "" && progress_shown=0
                fi
                sed -n "$((printed+1)),${total}p" "$tmpfile" 2>/dev/null | while IFS= read -r line; do
                    printf "${GRAY}  ▏ %s${NC}\n" "$line"
                done
                printed=$total
                last_size=$current_size
                
            elif [ "$current_size" -ne "$last_size" ]; then
                # 文件大小变了 → dmrman 用 \r 更新进度
                local raw=$(tail -c 500 "$tmpfile" 2>/dev/null | awk 'BEGIN{RS="\r"} {last=$0} END{print last}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [ -z "$raw" ] && last_size=$current_size && sleep 2 && continue
                
                if echo "$raw" | grep -qE '\[Percent:[0-9.]+%\]'; then
                    # 标准进度格式 → 美化显示
                    if [ "$header_printed" -eq 0 ]; then
                        echo -e "${GRAY}  ▏ ─── ${cmd_op}${GRAY} ──────────────────────────────────${NC}"
                        [ -n "$cmd_target" ] && echo -e "${GRAY}  ▏   目标: ${cmd_target}${NC}"
                        [ -n "$cmd_source" ] && echo -e "${GRAY}  ▏   备份: ${cmd_source}${NC}"
                        echo -e "${GRAY}  ▏ ─── 进度 ─────────────────────────────────────────${NC}"
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
                    # 非进度内容
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
        
        # 结束进度行（用 \r 覆盖最后一行）
        if [ "$progress_shown" -eq 1 ]; then
            if [ $rc -eq 0 ]; then
                printf "\r${GRAY}  ▏ ${GREEN}✓ 完成${NC}${GRAY}                                               ${NC}\n"
            else
                printf "\r${GRAY}  ▏ ${RED}✗ 失败（退出码: $rc）${NC}${GRAY}                               ${NC}\n"
            fi
        fi
        
        # 显示剩余未打印的新行
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
    
    # 超时判断（timeout 退出码为 124）
    if [ $rc -eq 124 ]; then
        log_error "操作超时（${timeout_sec}秒），可能是备份文件过大或磁盘性能问题"
        log_error "如需更长等待时间，请修改脚本中的 DMRMAN_TIMEOUT 值（设为 0 则永不超时）"
        rm -f "$tmpfile"
        return $rc
    fi
    
    # 执行失败
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

# 全局变量存储时间范围（供主程序使用）
RECOVER_EARLIEST_TIME=""
RECOVER_LATEST_TIME=""

# 辅助函数：从 YYYY_MM_DD 格式的日期字符串解析为 YYYY-MM-DD HH:MM:SS
# 如果日期解析失败，返回空字符串
parse_backup_date() {
    local ymd="$1"
    [ -z "$ymd" ] && return 1
    local disp="${ymd//_/-} 00:00:00"
    local sec=$(date -d "$disp" +%s 2>/dev/null)
    if [ -z "$sec" ] || [ "$sec" -eq 0 ]; then
        return 1
    fi
    echo "$disp"
    return 0
}

# 辅助函数：从备份目录名中提取精确时间 YYYY_MM_DD_HH_MI_SS，转为 YYYY-MM-DD HH:MI:SS
# 目录名示例: DB_DAMENG_FULL_2026_06_12_12_39_11
# 提取: 2026_06_12_12_39_11 → 2026-06-12 12:39:11
# 如果时间部分不存在或解析失败，降级为 parse_backup_date（只取日期）
parse_backup_datetime() {
    local name="$1"
    [ -z "$name" ] && return 1
    local raw=$(echo "$name" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}')
    if [ -n "$raw" ]; then
        local date_part="${raw:0:10}"
        local time_part="${raw:11:8}"
        local disp="${date_part//_/-} ${time_part//_/:}"
        if date -d "$disp" +%s >/dev/null 2>&1; then
            echo "$disp"
            return 0
        fi
    fi
    # 降级：只取日期
    local ymd=$(echo "$name" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    [ -z "$ymd" ] && return 1
    local disp="${ymd//_/-} 00:00:00"
    if date -d "$disp" +%s >/dev/null 2>&1; then
        echo "$disp"
        return 0
    fi
    return 1
}

# =============================================================================
# 显示可恢复时间范围
# =============================================================================
show_recoverable_range() {
    echo ""
    echo -e "${CYAN}========== 可恢复时间范围 ==========${NC}"
    
    # 全量备份
    local full_baks=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort)
    if [ -z "$full_baks" ]; then
        log_error "未找到全量备份！"
        exit 1
    fi
    
    local latest_full=$(echo "$full_baks" | tail -1)
    local latest_date=$(basename "$latest_full" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
    
    # 从归档文件名提取最晚归档时间（按文件名中的时间戳排序，不受拷贝修改时间影响）
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
    
    # 如果 RECOVER_LATEST_TIME 仍然为空，设置一个合理默认值
    if [ -z "$RECOVER_LATEST_TIME" ]; then
        RECOVER_LATEST_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
        log_warn "未找到归档日志，最晚可恢复时间设为当前时间"
    fi
    
    # 找出"有归档覆盖"的全量范围（全量日期 <= 最晚归档日期）
    local latest_arch_sec=$(date -d "${RECOVER_LATEST_TIME}" +%s 2>/dev/null || echo 0)
    local oldest_good_full=""   # 最旧的有归档覆盖的全量 → 最早可恢复时间
    local latest_good_full=""   # 最新的有归档覆盖的全量 → 推荐基座
    local oldest_full_any=""    # 最早的全量备份（无论是否有归档覆盖）
    
    for fbak in $(echo "$full_baks" | sort); do
        local fd_disp=$(parse_backup_datetime "$(basename "$fbak")")
        if [ -z "$fd_disp" ]; then
            log_warn "备份目录名日期解析失败: $(basename "$fbak")，跳过"
            continue
        fi
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
        if [ -n "$good_disp" ]; then
            RECOVER_EARLIEST_TIME="$good_disp"
        fi
    fi
    
    # 如果仍然没有 earliest_time（所有全量都晚于归档），用最早的全量备份时间
    if [ -z "$RECOVER_EARLIEST_TIME" ] && [ -n "$oldest_full_any" ]; then
        local oldest_any_date=$(basename "$oldest_full_any" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
        local any_disp=$(parse_backup_date "$oldest_any_date")
        if [ -n "$any_disp" ]; then
            RECOVER_EARLIEST_TIME="$any_disp"
            log_warn "没有全量备份早于归档时间，最早可恢复时间设为最早的全量备份时间"
        fi
    fi
    
    # 最终兜底：如果 earliest_time 仍然为空
    if [ -z "$RECOVER_EARLIEST_TIME" ]; then
        RECOVER_EARLIEST_TIME="${latest_date//_/-} 00:00:00"
        log_warn "时间解析异常，最早可恢复时间使用最新全量备份日期"
    fi
    
    echo -e "  最新全量备份: ${GREEN}$(basename "$latest_full")${NC}"
    
    # 如果最新全量没有归档覆盖，注明
    if [ "$latest_full" != "$latest_good_full" ]; then
        echo -e "  ${YELLOW}  ⚠ $(basename "$latest_full") 无归档覆盖，仅模式3（仅恢复备份）可用${NC}"
    fi
    if [ -n "$latest_good_full" ] && [ "$latest_good_full" != "$latest_full" ]; then
        echo -e "  ${GREEN}  ✓ 推荐基座: $(basename "$latest_good_full")${NC}"
    fi
    
    # 增量备份（只显示 > 最新全量的，避免混淆）
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
            if [ "$d_sec" -gt "$latest_full_sec" ]; then
                inc_to_apply_list="$inc_to_apply_list $bak"
                inc_count=$((inc_count + 1))
            fi
        fi
    done
    
    if [ "$inc_count" -eq 0 ]; then
        if [ "$inc_total" -gt 0 ]; then
            echo -e "  增量备份数量: ${YELLOW}0${NC} (目录下共 $inc_total 个，将被自动跳过)"
        else
            echo -e "  增量备份数量: ${YELLOW}0${NC}"
        fi
    else
        echo -e "  增量备份数量: ${GREEN}${inc_count}个${NC} (仅基于最新全量的，会被应用)"
        for bak in $inc_to_apply_list; do
            echo -e "    -> $(basename "$bak")"
        done
    fi
    
    # 归档日志范围（仅显示，时间已在上面解析过）
    if [ -n "$arch_files" ]; then
        local first_arch=$(echo "$arch_files" | head -1)
        local last_arch=$(echo "$arch_files" | tail -1)
        local arch_count=$(echo "$arch_files" | wc -l)
        echo -e "  归档日志范围: ${GREEN}$(basename "$first_arch")${NC} ~ ${GREEN}$(basename "$last_arch")${NC}"
        echo -e "  归档日志数量: ${GREEN}${arch_count}${NC} (dmrman 自动按时间顺序应用，无需逐个处理)"
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
    echo -e "    - 全量备份: ${full_count}个 (恢复数据文件，按选择使用1个)"
    echo -e "    - 增量备份: ${inc_count}个 (模式1/3由 RESTORE WITH BACKUPDIR 自动应用，模式2由归档推进)"
    echo -e "    - 归档日志: dmrman 自动按 LSN 顺序应用，有 UNTIL TIME 时自动停止"
    echo -e "${CYAN}=====================================${NC}"
    echo ""
}

# 校验时间点是否在有效范围内
validate_time_point() {
    local tp="$1"
    
    # 1. 格式校验
    if ! echo "$tp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
        log_error "时间格式错误: $tp"
        log_error "正确格式: YYYY-MM-DD HH:MI:SS"
        return 1
    fi
    
    # 2. 日期合法性校验（检查是否真实存在，如 2026-02-30 是非法的）
    local date_part="${tp%% *}"
    local time_part="${tp##* }"
    local normalized=$(date -d "$tp" +%Y-%m-%d 2>/dev/null)
    if [ "$normalized" != "$date_part" ]; then
        log_error "日期不合法: $date_part"
        log_error "请检查月份（如 2月没有30日，4/6/9/11月没有31日等）"
        return 1
    fi
    
    # 3. 时间合法性校验
    local normalized_full=$(date -d "$tp" +%Y-%m-%d\ %H:%M:%S 2>/dev/null)
    if [ -z "$normalized_full" ]; then
        log_error "时间不合法: $time_part"
        return 1
    fi
    
    # 4. 时间范围校验
    local tp_sec=$(date -d "$tp" +%s 2>/dev/null)
    local earliest_sec=$(date -d "$RECOVER_EARLIEST_TIME" +%s 2>/dev/null)
    local latest_sec=$(date -d "$RECOVER_LATEST_TIME" +%s 2>/dev/null)
    
    if [ -z "$tp_sec" ]; then
        log_warn "目标时间转换失败，跳过范围校验"
        return 0
    fi
    
    if [ -z "$earliest_sec" ] || [ -z "$latest_sec" ]; then
        log_warn "可恢复时间范围解析异常，跳过范围校验（最早: $RECOVER_EARLIEST_TIME, 最晚: $RECOVER_LATEST_TIME）"
        return 0
    fi
    
    if [ "$tp_sec" -lt "$earliest_sec" ]; then
        log_error "时间点 $tp 早于最早可恢复时间 ${RECOVER_EARLIEST_TIME}"
        return 1
    fi
    
    if [ "$tp_sec" -gt "$latest_sec" ]; then
        log_error "时间点 $tp 晚于最新归档时间 ${RECOVER_LATEST_TIME}"
        return 1
    fi
    
    log_info "时间点 $tp 校验通过"
    return 0
}

# =============================================================================
# 停止数据库
# =============================================================================
stop_db() {
    log_step "停止数据库..."
    if command -v systemctl &>/dev/null; then
        systemctl stop $DB_SERVICE 2>/dev/null
    else
        su - dmdba -c "$DM_HOME/bin/$DB_SERVICE stop" 2>/dev/null
    fi
    sleep 3
    
    # 强制停止所有达梦相关进程
    local pid=$(pgrep -f "dmserver" | head -1)
    if [ -n "$pid" ]; then
        log_warn "数据库进程仍在运行，强制停止..."
        kill -9 $pid 2>/dev/null
        sleep 3
    fi
    
    # 检查并停止 dmap 进程（备份归档管理进程，备份恢复辅助服务）
    local dmap_pid=$(pgrep -f "dmap" | head -1)
    if [ -n "$dmap_pid" ]; then
        log_info "停止 DMAP 服务（备份归档管理进程）..."
        kill -9 $dmap_pid 2>/dev/null
        sleep 1
    fi
    
    # 确认所有进程已停止
    if pgrep -f "dmserver" > /dev/null 2>&1; then
        log_error "数据库进程无法停止，请手动检查"
        exit 1
    fi
    
    log_info "数据库已停止"
}

# =============================================================================
# 启动 DMAP 服务
# 说明：DMAP（DM Backup Archive Manager）是达梦数据库的备份归档管理进程
#       - 负责备份集的管理和校验
#       - 支持备份集加密和解密
#       - dmrman 执行备份恢复时依赖此服务
# =============================================================================
start_dmap() {
    log_step "启动 DMAP 服务（达梦备份归档管理进程）..."
    
    # 检查 DMAP 是否已在运行
    if pgrep -f "dmap" > /dev/null 2>&1; then
        log_info "DMAP 服务已在运行"
        return 0
    fi
    
    # 启动 DMAP 服务
    if [ -f "$DM_HOME/bin/dmap" ]; then
        $DM_HOME/bin/dmap 2>/dev/null &
        sleep 2
        if pgrep -f "dmap" > /dev/null 2>&1; then
            log_info "DMAP 服务启动成功（备份归档管理进程，运行中）"
            return 0
        else
            log_warn "DMAP 服务启动失败，将使用 dmrman 内置模式继续..."
            return 1
        fi
    else
        log_warn "DMAP 程序不存在，将使用内置模式"
        return 1
    fi
}

# =============================================================================
# 启动数据库
# =============================================================================
start_db() {
    log_step "启动数据库..."
    
    local dm_user=$(grep '^User=' /etc/systemd/system/${DB_SERVICE}.service 2>/dev/null | sed 's/User=//')
    [ -z "$dm_user" ] && dm_user="dmdba"
    
    local need_chown=0
    if [ -d "$DM_DATA" ] && [ "$(stat -c %U "$DM_DATA" 2>/dev/null)" != "$dm_user" ]; then
        need_chown=1
    fi
    for dbfile in SYSTEM.DBF ROLL.DBF MAIN.DBF TEMP.DBF; do
        if [ -f "$DM_DATA/$dbfile" ] && [ "$(stat -c %U "$DM_DATA/$dbfile" 2>/dev/null)" != "$dm_user" ]; then
            need_chown=1
            break
        fi
    done
    if [ $need_chown -eq 0 ]; then
        for dbfile in $(ls "$DM_DATA"/*.DBF 2>/dev/null); do
            if [ "$(stat -c %U "$dbfile" 2>/dev/null)" != "$dm_user" ]; then
                need_chown=1
                break
            fi
        done
    fi
    
    if [ $need_chown -eq 1 ]; then
        log_info "修复数据目录权限 (${dm_user})..."
        chown -R "${dm_user}":"${dm_user}" "$DM_DATA" 2>/dev/null || \
        chown -R "${dm_user}" "$DM_DATA" 2>/dev/null || \
        log_warn "权限修复失败，请手动执行: chown -R ${dm_user}:${dm_user} $DM_DATA"
    fi
    
    SECONDS=0
    if command -v systemctl &>/dev/null; then
        systemctl start $DB_SERVICE
    else
        su - dmdba -c "$DM_HOME/bin/$DB_SERVICE start" 2>/dev/null
    fi
    sleep 5
    if pgrep -f "dmserver.*$DM_DATA" > /dev/null; then
        log_info "start_db 耗时: ${SECONDS} 秒"
        log_info "数据库启动成功"
        return 0
    else
        log_info "start_db 耗时: ${SECONDS} 秒"
        log_error "数据库启动失败"
        log_info "查看日志: journalctl -u $DB_SERVICE -n 30"
        return 1
    fi
}

# =============================================================================
# 备份当前数据（复制一份，不移动原文件）
# =============================================================================
backup_current() {
    echo ""
    read -p "是否备份当前数据目录? (yes/no, 默认no): " do_backup_current
    if [ "$do_backup_current" != "yes" ] && [ "$do_backup_current" != "y" ]; then
        log_warn "跳过当前数据备份（恢复将直接覆盖原数据）"
        return 0
    fi
    
    log_step "备份当前数据..."
    local broken="${DM_DATA}_broken_$(date +%Y%m%d_%H%M%S)"
    
    if [ -d "$DM_DATA" ] && [ -n "$(ls -A $DM_DATA 2>/dev/null)" ]; then
        # 创建备份目录并复制所有文件
        mkdir -p "$broken"
        cp -r "$DM_DATA"/* "$broken/" 2>/dev/null
        log_info "当前数据已复制备份到: $broken"
    fi
}

# =============================================================================
# 恢复全量备份（含增量链，通过 WITH BACKUPDIR 自动搜索）
# 参数: $1=恢复模式 (latest/time/reset)
# =============================================================================
restore_full() {
    local mode="${1:-latest}"
    log_step "恢复全量备份..."
    local latest=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort | tail -1)
    [ -z "$latest" ] && log_error "未找到全量备份" && exit 1
    
    [ -n "$SELECTED_FULL" ] && latest="$SELECTED_FULL"
    
    log_info "使用: $(basename "$latest")"
    
    echo ""
    read -p "是否校验备份集完整性? (yes/no, 默认no): " check_bak
    if [ "$check_bak" = "yes" ] || [ "$check_bak" = "y" ]; then
        run_dmrman "校验备份集" "$DM_HOME/bin/dmrman CTLSTMT=\"CHECK BACKUPSET '$latest';\"" "yes"
        if [ $? -ne 0 ]; then
            log_error "备份集校验失败！"
            read -p "备份集可能损坏，是否继续恢复? (yes/no): " force_continue
            [ "$force_continue" != "yes" ] && exit 1
        fi
    else
        log_info "跳过备份集校验，直接恢复..."
    fi
    
    local restore_ok=0
    
    if [ "$mode" != "time" ] && [ "${INC_MODE:-all}" != "none" ] && [ "${INC_MODE:-all}" != "select" ]; then
        local full_disp=$(parse_backup_datetime "$(basename "$latest")")
        local full_sec=0
        [ -n "$full_disp" ] && full_sec=$(date -d "$full_disp" +%s 2>/dev/null || echo 0)
        local has_inc=0
        local inc_count_check=0
        for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
            local d_disp=$(parse_backup_datetime "$(basename "$bak")")
            local d_sec=0
            [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
            if [ "$d_sec" -gt "$full_sec" ]; then
                has_inc=1
                inc_count_check=$((inc_count_check + 1))
            fi
        done
        
        if [ "$has_inc" -eq 1 ]; then
            log_info "检测到 $inc_count_check 个增量备份，使用 WITH BACKUPDIR 模式..."
            log_info "WITH BACKUPDIR 将自动搜索并应用以下增量:"
            for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
                local d_disp=$(parse_backup_datetime "$(basename "$bak")")
                local d_sec=0
                [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
                [ "$d_sec" -gt "$full_sec" ] && log_detail "$(basename "$bak")"
            done
            
            SECONDS=0
            run_dmrman "恢复全量+增量链" "$DM_HOME/bin/dmrman CTLSTMT=\"RESTORE DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$latest' WITH BACKUPDIR '$DM_BAK' PARALLEL 8;\""
            log_info "RESTORE 耗时: ${SECONDS} 秒"
            local wbd_rc=$?
            if [ $wbd_rc -eq 0 ]; then
                restore_ok=1
                log_info "全量+增量链恢复成功"
            else
                log_warn "WITH BACKUPDIR 恢复失败（退出码: $wbd_rc），将降级为纯全量恢复"
                log_warn "注意：降级后增量备份需要手动逐个应用"
            fi
        fi
    fi
    
    if [ "$restore_ok" -eq 0 ]; then
        SECONDS=0
        run_dmrman "恢复全量备份" "$DM_HOME/bin/dmrman CTLSTMT=\"RESTORE DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$latest' PARALLEL 8;\""
        log_info "RESTORE 耗时: ${SECONDS} 秒"
        [ $? -ne 0 ] && log_error "全量恢复失败" && exit 1
        log_info "全量恢复完成"
        
        if [ "${INC_MODE:-all}" = "select" ]; then
            log_info "手动选择增量模式，全量已恢复，后续将逐个应用选中的增量"
        fi
    fi
    
    export RESTORE_INC_DONE=$restore_ok
}

# =============================================================================
# 应用增量备份
# 参数: $1=恢复模式
# =============================================================================
apply_incremental() {
    local mode="${1:-latest}"
    
    # WITH BACKUPDIR 已成功，跳过
    [ "${RESTORE_INC_DONE:-0}" -eq 1 ] && log_info "增量已在 RESTORE+WITH BACKUPDIR 阶段处理完毕，跳过" && return 0
    
    # 时间点恢复/不使用增量，跳过
    [ "$mode" = "time" ] && log_info "时间点恢复模式，跳过增量（由归档日志精确推进到目标时间）" && return 0
    [ "${INC_MODE:-all}" = "none" ] && log_info "不使用增量，跳过" && return 0
    
    log_step "逐个应用增量备份..."
    
    local to_apply=""
    local total=0
    
    if [ "${INC_MODE:-all}" = "select" ]; then
        # 仅用户手动选择的增量
        to_apply="${INC_SELECTED}"
        total=$(echo "$to_apply" | grep -c . 2>/dev/null || echo 0)
        log_info "手动选择增量，共 $total 个"
    else
        # 全部增量（模式1降级方案 或 模式3默认）— 用精确时间筛选
        local latest_full=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort | tail -1)
        [ -n "$SELECTED_FULL" ] && latest_full="$SELECTED_FULL"
        local full_disp=$(parse_backup_datetime "$(basename "$latest_full")")
        local full_sec=0
        [ -n "$full_disp" ] && full_sec=$(date -d "$full_disp" +%s 2>/dev/null || echo 0)
        
        for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
            local d_disp=$(parse_backup_datetime "$(basename "$bak")")
            local d_sec=0
            [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
            if [ "$d_sec" -gt "$full_sec" ]; then
                total=$((total + 1))
                to_apply="$to_apply
$bak"
            fi
        done
    fi
    
    [ -z "$to_apply" ] || [ "$total" -eq 0 ] && log_info "无增量备份，跳过" && return 0
    
    log_info "共 $total 个增量备份待应用"
    
    local applied=0
    local succeeded=0
    local skipped=0
    for bak in $to_apply; do
        [ -z "$bak" ] && continue
        applied=$((applied + 1))
        SECONDS=0
        run_dmrman "增量[$applied/$total] $(basename "$bak")" \
            "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' FROM BACKUPSET '$bak';\""
        log_info "RECOVER 耗时: ${SECONDS} 秒"
        local inc_rc=$?
        if [ $inc_rc -eq 0 ]; then
            succeeded=$((succeeded + 1))
        else
            skipped=$((skipped + 1))
            log_warn "$(basename "$bak") 跳过（N_MAGIC 不匹配或恢复失败，退出码: $inc_rc）"
        fi
    done
    
    # 检查增量恢复结果
    if [ "$succeeded" -eq 0 ] && [ "$total" -gt 0 ]; then
        log_error "所有 $total 个增量备份均未成功应用！"
        log_error "可能原因：N_MAGIC 不匹配或备份集损坏"
        log_error "建议：检查备份集是否与当前全量备份匹配，或尝试仅恢复全量备份"
        read -p "是否继续执行（可能导致数据不完整）? (yes/no, 默认no): " force_inc_continue
        if [ "$force_inc_continue" != "yes" ]; then
            exit 1
        fi
    elif [ "$skipped" -gt 0 ]; then
        log_warn "增量备份完成：成功 $succeeded 个，跳过 $skipped 个"
        log_warn "注意：被跳过的增量中的数据将无法恢复，数据库可能处于部分恢复状态"
    else
        log_info "所有 $succeeded 个增量备份成功应用"
    fi
    
    log_info "增量备份处理完成，继续执行归档恢复"
}

# =============================================================================
# 应用归档
# 说明：
#   - 模式1/2：使用 WITH ARCHIVEDIR 应用归档日志
#   - 异机场景：归档目录为空或不包含有效归档时，自动降级为 WITH BACKUPDIR UPDATE DB_MAGIC
# =============================================================================
apply_archives() {
    local mode="$1"
    local time_point="$2"
    
    log_step "应用归档日志..."
    
    # 检查归档目录是否包含有效的归档文件（异机场景可能为空）
    local arch_count=$(find "$DM_ARCH" -type f -name "$ARCH_PATTERN" 2>/dev/null | wc -l | tr -d ' ')
    
    # 异机场景：无归档日志时，自动降级为 WITH BACKUPDIR 方式
    if [ -z "$arch_count" ] || [ "$arch_count" -eq 0 ] 2>/dev/null; then
        log_warn "归档目录为空或无有效归档文件（异机恢复场景）"
        log_info "自动降级为 WITH BACKUPDIR 方式恢复数据库状态..."
        
        local backup_dir=$(dirname "${SELECTED_FULL:-$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r | head -1)}")
        
        SECONDS=0
        run_dmrman "RECOVER DATABASE WITH BACKUPDIR" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' WITH BACKUPDIR '$backup_dir';\""
        log_info "RECOVER WITH BACKUPDIR 耗时: ${SECONDS} 秒"
        
        if [ $? -ne 0 ]; then
            log_warn "RECOVER WITH BACKUPDIR 失败，尝试直接 UPDATE DB_MAGIC..."
        fi
        
        SECONDS=0
        run_dmrman "UPDATE DB_MAGIC" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;\""
        log_info "UPDATE DB_MAGIC 耗时: ${SECONDS} 秒"
        
        # 标记已在 apply_archives 中完成 UPDATE DB_MAGIC，阻止 update_magic 重复执行
        export ARCH_APPLY_MAGIC_DONE=1
        log_info "归档应用完成（异机降级模式）"
        return 0
    fi
    
    # 本机场景：归档目录有有效文件，正常应用归档
    SECONDS=0
    if [ "$mode" = "time" ] && [ -n "$time_point" ]; then
        run_dmrman "恢复到时间点 $time_point" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' WITH ARCHIVEDIR '$DM_ARCH' UNTIL TIME '$time_point';\""
    else
        run_dmrman "恢复到最新状态" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' WITH ARCHIVEDIR '$DM_ARCH';\""
    fi
    log_info "RECOVER 耗时: ${SECONDS} 秒"
    [ $? -ne 0 ] && log_error "归档应用失败" && exit 1
    log_info "归档应用完成"
}

# =============================================================================
# 更新 DB_MAGIC
# 说明：
#   - 本机场景：先 apply_archives 推进数据，再 UPDATE DB_MAGIC
#   - 异机场景：apply_archives 已自动处理 UPDATE DB_MAGIC，此处跳过
# =============================================================================
update_magic() {
    # 异机降级场景：apply_archives 已完成 UPDATE DB_MAGIC，跳过
    [ "${ARCH_APPLY_MAGIC_DONE:-0}" -eq 1 ] && log_info "UPDATE DB_MAGIC 已在归档应用阶段完成，跳过" && return 0
    
    log_step "更新 DB_MAGIC..."
    SECONDS=0
    run_dmrman "UPDATE DB_MAGIC" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;\""
    log_info "UPDATE DB_MAGIC 耗时: ${SECONDS} 秒"
    [ $? -ne 0 ] && log_error "DB_MAGIC 更新失败" && exit 1
    log_info "DB_MAGIC 更新完成"
}

# =============================================================================
# 验证数据库（带连接重试）
# =============================================================================
verify_db() {
    log_step "等待数据库就绪并验证..."
    
    # 重试：用端口检测数据库是否就绪（避免 disql 密码特殊字符问题）
    local retry=0
    local max_retry=15
    local port_ready=0
    
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
        
        # 检查进程是否还在
        if ! pgrep -f "dmserver.*$DM_DATA" > /dev/null 2>&1; then
            echo ""
            log_error "数据库进程已退出"
            return 1
        fi
        sleep 2
    done
    
    echo ""
    
    if [ "$port_ready" -eq 1 ]; then
        log_info "数据库端口已就绪"
    else
        log_warn "数据库端口未就绪，但进程仍在启动中"
    fi
    
    log_info "数据库验证完成"
}

# =============================================================================
# 完整备份数据库
# =============================================================================
full_backup() {
    log_step "执行完整备份..."
    
    # 生成备份目录名
    local bak_dir="$DM_BAK/DB_DAMENG_FULL_$(date +%Y_%m_%d_%H_%M_%S)"
    
    echo ""
    echo -e "${CYAN}========== 完整备份数据库 ==========${NC}"
    echo -e "  备份路径: ${GREEN}$bak_dir${NC}"
    echo -e "  数据库:   ${GREEN}$DB_SERVICE${NC}"
    echo -e "  数据目录: ${GREEN}$DM_DATA${NC}"
    echo -e "  ${YELLOW}注意: dmrman 为脱机备份，需要先停止数据库${NC}"
    echo ""
    
    read -p "确认执行完整备份? (yes/no): " confirm
    [ "$confirm" != "yes" ] && log_info "已取消" && exit 0
    
    # dmrman 脱机备份：先停止数据库
    stop_db
    start_dmap
    
    # 使用 dmrman 执行脱机全量备份
    log_info "完整备份..."
    echo -e "${GRAY}---------- 完整备份 ----------${NC}"
    local tmp_cmd_file=$(mktemp /tmp/dmrman_cmd_XXXXXX.txt)
    echo "BACKUP DATABASE '$DM_DATA/dm.ini' FULL BACKUPSET '$bak_dir' COMPRESSED LEVEL 1;" > "$tmp_cmd_file"
    echo "[CMD] $DM_HOME/bin/dmrman CTLFILE=$tmp_cmd_file" >> "$RECOVER_LOG"
    $DM_HOME/bin/dmrman CTLFILE="$tmp_cmd_file" 2>&1 | tee -a "$RECOVER_LOG"
    local bak_rc=${PIPESTATUS[0]}
    rm -f "$tmp_cmd_file"
    
    echo ""
    
    if [ $bak_rc -eq 0 ]; then
        if [ -d "$bak_dir" ] && [ -n "$(ls -A "$bak_dir")" ]; then
            # 修复备份文件权限（dmrman 以 root 运行，备份文件属主为 root）
            local dm_user=$(grep '^User=' /etc/systemd/system/${DB_SERVICE}.service 2>/dev/null | sed 's/User=//')
            [ -z "$dm_user" ] && dm_user="dmdba"
            chown -R "${dm_user}:dinstall" "$bak_dir" 2>/dev/null || chown -R "$dm_user" "$bak_dir" 2>/dev/null
            
            local bak_size=$(du -sh "$bak_dir" 2>/dev/null | awk '{print $1}')
            echo ""
            echo -e "${GREEN}========== 备份完成 ==========${NC}"
            echo -e "  备份目录: ${GREEN}$bak_dir${NC}"
            echo -e "  备份大小: ${GREEN}${bak_size}${NC}"
            echo -e "  备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "=================================="
            log_info "备份完成，大小: $bak_size"
            start_db
        else
            log_error "备份命令执行完成，但备份目录不存在或为空"
            log_error "备份目录: $bak_dir"
            start_db
            exit 1
        fi
    else
        log_error "备份失败（退出码: $bak_rc）"
        start_db
        exit 1
    fi
}

# =============================================================================
# 联机完整备份数据库（使用 disql 执行，不需要停库）
# =============================================================================
online_full_backup() {
    log_step "执行联机完整备份..."
    
    local bak_dir="$DM_BAK/DB_DAMENG_FULL_$(date +%Y_%m_%d_%H_%M_%S)"
    
    echo ""
    echo -e "${CYAN}========== 联机完整备份数据库 ==========${NC}"
    echo -e "  备份路径: ${GREEN}$bak_dir${NC}"
    echo -e "  数据库:   ${GREEN}$DB_SERVICE${NC}"
    echo -e "  数据目录: ${GREEN}$DM_DATA${NC}"
    echo -e "  ${YELLOW}注意: 联机备份需要数据库处于 OPEN 状态且已开启归档${NC}"
    echo ""
    
    read -p "确认执行联机完整备份? (yes/no): " confirm
    [ "$confirm" != "yes" ] && log_info "已取消" && exit 0
    
    # 检查 DMAP 是否运行（联机备份建议启动 DMAP）
    if ! pgrep -f "dmap" > /dev/null 2>&1; then
        log_warn "DMAP 服务未运行，建议启动以确保备份正常"
        log_info "尝试启动 DMAP..."
        start_dmap
    else
        log_info "DMAP 服务运行正常（备份归档管理进程已就绪）"
    fi
    
    log_info "联机完整备份..."
    echo -e "${GRAY}---------- 联机完整备份 ----------${NC}"
    
    local tmp_sql_file=$(mktemp /tmp/disql_bak_XXXXXX.sql)
    echo "BACKUP DATABASE FULL BACKUPSET '$bak_dir' COMPRESSED LEVEL 1;" > "$tmp_sql_file"
    echo "EXIT;" >> "$tmp_sql_file"
    echo "[CMD] $DM_HOME/bin/disql $DB_USER/***@localhost:$DB_PORT @$tmp_sql_file" >> "$RECOVER_LOG"

    $DM_HOME/bin/disql "$DB_USER/\"$DB_PASS\"@localhost:$DB_PORT" @"$tmp_sql_file" 2>&1 | tee -a "$RECOVER_LOG"
    local bak_rc=${PIPESTATUS[0]}
    rm -f "$tmp_sql_file"
    
    echo ""
    
    if [ $bak_rc -eq 0 ]; then
        if [ -d "$bak_dir" ] && [ -n "$(ls -A "$bak_dir")" ]; then
            local bak_size=$(du -sh "$bak_dir" 2>/dev/null | awk '{print $1}')
            echo ""
            echo -e "${GREEN}========== 备份完成 ==========${NC}"
            echo -e "  备份目录: ${GREEN}$bak_dir${NC}"
            echo -e "  备份大小: ${GREEN}${bak_size}${NC}"
            echo -e "  备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "=================================="
            log_info "联机备份完成，大小: $bak_size"
        else
            log_error "备份命令执行完成，但备份目录不存在或为空"
            log_error "备份目录: $bak_dir"
            exit 1
        fi
    else
        log_error "联机备份失败（退出码: $bak_rc）"
        exit 1
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
# 主程序
# =============================================================================
main() {
    echo "========================================"
    echo "    达梦数据库 DM 快速恢复脚本"
    echo "========================================"
    echo ""
    
    log_init
    
    # 检查基本环境
    [ ! -d "$DM_HOME" ] && log_error "DM_HOME 不存在: $DM_HOME" && exit 1
    [ ! -d "$DM_BAK" ] && log_error "备份目录不存在" && exit 1
    [ ! -d "$DM_ARCH" ] && log_error "归档目录不存在" && exit 1
    [ ! -f "$DM_DATA/dm.ini" ] && log_error "dm.ini 不存在: $DM_DATA/dm.ini" && exit 1
    
    # 显示可恢复时间范围
    show_recoverable_range
    
    # 检查：最新全量备份是否有归档覆盖
    # （如果最新全量日期 > 最晚归档日期，则需要让用户选择较早的全量）
    local latest_full_check=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort | tail -1)
    local lf_check_disp=$(parse_backup_datetime "$(basename "$latest_full_check")")
    [ -z "$lf_check_disp" ] && lf_check_disp="$(echo "$(basename "$latest_full_check")" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}' | tr '_' '-') 00:00:00"
    local lf_sec=$(date -d "$lf_check_disp" +%s 2>/dev/null || echo 0)
    local latest_sec=$(date -d "${RECOVER_LATEST_TIME}" +%s 2>/dev/null || echo 0)
    if [ "$lf_sec" -gt 0 ] && [ "$latest_sec" -gt 0 ] && [ "$lf_sec" -gt "$latest_sec" ]; then
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}  注意：最新全量备份晚于最新归档日志${NC}"
        echo -e "${YELLOW}  最新全量: ${lf_check_disp}${NC}"
        echo -e "${YELLOW}  最新归档: ${RECOVER_LATEST_TIME}${NC}"
        echo -e "${YELLOW}  需要选择较早的全量备份才能使用归档日志${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
        echo -e "${CYAN}可用的全量备份:${NC}"
        local all_full=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r)
        local idx=0
        local full_list=""
        for fbak in $all_full; do
            idx=$((idx + 1))
            local fdate=$(basename "$fbak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
            fdate="${fdate//_/-}"
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
                log_info "使用全量备份: $(basename "$fbak")"
                local fbak_date=$(basename "$fbak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
                if [ "$fbak_date" != "$(basename "$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r | head -1)" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')" ]; then
                    export SELECTED_FULL="$fbak"
                fi
            fi
        done
        # 更新 RECOVER_EARLIEST_TIME
        if [ -n "$SELECTED_FULL" ]; then
            local selected_date=$(basename "$SELECTED_FULL" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
            local sel_disp=$(parse_backup_date "$selected_date")
            [ -n "$sel_disp" ] && RECOVER_EARLIEST_TIME="$sel_disp"
        fi
        echo ""
    fi
    
    # 选择恢复模式
    local mode="latest"
    local time_point=""
    
    while true; do
        echo -e "${CYAN}请选择恢复模式:${NC}"
        echo -e "  ${GREEN}1)${NC} 恢复到最新状态 (推荐)"
        echo -e "  ${GREEN}2)${NC} 恢复到指定时间点"
        echo -e "  ${GREEN}3)${NC} 仅恢复备份，不应用归档"
        echo -e "  ${GREEN}4)${NC} 完整备份数据库（物理备份/dmrman脱机）"
        echo -e "  ${GREEN}5)${NC} 完整备份数据库（逻辑备份/disql联机）"
        echo ""
        read -p "请输入选项 (1/2/3/4/5): " choice
        echo ""
        
        case "$choice" in
            1)
                mode="latest"
                break
                ;;
            2)
                mode="time"
                echo -e "${CYAN}请输入恢复时间点，格式: YYYY-MM-DD HH:MI:SS${NC}"
                echo -e "${GRAY}  示例: 2026-06-10 12:00:00${NC}"
                echo -e "${YELLOW}  有效范围: ${RECOVER_EARLIEST_TIME} ~ ${RECOVER_LATEST_TIME}${NC}"
                echo ""
                read -p "恢复时间点: " time_point
                [ -z "$time_point" ] && log_error "未输入时间点" && exit 1
                
                if ! validate_time_point "$time_point"; then
                    echo ""
                    echo -e "${YELLOW}输入有误，请重新选择恢复模式${NC}"
                    echo ""
                    continue
                fi
                break
                ;;
            3)
                mode="reset"
                log_warn "仅恢复备份，不应用归档"
                break
                ;;
            4)
                mode="backup"
                break
                ;;
            5)
                mode="backup_online"
                break
                ;;
            *)
                echo -e "${YELLOW}无效选项，请输入 1、2、3、4 或 5${NC}"
                echo ""
                continue
                ;;
        esac
    done
    
    # =========================================================================
    # 模式4/5：完整备份数据库（离线/联机），直接执行备份后退出
    # =========================================================================
    if [ "$mode" = "backup" ]; then
        full_backup
        exit 0
    fi
    
    if [ "$mode" = "backup_online" ]; then
        online_full_backup
        exit 0
    fi
    
    # 如果是恢复到指定时间点，自动选择最合适的全量备份（最晚不晚于目标时间）
    if [ "$mode" = "time" ] && [ -n "$time_point" ]; then
        local tp_sec=$(date -d "$time_point" +%s 2>/dev/null || echo 0)
        if [ "$tp_sec" -gt 0 ]; then
            local best_full=""
            for fbak in $(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort); do
                local fd_disp=$(parse_backup_datetime "$(basename "$fbak")")
                local fd_sec=0
                [ -n "$fd_disp" ] && fd_sec=$(date -d "$fd_disp" +%s 2>/dev/null || echo 0)
                if [ "$fd_sec" -gt 0 ] && [ "$fd_sec" -le "$tp_sec" ]; then
                    best_full="$fbak"
                fi
            done
            if [ -n "$best_full" ]; then
                export SELECTED_FULL="$best_full"
                log_info "目标时间 $time_point，自动选择全量基座: $(basename "$best_full")"
            else
                log_error "没有早于 $time_point 的全量备份，无法恢复"
                exit 1
            fi
        fi
    fi
    
    # 全量备份选择确认（仅恢复模式可用，备份模式跳过）
    if [ "$mode" != "backup" ]; then
        echo ""
        echo -e "${CYAN}当前选择的全量备份:${NC} ${GREEN}$(basename "${SELECTED_FULL:-$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r | head -1)}")${NC}"
        read -p "是否更换全量备份? (yes/no, 默认no): " change_full
        if [ "$change_full" = "yes" ] || [ "$change_full" = "y" ]; then
            local all_full=$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r)
            local idx=0
            local full_list=""
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
                    export SELECTED_FULL="$fbak"
                    log_info "已切换全量备份: $(basename "$fbak")"
                    # 更新最早可恢复时间
                    local selected_date=$(basename "$fbak" | grep -oE '[0-9]{4}_[0-9]{2}_[0-9]{2}')
                    local sel_disp=$(parse_backup_date "$selected_date")
                    [ -n "$sel_disp" ] && RECOVER_EARLIEST_TIME="$sel_disp"
                fi
            done
        fi
    fi
    
    # =========================================================================
    # 增量备份选择（模式3可手动选择，模式1/latest用全部）
    # =========================================================================
    # 先计算当前选择的全量备份精确时间
    local current_full_name=$(basename "${SELECTED_FULL:-$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r | head -1)}")
    local current_full_disp=$(parse_backup_datetime "$current_full_name")
    local current_full_sec=0
    [ -n "$current_full_disp" ] && current_full_sec=$(date -d "$current_full_disp" +%s 2>/dev/null || echo 0)
    
    # 筛选出基座全量之后的增量列表
    local inc_options=""
    local inc_opt_count=0
    for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
        local d_disp=$(parse_backup_datetime "$(basename "$bak")")
        local d_sec=0
        [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
        if [ "$d_sec" -gt "$current_full_sec" ]; then
            inc_opt_count=$((inc_opt_count + 1))
            inc_options="$inc_options
$bak"
        fi
    done
    
    export INC_MODE="all"   # 默认: 全部增量
    export INC_SELECTED=""   # 用户手动选择的增量列表
    
    # 模式3（仅恢复备份）可以选择增量
    if [ "$mode" = "reset" ] && [ "$inc_opt_count" -gt 0 ]; then
        echo ""
        echo -e "${CYAN}增量备份选择（模式3）:${NC}"
        echo -e "  基座全量之后共有 ${inc_opt_count} 个增量备份:"
        echo "$inc_options" | while IFS= read -r bak; do
            [ -n "$bak" ] && echo -e "    ${GREEN}  -> $(basename "$bak")${NC}"
        done
        echo ""
        echo -e "  ${GREEN}A)${NC} 全部增量（推荐，自动恢复全量+所有增量）"
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
            local inc_idx=1
            local inc_selected_list=""
            local inc_arr=()
            while IFS= read -r bak; do
                [ -n "$bak" ] && inc_arr+=("$bak")
            done <<< "$inc_options"
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
    
    # =========================================================================
    # 恢复计划摘要（精确筛选，只显示本次会用到的备份）
    # =========================================================================
    echo ""
    echo -e "${CYAN}══════════ 恢复计划 ══════════${NC}"
    
    # 确定全量基座和精确时间
    local plan_full_name=$(basename "${SELECTED_FULL:-$(ls -d $DM_BAK/$FULL_BAK_PATTERN 2>/dev/null | sort -r | head -1)}")
    local plan_full_disp=$(parse_backup_datetime "$plan_full_name")
    local plan_full_sec=0
    [ -n "$plan_full_disp" ] && plan_full_sec=$(date -d "$plan_full_disp" +%s 2>/dev/null || echo 0)
    echo -e "  ${GREEN}基座全量:${NC} $plan_full_name"
    
    # -------------------------------------------------------------------------
    # 增量备份
    # -------------------------------------------------------------------------
    if [ "$mode" = "time" ]; then
        echo -e "  ${YELLOW}增量备份:${NC} 跳过（由归档日志精确推进到目标时间）"
    else
        # 列出所有在基座全量之后的增量（用精确时间筛选）
        local inc_list=""
        local inc_count=0
        for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
            local d_disp=$(parse_backup_datetime "$(basename "$bak")")
            local d_sec=0
            [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
            if [ "$d_sec" -gt "$plan_full_sec" ]; then
                inc_count=$((inc_count + 1))
            fi
        done
        
        if [ "$inc_count" -eq 0 ]; then
            echo -e "  ${YELLOW}增量备份:${NC} 无"
        elif [ "$mode" = "latest" ]; then
            # 模式1：WITH BACKUPDIR 自动应用全部
            local inc_all_list=""
            for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
                local d_disp=$(parse_backup_datetime "$(basename "$bak")")
                local d_sec=0
                [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
                if [ "$d_sec" -gt "$plan_full_sec" ]; then
                    inc_all_list="$inc_all_list
$(basename "$bak")"
                fi
            done
            echo -e "  ${GREEN}增量备份:${NC} $inc_count 个"
            echo -e "  ${GRAY}  (通过 RESTORE WITH BACKUPDIR 自动应用):${NC}"
            echo "$inc_all_list" | while IFS= read -r name; do
                [ -n "$name" ] && echo -e "  ${GRAY}    -> $name${NC}"
            done
        else
            # 模式3：根据用户选择显示
            if [ "${INC_MODE:-all}" = "none" ]; then
                echo -e "  ${YELLOW}增量备份:${NC} 不使用"
            elif [ "${INC_MODE:-all}" = "select" ]; then
                local sel_cnt=$(echo "${INC_SELECTED}" | grep -c . 2>/dev/null || echo 0)
                echo -e "  ${GREEN}增量备份:${NC} 手动选择 $sel_cnt 个"
                echo -e "  ${GRAY}  (手动逐个 RECOVER，若 N_MAGIC 不匹配则跳过):${NC}"
                echo "${INC_SELECTED}" | while IFS= read -r bak; do
                    [ -n "$bak" ] && echo -e "  ${GRAY}    -> $(basename "$bak")${NC}"
                done
                echo -e "  ${YELLOW}  ⚠ 手动选择模式：N_MAGIC 不匹配的增量将被跳过${NC}"
            else
                local inc_all_list=""
                for bak in $(ls -d $DM_BAK/$INC_BAK_PATTERN 2>/dev/null | sort); do
                    local d_disp=$(parse_backup_datetime "$(basename "$bak")")
                    local d_sec=0
                    [ -n "$d_disp" ] && d_sec=$(date -d "$d_disp" +%s 2>/dev/null || echo 0)
                    if [ "$d_sec" -gt "$plan_full_sec" ]; then
                        inc_all_list="$inc_all_list
$(basename "$bak")"
                    fi
                done
                echo -e "  ${GREEN}增量备份:${NC} $inc_count 个"
                echo -e "  ${GRAY}  (通过 RESTORE WITH BACKUPDIR 自动应用):${NC}"
                echo "$inc_all_list" | while IFS= read -r name; do
                    [ -n "$name" ] && echo -e "  ${GRAY}    -> $name${NC}"
                done
            fi
        fi
    fi
    
    # -------------------------------------------------------------------------
    # 归档日志
    # -------------------------------------------------------------------------
    if [ "$mode" = "reset" ]; then
        echo -e "  ${YELLOW}归档日志:${NC} 不应用"
    else
        # 归档时间窗口起点：基座全量时间
        # 归档时间窗口终点：最新归档时间（模式1）或目标时间（模式2）
        local arch_window_end=0
        
        if [ "$mode" = "time" ]; then
            arch_window_end=$(date -d "$time_point" +%s 2>/dev/null || echo 0)
        else
            arch_window_end=$(date -d "${RECOVER_LATEST_TIME}" +%s 2>/dev/null || echo 0)
        fi
        
        # 筛选出在窗口内的归档并按时间排序
        local arch_in_window=""
        local arch_count=0
        local arch_earliest_ts=""
        local arch_latest_ts=""
        
        local arch_tmp_plan=$(mktemp /tmp/dm_arch_plan_XXXXXX.txt)
        for f in $(find "$DM_ARCH" -type f -name "$ARCH_PATTERN" 2>/dev/null); do
            local ts=$(basename "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}')
            [ -z "$ts" ] && continue
            local arch_date="${ts:0:10}"
            local arch_time="${ts:11}"
            local ts_sec=$(date -d "${arch_date} ${arch_time//-/:}" +%s 2>/dev/null || echo 0)
            [ "$ts_sec" -eq 0 ] && continue
            
            # 归档 > 基座全量时间 且 <= 窗口终点
            if [ "$ts_sec" -gt "$plan_full_sec" ] && [ "$ts_sec" -le "$arch_window_end" ]; then
                local sort_key="${ts:0:4}${ts:5:2}${ts:8:2}${ts:11:2}${ts:14:2}${ts:17:2}"
                echo "$sort_key|$ts|$f" >> "$arch_tmp_plan"
                arch_count=$((arch_count + 1))
            fi
        done
        arch_in_window=$(sort -t'|' -k1 "$arch_tmp_plan" | cut -d'|' -f2-)
        arch_earliest_ts=$(echo "$arch_in_window" | head -1 | cut -d'|' -f1)
        arch_latest_ts=$(echo "$arch_in_window" | tail -1 | cut -d'|' -f1)
        rm -f "$arch_tmp_plan"
        
        if [ "$arch_count" -gt 0 ]; then
            local arch_mode_desc=""
            if [ "$mode" = "time" ]; then
                arch_mode_desc="应用到目标时间 ${CYAN}$time_point${NC}"
            else
                arch_mode_desc="应用到最新"
            fi
            echo -e "  ${GREEN}归档日志:${NC} $arch_mode_desc"
            echo -e "  ${GRAY}  归档数量: ${arch_count} 个${NC}"
            echo -e "  ${GRAY}  时间范围: ${arch_earliest_ts//_/:} ~ ${arch_latest_ts//_/:}${NC}"
            
            # 逐个列出归档文件名
            echo "$arch_in_window" | sort | while IFS='|' read -r ts fname; do
                [ -n "$fname" ] && echo -e "  ${GRAY}    -> $(basename "$fname")${NC}"
            done
            
            # 警告：基座全量时间晚于目标时间
            if [ "$mode" = "time" ]; then
                if [ "$plan_full_sec" -gt 0 ] && [ "$arch_window_end" -gt 0 ] && [ "$plan_full_sec" -gt "$arch_window_end" ]; then
                    echo -e "  ${RED}  ⚠ 基座全量时间晚于目标时间，恢复无法执行！${NC}"
                fi
            fi
        else
            echo -e "  ${RED}归档日志:${NC} 窗口内无归档"
            if [ "$mode" = "time" ]; then
                echo -e "  ${RED}  ⚠ 目标时间 ${time_point} 超出归档覆盖范围，或归档起始晚于目标时间${NC}"
            else
                echo -e "  ${RED}  ⚠ 无归档日志覆盖当前基座全量之后的时间段${NC}"
            fi
        fi
    fi
    
    echo -e "${CYAN}════════════════════════════${NC}"
    echo ""
    
    # 恢复模式说明
    local mode_desc=""
    case "$mode" in
        latest) mode_desc="恢复到最新状态" ;;
        time)   mode_desc="恢复到指定时间点" ;;
        reset)  mode_desc="仅恢复备份，不应用归档" ;;
        backup) mode_desc="完整备份数据库" ;;
    esac
    echo -e "  ${GREEN}恢复模式:${NC} $mode_desc"
    
    echo -e "${CYAN}════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}警告: 此操作将覆盖现有数据！${NC}"
    read -p "确认执行恢复? (yes/no): " confirm
    [ "$confirm" != "yes" ] && log_info "已取消" && exit 0
    
    echo ""
    
    # 执行恢复
    stop_db
    start_dmap
    backup_current
    restore_full "$mode"
    apply_incremental "$mode"
    
    if [ "$mode" != "reset" ]; then
        apply_archives "$mode" "$time_point"
    else
        log_warn "跳过归档日志应用"
        log_step "恢复数据库一致性（无归档，仅完成还原）..."
        
        # 模式3（仅恢复备份）：数据已通过 RESTORE 恢复，无需 RECOVER
        # 直接 UPDATE DB_MAGIC 让数据库可启动
        SECONDS=0
        run_dmrman "更新 DB_MAGIC（无归档，直接更新）" "$DM_HOME/bin/dmrman CTLSTMT=\"RECOVER DATABASE '$DM_DATA/dm.ini' UPDATE DB_MAGIC;\""
        local magic_rc=$?
        log_info "UPDATE DB_MAGIC 耗时: ${SECONDS} 秒"
        
        [ $magic_rc -ne 0 ] && log_error "UPDATE DB_MAGIC 失败，请检查数据库状态" && exit 1
        log_info "数据库一致性恢复完成（无归档模式）"
    fi
    
    if [ "$mode" != "reset" ]; then
        update_magic
    fi
    
    if start_db; then
        log_info "数据库启动成功"
    else
        log_error "数据库启动失败，请检查日志"
        exit 1
    fi
    
    if verify_db; then
        log_info "数据库验证通过"
    else
        log_error "数据库验证失败，请检查状态"
        exit 1
    fi
    
    post_backup
    
    # 摘要
    echo ""
    echo "========================================"
    echo -e "${GREEN}        恢复完成${NC}"
    echo "========================================"
    echo "恢复时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "恢复模式: $mode"
    [ -n "$time_point" ] && echo "时间点: $time_point"
    echo "日志文件: $RECOVER_LOG"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "1. 原数据已备份到 ${DM_DATA}_broken_*"
    echo "2. 确认正常后可删除备份释放空间"
    echo "========================================"
}

main
