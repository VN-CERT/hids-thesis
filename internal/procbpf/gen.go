// Package procbpf nap chuong trinh BPF proc_events (fork/exec/exit).
package procbpf

//go:generate go tool bpf2go -target amd64 -cc clang -cflags "-O2 -g -Wall -Werror" procEvents ../../bpf/proc_events.bpf.c
