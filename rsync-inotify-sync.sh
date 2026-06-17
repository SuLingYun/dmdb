#!/bin/bash
#===============================================================================
# rsync + inotify 实时文件同步工具 v3.4
# 支持一台备份服务器接收多个本地服务器的同步
# 两种模式均通过 systemd 管理
# 兼容：麒麟V10、CentOS/RHEL 7-9、Ubuntu/Debian、Alpine 等
#===============================================================================

set -e

# 路径
INSTALL_DIR="/opt/rsync-sync"
CONFIG_FILE="${INSTALL_DIR}/sync.conf"
LOG_FILE="${INSTALL_DIR}/sync.log"
PASSWORD_FILE="/etc/rsync.password"
RSYNCD_SECRETS="/etc/rsyncd.secrets"
RSYNCD_CONF="/etc/rsyncd.conf"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 全局变量
MODE=""
REMOTE_HOST=""
REMOTE_PORT=""
REMOTE_MODULE=""
LOCAL_DIR=""
RSYNC_USER=""
RSYNC_PASSWORD=""
WATCH_EVENTS=""
RSYNC_OPTS=""
EXCLUDE_PATTERNS=""
ALLOW_HOSTS=""

# 输出函数
log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n${BOLD}  $1${NC}\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"; }
print_line() { echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"; }

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║         rsync + inotify 实时文件同步工具 v3.4                ║
║                                                               ║
║   模式1: 本地服务器（数据源）                                 ║
║   模式2: 备份服务器（接收端）- 支持多个数据源                  ║
║                                                               ║
║   两种模式均通过 systemd 管理                                  ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[✗] 请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

# 系统检测
detect_system() {
    echo -e "${BOLD}系统信息${NC}\n"
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID}"
        DISTRO_LIKE="${ID_LIKE}"
        DISTRO_VERSION="${VERSION_ID}"
    else
        DISTRO="unknown"
    fi

    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"; PKG_INSTALL="dnf install -y"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"; PKG_INSTALL="yum install -y"
    elif command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"; PKG_INSTALL="apt-get install -y"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"; PKG_INSTALL="pacman -S --noconfirm"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"; PKG_INSTALL="zypper install -y"
    else
        PKG_MANAGER="apk"; PKG_INSTALL="apk add"
    fi

    log_info "包管理器: ${PKG_MANAGER}"
    log_info "系统: ${DISTRO} ${DISTRO_VERSION}"
}

#===============================================================================
# 增强的依赖安装函数（支持麒麟V10、RHEL系、Debian系等）
#===============================================================================

# 配置 EPEL 仓库（适用于 RHEL 8/9 及麒麟 V10）
setup_epel() {
    local major_ver=""
    if [[ -f /etc/redhat-release ]] || [[ "${DISTRO}" =~ (rhel|centos|kylin) ]]; then
        if [[ -n "${DISTRO_VERSION}" ]]; then
            major_ver=$(echo "${DISTRO_VERSION}" | cut -d. -f1)
        else
            major_ver=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) | cut -d. -f1 2>/dev/null || echo "8")
        fi
        
        if [[ "${major_ver}" -ge 7 ]] && [[ "${major_ver}" -le 9 ]]; then
            if [[ ! -f /etc/yum.repos.d/epel.repo ]]; then
                log_info "配置 EPEL ${major_ver} 仓库..."
                cat > /etc/yum.repos.d/epel.repo << EOF
[epel]
name=Extra Packages for Enterprise Linux ${major_ver} - \$basearch
baseurl=https://mirrors.tuna.tsinghua.edu.cn/epel/${major_ver}/Everything/\$basearch
enabled=1
gpgcheck=0
EOF
                ${PKG_MANAGER} clean all &>/dev/null
                ${PKG_MANAGER} makecache &>/dev/null
                log_info "EPEL 仓库已配置"
            fi
        fi
    fi
}

# 麒麟 V10 特殊处理（如果 EPEL 不可用，尝试华为官方源）
setup_kylin_repo() {
    if [[ "${DISTRO}" == "kylin" ]]; then
        if [[ ! -f /etc/yum.repos.d/kylin.repo ]]; then
            log_info "添加麒麟 V10 官方源（华为镜像）..."
            cat > /etc/yum.repos.d/kylin.repo << 'EOF'
[kylin]
name=Kylin Linux Advanced Server V10
baseurl=https://update.cs2c.com.cn/NS/V10/V10SP3/os/adv/lic/BaseOS/$basearch/
enabled=1
gpgcheck=0
EOF
            ${PKG_MANAGER} clean all &>/dev/null
            ${PKG_MANAGER} makecache &>/dev/null
        fi
    fi
}

