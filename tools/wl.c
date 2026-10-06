/*
 * wl.c — workload don luong cho g3.sh va M4.
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
#include <sys/random.h>

#define SPIN_CHUNK 1000000ULL
#define CAL_US     200000ULL
#define M4_LOOPS_FILE "/root/hids/out/m4-loops.txt"

static double loops_per_us;
static unsigned long long fixed_loops_10ms;
static int use_fixed_loops;

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

static void spin_loops(unsigned long long n)
{
	volatile unsigned long long sink = 0;
	unsigned long long i;

	for (i = 0; i < n; i++) {
		asm volatile("" ::: "memory");
		sink++;
	}
	(void)sink;
}

static unsigned long long mono_us(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		_exit(1);
	return (unsigned long long)ts.tv_sec * 1000000ULL +
	       (unsigned long long)ts.tv_nsec / 1000ULL;
}

static unsigned long long thread_cpu_us(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0)
		_exit(1);
	return (unsigned long long)ts.tv_sec * 1000000ULL +
	       (unsigned long long)ts.tv_nsec / 1000ULL;
}

static void calibrate_loops_per_us(void)
{
	unsigned long long t0, t1, total = 0;

	t0 = mono_us();
	for (;;) {
		spin_loops(SPIN_CHUNK);
		total += SPIN_CHUNK;
		if ((total % SPIN_CHUNK) == 0) {
			t1 = mono_us();
			if (t1 - t0 >= CAL_US)
				break;
		}
	}
	t1 = mono_us();
	loops_per_us = (double)total / (double)(t1 - t0);
	fixed_loops_10ms = (unsigned long long)(10000.0 * loops_per_us);
	fprintf(stderr, "wl: loops_per_us=%.6f loops_10ms=%llu (hieu chinh %llu us)\n",
		loops_per_us, fixed_loops_10ms, (unsigned long long)(t1 - t0));
}

static int mono_in_range(unsigned long long dm)
{
	return dm >= 9500 && dm <= 10500;
}

static void self_test_burn_10ms(void)
{
	unsigned long long samples[5];
	int pass, i;

	for (pass = 0; pass < 2; pass++) {
		unsigned long long sum = 0;

		for (i = 0; i < 5; i++) {
			unsigned long long m0, m1, c0, c1, dm, dc;

			m0 = mono_us();
			c0 = thread_cpu_us();
			spin_loops(fixed_loops_10ms);
			m1 = mono_us();
			c1 = thread_cpu_us();
			dm = m1 - m0;
			dc = c1 - c0;
			samples[i] = dm;
			sum += dm;
			fprintf(stderr, "wl: tu kiem %d/5 mono=%llu us thread_cpu=%llu us\n", i + 1, dm, dc);
		}
		if (mono_in_range(samples[0]) && mono_in_range(samples[1]) &&
		    mono_in_range(samples[2]) && mono_in_range(samples[3]) &&
		    mono_in_range(samples[4]))
			return;
		if (pass == 0 && sum > 0) {
			unsigned long long avg = sum / 5;

			fixed_loops_10ms = (unsigned long long)((double)fixed_loops_10ms * 10000.0 / (double)avg);
			if (fixed_loops_10ms == 0)
				fixed_loops_10ms = 1;
			loops_per_us = (double)fixed_loops_10ms / 10000.0;
			fprintf(stderr, "wl: dieu chinh loops_10ms=%llu (trung binh %llu us)\n",
				fixed_loops_10ms, avg);
			continue;
		}
		fprintf(stderr, "wl: LOI tu kiem: mono lech qua 5%% so voi 10 ms\n");
		_exit(1);
	}
}

static unsigned long long read_loops_file_field(const char *key)
{
	FILE *f = fopen(M4_LOOPS_FILE, "r");
	unsigned long long val = 0;
	char line[128];
	char fmt[64];

	if (!f)
		return 0;
	snprintf(fmt, sizeof(fmt), "%s %%llu", key);
	while (fgets(line, sizeof(line), f)) {
		unsigned long long v;

		if (sscanf(line, fmt, &v) == 1)
			val = v;
	}
	fclose(f);
	return val;
}

static unsigned long long read_mem_steps_file(void)
{
	return read_loops_file_field("mem_steps");
}

static void write_m4_loops(unsigned long long mem_steps)
{
	FILE *f = fopen(M4_LOOPS_FILE, "w");
	unsigned long long keep_mem = mem_steps;

	if (!f) {
		perror("fopen m4-loops");
		_exit(1);
	}
	if (keep_mem == 0)
		keep_mem = read_mem_steps_file();
	fprintf(f, "burn_loops %llu\n", fixed_loops_10ms);
	fprintf(f, "mem_steps %llu\n", keep_mem);
	fclose(f);
}

static void burn_cpu_us(unsigned long target_us)
{
	unsigned long long n;

	if (use_fixed_loops && target_us == 10000)
		n = fixed_loops_10ms;
	else
		n = (unsigned long long)(target_us * loops_per_us);
	if (n == 0)
		n = 1;
	spin_loops(n);
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

static unsigned long long calibrate_mem_steps(unsigned char *buf, size_t sz)
{
	unsigned long long t0, t1, steps = 0;
	unsigned int seed = 1;

	t0 = mono_us();
	while (mono_us() - t0 < CAL_US) {
		size_t off = (size_t)(rand_r(&seed) % (unsigned int)sz);
		buf[off]++;
		steps++;
	}
	t1 = mono_us();
	return steps * 10000ULL / (t1 - t0);
}

static void mem_work(unsigned char *buf, size_t sz, unsigned long long steps)
{
	unsigned int seed = 42;
	unsigned long long i;

	for (i = 0; i < steps; i++) {
		size_t off = (size_t)(rand_r(&seed) % (unsigned int)sz);
		buf[off]++;
		asm volatile("" ::: "memory");
	}
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

static void shift_argv(int *argc, char ***argv, int n)
{
	*argc -= n;
	*argv += n;
}

int main(int argc, char **argv)
{
	unsigned long loops_arg = 0;
	unsigned long x_us = 0, y_us = 0, rounds = 1;
	const char *mode;
	char iopath[512];
	unsigned long r;

	argc--;
	argv++;

	while (argc > 1 && strcmp(argv[0], "-loops") == 0) {
		if (argc < 2) {
			fprintf(stderr, "wl: -loops can so\n");
			return 1;
		}
		loops_arg = parse_ul(argv[1], "loops");
		shift_argv(&argc, &argv, 2);
	}

	if (argc < 1) {
		fprintf(stderr,
			"usage: wl [-loops N] <cpu X_us R|sleep Y_us R|mixed [X_us Y_us] R|io R|mem R>\n");
		return 1;
	}

	mode = argv[0];
	if (strcmp(mode, "cpu") == 0) {
		if (argc != 3)
			goto usage;
		x_us = parse_ul(argv[1], "X_us");
		rounds = parse_ul(argv[2], "R");
	} else if (strcmp(mode, "sleep") == 0) {
		if (argc != 3)
			goto usage;
		y_us = parse_ul(argv[1], "Y_us");
		rounds = parse_ul(argv[2], "R");
	} else if (strcmp(mode, "mixed") == 0) {
		if (argc == 2) {
			x_us = 10000;
			y_us = 10000;
			rounds = parse_ul(argv[1], "R");
		} else if (argc == 4) {
			x_us = parse_ul(argv[1], "X_us");
			y_us = parse_ul(argv[2], "Y_us");
			rounds = parse_ul(argv[3], "R");
		} else
			goto usage;
	} else if (strcmp(mode, "io") == 0) {
		if (argc != 2)
			goto usage;
		rounds = parse_ul(argv[1], "R");
	} else if (strcmp(mode, "mem") == 0) {
		if (argc != 2)
			goto usage;
		rounds = parse_ul(argv[1], "R");
	} else {
		goto usage;
	}

	printf("%d\n", getpid());
	fflush(stdout);

	if (loops_arg > 0) {
		fixed_loops_10ms = loops_arg;
		use_fixed_loops = 1;
		loops_per_us = (double)fixed_loops_10ms / 10000.0;
		fprintf(stderr, "wl: dung -loops %lu (bo qua hieu chinh)\n", loops_arg);
	} else {
		calibrate_loops_per_us();
		self_test_burn_10ms();
		use_fixed_loops = 1;
		if (strcmp(mode, "mem") != 0)
			write_m4_loops(read_mem_steps_file());
	}

	/* Hieu chinh mem truoc khi cho (calibrate_mem trong m4.sh khong can fifo). */
	if (strcmp(mode, "mem") == 0) {
		unsigned char *buf;
		unsigned long long mem_steps, burn_file;
		size_t mem_sz = 64UL * 1024 * 1024;

		burn_file = read_loops_file_field("burn_loops");
		if (burn_file > 0 && loops_arg == 0) {
			fixed_loops_10ms = burn_file;
			use_fixed_loops = 1;
			loops_per_us = (double)fixed_loops_10ms / 10000.0;
		}
		buf = malloc(mem_sz);
		if (!buf) {
			perror("malloc");
			_exit(1);
		}
		memset(buf, 0, mem_sz);
		if (loops_arg > 0) {
			mem_steps = read_mem_steps_file();
			if (mem_steps == 0) {
				fprintf(stderr, "wl: mem can mem_steps trong %s\n", M4_LOOPS_FILE);
				_exit(1);
			}
		} else {
			mem_steps = calibrate_mem_steps(buf, mem_sz);
			write_m4_loops(mem_steps);
			fprintf(stderr, "wl: mem_steps=%llu\n", mem_steps);
		}
		free(buf);
	}

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
	} else if (strcmp(mode, "mem") == 0) {
		unsigned char *buf;
		unsigned long long mem_steps;
		size_t mem_sz = 64UL * 1024 * 1024;

		mem_steps = read_mem_steps_file();
		if (mem_steps == 0) {
			fprintf(stderr, "wl: mem can mem_steps trong %s\n", M4_LOOPS_FILE);
			_exit(1);
		}
		buf = malloc(mem_sz);
		if (!buf) {
			perror("malloc");
			_exit(1);
		}
		memset(buf, 0, mem_sz);
		for (r = 0; r < rounds; r++) {
			mem_work(buf, mem_sz, mem_steps);
			do_sleep_us(10000);
			marker_getppid();
		}
		free(buf);
	} else {
		snprintf(iopath, sizeof(iopath), "/root/hids/out/wl-io-%d.tmp", getpid());
		for (r = 0; r < rounds; r++) {
			int fd;
			char b[4096];

			memset(b, 0x5a, sizeof(b));
			fd = open(iopath, O_CREAT | O_RDWR | O_TRUNC, 0600);
			if (fd < 0)
				_exit(1);
			pwrite(fd, b, sizeof(b), 0);
			fdatasync(fd);
			close(fd);
			marker_getppid();
		}
		unlink(iopath);
	}

	wait_go();
	return 0;

usage:
	fprintf(stderr,
		"usage: wl [-loops N] <cpu|sleep|mixed|io|mem> ...\n");
	return 1;
}
