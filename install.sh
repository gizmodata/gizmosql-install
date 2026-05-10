#!/bin/sh
# GizmoSQL one-line installer for macOS and Linux.
#
#   curl -fsSL https://install.gizmosql.com/install.sh | sh
#
# By default this installs the latest stable release of gizmosql_server
# and gizmosql_client into ~/.local/bin (no sudo required) and tells you
# how to add that directory to your PATH if it isn't already.
#
# Options (pass via `sh -s -- <args>` when piping):
#   --channel stable|lts   Pick the stable (default) or LTS release channel.
#   --version vX.Y.Z       Install a specific GizmoSQL version. Default: latest.
#   --prefix /path/to/bin  Where to install the executables. Default: ~/.local/bin.
#                          /usr/local/bin works too but usually needs sudo.
#   --no-path-hint         Don't print the "add this to your PATH" message.
#   --help                 Print this help and exit.
#
# Examples:
#   curl -fsSL https://install.gizmosql.com/install.sh | sh
#   curl -fsSL https://install.gizmosql.com/install.sh | sh -s -- --channel lts
#   curl -fsSL https://install.gizmosql.com/install.sh | sh -s -- --version v1.25.1 --prefix /usr/local/bin
#
# Source: https://github.com/gizmodata/gizmosql-install
# Releases: https://github.com/gizmodata/gizmosql/releases
# Channel guide: https://docs.gizmosql.com/#/lts_channel

set -eu

# ---- defaults ---------------------------------------------------------------
CHANNEL="stable"
VERSION=""
PREFIX="${HOME}/.local/bin"
PRINT_PATH_HINT=1
REPO="gizmodata/gizmosql"

# ---- pretty output ----------------------------------------------------------
# Disable color when stdout isn't a TTY (e.g. redirected to a file).
if [ -t 1 ]; then
  C_BOLD="$(printf '\033[1m')"
  C_DIM="$(printf '\033[2m')"
  C_GREEN="$(printf '\033[32m')"
  C_RED="$(printf '\033[31m')"
  C_RESET="$(printf '\033[0m')"
else
  C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_RESET=""
fi

info()  { printf "%s==>%s %s\n" "${C_GREEN}${C_BOLD}" "${C_RESET}" "$1"; }
warn()  { printf "%swarn:%s %s\n" "${C_BOLD}" "${C_RESET}" "$1" >&2; }
fatal() { printf "%serror:%s %s\n" "${C_RED}${C_BOLD}" "${C_RESET}" "$1" >&2; exit 1; }

# ---- arg parsing ------------------------------------------------------------
usage() {
  sed -n '2,/^$/p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' | head -40
  cat <<'EOF'

(usage above is also available at https://install.gizmosql.com)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --channel)        CHANNEL="${2:-}"; shift 2 ;;
    --channel=*)      CHANNEL="${1#*=}"; shift ;;
    --version)        VERSION="${2:-}"; shift 2 ;;
    --version=*)      VERSION="${1#*=}"; shift ;;
    --prefix)         PREFIX="${2:-}"; shift 2 ;;
    --prefix=*)       PREFIX="${1#*=}"; shift ;;
    --no-path-hint)   PRINT_PATH_HINT=0; shift ;;
    --help|-h)        usage; exit 0 ;;
    *)                fatal "unknown argument: $1 (try --help)" ;;
  esac
done

case "$CHANNEL" in
  stable|lts) ;;
  *) fatal "--channel must be 'stable' or 'lts' (got '$CHANNEL')" ;;
esac

# Cosmetic suffix that matches the release artifact naming convention
# (gizmosql_cli_<os>_<arch>.zip vs gizmosql_cli_<os>_<arch>_lts.zip and
# gizmosql_server vs gizmosql_server_lts).
if [ "$CHANNEL" = "lts" ]; then
  ARTIFACT_CHANNEL_SUFFIX="_lts"
  BIN_CHANNEL_SUFFIX="_lts"
else
  ARTIFACT_CHANNEL_SUFFIX=""
  BIN_CHANNEL_SUFFIX=""
fi

# ---- platform detection -----------------------------------------------------
UNAME_S="$(uname -s 2>/dev/null || echo unknown)"
UNAME_M="$(uname -m 2>/dev/null || echo unknown)"

case "$UNAME_S" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *) fatal "unsupported OS: $UNAME_S (this script supports macOS and Linux; for Windows use install.ps1)" ;;
esac

case "$UNAME_M" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) fatal "unsupported CPU architecture: $UNAME_M" ;;
esac

# Validate the (os, arch, channel) tuple actually has a published artifact.
case "${OS}_${ARCH}" in
  macos_arm64|linux_amd64|linux_arm64) ;;
  macos_amd64) fatal "GizmoSQL no longer publishes Intel macOS builds (use Rosetta or build from source)" ;;
  *) fatal "no GizmoSQL release artifact for ${OS}/${ARCH}" ;;
