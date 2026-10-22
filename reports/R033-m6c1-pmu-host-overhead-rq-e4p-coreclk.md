# R033 — M6c-1: chế độ PMU production (`-pmu host`), bộ overhead cuối, chẩn đoán lệch rq theo thứ tự probe, E4p đúng giao thức, kiểm bộ đếm cycles của vPMC

1. **Số báo cáo:** R033. **Ngày giờ:** 2026-10-22 09:50 (+07). **Mốc:** M6c-1. **Git commit:** `eea0258` (trước commit báo cáo này); tag `m6c.1` gắn ở bước kết thúc.
2. **Mục tiêu:** (1) thêm chế độ PMU production `-pmu host` (mặc định) để phép đo overhead cuối đúng cấu hình production; (2) chạy lại bộ overhead cuối ở `-pmu host`; (3) chẩn đoán lệch rq G3 theo thứ tự gắn probe (trả lời câu hỏi 2 của R032); (4) E4p đúng giao thức E4 và kiểm bộ đếm cycles của vPMC bằng `tools/coreclk.c`. Thứ tự thực hiện: 1 → 2 → 3 → 5 → 4 → 6 (phần 4 chạy đêm qua `systemd-run`, xong 2026-10-21 23:34).

## 3. Đã làm gì

### Phần 1 — phía Go và script (mỗi mục một commit)

- **1a** (commit `d2db255`): cờ `-pmu` nhận `off | host | on`, mặc định `host`, `auto` là bí danh của `host`. `host`: mở 2 fd perf trên mỗi CPU online như `on` nhưng không nạp fd vào map, `hids_pmu_on=0` (BPF không đọc PMU); luồng host 1 Hz vẫn ghi `pmu_inst_delta`, `pmu_cyc_delta` từ các fd; lỗi mở fd ở bất kỳ CPU nào → in cảnh báo, hạ về `off`, không từ chối chạy. `on`: như cũ (lỗi mở fd → từ chối chạy). Header `.bin`: `pmu: off|host|on`; `pmu_events: instructions:u,cycles:u` khi host/on. `.cursor/rules/hids.mdc` đã ghi `host` là mặc định production, `on` chỉ cho thí nghiệm, kèm chi phí R032 (~1,47 µs mỗi lần đọc).
- **1b** (commit `e726af5`, sửa thêm `b644912`): kiểm tra stealclock thử lại tối đa 3 cửa sổ 3 s liên tiếp; mỗi lần in một dòng `STEALCHECK lan=<k> lech_ns=<...> nguong_ns=<...> ket_qua=DAT|LECH`; `READY` chỉ in khi đạt. Ngưỡng max(2 ms, 1%) không đổi. Chú thích mã ghi lý do của kiến trúc sư (mỗi tick chỉ đuổi kịp một tick; CPU idle NOHZ không tick).
- **1c** (commit `76835b2`): `scripts/m6b1_pre24h.sh` đếm host lines bằng tổng mọi đoạn `host-*.tsv.zst` của lần chạy, không chỉ đoạn cuối. Tiêu chí 580–620 không đổi.
- **1d** (commit `9d2ecc5`): ba bản sao mới, không sửa bản gốc: `scripts/m6c1_overhead.sh`, `scripts/m6c1_e4p.sh`, `scripts/g3_swap.sh`. Cả ba: chờ dòng READY tối đa 20 s trước khi chạy tải; không thấy → ghi `KHONG_READY` vào log lượt và tự chạy lại lượt đó (tối đa 2 lần); sau mỗi lượt C1 kiểm bản ghi/giây > 0. Bản diff đầy đủ: `validation/m6c1-20261021/diff-g3-swap.txt` (102 dòng), `diff-overhead.txt` (426 dòng), `diff-e4p.txt` (53 dòng); riêng diff của `g3_swap.sh` so với `g3.sh` in ở mục 4.3.

Sau 1a–1d: `make build` thành công (kiểm sha256 5 file kiến trúc sư trước build, xem mục 9).

### Phần 2 — cổng nhanh với binary mới (container dừng)

G7a ba lần truyền tường minh và một lần không truyền `-pmu` (kiểm mặc định). Nguyên văn dòng chính của mỗi lần và header:

```
=== G7a -pmu host ===
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
=== G7a -pmu on ===
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
=== G7a -pmu off ===
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
=== G7a mac dinh (khong truyen -pmu) ===
ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0

out/g7a-20261021-185929.bin
# pmu: host
# pmu_events: instructions:u,cycles:u
out/g7a-20261021-185939.bin
# pmu: on
# pmu_events: instructions:u,cycles:u
out/g7a-20261021-185953.bin
# pmu: off
# pmu_events: khong co (pmu off)
out/g7a-20261021-190002.bin
# pmu: host
# pmu_events: instructions:u,cycles:u
```

G3 S1–S5 một lần, không truyền `-pmu` (mặc định host). Nguyên văn:

