SHELL := /bin/bash

GO ?= go
CC ?= gcc
BPFTOOL ?= bpftool
# Tinh luc chay recipe chu khong luc doc Makefile: 'make clean' xoa cac file .o
# dang duoc git theo doi, neu tinh som thi cay se bi coi la dirty cho den khi
# 'go generate' tao lai chung.
GIT_REV = $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
# Chi coi dirty neu co thay doi ngoai out/ va ngoai validation/g3-* (ket qua G3).
GIT_DIRTY = $(shell git status --porcelain 2>/dev/null | awk '$$2 !~ /^out\// && $$2 !~ /^validation\/g3-/ {found=1} END {if (found) print "-dirty"}')
GIT_COMMIT = $(GIT_REV)$(GIT_DIRTY)
LDFLAGS = -X hids/internal/buildinfo.Commit=$(GIT_COMMIT)

BINARIES := bin/steal-probe bin/steal-summary bin/hids-collect bin/rec-stat bin/rec-check bin/wl bin/sysinj

.PHONY: build generate vmlinux clean

build: generate bin/sysinj bin/wl
	@mkdir -p bin
	$(GO) build -ldflags "$(LDFLAGS)" -o bin/steal-probe ./cmd/steal-probe
	$(GO) build -ldflags "$(LDFLAGS)" -o bin/steal-summary ./cmd/steal-summary
	$(GO) build -ldflags "$(LDFLAGS)" -o bin/hids-collect ./cmd/hids-collect
	$(GO) build -ldflags "$(LDFLAGS)" -o bin/rec-stat ./cmd/rec-stat
	$(GO) build -ldflags "$(LDFLAGS)" -o bin/rec-check ./cmd/rec-check

# Cong cu kiem thu viet bang C, khong thuoc phan Go.
bin/sysinj: tools/sysinj.c
	@mkdir -p bin
	$(CC) -O2 -Wall -Wextra -o $@ $<

bin/wl: tools/wl.c
	@mkdir -p bin
	$(CC) -O2 -Wall -Wextra -o $@ $<

# Dich lai cac chuong trinh BPF (can clang va bpf/vmlinux.h).
generate: bpf/vmlinux.h
	$(GO) generate ./...

# Sinh vmlinux.h tu BTF cua kernel dang chay.
bpf/vmlinux.h:
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

vmlinux:
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > bpf/vmlinux.h

clean:
	rm -f $(BINARIES)
	rm -f internal/stealbpf/*.o internal/syscallbpf/*.o
