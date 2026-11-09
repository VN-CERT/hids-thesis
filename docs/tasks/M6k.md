NHIỆM VỤ M6k — KIỂM SỐ TOÀN DIỆN trước khi viết bài (195, repo /root/hids). Chỉ ĐỌC + TÍNH, KHÔNG sửa detector/dữ liệu, KHÔNG chạm LAB-2 đang chạy trên 201. Báo cáo R051 (bảng kiểm số), tag m6k. Mục đích: đối chiếu MỌI con số sẽ vào bài với dữ liệu gốc trên đĩa, dứt điểm, để chat viết không bịa/không dùng số sai. Mỗi mục: in SỐ THẬT + nguồn file; nếu không có → ghi "KHÔNG CÓ TRÊN ĐĨA".

A. PHÁT HIỆN VẬT LÝ D1 — DVFS hay CPI? (QUAN TRỌNG NHẤT)
1. Từ R041-d ti_so_vs_nen_mo_rong.tsv (hoặc features_ghep), với các phiên BEN-D1-8/BEN-D1-16, lớp nginx + postgres dày: in trung vị tỉ số (so nền cùng lớp) của: inst (x_inst_med), cpi_med, cpu_med, cyc (x_cyc_med nếu có), dt_med. Tính tần số hiệu dụng f = x_cyc_med/cpu_med (chu kỳ/ns → GHz) cho nền vs D1, in tỉ số f. Mục tiêu: xác nhận f dưới D1 là ×~0,93 (GIẢM, cơ chế = CPI giảm) hay ×>1 (turbo). In số để chốt "CPI giảm" vs "DVFS".
2. Có dấu tần số thật (coreclk / chuỗi lệnh phụ thuộc) ghi trong phiên D1 không? grep coreclk/freq/GHz trong validation/lab1*/. Nếu có, in GHz_wall nền vs D1.

B. LỖI SỐ (xác nhận số đúng)
3. RSS production: in số RSS thật đầu/cuối từ LAB-PROD-1 (R039 nguồn, hoặc validation/prod1/suc-khoe hay status). 187→227 MiB đúng không, tỉ lệ thật (+21%? +7,9%?).
4. Dung lượng production: tổng GB thật của prod1 (.bin) và GB/ngày thật. 1,9 GB/ngày và 16 GB tổng — số nào đúng, có mâu thuẫn không (9 ngày × GB/ngày = tổng?).
5. Tốc độ bản ghi production: trung vị + p95 bản ghi/giây (từ suc-khoe.tsv hoặc tính 1,955 tỷ / thời gian thật). Xác nhận ~2500/s.
6. x_inst_med nginx worker (lớp k=6) qua 7 ngày: in giá trị THẬT từ troi_theo_ngay.tsv (ngày 1 vs ngày 7) — per-record median, kỳ vọng ~nghìn, KHÔNG phải 4,34×10⁶. Nếu troi_theo_ngay ghi 4,34e6 thì cột đó là gì (đọc header). Chốt số bất biến thật + đơn vị.

C. C5 — PMU-off và Δt-thô (có thể đổi câu kết)
7. T² bắt B4 (đào coin) CHỈ nhờ x_inst? Chạy T² bộ chiều KHÔNG có inst/cpi (ví dụ chỉ own/dt/arr — mô phỏng production PMU-off): `python3 analysis/c5_score.py --features out/c5-lab1c/features_ghep.tsv --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --train-until 1006289550843307 --chieu-phanra own_only --t2 --out out/c5-lab1c/t2-pmuoff-own`. In muc_D3-7 @0,01 — T² KHÔNG inst còn bắt B4 ở D3-7 không? (nếu KHÔNG → "T² bắt đào coin" chỉ đúng khi có PMU; production PMU-off thì không — câu kết phải nói rõ).
8. T² trên Δt THÔ (BASELINE dt_med/p90/iqr/cv): từ t2fair-v15-* đã có cột BASELINE — in BASELINE T² muc_D3-7 và phat_hien @0,01. T² trên dt-thô có bắt B4/B1 không, so với T² trên phân rã.
9. B4 có quota cgroup (throttled) không: đọc nhãn/script B4 trong lab1c — stress-ng --cpu có --timeout/quota gì; "throttled miner" đúng hay B4 chạy full. In dòng lệnh B4.
10. B4 inst u32 bão hoà/CLAMPED: trong features_ghep các cửa sổ B4, có cờ OVERFLOW/CLAMPED hay x_inst chạm trần u32 không.

D. SỐ ĐỀ CƯƠNG §6 — đo lại M6c-3 chưa (loại 3, cũ chưa trả lời)
11. E1-E4: in các số từ reports/R036 (E-series) nếu có: E1 Δt ratio, E2 steal %, E3 vol, E4 inst/CPI/cyc/freq. So với số đề cương (Δt ×3,67, inst 14170548-579, CPI 1,92/3,45/6,40). Ghi số nào từ R036 (M6d) vs đề cương (M5), cái nào là collector cuối.
12. Generator: open-loop hay closed-loop — grep wrk2/pgbench/wrk/-R/--rate trong scripts generator. In dòng lệnh generator (nginx + postgres). Xác nhận open-loop (-R tốc độ cố định) hay closed.
13. Cấu hình collector: grep ring buffer size, zstd level, số tracepoint IRQ (13 cặp?), ngưỡng steal fail-closed — trong bpf/*.c, scripts, docs. In các hằng số này.

R051: in bảng từng mục A-D với SỐ THẬT + nguồn; mục nào "KHÔNG CÓ TRÊN ĐĨA" ghi rõ. Mục A (DVFS/CPI) và C7 (PMU-off) in kết luận số. Commit báo cáo nhỏ, tag m6k. DỪNG. KHÔNG kết luận văn, chỉ số.