```
S1-ketqua.txt: g5_max_ns=0
S2-ketqua.txt: g5_max_ns=499
S3-ketqua.txt: g5_max_ns=499
S4-ketqua.txt: g5_max_ns=0
S5-ketqua.txt: g5_max_ns=500
so khoang CLAMPED va |phan du| > 500 ns: 0 / tong (moi kich ban; tong 300, 1000, 1000, 300, 1502)
recursion_misses (bpf_prog_info), tong 0 tren 31 chuong trinh
--- S2: LECH_RQ_TONG_S2: collector=14295192 bpftrace_tong=12929757 lech=10.56% (tieu chi: <=5%)
--- S3: LECH_RQ_TONG_S3: collector=11676919 bpftrace_tong=15849987 lech=26.33% (tieu chi: <=5%)
--- S5: LECH_RQ_TONG_S5: collector=6756692 bpftrace_tong=6277029 lech=7.64% (tieu chi: <=5%)
```

(Lệch rq này là đối tượng chẩn đoán của phần 3, không phải tiêu chí phần 2.)

Luồng host: chạy `-datadir` 70 s, lọc cgroup của một container thử tạm (`hids-hostcheck`), thư mục `validation/m6c1-20261021/part2/hostcheck/`. Hai cột cuối của 3 dòng cuối: chế độ host là số, chế độ off là `na`. Nguyên văn ở file `validation/m6c1-20261021/part2/hostcheck.txt`; hai dòng mẫu:

```
31410273977669	...	229349912	238253259        (host: hai cot cuoi la so)
31484063166419	...	na	na                      (off: hai cot cuoi la "na")
```

Đếm STEALCHECK trong mọi log khởi động collector của nhiệm vụ (file `*.log`/`*.txt` dưới `validation/m6c1-20261021/`): tổng 162 lần có dòng `STEALCHECK lan=1`; trong đó 15 lần phải sang `lan=2`, 2 lần sang `lan=3`; **từ chối hẳn: 1 lần** (lượt E4p L12 đầu tiên, nguyên văn ở mục 5a). Số này không phải tiêu chí.

### Phần 3 — chẩn đoán lệch rq theo thứ tự gắn probe

**3a.** Từ `gates2b` đã có của M6c (`g3-on1`, `g3-on2`, `g3-on3`, `g3-off1`), kịch bản S4 (chỉ có collector đối chiếu schedstat; bpftrace của g3.sh chỉ gắn cho S2/S3/S5 nên không có dòng `@rq_sau_preempt_ns` cho S4 trong các lần này). Nguyên văn (collector so với `Delta schedstat field2 run_delay`):

```
== g3-on1 S4
rq                   2962728118      2962571669      Delta schedstat field2 run_delay
== g3-on2 S4
rq                   2997681649      2997577502      Delta schedstat field2 run_delay
== g3-on3 S4
rq                   2773656363      2773545406      Delta schedstat field2 run_delay
== g3-off1 S4
rq                   2840554434      2840466461      Delta schedstat field2 run_delay
```

Cạnh đó, số S2/S3/S5 đã có trong R032: PMU on — collector thấp hơn tổng bpftrace: S2 17,43/20,10/20,92%; S3 24,24/18,11/22,42%; S5 40,21/16,21/40,82% (ba lần on); PMU off — collector cao hơn: S2 3,61%, S3 8,76%, S5 7,50% (một lần off). File đầy đủ: `validation/m6c1-20261021/part3a-rq-tong.txt`.

**3b.** `scripts/g3_swap.sh` là bản sao của `g3.sh`, chỉ khác: bpftrace khởi động và `wait_bpftrace_attach` xong trước khi khởi động collector (wl vẫn khởi động trước cả hai); thêm biến môi trường `G3_ONLY` để chọn kịch bản. Diff đầy đủ 102 dòng ở `validation/m6c1-20261021/diff-g3-swap.txt`.

**3c.** Bốn lần chạy S2 + S5 (giữ `.bin`), mỗi lần in dòng rq như g3.sh vẫn in. Nguyên văn rút gọn (collector `rq`, bpftrace `@rq_sau_wakeup_ns` = `@rq_tong_ns`, `@so_lan`):

```
== norm-on S2    rq 27097183   bpftrace 36303066   so_lan 500
== norm-on S5    rq 16497067   bpftrace 20669672   so_lan 606
== norm-off S2   rq 28372427   bpftrace 27615196   so_lan 500
== norm-off S5   rq 15721162   bpftrace 16727147   so_lan 603
== swap-on S2    rq 30357561   bpftrace 30830795   so_lan 502
== swap-on S5    rq 16286249   bpftrace 16711991   so_lan 602
== swap-off S2   rq 28773267   bpftrace 28731122   so_lan 502
== swap-off S5   rq 14713594   bpftrace 15070072   so_lan 607
```

Nguyên văn đầy đủ (gồm cả cột đối chiếu schedstat): `validation/m6c1-20261021/part3/rq-lines-4runs.txt`.

**3d.** Ghép theo mốc thời gian đúng script đã dùng ở R031 (cặp (W,S) của bpftrace → khoảng collector chứa S; chỉ lấy khoảng chứa đúng một cặp wakeup, không preempt). Hiệu = rq_bpftrace − rq_collector, đơn vị µs. Nguyên văn bảng tổng hợp (dòng cuối mỗi mục trong `pair3d.txt` / `pair3d-swap.txt`):

