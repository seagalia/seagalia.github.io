#!/bin/sh
# Installs a Seagalia product binary from its GitHub release.
#
#   curl -fsSL https://seagalia.io/install.sh | sh -s -- flock
#   curl -fsSL https://seagalia.io/install.sh | sh -s -- vigie v0.3.1
#
# Every product is released by the same goreleaser config, so the archive layout is shared:
#   https://github.com/seagalia/<product>/releases/download/v<version>/<product>_<version>_<os>_<arch>.tar.gz
# with a .zip on windows, wrapped in a directory of the same name, next to a checksums.txt.
#
# The binary goes to /usr/local/bin when it is writable, to ~/.local/bin otherwise (~/bin on windows), so the default
# never asks for a password. Set INSTALL_DIR to choose another directory, sudo is used only if it is not writable.
set -eu

OWNER="seagalia"

# Escape codes would garble logs and pipes, so color only goes to a terminal, and NO_COLOR (no-color.org) turns it off.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD="$(printf '\033[1m')"
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    BLUE="$(printf '\033[34m')"
    RESET="$(printf '\033[0m')"
else
    BOLD="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

usage() {
    echo "${BOLD}usage:${RESET} install.sh <product> [version]"
    echo "  product   name of the product to install, e.g. flock or vigie"
    echo "  version   release to install, e.g. v0.3.1 or 0.3.1 (default: latest)"
}

info() {
    echo "${BLUE}==>${RESET} ${BOLD}$*${RESET}"
}

warn() {
    echo "${YELLOW}warning:${RESET} $*" >&2
}

fail() {
    echo "${RED}${BOLD}error:${RESET} $*" >&2
    exit 1
}

has() {
    command -v "$1" >/dev/null 2>&1
}

# Terminals answer the OSC 11 query with their background as rgb:RRRR/GGGG/BBBB, like flock's banner asks lipgloss to.
# It goes through /dev/tty because stdin is the downloaded script when piped from curl.
has_light_background() {
    saved_tty="$(stty -g </dev/tty 2>/dev/null)" || return 1
    stty raw -echo min 0 time 3 </dev/tty
    printf '\033]11;?\033\\' >/dev/tty
    answer="$(dd bs=64 count=1 </dev/tty 2>/dev/null)"
    stty "$saved_tty" </dev/tty

    # Only the two high hex digits of each channel matter for telling light from dark.
    channel='\([0-9a-fA-F][0-9a-fA-F]\)[^/]*'
    rgb="$(printf '%s' "$answer" | sed -n "s|.*rgb:${channel}/${channel}/${channel}.*|\\1 \\2 \\3|p")"
    [ -n "$rgb" ] || return 1
    set -- $rgb
    luminance=$(( (299 * 0x$1 + 587 * 0x$2 + 114 * 0x$3) / 1000 ))
    [ "$luminance" -gt 128 ]
}

# The logo is skipped outside a terminal, where it would only clutter logs, and on a terminal narrower than its 80
# columns, where wrapped lines would break the drawing.
print_banner() {
    [ -t 1 ] || return 0
    columns="$(stty size </dev/tty 2>/dev/null | awk '{print $2}')"
    if [ -n "$columns" ] && [ "$columns" -lt 80 ]; then
        return 0
    fi

    if [ -z "$RESET" ]; then
        printf '%s\n' "$BANNER_DARK" | sed 's/\\033\[[0-9;]*m//g'
        return 0
    fi
    banner="$BANNER_DARK"
    if has_light_background; then
        banner="$BANNER_LIGHT"
    fi
    printf '%b\n' "$banner"
}

# download <url> <output file>
download() {
    if has curl; then
        curl -fsSL -o "$2" "$1"
    elif has wget; then
        wget -q -O "$2" "$1"
    else
        fail "curl or wget is required"
    fi
}

# Same as download, with a progress bar on a terminal for files big enough to wait on.
download_with_progress() {
    if [ ! -t 2 ]; then
        download "$1" "$2"
        return
    fi
    if has curl; then
        curl -fSL --progress-bar -o "$2" "$1"
    elif has wget && wget --help 2>&1 | grep -q -- --show-progress; then
        wget -q --show-progress -O "$2" "$1"
    elif has wget; then
        # busybox wget has no --show-progress and draws its bar unless -q is given
        wget -O "$2" "$1"
    else
        fail "curl or wget is required"
    fi
}

