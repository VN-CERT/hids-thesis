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

## Phụ lục 1.2 — 24/10/2026 (sửa liều cho máy 8 vCPU; bản 1.1 giữ nguyên ở trên)
Lý do: D3 với 12/22 worker trên 7 CPU là quá tải gấp 2–3 lần, thread nền dạt sang CPU 0 và chiếm chỗ wl (rq 4–5 ms ở L≥12, 0 ở L≤4). Đây là lỗi cỡ liều, không phải tính chất của tranh chấp bộ nhớ.
1. D3: mức worker = {0, 2, 4, 7} (không bao giờ vượt số CPU 1–7). Áp dụng cho cả §4b (benign dưới liều: D3 worker ∈ {4, 7}) và §5 (nền D3 ∈ {0, 4, 7}).
2. Mọi lần chạy wl trong liều, E5, B/N: dùng `-loops <mem_steps>` lấy từ một lần hiệu chuẩn lúc máy rảnh đầu buổi (cơ chế m4.sh), KHÔNG dùng chế độ tự hiệu chuẩn/tự kiểm dưới tải. Ô thiếu số liệu chạy lại tối đa 3 lần; bắt buộc đủ 3/3 lần mỗi mức.
3. D4/E5: không dùng docker exec. Chạy wl trong scope systemd: `systemd-run --scope -p CPUQuota=<200%|100%|50%> taskset -c 0 ./bin/wl -loops <mem_steps> mem 500` (mức "không giới hạn" = không có CPUQuota); collector lọc `-pid` của wl; nr_throttled/throttled_usec đọc từ cpu.stat của scope đó.
4. Tiêu chí "thành phần không kỳ vọng đổi < 10 %" đổi thành: |Δ trung vị thành phần không kỳ vọng| < max(10 % của trung vị thành phần kỳ vọng ở mức cao nhất, 100 µs). Tránh chia cho nền 0.

## Phụ lục 1.3 — 24/10/2026 (chẩn đoán rq D3 L=7; DỪNG)

Số đo (máy 201, lab0 dừng, wl `-loops 664718 mem 500` CPU 0, stress-ng `--stream L --taskset 1-7`, không collector; cửa sổ bpftrace 60 s trên CPU 0). File đầy đủ: `validation/lab1-20261024/lieu/D3-chandoan.txt`.

**(a) Ghim stress-ng:** không worker nào `psr=0` hay affinity chứa CPU 0. L=7 và L=6 đều `aff=1-7`. Không phải lỗi ghim.

**(b) Ai chiếm CPU 0 ngoài wl** (other_busy = tổng `@oncpu_ns` của mọi `comm` khác `wl` và khác `swapper/*`, chia 60 s):

| L | other_busy % | top busy comm | wl % | idle (swapper/0) % |
|---|-------------:|---------------|-----:|-------------------:|
| 7 | 7.003264 | MainThread (2.573e9 ns, 4.29% cửa sổ) | 16.25 | 76.69 |
| 6 | 2.504643 | MainThread (1.074e9 ns, 1.79% cửa sổ) | 15.00 | 82.46 |

Top 10 L=7 (thứ tự `@oncpu_ns`): swapper/0, wl, MainThread, libuv-worker, git, kworker/0:0, V8Worker, sshd, containerd, bpftrace.
Top 10 L=6: swapper/0, wl, MainThread, git, kworker/0:0, V8Worker, containerd, sshd, bash, kworker/u16:3.

**Quyết định:** nhánh 3 của nhiệm vụ chẩn đoán — L=6 other_busy (2.50%) cũng ≥ 1% (cùng L=7 = 7.00%). **DỪNG.** Không đổi mức D3, không sửa ghim, không sửa tiêu chí phụ lục 1.2, không chạy lại D3/D4/E5 trong phiên này. Ghi nhận: tải busy ngoài wl trên CPU 0 chủ yếu là `MainThread`/`libuv-worker`/`V8Worker` (tiến trình IDE/agent trên máy lab), không phải stress-ng.