```
norm-on  S2	n=500	median_us=7.769	p10_us=5.330	p90_us=10.659	lech_tong_pct=+34.08
norm-on  S5	n=3	median_us=7.418	p10_us=4.558	p90_us=10.821	lech_tong_pct=+25.55
norm-off S2	n=500	median_us=-1.403	p10_us=-1.955	p90_us=-0.877	lech_tong_pct=-2.65
norm-off S5	n=5	median_us=-0.148	p10_us=-0.280	p90_us=1395.311	lech_tong_pct=+1958.15
swap-on  S2	n=501	median_us=0.451	p10_us=-0.429	p90_us=1.254	lech_tong_pct=+1.20
swap-on  S5	n=1	median_us=-0.041	p10_us=-0.041	p90_us=-0.041	lech_tong_pct=-0.13
swap-off S2	n=501	median_us=0.382	p10_us=-0.561	p90_us=1.059	lech_tong_pct=-0.32
swap-off S5	n=6	median_us=0.163	p10_us=-0.141	p90_us=0.222	lech_tong_pct=+1.98
```

Ghi chú nguyên văn từ output ghép: ở S5 hầu hết khoảng chứa nhiều hơn một cặp wakeup (`khoang trong cua so co >1 cap: 299–300`), nên số cặp lọc được rất nhỏ (n=1–6); tỉ lệ `lech_tong_pct=+1958.15` của norm-off S5 đến từ một khoảng có `d = -1395311 ns` trong 5 khoảng (xem `pair3d.txt`). S4 không có dòng sự kiện W/S của bpftrace (bpftrace chỉ gắn ở S2/S3/S5) nên script ghép không áp được cho S4; số S4 ở 3a là đối chiếu tổng với schedstat.

**3e.** Kỳ vọng của kiến trúc sư (không phải tiêu chí) đã ghi trong nhiệm vụ: thứ tự thường + `-pmu on` hiệu ≈ +2…+3 µs gần như hằng; `-pmu off` hiệu ≈ ±0,3–0,7 µs; thứ tự đảo thì on và off gần bằng nhau. Output thật: thứ tự thường + on, trung vị S2 = **+7,769 µs** (lớn hơn khoảng kỳ vọng +2…+3 µs); thứ tự thường + off, trung vị S2 = **−1,403 µs**; thứ tự đảo: on **+0,451 µs**, off **+0,382 µs** (S2). Báo cáo chỉ in số, không kết luận.

### Phần 5 — E4p đúng giao thức + kiểm bộ đếm cycles

**5a.** Thứ tự khởi động của E4 GỐC (`scripts/m4.sh`): hiệu chuẩn là bước riêng `calibrate` (dòng 487 gọi `calibrate_wl`, `calibrate_mem`) chạy khi máy rảnh; lúc chạy `e4_workers()` (dòng 308) thì stress-ng khởi động trước (dòng 315), `sleep 2` (dòng 318), rồi mới chạy wl bằng `run_wl_mem "$loops" 500` (dòng 319) với `mem_steps` đọc từ file hiệu chuẩn (không hiệu chuẩn lại trong lượt chạy).

`scripts/m6c1_e4p.sh` làm **khác** E4 gốc ở điểm này, theo giao thức kiến trúc sư ghi trong nhiệm vụ và bổ sung của người dùng (không dừng): wl khởi động, hiệu chuẩn và tự kiểm mem khi máy rảnh (stress-ng chưa chạy) → stress-ng khởi động → chờ ổn định 10 s → gửi go. Collector gắn `-pmu on` sau khi wl đã khởi động, trước khi stress-ng chạy.

Kết quả 9 ô (L = 0, 12, 22; 3 lần mỗi mức; khoảng đốt = bản ghi nr=230, không FIRST, có PMU đủ 500/500 mỗi ô). GHz dưới đây là trung vị của `cyc/cpu_ns` tính trên từng bản ghi, đúng như script in (`trung vi cyc/cpu_ns (GHz hieu dung)`):

```
L=0 run1: trung vi cpu_ns = 10667842.0 | inst = 10204316.0 | cyc = 19565740.0 | CPI = 1.9174 | GHz = 1.9564
L=0 run2: trung vi cpu_ns = 10920924.0 | inst = 10501900.0 | cyc = 20176669.0 | CPI = 1.9212 | GHz = 1.9517
L=0 run3: trung vi cpu_ns = 11239201.5 | inst = 10793857.0 | cyc = 20976705.5 | CPI = 1.9434 | GHz = 1.9581
L=12 run1: trung vi cpu_ns = 27337042.5 | inst = 14170561.0 | cyc = 52136140.5 | CPI = 3.6792 | GHz = 1.9587
L=12 run2: trung vi cpu_ns = 27327741.0 | inst = 13996429.0 | cyc = 52282946.5 | CPI = 3.7354 | GHz = 1.9582
L=12 run3: trung vi cpu_ns = 26434419.5 | inst = 13612268.0 | cyc = 50532976.5 | CPI = 3.7123 | GHz = 1.9597
L=22 run1: trung vi cpu_ns = 50404620.5 | inst = 17100534.0 | cyc = 101664084.5 | CPI = 5.9451 | GHz = 1.9789
L=22 run2: trung vi cpu_ns = 43979931.5 | inst = 14653580.0 | cyc = 88642333.0 | CPI = 6.0492 | GHz = 1.9746
L=22 run3: trung vi cpu_ns = 50584219.5 | inst = 16934663.0 | cyc = 108432942.0 | CPI = 6.4030 | GHz = 1.9778
```

