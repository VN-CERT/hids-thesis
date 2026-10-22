# R034 — M6c-2: E4p theo đúng cơ chế E4 gốc, STEALCHECK theo tổng mọi CPU, dấu tần số mỗi đợt đo, bổ sung số liệu R033

1. **Số báo cáo:** R034. **Ngày giờ:** 2026-10-22 10:49 (+07). **Mốc:** M6c-2. **Git commit:** `ec155d8` (trước commit báo cáo này); tag `m6c.2` gắn ở bước kết thúc.
2. **Mục tiêu:** làm lại E4p theo đúng cơ chế E4 gốc (`-loops`, không tự kiểm trong lượt chạy) để trả lời câu 8.2 của R033; đổi tiêu chí STEALCHECK sang tổng mọi CPU (quyết định 8.4); thêm dấu tần số coreclk cho mỗi đợt đo (phần 3); bổ sung số liệu còn thiếu của R033 từ dữ liệu đã có (phần 1). Không sửa BPF.

## 3. Đã làm gì

### Phần 1 — bổ sung số liệu từ dữ liệu đã có (không chạy lại gì)

**1a.** Bản ghi/giây mỗi ô từ collect-stats của phần 4 M6c-1 (`validation/m6c1-20261021/part4/overhead/`). Nguyên văn (file `validation/m6c2-20261022/part1.txt`):

```
=== 1a: ban ghi/giay moi o C1 (10 luot, tu collect-stats.txt), mat ===
T1 C1 n=10 min=1184399.5 max=1419555.1 trung_vi=1261136.9 mat_tong=0
T3 C1 n=10 min=429970.7 max=442398.2 trung_vi=435681.4 mat_tong=0
T4 C1 n=10 min=404063.1 max=462231.8 trung_vi=417455.0 mat_tong=0
T3-R25 C1 n=10 min=129839.3 max=133129.4 trung_vi=132093.7 mat_tong=0
T3-R50 C1 n=10 min=283676.9 max=287653.7 trung_vi=285209.5 mat_tong=0
T4-R25 C1 n=10 min=129143.1 max=130185.2 trung_vi=130004.9 mat_tong=0
T4-R50 C1 n=10 min=250237.6 max=253855.7 trung_vi=253248.4 mat_tong=0
=== 1a: C2 (collector loc cgroup decoy, khong phai tai) ===
T1 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
T3 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
T4 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
T3-R25 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
T3-R50 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
T4-R25 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
T4-R50 C2 n=10 ban_ghi_moi_luot=[0] mat_tong=0
```

(C2 bằng 0 vì collector ở C2 lọc theo cgroup decoy, không phải cgroup của tải — đúng định nghĩa C2.)

**1b.** Dòng `instructions:u` cạnh `cycles:u` của cả 6 lần coreclk trong `validation/m6c1-20261021/coreclk/coreclk.log` (nguyên văn):

```
L=0 lan=1:      2,494,480,873      cycles:u |     1,324,291,645      instructions:u                   #    0.53  insn per cycle
L=0 lan=2:      2,494,360,503      cycles:u |     1,324,291,632      instructions:u                   #    0.53  insn per cycle
L=0 lan=3:      2,493,921,977      cycles:u |     1,324,291,640      instructions:u                   #    0.53  insn per cycle
L=22 lan=1:     2,495,184,684      cycles:u |     1,324,291,714      instructions:u                   #    0.53  insn per cycle
L=22 lan=2:     2,498,350,036      cycles:u |     1,324,291,627      instructions:u                   #    0.53  insn per cycle
L=22 lan=3:     2,498,225,069      cycles:u |     1,324,291,659      instructions:u                   #    0.53  insn per cycle
```

**1c.** Giá trị C0 thời M5e/M5f/M5h tìm trong `reports/`, trích nguyên văn dòng chứa số, đặt cạnh C0 của M6c-1. Không kết luận.

