# R019 — M5d O1, kiểm chứng G7/G3, G7-cap, đóng mốc

1. **Số báo cáo:** R019  
   **Ngày giờ:** 2026-10-08 17:05 (UTC+7)  
   **Mốc:** M5d  
   **Git commit:** `7ff5b73` (tag `m5d`)

2. **Mục tiêu**  
   Kiểm chứng O1 trước khi dùng số overhead; đo công suất G7-cap; chi phí BPF; dọn dữ liệu; ma trận T1–T4 × C0–C2 và tải cố định; tag `m5d`.

3. **Đã làm**  
   - Commit script đóng mốc (`1120f34`, `9ac6051`).  
   - Bước 1: `validation/m5d-20261008/verify-close-1120f34-v2/` — G7a/G7b (24×1 000 000, `-zstd-level 0` như G3/R003), G7b-nho, G3 S1–S5, IRQ T3-C1 60 s.  
   - G7-cap: `validation/m5d-20261008/g7-cap/summary.tsv` (zstd mặc định + `-zstd-level 0`).  
   - Collector: goroutine ghi/nén tách khỏi vòng đọc ringbuf khi bật zstd; `zstd.WithEncoderConcurrency(4)`.  
   - Bước 2: `bpf-ranh.txt`, `bpf-tai.txt` (đoạn kiến trúc sư, nguyên văn).  
   - Xóa `mini-t1/`; `validation/m5d-20261008/README.md`.  
   - Sau sửa collector: chạy lại T3-C1 và T4-C1 (5 lượt) → `rerun-t3t4-c1.log`.  
   - Sửa `m5d.sh` dùng `exec > >(tee …)` (không subshell mất `hids_print_df_at_job_end`).

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids && make build
   sudo M5D_CLOSE_VERIFY_OUT=validation/m5d-20261008/verify-close-1120f34-v2 \
     bash scripts/m5d_close_step1_verify.sh
   sudo M5D_CLOSE_OUT=validation/m5d-20261008 bash scripts/m5d_close_step2_bpf.sh
   sudo M5_SKIP_GIT_CHECK=1 M5D_MODE=1 M5_OUTROOT=validation/m5d-20261008 \
     M5_RERUN=T3:C1,T4:C1 M5_RUNS=5 bash scripts/m5.sh
   git tag m5d
   ```

5. **Kết quả**

   **Quyết định kiến trúc sư (G7b quy mô 576 M):** Lần đo `G7b` với N=24 000 000/tiến trình (576 M bản ghi) cho `mat ≈ 150 060 412`; `perf − bản ghi = mất = 150 060 412` (khớp tuyệt đối). Code trước O1 mất ~159 M ở quy mô đó — **giới hạn công suất chạy liên tục**, không chứng minh O1 hỏng. Định nghĩa gốc G7b: **24 × 1 000 000**.

   **Kiểm chứng O1 (`verify-close-1120f34-v2/step1-result.txt`):**
   ```
   PASS: G7a mat=0 perf-diff=0
   PASS: G7b mat=0 perf-diff=0
   PASS: G7b-nho perf-diff=2244749 = mat = seq_thieu
   PASS: G3 S1-S5 p99 phan du <= 500 ns
   STEP1_ALL_PASS 2026-10-08T16:48:45+07:00
   ```

   **IRQ T3-C1 60 s (`irq-t3c1-60s.tsv`, collector trên cgroup pgtest):**
   ```
   ts=2026-10-08T16:35:37+07:00 duration_s=60 IWI_delta=4 CAL_delta=10322619 RES_delta=706404 IWI_per_s=0 CAL_per_s=172043
   ```
   Đối chiếu R018 T3 (a) C1 đĩa 60 s: ΔIWI ≈ 5 971 025, ΔCAL ≈ 17 435 080 (cùng kịch bản diag khác collector/cgroup).

   **G7-cap — tốc độ cao nhất không mất (từ `g7-cap/summary.tsv`):**
   - zstd mặc định (level 2): **1 293 607 bản ghi/s** @ 2 tiến trình, `mat=0` (≥ 1 M/s mục tiêu khi bật nén).
   - `-zstd-level 0`: **2 767 327 bản ghi/s** @ 2 tiến trình; 24 tiến trình **2 100 065/s**, `mat=0`.

   **Bảng G7-cap (nguyên văn TSV):**
   ```
   mode	nproc	zstd_flag	records	lost	rate_per_s	loss_pct	cpu_user_s	cpu_sys_s	elapsed_s
   zstd-default	1		73539066	0	1225529	0.0000	61.093	48.662	60.006
   zstd-default	2		77628073	0	1293607	0.0000	61.09	51.969	60.009
   zstd-default	4		69751823	197502183	1162337	73.9006	61.478	49.314	60.010
   zstd-default	8		67668521	137904447	1127621	67.0830	61.484	50.205	60.010
   zstd-default	16		66726269	89727641	1111993	57.3508	61.485	49.703	60.006
   zstd-default	24		64242483	73098053	1070583	53.2239	61.462	44.554	60.007
   zstd0	1	-zstd-level 0	143142185	0	2385306	0.0000	61.054	27.383	60.010
   zstd0	2	-zstd-level 0	166067275	0	2767327	0.0000	61.046	32.751	60.010
   zstd0	4	-zstd-level 0	161738262	3129622	2695233	1.8983	61.052	33.345	60.009
   zstd0	8	-zstd-level 0	153714089	8484924	2561560	5.2312	61.077	35	60.008
   zstd0	16	-zstd-level 0	132301987	1618699	2204813	1.2087	61.051	29.028	60.006
   zstd0	24	-zstd-level 0	126022812	0	2100065	0.0000	61.057	27.188	60.009
   ```

   **Chi phí BPF (30 s, `hids_sys_enter` ns/lần):**
   | Trạng thái | lần/giây | ns/lần |
   |------------|----------|--------|
   | Rảnh, collector decoy | 32 734 | 77.7 |
   | T3-C1 có tải (+10 s pgbench) | 1 852 931 | 198.9 |

   Tỉ số ns/lần có tải / rảnh ≈ **2,56** (≥ 1,5). **O5 chưa làm** — chờ kiến trúc sư.

   **Ma trận kịch trần (mean overhead %), đặt cạnh R016 / R018:**

   | Load | C0 (R016) | C1 (R016) | C2 (R016) | C0 (R018) | C1 (R018) | C2 (R018) | C0 (M5d) | C1 (M5d) | C2 (M5d) |
   |------|-----------|-----------|-----------|-----------|-----------|-----------|----------|----------|----------|
   | T1 | 0 | 367 | 81 | — | — | — | 0 | 164 | 36 |
   | T2 | 0 | 8.5 | 1.5 | — | — | — | 0 | 0.45 | −0.13 |
   | T3 | 0 | −45.4 | −3.8 | — | — | — | 0 | −1.3 | 1.0 |
   | T4 | 0 | −23.6 | −4.6 | — | — | — | 0 | −7.3 | −10.5 |

   (R018 không có ma trận T1–T4 đầy đủ; số R016 từ `reports/R016-m5-m6a-overhead.md`.)

   **Tải cố định T4-R (trung bình 3 run, từ `result.txt` / hey):**

   | Load | C0 lat (ms) | C0 p99 | C0 cgroup µs | C1 lat | C1 p99 | C1 cgroup µs | C2 lat | C2 p99 | C2 cgroup µs |
   |------|-------------|--------|--------------|--------|--------|--------------|--------|--------|--------------|
   | T4-R25 | 1.17 | 0.90 | 55.8M | 0.20 | 1.00 | 63.6M | 0.17 | 0.90 | 58.1M |
   | T4-R50 | 0.40 | 1.17 | 101.3M | 0.13 | 1.30 | 119.7M | 0.37 | 1.20 | 106.6M |

   **T3-R25/T3-R50:** `pgbench.log` rỗng trong `validation/m5d-20261008/` (lượt `m5c_fixed` trước đó); không có lat/p99 đáng tin — cần chạy lại T3-R nếu cần số cho bài báo.

   **Chi phí người quan sát:** `observer_cost.txt` → `chi_phi_nguoi_quan_sat_ns=237.058`

   **summary.csv (nguyên văn):**
   ```
   load,condition,mean,std,n_runs,records_mean,drops_mean,overhead_pct
   T1,C0,141.756,0.11371015785760144,5,0.0,0.0,0.0
   T1,C1,374.836,10.190246807609698,5,,0.0,164.4233753774091
   T1,C2,192.238,0.07429670248402469,5,,0.0,35.61189649820819
   T2,C0,4.3186432,0.0450696308915436,5,,,0.0
   T2,C1,4.338194199999999,0.048711239167157326,5,,,0.4527116294302568
   T2,C2,4.313241,0.03658440255081393,5,,,-0.12509021351892857
   T3,C0,3955.7476938,228.56417642248502,5,0.0,0.0,0.0
   T3,C1,3904.9452032,55.195368734049126,5,46789019.8,,-1.284270245031674
   T3,C2,3994.7413988,25.18271408365416,5,0.0,,0.9857480309251331
   T4,C0,175529.862,6914.425041539605,5,0.0,0.0,0.0
   T4,C1,162683.246,3108.266578614193,5,60596866.8,,-7.318763800999275
   T4,C2,157114.415,13269.374854600344,4,0.0,,-10.491347050680178
   ```

6. **File dữ liệu**  
   - `/root/hids/validation/m5d-20261008/`  
   - `/root/hids/validation/m5d-20261008/verify-close-1120f34-v2/`  
   - `/root/hids/validation/m5d-20261008/g7-cap/summary.tsv`  
   - `/root/hids/validation/m5d-20261008/bpf-ranh.txt`, `bpf-tai.txt`

7. **Quyết định tự đưa ra**  
   - G7 kiểm chứng dùng `-zstd-level 0` (cùng chính sách `g3.sh` / R003); ma trận M5d vẫn ghi đĩa với zstd mặc định (overhead thực tế).  
   - G7-cap đạt ≥ 1 M bản ghi/s không mất với zstd mặc định ở 2 sysinj; không cần hạ zstd level 1 thêm.  
   - Không triển khai O5 dù BPF ≥ 1,5×.

8. **Cần kiến trúc sư**  
   - O5 (ring per-CPU) sau tỉ số BPF 2,56×.  
   - Có chạy lại T3-R25/T3-R50 (pgbench) hay chấp nhận thiếu số T3-R trong báo cáo.

9. **Việc người dùng cần làm tay**  
   - Không.

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - T3-R trong `validation/m5d-20261008/` thiếu metric tải.  
    - G7-cap: mất lớn khi zstd-default và nproc ≥ 4 (báo cáo công suất, không fail O1).