Kỳ vọng của kiến trúc sư (không phải tiêu chí): inst gần như không đổi theo L; cpu_ns tăng theo L; CPI tăng. Output thật: cpu_ns và CPI tăng theo L; **inst cũng tăng theo L** (trung vị khoảng 10,2–10,8 triệu ở L=0; 13,6–14,2 triệu ở L=12; 14,7–17,1 triệu ở L=22). Báo cáo chỉ in số, không kết luận.

Sự cố trong lúc chạy 5a (ghi nguyên văn, không che): job đầu (`hids-m6c1e4p`) chết ở L12 lượt 1 attempt 6 vì collector không READY — log collector của attempt đó (đã bị attempt sau ghi đè, nội dung đọc được khi sự cố xảy ra):

```
STEALCHECK lan=3 lech_ns=5576695 nguong_ns=2000000 ket_qua=LECH
doi chieu xong: lech lon nhat 5576695 ns tren 24 CPU, nguong max(2000000 ns, 1%)
hids-collect: vmw_steal_time lech qua nguong so voi rq->prev_steal_time trong 3s dau:
   cpu         vmw_ns    rq_steal_ns      lech_ns    nguong_ns
     0       19474299       13897604      5576695      2000000
Chay lai voi -steal-fallback de dung rq->prev_steal_time
```

Sau đó đã sửa bản sao `m6c1_e4p.sh` (commit `M6c-1 5a-fix`: `wait_ready` trả 1 thay vì `exit 1`, attempt hỏng được thử lại như các attempt khác) và chạy lại các ô còn thiếu; ô L12/run1 phải chạy ở job thứ ba mới đủ 500 khoảng. Tổng số attempt đã dùng ghi trong `out/jobs/m6c1e4p*.log`.

**5b.** coreclk (không collector). Đã kiểm sha256 `tools/coreclk.c` = `88ef821e…` trước khi dùng (xem mục 7), build `gcc -O2 -o bin/coreclk tools/coreclk.c` (đã thêm vào Makefile, commit `54a5a28`). Chạy L=0 và L=22 (stress-ng stream 22 worker như E4), ghim CPU 20, 3 lần mỗi mức: `perf stat -e cycles:u,instructions:u taskset -c 20 bin/coreclk 100000000`, kèm `grep '^cpu ' /proc/stat` trước và sau mỗi lần. Nguyên văn đầy đủ: `validation/m6c1-20261021/coreclk/coreclk.log`. Bảng tỉ số tính thêm (cycles_u lấy từ perf stat; chu_ky_ky_vong, thoi_gian_ns, GHz_wall lấy từ dòng coreclk in; GHz_pmu = cycles_u / thoi_gian_ns; steal là hiệu cột 8 của dòng `cpu ` trong /proc/stat, đơn vị jiffies):

```
L=0 lan=1 cycles_u=2494480873 ky_vong=2400000000 ti_so=1.0394 GHz_pmu=2.0062 GHz_wall=1.9302 steal_jiffies_delta=6
L=0 lan=2 cycles_u=2494360503 ky_vong=2400000000 ti_so=1.0393 GHz_pmu=1.9977 GHz_wall=1.9221 steal_jiffies_delta=5
L=0 lan=3 cycles_u=2493921977 ky_vong=2400000000 ti_so=1.0391 GHz_pmu=2.0084 GHz_wall=1.9328 steal_jiffies_delta=7
L=22 lan=1 cycles_u=2495184684 ky_vong=2400000000 ti_so=1.0397 GHz_pmu=1.9632 GHz_wall=1.8883 steal_jiffies_delta=3
L=22 lan=2 cycles_u=2498350036 ky_vong=2400000000 ti_so=1.0410 GHz_pmu=1.9967 GHz_wall=1.9181 steal_jiffies_delta=4
L=22 lan=3 cycles_u=2498225069 ky_vong=2400000000 ti_so=1.0409 GHz_pmu=2.0037 GHz_wall=1.9250 steal_jiffies_delta=2
```

Dòng nguyên văn của một lần chạy (L=0 lần 1):

```
so_imul=800000000 chu_ky_ky_vong=2400000000 thoi_gian_ns=1243398780 GHz_wall=1.9302 kiem=5236358074778120193
     2,494,480,873      cycles:u
     1,324,291,645      instructions:u                   #    0.53  insn per cycle
```

Không tiêu chí; kiến trúc sư đọc.

### Phần 4 — bộ overhead cuối, cấu hình production (`-pmu host`)

