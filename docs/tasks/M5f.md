NHIỆM VỤ M5f — lưu nguyên văn vào docs/tasks/M5f.md. Làm ĐÚNG từng bước, không tự sáng tạo thêm.

1. Hoàn lại collector: khôi phục các file Go của phần ghi/nén (cmd/hids-collect và internal/ tương ứng) về đúng nội dung ở commit 7ff5b73 (tag m5d) bằng git checkout 7ff5b73 -- <các file đó>. Bỏ hẳn chế độ /dev/shm. GIỮ các sửa đổi trong scripts/. make build; commit; git status phải sạch.
2. Kiểm đường có nén (mặc định): G7a; và G7-cap mức 2 tiến trình chạy 60 giây. Yêu cầu perf = bản ghi, mất = 0.
3. Cài wrk2: apt install -y build-essential libssl-dev zlib1g-dev git; git clone https://github.com/giltene/wrk2 /opt/wrk2; cd /opt/wrk2 && make; cp wrk /usr/local/bin/wrk2.
4. Lệnh tải:
   - T4-R: wrk2 -t4 -c64 -d60s -R <tốc độ mục tiêu> --latency http://<nginx>/<file 4KiB>, client ghim CPU 16-19, lưu output vào wrk2.txt của lượt.
   - T3-R: pgbench -R <TPS mục tiêu> -c 16 -j 4 -T 60 -l --log-prefix=<thư mục lượt>/pglog, client ghim CPU 16-19.
   - Tốc độ mục tiêu: 25% và 50% của thông lượng C0 kịch trần đo trong cùng đợt.
5. Tính số liệu CHỈ bằng analysis/m5f_parse.py (KHÔNG sửa file này):
   python3 analysis/m5f_parse.py --header pgbench --target <TPS> <thư mục lượt>/pglog.*
   python3 analysis/m5f_parse.py --header wrk2 --target <RPS> <thư mục lượt>/wrk2.txt
   Lượt nào có cột hop_ly = NGHI_NGO hoặc dat_muc = LECH: chạy lại MỘT lần; vẫn vậy thì giữ nguyên và ghi rõ.
6. Đo (dừng container thật; máy không chạy việc nào khác; từ commit sạch):
   - T4 kịch trần như M5e (wrk, 7 lượt, xen kẽ C0, C1, C2).
   - T3-R và T4-R ở 25% và 50%: C0, C1, C2, 3 lượt, xen kẽ. Ghi thêm CPU của cgroup tải.
   Lưu vào validation/m5f-<ngày>/.
7. In giờ git push: git reflog show --date=iso cho từng ref trong refs/remotes/github/.
8. Gắn tag m5f. Viết R021 bằng công cụ sửa file: kết quả bước 2; bảng T4 kịch trần; dán NGUYÊN VĂN mọi dòng output của m5f_parse.py, kèm CPU của cgroup mỗi lượt; giờ git push. DỪNG.