- Vi mô sysinj, C0 (ns/syscall): R026 (M5h), mục Bảng T1: `C0                141.84 ± 0.03        —` (n=5). R021 (M5f) không có cùng ma trận T1 (ghi trong R026: "(R021/M5f không có cùng ma trận T1 5 điều kiện...)"). Cạnh đó, M6c-1: **185,65 ns**.
- T3 kịch trần, C0 (TPS): R021 (M5f): `T3 C0 run1 TPS=4943.3227`, `T3 C0 run2 TPS=5016.8065`, `T3 C0 run3 TPS=4934.5471`, và `(C0 trung bình TPS ≈ 4965 → ...)`. R026 (M5h): `C0      4901.59 ± 28.24    4965.22` (n=3). Cạnh đó, M6c-1: **2962,71 TPS**.
- T4 kịch trần, C0 (req/s): R026 (M5h): `C0                140081 ± 335         142675` (cột thứ hai là trung vị/trung bình R021). R020 (M5e): `T4 C0 mean=185353.8171 std=2327.5880 ci95_half=1724.3013 n=7`. Cạnh đó, M6c-1: **68258,01 req/s**.

### Phần 2 — STEALCHECK theo tổng mọi CPU (commit riêng)

Thay đổi trong `internal/stealcheck/stealcheck.go` và `cmd/hids-collect/main.go` (commit "M6c-2 phan 2: ..."):

- Giữ nguyên: cửa sổ 3 s, thử lại tối đa 3 cửa sổ, fail-closed, cờ `-steal-fallback` và `-allow-no-stealclock`, bảng per-CPU in đầy đủ vào log mỗi cửa sổ kèm dòng tổng.
- Tiêu chí mới: trên mọi CPU online, đạt khi |Σvmw_delta − Σrq_delta| ≤ max(5 ms, 1% × Σvmw_delta). Dòng in: `STEALCHECK lan=<k> tong_vmw_ns=<...> tong_rq_ns=<...> lech_ns=<...> nguong_ns=<...> cpu_lech_max=<cpu>:<ns> ket_qua=DAT|LECH`.
- Chú thích mã cũ (lý do ở 1b của M6c-1) đã thay bằng: "kernel chỉ cộng steal vào rq->prev_steal_time tại tick hoặc khi thoát idle qua ranh giới jiffy, nên một CPU gần như rảnh nhưng thức dậy liên tục có thể chậm vài ms so với đồng hồ vmw trong vài giây; tổng trên mọi CPU không lệch có hệ thống; phép kiểm gốc là G1 10 phút (0,08%)". Mô tả trong `.cursor/rules/hids.mdc` đã cập nhật.

Kiểm sau sửa (container dừng), dữ liệu `validation/m6c2-20261022/part23/`:

```
=== G7a x1 (binary sau sua STEALCHECK) ===
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0

=== G3 x1 ===
S1-ketqua.txt: g5_max_ns=0
S2-ketqua.txt: g5_max_ns=500
S3-ketqua.txt: g5_max_ns=499
S4-ketqua.txt: g5_max_ns=0
S5-ketqua.txt: g5_max_ns=500
so khoang CLAMPED va |phan du| > 500 ns: 0 / tong (moi kich ban)
recursion_misses (bpf_prog_info), tong 0 tren 31 chuong trinh
```

Ba dòng STEALCHECK của ba lần khởi động bất kỳ trong nhiệm vụ (nguyên văn):

```
STEALCHECK lan=1 tong_vmw_ns=211475713 tong_rq_ns=211016981 lech_ns=458732 nguong_ns=5000000 cpu_lech_max=1:399231 ket_qua=DAT
STEALCHECK lan=1 tong_vmw_ns=181866342 tong_rq_ns=181294830 lech_ns=571512 nguong_ns=5000000 cpu_lech_max=1:537571 ket_qua=DAT
STEALCHECK lan=1 tong_vmw_ns=210395949 tong_rq_ns=210219313 lech_ns=176636 nguong_ns=5000000 cpu_lech_max=1:169390 ket_qua=DAT
```