Điều kiện: C0 = không collector; C1 = bị đo, `-pmu host` truyền tường minh; C2 = cgroup decoy, `-pmu host`. Mọi cờ khác mặc định. Mỗi ô 10 lượt xen kẽ C0→C1→C2. Container dừng trong lúc đo, khởi động lại sau (kể cả khi lỗi). Unit `hids-m6c1p4`, chạy 2026-10-21 19:19 → 23:34, `overhead_exit=0`. Thư mục dữ liệu: `validation/m6c1-20261021/part4/`.

Lệnh T4 kịch trần dùng trong đợt này (trong `scripts/m6c1_overhead.sh`), đặt cạnh lệnh M5f trong `scripts/m5f_resume.sh` dòng 150:

```
M5f (m5f_resume.sh:150): taskset -c 16-19 wrk -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin"
Do nay (m6c1_overhead.sh): taskset -c 16-19 wrk -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk.txt" 2>&1
```

Hai lệnh giống hệt nhau (chỉ khác nơi ghi output). `wrk` gốc tại `/usr/bin/wrk`. Tải cố định T4-R25/R50 dùng `wrk2 -R` như `scripts/m5f.sh` dòng 310. Cách lấy Requests/sec: xem mục 7.

Tham số pgtest/pgbench: đợt này dùng đúng cách của M5h — container `docker run -d --name pgtest --cpuset-cpus 12-15 -e POSTGRES_PASSWORD=m5test postgres:16-alpine -c checkpoint_timeout=30min -c max_wal_size=8GB -c autovacuum=off`; `pgbench -i -s 50`; trước mỗi lượt `VACUUM;` rồi `CHECKPOINT;`; pgbench `-c 16 -j 4 -T 60 -l --log-prefix=/tmp/pglog` (tải cố định thêm `-R <mức>`). Đây là điểm khác so với script overhead của M6c (R032), và nhiệm vụ yêu cầu ghi nhận: C0 kịch trần T3 của R032 là 3108 TPS, của m5h khoảng 4902 TPS; đợt này C0 = 2962,71 TPS (bảng dưới).

Mỗi chỉ số một file TSV `load cond run value`, chạy `python3 analysis/m6c_stats.py <file>` (không sửa script). Nguyên văn mọi output (rút gọn phần tiêu đề lặp; file đầy đủ trong `validation/m6c1-20261021/part4/overhead/*.stats.txt`):

```
T1 (ns/syscall):            C0 mean=185.6520 | C1 mean=791.9520 (+326.5788%) | C2 mean=249.9230 (+34.6191%)
T3 kich tran (TPS):         C0 mean=2962.7106 | C1 mean=2293.3548 (-22.5927%) | C2 mean=2843.1081 (-4.0369%)
T4 kich tran (req/s):       C0 mean=68258.0090 | C1 mean=59341.7460 (-13.0626%) | C2 mean=66244.6110 (-2.9497%)
T3-R25 lat_avg (ms):        C0 2.6437 | C1 2.9205 (+10.4714%) | C2 2.7155 (+2.7155%)
T3-R25 p50:                 C0 2.4514 | C1 2.6587 (+8.4564%) | C2 2.5061 (+2.2314%)
T3-R25 p99:                 C0 5.5869 | C1 6.6274 (+18.6239%) | C2 5.8005 (+3.8232%)
T3-R25 CPU cgroup (us/60s): C0 87057922.6 | C1 93978039.6 (+7.9489%) | C2 88566566.7 (+1.7329%)
T3-R50 lat_avg:             C0 3.0002 | C1 4.2688 (+42.2848%) | C2 3.1365 (+4.5434%)
T3-R50 p50:                 C0 2.6536 | C1 3.5114 (+32.3259%) | C2 2.7694 (+4.3639%)
T3-R50 p99:                 C0 7.8100 | C1 15.3731 (+96.8387%) | C2 8.1835 (+4.7823%)
T3-R50 CPU cgroup (us/60s): C0 142951623.3 | C1 161764179.9 (+13.1601%) | C2 146283524.7 (+2.3308%)
T4-R25 lat_avg:             C0 1.2790 | C1 1.2920 (+1.0164%) | C2 1.2880 (+0.7037%)
T4-R25 p50:                 C0 1.2260 | C1 1.2300 (+0.3263%) | C2 1.2290 (+0.2447%)
T4-R25 p99:                 C0 2.6430 | C1 2.7100 (+2.5350%) | C2 2.6790 (+1.3621%)
T4-R25 CPU cgroup (us/60s): C0 73392689.6 | C1 80274854.5 (+9.3772%) | C2 75090675.7 (+2.3136%)
T4-R50 lat_avg:             C0 1.3940 | C1 1.4710 (+5.5237%) | C2 1.4080 (+1.0043%)
T4-R50 p50:                 C0 1.2890 | C1 1.3290 (+3.1032%) | C2 1.2990 (+0.7758%)
T4-R50 p99:                 C0 3.2810 | C1 4.0670 (+23.9561%) | C2 3.3030 (+0.6705%)
T4-R50 CPU cgroup (us/60s): C0 115729479.2 | C1 128948281.2 (+11.4222%) | C2 118939004.5 (+2.7733%)
```

