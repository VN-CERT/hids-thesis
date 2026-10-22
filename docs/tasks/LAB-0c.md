NHIỆM VỤ LAB-0c — máy 201 (nạn nhân): cập nhật mã lên tag m6c.2 (mặc định `-pmu host`, STEALCHECK theo tổng, dấu tần số) và kiểm lại cổng trên máy nạn nhân. Lưu nguyên văn vào docs/tasks/LAB-0c.md. Báo cáo theo dãy báo cáo của lab (như LAB-0b). Không mở LAB-1 trong nhiệm vụ này.

File của kiến trúc sư (KHÔNG sửa; kiểm sha256 sau khi kéo mã và trước khi build, in vào báo cáo):
 - bpf/sys_enter.bpf.c   = 8b05464db597cfc471dc7af24ce651ef905751ebd80ec463b3863b7dd0263c35
 - bpf/proc_events.bpf.c = 39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec
 - analysis/m5f_parse.py = 9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd
 - analysis/m6c_stats.py = 8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25
 - tools/coreclk.c       = 88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706
Sha sai, build lỗi, verifier lỗi, cổng không đạt: DỪNG, dán nguyên văn. Không sửa tiêu chí. Báo cáo chỉ in số và output nguyên văn.

0. Điều kiện: không có collector nào đang chạy trên 201 (nếu có unit 24 giờ từ LAB-0b thì dừng và ghi lại). Máy yên như LAB-0b đã làm khi chạy cổng. Kernel phải sạch trước khi bắt đầu: `bpftool prog show | grep -c hids_` = 0.

1. Kéo mã: `git fetch --all --tags`, `git checkout m6c.2`, in `git describe --tags` (phải là `m6c.2`) và `git rev-parse HEAD`. Kiểm sha256 5 file. `make build`. In dòng header `pmu:` của một file .bin thử (bước 3) để xác nhận mặc định.

2. Dấu tần số: `bash scripts/freq_stamp.sh <cpu>` trên CPU của ứng dụng nạn nhân chính và trên CPU 0 (nếu không rõ CPU ứng dụng, dùng CPU 0 và CPU cuối). In nguyên văn (3 giá trị + trung vị + thời điểm). Ghi vào báo cáo số vCPU, model CPU (`lscpu`), kernel (`uname -r`), và vPMC có hay không (xem bước 3).

3. G7a ×2, không truyền `-pmu` (mặc định): perf = bản ghi, mất = 0. In header của file .bin: `pmu: host` nếu 201 có vPMC; nếu collector in cảnh báo mở perf fd lỗi và hạ về `pmu: off` thì dán nguyên văn cảnh báo (không phải lỗi; 201 không bật vPMC thì vẫn chạy).

4. G3 S1–S5 ×1 (wl + bpftrace như LAB-0b): phần dư ≤ 500 ns ở mọi kịch bản; dòng "so khoang CLAMPED va |phan du| > 500 ns" = 0 / tổng; recursion_misses = 0; bảng đối chiếu kernel (schedstat) in nguyên văn. Lệch rq so với bpftrace tổng KHÔNG phải tiêu chí (chỉ in). In 5 dòng STEALCHECK của 5 lần khởi động (dạng mới: `tong_vmw_ns ... ket_qua=DAT|LECH`).

5. Chạy thử cấu hình 24 giờ trong 10 phút, đúng dòng lệnh `-datadir` của LAB-0b (chỉ khác thời lượng): sau khi xong in CPU collector % một lõi (cửa sổ ổn định), RSS, kernel drops, proc drops, số dòng host (cộng mọi đoạn host-*.tsv.zst, kỳ vọng ≈600), và hai cột cuối của 3 dòng host cuối (số nếu `pmu: host`, `na` nếu off). Sau đó dừng collector; KHÔNG bật lại collector 24 giờ (chờ LAB-1).

6. Kết thúc: `systemctl list-units 'hids-*' 'hidsrun-*' --state=active` trống; `bpftool prog show | grep -c hids_` = 0; ứng dụng nạn nhân chạy bình thường. Viết báo cáo (mục: đã làm, output nguyên văn, file đã tạo, quyết định tự đưa ra, câu hỏi cho kiến trúc sư), commit theo quy ước của lab, DỪNG.