detect_os() {
    case "$(uname -s)" in
        Linux) echo "linux" ;;
        Darwin) echo "darwin" ;;
        MINGW* | MSYS* | CYGWIN*) echo "windows" ;;
        *) fail "unsupported operating system: $(uname -s)" ;;
    esac
}

detect_arch() {
    arch="$(uname -m)"
    # A shell running under Rosetta reports x86_64 on Apple silicon, the native arm64 binary is the better pick.
    if [ "$arch" = "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
        arch="arm64"
    fi
    case "$arch" in
        x86_64 | amd64) echo "amd64" ;;
        aarch64 | arm64) echo "arm64" ;;
        *) fail "unsupported architecture: $arch (releases exist for amd64 and arm64)" ;;
    esac
}

# GitHub resolves the latest release as a redirect, which avoids the API rate limit. Prereleases are never "latest".
latest_tag() {
    latest_url="https://github.com/${OWNER}/$1/releases/latest"
    if has curl; then
        resolved="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$latest_url" 2>/dev/null || true)"
    else
        resolved="$(wget -S --spider "$latest_url" 2>&1 | grep -i '^ *location:' | tail -n 1 | tr -d '\r' | awk '{print $2}')"
    fi
    tag="${resolved##*/}"
    case "$tag" in
        v*) echo "$tag" ;;
        *) fail "no release found for $1, check the product name" ;;
    esac
}

verify_checksum() {
    archive_path="$1"
    checksums_path="$2"
    expected="$(grep " $(basename "$archive_path")\$" "$checksums_path" | awk '{print $1}')"
    [ -n "$expected" ] || fail "$(basename "$archive_path") is missing from checksums.txt"

    if has sha256sum; then
        actual="$(sha256sum "$archive_path" | awk '{print $1}')"
    elif has shasum; then
        actual="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
    else
        warn "sha256sum or shasum not found, skipping checksum verification"
        return 0
    fi
    [ "$expected" = "$actual" ] || fail "checksum mismatch for $(basename "$archive_path")"
}

main() {
    product="${1:-}"
    case "$product" in
        "" | -h | --help)
            usage
            exit 1
            ;;
    esac
    requested_version="${2:-latest}"

    print_banner
    os="$(detect_os)"
    arch="$(detect_arch)"

    if [ "$requested_version" = "latest" ]; then
        tag="$(latest_tag "$product")"
    else
        # Tags carry a "v" prefix but archive names do not, so accept the version written either way.
        tag="v${requested_version#v}"
    fi
    version="${tag#v}"

    binary="$product"
    extension="tar.gz"
    default_install_dir="${HOME}/.local/bin"
    if [ -w /usr/local/bin ]; then
        default_install_dir="/usr/local/bin"
    fi
    if [ "$os" = "windows" ]; then
        binary="${product}.exe"
        extension="zip"
        default_install_dir="${HOME}/bin"
    fi
    install_dir="${INSTALL_DIR:-$default_install_dir}"

    archive_name="${product}_${version}_${os}_${arch}"
    release_url="https://github.com/${OWNER}/${product}/releases/download/${tag}"

    work_dir="$(mktemp -d)"
    trap 'rm -rf "$work_dir"' EXIT

    info "Installing ${product} ${tag} (${os}/${arch})"
    download_with_progress "${release_url}/${archive_name}.${extension}" "${work_dir}/${archive_name}.${extension}" \
        || fail "could not download ${release_url}/${archive_name}.${extension}, check the product name and version"
    download "${release_url}/checksums.txt" "${work_dir}/checksums.txt" \
        || fail "could not download ${release_url}/checksums.txt"
    verify_checksum "${work_dir}/${archive_name}.${extension}" "${work_dir}/checksums.txt"

    if [ "$extension" = "zip" ]; then
        has unzip || fail "unzip is required"
        unzip -q "${work_dir}/${archive_name}.zip" -d "$work_dir"
    else
        tar -xzf "${work_dir}/${archive_name}.tar.gz" -C "$work_dir"
    fi
    extracted_binary="${work_dir}/${archive_name}/${binary}"
    [ -f "$extracted_binary" ] || fail "${binary} not found in ${archive_name}.${extension}"

    sudo_cmd=""
    mkdir -p "$install_dir" 2>/dev/null || true
    if [ ! -w "$install_dir" ]; then
        has sudo || fail "${install_dir} is not writable, set INSTALL_DIR to a directory you own"
        sudo_cmd="sudo"
    fi
    $sudo_cmd mkdir -p "$install_dir"
    $sudo_cmd install -m 755 "$extracted_binary" "${install_dir}/${binary}"

    echo "${GREEN}${BOLD}✓${RESET} ${BOLD}${product} ${tag}${RESET} installed to ${install_dir}/${binary}"
    case ":${PATH}:" in
        *":${install_dir}:"*) ;;
        *) warn "${install_dir} is not in your PATH, add it with: export PATH=\"${install_dir}:\$PATH\"" ;;
    esac
}