(n = 10 mỗi ô; sd, ci95, p_perm nguyên văn trong các file `.stats.txt` đã dẫn.)

Mức tải cố định = 25%/50% của trung vị C0 kịch trần đo trong đợt này.

Mỗi lượt C1: bản ghi/giây và số mất lấy từ collect-stats; trong log `overhead.log` có 70 dòng `mat=0` và không có dòng `mat=` khác 0; có 4 dòng `KHONG_READY` (lượt được tự chạy lại theo quy tắc 1d, số cuối cùng giữ nguyên từ lượt chạy lại). Không lượt nào bị loại.

iostat trong 1 lượt T3 C0 (thiết bị chứa dữ liệu pgtest: `/dev/mapper/ubuntu--vg-ubuntu--lv`, qua `docker inspect pgtest` → mount → `df` → `lsblk`): trung bình trên 540 mẫu (mọi thiết bị trong output `iostat -x 1 60` cộng dồn theo file `validation/m6c1-20261021/part4/overhead/T3/C0/run1/iostat.txt`): %util trung bình = 11,53; w_await trung bình = 2,723 ms. Không tiêu chí.

Đường CPU collector theo tốc độ (`-pmu host`, 2 phút mỗi mức; đạt được / CPU % một lõi; kernel drops = 0 ở mọi mức theo status):

```
muc 1000:   TONG_BAN_GHI=189204    toc_do_dat_duoc=1577 ban_ghi/giay    cpu_%_mot_loi=1.71%
muc 10000:  TONG_BAN_GHI=1249608   toc_do_dat_duoc=10413 ban_ghi/giay   cpu_%_mot_loi=4.02%
muc 100000: TONG_BAN_GHI=11868966  toc_do_dat_duoc=98908 ban_ghi/giay   cpu_%_mot_loi=20.99%
muc 500000: TONG_BAN_GHI=59058065  toc_do_dat_duoc=492151 ban_ghi/giay  cpu_%_mot_loi=116.08%
```

G7-cap (zstd mặc định, `-pmu host` qua mặc định, 60 s mỗi mức; nguyên văn từ `part4.log`):

```
=== G7-cap2 nproc=1 zstd-default duration=60s ===
recs=57203693 mat=0
g7cap nproc=1 exit=0
=== G7-cap2 nproc=2 zstd-default duration=60s ===
recs=53262308 mat=64071301
g7cap nproc=2 exit=1
=== G7-cap2 nproc=4 zstd-default duration=60s ===
recs=52486414 mat=204385788
g7cap nproc=4 exit=1
```

Tức bản ghi đọc được/giây: nproc=1: 953395/s, mất 0; nproc=2: 887705/s, mất 64071301; nproc=4: 874774/s, mất 204385788. Header của hai file p2/p4 đều là `# pmu: host` (file `part4/g7cap-pmu-headers.txt`). `exit=1` là mã thoát của script phụ `m5f_g7cap2.sh` khi số mất > 0; số liệu giữ nguyên, không loại lượt.

Không chạy lại ô T1 `-pmu on`/`off` theo nhiệm vụ: số R032 giữ cho câu chi phí PMU (C1 3745,7 / C1n 797,3 ns/syscall). Đặt cạnh: T1 C1 `-pmu host` đợt này = 791,9520 ns/syscall.

## 4. Lệnh build, lệnh chạy (để chạy lại được)

- Build: `make build` (đã chạy sau phần 1 và sau mỗi sửa; lần cuối trước phần 4/5).
- Phần 2: `bash scripts/m6c1_part2.sh validation/m6c1-20261021/part2`
- Phần 3: `bash scripts/m6c1_part3.sh ...`, `bash scripts/m6c1_part3swap.sh ...` (trong repo), ghép: `python3 scripts/m6c1_pair_table.py ...`
- Phần 5a: `M6C_E4P_ATTEMPTS=15 M6C_E4P_CELLS="0:3 12:1 12:2 12:3 22:1 22:2 22:3" bash scripts/m6c1_e4p.sh validation/m6c1-20261021/e4p`
- Phần 5b: `bash scripts/m6c1_coreclk.sh` (kiểm sha256 trong script).
- Phần 4: unit `hids-m6c1p4` chạy `bash scripts/m6c1_part4.sh validation/m6c1-20261021/part4` (bên trong gọi `m6c1_overhead.sh`, đường tốc độ, G7-cap).

## 5. Kết quả kiểm — output nguyên văn

Đã dán ở mục 3 theo từng phần. Các file output đầy đủ: `validation/m6c1-20261021/part2/`, `part3/`, `part3a-rq-tong.txt`, `part4/`, `coreclk/coreclk.log`, `e4p/L*/run*/ketqua.txt`, log job `out/jobs/m6c1p2.log`, `m6c1p4.log`, `m6c1e4p*.log`.

Cuối nhiệm vụ: `bpftool prog show | grep -c hids_` = 0; không còn tiến trình `hids-collect`; 12 container chạy lại đủ (danh sách `/root/containers-da-dung.txt`).