Đếm STEALCHECK toàn nhiệm vụ M6c-2 (G7a ×1, G3 ×5 kịch bản, E4p ×9 lượt = 15 lần khởi động có dòng STEALCHECK): **cả 15 lần đều `ket_qua=DAT` ở `lan=1`; 0 lần phải thử lại; 0 lần từ chối.** Không có dòng `ket_qua=LECH` nào trong log của nhiệm vụ.

### Phần 3 — dấu tần số cho mỗi đợt đo

Script mới `scripts/freq_stamp.sh <cpu>`: kiểm sha256 `tools/coreclk.c` (khớp `88ef821e…` mới chạy), build `bin/coreclk` nếu thiếu, chạy 3 lần `taskset -c <cpu> bin/coreclk 100000000` (không perf), in `date -Is`, 3 giá trị GHz_wall và trung vị; mã thoát 0.

Chạy trên máy rảnh (container dừng), nguyên văn:

```
=== freq_stamp CPU 12 ===
2026-10-22T10:27:43+07:00
lan 1: GHz_wall=1.9280
lan 2: GHz_wall=1.9359
lan 3: GHz_wall=1.9360
trung vi GHz_wall=1.9359
=== freq_stamp CPU 20 ===
2026-10-22T10:27:47+07:00
lan 1: GHz_wall=1.9308
lan 2: GHz_wall=1.9361
lan 3: GHz_wall=1.9349
trung vi GHz_wall=1.9349
```

Quy ước mới đã ghi vào `.cursor/rules/hids.mdc`: mọi đợt overhead và E-series bắt đầu bằng `freq_stamp.sh` trên CPU của tải; số GHz ghi trong báo cáo cạnh bảng kết quả; so sánh tuyệt đối giữa hai đợt chỉ khi GHz khác nhau ≤ 2%.

### Phần 4 — E4p theo đúng cơ chế E4 gốc

Script mới `scripts/m6c2_e4p.sh` (không sửa `m4.sh`, `m6c_e4p.sh`, `m6c1_e4p.sh`) làm đúng như E4 của `scripts/m4.sh`:

- Bước `calibrate` khi máy rảnh (container dừng): `calibrate_wl` (wl `mixed 1`, 3 s) và `calibrate_mem` (wl `mem 1`, 20 s) viết `out/m4-loops.txt`. Kết quả đợt này (nguyên văn): `calibrate xong: burn_loops=2634849 mem_steps=506088`.
- Mỗi mức: `freq_stamp.sh 20` một lần, rồi 3 lượt `e4_workers` (dòng 308): khởi động L worker `stress-ng --stream 1 --taskset 0-19,21-23 --timeout 120` (nguyên văn lệnh trong file kết quả từng lượt: `stress-ng: stress-ng --stream 1 --taskset 0-19,21-23 --timeout 120 (x12 worker)` / `(x22 worker)`), `sleep 2`, rồi `run_wl_mem "$loops" 500`.
- wl trong lượt chạy: `-loops` đọc từ file hiệu chuẩn, **không tự kiểm mem**. Dòng lệnh wl thực tế của một lượt mỗi mức (nguyên văn từ file kết quả; cả ba mức giống nhau vì cùng một lần hiệu chuẩn): `wl: taskset -c 20 ./bin/wl -loops 2634849 mem 500`.
- Collector gắn đúng cách `run_wl_mem` của m4.sh (dòng 212): `-pid <wl_pid>`, khởi động 0,5 s sau wl, chờ READY, hai cổng `.`; khác duy nhất là thêm `-pmu on` theo yêu cầu nhiệm vụ (và giữ `-duration 90s` như m4.sh). Mỗi lượt đủ 500/500 khoảng đốt có cờ PMU ngay attempt 1 (yêu cầu ≥ 450), nên `so_attempt = 1` ở cả 9 ô.

