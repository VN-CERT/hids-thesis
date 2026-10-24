# Giao thức LAB-1 — chốt TRƯỚC khi ghi dữ liệu đánh giá

> Mốc commit của file này là bằng chứng rằng phạm vi và tiêu chí LAB-1 được chốt trước khi thấy dữ liệu.
> KHÔNG sửa sau khi đã nhìn kết quả. Mọi thay đổi ghi rõ lý do + ngày, giữ bản cũ.
> Phiên bản 1.1 — 22/10/2026 (1.0 cùng ngày: 21 ngày benign; 1.1 rút còn 7 ngày và thêm §4b vì LAB-1 chỉ phục vụ C5 của Bài 1, không phải ước báo động giả production). Máy: hids-collector (55.201 / 192.168.77.10), 8 vCPU Xeon Gold 6330N, nhánh lab-collector.
> Thừa kế `docs/giao-thuc-danh-gia.md` v0.2, `docs/thu-vien-lieu-tranh-chap.md` v0.2, `docs/danh-muc-tan-cong.md` v0.2. File này chỉ THU HẸP phạm vi cho LAB-1; không thay tiêu chí nào của ba tài liệu đó.

## 1. LAB-1 làm gì (và KHÔNG làm gì)

LAB-1 là lần đầu ghi dữ liệu thật trên máy nạn nhân. Mục tiêu: (a) chứng minh đường ống thu benign chạy liên tục nhiều tuần không mất, không phình; (b) lấy bộ liều tranh chấp D1–D4 + E5 có nhãn trên 8 vCPU (đặc trưng hoá tác động lên 5 thành phần — đầu vào cho C5 của Bài 1); (c) lấy HAI cặp tấn-công-đổi-nhịp / song-sinh-benign (B1/N1 và B4/N4) để Bài 1 có đủ dữ liệu cho hình trung tâm C5.

LAB-1 KHÔNG: không chạy lớp A, không chạy B2/B3/B5/B6, không chạy lớp C, không dựng lại CVE của LID-DS, không đụng 192.168.77.20 cho phần benign/liều (B1/B4 chạy nội bộ trên 201, xem §5). Toàn bộ danh mục tấn công đầy đủ và mọi phép thu trên hạ tầng thật nằm ngoài Bài 1.

## 2. Thu benign (phần chạy dài)

- **Nguồn:** hai container sẵn có trên 201 — `lab0-postgres` (PostgreSQL, cgroup đã biết) và `lab0-nginx` (nginx, trả file 4 KB). Collector lọc theo cgroup của hai container này (hai cờ `-cgroup`), KHÔNG lọc toàn máy.
- **Cấu hình collector:** đúng dòng lệnh `-datadir` của LAB-0b, thêm `-pmu sample=20`. Nén zstd mặc định, `-rb-poll` mặc định, xoay file theo giờ.
- **Tải benign:** một generator (§2b) chạy hai container ở mức tải THẤP, biến thiên nhẹ theo giờ trong ngày (nhịp sinh hoạt), KHÔNG kịch trần — mục tiêu là hành vi "bình thường" để ước báo động giả, không phải đo overhead.
- **Thời lượng:** 7 ngày liên tục. Nền này là để huấn luyện chuẩn hoá của C5 và làm nền chèn tấn công có nhãn, KHÔNG phải để công bố tỷ lệ báo động giả production. Nếu generator hoặc collector chết giữa chừng, systemd khởi động lại và ghi mốc gián đoạn; không coi là hỏng trừ khi mất > 5% thời gian.
- **Tiêu chí thu benign (chốt trước):**
  1. kernel drops = 0 và proc drops = 0 trên toàn bộ thời gian (kiểm từ status.tsv mỗi giờ).
  2. Tỉ lệ bản ghi không-FIRST có cờ PMU ∈ [4,0 %, 6,0 %] (sample=20 ⇒ kỳ vọng 5 %).
  3. CPU collector trung vị ≤ 3 % một lõi trên cửa sổ giờ (8 vCPU; kỳ vọng ~1 %).
  4. RSS collector không tăng đơn điệu quá 20 % giữa ngày 1 và ngày 7 (kiểm rò bộ nhớ).
  5. Không có khoảng mù > 60 s nào mà cả hai cgroup vắng bản ghi trong giờ generator đang chạy.
