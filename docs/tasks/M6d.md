NHIỆM VỤ M6d — máy 195 (uni-lms-app, 10.70.55.195): chốt bảng tranh chấp của Bài 1 bằng cách lặp E1, E3, E4-cache ≥ 3 lần/mức với binary cuối (m6c.3) và dấu tần số; E2 chạy lại với stress-ng `--cpu-method int64` (cần người ở vCenter). Lưu nguyên văn docs/tasks/M6d.md. Báo cáo R036, tag m6d. Không sửa BPF, không sửa m4.sh.

File kiến trúc sư (KHÔNG sửa; kiểm sha256 trước build và lúc viết báo cáo):
 - bpf/sys_enter.bpf.c = 9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0
 - bpf/proc_events.bpf.c = 39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec
 - analysis/m5f_parse.py = 9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd
 - analysis/m6c_stats.py = 8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25
 - tools/coreclk.c = 88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706
Build lỗi, cổng không đạt: DỪNG, dán nguyên văn. Báo cáo chỉ in số; mục "kỳ vọng" không phải tiêu chí. Mọi phép đo: 12 container dừng, máy yên, `docker start` lại khi xong (kể cả lỗi). Chốt READY/KHONG_READY, tự chạy lại lượt như M6c-1. `freq_stamp.sh` trước và sau MỖI mức; lệch > 2% thì ghi chú mức đó.

PHẦN A — chạy không cần người (một unit systemd-run `hids-m6d-a`, ~2 giờ):
 1. `make build`, kiểm sha256. Script mới `scripts/m6d_eseries.sh` gọi đúng các hàm/mức của `scripts/m4.sh` (calibrate khi máy rảnh → e1 → e3 → e4 cache), KHÔNG sửa m4.sh; chỉ thêm: lặp 3 lần/mức, freq_stamp, collector `-pmu on` cho E1/E4 (để có CPI khoảng đốt), `-pmu host` cho E3, giữ `.bin`, export rec-export ra TSV mỗi lượt. In nguyên văn các mức đã dùng (đọc từ m4.sh) vào báo cáo.
 2. E1 (co-runner cùng CPU, rq): các mức của m4.sh, 3 lần/mức. Bảng: mức → trung vị cpu_ns, rq_ns, steal_ns, irq_ns, vol_us, CPI của khoảng đốt; tỉ lệ so mức 0. Kỳ vọng: rq tăng theo mức, cpu và CPI gần như không đổi, steal ≈ 0.
 3. E3 (mạng, vol): các mức của m4.sh, 3 lần/mức. Bảng như trên. Kỳ vọng: vol tăng, cpu/rq/steal không đổi.
 4. E4-cache (`stress-ng --cache`, các mức worker của m4.sh; E4-stream đã có ở R034 không chạy lại): 3 lần/mức, `-pmu on`. Bảng + CPI. Kỳ vọng: inst không đổi, CPI tăng, GHz hiệu dụng ghi kèm.
 5. Mỗi bảng in cả 3 lần (không chỉ trung bình) và dấu tần số của mức. Dữ liệu `validation/m6d-<ngày>/`.

PHẦN B — E2 (steal), chạy khi người dùng ngồi vCenter (~1 giờ), khởi động riêng bằng `bash scripts/m6d_e2.sh`:
 1. Dùng đúng cơ chế E2 của m4.sh (chờ Enter sau mỗi lần người dùng đặt CPU limit trên vCenter cho VM 55.195-Test-NB), các mức limit đúng như m4.sh đã dùng (in ra màn hình: giá trị MHz từng mức, và "Unlimited" ở cuối), stress-ng co-runner dùng `--cpu-method int64` (khác m4.sh gốc; ghi rõ). 3 lần/mức; mỗi mức đo steal VM 10 giây bằng /proc/stat trước khi chạy như m4.sh vẫn làm.
 2. Script phải in rõ ràng, từng bước, bằng tiếng Việt: "Bây giờ đặt CPU limit = <X> MHz cho VM 55.195-Test-NB trên vCenter rồi bấm Enter"; cuối cùng "Đặt lại Unlimited rồi bấm Enter" và tự kiểm steal về ≈ 0 trước khi kết thúc. Nếu người dùng ngắt giữa chừng: in nhắc "ĐẶT LẠI UNLIMITED" và ghi trạng thái dở dang.
 3. Bảng: mức limit → steal VM đo được (%), trung vị steal_ns, cpu_ns, rq_ns, steal_off_ns, CPI; kỳ vọng: steal tăng theo mức, cpu/CPI không đổi.

PHẦN C — kết thúc (sau cả A và B): commit, tag m6d, push --all --tags; R036 + INDEX.md: bảng E1/E2/E3/E4-cache đầy đủ (3 lần + trung vị + dấu tần số), các mức, output nguyên văn, "Thay đổi ngoài phạm vi" (`git diff --stat m6c.3..HEAD -- scripts analysis internal cmd tools`), sha256 5 file, mục 8 câu hỏi. Nếu B chưa chạy được ngay: viết R036 phần A trước, ghi "E2 chờ", tag m6d sau khi B xong. DỪNG.
