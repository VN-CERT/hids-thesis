Bối cảnh: máy này (hids-collector, card cô lập 192.168.77.10) là NẠN NHÂN trong lab HIDS. Repo /root/collector ở nhánh lab-collector, đã build, sha256 BPF khớp kiến trúc sư. KHÔNG cài hay chạy công cụ tấn công trên máy này. KHÔNG đụng máy 192.168.77.20 trong nhiệm vụ này. Mọi lệnh ssh/scp giữa các máy dùng cổng 22022.

NHIỆM VỤ LAB-0 — dựng và kiểm máy nạn nhân. Lưu nguyên văn vào docs/tasks/LAB-0.md, làm việc trên nhánh lab-collector.

1. Môi trường: nproc; uname -r (phải 6.8); journalctl -k -b | grep -c vmware-stealtime (phải = nproc); lscpu | grep 'Model name'; ip -br addr (phải thấy 192.168.77.10). Thiếu điều kiện nào thì DỪNG, báo.

2. Kiểm collector chạy đúng trên máy này (8 vCPU): trước khi chạy, bpftool prog show | grep -c hids_ phải bằng 0. Chạy G7a (-zstd-level 0) và G3 S1–S5 bằng scripts/g7.sh và scripts/g3.sh. Yêu cầu như trên máy test: G7a perf = bản ghi, mất = 0; G3 phần dư ≤ 0,5 µs, recursion_misses = 0; in bảng đối chiếu với kernel. Không đạt: DỪNG, dán nguyên văn.

3. Cài tải benign (qua card quản lý/mạng thật còn trên máy này): nginx, postgresql, docker.io, stress-ng.

4. Dựng hai container tải, chưa chạy tải: một nginx phục vụ file 4 KiB ở cổng 18080; một postgres chạy pgbench -i -s 50. Ghi tên hai container.

5. Tạo thư mục /srv/hids-data/hids-collector/.

6. Viết LAB-0-ketqua.txt: kết quả bước 1, kết quả G7a và G3 bước 2 (kèm bảng đối chiếu kernel), phiên bản các gói, tên hai container. Commit lên nhánh lab-collector. DỪNG.
