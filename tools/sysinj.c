// sysinj: cong cu kiem thu, bom mot so luong syscall biet truoc.
//
// Don luong. In PID ra, roi chan tai DUNG MOT lenh read() tren stdin. Khong
// vong lap kiem tra file, khong sleep: trong luc cho, tien trinh khong goi
// them syscall nao, nen tong so syscall do duoc khop tuyet doi voi perf.
// Nhan duoc du lieu thi goi dung N lan syscall(SYS_getppid) roi thoat ngay.
//
// Bien dich: gcc -O2 -Wall -Wextra -o bin/sysinj tools/sysinj.c

#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static void usage(const char *prog)
{
	fprintf(stderr, "cach dung: %s [-n so_lan]\n", prog);
	fprintf(stderr, "  -n  so lan goi syscall(SYS_getppid), mac dinh 1000000\n");
	fprintf(stderr, "Tien trinh cho tin hieu bat dau bang mot lenh read() tren stdin.\n");
}

int main(int argc, char **argv)
{
	long n = 1000000;
	char buf[1];
	ssize_t r;
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

	/* Mot lenh read() duy nhat. Tu day den khi nguoi goi ghi vao stdin,
	 * tien trinh khong sinh them su kien sys_enter nao. */
	r = read(STDIN_FILENO, buf, sizeof(buf));
	if (r < 0) {
		fprintf(stderr, "sysinj: read stdin: %s\n", strerror(errno));
		return 1;
	}

	for (long i = 0; i < n; i++)
		syscall(SYS_getppid);

	return 0;
}
