# R018 — M5c chẩn đoán đĩa, O4 fentry, tải cố định

1. **Số báo cáo:** R018  
   **Ngày giờ:** 2026-10-08 11:30 (UTC+7)  
   **Mốc:** M5c  
   **Git commit:** `7b372a8` (tag `m5c`)

2. **Mục tiêu**  
   Theo R017: bỏ O1 (NO_WAKEUP / `-ringbuf-poll-ms`); chẩn đoán lại T3/T4 (C0, C1 đĩa, discard, tmpfs); thử O4 fentry; O5 chỉ khi BPF stats đủ; ma trận T3-R/T4-R; chi phí người quan sát; không hồi quy G7/G3.

3. **Đã làm**  
   - Lưu nhiệm vụ `docs/tasks/M5c.md`.  
   - Gỡ `BPF_RB_NO_WAKEUP`, `-ringbuf-poll-ms`, vòng `ReadIntoPoll` (giữ `ReadInto` chặn).  
   - O4: `hids_on_sys_enter` + `SEC("fentry/x64_sys_call")`, cờ `-sys-enter-hook tracepoint|fentry`.  
   - `scripts/m5c_diag.sh` → `validation/m5c-20261008/diag/`.  
   - `scripts/m5c_regress.sh fentry` → `validation/m5c-20261008/regress-fentry/` + G7 (fentry) + G3 → `validation/g3-20261008-v3/`.  
   - Sửa `systemd-run` (tách `--` trước lệnh collector), `collector_drops` khi chưa có `collect.log`, `m5c_fixed` (stealclock, log pgbench).  
   - Bước 3: `scripts/m5c_fixed.sh`, hook **tracepoint**, `validation/m5c-20261008/fixed/`.  
   - **O5:** không làm (không có `bpf-hids.tsv` hids_* dưới tải; idle rỗng).  
   - **Bước 4:** không ghi hướng dẫn vCenter (đĩa không phải nguyên nhân chính).

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids
   make build
   sudo bash scripts/m5c_diag.sh
   sudo bash scripts/m5c_regress.sh fentry
   sudo M5_SKIP_GIT_CHECK=1 M5C_BEST_HOOK=tracepoint \
     M5C_DIAG_SUMMARY=validation/m5c-20261008/diag/diag-summary.tsv \
     bash scripts/m5c_fixed.sh
   sudo HIDS_COLLECT_EXTRA="-sys-enter-hook tracepoint -allow-no-stealclock" \
     M5_SKIP_GIT_CHECK=1 M5_OUTROOT=validation/m5c-20261008/fixed/mini-t1 \
     M5_RUNS=5 M5_ONLY_T1_COND=C1 bash scripts/m5.sh
   git tag m5c   # trên commit báo cáo
   ```

5. **Kết quả**

   **Bảng bước 1 (T3/T4, 60 s; metric = TPS hoặc RPS; nguồn `diag-summary.tsv` + pgbench log trong `validation/m5c-20261008/diag/`):**

   | Tải | Biến thể | Throughput | Lat avg (ms, T3) | p99 (ms, T3) | ΔIWI | ΔCAL | ΔRES | cgroup Δusec (tải) |
   |-----|----------|------------|-------------------|--------------|------|------|------|---------------------|
   | T3 | C0 | 3808.50 | 4.201 | (log không có dòng p99) | 0 | 10246997 | 712010 | 173368519 |
   | T3 | (a) C1 đĩa+zstd | 2394.75 | 6.681 | — | 5971025 | 17435080 | 348253 | 172548632 |
   | T3 | (b) -discard | 2234.03 | 7.162 | — | 6787216 | 18931595 | 275569 | 168609126 |
   | T3 | (f) tmpfs | 2436.81 | 6.566 | — | 5999658 | 17759118 | 357733 | 172949428 |
   | T4 | C0 | 182086.68 | — | — | 0 | 22617010 | 1005029 | 184019388 |
   | T4 | (a) | 136085.21 | — | — | 5454721 | 23492854 | 1198303 | 185883990 |
   | T4 | (b) | 140675.82 | — | — | 7082796 | 25006563 | 1312535 | 192611860 |
   | T4 | (f) | 124829.95 | — | — | 5598187 | 25804925 | 1016200 | 170110738 |

   Kỳ vọng kiểm lỗi: nếu đĩa là nguyên nhân chính thì (b)/(f) phục hồi phần lớn TPS so (a). **T3:** (b) và (f) **không** phục hồi (còn ~59–63% C0). **T4:** (f) thấp hơn (a); (b) nhỉnh hơn (a) nhưng không đủ để kết luận đĩa.

   **BPF stats (a), T3:** `validation/m5c-20261008/diag/T3/a/bpf-hids.tsv` **rỗng**; `bpf-idle.tsv` rỗng. Không so được ns/lần hids_sys_enter tải vs rảnh.

   **O4 (fentry):** verifier/attach OK (`sys_enter_hook: fentry` trong `out/g7a-20261008-100212.bin.stats`). G7a/d/b-nho fentry: 1 000 001 bản ghi, mat=0. So với M5b tracepoint (`validation/m5b-20261007/summary.csv`): T4-C1 mean RPS fentry **142 103** vs m5b **139 218** (~+2%); T1-C1 fentry **510** ns/syscall vs m5b **656** (C0 fentry **142** vs m5b **195** — baseline T1 lệch). **Giữ tracepoint mặc định.**

   **O5:** không triển khai (điều kiện 1,5× không đo được).

   **Tải cố định (3 lượt/ô, tracepoint, `-allow-no-stealclock`; lat từ `result.txt`):**

   | Ô | C0 metric | C1 metric | C2 metric | C1 lat avg (ms, T3) | C1 cgroup Δusec (mean) |
   |---|-----------|-----------|-----------|---------------------|-------------------------|
   | T3-R25 | 951.79 TPS | 949.58 | 953.73 | 2.56 | 67 445 103 |
   | T3-R50 | 1903.42 | 1902.04 | 1904.06 | 13.31 | 137 430 374 |
   | T4-R25 | 45 401.9 RPS | 45 374.5 | 45 379.6 | — | 76 316 555 |
   | T4-R50 | 83 129.2 | 85 156.5 | 84 301.7 | — | 140 534 915 |

   p99_ms trong `result.txt` trống (pgbench không in percentile với cấu hình hiện tại).

   **Chi phí người quan sát (T1-C1 − T1-C0, tracepoint, `mini-t1`):** `366.782` ns/syscall (`validation/m5c-20261008/fixed/observer_cost_ns.txt`). So R017 M5b: `461.712` ns/syscall.

   **summary.csv (nguyên văn):**

   ```
   load,condition,mean,std,n_runs,records_mean,drops_mean,overhead_pct
   T3-R25,C0,951.7938673333333,4.072997644637801,3,0.0,,0.0
   T3-R25,C1,949.58103,4.08096185638191,3,10730996.666666666,,-0.23249123673522096
   T3-R25,C2,953.7269053333333,3.652690058009489,3,0.0,,0.20309418523738293
   T3-R50,C0,1903.4209553333335,4.764499938091714,3,0.0,0.0,0.0
   T3-R50,C1,1902.0409086666666,9.438141955434695,3,24645396.333333332,,-0.07250349234624281
   T3-R50,C2,1904.0624723333333,4.022451631046602,3,0.0,,0.033703369619961426
   T4-R25,C0,45401.93423333333,14.739913134187251,3,0.0,0.0,0.0
   T4-R25,C1,45374.4836,25.323502350388786,3,17553455.333333332,,-0.0604613741614119
   T4-R25,C2,45379.61236666667,20.919198989524055,3,0.0,,-0.049165012556396694
   T4-R50,C0,83129.22433333333,371.08200340886805,3,0.0,0.0,0.0
   T4-R50,C1,85156.54323333333,588.0730489917307,3,33123889.0,,2.4387559444447744
   T4-R50,C2,84301.66266666667,802.1749436703468,3,0.0,,1.41038045613426
   ```

   **G3:** `validation/g3-20261008-v3/` (chạy sau G7 fentry; collector G3 vẫn tracepoint mặc định).

6. **File dữ liệu**  
   - `/root/hids/validation/m5c-20261008/diag/`  
   - `/root/hids/validation/m5c-20261008/regress-fentry/`  
   - `/root/hids/validation/m5c-20261008/fixed/`  
   - `/root/hids/validation/g3-20261008-v3/`  
   - `/root/hids/out/jobs/m5c-regress-fentry.log`, `m5c-fixed.log`

7. **Quyết định tự đưa ra**  
   - Giữ **tracepoint** sau O4 (không cải thiện rõ T3/T4; T1 baseline lệch).  
   - `-allow-no-stealclock` trên script đo khi dmesg mất dòng `vmware-stealtime` (fail-closed steal).  
   - Không bước 4 vCenter vì chẩn đoán đĩa không khớp kỳ vọng.  
   - Sửa `systemd-run --` và `collector_drops` để ma trận chạy được.

8. **Cần kiến trúc sư quyết định**  
   - Cách lấy **BPF stats** `hids_*` có ý nghĩa dưới tải (để O5 hoặc so idle×1,5).  
   - Có chạy lại T1 baseline (C0 ~142 ns vs M5b ~195) trước khi so chi phí quan sát xuyên mốc hay không.

9. **Việc người dùng cần làm tay**  
   Không (bước 4 không kích hoạt).

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - p99 pgbench/T4 hey chưa parse vào `result.txt`.  
    - `hey` latency Distribution đôi khi trống trong log T4-R.  
    - Đề xuất: cải thiện `dump_bpf_hids` trong `m5c_diag.sh` (lọc `hids_*`, bật stats trước unload).
