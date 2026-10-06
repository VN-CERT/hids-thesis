// Package syscallbpf nap va gan chuong trinh BPF hids_sys_enter.
package syscallbpf

//go:generate go tool bpf2go -target amd64 -cc clang -cflags "-O2 -g -Wall -Werror" sysEnter ../../bpf/sys_enter.bpf.c