Kết quả (trung vị trên từng bản ghi; GHz = trung vị của `cyc/cpu_ns` tính trên từng bản ghi; `GHz_wall` là dấu tần số của mức, đo trên CPU 20 trước mức đó):

```
L=0 run1: cpu_ns=14823782.0 inst=14170548 cyc=27660199.0 CPI=1.9519 GHz=1.9623 khoang=500 attempt=1 GHz_wall=1.9338
L=0 run2: cpu_ns=14374572.5 inst=14170548 cyc=27163795.5 CPI=1.9169 GHz=1.9612 khoang=500 attempt=1 GHz_wall=1.9338
L=0 run3: cpu_ns=14806265.5 inst=14170548 cyc=27237013.0 CPI=1.9221 GHz=1.9612 khoang=500 attempt=1 GHz_wall=1.9338
L=12 run1: cpu_ns=24971997.5 inst=14170558.5 cyc=47377027.0 CPI=3.3433 GHz=1.9572 khoang=500 attempt=1 GHz_wall=1.9314
L=12 run2: cpu_ns=26004697.0 inst=14170560.0 cyc=49677969.0 CPI=3.5057 GHz=1.9573 khoang=500 attempt=1 GHz_wall=1.9314
L=12 run3: cpu_ns=25643003.0 inst=14170559.0 cyc=48866095.0 CPI=3.4484 GHz=1.9579 khoang=500 attempt=1 GHz_wall=1.9314
L=22 run1: cpu_ns=42466242.0 inst=14170579.0 cyc=98678279.5 CPI=6.9636 GHz=2.4110 khoang=500 attempt=1 GHz_wall=2.5239
L=22 run2: cpu_ns=39452113.0 inst=14170576.0 cyc=85491309.5 CPI=6.0330 GHz=2.0744 khoang=500 attempt=1 GHz_wall=2.5239
L=22 run3: cpu_ns=39050517.0 inst=14170574.0 cyc=90758257.5 CPI=6.4047 GHz=2.2281 khoang=500 attempt=1 GHz_wall=2.5239
```

Dấu tần số của mức L=22 (nguyên văn, file `validation/m6c2-20261022/e4p/freq-L22.txt`; hai mức L=0/L=12 ở cùng thư mục):

```
2026-10-22T10:41:45+07:00
lan 1: GHz_wall=2.5185
lan 2: GHz_wall=2.5239
lan 3: GHz_wall=2.5267
trung vi GHz_wall=2.5239
```

Kỳ vọng của kiến trúc sư (không phải tiêu chí): inst không đổi theo L (±3%); cpu_ns và CPI tăng theo L; GHz không đổi. Output thật: inst trung vị ở cả 9 ô nằm trong khoảng 14170548–14170579 (chênh nhau tối đa 31 trên ~14,17 triệu); cpu_ns và CPI tăng theo L; GHz hiệu dụng ở L=0/L=12 là 1,957–1,962, ở L=22 là 2,074–2,411 và dấu tần số `GHz_wall` của mức L=22 là 2,5239 so với 1,9338/1,9314 của hai mức trước. Báo cáo chỉ in số, không kết luận; điểm GHz này đưa vào câu 8.1.

Đoạn mã `tools/wl.c` của vòng đốt mem (dòng 461–465, nguyên văn):

```c
		for (r = 0; r < rounds; r++) {
			mem_work(buf, mem_sz, mem_steps);
			do_sleep_us(10000);
			marker_getppid();
		}
```

và hàm `mem_work_with_seed` mà vòng đốt gọi (dòng 214–223, nguyên văn):

```c
static void mem_work_with_seed(unsigned char *buf, size_t sz, unsigned long long steps,
			     unsigned int *seed)
{
	unsigned long long i;

	for (i = 0; i < steps; i++) {
		size_t off = (size_t)(rand_r(seed) % (unsigned int)sz);
		buf[off]++;
		asm volatile("" ::: "memory");
	}
}
```

