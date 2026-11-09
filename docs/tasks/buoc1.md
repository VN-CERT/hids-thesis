NHIỆM VỤ BƯỚC 1 — PHÂN TÍCH QUY NGUYÊN NHÂN BÁO ĐỘNG (mảnh ghép lõi của bài Q1 mới). (195, repo /root/hids). CHỈ ĐỌC + TÍNH trên dữ liệu đã có, KHÔNG chạy lại lab, KHÔNG chạm LAB-2 trên 201, KHÔNG sửa detector. Báo cáo R052, tag buoc1. Đây là phép thử QUYẾT ĐỊNH: nếu đạt → bài có kết quả dương (RQ5); nếu trượt → bài đứng trên luận đề nhẹ hơn. Tiêu chí đạt/trượt CHỐT TRƯỚC khi chạy (ghi vào R052 mục đầu, nguyên văn):
"ĐẠT nếu: (a) ≥80% cửa sổ báo động do liều tranh chấp (twin dưới D3-7, nền dưới D1/D3) được gán 'môi trường'; VÀ (b) ≥80% cửa sổ báo động B4 được gán 'hành vi'. Phép gán dùng quy tắc thống kê CỐ ĐỊNH (không học), định nghĩa dưới."

ĐỊNH NGHĨA QUY NGUYÊN NHÂN (viết script scripts/quy_nguyen_nhan.py, không sửa c5_score):
Với mỗi cửa sổ W của tid T vượt ngưỡng detector (dùng ngưỡng ngân sách 1% của bộ chiều đã có, hoặc T² bộ D):
1. PHẦN DƯ TỪNG THÀNH PHẦN: với mỗi thành phần c ∈ {rq, steal, irq, cpu, vol} và x_arr, x_inst, cpi — tính giá trị trung vị của c trong cửa sổ W, trừ trung vị nền của CHÍNH tid T (các cửa sổ nguon=nen, muc=0 của T, hoặc nếu T không có nền riêng thì nền lớp (cgroup,k) của T). Chuẩn hoá theo MAD nền. Ra vector phần dư z_c.
2. PHÂN LOẠI THÀNH PHẦN CHIẾM ƯU THẾ: thành phần có |z_c| lớn nhất.
   - Nếu ưu thế ở rq / steal / irq → ứng viên MÔI TRƯỜNG (scheduler/hypervisor/ngắt).
   - Nếu ưu thế ở cpu VÀ cpi tăng (z_cpi > 0) → MÔI TRƯỜNG (cache/mesh contention: nhiều chu kỳ/lệnh).
   - Nếu ưu thế ở vol / x_arr / x_inst VỚI cpi phẳng (|z_cpi| nhỏ) → HÀNH VI (tiến trình đổi nhịp/khối lượng, không phải máy chậm).
3. KIỂM ĐỒNG PHA QUẦN THỂ (quyết định — R045 cho thấy inst nhảy ×14 dưới D3-7 do spin, nhìn thành phần sẽ gọi nhầm là hành vi): trong cùng cửa sổ thời gian [start, stop] của W, đếm bao nhiêu tid KHÁC trong cùng cgroup (hoặc cùng VM) CŨNG có phần dư cùng dấu cùng thành phần vượt ngưỡng. 
   - Nhiễu môi trường đánh MỌI tid cùng cgroup/VM cùng lúc → nếu ≥ nửa số tid hoạt động trong cửa sổ cùng dịch chuyển → MÔI TRƯỜNG (ghi đè bước 2 nếu bước 2 nói hành vi).
   - Chỉ MỘT tid dịch chuyển, các tid khác bình thường → HÀNH VI.
   Ra nhãn cuối mỗi cửa sổ: MOI_TRUONG | HANH_VI, kèm lý do (thành phần ưu thế + số tid đồng pha).

CHẠY trên các tập báo động đã có (dùng nhãn lab1c + features_ghep):
A. Cửa sổ báo động của TWIN (N1) dưới D3-7 và D1-16 (benign bị báo động do tranh chấp) → kỳ vọng MÔI_TRUONG.
B. Cửa sổ báo động của nền (nguon=nen) dưới các mức D1/D3 → kỳ vọng MÔI_TRUONG.
C. Cửa sổ báo động của B4 (đào coin) dưới D3-7 → đây là test khó: B4 đốt CPU (có thể trông như môi trường) NHƯNG là hành vi tiến trình. Xem quy tắc đồng pha có tách đúng không (B4 chỉ 1 tid nhảy, nền không nhảy → HANH_VI).
D. Cửa sổ báo động của B1 (beacon) nếu có cửa sổ nào vượt ngưỡng (ít, vì 0/20) → kỳ vọng HANH_VI nếu bắt được.

R052: 
(1) tiêu chí đạt/trượt (nguyên văn trên);
(2) script quy_nguyen_nhan.py định nghĩa đầy đủ;
(3) BẢNG kết quả: mỗi tập A/B/C/D — số cửa sổ báo động, số gán MOI_TRUONG, số gán HANH_VI, tỉ lệ; phân tích theo thành phần ưu thế;
(4) KẾT LUẬN ĐẠT/TRƯỢT theo tiêu chí (a)+(b): twin/nền ≥80% môi trường? B4 ≥80% hành vi?;
(5) ví dụ: 5 cửa sổ twin@D3-7 (nhãn môi trường, thành phần ưu thế, số tid đồng pha) + 5 cửa sổ B4 (nhãn hành vi);
(6) nếu quy tắc đồng pha cần dữ liệu quần thể mà features_ghep không đủ (thiếu các tid khác cùng cửa sổ), ghi rõ "cần trích thêm tid nền đồng thời" và làm phần (2) thành phần-only, đánh dấu đồng-pha [cần dữ liệu].
Commit script + báo cáo (không .bin), tag buoc1. In R052 toàn văn. DỪNG. Không kết luận văn ngoài đạt/trượt theo số.
