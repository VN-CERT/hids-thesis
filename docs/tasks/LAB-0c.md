NHIỆM VỤ LAB-0c — máy 201 (nạn nhân): cập nhật collector lên tag m6c.3 và kiểm lại cổng trước khi thu dữ liệu lab. Lưu nguyên văn docs/tasks/LAB-0c.md, nhánh lab-collector. KHÔNG đụng 192.168.77.20, KHÔNG cài công cụ tấn công, KHÔNG mở LAB-1. Mọi ssh/scp cổng 22022. Chỉ bắt đầu khi máy test đã có tag m6c.3 (R035 xong).

File của kiến trúc sư (KHÔNG sửa; kiểm sha256 sau khi kéo mã và trước khi build, in vào báo cáo):
 - bpf/sys_enter.bpf.c   = 9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0
 - bpf/proc_events.bpf.c = 39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec
 - analysis/m5f_parse.py = 9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd
 - analysis/m6c_stats.py = 8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25
 - tools/coreclk.c       = 88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706
Sha sai, build/verifier lỗi, cổng không đạt, xung đột git: DỪNG, dán nguyên văn. Không sửa tiêu chí. Báo cáo chỉ in số.

0. Điều kiện: không collector nào đang chạy trên 201 (có unit từ LAB-0b thì dừng, ghi lại); `bpftool prog show | grep -c hids_` = 0; máy yên như LAB-0b khi chạy cổng; `kernel.perf_event_paranoid` ≤ 1 (sysctl -w nếu cần).

1. Kéo mã: `cd /root/collector && git fetch origin --tags && git checkout lab-collector && git merge --no-edit m6c.3` (giữ các commit riêng của nhánh lab; xung đột → DỪNG). In `git describe --tags`, `git rev-parse HEAD`, `git log --oneline -3`. Kiểm sha256 5 file. `make build`.

2. Thông tin máy và vPMC: `lscpu` (model, số vCPU), `uname -r`, `perf stat -e cycles:u,instructions:u -a -- sleep 1` (ra số = có vPMC; "<not supported>" = không có, ghi lại, vẫn tiếp tục). `bash scripts/freq_stamp.sh <cpu>` trên CPU của ứng dụng nạn nhân chính và CPU 0 (không rõ thì CPU 0 và CPU cuối). In nguyên văn.

3. G7a ×3 (-zstd-level 0): không truyền `-pmu` (mặc định, header phải `pmu: host`), `-pmu sample=20`, `-pmu on` → perf = bản ghi, mất 0. Nếu 201 không có vPMC: collector phải tự hạ `host` → `off` với cảnh báo (dán nguyên văn), còn `sample=20`/`on` phải từ chối chạy (dán nguyên văn) — khi đó LAB-1 sẽ chạy `host`.

4. G3 S1–S5 ×1 với `-pmu sample=20` (hoặc mặc định nếu không có vPMC): phần dư ≤ 500 ns; "CLAMPED & |dư| > 500 ns" = 0 / tổng; recursion_misses = 0; bảng kernel nguyên văn; tỉ lệ cờ PMU ≈ 5%. Lệch rq so bpftrace tổng chỉ in, không phải tiêu chí. In 5 dòng STEALCHECK (dạng tổng).

5. Chạy thử cấu hình 24 giờ 10 phút, đúng dòng lệnh `-datadir` của LAB-0b, thêm `-pmu sample=20` (hoặc mặc định nếu không vPMC): CPU collector % một lõi (cửa sổ ổn định), RSS, kernel drops, proc drops, số dòng host (cộng mọi đoạn, ≈ 600), hai cột PMU của 3 dòng host cuối, tỉ lệ cờ PMU trong .bin. Sau đó dừng collector; KHÔNG bật lại (chờ LAB-1).

6. Kết thúc: unit `hids-*`/`hidsrun-*` trống; `bpftool prog show | grep -c hids_` = 0; ứng dụng nạn nhân chạy bình thường. Viết LAB-0c-ketqua.txt (đã làm, output nguyên văn, file tạo, quyết định tự đưa ra, câu hỏi), commit nhánh lab-collector, push. DỪNG.
