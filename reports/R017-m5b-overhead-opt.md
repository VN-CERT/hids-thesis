# R017 — M5b tối ưu overhead collector

1. **Số báo cáo:** R017  
   **Ngày giờ:** 2026-10-07 22:15 (UTC+7)  
   **Mốc:** M5b  
   **Git commit:** `255ef53` (tag `m5b`; sửa `m5b.sh`/hey sau tag trên nhánh master)

2. **Mục tiêu**  
   Chẩn đoán overhead T3/T4-C1; O1–O3; không hồi quy G7/G3; đo lại ma trận M5; T3-R/T4-R; chi phí người quan sát; so với R016.

3. **Đã làm**  
   - Bước 1: `scripts/m5b_diag.sh`, cờ `-discard`, dữ liệu `validation/m5b-20261007/diag/` (chạy trước khi sửa O1 — xem mục 7).  
   - O2: map cgroup con cháu (`internal/cgroupexpand`), BPF tra một lần `bpf_get_current_cgroup_id()`.  
   - O3: zstd mức 2 (mặc định) trên phần bản ghi; `recfmt.RecordPayloadReader`; g3 dùng `-zstd-level 0`.  
   - O1: thử `BPF_RB_NO_WAKEUP` + poll 10 ms → **100% mất bản ghi**; đã **tắt NO_WAKEUP**, mặc định `-ringbuf-poll-ms 0`, giữ `ReadIntoPoll` cho tương lai (`fd89a20`, `255ef53`).  
   - O4: **không làm** — T3/T4-C2 sau tối ưu ≤ ~1,4% (dưới 3%).  
   - Bước 3: G7a + G7d (lượt chạy sau sửa); G7b-nho (1 MiB, đối chiếu mất/seq); G3 S1–S5 → `validation/g3-20261007-v3/`.  
   - Bước 4: `scripts/m5b.sh` → `validation/m5b-20261007/`.

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids
   make build
   sudo bash scripts/m5b_diag.sh          # bước 1
   sudo bash scripts/g7.sh a 1000000
   sudo bash scripts/g7.sh d 1000000
   sudo bash scripts/g7.sh b-nho 1000000
   sudo bash scripts/g3.sh
   sudo bash scripts/m5b.sh
   ```

5. **Kết quả**

   **Bảng chẩn đoán bước 1 (T3-C1 / T4-C1, 60 s; commit diag trước sửa đọc ring buffer — `mat` ≈ `dinh_ghi`, 0 bản ghi trong file):**

   | Tải | (a) metric | (b) discard | (c) hids_sys_enter avg ns (bpf stats) | (d) ΔIWI | (d) ΔCAL | (e) coll Δusec* |
   |-----|------------|-------------|----------------------------------------|----------|----------|-----------------|
   | T3 | 3531 TPS | 3854 TPS | (có file `bpf-hids.tsv`) | 8 | 10213908 | ~−313k |
   | T4 | 169983 RPS | 151933 RPS | (có file `bpf-hids.tsv`) | 10 | 21040133 | ~−324k |

   *`usage_usec` scope collector âm do đo cgroup scope không ổn định; chỉ mang tính định hướng.

   **Tác dụng tối ưu (so R016 `summary.csv` m5 / `validation/m5-20261007-m6a`):**

   | Tải | Chỉ số | R016 C1/C2 overhead % | M5b C1/C2 overhead % |
   |-----|--------|----------------------|----------------------|
   | T3 | TPS | C1 −45,4; C2 −3,8 | C1 −41,0; C2 −1,2 |
   | T4 | RPS | C1 −23,6; C2 −4,6 | C1 −13,4; C2 +1,4 |
   | T2 | µs/iter | C1 +8,5; C2 +1,5 | C1 +6,3; C2 +0,6 |

   O2 chủ yếu giảm C2 (lọc decoy). O3 giảm ghi đĩa (zstd). O1 chưa bật NO_WAKEUP ổn định.

   **Chi phí người quan sát (T1-C1 − T1-C0):** `461.712` ns/syscall (`validation/m5b-20261007/observer_cost.txt`).

   **T3-R (50% TPS T3-C0, pgbench `-R`, C1):** TPS ≈ 2044,3; target ≈ 2045,7; `latency_ms` ≈ 30,4 (`T3-R/C1/run1/result.txt`). p99 chưa parse đúng từ log pgbench `-r`.

   **T4-R:** lần chạy trong `m5b.sh` lỗi `hey -qps` (cờ sai). Đã sửa script dùng `hey -q <QPS/worker> -c 64`; chưa chạy lại đủ 60 s trong khung báo cáo.

   **summary.csv M5b (nguyên văn):**

   ```
   load,condition,mean,std,n_runs,records_mean,drops_mean,overhead_pct
   T1,C0,194.518,11.609288091868503,5,0.0,0.0,0.0
   T1,C1,656.23,19.507125621167244,5,,0.0,237.36209502462495
   T1,C2,194.278,4.535071113003625,5,,0.0,-0.12338189781922963
   T1,C3,537.078,17.929067739288644,5,,0.0,176.10709548730705
   T2,C0,4.3181136,0.04716019085309152,5,,,0.0
   T2,C1,4.5922816,0.11865877186832831,5,,,6.349253989056692
   T2,C2,4.3429182,0.029923711696579425,5,,,0.5744313905961045
   T2,C3,4.5613741999999995,0.027029385318575138,5,,,5.63349236574043
   T3,C0,4091.3825343999997,111.55222709804715,5,0.0,0.0,0.0
   T3,C1,2412.5210352,20.6842133781064,5,32179815.4,,-41.034087746239166
   T3,C2,4042.0523498000002,18.026496145727762,5,0.0,,-1.2057094193768352
   T3,C3,2453.161417,23.15242649357463,5,32509799.4,,-40.04077114828483
   T4,C0,160815.34,4651.310961788086,5,0.0,0.0,0.0
   T4,C1,139217.66,2080.3574586594477,5,51618400.2,,-13.43011182888398
   T4,C2,163071.148,2920.571142973588,5,0.0,,1.402731853814437
   T4,C3,116433.024,3605.0983143223684,5,43342441.4,,-27.59830996222126
   T3-R,C1,2044.311187,0.0,1,27052472.0,,
   ```

6. **File dữ liệu**  
   - `/root/hids/validation/m5b-20261007/` (`summary.csv`, `observer_cost.txt`, ma trận T1–T4, T3-R)  
   - `/root/hids/validation/m5b-20261007/diag/`  
   - `/root/hids/validation/g3-20261007-v3/`  
   - Log job: `out/jobs/m5b.log`, `out/jobs/g3-m5b-r3.log`

7. **Quyết định tự đưa ra**  
   - Tắt `BPF_RB_NO_WAKEUP` mặc định vì cilium/ebpf + poll 10 ms gây 0 bản ghi đọc được dù kernel vẫn đếm `dinh_ghi`.  
   - g3 tắt zstd khi thu để `g3_window.py` đọc `.bin` thô.  
   - T4-R dùng `hey` vì hỗ trợ `-q` (QPS/worker) + `-z` (thời lượng); `wrk` không giới hạn tốc độ trực tiếp.

8. **Cần kiến trúc sư**  
   - Có bật lại O1 (NO_WAKEUP + poll) sau khi có cách đọc ring buffer đã kiểm chứng (ví dụ `ringbuf` notify từ user space hoặc vòng drain khác)?  
   - T3/T4-C1 vẫn >10% suy giảm throughput — có chấp nhận O4 fentry `x64_sys_call` thử nghiệm?

9. **Việc người dùng**  
   Không.

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Chạy lại `m5b_diag.sh` sau `255ef53` để bảng (a)–(e) có `records`/`drops` đúng.  
    - Chạy lại T4-R sau sửa `hey -q`.  
    - Hoàn thiện O1 nếu kiến trúc sư yêu cầu.
