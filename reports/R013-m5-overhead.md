# R013 — M5: overhead collector (đang chạy)

1. **Số báo cáo:** R013 — 2026-10-07 — M5 — git commit: `f725073` (script); tag `m5` **chưa gắn**
2. **Mục tiêu:** Đo overhead C0–C3 cho T1–T4; chi phí BPF; lưu `validation/m5-20261007/`.
3. **Đã làm:** `scripts/m5.sh`, `analysis/m5_summarize.py`; sửa scope PID, pgbench `-u postgres`, resume, timing `wait_pid_gone`.
4. **Lệnh:** `sudo systemd-run --unit=hids-m5-full --collect bash -c 'cd /root/hids && bash scripts/m5.sh >> out/jobs/m5.log 2>&1; echo done >> out/jobs/m5.status'`
5. **Kết quả (tạm):** T1 C0 (5 lần) ≈ **142 ns/syscall** (xem `out/jobs/m5.log`). Toàn bộ ma trận 80 lần chạy **chưa xong** tại thời điểm báo cáo.
6. **File:** `validation/m5-20261007/` (đang tăng), `out/jobs/m5.log`, `out/jobs/m5.status`
7. **Quyết định:** Bỏ qua `rec-stat` trên file 10M bản ghi; đọc `ban ghi doc duoc` / `mat` từ `collect.log`.
8. **Kiến trúc sư:** Không.
9. **Người dùng:** Kiểm tra `systemctl is-active hids-m5-full`; khi `done` trong `out/jobs/m5.status`, chạy lại báo cáo R013 đầy đủ (bảng + tag `m5`).
10. **Tiếp theo:** Hoàn tất job → `summary.csv` → cập nhật R013 + tag `m5`.

**CHƯA XONG:** hids-m5-full — tiến độ: T1 C0 xong (5/80 lần đo chính) — log `/root/hids/out/jobs/m5.log`
