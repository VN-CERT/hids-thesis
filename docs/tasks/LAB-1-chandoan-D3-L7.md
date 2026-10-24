LAB-1: chẩn đoán rq ở D3 L=7 trước khi quyết; KHÔNG sửa tiêu chí. Container lab0-* dừng, cùng wl -loops và stress-ng như lần chạy lại, hai phiên 60 s ở L=7 và L=6, KHÔNG collector:
 (a) Kiểm ghim sau khi stress-ng khởi động: for p in $(pgrep stress-ng); do echo "$p $(cat /proc/$p/comm) psr=$(ps -o psr= -p $p) aff=$(taskset -cp $p | awk -F: '{print $2}')"; done — tiến trình nào psr=0 hoặc aff chứa 0 là lọt.
 (b) Ai chạy trên CPU 0 ngoài wl, chạy song song 60 s: bpftrace -e 'tracepoint:sched:sched_switch /cpu == 0/ { if (@t) { @oncpu_ns[args->prev_comm] = sum(nsecs - @t); } @t = nsecs; } interval:s:60 { exit(); }' — in top 10 comm theo @oncpu_ns và tổng của mọi comm khác wl chia 60 s (phần trăm).
 Ghi hai bảng (L=7, L=6) vào validation/lab1-20261024/lieu/D3-chandoan.txt. Quyết định tự động, ghi thành Phụ lục 1.3 nối vào cuối docs/giao-thuc-lab1.md (commit riêng, nêu số đo):
  - Có worker stress-ng lọt vào CPU 0: sửa cách ghim (bọc ngoài bằng taskset -c 1-7, kiểm lại bằng (a)), giữ mức {0,2,4,7}, chạy lại D3.
  - Không lọt, tổng comm khác wl trên CPU 0 ở L=6 < 1 % nhưng L=7 ≥ 1 %: mức D3 = {0,2,4,6}, ghi tên comm chiếm nhiều nhất ở L=7 (bão hoà toàn bộ 7 CPU kéo việc nhà hệ thống về CPU 0), chạy lại D3 với {0,2,4,6}; §4b dùng D3 ∈ {4,6}, §5 nền D3 ∈ {0,4,6}.
  - L=6 cũng ≥ 1 %: DỪNG, dán hai bảng.
 D3 đạt → D4, E5, rồi đúng LAB-1.md từ bước 4 (driver). Ghi mục "chẩn đoán D3 L=7" vào LAB-1-ketqua.txt.
