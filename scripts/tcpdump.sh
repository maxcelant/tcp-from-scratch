#!/usr/bin/env bash
# Live packet view on the test TUN device. Pass extra tcpdump args after --.
#   ./scripts/tcpdump.sh            # everything
#   ./scripts/tcpdump.sh tcp port 7777
source "$(dirname "$0")/lib.sh"
need_root "$@"
exec tcpdump -ni "$TUN" -vv "$@"
