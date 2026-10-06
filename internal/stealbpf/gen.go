// Package stealbpf nap va chay chuong trinh BPF hids_steal_snap.
package stealbpf

//go:generate go tool bpf2go -target amd64 -cc clang -cflags "-O2 -g -Wall -Werror" stealSnap ../../bpf/steal_snap.bpf.c
//go:generate go tool bpf2go -target amd64 -cc clang -cflags "-O2 -g -Wall -Werror -DHIDS_NO_VMW" stealSnapRq ../../bpf/steal_snap.bpf.c
