#!/bin/sh
#
# lib/packages.sh —— 按 package.list 安装软件包
#   被 install.sh source 调用
#   定义 install_packages()
#

_dl_bin() {
    _url="$1"
    _bin="$2"
    echo "  [dl] ${_bin} <- ${_url}"
    wget -q -O "/usr/local/bin/${_bin}" "${_url}"
    chmod +x "/usr/local/bin/${_bin}"
}

# install_packages <package.list 路径>
install_packages() {
    _PKG_LIST="${1:-$SCRIPT_DIR/package.list}"

    echo "[packages] === 安装软件包 ==="
    [ -f "${_PKG_LIST}" ] || { echo "[packages] ${_PKG_LIST} 不存在!"; return 1; }

    apk update

    while read -r _line_; do
        [ -z "${_line_}" ] && continue
        case "${_line_}" in '#'*) continue ;; esac

        case "${_line_}" in
            '[pm]'*)
                _pkg_="${_line_#\[pm\] }"
                echo "  [pm] ${_pkg_}"
                apk add --no-cache "${_pkg_}"
                ;;
            '[dl@'*)
                _line_="${_line_#\[dl@}"
                _url_="${_line_%%\] *}"
                _bin_="${_line_#*\] }"
                _dl_bin "${_url_}" "${_bin_}"
                ;;
            *)
                echo "  [skip] 无法解析: ${_line_}"
                ;;
        esac
    done < "${_PKG_LIST}"

    echo "[packages] 完成。"
}
