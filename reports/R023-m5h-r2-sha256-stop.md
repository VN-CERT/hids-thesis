# R023 — M5h-r2: dừng bước 0 (sha256 BPF chưa khớp)

1. **Số báo cáo:** R023  
   **Ngày giờ:** 2026-10-09 00:10 (UTC+7)  
   **Mốc:** M5h (tiếp tục sau R022)  
   **Git commit:** `42bb893` (HEAD trước phiên); **không** tag `m5h`

2. **Mục tiêu**  
   Tiếp M5h với BPF sửa verifier (`14d065a6…`); commit M5h-r2; `make build`; bước 2–4; R023 kết quả đầy đủ; tag `m5h`.

3. **Đã làm gì**  
   - Kiểm sha256 `bpf/sys_enter.bpf.c` — **không khớp** bản kiến trúc sư M5h-r2.  
   - Không commit BPF; không `make build` cho bản mới; không chạy bước 2–4.  
   - Hoàn nguyên thay đổi lạ `bpf/steal_snap.bpf.c` (không thuộc M5h) để git sạch.

4. **Lệnh kiểm (người dùng / agent chạy lại sau khi chép file)**  
   ```bash
   cd /root/hids
   sha256sum bpf/sys_enter.bpf.c
   # mong đợi: 14d065a601787645b911b7a743e4d6d323757aff0b02bf3487a58fee5fed9d7d
   git add bpf/sys_enter.bpf.c
   git commit -m "M5h-r2: sua loi verifier (kien truc su)"
   make build
   ```

5. **Kết quả**  
   ```
   $ sha256sum bpf/sys_enter.bpf.c
   7618d9c118c89548b6acca9fa2b9e9ab81022707a81f86306c8fcd31f503e47a  bpf/sys_enter.bpf.c
   ```
   Mong đợi (M5h-r2):  
   `14d065a601787645b911b7a743e4d6d323757aff0b02bf3487a58fee5fed9d7d`

   Trên đĩa vẫn là bản M5h bước 0 (commit `25c66cb`, verifier fail R022). Không có log verifier mới trong phiên này.

6. **File dữ liệu**  
   - `/root/hids/docs/tasks/M5h.md`  
   - `/root/hids/reports/R022-m5h-bpf-verifier-stop.md` (giữ nguyên)

7. **Quyết định đã tự đưa ra**  
   - Dừng ngay bước 0 theo đặc tả (sha256 sai → không commit, không đo).

8. **Cần kiến trúc sư / người dùng**  
   - Chép đúng file `sys_enter.bpf.c` sha256 `14d065a6…` vào `/root/hids/bpf/sys_enter.bpf.c` trên máy đo.

9. **Việc người dùng cần làm tay**  
   1. Sao chép file BPF M5h-r2 từ kiến trúc sư vào `/root/hids/bpf/sys_enter.bpf.c` (ghi đè).  
   2. Chạy `sha256sum bpf/sys_enter.bpf.c` và xác nhận dòng hash `14d065a6…`.  
   3. Báo agent chạy lại «Tiếp tục M5h» (hoặc lặp lệnh tương tự).

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Sau khi sha256 đúng: commit M5h-r2 → `make build` → bước 2 G7/G3 → bước 3 đo → tag `m5h` → báo cáo R024 (hoặc R023 bổ sung nếu kiến trúc sư quy định một số R023 cho lần chạy thành công).
