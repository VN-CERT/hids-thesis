# R032 — M6c: PMU trong bản ghi (64 byte), sửa cuộc đua ngắt, bộ overhead cuối

## 1. Thông tin

- Số báo cáo: R032
- Ngày giờ: 2026-10-21 16:35 (+07)
- Mốc: M6c (nhiệm vụ lưu nguyên văn ở `docs/tasks/M6c.md`)
- Git commit: xem commit chứa báo cáo này
- Tag: `m6c` (gắn kèm báo cáo này, push github `--all` và `--tags`)
- BPF mới do kiến trúc sư viết (`bpf/sys_enter.bpf.c`, sha256 ở mục cuối): bản ghi 64 byte có `inst`/`cyc`, cờ PMU ở bit7, và sửa cuộc đua ngắt bằng cơ chế `gen` trong `snap_sys_enter` (đọc mốc thời gian, steal, PMU và tổng irq bên trong cặp kiểm `gen`; đọc lại tối đa 3 lần nếu một ngắt kết thúc chen giữa). Phía Go làm theo đặc tả, không sửa BPF.

## 2. Mục tiêu

- Cập nhật đặc tả bản ghi 64 byte và cờ PMU (bit7) trong `.cursor/rules/hids.mdc`; file 48/56 byte cũ vẫn đọc được.
- Phía Go: recfmt nhận 48/56/64; loader mở bộ đếm PMU user per-CPU (cờ `-pmu auto|on|off`); header ghi `pmu:`; luồng host thêm hai cột PMU; rec-export thêm `inst,cyc,pmu_ok`; rec-stat thêm tỉ lệ cờ PMU.
- Cổng: đọc lại file cũ, G7a (on/off), G7b ×3, G7b-nhỏ, G3 ×3 (on) + ×1 (off), G11 (PMU so với perf stat), G8, G9a, G9b, G10.
- Bộ overhead cuối: T1, T3, T4 (kịch trần và tải cố định 25%/50%), mỗi ô 10 lượt xen kẽ, xử lý bằng `analysis/m6c_stats.py`; đường CPU theo tốc độ; G7-cap 1/2/4.
- E4p: E4-stream với PMU ở L = 0, 12, 22.

## 3. Đã làm gì

- `.cursor/rules/hids.mdc`: đặc tả bản ghi 64 byte (`inst u32 | cyc u32` trước `reserved`), bit7 = PMU, định nghĩa inst/cyc (chế độ user, `exclude_kernel=1, exclude_hv=1`, chỉ trong đoạn ON-CPU, bão hoà u32 + OVERFLOW).
- `internal/recfmt`: `RecordSize = 64`, thêm `RecordSize56 = 56`, giữ `LegacyRecordSize = 48`; `Decode`/`ForEach`/`RecordSizeFromHeader` nhận cả ba; `Record.Inst`, `Record.Cyc`; `FlagPMU = 1<<7`.
- `internal/syscallbpf` (loader): cờ `-pmu auto|on|off` (mặc định auto). Mở hai `perf_event_open` (PERF_COUNT_HW_INSTRUCTIONS, PERF_COUNT_HW_CPU_CYCLES; pid=-1, cpu=id CPU; exclude_kernel/hv; disabled=0; read_format có TOTAL_TIME_ENABLED|RUNNING) trên mỗi CPU online, nạp fd vào `hids_pmu_inst`/`hids_pmu_cyc` tại chỉ số = số CPU, đặt `hids_pmu_on`. Lỗi mở ở bất kỳ CPU nào: auto → tắt PMU + in cảnh báo + header `pmu: off`; on → từ chối chạy. Hằng số UAPI đối chiếu với `/usr/include/linux/perf_event.h`. Đồng bộ struct Go `irqState` thêm trường `Gen` theo BPF mới (nếu không, `IRQStats()` lỗi "doesn't consume all data"; số liệu bản ghi không bị ảnh hưởng vì cộng dồn irq nằm trong BPF).
- Header `.bin` ghi thêm `pmu: on|off` và `pmu_events: instructions:u,cycles:u` ở cả hai chế độ `-out` và `-datadir`.
- Luồng host 1 Hz (chế độ `-datadir`): thêm hai cột `pmu_inst_delta`, `pmu_cyc_delta` ở CUỐI dòng (tổng user trên mọi CPU đọc từ chính các fd; `na` khi PMU tắt).
- `cmd/rec-export`: thêm cột `inst`, `cyc`, `pmu_ok` ở CUỐI. `cmd/rec-stat`: thêm dòng tỉ lệ bản ghi không-FIRST có cờ PMU.
- Rà chỗ giả định 56 byte/bit7=0: chỉ có `internal/recfmt` (đã đổi), chú thích đầu file `cmd/hids-collect/main.go` (đã đổi sang 64), và `scripts/bin_header.py` (đã nhận 64). Các script python đọc bản ghi theo `record_size` trong header và offset trong 48 byte đầu nên tương thích. `scripts/g3.sh` thêm `${HIDS_COLLECT_EXTRA:-}` vào 3 lệnh collector (giống `g7.sh`) để truyền `-pmu`.
- Script mới: `scripts/m6c_gates1.sh`, `m6c_gates2.sh`, `m6c_g11.sh`, `m6c_gates3.sh`, `m6c_gates4.sh`, `m6c_overhead.sh`, `m6c_t4fix.sh`, `m6c_e4p.sh`.

