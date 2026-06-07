#!/usr/bin/env bash
# L08: the final ACK drives the connection to ESTABLISHED and Accept returns.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

MOD="$(module_path)"
OUT="$(mktemp)"; PCAP="$(mktemp --suffix=.pcap)"
cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; stop_capture; net_down; clean_tmp; rm -f "$OUT" "$PCAP"; }
trap cleanup EXIT

read -r -d '' SRC <<EOF || true
package main
import (
	"log"
	"net/netip"
	"time"
	tcp "${MOD}/internal/tcp"
)
func main() {
	l, err := tcp.Listen(netip.MustParseAddrPort("${STACK_ADDR}:7777"))
	if err != nil { log.Fatalf("Listen: %v", err) }
	defer l.Close()
	c, err := l.Accept()
	if err != nil { log.Fatalf("Accept: %v", err) }
	log.Printf("STATE=%s", c.State())
	time.Sleep(3 * time.Second)
}
EOF
gen_helper accept "$SRC" >/dev/null

info "building accept helper"
go build -o "${TMP_DIR}/accept.bin" "${TMP_DIR}/accept/main.go" || fail "helper build failed — check tcp.Conn.State()"

net_up
start_capture "$PCAP"
"${TMP_DIR}/accept.bin" >"$OUT" 2>&1 &
PROG_PID=$!
sleep 0.5

info "performing a full 3-way handshake from the kernel"
( timeout 3 nc -w 2 "$STACK_ADDR" 7777 >/dev/null 2>&1 <<<"" ) || true
sleep 1
stop_capture

grep -q "STATE=ESTABLISHED" "$OUT" || { sed 's/^/    /' "$OUT"; fail "Accept did not reach ESTABLISHED. Validate the final ACK (seg.ack == SND.NXT) and push the conn to the accept channel."; }

if have_tshark; then
  RST="$(tshark_count "$PCAP" "ip.src==${STACK_ADDR} && tcp.flags.reset==1")"
  [ "${RST:-0}" -eq 0 ] || fail "your stack emitted a RST during the handshake (${RST}). A valid ACK is being rejected."
fi

green "L08 OK: connection reached ESTABLISHED."
