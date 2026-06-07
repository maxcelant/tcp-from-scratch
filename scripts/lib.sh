#!/usr/bin/env bash
# Shared helpers for the network test fixture and per-lesson integration checks.
#
# NETWORK MODEL (no network namespace required):
#   - tun0 is a *persistent* L3 TUN device created here.
#   - tun0's interface address is the KERNEL/host side: 10.0.0.1/24.
#   - YOUR TCP stack uses address 10.0.0.2 — it's in 10.0.0.0/24, routed to
#     tun0, but is NOT a local address, so the kernel writes packets destined
#     to it onto the tun fd (which your program reads).
#   - The Linux kernel's own TCP stack acts as the "real peer":
#       * server lessons: kernel is the client (`nc 10.0.0.2 PORT`),
#         your stack is the server listening on 10.0.0.2.
#       * client lessons: kernel runs a real server on 10.0.0.1
#         (`python3 -m http.server --bind 10.0.0.1`), your stack dials it.
#
# Because the kernel silently drops TCP segments with a bad checksum, several
# checks use "did the kernel reply?" as an end-to-end checksum oracle.

set -euo pipefail

TUN="${TUN:-tun0}"
HOST_ADDR="${HOST_ADDR:-10.0.0.1}"
STACK_ADDR="${STACK_ADDR:-10.0.0.2}"
PREFIX="${PREFIX:-24}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${REPO_ROOT}/.reviewtmp"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }

fail() { red "FAIL: $*"; exit 1; }

# Re-exec the calling script under sudo if we are not root. TUN + iptables + tc
# all need CAP_NET_ADMIN. Inside the dev container you are usually already root.
need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
  fi
}

module_path() {
  if [ ! -f "${REPO_ROOT}/go.mod" ]; then
    fail "go.mod not found — run \`go mod init <module>\` (lesson 00) first."
  fi
  awk '/^module /{print $2; exit}' "${REPO_ROOT}/go.mod"
}

# Bring up the persistent tun device with the host-side address.
net_up() {
  if ! ip link show "$TUN" >/dev/null 2>&1; then
    ip tuntap add dev "$TUN" mode tun
  fi
  ip addr flush dev "$TUN" 2>/dev/null || true
  ip addr add "${HOST_ADDR}/${PREFIX}" dev "$TUN"
  ip link set "$TUN" up
  # Accept packets sourced from STACK_ADDR even though they arrive on tun0.
  sysctl -wq "net.ipv4.conf.${TUN}.rp_filter=0" 2>/dev/null || true
  sysctl -wq "net.ipv4.conf.all.rp_filter=0"     2>/dev/null || true
}

net_down() {
  ip link del "$TUN" 2>/dev/null || true
}

# Generate a throwaway helper program that imports the user's packages, so the
# user never has to write scratch mains. Args: <name> <go-source>.
# The dir is dot-prefixed so `go build ./...` ignores it.
gen_helper() {
  local name="$1" src="$2"
  mkdir -p "${TMP_DIR}/${name}"
  printf '%s\n' "$src" > "${TMP_DIR}/${name}/main.go"
  echo "${TMP_DIR}/${name}/main.go"
}

clean_tmp() { rm -rf "${TMP_DIR}"; }

# Background pcap capture. Sets CAP_PID; writes to $1.
start_capture() {
  local out="$1"
  tcpdump -ni "$TUN" -w "$out" -U >/dev/null 2>&1 &
  CAP_PID=$!
  sleep 0.4   # let tcpdump open the device before traffic starts
}

stop_capture() {
  [ -n "${CAP_PID:-}" ] && kill "$CAP_PID" 2>/dev/null || true
  wait "${CAP_PID:-}" 2>/dev/null || true
}

have_tshark() { command -v tshark >/dev/null 2>&1; }

# tshark display-filter packet count over a pcap. Echoes an integer.
tshark_count() {
  local pcap="$1" filter="$2"
  tshark -r "$pcap" -Y "$filter" 2>/dev/null | wc -l | tr -d ' '
}
