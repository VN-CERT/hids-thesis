LAB-1 tiếp tục từ bước 3 theo quyết định của kiến trúc sư. Trước hết NỐI THÊM nguyên văn khối sau vào cuối docs/giao-thuc-lab1.md (không sửa phần trên), commit "LAB-1: phu luc 1.2 giao thuc (kien truc su)":

## Phụ lục 1.2 — 24/10/2026 (sửa liều cho máy 8 vCPU; bản 1.1 giữ nguyên ở trên)
Lý do: D3 với 12/22 worker trên 7 CPU là quá tải gấp 2–3 lần, thread nền dạt sang CPU 0 và chiếm chỗ wl (rq 4–5 ms ở L≥12, 0 ở L≤4). Đây là lỗi cỡ liều, không phải tính chất của tranh chấp bộ nhớ.
1. D3: mức worker = {0, 2, 4, 7} (không bao giờ vượt số CPU 1–7). Áp dụng cho cả §4b (benign dưới liều: D3 worker ∈ {4, 7}) và §5 (nền D3 ∈ {0, 4, 7}).
2. Mọi lần chạy wl trong liều, E5, B/N: dùng `-loops <mem_steps>` lấy từ một lần hiệu chuẩn lúc máy rảnh đầu buổi (cơ chế m4.sh), KHÔNG dùng chế độ tự hiệu chuẩn/tự kiểm dưới tải. Ô thiếu số liệu chạy lại tối đa 3 lần; bắt buộc đủ 3/3 lần mỗi mức.
3. D4/E5: không dùng docker exec. Chạy wl trong scope systemd: `systemd-run --scope -p CPUQuota=<200%|100%|50%> taskset -c 0 ./bin/wl -loops <mem_steps> mem 500` (mức "không giới hạn" = không có CPUQuota); collector lọc `-pid` của wl; nr_throttled/throttled_usec đọc từ cpu.stat của scope đó.
4. Tiêu chí "thành phần không kỳ vọng đổi < 10 %" đổi thành: |Δ trung vị thành phần không kỳ vọng| < max(10 % của trung vị thành phần kỳ vọng ở mức cao nhất, 100 µs). Tránh chia cho nền 0.

Sau đó: sửa script liều theo đúng 4 điểm trên (in diff), chạy lại D3, D4, E5 với tiêu chí phụ lục 1.2; D1 giữ kết quả đã đạt. Đạt → tiếp tục đúng LAB-1.md từ bước 4 (khởi động hids-lab1-driver). Không đạt → DỪNG, dán bảng. Ghi thêm vào LAB-1-ketqua.txt mục "chạy lại theo phụ lục 1.2".
