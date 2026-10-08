# R021 — M5f: G7 nén, T4 wrk kịch trần (case A), T3/T4-R + m5f_parse

1. **Số báo cáo:** R021  
   **Ngày giờ:** 2026-10-08 23:10 (UTC+7)  
   **Mốc:** M5f  
   **Git commit:** `b8ac53f` (tag `m5f`; code đo collector tại `ff6c0ab`)

2. **Mục tiêu**  
   Khôi phục collector không `/dev/shm`; kiểm G7a + G7-cap zstd; cài wrk2; đo T4 kịch trần (case A: `wrk` không `-R`), T3 kịch trần cấu hình mới, T3-R/T4-R 25%/50% với `m5f_parse.py`; lưu `validation/m5f-20261008/`; reflog git push; tag `m5f`.

3. **Đã làm gì**  
   - Bước 0 (trước resume): sửa `hids_require_clean_git` / Makefile — commit `7d57586`, `ff6c0ab`.  
   - Bước 1 case A: archive T4 wrk2 không `-R` → `T4-khong-hop-le/`; `step1-case.txt` = `CASE=A`.  
   - Bước 2 G7 (đã chạy trước resume, không chạy lại): `validation/m5f-20261008/step2/g7a.log`, `g7cap.log`.  
   - Job `hids-m5f-resume`: `bash scripts/m5f_resume.sh` — xong 23:02:45, exit 0.  
   - `git-push-reflog.txt` trong thư mục validation.

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids && make build
   sudo systemd-run --unit=hids-m5f-resume --collect bash scripts/m5f_resume.sh
   # log: out/jobs/m5f-resume.log  status: out/jobs/m5f-resume.status
   python3 analysis/m5f_parse.py pgbench --target <TPS> validation/m5f-20261008/T3-R<pct>/<cond>/run<n>/pglog.*
   python3 analysis/m5f_parse.py wrk2 --target <RPS> validation/m5f-20261008/T4-R<pct>/<cond>/run<n>/wrk2.txt
   git tag m5f
   ```

5. **Kết quả**

   **Bước 1 — trường hợp A (T4 kịch trần không hợp lệ cũ):**  
   ```
   CASE=A
   ```
   Thư mục: `validation/m5f-20261008/T4-khong-hop-le/T4-wrk2-khong-rate/` (21 lượt wrk2 thiếu `-R`, không dùng cho RPS C0).

   **Bước 2 — G7a (nguyên văn tóm tắt từ `step2/g7a.log`):**  
   ```
   perf sys_enter: 1000001 | ban ghi: 1000001 | mat: 0 | perf-ban_ghi: 0
   zstd_level: 2
   ```

   **Bước 2 — G7-cap 2 tiến trình 60s (`step2/g7cap.log`):**  
   ```
   recs=74442243 mat=0
   ```

   **T4 kịch trần mới (wrk, 7 lượt × C0/C1/C2) — Requests/sec và cgroup CPU:**  
   ```
   T4 C0 run1 RPS=143291.70 cgroup_cpu_usec=230444115
   T4 C1 run1 RPS=123293.74 cgroup_cpu_usec=228815512
   T4 C2 run1 RPS=135511.54 cgroup_cpu_usec=229716187
   T4 C0 run2 RPS=142307.56 cgroup_cpu_usec=231244295
   T4 C1 run2 RPS=123870.10 cgroup_cpu_usec=227184519
   T4 C2 run2 RPS=136052.84 cgroup_cpu_usec=230974642
   T4 C0 run3 RPS=141741.97 cgroup_cpu_usec=231446035
   T4 C1 run3 RPS=123640.06 cgroup_cpu_usec=227837106
   T4 C2 run3 RPS=136381.26 cgroup_cpu_usec=230145103
   T4 C0 run4 RPS=143052.40 cgroup_cpu_usec=231071031
   T4 C1 run4 RPS=124921.22 cgroup_cpu_usec=228185475
   T4 C2 run4 RPS=137335.60 cgroup_cpu_usec=230513126
   T4 C0 run5 RPS=143002.42 cgroup_cpu_usec=230780607
   T4 C1 run5 RPS=124851.31 cgroup_cpu_usec=228727315
   T4 C2 run5 RPS=136607.31 cgroup_cpu_usec=230660516
   T4 C0 run6 RPS=142998.41 cgroup_cpu_usec=230933517
   T4 C1 run6 RPS=124148.22 cgroup_cpu_usec=228620758
   T4 C2 run6 RPS=136567.80 cgroup_cpu_usec=230618389
   T4 C0 run7 RPS=142330.98 cgroup_cpu_usec=231247369
   T4 C1 run7 RPS=124158.66 cgroup_cpu_usec=228033304
   T4 C2 run7 RPS=136468.02 cgroup_cpu_usec=230994432
   ```

   **T4 kịch trần — 95% CI trên Requests/sec:**  
   ```
   T4	C0	mean=142675.0629	std=556.5451	ci95_half=514.7369	n=7
   T4	C1	mean=124126.1871	std=599.2063	ci95_half=554.1933	n=7
   T4	C2	mean=136417.7671	std=556.6464	ci95_half=514.8306	n=7
   ```
   (C0 trung bình RPS ≈ 142675 → 25% ≈ 35669, 50% ≈ 71338; dùng làm mục tiêu T4-R.)

   **T3 kịch trần cấu hình mới (3 lượt × C0/C1/C2, pgtest cpuset 12–15, scale 50):**  
   ```
   T3 C0 run1 TPS=4943.3227 cgroup_cpu_usec=208971425
   T3 C1 run1 TPS=4049.4283 cgroup_cpu_usec=205624543
   T3 C2 run1 TPS=4845.5693 cgroup_cpu_usec=211902186
   T3 C0 run2 TPS=5016.8065 cgroup_cpu_usec=211325062
   T3 C1 run2 TPS=4012.7820 cgroup_cpu_usec=205708277
   T3 C2 run2 TPS=4909.2207 cgroup_cpu_usec=213299766
   T3 C0 run3 TPS=4934.5471 cgroup_cpu_usec=208793171
   T3 C1 run3 TPS=4038.2878 cgroup_cpu_usec=207953646
   T3 C2 run3 TPS=4885.3900 cgroup_cpu_usec=213361647
   ```
   (C0 trung bình TPS ≈ 4965 → 25% target_tps ≈ 1241.22, 50% ≈ 2482.45.)

   **Bảng `m5f_parse_sat.tsv` (T4: parser wrk2 trên output `wrk` → cột hop_ly = NGHI_NGO, đúng case A):**  
   Toàn bộ 21 dòng T4-sat có `hop_ly=NGHI_NGO`; 9 dòng T3-sat có `hop_ly=OK` (file: `validation/m5f-20261008/m5f_parse_sat.tsv`).

   **Git push (reflog `refs/remotes/github/master`, nguyên văn):**  
   ```
   === refs/remotes/github/master ===
   8b9c422 refs/remotes/github/master@{2026-10-08 21:30:04 +0700}: update by push
   2506d93 refs/remotes/github/master@{2026-10-08 20:30:04 +0700}: update by push
   5de5406 refs/remotes/github/master@{2026-10-08 20:19:10 +0700}: update by push
   ```

   **Output NGUYÊN VĂN `analysis/m5f_parse.py` — T3-R và T4-R (kèm cgroup CPU mỗi lượt):**  
   ```
   === T3-R25 C0 run1 target_tps=1241.223025 cgroup_cpu_usec=55656342 ===
   pgbench	74614	1243.7473	1.2002	1.0330	3.6560	32.8870	0.0624	0.1290	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C0 run2 target_tps=1241.223025 cgroup_cpu_usec=55588548 ===
   pgbench	74235	1237.5627	1.1955	1.0380	3.4380	15.1710	0.0604	0.1280	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C0 run3 target_tps=1241.223025 cgroup_cpu_usec=56327833 ===
   pgbench	74413	1240.4659	1.2689	1.0600	4.6100	25.9450	0.0684	0.1420	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C1 run1 target_tps=1241.223025 cgroup_cpu_usec=62386584 ===
   pgbench	74902	1248.5798	1.3171	1.1190	3.7080	46.8970	0.0816	0.1700	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C1 run2 target_tps=1241.223025 cgroup_cpu_usec=62567217 ===
   pgbench	74531	1242.5091	1.4003	1.1360	5.1460	63.5550	0.0968	0.1800	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C1 run3 target_tps=1241.223025 cgroup_cpu_usec=62653178 ===
   pgbench	74518	1242.0593	1.3823	1.1490	5.0070	28.6300	0.0743	0.1770	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C2 run1 target_tps=1241.223025 cgroup_cpu_usec=57467368 ===
   pgbench	74060	1234.5939	1.2275	1.0650	3.6100	17.1870	0.0612	0.1350	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C2 run2 target_tps=1241.223025 cgroup_cpu_usec=58018409 ===
   pgbench	74152	1236.1076	1.2724	1.0820	3.9770	30.7750	0.0699	0.1450	bo_qua=0;that_bai=0	OK	OK
   === T3-R25 C2 run3 target_tps=1241.223025 cgroup_cpu_usec=58211510 ===
   pgbench	74007	1233.6801	1.2745	1.0960	3.8270	12.3590	0.0612	0.1420	bo_qua=0;that_bai=0	OK	OK
   === T4-R25 C0 run1 target_rps=35668 cgroup_cpu_usec=65824924 ===
   wrk2	2138734	35645.1500	1.0100	0.9800	2.0600	5.3000	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C0 run2 target_rps=35668 cgroup_cpu_usec=65787756 ===
   wrk2	2138730	35645.0500	1.0100	0.9800	2.0600	3.3800	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C0 run3 target_rps=35668 cgroup_cpu_usec=65867741 ===
   wrk2	2138740	35645.6800	1.0100	0.9800	2.0600	3.4800	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C1 run1 target_rps=35668 cgroup_cpu_usec=74180877 ===
   wrk2	2138699	35644.7700	1.0300	1.0000	2.0900	3.6000	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C1 run2 target_rps=35668 cgroup_cpu_usec=74332928 ===
   wrk2	2138737	35645.3100	1.0300	1.0000	2.1200	4.7300	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C1 run3 target_rps=35668 cgroup_cpu_usec=74949086 ===
   wrk2	2138727	35644.9500	1.0300	1.0000	2.1000	4.7600	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C2 run1 target_rps=35668 cgroup_cpu_usec=69217109 ===
   wrk2	2138731	35645.2100	1.0200	0.9900	2.0800	3.5400	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C2 run2 target_rps=35668 cgroup_cpu_usec=68306594 ===
   wrk2	2130137	35501.8600	1.0100	0.9900	2.0500	3.4400	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R25 C2 run3 target_rps=35668 cgroup_cpu_usec=68711645 ===
   wrk2	2138726	35645.0900	1.0200	0.9900	2.0900	5.0300	nan	nan	non2xx=0;socket=0	OK	OK
   === T3-R50 C0 run1 target_tps=2482.44605 cgroup_cpu_usec=115301831 ===
   pgbench	149387	2490.1278	7.1851	1.3410	175.8300	321.8830	5.5221	169.5110	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C0 run2 target_tps=2482.44605 cgroup_cpu_usec=115276606 ===
   pgbench	148734	2479.2729	6.3433	1.3340	213.5570	404.7320	4.7355	207.0380	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C0 run3 target_tps=2482.44605 cgroup_cpu_usec=114863415 ===
   pgbench	148817	2480.5659	4.8693	1.3130	175.0290	240.1390	3.3262	168.9180	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C1 run1 target_tps=2482.44605 cgroup_cpu_usec=131845273 ===
   pgbench	149560	2493.0401	6.8362	1.5890	213.0300	336.5090	4.9793	206.7460	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C1 run2 target_tps=2482.44605 cgroup_cpu_usec=130850546 ===
   pgbench	148869	2481.5517	5.3849	1.5680	162.4560	245.4520	3.5509	157.4470	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C1 run3 target_tps=2482.44605 cgroup_cpu_usec=131370190 ===
   pgbench	149227	2487.5745	11.6831	1.6220	264.8760	452.8750	9.6583	258.8570	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C2 run1 target_tps=2482.44605 cgroup_cpu_usec=118992072 ===
   pgbench	149227	2487.3725	5.9901	1.3890	169.0660	298.7910	4.3187	162.5970	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C2 run2 target_tps=2482.44605 cgroup_cpu_usec=119810925 ===
   pgbench	149192	2486.7496	4.5964	1.3870	106.9780	279.9410	2.9417	100.3120	bo_qua=0;that_bai=0	OK	OK
   === T3-R50 C2 run3 target_tps=2482.44605 cgroup_cpu_usec=118791171 ===
   pgbench	148481	2475.0175	5.3033	1.3760	180.2110	280.0990	3.6867	173.7500	bo_qua=0;that_bai=0	OK	OK
   === T4-R50 C0 run1 target_rps=71337 cgroup_cpu_usec=124488820 ===
   wrk2	4277494	71290.7300	1.2700	1.2000	2.9700	7.9300	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C0 run2 target_rps=71337 cgroup_cpu_usec=124482556 ===
   wrk2	4277490	71291.6700	1.2600	1.2000	2.9500	6.0700	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C0 run3 target_rps=71337 cgroup_cpu_usec=123201067 ===
   wrk2	4277484	71291.6600	1.2600	1.2000	2.9600	8.3700	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C1 run1 target_rps=71337 cgroup_cpu_usec=140845961 ===
   wrk2	4277475	71290.3300	1.2600	1.1900	3.0100	6.5200	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C1 run2 target_rps=71337 cgroup_cpu_usec=140051391 ===
   wrk2	4277457	71291.1900	1.2600	1.1800	3.0500	8.4900	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C1 run3 target_rps=71337 cgroup_cpu_usec=138459234 ===
   wrk2	4260265	71004.7000	1.2600	1.1700	3.0200	9.2300	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C2 run1 target_rps=71337 cgroup_cpu_usec=130140793 ===
   wrk2	4277487	71291.7100	1.2700	1.2000	2.9800	5.7900	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C2 run2 target_rps=71337 cgroup_cpu_usec=128437162 ===
   wrk2	4277455	71291.2000	1.2700	1.2000	2.9800	7.1200	nan	nan	non2xx=0;socket=0	OK	OK
   === T4-R50 C2 run3 target_rps=71337 cgroup_cpu_usec=128406692 ===
   wrk2	4277478	71290.6600	1.2700	1.2000	3.0000	7.8300	nan	nan	non2xx=0;socket=0	OK	OK
   ```

6. **File dữ liệu**  
   - `/root/hids/validation/m5f-20261008/` (`T3/`, `T4/`, `T3-R25`, `T3-R50`, `T4-R25`, `T4-R50`, `m5f_parse_sat.tsv`, `m5f_parse.tsv`, `git-push-reflog.txt`, `step2/`, `T4-khong-hop-le/`, `T3-R-cau-hinh-cu/`)  
   - `/root/hids/out/jobs/m5f-resume.log`, `m5f-resume.status`  
   - `/root/hids/out/m5f-r021-parse-full.txt` (bản sao output parse cho báo cáo)

7. **Quyết định đã tự đưa ra**  
   - Resume chỉ chạy `m5f_resume.sh` (không lặp G7 bước 2).  
   - Parse T3-R/T4-R trong báo cáo: trích `target_*` từ `meta.txt` bằng regex (một dòng `target_tps=… cgroup_cpu_usec=…`), vì `awk -F=` trong script resume gộp sai trường.

8. **Cần kiến trúc sư quyết định**  
   - Sửa `scripts/m5f_resume.sh`: đọc `target_tps` / `target_rps` khi `meta.txt` một dòng (để `m5f_parse.tsv` có dữ liệu khi chạy job)?  
   - Case B (T4 kịch trần bằng wrk2 `-R`) có cần chạy riêng không?

9. **Việc người dùng cần làm tay**  
   - (không)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - `validation/m5f-20261008/m5f_parse.tsv`: 35 dòng chỉ có nhãn, không có output parse (lỗi trích target trong job resume; dữ liệu thô T3-R/T4-R vẫn đầy đủ).  
    - T4-R25 C2 run2: `toc_do_per_s` ≈ 35502 (dưới mục tiêu 35668) nhưng parser vẫn `dat_muc=OK`.  
    - O5 không làm (R019/R020).