- **Chia dữ liệu (theo giao thức đánh giá §4):** mốc cắt = hết ngày 5. Ngày 1–5 = huấn luyện/validation; ngày 6–7 = kiểm tra. Mọi chuẩn hoá và ngưỡng của C5 tính CHỈ trên ngày 1–5.

## 2b. Generator tải benign (Cursor tạo nếu chưa có)

`scripts/lab1_benign_gen.sh <thu_muc_log>`: vòng lặp vô hạn, mỗi "nhịp" 5 phút:
- nginx: `taskset -c 0-3 wrk2 -t2 -c16 -R <rps> -d290s --latency http://127.0.0.1:18080/file4k.bin`, với `rps` = một trong {20, 50, 120, 200} chọn theo giờ (ban đêm thấp, ban ngày cao), có jitter ±20 %.
- postgres: `scripts/lab0-load-postgres.sh <tps> 290 <thu_muc_log>` với `tps` = một trong {15, 40, 100} theo giờ. (Script này đã VACUUM+CHECKPOINT trước mỗi lượt theo LAB-0b.)
- Hai tải chạy xen kẽ hoặc song song đều được; ghi mốc mono_ns đầu/cuối mỗi nhịp vào `<thu_muc_log>/nhip-benign.tsv`.
- Dừng sạch khi nhận SIGTERM (systemd stop).

## 3. Bốn trục liều D1–D4 (có nhãn, §1 thư viện liều)

Chạy TRƯỚC khi bắt đầu thu benign dài (để đặc trưng hoá), mỗi liều 60 s, lượng công việc nạn nhân cố định (dùng `wl` lượng cố định ghim CPU 0, cùng CPU với container). Mỗi liều ghi một dòng `lab/nhan-lieu.tsv` theo định dạng §4 thư viện liều.

- **D1 (rq):** stress-ng --cpu N ghim CPU 0, N ∈ {0,1,2,3,4}. Oracle: rq collector tăng theo N; đối chiếu bpftrace @rq.
- **D2 (steal):** CẦN vCenter (PowerCLI, khối finally gỡ limit). **LAB-1 KHÔNG chạy D2** (cần người ở vCenter; xếp vào nhiệm vụ E2 riêng của máy test). Ghi "D2 hoãn" vào nhãn.
- **D3 (bộ nhớ):** stress-ng --stream và --cache, worker ∈ {0,4,12,22} trên CPU 1–7. Oracle: CPI từ `-pmu on` trên khoảng đốt của wl (201 CÓ vPMC — LAB-0c xác nhận). Thành phần kỳ vọng: cpu phình, rq/steal ≈ 0.
- **D4 (throttle):** chạy wl trong container `--cpus` ∈ {không giới hạn, 2, 1, 0.5}. Oracle: nr_throttled, throttled_usec trong cpu.stat (đã nằm trong luồng host mỗi giây). Thành phần kỳ vọng: throttle rơi vào rq, steal = 0.
- Mỗi trục lặp 3 lần/mức. Mỗi khối có freq_stamp CPU 0 trước và sau.
- **Tiêu chí (chốt trước):** với mỗi trục, thành phần kỳ vọng phải đổi ĐƠN ĐIỆU theo mức (hệ số tương quan hạng Spearman giữa mức và trung vị thành phần ≥ 0,9 cho D1-rq, D3-cpu, D4-rq); thành phần KHÔNG kỳ vọng (ví dụ cpu trong D1, steal trong D4) đổi < 10 % giữa mức thấp nhất và cao nhất. In số, không tự kết luận nếu không đạt — dừng và báo.

## 4. E5 — throttle chi tiết (§2 thư viện liều)

- wl lượng cố định trong container, mỗi mức D4 chạy 60 s, 3 lần.
- Đo: Δrq collector so với Δthrottled_usec trong cpu.stat (kỳ vọng tương quan mạnh); kiểm steal ≈ 0.
- **Tiêu chí:** Pearson giữa Δrq và Δthrottled_usec trên các mức ≥ 0,8; |steal trung vị| < 2 % của rq ở mọi mức. In nguyên văn.

## 4b. Benign dưới liều (đường "báo động giả theo mức tranh chấp" của C5)

