# R014 — M6a: irq trừ steal, steal_off_ns, bản ghi 56 byte

1. **Số báo cáo:** R014  
   **Ngày giờ:** 2026-10-07 16:45 (UTC+7)  
   **Mốc:** M6a  
   **Git commit:** `a7ef763` (tag `m6a`; mã BPF/công cụ `5121d30`)

2. **Mục tiêu**  
   Xác nhận lỗi irq/steal chồng trên E2 cũ; sửa đo irq; thêm `steal_off_ns` (56 byte); cập nhật công cụ; tự kiểm G7a/G7d và G3 S1–S5; chuẩn bị E2 lần 3 (không chạy E2).

3. **Đã làm gì**  
   - Dừng `hids-m5-full`; đổi tên `validation/m5-20261007` → `validation/m5-20261007-truoc-m6a` + README.  
   - Phân tích E2 trước sửa (CSV `validation/m4-20261007/E2/`).  
   - BPF: lưu vmw tại entry irq; thời lượng irq trừ Δsteal; `steal_off_ns` khi OFF-CPU; bản ghi 56 byte.  
   - Go: `recfmt`, `hids-collect`, `rec-stat`, `rec-check`, `rec-export`; sửa `irqState` userspace.  
   - Python: `analysis/m4.py` (`steal_off`, đếm CLAMPED theo mức E2); `scripts/bin_header.py` + G3 đọc `record_size`.  
   - Cập nhật `.cursor/rules/hids.mdc`.  
   - Tự kiểm: G7a, G7d, G3 S1–S5 → `validation/g3-20261007-m6a/`.

4. **Lệnh build, lệnh chạy**  
   ```bash
   cd /root/hids
   make build
   sudo bash scripts/g7.sh a 1000000
   sudo bash scripts/g7.sh d 1000000
   G3_OUTROOT=validation/g3-20261007-m6a sudo bash scripts/g3.sh
   ```
   (G3 dừng sau S5 vì không có container `qdrant`; S1–S5 đã ghi xong.)

5. **Kết quả**

   **5.1 — Xác nhận lỗi trước sửa (E2, CSV export mã 48 byte)**  

   Nguồn: `validation/m4-20261007/E2/{level}.csv`, `dt_ns` = khoảng giữa hai `ts_enter` liên tiếp, phần dư = `dt_ns − (cpu+steal+irq+rq+vol)`.

   | Mức | Bản ghi có dt | CLAMPED (cờ) | \|phần dư\| > 1 µs |
   |-----|---------------|--------------|-------------------|
   | 36000 | 1003 | 1 | 1 |
   | 24000 | 1003 | 0 | 0 |
   | 12000 | 1003 | 0 | 0 |

   Top irq (36000), bản ghi có CLAMPED:
   ```
   dt=404602158 cpu=9537842 steal=394005740 irq=394113942 rq=436201 vol_us=0 flags=5184 residual_ns=-393491567
   ```
   `steal` và `irq` cùng cỡ (~394 ms), `cpu` nhỏ, cờ CLAMPED — **khớp giả thuyết** đếm steal vừa trong irq vừa trong steal (cpu kẹp 0, tổng thành phần > Δt).  
   24000/12000: không có CLAMPED; irq lớn nhất vẫn nhỏ so với steal (ví dụ 12000: irq=787541 ns, steal=992483264 ns).

   **5.2 — G7a (N=1.000.000)**  
   ```
   1,000,001      raw_syscalls:sys_enter
   ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
   tong (perf - ban ghi): 0
   record_size: 56
   recursion_misses: tong 0
   ```

   **5.3 — G7d**  
   ```
   perf raw_syscalls:sys_enter: 1000001
   so ban ghi collector: 1000001
   hieu (perf - ban ghi): 0
   mat: 0
   ```

   **5.4 — G3 S1–S5** (`validation/g3-20261007-m6a/S*-ketqua.txt`)  

   G5 (phần dư Δt − tổng 5 thành phần, trừ FIRST), max và p99:

   | Scenario | n | p99 (ns) | max (ns) | \|du\|>1000 ns | CLAMPED trong cửa sổ |
   |----------|---|----------|----------|----------------|----------------------|
   | S1 | 300 | 0 | 0 | 0 | 0 |
   | S2 | 1000 | 494 | 500 | 0 | 0 |
   | S3 | 1000 | 490 | 500 | 0 | 0 |
   | S4 | 300 | 0 | 0 | 0 | 0 |
   | S5 | 1502 | 480 | 498 | 0 | 0 |

   Ngưỡng mục 5: phần dư ≤ 0,5 µs (500 ns) — **max ≤ 500 ns** trên S2/S3/S5.

   **Tổng `steal_off` S2 (máy rảnh, sleep):** `3961640` ns (~4,0 ms) trong cửa sổ đo; không bằng 0 tuyệt đối (có steal hypervisor trong lúc thread OFF-CPU).

   Bảng đối chiếu đầy đủ: xem từng `S*-ketqua.txt` (định dạng v3).

6. **File dữ liệu đã tạo**  
   - `/root/hids/validation/g3-20261007-m6a/S1-ketqua.txt` … `S5-ketqua.txt`  
   - `/root/hids/validation/g3-20261007-m6a/g7a.log`, `g7d.log`  
   - `/root/hids/out/g3-S*-1637*.bin` (collector G3)  
   - `/root/hids/validation/m5-20261007-truoc-m6a/README.md`

7. **Quyết định đã tự đưa ra**  
   - Thêm `scripts/bin_header.py` để G3/Python đọc `record_size` từ header (tránh đọc cố định 48 byte).  
   - Commit một phần dữ liệu M5 dừng giữa chừng kèm README (đánh dấu không dùng cho bài).  
   - G3 không sửa để bỏ G-real: thiếu `qdrant` thì thoát sau S5; S1–S5 đủ cho mục 5 nhiệm vụ.

8. **Cần kiến trúc sư quyết định**  
   - `steal_off` S2 ≈ 4 ms trên máy “rảnh”: chấp nhận là nhiễu VMware hay cần tinh chỉnh định nghĩa (a)/(b)?

9. **Việc người dùng cần làm tay — E2 lần 3**  
   1. Đảm bảo đã `make build` và tag `m6a` trên máy thu thập.  
   2. Chạy: `cd /root/hids && sudo bash scripts/m4.sh e2`  
   3. Giữ nguyên quy trình/script như M4 (tải liên tục, steal-probe, các mức 12000/24000/36000).  
   4. Sau khi xong: kiểm tra `summary.csv` / bảng phân rã có cột `steal_off`, `clamped_n` theo mức; so sánh CLAMPED và phần dư với E2 cũ (mục 5.1).  
   5. Khi ổn: chạy lại M5 (`scripts/m5.sh`) trên mã M6a.

10. **Lỗi còn tồn tại, việc tiếp theo**  
    - M5 chưa chạy lại; dữ liệu cũ trong `validation/m5-20261007-truoc-m6a/`.  
    - G3 G-real / G-irq không chạy (không có container `qdrant`).  
    - E2 lần 3 chưa thu — chờ người dùng mục 9.
