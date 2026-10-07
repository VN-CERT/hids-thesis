NHIỆM VỤ M5 — chạy lại toàn bộ trên mã m6a. Dùng nguyên Phần B trong docs/tasks/M5.md, với các điều chỉnh:
1. Chạy từ commit sạch, từ tag m6a trở về sau. Không dùng dữ liệu T1 cũ (đã nằm ở validation/m5-20261007-truoc-m6a). Lưu kết quả vào validation/m5-<ngày>-m6a/.
2. C3: stress-ng --cpu 8 --cpu-method int64 (chỉ tranh chấp CPU, không gây nhiễu bộ nhớ).
3. Các container thật đã được dừng sẵn; danh sách ở /root/containers-da-dung.txt. Khi M5 kết thúc (kể cả khi lỗi giữa chừng): docker start lại đúng danh sách đó.
4. Cập nhật summary.csv sau MỖI tải chạy xong, không chỉ ở cuối, để nếu dừng giữa chừng vẫn còn số liệu.
5. Chạy tách khỏi phiên (systemd-run), báo tiến độ theo workflow.mdc. Khi xong: gắn tag m5; viết R016 gồm bảng mỗi tải (C0–C3, trung bình ± sd, overhead %), bảng chi phí từng chương trình BPF, số bản ghi/giây, dung lượng/giờ, số mất; in nguyên văn summary.csv. DỪNG.
Ghi vào STATE.md, mục "Chạy lại cho bài báo": E2 bản cuối dùng stress-ng --cpu-method int64 cho tải nền (lần 3 dùng phương pháp mặc định, có thể gây tranh chấp bộ nhớ làm cpu trung bình dao động 1–9%).
