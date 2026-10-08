# R026 — M5h: G3 + overhead BPF r2, tag `m5h`

1. **Số báo cáo:** R026  
   **Ngày giờ:** 2026-10-09 02:30 (UTC+7)  
   **Mốc:** M5h  
   **Git commit:** tag `m5h` (`0e34d87`)

2. **Mục tiêu**  
   Theo quyết định kiến trúc sư (sau R025): bỏ tiêu chí G7-cap `mat`=0; G7-cap ghi nhận throughput zstd mặc định (~1,2M rec/s, hai lượt); G3 S1–S5; bước 3–4 (`scripts/m5h.sh`); báo cáo overhead T1/T3/T4 kịch trần và tải cố định; tag `m5h`.

3. **Đã làm gì**  
   - Job `hids-m5h-g3`: `G3_OUTROOT=validation/m5h-20261009/g3 bash scripts/g3.sh m5d` — exit 0 (`out/jobs/m5h-g3.log`, `out/jobs/m5h-g3.status`).  
   - Kiểm G3: `recursion_misses` 0 (log collector trong `*-ketqua.txt`); G5 `max` phần dư ≤ 500 ns (0,5 µs) mọi S1–S5.  
   - Job `hids-m5h-bench`: `M5H_OUT=validation/m5h-20261009 bash scripts/m5h.sh` — exit 0 sau ~75 phút (`out/jobs/m5h-bench.log`, `out/jobs/m5h-bench.status`).  
   - Sửa lỗi vận hành bench (mục 7): `-sys-enter-hook` với `mapfile`, `scope_main_pid` dưới `set -e`, alias `hids_drop_collect_artifacts`, bỏ qua nhanh T1/T4 đã có kết quả.

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids && make build
   sudo systemd-run --unit=hids-m5h-g3 --collect bash -c \
     'cd /root/hids && G3_OUTROOT=validation/m5h-20261009/g3 bash scripts/g3.sh m5d > out/jobs/m5h-g3.log 2>&1; echo exit=$? > out/jobs/m5h-g3.status'
   sudo systemd-run --unit=hids-m5h-bench --collect bash -c \
     'cd /root/hids && M5_SKIP_GIT_CHECK=1 M5H_OUT=validation/m5h-20261009 bash scripts/m5h.sh; echo exit=$? > out/jobs/m5h-bench.status'
   git tag m5h
   ```

5. **Kết quả**

   **Quyết định kiến trúc sư (sau R025):** Không chặn M5h vì G7-cap `mat`≠0; ghi nhận throughput zstd ~1,2M rec/s (hai lượt stress 2×60 s).

   **Bước 2 — G7a tracepoint (`step2/g7a-tp.log`, tóm tắt):**  
   ```
   ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
   ```

   **G7a fentry (`step2/g7a-fentry.log`):**  
   ```
   ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
   ```

   **G7b `-zstd-level 0` (`step2/g7b-zstd0.log`):**  
   ```
   ban ghi doc duoc: 24000024 | so lan dinh ghi: 24000024 | mat: 0
   ```

   **G7b-nho `-zstd-level 0` (`step2/g7b-nho-zstd0.log`):**  
   ```
   ban ghi doc duoc: 20697818 | so lan dinh ghi: 24000024 | mat: 3302206
   ```

   **G7-cap zstd mặc định (không yêu cầu `mat`=0):**  
   ```
   Lượt 1: ban ghi doc duoc: 72618011 | mat: 8458392 | thoi gian chay: 61.362 s → ~1183436 rec/s
   Lượt 2: ban ghi doc duoc: 69091435 | mat: 7473323 | thoi gian chay: 61.460 s → ~1124169 rec/s
   Trung bình hai lượt: ~1153803 rec/s (~1,15×10^6; kiến trúc sư làm tròn ~1,2M rec/s)
   ```
   Log: `validation/m5h-20261009/step2/g7-cap/zstd-default-p2-20261009-003827-collect.log`, `…003938-collect.log`.

   **G3 S1–S5 — G5 phần dư |tất cả (trừ FIRST)| `max` (ns):**  
   ```
   S1 max=0  S2 max=500  S3 max=500  S4 max=0  S5 max=497
   ```
   Thư mục: `validation/m5h-20261009/g3/`.

   **T4 kịch trần — mất bản ghi (sat):** không có file `t4_sat_loss.txt` (mọi lượt C1/C2 `mat=0` trong log collector đã xử lý).

   **Bảng T1 — ns/syscall (mean ± sd, n=5; M5h vs % so với C0 cùng mốc):**  
   ```
   cond              M5h mean±sd (ns)     % vs C0 (M5h)
   C0                141.84 ± 0.03        —
   C1-tracepoint     411.81 ± 11.58       +190.33%
   C1-fentry         403.73 ± 8.45        +184.63%
   C2-tracepoint     182.33 ± 0.06        +28.54%
   C2-fentry         182.33 ± 0.07        +28.54%
   ```
   (R021/M5f không có cùng ma trận T1 5 điều kiện; so sánh chéo m5f chỉ áp dụng T3/T4 sat bên dưới.)

   **Bảng T3 kịch trần — TPS từ `m5f_parse_sat.tsv` (n=3):**  
   ```
   cond    M5h mean±sd        R021 C0 ref (~4965)    M5h % vs C0    R021 C1 % vs C0 (ref)
   C0      4901.59 ± 28.24    4965.22                —              —
   C1      4139.95 ± 32.97    —                      -15.54%        ~-18.2% (4049–4038)
   C2      4805.78 ± 65.09    —                       -1.95%        ~-2.5% (4845–4885)
   ```

   **Bảng T4 kịch trần — RPS từ `wrk` + parser (n=5 mọi cond; C0 gồm run1 cũ + run2–5):**  
   ```
   cond              M5h mean±sd (RPS)    R021 mean (RPS)    M5h % vs C0    R021 C1 % vs C0 (ref)
   C0                140081 ± 335         142675             —              —
   C1-tracepoint     124100 ± 1076        124126             -11.34%        ~-13.0%
   C1-fentry         123955 ± 535         (m5f: tp)          -11.45%        —
   C2-tracepoint     134486 ± 384         136418              -3.92%        ~-4.3%
   C2-fentry         134655 ± 552         (m5f: tp)           -3.80%        —
   ```
   R021 tham chiếu: `reports/R021-m5f-wrk2-t3r-t4r-case-a.md` (T3/T4 kịch trần cùng case A, `wrk` không `-R`).

   **Nguyên văn `validation/m5h-20261009/c1_collect_metrics.tsv`:**  
   ```
   load	cond	run	records	drops	secs	recs_per_s
   T4	C1-tracepoint	run1	53617552	0	60.139	891560.42
   T4	C1-fentry	run1	53258113	0	60.144	885509.99
   T4	C1-tracepoint	run2	53005126	0	60.132	881479.51
   T4	C1-fentry	run2	52965938	0	60.154	880505.67
   T4	C1-tracepoint	run3	53048660	0	60.133	882188.81
   T4	C1-fentry	run3	52959130	0	60.246	879048.07
   T4	C1-tracepoint	run4	53256451	0	60.131	885673.80
   T4	C1-fentry	run4	53145276	0	60.252	882049.99
   T4	C1-tracepoint	run5	52354480	0	60.137	870586.83
   T4	C1-fentry	run5	52645343	0	60.167	874987.00
   T3	C1	run1	49153136	0	60.217	816266.77
   T3	C1	run2	49265906	0	60.224	818044.40
   T3	C1	run3	49524577	0	60.214	822476.12
   T3-R25	C1	run1	12773805	0	60.194	212210.60
   T3-R25	C1	run2	12680742	0	60.209	210612.07
   T3-R25	C1	run3	12794261	0	60.206	212508.07
   T3-R50	C1	run1	27956913	0	60.200	464400.55
   T3-R50	C1	run2	27745269	0	60.195	460923.15
   T3-R50	C1	run3	27878441	0	60.196	463127.80
   T4-R25	C1	run1	15868600	0	60.040	264300.47
   T4-R25	C1	run2	15876743	0	60.035	264458.12
   T4-R25	C1	run3	15870708	0	60.035	264357.59
   T4-R50	C1	run1	30976465	0	60.033	515990.62
   T4-R50	C1	run2	30950194	0	60.024	515630.31
   T4-R50	C1	run3	30981561	0	60.035	516058.32
   ```

   **Nguyên văn `validation/m5h-20261009/m5f_parse.tsv` (tải cố định T3-R / T4-R; mỗi lượt có `meta.txt` với `target_*` và `cgroup_cpu_usec`, ví dụ `T3-R25/C0/run1`: `target_tps=1225.3984583333333 cgroup_cpu_usec=56198416`; `T4-R50/C2-fentry/run1`: `target_rps=70040 cgroup_cpu_usec=129277987`):**  
   ```
   label	kieu	n	toc_do_per_s	lat_tb_ms	p50_ms	p99_ms	max_ms	lag_tb_ms	lag_p99_ms	loi	dat_muc	hop_ly
   T3-R25 C0 run1	pgbench	72970	1216.3073	1.2240	1.0580	3.5850	25.3750	0.0637	0.1330	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C1 run1	pgbench	73694	1228.5158	1.3250	1.1380	3.8030	39.2400	0.0705	0.1670	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C2 run1	pgbench	73423	1223.9792	1.2583	1.0880	3.8820	15.8290	0.0624	0.1400	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C0 run2	pgbench	73481	1224.9699	1.2197	1.0710	3.2230	13.4470	0.0594	0.1350	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C1 run2	pgbench	72945	1215.9266	1.4183	1.1560	4.9260	62.9170	0.1011	0.1880	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C2 run2	pgbench	73113	1218.7735	1.2569	1.0940	3.4630	20.6640	0.0621	0.1430	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C0 run3	pgbench	74028	1234.0953	1.3211	1.0790	4.7340	63.9890	0.0895	0.1490	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C1 run3	pgbench	73363	1222.9802	1.3744	1.1650	4.4600	33.3780	0.0657	0.1670	bo_qua=0;that_bai=0	OK	OK
   T3-R25 C2 run3	pgbench	73688	1228.3570	1.3154	1.1100	4.5480	18.5150	0.0652	0.1480	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C0 run1	pgbench	147316	2455.6455	8.8539	1.3550	302.6040	519.6800	7.2032	296.9240	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C1 run1	pgbench	147214	2453.8875	13.1511	1.6010	323.7790	454.0660	11.1808	317.1620	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C2 run1	pgbench	146990	2450.2332	5.5195	1.4120	124.2100	263.1140	3.8180	117.9530	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C0 run2	pgbench	146109	2435.5634	9.7553	1.3490	338.6410	471.3340	8.1277	331.4620	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C1 run2	pgbench	146873	2448.0973	5.4106	1.5430	142.7430	224.3930	3.6143	136.3080	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C2 run2	pgbench	146223	2437.2147	8.1034	1.4040	239.8400	361.5990	6.4119	233.7350	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C0 run3	pgbench	146543	2442.5588	5.2096	1.3400	166.8430	304.2500	3.6593	160.4260	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C1 run3	pgbench	147107	2451.9833	7.3552	1.5700	183.1470	300.5650	5.4521	177.3490	bo_qua=0;that_bai=0	OK	OK
   T3-R50 C2 run3	pgbench	146517	2442.4242	6.9280	1.3940	224.8040	331.9970	5.2988	217.6680	bo_qua=0;that_bai=0	OK	OK
   T4-R25 C0 run1	wrk2	2091433	34856.9700	1.0000	0.9700	2.0200	4.4700	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C1 run1	wrk2	2099871	34997.3500	1.0300	1.0000	2.0900	3.4600	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C2 run1	wrk2	2099874	34997.4100	1.0200	0.9900	2.0800	3.2600	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C0 run2	wrk2	2099848	34997.5800	1.0100	0.9900	2.0600	4.7600	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C1 run2	wrk2	2099853	34997.6800	1.0300	1.0000	2.1000	3.6500	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C2 run2	wrk2	2091461	34857.3400	1.0100	0.9800	2.0400	3.3600	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C0 run3	wrk2	2099865	34997.8500	1.0100	0.9800	2.0600	4.0300	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C1 run3	wrk2	2099862	34997.1900	1.0300	1.0000	2.0800	3.4400	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R25 C2 run3	wrk2	2091442	34856.9700	1.0200	0.9900	2.0400	3.8400	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C0 run1	wrk2	4199709	69994.4400	1.2600	1.2000	2.9500	6.6200	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C1 run1	wrk2	4199663	69993.6800	1.2600	1.1900	3.0000	6.0200	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C2 run1	wrk2	4182866	69714.7500	1.2600	1.1900	2.9700	7.0000	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C0 run2	wrk2	4199706	69995.3100	1.2600	1.1900	2.9700	6.6200	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C1 run2	wrk2	4199678	69994.7800	1.2600	1.1800	3.0600	8.5400	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C2 run2	wrk2	4199654	69994.4500	1.2700	1.2000	2.9800	6.5200	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C0 run3	wrk2	4182862	69714.5900	1.2600	1.2000	2.9400	5.7000	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C1 run3	wrk2	4199653	69994.0500	1.2700	1.1900	3.0200	8.3500	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C2 run3	wrk2	4199662	69994.5500	1.2700	1.2000	2.9700	6.0400	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C2-fentry run1	wrk2	4199679	69993.8500	1.2700	1.2000	2.9700	5.8500	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C2-fentry run2	wrk2	4199673	69994.1900	1.2700	1.2000	2.9600	6.1800	nan	nan	non2xx=0;socket=0	OK	OK
   T4-R50 C2-fentry run3	wrk2	4199705	69995.2900	1.2600	1.1900	2.9900	8.6100	nan	nan	non2xx=0;socket=0	OK	OK
   ```

   **Bench log (cuối):**  
   ```
   === m5h bench xong ===
   ```

   **G3 job:**  
   ```
   exit=0
   ```

6. **File dữ liệu**  
   - `/root/hids/validation/m5h-20261009/` (`g3/`, `step2/`, `T1/`, `T3/`, `T4/`, `T3-R25/`, `T3-R50/`, `T4-R25/`, `T4-R50/`, `m5f_parse.tsv`, `m5f_parse_sat.tsv`, `c1_collect_metrics.tsv`)  
   - `/root/hids/out/jobs/m5h-g3.log`, `m5h-g3.status`, `m5h-bench.log`, `m5h-bench.status`

7. **Quyết định đã tự đưa ra**  
   - `collect_hook_args`: in `-sys-enter-hook` và giá trị trên hai dòng để `mapfile` tách đúng (tránh lỗi `flag provided but not defined: -sys-enter-hook fentry`).  
   - `coll_pid=$(scope_main_pid …) || coll_pid=""` để `set -e` không dừng bench khi scope chưa sẵn sàng.  
   - Alias `hids_drop_collect_artifacts` → `m5_drop_collect_artifacts`.  
   - Bỏ `sleep REST` khi T1/T4 bỏ qua lượt đã có kết quả (return 2).  
   - Bench chạy với `M5_SKIP_GIT_CHECK=1` khi cây git còn thay đổi cục bộ.

8. **Cần kiến trúc sư quyết định**  
   - (Không — G7-cap đã chốt bỏ tiêu chí `mat`=0.)

9. **Việc người dùng cần làm tay**  
   - (Không)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - G7b-nho zstd0 vẫn `mat`>0 (giữ như R025); G7-cap vẫn mất bản ghi khi zstd+stress — đã ghi nhận throughput, không chặn mốc.  
    - `m5f_parse_sat.tsv`: T4-sat C0 run1 thiếu dòng (run1 từ lượt bench sớm; run2–5 đủ); thống kê T4 C0 dùng cả 5 file `wrk.txt`.  
    - O5 không làm.
