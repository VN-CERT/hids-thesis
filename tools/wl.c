/*
 * wl.c — tai tao don luong cho scripts/g3.sh.
 *
 * Giao thuc: ba lan read() tren stdin (moi lan 1 byte).
 *   read 1 (go1)  -> getuid() danh dau khoi tao
 *   read 2 (go2)  -> chay kich ban R vong -> getppid() danh dau ket thuc
 *   read 3 (go3)  -> thoat
 *
 * Che do:
 *   cpu X_us R       — dot CPU cho CLOCK_THREAD_CPUTIME_ID tang X us, moi vong getppid
 *   sleep Y_us R     — nanosleep Y us, moi vong getppid
 *   mixed X_us Y_us R
 *   io R             — pwrite 4 KiB + fdatasync file tam trong out/
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>

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

static uint64_t thread_cputime_ns(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) {
		perror("clock_gettime CLOCK_THREAD_CPUTIME_ID");
		_exit(1);
	}
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static void burn_cpu_us(unsigned long target_us)
{
	uint64_t start, now, target_ns;

	target_ns = (uint64_t)target_us * 1000ULL;
	start = thread_cputime_ns();
	for (;;) {
		now = thread_cputime_ns();
		if (now - start >= target_ns)
			break;
	}
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
	int fd, i;

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
	for (i = 0; i < 4096; i++)
		(void)i;
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
