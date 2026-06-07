#!/usr/bin/env bash
# L10: the echo server writes data back; multi-segment payload round-trips.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; net_down; rm -f "$SENT" "$GOT"; }
trap cleanup EXIT
SENT="$(mktemp)"; GOT="$(mktemp)"

info "building cmd/tcp-echo"
go build -o "${TMP_DIR}/tcp-echo" ./cmd/tcp-echo || fail "build failed"

net_up
"${TMP_DIR}/tcp-echo" >/dev/null 2>&1 &
PROG_PID=$!
sleep 0.5

# ~6 KB forces several MSS-sized segments.
head -c 6000 /dev/urandom | base64 | head -c 6000 > "$SENT"
info "sending $(wc -c <"$SENT") bytes through the echo server"
timeout 8 nc -w 3 "$STACK_ADDR" 7777 < "$SENT" > "$GOT" 2>/dev/null || true

if cmp -s "$SENT" "$GOT"; then
  green "L10 OK: $(wc -c <"$GOT") bytes echoed back byte-identical."
else
  info "sent $(wc -c <"$SENT") bytes, got $(wc -c <"$GOT") bytes back"
  fail "payload did not round-trip. Check segmentation (<= MSS), SND.NXT advance, the window check, and SND.UNA advance on ACK."
fi