Đoạn mã tự kiểm mem `self_test_mem_10ms` (dòng 252–293, nguyên văn):

```c
static void self_test_mem_10ms(unsigned char *buf, size_t sz, unsigned long long *mem_steps)
{
	unsigned long long samples[5];
	int pass, i;

	for (pass = 0; pass < 2; pass++) {
		unsigned long long sum = 0;
		unsigned int seed = 42;

		for (i = 0; i < 5; i++) {
			unsigned long long m0, m1, c0, c1, dm, dc;

			m0 = mono_us();
			c0 = thread_cpu_us();
			mem_work_with_seed(buf, sz, *mem_steps, &seed);
			m1 = mono_us();
			c1 = thread_cpu_us();
			dm = m1 - m0;
			dc = c1 - c0;
			samples[i] = dm;
			fprintf(stderr, "wl: tu kiem mem %d/5 mono=%llu us thread_cpu=%llu us\n",
				i + 1, dm, dc);
		}
		if (mono_in_range(samples[0]) && mono_in_range(samples[1]) &&
		    mono_in_range(samples[2]) && mono_in_range(samples[3]) &&
		    mono_in_range(samples[4]))
			return;
		if (pass == 0 && sum > 0) {
			unsigned long long avg = sum / 5;

			*mem_steps = (unsigned long long)((double)(*mem_steps) * 10000.0 / (double)avg);
			if (*mem_steps == 0)
				*mem_steps = 1;
			fprintf(stderr, "wl: dieu chinh mem_steps=%llu (trung binh %llu us)\n",
				*mem_steps, avg);
			continue;
		}
		fprintf(stderr, "wl: LOI tu kiem mem: mono lech qua 5%% so voi 10 ms\n");
		_exit(1);
	}
}
```

Trong cơ chế E4 gốc, `self_test_mem_10ms` chỉ chạy khi wl khởi động **không có** `-loops` (nhánh hiệu chuẩn ở dòng ~405–412 của `tools/wl.c`); lượt chạy E4 có `-loops` nên không tự kiểm, `mem_steps` đọc từ file (dòng 449 trong nhánh `mem` của vòng chính). Ở M6c-1 (R033), wl chạy không có `-loops`, nên tự kiểm chạy trong từng lượt, dưới tải ở L=12/L=22.

## 4. Lệnh build, lệnh chạy (để chạy lại được)

- Build: `make build` (sau commit phần 2; kiểm sha256 5 file trước build).
- Phần 1: chỉ đọc dữ liệu cũ; bảng ở `validation/m6c2-20261022/part1.txt`.
- Phần 2+3: `bash scripts/m6c2_part23.sh validation/m6c2-20261022/part23` (unit `hids-m6c2p23`).
- Phần 4: `bash scripts/m6c2_part4_driver.sh` (bên trong gọi `scripts/m6c2_e4p.sh validation/m6c2-20261022/e4p`; unit `hids-m6c2e4p`).

## 5. Kết quả kiểm — output nguyên văn

Đã dán ở mục 3 theo từng phần. File đầy đủ: `validation/m6c2-20261022/part1.txt`, `part23/`, `e4p/` (kèm `freq-L0.txt`, `freq-L12.txt`, `freq-L22.txt`, `calibrate.txt`), log job `out/jobs/m6c2p23.log`, `out/jobs/m6c2e4p.log`.

Cuối nhiệm vụ: `systemctl list-units 'hids-*' 'hidsrun-*' --state=active` trống; `bpftool prog show | grep -c hids_` = 0; 12 container chạy đủ.

## 6. File dữ liệu đã tạo

- `validation/m6c2-20261022/part1.txt`, `part23/` (freq-12, freq-20, g7a, g3), `e4p/` (9 ô + hiệu chuẩn + 3 dấu tần số)
- Script mới: `scripts/freq_stamp.sh`, `scripts/m6c2_part23.sh`, `scripts/m6c2_e4p.sh`, `scripts/m6c2_part4_driver.sh`
- Sửa: `internal/stealcheck/stealcheck.go`, `cmd/hids-collect/main.go`, `.cursor/rules/hids.mdc`

