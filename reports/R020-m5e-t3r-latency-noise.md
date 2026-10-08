# R020 — M5e: zstd G7, T3-R/T4-R, nhiễu git push, độ trễ từ log

1. **Số báo cáo:** R020  
   **Ngày giờ:** 2026-10-08 19:45 (UTC+7)  
   **Mốc:** M5e  
   **Git commit:** `583857b` (cây dirty — chưa commit các sửa collector/scripts sau m5e task)

2. **Mục tiêu**  
   Kiểm G7a/G7b zstd mặc định; chạy lại T3-R/T4-R 25%/50% xen kẽ C0–C2 × 3; T4 kịch trần × 7; độ trễ từ hey CSV / pgbench `-l`; đánh dấu và chạy lại lượt giao cửa sổ git push; summary + tag `m5e`. O5 không làm (R019).

3. **Đã làm gì**  
   - `hids-collect`: ghi raw trên `/dev/shm`, nén zstd mặc định sau khi dừng (G7b mat=0).  
   - `m5e_step1_zstd.sh`, `m5e_latency.py`, `m5e_noise.py`, `m5e_noise_rerun.sh`, `m5e.sh` (skip step1, resume, noise).  
   - Sửa `m5c_fixed.sh`: pgbench `-l --log-prefix`, nginx mount `chmod 755`, hey latency cột 0 + HTTP 200.  
   - Job `hids-m5e-noise`: 8 lượt nhiễu chạy lại; job `hids-m5e` resume → xong 19:38.  
   - Dữ liệu: `validation/m5e-20261008/`.

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids && make build
   sudo bash scripts/m5e.sh                    # lần đầu (step1 + matrix)
   sudo M5E_SKIP_STEP1=1 M5E_RESUME=1 bash scripts/m5e.sh
   sudo bash scripts/m5e_noise_rerun.sh
   python3 analysis/m5e_summary.py validation/m5e-20261008 validation/m5d-20261008
   python3 analysis/m5e_report_tables.py validation/m5e-20261008
   git tag m5e
   ```

5. **Kết quả**

   **Mục 1 — G7 zstd mặc định (STEP1_ZSTD_PASS 2026-10-08T17:44:05+07:00):**  
   ```
   G7a mat=0 perf_diff=0 recstat=1000001 collector_rec=1000001
   G7b mat=0 perf_diff=0 recstat=24000024 collector_rec=24000024
   ```
   (Đối chiếu rec-stat sau giải nén; perf − bản ghi = 0 trên bảng g7a/g7b-zstd.txt.)

   **Cửa sổ nhiễu git push (HH:MM–HH:MM, +07):**  
   - **17:51–17:56** — sửa `.git/index` lúc 17:51:12; VS Code git `diff --numstat` ~11s/lần 17:51:09–17:52:24 (`exthost4/vscode.git` log). Không có dòng `git push` / `pack-objects` trong `journalctl`, `auth.log`, hay log push Cursor.  
   - **18:13–18:18** — sửa `.git/config` 18:15:12; cụm git diff 18:17:43–18:18:44.  
   - **sar** (`/var/log/sysstat/sa08`): không có mẫu CPU sau ~14:20; không dùng được để xác nhận 24 lõi trong lúc M5e (17:51+).

   **Lượt giao cửa sổ (ánh xạ pgbench/hey, lần chạy đầu) — đã chạy lại:**  
   ```
   T3-R25 C0 run1, C0 run2, C1 run1, C2 run1  (push-A)
   T3-R50 C2 run3                              (push-B)
   T4-R25 C0 run1, C1 run1, C2 run1           (push-B)
   ```
   Chi tiết: `validation/m5e-20261008/noise-reruns.done`, log `out/jobs/m5e-noise-rerun.log`.  
   T4-R25/T4-R50 bị 403 nginx (mount quyền) trên một phần lượt cũ → xóa thư mục T4-R và đo lại trong job resume (hey HTTP 200, ~1e6 mẫu/60s).

   **Bảng tải cố định (latency_sanity=1, từ `m5e-tables.txt`):**  
   ```
   === tai co dinh (chi run latency_sanity=1) ===
   T3-R25	C0	avg_ms=500.4543	p50=500.0577	p99=989.6657	cgroup_cpu_usec=43395401	n=3
   T3-R25	C1	avg_ms=499.2883	p50=498.8060	p99=990.0350	cgroup_cpu_usec=48090905	n=3
   T3-R25	C2	avg_ms=498.4831	p50=496.2757	p99=989.6680	cgroup_cpu_usec=45012332	n=3
   T3-R50	C0	avg_ms=499.9400	p50=499.1613	p99=990.1753	cgroup_cpu_usec=91047874	n=3
   T3-R50	C1	avg_ms=499.1403	p50=499.0627	p99=989.8557	cgroup_cpu_usec=102706374	n=3
   T3-R50	C2	avg_ms=499.1796	p50=498.4923	p99=989.8447	cgroup_cpu_usec=93399346	n=3
   T4-R25	C0	avg_ms=0.3898	p50=0.3000	p99=1.1000	cgroup_cpu_usec=81099887	n=3
   T4-R25	C1	avg_ms=0.4185	p50=0.4000	p99=1.2000	cgroup_cpu_usec=91054784	n=3
   T4-R25	C2	avg_ms=0.4045	p50=0.3000	p99=1.2333	cgroup_cpu_usec=84629143	n=3
   T4-R50	C0	avg_ms=0.4501	p50=0.4000	p99=1.5333	cgroup_cpu_usec=155113408	n=3
   T4-R50	C1	avg_ms=0.4753	p50=0.4000	p99=1.6333	cgroup_cpu_usec=173116669	n=3
   T4-R50	C2	avg_ms=0.4651	p50=0.4000	p99=1.6000	cgroup_cpu_usec=161762545	n=3
   ```

   **T4 kịch trần (95% CI trên metric value):**  
   ```
   === T4 kich tran (95% CI tren metric value) ===
   T4	C0	mean=185353.8171	std=2327.5880	ci95_half=1724.3013	n=7
   T4	C1	mean=169333.2057	std=4308.7912	ci95_half=3191.9972	n=7
   T4	C2	mean=180883.0614	std=2086.0372	ci95_half=1545.3580	n=7
   ```

   **Summary (`validation/m5e-20261008/summary.csv`) — nguyên văn:**  
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
   T4,C0,185353.81714285715,2327.587986132959,7,0.0,0.0,0.0
   T4,C1,169333.20571428572,4308.7912098594325,7,63127146.0,,-8.643259510660044
   T4,C2,180883.0614285714,2086.0372156270205,7,0.0,,-2.412011677558283
   T3-R25,C0,970.6944444444445,1.9568493195081114,3,,0.0,0.0
   T3-R25,C1,973.9444444444445,8.124334730598864,3,10009069.666666666,,0.334811847188439
   T3-R25,C2,974.05,2.2452418825398346,3,0.0,,0.34568607812275837
   T3-R50,C0,1938.8111111111111,5.087275338564892,3,,0.0,0.0
   T3-R50,C1,1946.2111111111112,4.196305694474722,3,21484665.0,,0.3816772019507993
   T3-R50,C2,1942.8222222222223,9.568558659213851,3,0.0,,0.20688508994630497
   T4-R25,C0,16666.666666666668,0.0,3,,0.0,0.0
   T4-R25,C1,16666.666666666668,0.0,3,19783880.0,,0.0
   T4-R25,C2,16666.666666666668,0.0,3,0.0,,0.0
   T4-R50,C0,16666.666666666668,0.0,3,,0.0,0.0
   T4-R50,C1,16666.666666666668,0.0,3,37935348.666666664,,0.0
   T4-R50,C2,16666.666666666668,0.0,3,0.0,,0.0
   ```

6. **File dữ liệu**  
   - `/root/hids/validation/m5e-20261008/` (summary.csv, m5e-tables.txt, step1-zstd/, T3-R25, T3-R50, T4-R25, T4-R50, T4/)  
   - `/root/hids/out/jobs/m5e.log`, `m5e-noise-rerun.log`

7. **Quyết định đã tự đưa ra**  
   - Deferred zstd + `/dev/shm` để G7b mat=0 với zstd level 2.  
   - Cửa sổ nhiễu suy từ dấu vết `.git/*` + VS Code git log (không có log push trực tiếp).  
   - `M5E_RESUME=1` bỏ `rm -rf` và không `M5C_FIXED_FORCE` để không đo lại T3-R đã sạch.

8. **Cần kiến trúc sư quyết định**  
   - Có chấp nhận cửa sổ nhiễu suy diễn (mục 5) khi không có log `git push` trên máy?

9. **Việc người dùng cần làm tay**  
   - (không)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Commit các thay đổi code (collector, scripts) trước khi coi số tái lập được.  
    - O5 vẫn không làm theo R019.
