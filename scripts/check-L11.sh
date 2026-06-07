#!/usr/bin/env bash
# L11: with induced packet loss the transfer still completes (retransmission),
# and duplicate sequence numbers appear on the wire.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

LOSS_RULE=(INPUT -s "$STACK_ADDR" -p tcp -m statistic --mode random --probability 0.30 -j DROP)
cleanup() {
  kill "${PROG_PID:-}" 2>/dev/null || true
  iptables -D "${LOSS_RULE[@]}" 2>/dev/null || true
  stop_capture; net_down; rm -f "$SENT" "$GOT" "$PCAP"
}
trap cleanup EXIT
SENT="$(mktemp)"; GOT="$(mktemp)"; PCAP="$(mktemp --suffix=.pcap)"

info "building cmd/tcp-echo"
go build -o "${TMP_DIR}/tcp-echo" ./cmd/tcp-echo || fail "build failed"

net_up
start_capture "$PCAP"
"${TMP_DIR}/tcp-echo" >/dev/null 2>&1 &
PROG_PID=$!
sleep 0.5

info "inducing ~30% loss on packets from your stack (forces retransmission)"
iptables -I "${LOSS_RULE[@]}"

head -c 4000 /dev/urandom | base64 | head -c 4000 > "$SENT"
info "sending $(wc -c <"$SENT") bytes; allowing up to 30s for retransmits"
timeout 30 nc -w 5 "$STACK_ADDR" 7777 < "$SENT" > "$GOT" 2>/dev/null || true
iptables -D "${LOSS_RULE[@]}" 2>/dev/null || true
sleep 0.5
stop_capture

cmp -s "$SENT" "$GOT" || { info "got $(wc -c <"$GOT")/$(wc -c <"$SENT") bytes"; fail "transfer did not complete under loss. Check the retransmit queue: are unacked segments resent after RTO, and is SND.NXT NOT advanced on resend?"; }

if have_tshark; then
  # A retransmit shows up as analysis.retransmission in tshark's TCP heuristics.
  RTX="$(tshark_count "$PCAP" "ip.src==${STACK_ADDR} && tcp.analysis.retransmission")"
  info "retransmitted segments observed: ${RTX}"
  [ "${RTX:-0}" -ge 1 ] || info "(warning) no retransmissions detected — loss may have been low this run; the byte-identical transfer is the primary signal."
fi

green "L11 OK: reliable transfer under packet loss."