## 6. File dữ liệu đã tạo

- `validation/m6c1-20261021/part2/` (G7a ×4, G3 mặc định, hostcheck)
- `validation/m6c1-20261021/part3/` (4 lần g3/g3_swap + `pair3d.txt`, `pair3d-swap.txt`, `rq-lines-4runs.txt`), `part3a-rq-tong.txt`
- `validation/m6c1-20261021/e4p/` (9 ô E4p), `coreclk/coreclk.log`
- `validation/m6c1-20261021/part4/` (overhead, rate-*, g7cap)
- `validation/m6c1-20261021/diff-g3-swap.txt`, `diff-overhead.txt`, `diff-e4p.txt`
- Script mới: `scripts/m6c1_overhead.sh`, `scripts/m6c1_e4p.sh`, `scripts/g3_swap.sh`, `scripts/m6c1_part2.sh`, `scripts/m6c1_part3.sh`, `scripts/m6c1_part3swap.sh`, `scripts/m6c1_part4.sh`, `scripts/m6c1_coreclk.sh`, `scripts/m6c1_pair_table.py`; `tools/coreclk.c`, `bin/coreclk`.

## 7. Quyết định đã tự đưa ra và lý do

1. **coreclk:** lúc bắt đầu nhiệm vụ, file trong repo có sha256 `3d2c9005…`, khác giá trị kiến trúc sư ghi (`88ef821e…`) nên đã dừng dùng file. Người dùng sau đó đã thay bằng bản đúng của kiến trúc sư (bản không có ký tự tab; nội dung mã giống hệt bản `3d2c9005`), kiểm lại sha256 khớp `88ef821e…` trước phần 5 và commit với thông điệp `M6c-1: tools/coreclk.c ban kien truc su 88ef821e`. Vì file chưa từng được dùng trước khi thay, phần 5b được làm bình thường.
2. **T4 kịch trần — cách đọc Requests/sec:** script `m6c1_overhead.sh` được viết và phần 4 đã khởi động (19:19) trước khi bổ sung đề bài tới (19:31). Script lấy số bằng `grep -oE "Requests/sec:\s*[0-9.]+" wrk.txt` từ chính output của lệnh `wrk` gốc, thay vì `python3 analysis/m5f_parse.py wrk2 <file>` như bổ sung yêu cầu. Nguồn số là cùng một dòng `Requests/sec:` trong cùng file `wrk.txt`; các chỉ số độ trễ của tải cố định vẫn lấy qua `m5f_parse.py`. Ghi rõ tại đây để kiến trúc sư quyết có cần chạy lại T4 kịch trần chỉ vì cách đọc số hay không (câu 8.5).
3. **5a — sửa bản sao `m6c1_e4p.sh`:** `wait_ready` của bản sao dùng `exit 1` nên một lần collector không READY (STEALCHECK từ chối, xem mục 5a) giết cả job. Đã sửa bản sao (không sửa bản gốc): `wait_ready` trả 1 sau 20 s và in `KHONG_READY`, attempt đó được thử lại như các attempt trượt tự kiểm wl khác, đúng quy tắc 1d.
4. **G7-cap:** giữ nguyên mã thoát và số mất của script phụ; không chạy lại, không đổi tiêu chí.
5. **iostat:** `sysstat` đã có sẵn (`/usr/bin/iostat`) nên không cần cài; phép đo làm như nhiệm vụ ghi.

## Trả lời ba câu hỏi mục 8 của R032

- **8.1 (chấp nhận chi phí PMU theo bản ghi?):** đã làm chế độ `-pmu host` là mặc định production: BPF không đọc PMU theo bản ghi (bit7 = 0), chỉ luồng host đọc tổng mỗi giây từ fd per-CPU. Số production đo ở phần 4: T1 C1 `-pmu host` = 791,9520 ns/syscall, đặt cạnh số R032 của `-pmu on` (3745,7) và C1n không PMU (797,3). Chế độ `on` giữ cho thí nghiệm cần inst/cyc theo bản ghi (E4p).
- **8.2 (lệch rq G3 đổi chiều theo PMU):** đã chẩn đoán theo thứ tự gắn probe ở phần 3. Số liệu: thứ tự thường + on trung vị hiệu (bpftrace − collector) S2 = +7,769 µs; thứ tự thường + off = −1,403 µs; thứ tự đảo: on +0,451 µs, off +0,382 µs. Ghép theo mốc thời gian và dòng tổng ở mục 3c/3d. Báo cáo không tự kết luận; chờ kiến trúc sư đọc (câu 8.1).
- **8.3 (sửa cách đếm host lines của pre24h?):** đã sửa ở mục 1c: đếm bằng tổng mọi đoạn `host-*.tsv.zst` của lần chạy; tiêu chí không đổi.

## Thay đổi ngoài phạm vi nhiệm vụ

`git diff --stat m6c..HEAD -- scripts analysis internal cmd tools` (nguyên văn, rút gọn cột số ở các dòng script dài — toàn văn trong repo):

