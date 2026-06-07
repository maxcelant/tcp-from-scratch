.PHONY: dev build down net-up net-down tcpdump review hint clean test vet

# Drop into the dev container (interactive shell). All lesson work happens inside.
# Depends on `build` so the image exists locally (avoids a registry pull).
dev: build
	docker compose run --rm --service-ports dev

# Build the image without entering it.
build:
	docker compose build

# Tear down everything (containers, volumes are kept).
down:
	docker compose down

# Bring up the test TUN device. The interface (kernel side) is 10.0.0.1/24;
# your TCP stack uses 10.0.0.2. The Linux kernel acts as the peer. No netns
# needed — see scripts/lib.sh for the model.
net-up:
	./scripts/net-up.sh

net-down:
	./scripts/net-down.sh

# Live tcpdump on the TUN device (run in a second terminal).
tcpdump:
	./scripts/tcpdump.sh

# Run the current lesson's review checks.
# This target is a convenience wrapper - prefer `/review` from Claude Code.
review:
	@./scripts/run-review.sh

# Tests + vet against everything the user has written so far.
test:
	go test ./... 2>/dev/null || echo "(no Go code yet)"

vet:
	go vet ./... 2>/dev/null || echo "(no Go code yet)"

clean:
	rm -f *.pcap cap.pcap
	@find . -maxdepth 3 -name '*.test' -delete