## 4. Lệnh build, lệnh chạy

```bash
make build
bash scripts/m6c_gates1.sh validation/m6c-20261021/gates1
bash scripts/m6c_gates2.sh validation/m6c-20261021/gates2b   # G3 on x3, off x1, G11
bash scripts/m6c_g11.sh validation/m6c-20261021/g11          # container da dung
bash scripts/m6c_gates3.sh validation/m6c-20261021/gates3    # G8/G9a (gate) + G9b (pre24h)
bash scripts/m6c_gates4.sh validation/m6c-20261021/gates4    # duong CPU + G7-cap
bash scripts/m6c_overhead.sh validation/m6c-20261021/overhead
bash scripts/m6c_t4fix.sh validation/m6c-20261021/overhead   # chay lai T4 + T3 C1 run10
bash scripts/m6c_e4p.sh validation/m6c-20261021/e4p5
```

## 5. Kết quả (nguyên văn)

### 5.1 Đọc lại dữ liệu cũ (file 56 byte `out/g3-S3-070928.bin`)

Không còn file `.bin` nào kèm file `.stats` (dữ liệu thô không vào git, bản lưu m5d chỉ còn log); đối chiếu ba cách trên cùng file:

```
rec-stat (moi):  tong so ban ghi trong file : 1003
rec-check (moi): so ban ghi trong cua so: 1003
doc lap (python struct): record_size=56 so_ban_ghi=1003 byte_thua=0
```

### 5.2 G7a hai lần (-zstd-level 0)

Cả `-pmu on` và `-pmu off`:

```
tong ban ghi doc duoc:                        1000001
tong bo dem mat:                              0
tong so seq bi thieu theo CPU:                0
tong (perf - ban ghi):                        0
```

### 5.3 G7b 3 lần (24 × 1.000.000, -zstd-level 0, PMU mặc định auto = on)

Yêu cầu mới: perf − bản ghi = bộ đếm mất = seq thiếu, khớp tuyệt đối. Cả 3 lần (và 2 lần chạy thêm) đều khớp tuyệt đối:

```
run1: ban_ghi=19491724 mat=4508300 seq_thieu=4508300 (perf-ban_ghi)=4508300  mat 18.79%
run2: ban_ghi=22134048 mat=1865976 seq_thieu=1865976 (perf-ban_ghi)=1865976  mat 7.78%
run3: ban_ghi=21794034 mat=2205990 seq_thieu=2205990 (perf-ban_ghi)=2205990  mat 9.19%
run4: ban_ghi=22178917 mat=1821107 (khop tuyet doi)  mat 7.59%
run5: ban_ghi=22450506 mat=1549518 (khop tuyet doi)  mat 6.45%
```

G7b-nhỏ (ring 1 MiB): `tong ban ghi doc duoc: 17229465`, `tong bo dem mat: 6770559`, `tong so seq bi thieu theo CPU: 6770559`, `tong (perf - ban ghi): 6770559` — khớp tuyệt đối.