# 尝试安装 inotify-tools（针对不同发行版）
install_inotify_tools() {
    log_step "安装 inotify-tools"
    
    # 对于 RHEL/CentOS/Kylin：需要 EPEL
    if [[ "${PKG_MANAGER}" == "dnf" ]] || [[ "${PKG_MANAGER}" == "yum" ]]; then
        setup_epel
        setup_kylin_repo
        if ${PKG_INSTALL} inotify-tools; then
            log_info "inotify-tools 安装成功"
            return 0
        else
            log_warn "通过包管理器安装失败，尝试手动编译安装..."
            compile_inotify_tools
            return $?
        fi
    else
        # Debian/Ubuntu/Alpine 等直接安装
        if ${PKG_INSTALL} inotify-tools; then
            log_info "inotify-tools 安装成功"
            return 0
        else
            log_error "安装失败，请手动安装 inotify-tools"
            exit 1
        fi
    fi
}

# 手动编译安装 inotify-tools（备用方案）—— 修正版
compile_inotify_tools() {
    log_info "开始编译安装 inotify-tools..."
    
    # 获取脚本所在目录的绝对路径（用于查找本地源码包）
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    local version="3.22.1.0"
    local local_tarball="${script_dir}/inotify-tools-${version}.tar.gz"
    
    local workdir="/tmp/inotify-tools-build"
    mkdir -p "${workdir}"
    cd "${workdir}"
    
    # 安装编译工具
    log_info "安装编译工具..."
    ${PKG_INSTALL} make automake gcc gcc-c++ || ${PKG_INSTALL} make automake gcc g++ || true
    
    # 优先使用本地源码包，否则在线下载
    if [[ -f "${local_tarball}" ]]; then
        log_info "找到本地源码包: ${local_tarball}，使用本地文件"
        cp "${local_tarball}" inotify-tools.tar.gz
    else
        log_info "未找到本地源码包，尝试在线下载..."
        local url="https://github.com/rvoicilas/inotify-tools/archive/refs/tags/${version}.tar.gz"
        wget --no-check-certificate "${url}" -O inotify-tools.tar.gz || curl -L "${url}" -o inotify-tools.tar.gz
    fi
    
    tar -xzf inotify-tools.tar.gz
    cd "inotify-tools-${version}"
    
    ./autogen.sh
    ./configure --prefix=/usr
    make
    make install
    
    # 更新动态链接库缓存
    ldconfig 2>/dev/null || true
    
    cd /
    rm -rf "${workdir}"
    
    if command -v inotifywait &>/dev/null; then
        log_info "编译安装成功"
        return 0
    else
        log_error "编译安装失败，请手动安装 inotify-tools"
        exit 1
    fi
}

# 主安装依赖函数
install_deps() {
    local pkgs=()
    command -v rsync &>/dev/null || pkgs+=("rsync")
    
    # 本地模式需要 inotify-tools
    if [[ "${MODE}" == "local" ]] && ! command -v inotifywait &>/dev/null; then
        pkgs+=("inotify-tools")
    fi
    
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log_info "所有依赖已安装"
        return
    fi
    
    log_step "安装依赖: ${pkgs[*]}"
    
    # 先安装 rsync（通常都很容易）
    if [[ " ${pkgs[*]} " == *" rsync "* ]]; then
        if ! ${PKG_INSTALL} rsync; then
            log_error "rsync 安装失败，请检查网络或软件源"
            exit 1
        fi
    fi
    
    # 安装 inotify-tools（如果需要）
    if [[ " ${pkgs[*]} " == *" inotify-tools "* ]]; then
        install_inotify_tools
    fi
    
    log_info "依赖处理完成"
}

#===============================================================================
# 本地服务器 - 已有配置检测
#===============================================================================

check_local_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        return 1
    fi
    
    source "${CONFIG_FILE}"
    
    log_step "检测到已有配置"
    echo -e "   ${BOLD}当前配置${NC}"
    echo -e "   备份服务器: ${GREEN}${REMOTE_HOST}:${REMOTE_PORT}::${REMOTE_MODULE}${NC}"
    echo -e "   本地目录  : ${GREEN}${LOCAL_DIR}${NC}"
    echo -e "   用户      : ${GREEN}${RSYNC_USER}${NC}\n"
    
    if systemctl is-active rsync-sync &>/dev/null; then
        echo -e "   服务状态: ${GREEN}运行中${NC}"
    else
        echo -e "   服务状态: ${YELLOW}未运行${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}请选择操作：${NC}"
    echo -e "  ${YELLOW}1${NC} - 查看服务状态和日志"
    echo -e "  ${YELLOW}2${NC} - 重新配置（覆盖当前配置）"
    echo -e "  ${YELLOW}3${NC} - 卸载"
    echo -e "  ${YELLOW}q${NC} - 退出"
    echo ""
    
    while true; do
        read -p "$(echo -e "${CYAN}► [1/2/3/q]:${NC} ")" choice
        case "${choice}" in
            1|"")
                show_local_status
                exit 0
                ;;
            2)
                return 2
                ;;
            3)
                do_uninstall_local
                exit 0
                ;;
            q|Q)
                exit 0
                ;;
            *)
                log_warn "输入 1/2/3 或 q"
                ;;
        esac
    done
}

