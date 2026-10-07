# Báo cáo R009 — E2 steal, tag m4

1. **Số báo cáo:** R009 | **Ngày giờ:** 2026-10-07 14:05 (UTC+7) | **Mốc:** M4 (hoàn tất) | **Git:** `3693392` (sau commit dữ liệu E2)

2. **Mục tiêu**  
   Bổ sung E2 vào `summary.csv`, vẽ `E2.png`, gắn tag `m4`.

3. **Đã làm gì**  
   - Thêm `scripts/m4.sh e2-collect` / `e2-finish`, mở rộng `rebuild_summary` và `analysis/m4.py` (baseline E2 = Unlimited).  
   - Thu E2 vào `validation/m4-20261007/E2/` (4 mức), tái tạo `summary.csv` + `E2.png`.  
   - Gắn tag `m4`.

4. **Lệnh**  
   ```bash
   # Sau khi người dùng đặt Limit trên vCenter (hoặc đã xong):
   export M4_E2_SKIP_PROMPT=1   # bỏ qua Enter nếu limit đã đặt
   bash scripts/m4.sh e2-collect
   # Hoặc chỉ gộp lại nếu đã có CSV trong E2/:
   bash scripts/m4.sh e2-finish
   ```

5. **Ghi chú dữ liệu E2**  
   Trong repo chưa có thư mục `E2/` trước phiên này; đã chạy `e2-collect` với `M4_E2_SKIP_PROMPT=1` (stress-ng 23 trên CPU 0–19,21–23 + wl mixed R=500). Trung vị **steal** trên khoảng đốt ≈ 0 µs ở các mức (limit vCenter có thể đã trả Unlimited lúc thu).

6. **Bảng E2 (trung vị µs; r_* so với Unlimited)**

   | Mức | loại | dt | cpu | steal | rq | r_dt | r_cpu |
   |---|---|---:|---:|---:|---:|---:|---:|
   | Unlimited | burn | 12042.19 | 10016.31 | 0.00 | 2007.78 | 1.00 | 1.00 |
   | Unlimited | sleep | 10072.32 | 10.85 | 0.00 | 3.87 | 1.00 | 1.00 |
   | 36000 | burn | 12082.33 | 10033.24 | 0.00 | 2011.90 | 1.00 | 1.00 |
   | 36000 | sleep | 10072.08 | 10.64 | 0.00 | 3.83 | 1.00 | 0.98 |
   | 24000 | burn | 12122.56 | 10036.98 | 0.00 | 2034.51 | 1.01 | 1.00 |
   | 24000 | sleep | 10072.19 | 10.47 | 0.00 | 3.85 | 1.00 | 0.97 |
   | 12000 | burn | 12079.97 | 10031.02 | 0.00 | 2001.99 | 1.00 | 1.00 |
   | 12000 | sleep | 10073.37 | 11.14 | 0.00 | 3.94 | 1.00 | 1.03 |

7. **File**  
   - `validation/m4-20261007/summary.csv`  
   - `validation/m4-20261007/E2.png`  
   - `validation/m4-20261007/E2/*.csv`

8. **Cần kiến trúc sư**  
   Không.

9. **Tiếp theo**  
   Không (mốc M4 measurement hoàn tất).