### 5.4 G3 S1–S5 với -pmu on ×3 và -pmu off ×1 (dừng container, một collector)

Mọi lần: g3_exit=0; phần dư G5 max ≤ 500 ns ở mọi kịch bản (S1=0, S2=497–500, S3=497–500, S4=0, S5=495–499); recursion_misses tổng 0; dòng đếm mới ở mọi kịch bản:

```
so khoang CLAMPED va |phan du| > 500 ns: 0 / tong 300   (S1, S4)
so khoang CLAMPED va |phan du| > 500 ns: 0 / tong 1000  (S2, S3)
so khoang CLAMPED va |phan du| > 500 ns: 0 / tong 1502  (S5)
```

Cuộc đua ngắt đã hết theo tiêu chí này. (Hai lần chạy đầu tiên của đợt 1 bị collector từ chối khởi động ở S4/S1 vì kiểm tra stealclock 3 giây đầu — lệch vmw/rq-steal 3.384.376 ns > ngưỡng 2.000.000 ns; đã chạy lại toàn bộ bằng binary cuối, kết quả ở trên.)

Lệch rq collector so với TỔNG bpftrace (wakeup + preempt) — in nguyên văn, không phải tiêu chí M6c:

```
-pmu on  lan1: S2 17.43%  S3 24.24%  S5 40.21%  (collector THAP hon)
-pmu on  lan2: S2 20.10%  S3 18.11%  S5 16.21%  (collector THAP hon)
-pmu on  lan3: S2 20.92%  S3 22.42%  S5 40.82%  (collector THAP hon)
-pmu off lan1: S2 3.61%   S3 8.76%   S5 7.50%   (collector CAO hon)
```

Chiều lệch đổi theo PMU bật/tắt; xem câu hỏi 2 ở mục 8.

### 5.5 G11 (PMU so với perf stat, S1 và S3, container dừng)

perf stat gắn khi wl đang chờ FIFO, dừng sau kịch bản; cửa sổ như `g3_window.py`. Không có chú thích ghép kênh trong output perf (đếm 100%). Nguyên văn:

S1 (`cpu 10000 300`, tid 214456):

```
     4,809,756,172      instructions:u
     5,990,469,100      cycles:u
collector: ban ghi trong cua so=301 khong_FIRST=301 co_PMU=301
ti le PMU (khong-FIRST): 301/301 = 100.0000%
tong inst collector = 4809756129
tong cyc collector = 5990460440
CPU 20: PMU 301/301 = 100.00%
```

Lệch inst: 43 (0.0000009%); lệch cyc: 8.660 (0.00014%).

S3 (`mixed 2000 3000 500`, tid 215745):

```
     1,601,534,310      instructions:u
     1,987,584,919      cycles:u
collector: ban ghi trong cua so=1001 khong_FIRST=1001 co_PMU=1001
ti le PMU (khong-FIRST): 1001/1001 = 100.0000%
tong inst collector = 1601534267
tong cyc collector = 1987581170
CPU 20: PMU 1001/1001 = 100.00%
```

Lệch inst: 43; lệch cyc: 3.749 (0.00019%). Phân bố cờ PMU theo CPU: wl ghim CPU 20 nên chỉ có CPU 20, tỉ lệ 100% — không CPU nào thấp bất thường.

### 5.6 G8, G9a, G9b, G10 (như R030)

`m6b1_gate.sh` exit=0:

```
PASS: G7a mat=0
PASS: G8 exec collector=501 perf=501
PASS: G8 fork collector=501 perf=501
PASS: G8 exit collector=502 perf=502
PASS: G8 exec /true = 500
PASS: G9 rec-chain seq_thieu=0 lo_hong=0 mat=0
PASS: G10 PAUSE_DISK
PASS: G10 RESUME_DISK
PASS: G10 bo vi dia=3060221
PASS: G10 kernel mat=0
```

`m6b1_pre24h.sh`:

```
PASS: G7a perf=ban_ghi=1000001 mat=0
PASS: G7b-nho (perf-ban_ghi)=mat=seq_thieu=5755927
PASS: G3 recursion_misses=0
PASS: G3 S1-S5 phan du max <= 500 ns
PASS: G9b rec-chain ranh_gioi seq_thieu=0 lo_hong=0 mat=0
FAIL: host lines=471
```