## Phụ lục 1.4 — 24/10/2026 (vệ sinh CPU 0 trên máy nạn nhân)
Chẩn đoán (D3-chandoan.txt): không worker stress-ng nào lọt CPU 0; phần bận ngoài wl trên CPU 0 là MainThread/libuv-worker/git của cursor-server: 7,0 % ở L=7, 2,5 % ở L=6; kworker/0:0 0,6 %/0,2 %.
1. Trước mọi phiên đo (liều, B/N, benign dưới liều, nền 7 ngày): `systemctl set-property --runtime user.slice AllowedCPUs=1-7`; kiểm `cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective` = 1-7 và `ps -eo pid,psr,cgroup,comm | awk '$2==0'` chỉ còn kernel thread + wl + unit đo. Collector trong mọi phiên liều/B/N chạy `taskset -c 1-7 ./bin/hids-collect …` (không cần CPU 0). Thiết lập là --runtime (mất khi reboot): driver và lệnh khởi động nền 7 ngày tự đặt lại ở đầu và ghi cpuset.cpus.effective vào log mỗi phiên.
2. Chạy lại chẩn đoán (b) 60 s ở L=7 sau khi giới hạn, tính other_busy loại swapper: < 1 % → giữ D3 {0,2,4,7}; 1–2 % và phần dư toàn kernel thread (kworker/ksoftirqd/rcu) → D3 {0,2,4,6} với điều kiện L=6 < 1 %; còn tiến trình user-space nào ngoài wl, hoặc ≥ 2 % → DỪNG, dán bảng.
3. Chạy lại D3 với mức đã chốt (tiêu chí phụ lục 1.2), rồi D4, E5, rồi đúng LAB-1.md từ bước 4 (driver). Ghi mục "phụ lục 1.4" + bảng chẩn đoán sau giới hạn vào LAB-1-ketqua.txt.

## Phụ lục 1.5 — 24/10/2026 (D4/E5: wl cpu liên tục + CPUQuota)
D4/E5 dùng wl chế độ cpu (đốt liên tục, marker mỗi 10 ms, như S1 của G3: `wl -loops <burn_loops> cpu 10000 3000`, không ngủ) thay cho mixed, vì quota chỉ có tác dụng khi nhu cầu vượt quota. Mức CPUQuota = none, 75%, 50%, 25% (systemd-run --scope, như 1.2 mục 3). Thành phần kỳ vọng: rq trong khoảng đốt tăng theo mức (≈ 0/25/50/75 % của Δt); oracle: throttled_usec_delta của scope; steal ≈ 0. Tiêu chí như 1.2 mục 4.

## Phụ lục 1.6 — 24/10/2026 (thống kê tỉ lệ tổng cho tác động cục)
Với các trục có tác động theo cục (D4 throttle, E5, và steal nói chung), thống kê của thành phần kỳ vọng là TỈ LỆ = tổng thành phần / tổng Δt trên cả lượt (p90 ghi kèm để mô tả), không phải trung vị; Spearman tính trên tỉ lệ này; thành phần không kỳ vọng tính trên tỉ lệ tổng, ngưỡng như 1.2 mục 4. D1/D3 giữ trung vị (tác động đều). E5 tính trên chính 12 lượt D4 (cùng workload, cùng scope): Pearson giữa tổng rq và throttled_usec_delta, và |steal|/rq < 2 % — không chạy lại lượt riêng.

## Phụ lục 1.7 — 25/10/2026 (chu kỳ beacon tách khỏi mức tranh chấp)
Trong driver (§5): B1 và N1 dùng chu kỳ 10 s (jitter 0–50 %) ở cả 3 mức nền D1 N∈{0,2,4}; B4/N4 giữ nguyên. Chu kỳ chậm chạy TRÊN NỀN 7 ngày sau khi nền bật, không liều, tuần tự, có nhãn trong `lab/nhan-tan-cong.tsv`: B1-60s 30 phút, N1-60s 30 phút, B1-300s 120 phút, N1-300s 120 phút (đều ≥ 20 chu kỳ); driver tự lên lịch bằng unit phụ `hids-lab1-slow` sau bước 6, không chờ người. Tiêu chí ≥ 20 chu kỳ giữ nguyên.

## Phụ lục 1.8 — 25/10/2026 (§4b: oracle/liều cho dịch vụ, khác wl)
§4b oracle và liều cho DỊCH VỤ (không ghim CPU) khác với wl (ghim CPU 0).
(a) D1 trên dịch vụ: co-runner phủ mọi CPU: `stress-ng --cpu N --taskset 0-7`, N ∈ {8, 16}; oracle: rq_p90 và rq_mean của bản ghi dịch vụ tăng theo mức (nền ≈ 1,5 µs). Phiên BEN-D1 với N∈{2,4} (taskset 0) ghi nhận liều không tác dụng (dịch vụ dời CPU), giữ file, không dùng.
(b) D3 trên dịch vụ: oracle = press_delta và rq_p90 tăng theo mức; CPI không dùng làm oracle cho dịch vụ I/O-bound (chỉ ghi mô tả).