## 7. Quyết định đã tự đưa ra và lý do

1. Collector ở phần 4 giữ đúng dòng lệnh của `run_wl_mem` trong m4.sh (`-pid`, `-duration 90s`, `-out`) và chỉ thêm `-pmu on` như nhiệm vụ yêu cầu; không thêm `-zstd-level 0` như các script E4p của M6c/M6c-1.
2. Số attempt tối đa cho mỗi ô E4p đặt là 3 (nhiệm vụ không ghi số lần); cả 9 ô đều đạt ở attempt 1 nên con số này không ảnh hưởng kết quả.
3. Dấu tần số của một mức đo một lần trước mức đó (không đo lại trước từng lượt), đúng câu chữ nhiệm vụ "Trước mỗi mức: `freq_stamp.sh 20` một lần".

## Trả lời mục 8 của R033

Chép nguyên văn quyết định của kiến trúc sư (từ nhiệm vụ M6c-2):

 - 8.1 Lệch rq: ĐÓNG. Thứ tự đảo cho on/off bằng nhau (+0,451/+0,382 µs), S4 khớp schedstat 0,003–0,005% ở mọi chế độ → rq của collector không phụ thuộc PMU; lệch khi collector gắn trước là độ dài chương trình collector lọt vào phép đo của bpftrace. +7,769 µs (on) lớn hơn kỳ vọng vì hai lần đọc PMU lúc switch-in từ idle tốn ≈4,6 µs/lần, hơn 1,47 µs ở sys_enter — ghi nhận, không theo đuổi (PMU theo bản ghi không vào production). Cấu hình đối chiếu dùng cho bài: bpftrace tối giản gắn TRƯỚC collector (B6a của R031 và swap ở R033). So sánh "tổng" ở S3/S5 không dùng làm bằng chứng; chỉ dùng ghép theo mốc thời gian (S2, n=500).
 - 8.2 E4p inst tăng theo L: CHƯA chấp nhận; làm lại theo phần 4 của nhiệm vụ M6c-2 (cơ chế `-loops` của E4 gốc, không tự kiểm). → Đã làm ở phần 4 của báo cáo này.
 - 8.3 G7-cap: ghi nhận là giới hạn hiện tại: ≈0,95 triệu bản ghi/giây đọc được với zstd mặc định (1 tiến trình mất 0; 2–4 tiến trình mất, đếm đúng). Số này thay số 1,15–1,2 triệu cũ. Không xử lý thêm.
 - 8.4 STEALCHECK: đổi tiêu chí sang TỔNG mọi CPU (phần 2 của nhiệm vụ M6c-2). Giữ fail-closed và 3 cửa sổ. → Đã làm ở phần 2 của báo cáo này.
 - 8.5 T4 kịch trần đọc bằng grep: CHẤP NHẬN (cùng dòng `Requests/sec:`, cùng biểu thức với m5f_parse.py). Không chạy lại.
 - 8.6 T3 C0 thấp hơn m5h: nhiều khả năng do trạng thái máy/host (tần số lõi hiệu dụng 1,92 GHz theo coreclk, không turbo; T4 C0 cũng giảm 51%), không phải đường pgtest. Không chẩn đoán pgtest; đối chiếu theo phần 1c và từ nay đóng dấu tần số mỗi đợt đo (phần 3). → Đối chiếu ở mục 1c, dấu tần số ở phần 3 của báo cáo này.

## Thay đổi ngoài phạm vi nhiệm vụ

`git diff --stat m6c.1..HEAD -- scripts analysis internal cmd tools` (nguyên văn):