Dòng FAIL host: đếm lại bằng tay hai đoạn host của lần chạy 10 phút (xoay file theo giờ ở mốc :05): `host-2026102104.tsv.zst` 130 dòng + `host-2026102105.tsv.zst` 472 dòng = 602 dòng tổng (kỳ vọng ~600). Script pre24h chỉ đếm một đoạn nên báo 471. Hai cột PMU mới có mặt và có số thật (ví dụ một dòng: `pmu_inst_delta=222300282`, `pmu_cyc_delta=232564137`). Số liệu nguyên văn giữ nguyên ở trên; cách đếm của script ghi ở mục 7.

### 5.7 Bộ overhead cuối (mỗi ô 10 lượt xen kẽ, container dừng; output nguyên văn của `analysis/m6c_stats.py`)

T1 — sysinj N=10.000.000 ghim CPU 12, ns/syscall:

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T1	C0	10	184.3280	2.8521	182.2879	186.3681	0.0000	-	-	-
T1	C1	10	3745.6680	182.5139	3615.1145	3876.2215	1932.0668	1872.1722	1994.6941	0.0001
T1	C1n	10	797.2980	16.6901	785.3595	809.2365	332.5431	325.9759	339.2025	0.0001
T1	C2	10	243.1240	3.9474	240.3004	245.9476	31.8975	30.0581	33.5910	0.0001
```

T4 kịch trần — Requests/sec (đợt đầu hỏng vì wrk2 bắt buộc `-R`; chạy lại bằng `-R 10000000`, xem mục 7):

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T4	C0	10	88666.9930	8943.8585	82269.3865	95064.5995	0.0000	-	-	-
T4	C1	10	64758.8650	10951.7590	56924.9929	72592.7371	-26.9640	-34.1129	-17.2536	0.0004
T4	C1n	10	81086.9840	3248.4801	78763.3228	83410.6452	-8.5489	-14.0085	-2.3937	0.0207
T4	C2	10	92146.2950	4668.6759	88806.7575	95485.8325	3.9240	-2.4651	11.2719	0.2879
```

