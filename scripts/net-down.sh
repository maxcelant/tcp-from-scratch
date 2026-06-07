#!/usr/bin/env bash
# Tear down the test TUN device.
source "$(dirname "$0")/lib.sh"
need_root "$@"
net_down
green "tun device '${TUN}' removed."
