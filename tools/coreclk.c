// SPDX-License-Identifier: GPL-2.0
//
// coreclk.c - do kien truc su viet. KHONG SUA NOI DUNG.
//
// Thuoc do DOC LAP (khong can collector, khong can PMU) cua tan so loi thuc
// luc chay, dong thoi la phep kiem bo dem "cycles" cua vPMC VMware.
//
// Nguyen ly: chuoi lenh imul PHU THUOC (moi imul dung ket qua cua imul
// truoc) nen bo xu ly khong the chay song song. Do tre cua imul r64,r64 la
// dung 3 chu ky loi tren Intel tu Nehalem den nay (Ice Lake-SP cua may test
// va may lab, Sapphire Rapids) va AMD Zen 3+. Vay
//     so chu ky loi da troi qua  ~=  3 x so_imul      (CPI theo cau tao)
//     GHz_wall = 3 x so_imul / thoi_gian_ns = tan so loi THUC luc chay.
// (Khong dung chuoi "add $1": loi Golden Cove tro di gap add voi hang so
// ngay o buoc doi ten thanh ghi, chay 4-5 add phu thuoc moi chu ky; da thay
// trong sandbox. imul khong bi gop.)
//
// Dung kem:  perf stat -e cycles:u,instructions:u taskset -c <cpu> coreclk
//   - cycles:u ~= 3 x so_imul (±5%)     -> bo dem cycles la CHU KY LOI THAT;
//     khi do cyc/cpu_ns trong ban ghi la tan so hieu dung that.
//   - cycles:u / thoi_gian_ns ~= hang so (vd 2,0 GHz) trong khi GHz_wall
//     khac (vd 2,6-3,1 khi turbo) hoac doi theo tai -> bo dem la chu ky
//     THAM CHIEU; khi do "GHz hieu dung khong doi" o E4p khong noi gi ve
//     turbo, va CPI tu vPMC phai goi la "chu ky tham chieu / lenh".
//   Chi chay khi steal ~ 0 (nhu E4): steal lam thoi_gian dai ra -> GHz_wall
//   thap gia.
//
// Cach dung:  taskset -c <cpu> coreclk [so_vong]
//   moi vong = 8 imul phu thuoc; mac dinh 100000000 vong = 0,8 ti imul
//   = 2,4 ti chu ky (~0,8-1,2 s o 2-3 GHz). Lam nong 2 trieu vong truoc khi
//   do (~2% so voi phan do; perf stat dem ca phan nay).
//   In MOT dong:
//   so_imul=... chu_ky_ky_vong=... thoi_gian_ns=... GHz_wall=... kiem=...
//   (kiem = gia tri cuoi cua thanh ghi, de trinh bien dich khong bo vong lap)

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static inline uint64_t now_ns(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

/* 8 lenh imul phu thuoc nhau tren cung mot thanh ghi; y le nen x luon doi. */
#define IMUL8(x, y)                                                     \
	__asm__ volatile("imul %1, %0\n\timul %1, %0\n\timul %1, %0\n\t"   \
			 "imul %1, %0\n\timul %1, %0\n\timul %1, %0\n\t"   \
			 "imul %1, %0\n\timul %1, %0"                      \
			 : "+r"(x)                                         \
			 : "r"(y))

int main(int argc, char **argv)
{
	uint64_t loops = 100000000ull;
	uint64_t x = 1, y = 3, t0, t1, n;

	if (argc > 1) {
		loops = strtoull(argv[1], NULL, 10);
		if (loops == 0) {
			fprintf(stderr, "so_vong phai > 0\n");
			return 2;
		}
	}

	/* Lam nong: de loi len tan so on dinh truoc khi do. */
	for (uint64_t i = 0; i < 2000000ull; i++)
		IMUL8(x, y);

	t0 = now_ns();
	for (uint64_t i = 0; i < loops; i++)
		IMUL8(x, y);
	t1 = now_ns();

	n = loops * 8ull;
	printf("so_imul=%llu chu_ky_ky_vong=%llu thoi_gian_ns=%llu GHz_wall=%.4f kiem=%llu\n",
	       (unsigned long long)n, (unsigned long long)(3ull * n),
	       (unsigned long long)(t1 - t0),
	       3.0 * (double)n / (double)(t1 - t0), (unsigned long long)x);
	return 0;
}
