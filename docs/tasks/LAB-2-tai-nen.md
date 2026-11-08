NHIỆM VỤ (nhỏ, 201) — ghi lại mức tải nền mỗi phiên LAB-2, để phân tích sau biết tấn công chạy dưới tải nào. Nối vào LAB-2 driver hoặc chạy bổ sung. KHÔNG đụng dữ liệu .bin đang thu, KHÔNG dừng collector.

Cách A — nếu driver LAB-2 CÒN đang chạy (thêm vào, không sửa phiên đã xong):
- Với MỖI phiên từ nay về sau, trong cửa sổ nhãn (phút 3→13), driver ghi mẫu tải mỗi 10 giây vào validation/lab2-<ngày>/<lop>/<run_id>/tai-nen.tsv, cột:
  t_mono_ns  loadavg_1m  cpu_pct_tong  cpu_pct_nginx_cgroup  cpu_pct_postgres_cgroup  n_stress_worker
  (loadavg từ /proc/loadavg cột 1; cpu_pct_tong từ /proc/stat delta; cpu theo cgroup từ cpu.stat usage_usec delta của scope docker nginx/postgres; n_stress = số tiến trình stress-ng-stream/--cpu đang chạy, đếm bằng pgrep).
- Cuối mỗi phiên, tính trung bình + p95 các cột, ghi một dòng vào validation/lab2-<ngày>/tai-nen-tomtat.tsv:
  run_id  lop  muc_tranh_chap  load_1m_tb  load_1m_p95  cpu_tong_tb%  cpu_nginx_tb%  cpu_pg_tb%  n_worker_tb

Cách B — nếu driver LAB-2 ĐÃ XONG (các phiên đã chạy, không đo lại được tải lúc đó):
- KHÔNG bịa số tải quá khứ. Thay vào đó: với mỗi phiên đã có .bin, ước tải nền GIÁN TIẾP từ chính dữ liệu đã thu — rec-export đếm số bản ghi/giây trung bình của cgroup nginx+postgres trong cửa sổ nhãn (tải cao → nhiều syscall/giây), và đọc mức tranh chấp từ run_id (D3-7 = 7 worker stream, D1-8 = 8 hog...). Ghi validation/lab2-<ngày>/tai-nen-uoc-tomtat.tsv:
  run_id  lop  muc_tranh_chap  ban_ghi_tren_giay_tb  ghi_chu("tai truc tiep khong do luc chay; uoc tu rec/s + muc")
- Ghi rõ đây là ƯỚC từ dữ liệu, không phải đo loadavg lúc chạy.

Chung: in bảng tóm tắt ra chat (một dòng/phiên: run_id, mức tranh chấp, tải nền). Mục đích cho kiến trúc sư: khi phân tích LAB-2, biết mỗi phiên tấn công chạy dưới tải nền nào, để so tấn công với benign song sinh CÙNG tải (tránh bẫy tải như R045). Commit bảng (không .bin). DỪNG. Không kết luận.
