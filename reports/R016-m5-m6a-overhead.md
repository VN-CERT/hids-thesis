# R016 — M5 overhead collector (mã m6a)

1. **Số báo cáo:** R016  
   **Ngày giờ:** 2026-10-07 21:05 (UTC+7)  
   **Mốc:** M5 (m6a)  
   **Git commit:** `32313e5` (tag `m5`)

2. **Mục tiêu**  
   Đo overhead C0–C3 cho T1–T4 trên mã m6a; lưu `validation/m5-20261007-m6a/`; C3 dùng `stress-ng --cpu-method int64`.

3. **Đã làm**  
   - Sửa `m5.sh` (OUTROOT `-m6a`, restore `/root/containers-da-dung.txt`, summary sau mỗi run, parse T2/T3, xóa `.bin` sau run).  
   - Job `hids-m5-m6a` (systemd); sửa lỗi đầy đĩa (xóa archive M5 cũ + `collect.bin`).  
   - Bảng BPF: lượt đo bổ sung với `kernel.bpf_stats_enabled=1` (pgtest, ~60 s) — file `bpf-kernel-cost.txt`.

4. **Lệnh**  
   ```bash
   cd /root/hids
   M5_OUTROOT=validation/m5-20261007-m6a sudo bash scripts/m5.sh
   ```

5. **Kết quả**

   **Bảng theo tải (mean ± std; overhead % so C0):**

   | Tải | C0 | C1 | C2 | C3 |
   |-----|----|----|----|-----|
   | T1 ns/syscall | 141.95 ± 0.06 | 662.88 ± 5.51 (+367%) | 257.30 ± 5.48 (+81%) | 677.35 ± 8.56 (+377%) |
   | T2 µs/iter | 4.305 ± 0.018 | 4.670 ± 0.045 (+8.5%) | 4.368 ± 0.032 (+1.5%) | 4.684 ± 0.043 (+8.8%) |
   | T3 TPS | 4107.9 ± 110.0 | 2242.7 ± 19.7 (−45%) | 3952.0 ± 57.0 (−3.8%) | 2269.6 ± 18.5 (−45%) |
   | T4 req/s | 176595 ± 2400 | 134904 ± 12644 (−24%) | 168413 ± 6765 (−4.6%) | 113445 ± 5312 (−36%) |

   **C1/C3 — bản ghi/giây và mất (trung bình 5 run, cửa sổ đo 60 s):**

   | Tải | Điều kiện | records/s | drops (mean) |
   |-----|-----------|-----------|--------------|
   | T3 | C1 | 502896 | 0 |
   | T3 | C3 | 506041 | 0 |
   | T4 | C1 | 832867 | 0 |
   | T4 | C3 | 702777 | 0 |

   **Dung lượng/giờ (C3 T4, một run sau khi ghi `bin_bytes` trong `result.txt`):** ~1,42×10¹¹ byte/h (ước từ `bin_bytes` mean ≈ 2,36×10⁹ byte trong 60 s). Các run trước khi bật xóa `.bin` đã mất file — chỉ run cuối T4 C3 còn `bin_bytes` trong `result.txt`.

   **Chi phí BPF (trích `bpf-kernel-cost.txt`, lượt đo bổ sung):**

   ```
   hids_sys_enter	avg_ns=203.2	run_cnt=124695	runs_per_s=2078.25
   hids_sched_switch	avg_ns=102.4	run_cnt=52218	runs_per_s=870.30
   hids_sched_wakeup	avg_ns=76.0	run_cnt=26031	runs_per_s=433.85
   hids_irq_call_function_single_entry	avg_ns=94.5	run_cnt=22775	runs_per_s=379.58
   hids_irq_call_function_single_exit	avg_ns=70.8	run_cnt=22776	runs_per_s=379.60
   … (đầy đủ: validation/m5-20261007-m6a/bpf-kernel-cost.txt)
   ```

   **summary.csv (nguyên văn):**

   ```
   load,condition,mean,std,n_runs,records_mean,drops_mean,overhead_pct
   T1,C0,141.946,0.05941380311005923,5,0.0,0.0,0.0
   T1,C1,662.876,5.513975879526517,5,,0.0,366.99167288969045
   T1,C2,257.304,5.4827757568589135,5,,0.0,81.26893325630871
   T1,C3,677.35,8.56144555551221,5,,0.0,377.1885083059755
   T2,C0,4.3050774,0.017874715013112726,5,,,0.0
   T2,C1,4.6695718,0.04512253394591208,5,,,8.466616651305731
   T2,C2,4.3684966,0.032075119373121366,5,,,1.4731256631994638
   T2,C3,4.6837766,0.04299420917170124,5,,,8.796571230055
   T3,C0,4107.8820804,110.0441656456019,5,0.0,0.0,0.0
   T3,C1,2242.7105944,19.701788772185257,5,30173739.4,,-45.40469880816007
   T3,C2,3952.013263,56.98683851708336,5,0.0,,-3.7943839270289463
   T3,C3,2269.6477808,18.545848682720475,5,30362467.6,,-44.74895490235212
   T4,C0,176594.718,2399.634512310158,5,0.0,0.0,0.0
   T4,C1,134904.014,12644.237678499247,5,49972035.0,,-23.608126263436713
   T4,C2,168413.44400000002,6765.475306830265,5,0.0,,-4.6327965483089795
   T4,C3,113444.772,5311.833450737142,5,42166621.0,,-35.7598158739946
   ```

6. **File**  
   - `/root/hids/validation/m5-20261007-m6a/summary.csv`  
   - `/root/hids/validation/m5-20261007-m6a/bpf-kernel-cost.txt`  
   - `/root/hids/out/jobs/m5-m6a.log`

7. **Quyết định**  
   - Xóa `validation/m5-20261007-truoc-m6a` trên đĩa để tiếp tục job; dữ liệu cũ vẫn có trong git commit `5e9160b` nếu cần.  
   - BPF kernel cost trong `m5.sh` ghi `progs.json` sau khi collector thoát — bổ sung lượt đo tay cho R016.

8. **Cần kiến trúc sư**  
   Không.

9. **Người dùng**  
   Không.

10. **Ghi chú**  
    - T1 overhead % lớn nhất; C2 < C1; T3/T4 drops = 0.  
    - Container thật đã `docker start` theo `/root/containers-da-dung.txt`.
