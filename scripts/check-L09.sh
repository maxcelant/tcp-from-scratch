#!/usr/bin/env bash
# L09: the echo server receives application data and ACKs it.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

OUT="$(mktemp)"
cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; net_down; rm -f "$OUT"; }
trap cleanup EXIT

info "building cmd/tcp-echo (listens on ${STACK_ADDR}:7777)"
go build -o "${TMP_DIR}/tcp-echo" ./cmd/tcp-echo || fail "build failed"

net_up
"${TMP_DIR}/tcp-echo" >"$OUT" 2>&1 &
PROG_PID=$!
sleep 0.5

TOKEN="PING-$RANDOM-$RANDOM"
info "sending ${TOKEN} to the echo server"
printf '%s\n' "$TOKEN" | timeout 4 nc -w 2 "$STACK_ADDR" 7777 >/dev/null 2>&1 || true
sleep 0.7

grep -q "$TOKEN" "$OUT" || { sed 's/^/    /' "$OUT"; fail "the server never logged the data. Check the in-order data path (seg.seq==RCV.NXT), the recv buffer, and Conn.Read."; }

green "L09 OK: data received in order and surfaced through Conn.Read."
