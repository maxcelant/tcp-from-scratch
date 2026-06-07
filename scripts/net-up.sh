#!/usr/bin/env bash
# Bring up the test TUN device. See scripts/lib.sh for the network model.
#
#   tun0  ->  host/kernel side  = 10.0.0.1/24
#   your stack should use        = 10.0.0.2
#
# Run with sudo (or as root inside the dev container).
source "$(dirname "$0")/lib.sh"
need_root "$@"
net_up
green "tun device '${TUN}' is up."
info "host/kernel address : ${HOST_ADDR}/${PREFIX}"
info "use in your stack   : ${STACK_ADDR}"
info "tear down with      : ./scripts/net-down.sh"