```
 cmd/hids-collect/main.go          |  56 +++++++---
 internal/stealcheck/stealcheck.go |  30 ++++-
 scripts/freq_stamp.sh             |  27 +++++
 scripts/m6c2_e4p.sh               | 219 ++++++++++++++++++++++++++++++++++++++
 scripts/m6c2_part23.sh            |  27 ++++++
 scripts/m6c2_part4_driver.sh      |  11 +++
 6 files changed, 281 insertions(+), 20 deletions(-)
```

Ngoài các file trên: `.cursor/rules/hids.mdc` (mô tả tiêu chí STEALCHECK mới + quy ước dấu tần số, theo đúng nhiệm vụ), `docs/STATE.md`, `docs/tasks/M6c-2.md`, báo cáo này và `reports/INDEX.md`. Không sửa file kiến trúc sư nào, không sửa BPF, không sửa `scripts/m4.sh`, `scripts/m6c_e4p.sh`, `scripts/m6c1_e4p.sh`.

sha256 của 5 file kiến trúc sư, kiểm trước mỗi lần build và lúc viết báo cáo:

```
8b05464db597cfc471dc7af24ce651ef905751ebd80ec463b3863b7dd0263c35  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
```

Cả 5 giá trị khớp với giá trị kiến trúc sư ghi trong nhiệm vụ.

## 8. Cần kiến trúc sư quyết định

1. **Tần số ở mức L=22 khác hẳn hai mức trước:** dấu tần số trước mức L=22 là 2,5239 GHz so với 1,9338 (L=0) và 1,9314 (L=12), và GHz hiệu dụng trong bản ghi L=22 là 2,074–2,411 so với 1,957–1,962 ở hai mức trước. Theo quy ước mới (chỉ so sánh tuyệt đối khi GHz khác nhau ≤ 2%), kiến trúc sư quyết các số tuyệt đối của L=22 (cpu_ns, cyc) có dùng được cạnh L=0/L=12 hay phải đo lại mức L=22 trong một đợt có dấu tần số khớp; CPI và inst là tỉ số/số đếm không phụ thuộc tần số.
2. **E4p cơ chế gốc — inst không đổi:** với cơ chế `-loops`, inst trung vị của 9 ô nằm trong 14170548–14170579, cpu_ns và CPI tăng theo L (bảng phần 4). Kiến trúc sư quyết câu 8.2 của R033 đã đóng được chưa.

## 9. Việc người dùng cần làm tay

Không có. Mọi job đã xong, 12 container đã khởi động lại, kernel sạch.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất

- Không có cổng nào không đạt trong nhiệm vụ này: G7a mất 0; G3 phần dư ≤ 500 ns, CLAMPED 0/tổng, recursion_misses = 0; STEALCHECK 15/15 lần đạt ở cửa sổ đầu; E4p đủ 9/9 ô ở attempt 1, mỗi ô 500/500 khoảng đốt có PMU.
- Đề xuất: chờ kiến trúc sư trả lời mục 8 (đặc biệt câu 1 về dấu tần số của L=22) rồi mở nhiệm vụ tiếp theo; không tự mở rộng phạm vi.

## Phụ lục — Trả lời của kiến trúc sư về mục 8 (nhận 2026-10-22, ghi nguyên văn)

1. Không đo lại L=22; so sánh giữa các mức bằng cyc, CPI, inst (không phụ thuộc tần số); cpu_ns luôn kèm GHz hiệu dụng của mức đó; việc tần số nhảy 1,93→2,52 GHz là phát hiện: turbo có nhưng host dùng chung nên lúc có lúc không; quy ước bổ sung: freq_stamp trước VÀ sau mỗi khối đo, lệch >2% thì ghi chú khối đó.
2. Câu 8.2 của R033 đóng: inst không đổi với cơ chế -loops. Ghi nhận lỗi trong tools/wl.c self_test_mem_10ms: biến sum không được cộng dồn nên nhánh điều chỉnh mem_steps là mã chết; không sửa trong nhiệm vụ nào hiện tại.