# BEGIN banner, generated by scripts/banner.py
BANNER_DARK='
             \033[38;2;11;143;222m⢀⣀⣀\033[0m
             \033[38;2;11;143;222m⢈⣙⣿⣿⣶⣄\033[0m
            \033[38;2;8;120;184m⠚⣫⣽⣿\033[38;2;255;249;240m⣿⣿⣿⣷⣶⣄\033[0m
            \033[38;2;11;143;222m⣴\033[38;2;248;241;231m⣿\033[38;2;255;249;240m⣿⣿\033[38;2;229;222;211m⣿\033[38;2;255;249;240m⣿⣿⣿⣿\033[38;2;229;222;211m⡏\033[38;2;255;249;240m⣷\033[0m
           \033[38;2;11;143;222m⢸\033[38;2;248;241;231m⣿\033[38;2;255;249;240m⣿⣿\033[38;2;255;255;255m⣿\033[38;2;8;120;184m⡁⠙\033[38;2;255;249;240m⣿⣿\033[38;2;255;156;33m⣿⣿⣿⡿⠒\033[0m
           \033[38;2;11;143;222m⢸\033[38;2;131;207;255m⣿\033[38;2;255;249;240m⣿⣿⣿⣷⣾⣿⣿⣿⣿⣿\033[0m
           \033[38;2;131;207;255m⢸\033[38;2;255;249;240m⣿\033[38;2;248;241;231m⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;231;239;242m⣄          \033[38;2;11;143;222m⣴⡾⠿⠿⠖                        ⢸⡇ ⠸⠇\033[0m
           \033[38;2;11;143;222m⣸\033[38;2;131;207;255m⣿\033[38;2;11;143;222m⣿⣿⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿\033[38;2;131;207;255m⣷⡄        \033[38;2;11;143;222m⠻⣷⣤⣄⡀ ⣰⡿⠛⣷⡄ ⠟⠛⢻⣷ ⢠⣾⠛⢿⣿⠃⠘⠛⠛⣿⡆ ⢸⡇ ⢸⡇ ⠸⠛⠻⣷⡄\033[0m
         \033[38;2;11;143;222m⢀⣴⣿⣿⣿⣿⣿⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿\033[38;2;131;207;255m⣿⡀         \033[38;2;11;143;222m⠉⢻⣿ ⣿⡷⠶⠿⠇⢠⣶⠟⢻⣿ ⠘⣿⡶⠾⠏ ⣰⡾⠛⣿⡇ ⢸⡇ ⢸⡇ ⣴⡞⠛⣿⡇\033[0m
       \033[38;2;11;143;222m⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;11;143;222m⣿\033[38;2;131;207;255m⠇       \033[38;2;11;143;222m⠻⠿⠾⠿⠋ ⠙⠿⠶⠾⠇⠈⠿⠶⠞⠿⠆⢀⣿⠶⢶⣶⡄⠙⠿⠶⠻⠷ ⠸⠇ ⠸⠇ ⠻⠷⠾⠻⠇\033[0m
     \033[38;2;131;207;255m⢀⣼⣿\033[38;2;11;143;222m⣿⣿⣿⣿⣿⣿⣿\033[38;2;131;207;255m⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;131;207;255m⣿⠏                         \033[38;2;11;143;222m⠸⢿⣶⣶⠿⠃\033[0m
     \033[38;2;131;207;255m⠾⠿⠿⣿⣿⣿\033[38;2;11;143;222m⣿\033[38;2;131;207;255m⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿⡿\033[38;2;248;241;231m⠟\033[38;2;131;207;255m⠁\033[0m
       \033[38;2;231;239;242m⣠⣼⣿\033[38;2;236;231;223m⣿⡿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿\033[38;2;236;231;223m⡿⠛\033[38;2;248;241;231m⠉\033[0m
       \033[38;2;231;239;242m⠈     \033[38;2;255;156;33m⣸⡇   ⣾⡃\033[0m
            \033[38;2;255;156;33m⠛⠙⠿⠉ ⠉⠉⠛⠛⠓\033[0m
'
BANNER_LIGHT='
             \033[38;2;11;143;222m⢀⣀⣀\033[0m
             \033[38;2;11;143;222m⢈⣙⣿⣿⣶⣄\033[0m
            \033[38;2;8;120;184m⠚⣫⣽⣿\033[38;2;255;249;240m⣿⣿⣿⣷⣶⣄\033[0m
            \033[38;2;11;143;222m⣴\033[38;2;248;241;231m⣿\033[38;2;255;249;240m⣿⣿\033[38;2;229;222;211m⣿\033[38;2;255;249;240m⣿⣿⣿⣿\033[38;2;229;222;211m⣿\033[38;2;255;249;240m⣷\033[0m
           \033[38;2;11;143;222m⢸\033[38;2;248;241;231m⣿\033[38;2;255;249;240m⣿⣿\033[38;2;255;255;255m⣿\033[38;2;11;47;85m⣿\033[38;2;7;59;116m⣿\033[38;2;255;249;240m⣿⣿\033[38;2;255;156;33m⣿⣿⣿⡿⠒\033[0m
           \033[38;2;11;143;222m⢸\033[38;2;223;228;229m⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿\033[0m
           \033[38;2;11;143;222m⢸⣿\033[38;2;248;241;231m⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;229;222;211m⣄          \033[38;2;11;143;222m⣴⡾⠿⠿⠖                        ⢸⡇ ⠸⠇\033[0m
           \033[38;2;11;143;222m⣸⣿⣿⣿⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿\033[38;2;7;59;116m⣷⡄        \033[38;2;11;143;222m⠻⣷⣤⣄⡀ ⣰⡿⠛⣷⡄ ⠟⠛⢻⣷ ⢠⣾⠛⢿⣿⠃⠘⠛⠛⣿⡆ ⢸⡇ ⢸⡇ ⠸⠛⠻⣷⡄\033[0m
         \033[38;2;8;120;184m⢀\033[38;2;11;143;222m⣴⣿⣿⣿⣿⣿⣿\033[38;2;8;120;184m⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿\033[38;2;7;59;116m⣿⡀         \033[38;2;11;143;222m⠉⢻⣿ ⣿⡷⠶⠿⠇⢠⣶⠟⢻⣿ ⠘⣿⡶⠾⠏ ⣰⡾⠛⣿⡇ ⢸⡇ ⢸⡇ ⣴⡞⠛⣿⡇\033[0m
       \033[38;2;11;143;222m⢀⣴⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;7;59;116m⣿⠇       \033[38;2;11;143;222m⠻⠿⠾⠿⠋ ⠙⠿⠶⠾⠇⠈⠿⠶⠞⠿⠆⢀⣿⠶⢶⣶⡄⠙⠿⠶⠻⠷ ⠸⠇ ⠸⠇ ⠻⠷⠾⠻⠇\033[0m
     \033[38;2;7;59;116m⢀⣼⣿\033[38;2;8;120;184m⣿\033[38;2;11;143;222m⣿⣿⣿⣿⣿⣿\033[38;2;8;120;184m⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿⣿\033[38;2;7;59;116m⠏                         \033[38;2;11;143;222m⠸⢿⣶⣶⠿⠃\033[0m
     \033[38;2;7;59;116m⠾⠿⠿⣿⣿⣿\033[38;2;11;143;222m⣿\033[38;2;7;59;116m⣿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿⣿⣿⡿\033[38;2;236;231;223m⠟\033[38;2;7;59;116m⠁\033[0m
       \033[38;2;231;239;242m⣠⣼⣿\033[38;2;236;231;223m⣿⡿⣿\033[38;2;255;249;240m⣿⣿⣿⣿⣿⣿\033[38;2;236;231;223m⡿⠛\033[38;2;248;241;231m⠉\033[0m
       \033[38;2;231;239;242m⠈     \033[38;2;255;156;33m⣸⡇   ⣾⡃\033[0m
            \033[38;2;255;156;33m⠛⠙⠿⠉ ⠉⠉⠛⠛⠓\033[0m
'
# END banner

main "$@"
