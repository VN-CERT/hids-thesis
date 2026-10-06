// sysinj: cong cu kiem thu, bom mot so luong syscall biet truoc.
//
// Don luong. In PID ra, cho toi khi file /tmp/hids-go ton tai, goi dung N lan
// syscall(SYS_getppid), ngu 1 giay roi thoat.
//
// Bien dich: gcc -O2 -Wall -Wextra -o bin/sysinj tools/sysinj.c

#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define GO_FILE "/tmp/hids-go"

static void usage(const char *prog)
{
	fprintf(stderr, "cach dung: %s [-n so_lan]\n", prog);
	fprintf(stderr, "  -n  so lan goi syscall(SYS_getppid), mac dinh 1000000\n");
}

int main(int argc, char **argv)
{
	long n = 1000000;
	int opt;

	while ((opt = getopt(argc, argv, "n:h")) != -1) {
		switch (opt) {
		case 'n': {
			char *end = NULL;

			errno = 0;
			n = strtol(optarg, &end, 10);
			if (errno != 0 || end == optarg || *end != '\0' || n < 0) {
				fprintf(stderr, "sysinj: -n khong hop le: %s\n", optarg);
				return 2;
			}
			break;
		}
		case 'h':
			usage(argv[0]);
			return 0;
		default:
			usage(argv[0]);
			return 2;
		}
	}

	printf("sysinj pid=%d n=%ld\n", (int)getpid(), n);
	fflush(stdout);

	/* Cho tin hieu bat dau tu file, de nguoi goi kip gan collector va perf. */
	while (access(GO_FILE, F_OK) != 0) {
		struct timespec ts = { .tv_sec = 0, .tv_nsec = 1000000 }; /* 1 ms */

		nanosleep(&ts, NULL);
	}

	for (long i = 0; i < n; i++)
		syscall(SYS_getppid);

	sleep(1);
	return 0;
}
