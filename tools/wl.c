/*
 * wl.c — tai tao don luong cho scripts/g3.sh.
 *
 * Giao thuc: ba lan read() tren stdin (moi lan 1 byte).
 *   read 1 (go1)  -> getuid() danh dau khoi tao
 *   read 2 (go2)  -> chay kich ban R vong -> getppid() danh dau ket thuc
 *   read 3 (go3)  -> thoat
 *
 * Truoc read lan 1: hieu chinh so vong lap / us bang CLOCK_MONOTONIC (~200 ms).
 * Che do cpu X: dot CPU bang X * he_so vong, KHONG syscall trong vong dot.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>

static double loops_per_us;

static int wait_go(void)
{
	unsigned char b;

	if (read(STDIN_FILENO, &b, 1) != 1)
		_exit(1);
	return 0;
}

static void marker_getuid(void)
{
	syscall(SYS_getuid);
}

static void marker_getppid(void)
{
	syscall(SYS_getppid);
}

static void spin_once(void)
{
	asm volatile("" ::: "memory");
}

static void calibrate_loops_per_us(void)
{
	struct timespec t0, t1;
	unsigned long long n = 0;
	unsigned long long elapsed_us;

	if (clock_gettime(CLOCK_MONOTONIC, &t0) != 0) {
		perror("clock_gettime CLOCK_MONOTONIC");
		_exit(1);
	}
	for (;;) {
		spin_once();
		n++;
		if (clock_gettime(CLOCK_MONOTONIC, &t1) != 0) {
			perror("clock_gettime CLOCK_MONOTONIC");
			_exit(1);
		}
		elapsed_us = (unsigned long long)(t1.tv_sec - t0.tv_sec) * 1000000ULL +
			     (unsigned long long)(t1.tv_nsec - t0.tv_nsec) / 1000ULL;
		if (elapsed_us >= 200000ULL)
			break;
	}
	loops_per_us = (double)n / (double)elapsed_us;
	fprintf(stderr, "wl: loops_per_us=%.6f (%llu vong trong %llu us)\n",
		loops_per_us, n, (unsigned long long)elapsed_us);
}

static void burn_cpu_us(unsigned long target_us)
{
	unsigned long long i, n;

	if (loops_per_us <= 0.0) {
		fprintf(stderr, "wl: chua hieu chinh loops_per_us\n");
		_exit(1);
	}
	n = (unsigned long long)(target_us * loops_per_us);
	if (n == 0)
		n = 1;
	for (i = 0; i < n; i++)
		spin_once();
}

static void do_sleep_us(unsigned long us)
{
	struct timespec req, rem;

	req.tv_sec = (time_t)(us / 1000000UL);
	req.tv_nsec = (long)((us % 1000000UL) * 1000UL);
	while (nanosleep(&req, &rem) < 0) {
		if (errno != EINTR) {
			perror("nanosleep");
			_exit(1);
		}
		req = rem;
	}
}

static void do_io_once(const char *path)
{
	char buf[4096];
	int fd;

	memset(buf, 0x5a, sizeof(buf));
	fd = open(path, O_CREAT | O_RDWR | O_TRUNC, 0600);
	if (fd < 0) {
		perror("open");
		_exit(1);
	}
	if (pwrite(fd, buf, sizeof(buf), 0) != (ssize_t)sizeof(buf)) {
		perror("pwrite");
		close(fd);
		_exit(1);
	}
	if (fdatasync(fd) != 0) {
		perror("fdatasync");
		close(fd);
		_exit(1);
	}
	close(fd);
}

static unsigned long parse_ul(const char *s, const char *name)
{
	char *end;
	unsigned long v;

	errno = 0;
	v = strtoul(s, &end, 10);
	if (errno != 0 || *end != '\0' || end == s) {
		fprintf(stderr, "wl: %s khong hop le: %s\n", name, s);
		_exit(1);
	}
	return v;
}

int main(int argc, char **argv)
{
	const char *mode;
	unsigned long x_us = 0, y_us = 0, rounds = 1;
	char iopath[512];
	unsigned long r;

	if (argc < 3) {
		fprintf(stderr,
			"usage: wl <cpu X_us R|sleep Y_us R|mixed X_us Y_us R|io R>\n");
		return 1;
	}

	mode = argv[1];
	if (strcmp(mode, "cpu") == 0) {
		if (argc != 4)
			goto usage;
		x_us = parse_ul(argv[2], "X_us");
		rounds = parse_ul(argv[3], "R");
	} else if (strcmp(mode, "sleep") == 0) {
		if (argc != 4)
			goto usage;
		y_us = parse_ul(argv[2], "Y_us");
		rounds = parse_ul(argv[3], "R");
	} else if (strcmp(mode, "mixed") == 0) {
		if (argc != 5)
			goto usage;
		x_us = parse_ul(argv[2], "X_us");
		y_us = parse_ul(argv[3], "Y_us");
		rounds = parse_ul(argv[4], "R");
	} else if (strcmp(mode, "io") == 0) {
		if (argc != 3)
			goto usage;
		rounds = parse_ul(argv[2], "R");
	} else {
		goto usage;
	}

	printf("%d\n", getpid());
	fflush(stdout);

	calibrate_loops_per_us();

	wait_go();
	marker_getuid();

	wait_go();
	if (strcmp(mode, "cpu") == 0) {
		for (r = 0; r < rounds; r++) {
			burn_cpu_us(x_us);
			marker_getppid();
		}
	} else if (strcmp(mode, "sleep") == 0) {
		for (r = 0; r < rounds; r++) {
			do_sleep_us(y_us);
			marker_getppid();
		}
	} else if (strcmp(mode, "mixed") == 0) {
		for (r = 0; r < rounds; r++) {
			burn_cpu_us(x_us);
			do_sleep_us(y_us);
			marker_getppid();
		}
	} else {
		snprintf(iopath, sizeof(iopath), "/root/hids/out/wl-io-%d.tmp", getpid());
		for (r = 0; r < rounds; r++) {
			do_io_once(iopath);
			marker_getppid();
		}
		unlink(iopath);
	}

	wait_go();
	return 0;

usage:
	fprintf(stderr,
		"usage: wl <cpu X_us R|sleep Y_us R|mixed X_us Y_us R|io R>\n");
	return 1;
}