show_local_status() {
    log_step "服务状态"
    systemctl status rsync-sync --no-pager || true
    
    echo ""
    log_step "最近日志"
    if [[ -f "${LOG_FILE}" ]]; then
        tail -20 "${LOG_FILE}"
    else
        log_warn "日志文件不存在"
    fi
}

do_uninstall_local() {
    log_step "卸载本地服务器"
    systemctl stop rsync-sync 2>/dev/null || true
    systemctl disable rsync-sync 2>/dev/null || true
    rm -rf "${INSTALL_DIR}"
    rm -f /etc/systemd/system/rsync-sync.service "${PASSWORD_FILE}"
    systemctl daemon-reload
    log_info "已卸载"
}

#===============================================================================
# 本地服务器配置
#===============================================================================

configure_local() {
    log_step "配置本地服务器"
    
    echo -e "请输入配置（${GREEN}直接回车使用默认值${NC}）：\n"
    
    print_line
    echo -e "${BOLD}【备份服务器 IP】${NC}"
    print_line
    while true; do
        read -p "$(echo -e "${CYAN}► IP [192.168.1.100]:${NC} ")" REMOTE_HOST
        REMOTE_HOST=${REMOTE_HOST:-192.168.1.100}
        [[ "${REMOTE_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && break
        log_warn "IP 格式错误"
    done
    
    read -p "$(echo -e "${CYAN}► 端口 [873]:${NC} ")" REMOTE_PORT
    REMOTE_PORT=${REMOTE_PORT:-873}
    
    print_line
    echo -e "${BOLD}【模块名称】${NC}"
    echo -e "  说明: 备份服务器上定义的模块名（不是路径）"
    echo -e "  注意: 建议使用字母开头，避免纯数字/点"
    echo -e "  ✓ 正确: server-a"
    echo -e "  ✗ 错误: 1.2.3.4"
    print_line
    read -p "$(echo -e "${CYAN}► 模块名 [backup]:${NC} ")" REMOTE_MODULE
    REMOTE_MODULE=${REMOTE_MODULE:-backup}
    REMOTE_MODULE=$(echo "${REMOTE_MODULE}" | sed 's|^/||' | sed 's|/$||')
    
    print_line
    echo -e "${BOLD}【本地同步目录】${NC}"
    print_line
    while true; do
        read -p "$(echo -e "${CYAN}► 目录 [/data/backup/]:${NC} ")" LOCAL_DIR
        LOCAL_DIR=${LOCAL_DIR:-/data/backup/}
        [[ "${LOCAL_DIR}" != */ ]] && LOCAL_DIR="${LOCAL_DIR}/"
        if [[ ! -d "${LOCAL_DIR}" ]]; then
            read -p "   创建目录? [Y/n]: " c
            [[ ! "${c}" =~ ^[Nn]$ ]] && mkdir -p "${LOCAL_DIR}" && log_info "已创建" || continue
        fi
        break
    done
    
    print_line
    echo -e "${BOLD}【认证信息】${NC}"
    echo -e "  必须与备份服务器配置一致"
    print_line
    read -p "$(echo -e "${CYAN}► 用户名 [rsync_backup]:${NC} ")" RSYNC_USER
    RSYNC_USER=${RSYNC_USER:-rsync_backup}
    
    while true; do
        read -s -p "$(echo -e "${CYAN}► 密码:${NC} ")" RSYNC_PASSWORD; echo ""
        [[ -z "${RSYNC_PASSWORD}" ]] && log_warn "密码不能为空" && continue
        read -s -p "$(echo -e "${CYAN}► 确认:${NC} ")" c; echo ""
        [[ "${RSYNC_PASSWORD}" == "${c}" ]] && break
        log_warn "密码不一致"
    done
    
    read -p "$(echo -e "${CYAN}► 监听事件 [modify,delete,create,attrib,move]:${NC} ")" WATCH_EVENTS
    WATCH_EVENTS=${WATCH_EVENTS:-modify,delete,create,attrib,move}
    
    read -p "$(echo -e "${CYAN}► rsync参数 [-azP --delete]:${NC} ")" RSYNC_OPTS
    RSYNC_OPTS=${RSYNC_OPTS:--azP --delete}
    
    read -p "$(echo -e "${CYAN}► 排除文件（回车跳过）:${NC} ")" EXCLUDE_PATTERNS
}

generate_local_config() {
    log_step "生成配置"
    
    mkdir -p "${INSTALL_DIR}"
    
    cat > "${CONFIG_FILE}" << EOF
REMOTE_HOST="${REMOTE_HOST}"
REMOTE_PORT="${REMOTE_PORT}"
REMOTE_MODULE="${REMOTE_MODULE}"
LOCAL_DIR="${LOCAL_DIR}"
RSYNC_USER="${RSYNC_USER}"
RSYNC_PASSWORD="${RSYNC_PASSWORD}"
WATCH_EVENTS="${WATCH_EVENTS}"
RSYNC_OPTS="${RSYNC_OPTS}"
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS}"
LOG_FILE="${LOG_FILE}"
EOF
    chmod 600 "${CONFIG_FILE}"
    
    echo "${RSYNC_PASSWORD}" > "${PASSWORD_FILE}"
    chmod 600 "${PASSWORD_FILE}"
    
    local exclude_args=""
    [[ -n "${EXCLUDE_PATTERNS}" ]] && for p in ${EXCLUDE_PATTERNS}; do exclude_args="${exclude_args} --exclude=${p}"; done
    
    cat > "${INSTALL_DIR}/sync-daemon.sh" << SCRIPT_EOF
#!/bin/bash
set -e
source "${CONFIG_FILE}"
LOCK="${INSTALL_DIR}/sync.lock"
log() { echo "\$(date '+%Y-%m-%d %H:%M:%S') \$1" >> "\${LOG_FILE}"; }
cleanup() { rm -f "\${LOCK}"; log "[INFO] 停止"; exit 0; }
[[ -f "\${LOCK}" ]] && { pid=\$(cat "\${LOCK}"); kill -0 "\${pid}" 2>/dev/null && echo "已运行" && exit 1; rm -f "\${LOCK}"; }
echo \$\$ > "\${LOCK}"
trap cleanup EXIT
mkdir -p "\${LOCAL_DIR}"
log "=========================================="
log "[INFO] 启动 | 目录: \${LOCAL_DIR} | 目标: \${REMOTE_HOST}::\${REMOTE_MODULE}"
log "=========================================="
rsync \${RSYNC_OPTS} --port="\${REMOTE_PORT}" --password-file="${PASSWORD_FILE}" ${exclude_args} "\${LOCAL_DIR}" "\${RSYNC_USER}@\${REMOTE_HOST}::\${REMOTE_MODULE}" && log "[INFO] 初始同步完成" || log "[WARN] 初始同步失败"
log "[INFO] 开始监听..."
inotifywait -mrq -e "\${WATCH_EVENTS}" --format '%w%f %e' "\${LOCAL_DIR}" 2>/dev/null | while read f e; do
    [[ "\$f" =~ \\.(swp|swx|tmp)$ ]] && continue
    log "[EVENT] \$e - \$f"
    rsync \${RSYNC_OPTS} --port="\${REMOTE_PORT}" --password-file="${PASSWORD_FILE}" ${exclude_args} "\${LOCAL_DIR}" "\${RSYNC_USER}@\${REMOTE_HOST}::\${REMOTE_MODULE}" && log "[SYNC] 成功" || log "[ERROR] 失败"
done
SCRIPT_EOF
    chmod +x "${INSTALL_DIR}/sync-daemon.sh"
    
    cat > /etc/systemd/system/rsync-sync.service << EOF
[Unit]
Description=rsync + inotify 同步服务
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/sync-daemon.sh
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable rsync-sync &>/dev/null
    
    log_info "配置文件: ${CONFIG_FILE}"
    log_info "密码文件: ${PASSWORD_FILE}"
    log_info "服务文件: /etc/systemd/system/rsync-sync.service"
}

#===============================================================================
# 备份服务器 - 已有配置检测
#===============================================================================

check_remote_config() {
    if [[ ! -f "${RSYNCD_CONF}" ]]; then
        return 1
    fi
    
    local modules=()
    while IFS= read -r line; do
        [[ "$line" =~ ^\[([^\]]+)\] ]] && modules+=("${BASH_REMATCH[1]}")
    done < "${RSYNCD_CONF}"
    
    if [[ ${#modules[@]} -eq 0 ]]; then
        return 1
    fi
    
    log_step "检测到已有配置"
    echo -e "   ${BOLD}已有模块${NC}\n"
    
    for m in "${modules[@]}"; do
        local path=$(grep -A20 "^\[${m}\]" "${RSYNCD_CONF}" | grep "^    path" | head -1 | awk '{print $3}')
        echo -e "   ${GREEN}•${NC} ${m} -> ${path}"
    done
    
    echo ""
    if systemctl is-active rsyncd &>/dev/null; then
        echo -e "   服务状态: ${GREEN}运行中${NC}"
    else
        echo -e "   服务状态: ${YELLOW}未运行${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}请选择操作：${NC}"
    echo -e "  ${YELLOW}1${NC} - 添加新模块"
    echo -e "  ${YELLOW}2${NC} - 修改模块"
    echo -e "  ${YELLOW}3${NC} - 删除模块"
    echo -e "  ${YELLOW}4${NC} - 查看服务状态"
    echo -e "  ${YELLOW}q${NC} - 退出"
    echo ""
    
    while true; do
        read -p "$(echo -e "${CYAN}► [1/2/3/4/q]:${NC} ")" choice
        case "${choice}" in
            1|"")
                return 2
                ;;
            2)
                modify_remote_module
                exit 0
                ;;
            3)
                delete_remote_module
                exit 0
                ;;
            4)
                show_remote_status
                exit 0
                ;;
            q|Q)
                exit 0
                ;;
            *)
                log_warn "输入 1/2/3/4 或 q"
                ;;
        esac
    done
}