esac

# ---- required tools ---------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || fatal "missing required tool: $1"; }
need curl
need unzip

# ---- resolve version --------------------------------------------------------
# Use the GitHub releases/latest endpoint; follow the 302 redirect to the tag
# page and extract the tag from the final URL. Avoids needing an API token.
if [ -z "$VERSION" ]; then
  info "Resolving latest GizmoSQL release..."
  LATEST_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  VERSION="${LATEST_URL##*/}"
  case "$VERSION" in
    v*) ;;
    *) fatal "could not resolve latest version (got '$VERSION'); pass --version v1.25.1 explicitly" ;;
  esac
fi
info "GizmoSQL ${C_BOLD}${VERSION}${C_RESET} (${CHANNEL} channel) for ${OS}/${ARCH}"

# ---- download ---------------------------------------------------------------
ARTIFACT="gizmosql_cli_${OS}_${ARCH}${ARTIFACT_CHANNEL_SUFFIX}.zip"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARTIFACT}"

TMPDIR="$(mktemp -d 2>/dev/null || mktemp -d -t gizmosql-install)"
trap 'rm -rf "$TMPDIR"' EXIT INT TERM

info "Downloading ${ARTIFACT}..."
if ! curl -fsSL --retry 3 -o "$TMPDIR/$ARTIFACT" "$URL"; then
  fatal "download failed: $URL
  (the channel/version combination may not exist; see https://github.com/${REPO}/releases)"
fi
# Transit integrity is covered by HTTPS + the zip's own CRCs. For supply-chain
# provenance we publish Sigstore build attestations on every release asset —
# verify with `gh attestation verify <file> --repo ${REPO}` if you want it.

# ---- install ----------------------------------------------------------------
info "Extracting..."
unzip -q -o "$TMPDIR/$ARTIFACT" -d "$TMPDIR/extracted"

mkdir -p "$PREFIX" || fatal "could not create $PREFIX (try --prefix /writable/dir)"
[ -w "$PREFIX" ] || fatal "$PREFIX is not writable (try --prefix \$HOME/.local/bin or run with sudo)"

SRV="gizmosql_server${BIN_CHANNEL_SUFFIX}"
CLI="gizmosql_client${BIN_CHANNEL_SUFFIX}"

for f in "$SRV" "$CLI"; do
  if [ ! -f "$TMPDIR/extracted/$f" ]; then
    fatal "expected $f in $ARTIFACT but it wasn't there"
  fi
  install -m 0755 "$TMPDIR/extracted/$f" "$PREFIX/$f"
done

# ---- macOS quarantine -------------------------------------------------------
# The binaries are notarized; clearing the quarantine flag set by curl-via-shell
# avoids a "cannot be opened because the developer cannot be verified" dialog
# on first run. (No-op when xattr or the attribute is missing.)
if [ "$OS" = "macos" ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "$PREFIX/$SRV" 2>/dev/null || true
  xattr -d com.apple.quarantine "$PREFIX/$CLI" 2>/dev/null || true
fi

# ---- post-install summary ---------------------------------------------------
info "Installed:"
printf "    %s\n    %s\n" "$PREFIX/$SRV" "$PREFIX/$CLI"

# Verify the binary actually runs (quick sanity check; --version is cheap).
if "$PREFIX/$SRV" --version >/dev/null 2>&1; then
  REPORTED_VERSION="$("$PREFIX/$SRV" --version 2>&1 | head -1)"
  info "${REPORTED_VERSION}"
else
  warn "binary installed but '$PREFIX/$SRV --version' failed; check that $PREFIX is on the right architecture and not blocked by Gatekeeper/SELinux."
fi

# PATH hint — only print if the prefix isn't already on PATH.
if [ "$PRINT_PATH_HINT" -eq 1 ]; then
  case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *)
      printf "\n%sNext step:%s add %s to your PATH. For example:\n" "${C_BOLD}" "${C_RESET}" "$PREFIX"
      printf "    %sexport PATH=\"%s:\$PATH\"%s\n" "${C_DIM}" "$PREFIX" "${C_RESET}"
      printf "  (add it to ~/.bashrc, ~/.zshrc, etc. to make it permanent)\n"
      ;;
  esac
fi

cat <<EOF

Get started:
    ${C_BOLD}${SRV} --password tiger${C_RESET}            # in one terminal
    ${C_BOLD}GIZMOSQL_PASSWORD=tiger ${CLI}${C_RESET}    # in another
    ${C_BOLD}${SRV} --help${C_RESET}                     # all options

Docs:    https://docs.gizmosql.com
LTS:     https://docs.gizmosql.com/#/lts_channel
Issues:  https://github.com/${REPO}/issues
EOF