Generator chạy bình thường (hai dịch vụ), KHÔNG tấn công, áp liều lên chính máy: D1 N ∈ {2, 4} (stress-ng ghim CPU 0, cùng CPU container) và D3 worker ∈ {12, 22} (stress-ng --stream CPU 1–7). Mỗi mức 20 phút × 3 lần, collector `-datadir -pmu sample=20` lọc 2 cgroup, nhãn benign, cột `muc_tranh_chap` ghi rõ. Cùng với nền 7 ngày (mức 0), đây là trục hoành của hình trung tâm C5. Tiêu chí: mỗi phiên có đủ bản ghi của cả hai cgroup liên tục (không khoảng mù > 60 s); oracle liều (rq hoặc CPI của dịch vụ) tăng theo mức.

## 5. Hai cặp tấn-công/song-sinh (cho C5)

Chạy trên các phiên ngắn riêng (20 phút mỗi lần) trong buổi dựng, trước khi khởi động nền 7 ngày; ghi rõ phiên nào. Mỗi mục chạy ở 3 mức tranh chấp (dùng D1 hoặc D3 làm nền): không / vừa (N=2 hoặc 12 worker) / nặng (N=4 hoặc 22 worker).

- **B1 (beacon C2) + N1 (poll hợp lệ):** cả hai dùng cùng một client HTTP tự viết trên 201 gọi `http://127.0.0.1:18080/file4k.bin` theo chu kỳ {10 s, 60 s, 300 s} có jitter 0–50 %. B1 = tiến trình "lạ" (tên khác, không thuộc dịch vụ), nhãn trong cửa sổ tấn công; N1 = cùng chu kỳ nhưng là health-check "hợp lệ", nhãn benign, cột `song_sinh_cua=B1`. KHÔNG cần 192.168.77.20 (beacon nội bộ tới chính nginx của mình; oracle = log client + bản ghi connect trong luồng syscall).
- **B4 (đào coin hãm tốc) + N4 (nén log định kỳ):** B4 = stress-ng --cpu 1 bật 2 s / nghỉ 20 s trong cửa sổ tấn công; N4 = `gzip` một file log định kỳ cùng nhịp bật/nghỉ, nhãn benign, `song_sinh_cua=B4`. Oracle: tiến trình chạy đúng chu kỳ.
- Mỗi lần chạy ghi một dòng `lab/nhan-tan-cong.tsv` theo §5 danh mục tấn công (mốc mono_ns đầu/cuối, oracle_ket_qua).
- **Tiêu chí LAB-1 (chốt trước):** chỉ cần dữ liệu GHI ĐÚNG — mỗi cửa sổ B/N có ≥ 20 chu kỳ bản ghi của tiến trình tương ứng; mốc nhãn khớp bản ghi trong ±1 s. KHÔNG chấm điểm phát hiện ở LAB-1 (đó là việc của C5 sau khi có đủ dữ liệu). Detector C5 (§6) chạy như kiểm tra khói, không phải để kết luận.

## 6. Detector C5 — kiểm tra khói ở LAB-1

- `analysis/detector_c5.py` (chốt đặc trưng + điểm đánh đổi TRƯỚC khi thấy dữ liệu, xem đầu file đó).
- Ở LAB-1 chỉ chạy để xác nhận: (a) đọc được TSV rec-export; (b) tính được điểm bất thường cho cả baseline Δt-thô và bản phân rã; (c) trên một cửa sổ B1 chậm 300 s, bản phân rã cho điểm ≥ baseline (kiểm khói, không phải tiêu chí thống kê). In bảng điểm, không chọn ngưỡng theo kết quả.

## 7. Ghi nhãn, lưu trữ

- `lab/nhan-lieu.tsv`, `lab/nhan-tan-cong.tsv`, `<thu_muc_log>/nhip-benign.tsv` theo định dạng của ba tài liệu v0.2.
- Dữ liệu .bin KHÔNG vào git (theo quy ước dự án). Chỉ tóm tắt + nhãn + status.tsv vào git.
- Mọi kết quả kiểm in ra file .txt dưới `validation/lab1-<ngày>/`.

## 8. Mối đe doạ tới tính hợp lệ (bổ sung cho LAB-1)

- Một máy nạn nhân, hai dịch vụ — đủ cho luận điểm cơ chế của C5, không đại diện cho đội máy thật.
- Beacon/benign song sinh chạy nội bộ (không qua 192.168.77.20) nên không có dấu vết mạng liên-máy; ghi rõ, và lab tấn công đầy đủ sau sẽ chạy qua .20.
- 7 ngày trên một máy lab không phải tỷ lệ báo động giả production; bài ghi rõ "đo trên nền lab 7 ngày".