modify_remote_module() {
    log_step "修改模块"
    
    local modules=()
    while IFS= read -r line; do
        [[ "$line" =~ ^\[([^\]]+)\] ]] && modules+=("${BASH_REMATCH[1]}")
    done < "${RSYNCD_CONF}"
    
    echo -e "${BOLD}选择要修改的模块：${NC}"
    for i in "${!modules[@]}"; do
        echo -e "  ${YELLOW}$((i+1))${NC} - ${modules[$i]}"
    done
    echo ""
    
    local selected
    while true; do
        read -p "$(echo -e "${CYAN}► 序号:${NC} ")" selected
        [[ "$selected" =~ ^[0-9]+$ ]] && [[ "$selected" -ge 1 ]] && [[ "$selected" -le ${#modules[@]} ]] && break
        log_warn "输入有效序号"
    done
    
    REMOTE_MODULE="${modules[$((selected-1))]}"
    log_info "选择模块: ${REMOTE_MODULE}"
    
    LOCAL_DIR=$(grep -A20 "^\[${REMOTE_MODULE}\]" "${RSYNCD_CONF}" | grep "^    path" | head -1 | awk '{print $3}')
    ALLOW_HOSTS=$(grep -A20 "^\[${REMOTE_MODULE}\]" "${RSYNCD_CONF}" | grep "^    hosts allow" | head -1 | sed 's/.*hosts allow = //')
    
    echo -e "\n${BOLD}当前配置${NC}"
    echo -e "  目录: ${LOCAL_DIR}"
    echo -e "  允许: ${ALLOW_HOSTS}"
    echo ""
    
    print_line
    echo -e "${BOLD}【存储目录】${NC}"
    print_line
    read -p "$(echo -e "${CYAN}► 目录 [${LOCAL_DIR}]:${NC} ")" new_dir
    LOCAL_DIR=${new_dir:-${LOCAL_DIR}}
    [[ "${LOCAL_DIR}" != */ ]] && LOCAL_DIR="${LOCAL_DIR}/"
    mkdir -p "${LOCAL_DIR}"
    
    print_line
    echo -e "${BOLD}【允许的 IP】${NC}"
    print_line
    read -p "$(echo -e "${CYAN}► IP [${ALLOW_HOSTS}]:${NC} ")" new_hosts
    ALLOW_HOSTS=${new_hosts:-${ALLOW_HOSTS}}
    
    sed -i "/^\[${REMOTE_MODULE}\]/,/^\[/ s|path = .*|path = ${LOCAL_DIR}|" "${RSYNCD_CONF}"
    sed -i "/^\[${REMOTE_MODULE}\]/,/^\[/ s|hosts allow = .*|hosts allow = ${ALLOW_HOSTS}|" "${RSYNCD_CONF}"
    
    log_info "已更新模块: ${REMOTE_MODULE}"
    systemctl restart rsyncd
    log_info "服务已重启"
    
    show_remote_done "${REMOTE_MODULE}" "${LOCAL_DIR}"
}

delete_remote_module() {
    log_step "删除模块"
    
    local modules=()
    while IFS= read -r line; do
        [[ "$line" =~ ^\[([^\]]+)\] ]] && modules+=("${BASH_REMATCH[1]}")
    done < "${RSYNCD_CONF}"
    
    echo -e "${BOLD}选择要删除的模块：${NC}"
    for i in "${!modules[@]}"; do
        local path=$(grep -A20 "^\[${modules[$i]}\]" "${RSYNCD_CONF}" | grep "^    path" | head -1 | awk '{print $3}')
        echo -e "  ${YELLOW}$((i+1))${NC} - ${modules[$i]} -> ${path}"
    done
    echo ""
    
    local selected
    while true; do
        read -p "$(echo -e "${CYAN}► 序号:${NC} ")" selected
        [[ "$selected" =~ ^[0-9]+$ ]] && [[ "$selected" -ge 1 ]] && [[ "$selected" -le ${#modules[@]} ]] && break
        log_warn "输入有效序号"
    done
    
    local module_to_delete="${modules[$((selected-1))]}"
    
    echo ""
    read -p "$(echo -e "${YELLOW}确认删除 ${module_to_delete}? [y/N]:${NC} ")" confirm
    [[ ! "${confirm}" =~ ^[Yy]$ ]] && log_warn "已取消" && exit 0
    
    sed -i "/^\[${module_to_delete}\]/,/^\[/d" "${RSYNCD_CONF}"
    sed -i '/^$/N;/^\n$/d' "${RSYNCD_CONF}"
    
    log_info "已删除模块: ${module_to_delete}"
    
    local remaining=$(grep "^\[" "${RSYNCD_CONF}" | wc -l)
    if [[ "$remaining" -eq 0 ]]; then
        echo ""
        read -p "$(echo -e "${YELLOW}已无模块，是否卸载? [Y/n]:${NC} ")" uninstall
        [[ ! "${uninstall}" =~ ^[Nn]$ ]] && do_uninstall_remote && exit 0
    fi
    
    systemctl restart rsyncd
    log_info "服务已重启"
}

show_remote_status() {
    log_step "服务状态"
    systemctl status rsyncd --no-pager || true
    
    echo ""
    log_step "最近日志"
    if [[ -f /var/log/rsyncd.log ]]; then
        tail -20 /var/log/rsyncd.log
    else
        log_warn "日志文件不存在"
    fi
}

do_uninstall_remote() {
    log_step "卸载备份服务器"
    systemctl stop rsyncd 2>/dev/null || true
    systemctl disable rsyncd 2>/dev/null || true
    rm -f "${RSYNCD_CONF}" "${RSYNCD_SECRETS}" /etc/systemd/system/rsyncd.service
    systemctl daemon-reload
    log_info "已卸载"
}

#===============================================================================
# 备份服务器配置
#===============================================================================

configure_remote() {
    log_step "配置备份服务器"
    
    echo -e "请输入配置（${GREEN}直接回车使用默认值${NC}）：\n"
    
    print_line
    echo -e "${BOLD}【模块名称】${NC}"
    echo -e "  为这台本地服务器定义一个唯一的模块名"
    echo -e "  建议使用字母开头，避免纯数字/点"
    echo -e "  示例: server-a, web1, db-backup"
    print_line
    while true; do
        read -p "$(echo -e "${CYAN}► 模块名 [backup]:${NC} ")" REMOTE_MODULE
        REMOTE_MODULE=${REMOTE_MODULE:-backup}
        [[ "${REMOTE_MODULE}" == *"/"* ]] && log_warn "不能包含 /" && continue
        
        if [[ -f "${RSYNCD_CONF}" ]] && grep -q "^\[${REMOTE_MODULE}\]" "${RSYNCD_CONF}"; then
            log_warn "模块 ${REMOTE_MODULE} 已存在"
            read -p "   覆盖? [y/N]: " overwrite
            [[ "${overwrite}" =~ ^[Yy]$ ]] || continue
        fi
        break
    done
    
    print_line
    echo -e "${BOLD}【存储目录】${NC}"
    print_line
    while true; do
        read -p "$(echo -e "${CYAN}► 目录 [/data/backup/]:${NC} ")" LOCAL_DIR
        LOCAL_DIR=${LOCAL_DIR:-/data/backup/}
        [[ "${LOCAL_DIR}" != */ ]] && LOCAL_DIR="${LOCAL_DIR}/"
        if [[ ! -d "${LOCAL_DIR}" ]]; then
            read -p "   创建目录? [Y/n]: " c
            [[ ! "${c}" =~ ^[Nn]$ ]] && mkdir -p "${LOCAL_DIR}" && log_info "已创建" || continue
        fi
        break
    done
    
    read -p "$(echo -e "${CYAN}► 端口 [873]:${NC} ")" REMOTE_PORT
    REMOTE_PORT=${REMOTE_PORT:-873}
    
    print_line
    echo -e "${BOLD}【认证信息】${NC}"
    echo -e "  ${YELLOW}请记住，配置本地服务器时需要使用${NC}"
    print_line
    read -p "$(echo -e "${CYAN}► 用户名 [rsync_backup]:${NC} ")" RSYNC_USER
    RSYNC_USER=${RSYNC_USER:-rsync_backup}
    
    while true; do
        read -s -p "$(echo -e "${CYAN}► 密码:${NC} ")" RSYNC_PASSWORD; echo ""
        [[ -z "${RSYNC_PASSWORD}" ]] && log_warn "密码不能为空" && continue
        read -s -p "$(echo -e "${CYAN}► 确认:${NC} ")" c; echo ""
        [[ "${RSYNC_PASSWORD}" == "${c}" ]] && break
        log_warn "密码不一致"
    done
    
    print_line
    echo -e "${BOLD}【允许的 IP】${NC}"
    echo -e "  多个IP用空格分隔，建议添加数据源 IP"
    print_line
    read -p "$(echo -e "${CYAN}► IP [192.168.0.0/16]:${NC} ")" ALLOW_HOSTS
    ALLOW_HOSTS=${ALLOW_HOSTS:-192.168.0.0/16}
}

generate_remote_config() {
    log_step "生成配置"
    
    mkdir -p "${LOCAL_DIR}"
    
    # 创建或更新密码文件
    if [[ -f "${RSYNCD_SECRETS}" ]] && ! grep -q "^${RSYNC_USER}:" "${RSYNCD_SECRETS}" 2>/dev/null; then
        echo "${RSYNC_USER}:${RSYNC_PASSWORD}" >> "${RSYNCD_SECRETS}"
    else
        echo "${RSYNC_USER}:${RSYNC_PASSWORD}" > "${RSYNCD_SECRETS}"
    fi
    chmod 600 "${RSYNCD_SECRETS}"
    
    # 创建全局配置（如果不存在）
    if [[ ! -f "${RSYNCD_CONF}" ]]; then
        cat > "${RSYNCD_CONF}" << 'EOF'
# rsync daemon 配置
uid = root
gid = root
use chroot = yes
max connections = 100
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsyncd.lock
log file = /var/log/rsyncd.log
timeout = 300
reverse lookup = no

EOF
    else
        # 确保全局有 uid/gid 设置，否则添加
        if ! grep -q "^uid =" "${RSYNCD_CONF}" && ! grep -q "^uid[[:space:]]*=" "${RSYNCD_CONF}"; then
            sed -i '1i uid = root\ngid = root\n' "${RSYNCD_CONF}"
        fi
    fi
    
    # 删除可能存在的同名模块
    if grep -q "^\[${REMOTE_MODULE}\]" "${RSYNCD_CONF}"; then
        sed -i "/^\[${REMOTE_MODULE}\]/,/^\[/d" "${RSYNCD_CONF}"
        sed -i '/^$/N;/^\n$/d' "${RSYNCD_CONF}"
    fi
    
    # 添加新模块
    cat >> "${RSYNCD_CONF}" << EOF

[${REMOTE_MODULE}]
    path = ${LOCAL_DIR}
    read only = no
    list = yes
    auth users = ${RSYNC_USER}
    secrets file = ${RSYNCD_SECRETS}
    hosts allow = ${ALLOW_HOSTS}
    ignore errors = yes
    dont compress = *.gz *.zip *.bz2 *.rpm *.deb
EOF

    log_info "配置文件: ${RSYNCD_CONF}"
    log_info "密码文件: ${RSYNCD_SECRETS}"
}

create_rsyncd_service() {
    log_step "创建 systemd 服务"
    
    cat > /etc/systemd/system/rsyncd.service << 'EOF'
[Unit]
Description=rsync daemon 服务
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rsync --daemon --no-detach
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable rsyncd &>/dev/null
    
    log_info "服务文件: /etc/systemd/system/rsyncd.service"
}

start_rsyncd_service() {
    log_step "启动服务"
    
    systemctl stop rsyncd 2>/dev/null || pkill -x rsync 2>/dev/null || true
    sleep 1
    
    systemctl start rsyncd
    sleep 2
    
    if systemctl is-active rsyncd &>/dev/null; then
        log_info "rsyncd 服务已启动"
    else
        log_error "启动失败"
        journalctl -u rsyncd -n 20 --no-pager
        exit 1
    fi
}

#===============================================================================
# 完成提示
#===============================================================================

show_local_done() {
    log_step "配置完成"
    echo -e "   ${GREEN}✓${NC} 本地服务器配置完成\n"
    echo -e "   ${BOLD}systemd 管理${NC}"
    echo -e "   systemctl start rsync-sync     # 启动"
    echo -e "   systemctl stop rsync-sync      # 停止"
    echo -e "   systemctl restart rsync-sync   # 重启"
    echo -e "   systemctl status rsync-sync    # 状态"
    echo -e "   systemctl enable rsync-sync    # 开机启动"
    echo -e "   systemctl disable rsync-sync   # 禁用启动\n"
    echo -e "   ${BOLD}日志${NC}"
    echo -e "   tail -f ${LOG_FILE}\n"
    echo -e "   ${BOLD}配置${NC}"
    echo -e "   本地目录: ${LOCAL_DIR}"
    echo -e "   备份服务器: ${REMOTE_HOST}:${REMOTE_PORT}::${REMOTE_MODULE}\n"
}

show_remote_done() {
    local module="${1:-${REMOTE_MODULE}}"
    local dir="${2:-${LOCAL_DIR}}"
    local ip=$(hostname -I | awk '{print $1}')
    
    log_step "配置完成"
    
    echo -e "   ${GREEN}✓${NC} 备份服务器配置完成\n"
    echo -e "   ${BOLD}systemd 管理${NC}"
    echo -e "   systemctl start rsyncd     # 启动"
    echo -e "   systemctl stop rsyncd      # 停止"
    echo -e "   systemctl restart rsyncd   # 重启"
    echo -e "   systemctl status rsyncd    # 状态"
    echo -e "   systemctl enable rsyncd    # 开机启动"
    echo -e "   systemctl disable rsyncd   # 禁用启动\n"
    echo -e "   ${BOLD}日志${NC}"
    echo -e "   tail -f /var/log/rsyncd.log\n"
    echo -e "   ${GREEN}────────────────────────────────────────${NC}"
    echo -e "   ${BOLD}本地服务器配置信息${NC}"
    echo -e "   IP    : ${YELLOW}${ip}${NC}"
    echo -e "   端口  : ${YELLOW}${REMOTE_PORT:-873}${NC}"
    echo -e "   模块  : ${YELLOW}${module}${NC}"
    echo -e "   用户  : ${YELLOW}${RSYNC_USER:-rsync_backup}${NC}"
    echo -e "   密码  : ${YELLOW}（您设置的密码）${NC}"
    echo -e "   ${GREEN}────────────────────────────────────────${NC}\n"
}

#===============================================================================
# 主函数
#===============================================================================

main() {
    case "${1:-}" in
        start)
            systemctl start rsync-sync 2>/dev/null || systemctl start rsyncd 2>/dev/null
            log_info "已启动"
            exit 0
            ;;
        stop)
            systemctl stop rsync-sync 2>/dev/null || systemctl stop rsyncd 2>/dev/null
            log_info "已停止"
            exit 0
            ;;
        restart)
            systemctl restart rsync-sync 2>/dev/null || systemctl restart rsyncd 2>/dev/null
            log_info "已重启"
            exit 0
            ;;
        status)
            systemctl status rsync-sync 2>/dev/null || systemctl status rsyncd 2>/dev/null
            exit 0
            ;;
        logs)
            [[ -f "${LOG_FILE}" ]] && tail -f "${LOG_FILE}" || tail -f /var/log/rsyncd.log
            exit 0
            ;;
        uninstall)
            systemctl stop rsync-sync 2>/dev/null || true
            systemctl stop rsyncd 2>/dev/null || true
            rm -rf "${INSTALL_DIR}" /etc/systemd/system/rsync-sync.service "${PASSWORD_FILE}"
            rm -f "${RSYNCD_CONF}" "${RSYNCD_SECRETS}" /etc/systemd/system/rsyncd.service
            systemctl daemon-reload
            log_info "已卸载"
            exit 0
            ;;
        help|--help|-h)
            echo ""
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  (无参数)     配置向导"
            echo "  start        启动服务"
            echo "  stop         停止服务"
            echo "  restart      重启服务"
            echo "  status       查看状态"
            echo "  logs         查看日志"
            echo "  uninstall    卸载"
            echo ""
            exit 0
            ;;
    esac
    
    print_banner
    check_root
    detect_system
    
    echo -e "${BOLD}选择角色：${NC}"
    echo -e "  ${YELLOW}1${NC} - 本地服务器（数据源）"
    echo -e "  ${YELLOW}2${NC} - 备份服务器（接收端）"
    echo ""
    
    while true; do
        read -p "$(echo -e "${CYAN}► [1/2]:${NC} ")" m
        case "${m}" in
            1|"") MODE="local"; log_info "本地服务器（数据源）"; break ;;
            2) MODE="remote"; log_info "备份服务器（接收端）"; break ;;
            *) log_warn "输入 1 或 2" ;;
        esac
    done
    
    install_deps
    
    if [[ "${MODE}" == "local" ]]; then
        check_local_config || true
        
        configure_local
        log_step "确认配置"
        echo -e "   备份服务器: ${GREEN}${REMOTE_HOST}:${REMOTE_PORT}${NC}"
        echo -e "   模块: ${GREEN}${REMOTE_MODULE}${NC}"
        echo -e "   目录: ${GREEN}${LOCAL_DIR}${NC}\n"
        read -p "确认? [Y/n]: " c
        [[ "${c}" =~ ^[Nn]$ ]] && exit 0
        generate_local_config
        systemctl start rsync-sync
        show_local_done
    else
        check_remote_config || true
        
        configure_remote
        log_step "确认配置"
        echo -e "   模块: ${GREEN}${REMOTE_MODULE}${NC}"
        echo -e "   目录: ${GREEN}${LOCAL_DIR}${NC}\n"
        read -p "确认? [Y/n]: " c
        [[ "${c}" =~ ^[Nn]$ ]] && exit 0
        generate_remote_config
        create_rsyncd_service
        start_rsyncd_service
        show_remote_done
    fi
}

main "$@"