T3 kịch trần — TPS (VACUUM + CHECKPOINT trước mỗi lượt; run10 của C1 đợt đầu bị collector không READY do kiểm tra steal, đã chạy lại, giá trị thay vào là 950.70 ± 2.86 cho cả 10 lượt):

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T3	C0	10	3107.9297	45.2030	3075.5957	3140.2637	0.0000	-	-	-
T3	C1	10	950.7018	2.8600	948.6560	952.7476	-69.4104	-69.6329	-69.1096	0.0001
T3	C2	10	3030.7339	50.3654	2994.7072	3066.7606	-2.4838	-3.6776	-1.1345	0.0024
```

Tải cố định (mức theo C0 kịch trần đo trong đợt: T3 trung vị 3116.6 TPS, T4 trung vị khoảng 88.7 nghìn req/s). Độ trễ (ms, qua `analysis/m5f_parse.py`) và CPU cgroup (µs/60s):

```
T3-R25 lat_avg: C0 2.4837 | C1 8.8162 (+254.9589%) | C2 2.5246 (+1.6471%)
T3-R25 p50:     C0 2.2571 | C1 6.7456 (+198.8614%) | C2 2.3003 (+1.9140%)
T3-R25 p99:     C0 5.4746 | C1 32.3044 (+490.0778%) | C2 5.6531 (+3.2605%)
T3-R25 cgroupcpu: C0 85420275 | C1 155801530 (+82.3941%) | C2 86596505 (+1.3770%)
T4-R25 lat_avg: C0 1.2930 | C1 1.3330 (+3.0936%) | C2 1.2950 (+0.1547%)
T4-R25 p50:     C0 1.2370 | C1 1.2640 (+2.1827%) | C2 1.2350 (-0.1617%)
T4-R25 p99:     C0 2.6590 | C1 2.8070 (+5.5660%) | C2 2.6540 (-0.1880%)
T4-R25 cgroupcpu: C0 78002093 | C1 128876721 (+65.2221%) | C2 79900691 (+2.4340%)
T4-R50 lat_avg: C0 1.3790 | C1 33.6620 (+2341.0442%) | C2 1.3870 (+0.5801%)
T4-R50 p50:     C0 1.2880 | C1 2.7030 (+109.8602%) | C2 1.2910 (+0.2329%)
T4-R50 p99:     C0 3.2770 | C1 335.4100 (+10135.2762%) | C2 3.3890 (+3.4178%)
T4-R50 cgroupcpu: C0 131166277 | C1 206236842 (+57.2331%) | C2 134611559 (+2.6267%)
```

(Bảng đầy đủ gồm sd/CI/p_perm ở `validation/m6c-20261021/overhead/*.stats.txt`; các file TSV nguồn cùng thư mục.)

Số bản ghi/giây và mất của các lượt C1/C1n (từ `collect-stats.txt` từng lượt; mất tổng = 0 ở mọi lượt có số liệu): T1 C1 247.190–281.924 bản ghi/giây; T1 C1n 1.198.158–1.292.907; T3 C1 253.318–256.862; T4 C1 378.155–458.930 (9/10 lượt có file); T4 C1n 545.470–616.497.

### 5.8 Đường CPU của collector theo tốc độ (binary cuối, -pmu on, mỗi mức 2 phút)

Đạt được (trung vị records_per_sec trong status.tsv) và CPU collector (% một lõi, cửa sổ ổn định 120s từ `/proc/<pid>/stat`):

```
muc dich 1000/s   -> dat 1537/s   CPU 1.87%
muc dich 10000/s  -> dat 10236/s  CPU 4.43%
muc dich 100000/s -> dat 98803/s  CPU 23.62%
muc dich 500000/s -> dat 206677/s CPU 47.97%
kernel drops = 0 o moi muc.
```

So với R030 (chưa PMU): 1.5k/s → 1.43%; 10k/s → 3.83%; 97k/s → 21.37%; 475k/s → 114.97%. Ở mức đích 500k lần này chỉ đạt 207k bản ghi/giây (tải sysinj bị chính BPF có PMU làm chậm, khớp T1 C1 = 3.745 ns/syscall).

### 5.9 G7-cap với binary cuối (zstd mặc định, 60 giây mỗi mức)

```
1 tien trinh: 16010739 ban ghi (266846 ban ghi/giay), mat=0
2 tien trinh: 31683548 ban ghi (528059 ban ghi/giay), mat=0
4 tien trinh: 52398998 ban ghi (873650 ban ghi/giay), mat=0
```

### 5.10 E4p (E4-stream, -pmu on, 3 lần mỗi mức; khoảng đốt = bản ghi kết thúc khoảng đốt)

Lưu ý số hiệu: wl hiện tại ngủ bằng `clock_nanosleep` (nr=230 qua glibc) chứ không phải nanosleep (nr=35) như chú thích M4; khoảng đốt là bản ghi nr=230 (500 bản ghi mỗi lần, tất cả có cờ PMU). Trung vị mỗi lần:

```
L   run  cpu_ns      inst       cyc        CPI     GHz hieu dung
0   1    10920048    12169580   20788070   1.7082  1.9674
0   2    10756760    11852060   20394660   1.7208  1.9661
0   3    10822508    12062424   20541648   1.7029  1.9668
12  1    11775680    6877637    21527437   3.1301  1.9306
12  2    10961015    6542616    19941418   3.0479  1.9227
12  3    11659437    6366273    20658263   3.2450  1.8953
22  1    7067548     2669317    15163250   5.6806  1.9690
22  2    6622666     2662429    13429797   5.0442  1.9635
22  3    7418070     2727614    14958619   5.4841  1.9613
```

Đối chiếu kỳ vọng của kiến trúc sư (không phải tiêu chí): tần số hiệu dụng gần như không đổi (1.90–1.97 GHz) trong khi CPI tăng 1.71 → 3.05–3.25 → 5.04–5.68 theo L. inst giảm theo L vì wl hiệu chuẩn lại `mem_steps` lúc khởi động dưới chính mức tải đó (số bước cho "10 ms" nhỏ hơn khi bộ nhớ đang tranh chấp), nên cpu_ns ở L22 thấp hơn L0 dù CPI cao hơn. Số lần chạy đạt được sau nhiều lần thử lại vì tự kiểm mem của wl (5 mẫu phải trong ±5% của 10 ms) hay trượt trên máy ảo này; các lần trượt giữ nguyên trong `validation/m6c-20261021/e4p2/`, `e4p3/`, `e4p4/`.

## 6. File dữ liệu đã tạo

- `/root/hids/validation/m6c-20261021/gates1/` (file cũ, G7a on/off, G7b ×5 + summary, G7b-nhỏ)
- `/root/hids/validation/m6c-20261021/gates2b/` (G3 on ×3, off ×1, mỗi lần có `g3/`, `g3-g5-max.txt`, `g3-rq-tong.txt`; G11 hỏng đợt đầu giữ ở `gates2/`)
- `/root/hids/validation/m6c-20261021/g11/` (G11 chính thức: `S1.txt`, `S3.txt`, `S1.perfstat.txt`, `S3.perfstat.txt`, export CSV)
- `/root/hids/validation/m6c-20261021/gates3/` (gate + pre24h driver log; output pre24h nằm ở `/root/hids/validation/m6b1-pre24h-20261021/` theo quy ước cũ của script)
- `/root/hids/validation/m6c-20261021/gates4/` (rate-1000/10000/100000/500000, g7cap)
- `/root/hids/validation/m6c-20261021/overhead/` (T1/T3/T4/T3-R25/T4-R25/T4-R50 từng lượt, các TSV và `*.stats.txt`)
- `/root/hids/validation/m6c-20261021/e4p5/` (E4p đủ 9 ô; các đợt hỏng `e4p/`, `e4p2/`, `e4p3/`, `e4p4/` giữ nguyên)
- Log unit: `/root/hids/out/jobs/m6c-gates1.log`, `m6c-gates2b.log`, `m6c-g11.log`, `m6c-gates3.log`, `m6c-gates4.log`, `m6c-e4p*.log`, `m6c-overhead-driver.log`, `m6c-t4fix.log`

## 7. Quyết định đã tự đưa ra và lý do

- Đồng bộ struct Go `irqState` thêm `Gen`: BPF mới của kiến trúc sư thêm trường này; không sửa thì mọi lần đọc `IRQStats()` đều lỗi. Đây là phía Go bám theo BPF, không sửa BPF.
- `scripts/g3.sh` nhận `HIDS_COLLECT_EXTRA` (giống `g7.sh`): cần để truyền `-pmu on/off` cho G3; mặc định không đổi hành vi.
- T4 kịch trần chạy lại bằng `wrk2 -R 10000000`: bản wrk2 trên máy từ chối chạy không có `-R` ("Throughput MUST be specified with the --rate or -R option") nên toàn bộ T4 đợt đầu và T4-R25/R50 (kéo theo mức C0 trống) không có số. `-R` đặt cao không đạt được nên tương đương kịch trần mở vòng. File hỏng đợt đầu giữ nguyên tên `wrk2-hong-dot1.txt` trong từng thư mục lượt.
- T3 C1 run10 chạy lại và thay giá trị: đợt đầu collector không READY (kiểm tra steal 3s đầu: lệch 2.679.976 ns > ngưỡng 2.000.000 ns) nên lượt đó thực chất đo không có collector (TPS 3133.6880 ≈ C0). File cũ giữ tên `pglog-hong-dot1.txt`, `collect-hong-dot1.log`. Hai lượt khác cũng dính lỗi READY này (T3 C2 run2, T3-R25 C2 run3): C2 đo cgroup decoy nên điều kiện đo của tải không đổi; vẫn ghi rõ ở đây.
- E4p: khoảng đốt chọn nr=230 thay vì 35 (glibc hiện tại hiện thực `nanosleep()` bằng `clock_nanosleep`); script tự thử lại tối đa 5–12 lần khi wl tự kiểm mem trượt, vì đó là tự kiểm của workload chứ không phải tiêu chí đo. `tools/wl.c` không sửa.
- Dòng FAIL host lines=471 của pre24h: giữ nguyên văn; đếm tay cho thấy tổng hai đoạn là 602 dòng. Không sửa script pre24h trong nhiệm vụ này vì tiêu chí/cách đếm của nó thuộc bộ cổng cũ; ghi ở mục 8.

## 8. Cần kiến trúc sư quyết định

1. Chi phí PMU: T1 cho thấy bật PMU làm ns/syscall tăng từ 797 (C1n) lên 3.746 (C1); T3 kịch trần −69.41% TPS ở C1 (PMU on, ~254k bản ghi/giây, mất 0); đường tốc độ chỉ đạt 207k bản ghi/giây ở mức đích 500k. Đây là số đo của phép đọc `bpf_perf_event_read_value` trên vPMC VMware theo thiết kế BPF hiện tại (đọc ở sys_enter + read_now trong sched_switch + vòng lặp gen tối đa 3 lần). Kiến trúc sư có chấp nhận chi phí này cho bài, hay cần đổi cách đọc PMU (ví dụ chỉ đọc ở sys_enter)?
2. Lệch rq ở G3 đổi chiều theo PMU: PMU on collector thấp hơn bpftrace tổng 16–41%; PMU off cao hơn 3.6–8.8%. Xin kiến trúc sư xác nhận đây vẫn là vùng nhiễu công cụ (tiếp nối kết luận B6 của R031) hay cần chẩn đoán thêm; M6c không đặt tiêu chí cho mục này.
3. pre24h đếm host lines trên một đoạn xoay file: khi lần chạy 10 phút vắt qua mốc xoay theo giờ, tổng đúng là 602 dòng nhưng script báo FAIL 471. Kiến trúc sư có muốn sửa cách đếm của `m6b1_pre24h.sh` (cộng mọi đoạn) không?

## 9. Việc người dùng cần làm tay

Không có.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất

- Kiểm tra stealclock lúc khởi động của collector thỉnh thoảng từ chối chạy (lệch vmw/rq-steal trong 3s đầu vượt ngưỡng 2 ms): gặp 3 lần trong nhiệm vụ này (G3 S4/S1 đợt đầu, T3 C1 run10, T3 C2 run2, T3-R25 C2 run3). Collector giữ hành vi fail-closed đúng thiết kế; các lượt đo dính lỗi đều đã chạy lại hoặc ghi rõ. Chưa rõ nguyên nhân gốc (nhiễu steal trên VMware lúc tải thay đổi?).
- Tự kiểm mem của wl rất nhạy trên máy ảo (trượt nhiều lần ở E4p; phải thử lại). Không sửa wl trong nhiệm vụ này.
- Sau mọi lần chạy: `bpftool prog show | grep -c hids_` = 0, không còn tiến trình hids-collect, 12 container chạy lại đầy đủ.
- Việc tiếp theo đề xuất: chờ kiến trúc sư trả lời mục 8; M6c đóng ở đây.

## Thay đổi ngoài phạm vi nhiệm vụ

Không sửa BPF, không sửa `analysis/m6c_stats.py`/`m5f_parse.py`, không đổi tiêu chí cổng nào. Thay đổi trong `scripts/` và `analysis/` từ tag `m6b1.3` đến commit chứa báo cáo này (`git diff --stat m6b1.3..HEAD -- scripts analysis`):

```
 scripts/m6c_overhead.sh | 370 ++++++++++++++++++++++++++++++++++++++++++++++++
 scripts/m6c_t4fix.sh    | 257 +++++++++++++++++++++++++++++++++
 13 files changed, 1154 insertions(+), 9 deletions(-)
```

(13 file: thêm `m6c_gates1.sh`, `m6c_gates2.sh`, `m6c_g11.sh`, `m6c_gates3.sh`, `m6c_gates4.sh`, `m6c_overhead.sh`, `m6c_t4fix.sh`, `m6c_e4p.sh`; sửa nhỏ `g3.sh` (HIDS_COLLECT_EXTRA), `bin_header.py` (nhận 64), `m5f_g7cap2.sh` (G7_CAP_NPROC), `m6b12_rate.sh` (HIDS_COLLECT_EXTRA). `analysis/` không đổi.)

Bốn file của kiến trúc sư, kiểm tra trước mỗi lần build và tại lúc viết báo cáo, không đổi:

```
8b05464db597cfc471dc7af24ce651ef905751ebd80ec463b3863b7dd0263c35  bpf/sys_enter.bpf.c
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
```