```
 cmd/hids-collect/longrun.go   |  14 +-
 cmd/hids-collect/main.go      |  56 ++++-
 internal/syscallbpf/loader.go |  34 ++-
 scripts/g3_swap.sh            | 535 ++++
 scripts/m6b1_pre24h.sh        |   8 +-
 scripts/m6c1_coreclk.sh       |  39 +++
 scripts/m6c1_e4p.sh           | 150 +++
 scripts/m6c1_overhead.sh      | 424 +++
 scripts/m6c1_pair_table.py    |  94 +++
 scripts/m6c1_part2.sh         |  59 +++
 scripts/m6c1_part3.sh         |  60 +++
 scripts/m6c1_part3swap.sh     |  51 +++
 scripts/m6c1_part4.sh         |  40 +++
 tools/coreclk.c               |  85 +++
 14 files changed, 1620 insertions(+), 29 deletions(-)
```

Ngoài các file trên: `.cursor/rules/hids.mdc` (ghi chế độ `host` mặc định, theo đúng mục 1a của nhiệm vụ), `docs/STATE.md`, `docs/tasks/M6c-1.md`, báo cáo này và `reports/INDEX.md`. Không sửa file kiến trúc sư nào; không sửa bản gốc `scripts/g3.sh`, `scripts/m6c_overhead.sh`, `scripts/m6c_e4p.sh`; không sửa BPF trong nhiệm vụ này.

sha256 của 5 file kiến trúc sư, kiểm trước mỗi lần build và lúc viết báo cáo:

```
8b05464db597cfc471dc7af24ce651ef905751ebd80ec463b3863b7dd0263c35  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
```

Cả 5 giá trị khớp với giá trị kiến trúc sư ghi trong nhiệm vụ (coreclk sau khi người dùng thay bản đúng, xem mục 7.1).

## 8. Cần kiến trúc sư quyết định

1. **Lệch rq theo thứ tự gắn (câu 8.2 của R032):** với số liệu phần 3 (thứ tự thường + on: trung vị +7,769 µs ở S2, lớn hơn khoảng kỳ vọng +2…+3 µs đã ghi trong nhiệm vụ; thứ tự đảo: on và off gần bằng nhau, +0,451/+0,382 µs), câu hỏi lệch rq có đóng được không, và có cần đo thêm cấu hình nào không?
2. **E4p — inst tăng theo L:** kỳ vọng là inst gần như không đổi theo L, nhưng với giao thức hiệu chuẩn khi máy rảnh, inst trung vị tăng từ ~10,2–10,8 triệu (L=0) lên ~13,6–14,2 triệu (L=12) và ~14,7–17,1 triệu (L=22), trong khi cpu_ns và CPI vẫn tăng theo L. Kiến trúc sư đọc và quyết có cần chẩn đoán thêm phía workload (`wl mem`) hay không.
3. **G7-cap ở `-pmu host`:** nproc=2 mất 64071301 bản ghi, nproc=4 mất 204385788 bản ghi trong 60 s (nproc=1 mất 0). So với R032 (đo ở cấu hình khác), kiến trúc sư quyết đây có phải giới hạn cần xử lý tiếp hay ghi nhận như giới hạn hiện tại.
4. **STEALCHECK từ chối hẳn 1 lần:** trong 162 lần khởi động có 15 lần phải thử cửa sổ 2, 2 lần cửa sổ 3, và 1 lần bị từ chối sau cả 3 cửa sổ (lệch 5576695 ns ở CPU 0, nguyên văn mục 5a). Kiến trúc sư quyết ngưỡng/cửa sổ hiện tại có giữ nguyên cho các đợt đo sau hay không.
5. **T4 kịch trần — cách đọc Requests/sec:** đợt này đọc bằng `grep` trên dòng `Requests/sec:` của `wrk.txt` thay vì `python3 analysis/m5f_parse.py wrk2 <file>` như bổ sung đề bài (lý do ở mục 7.2). Kiến trúc sư quyết có cần chạy lại riêng T4 kịch trần hay chấp nhận số đã đo.
6. **T3 kịch trần C0 vẫn thấp:** với đúng tham số pgtest/pgbench của M5h, C0 đợt này = 2962,71 TPS, vẫn thấp hơn số m5h (~4902 TPS) như R032 (3108 TPS); iostat trong lượt C0 cho %util trung bình 11,53, w_await 2,723 ms. Kiến trúc sư quyết có cần chẩn đoán riêng đường pgtest hay không.

## 9. Việc người dùng cần làm tay

Không có. Mọi job đã chạy xong, 12 container đã được khởi động lại, kernel sạch.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất

- Ô L12/run1 của E4p cần 3 job mới đủ (tự kiểm mem của `wl` trượt nhiều lần và 1 lần STEALCHECK từ chối); số liệu cuối cùng đủ 9/9 ô, không thiếu ô nào.
- G7-cap nproc=2/4 mất bản ghi (mục 8.3 chờ quyết).
- Đề xuất: chờ kiến trúc sư trả lời mục 8 rồi mở nhiệm vụ tiếp theo; không tự mở rộng phạm vi.
