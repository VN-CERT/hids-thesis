# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-21 07:20 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin`. Hash cũ: `docs/commit-map-loc-bin.txt`.
- Lịch sử đã **lọc lần 2** (2026-10-20): loại các file > 95 MB (log thô `pgbench.log` của m5f/m5h; bản sao giữ ở `/srv/hids-data/validation-raw/`). Hash các commit sau `ff99545` đã đổi; bảng đối chiếu ở `docs/commit-map-loc-2.txt`.
- Tham chiếu bằng **TAG mốc**, không dùng hash; dữ liệu `*.bin` / `*.bin.zst` không vào git.

## Mốc hiện tại và mục tiêu

- **M5:** đóng (`m5h`).
- **M6b-1:** đóng (`m6b1`, R028).
- **M6b-1.1:** đóng (`m6b1.1`, R029). Kiến trúc sư đã trả lời mục 8 trong nhiệm vụ M6b-1.2.
- **M6b-1.2:** đóng (`m6b1.2`, R030) — CPU collector còn ~1,4% lõi ở cấu hình 24 giờ.
- **M6b-1.3:** đóng (`m6b1.3`, R031) — phần A giữ mặc định `-rb-poll` 200ms; B3'/B6 cho thấy lệch rq phụ thuộc thứ tự gắn công cụ. Chờ kiến trúc sư quyết 3 câu hỏi trong R031 mục 8.

## Bước đã xong (M6b-1.1)

- Lưu nhiệm vụ nguyên văn `docs/tasks/M6b-1.1.md`.

## Bước đang làm

- A1 xong (commit e445f59, unit hids-m6b11-a1, exit=0): 5 phút đúng cấu hình 24h; CPU ≈10% một lõi; output `validation/m6b11-20261020/A1/`.
- A2 xong (unit hids-m6b11-a2, exit=0): baseline 9.7–10.0%; `-no-proc` 6.7–7.0%; `-no-host` 9.7–9.9%; `-cgroup-refresh 10s` 9.8–9.9%. Host/cgroup ≈ 0 điểm %; proc ≈ 3.1 điểm %.
- Chẩn đoán sâu: target idle (0 bản ghi/s) vẫn ~4.4% lõi; idle + `-no-proc` ~2.4% → mỗi vòng poll ringbuf ~2% lõi khi idle. Thread nóng là sysmon của Go runtime (`nanosleep` ~1700/s, strace) do reader nằm trong blocking `epoll_wait` (deadline 10 ms) chạm ngưỡng retake 10 ms. Chi tiết: `validation/m6b11-20261020/A-summary.txt`.
- A3: mục tiêu ≤2% KHÔNG đạt trong phạm vi sửa được phép (không đụng đường đọc ring buffer/deadline 10 ms). Không sửa ngoài phạm vi; chờ kiến trúc sư quyết định (câu hỏi trong R029). Các phần không phụ thuộc (B, C, D) làm tiếp theo quy tắc workflow.
- B xong (chưa commit riêng, gộp commit trước build C): `records_per_sec` dùng `writerSet.totalRecords` cộng dồn không reset khi xoay file + clamp delta < 0 về 0; `scripts/m6b1_gate.sh`: khai báo `lines=0` trước và gán `|| lines=0` (không đổi tiêu chí 580–620). Diff: `validation/m6b11-20261020/B-diff.txt`.
- C xong (3 đợt, binary 8faaec1): G7a, G7b-nho đạt; G3 đạt ở đợt 2 (đợt 1 S5 max=7979); G9b đạt; G8 đạt ở đợt 3 (đợt 2 exit 501/502); G9, G10, host-stats đạt ở đợt 3; chạy 1 giờ xong. Lệch rq so với bpftrace: S3 vượt 5% cả hai đợt (10.91%, 8.43%) — chờ kiến trúc sư.
- D: đã viết R029 (`reports/R029-m6b1.1-cpu-records-per-sec-gate.md`), cập nhật `reports/INDEX.md`. Gắn tag `m6b1.1` và dừng, chờ kiến trúc sư trả lời 2 câu hỏi trong R029 mục 8.

## Bước đang làm (M6b-1.2)

- Câu 1.1 xong (commit riêng "bộ đọc proc bỏ deadline"): đo sau sửa — idle 1.98% lõi (trước 4.4%), cấu hình 24 giờ ~6.9% lõi (trước ~9.9%). Output `validation/m6b12-20261020/after1-idle/`, `after1-24h/`.
- Câu 1.2 xong (commit riêng "cờ -rb-poll mặc định 200ms"): đo sau sửa — idle 0.25% lõi, cấu hình 24 giờ 1.34–1.46% lõi. Tổng kết câu 1: trước sửa idle 4.4% / 24h ~9.9%; sau 1.1 idle 1.98% / 24h ~6.9%; sau 1.2 idle 0.25% / 24h ~1.4%. Output `validation/m6b12-20261020/after2-idle/`, `after2-24h/`.
- Tiếp theo: đường CPU theo tốc độ (1k/10k/100k/500k, mỗi mức 2 phút), câu 2 (bpftrace `@rq_sau_preempt_ns`, G3 lúc dừng container và lúc container chạy), trích bản ghi phần dư S5 7979, cổng cuối (G7a, G7b, G7b-nho, G8, G9a, G9b, G10, 1 giờ), tag `m6b1.2`, R030.

## Bước đang làm (M6b-1.3)

- Nhiệm vụ: `docs/tasks/M6b-1.3.md` (trả lời mục 8 R030). Kiến trúc sư đã ĐÓNG câu CPU của R029 (1,4% lõi đạt).
- Giả thuyết kiến trúc sư về phần dư CLAMPED (không sửa ở nhiệm vụ này, sẽ sửa trong M6c bằng BPF của kiến trúc sư): trong `hids_sys_enter`, chương trình đọc `bpf_ktime_get_ns()` TRƯỚC rồi mới đọc tổng irq; ngắt xảy ra giữa hai lần đọc (ở sys_enter ngắt không bị khoá, khác sched_switch/sched_wakeup) bị tính vào khoảng trước trong khi Δt không chứa nó → irq > Δt → CLAMPED, phần dư = irq − Δt.
- Việc đang làm: thêm dòng đếm CLAMPED + phần dư >500 vào G3 (chỉ đếm); phần A (G7b 5+5 lần, CPU với `-rb-poll` 50ms); phần B (bpftrace in từng sự kiện, ghép wakeup, đọc code BPF); R031, tag `m6b1.3`.
- BỔ SUNG kiến trúc sư (đã lưu nguyên văn vào `docs/tasks/M6b-1.3.md`): bỏ cách ghép B3–B4 theo thứ tự; thay bằng B3' ghép theo MỐC THỜI GIAN (cặp (W_i,S_i) → khoảng collector chứa S_i; phần lọc: khoảng chứa đúng một cặp wakeup và không preempt — preempt theo khoảng đếm từ sự kiện bpftrace mở rộng). Thêm B6 (phép đo CHÍNH): S3, 3 lần × 3 cấu hình (a) bpftrace tối giản gắn TRƯỚC collector, (b) bpftrace tối giản gắn SAU collector, (c) bpftrace mở rộng + in sự kiện; container DỪNG, một collector; báo lệch % và µs/wakeup. Script phụ `scripts/m6b13_b6.sh` nếu g3.sh không hỗ trợ thứ tự gắn.
- Phần A XONG: G7b 200ms mất 2/5 lần (1803381, 662330); G7b 50ms mất 5/5 lần; CPU `-rb-poll` 50ms idle 0,60%, cấu hình 24 giờ 3,06–3,12% lõi → trường hợp "các trường hợp khác": giữ mặc định 200ms, không đổi gì. Commit `7ac5412`.
- B1/B1' XONG: g3.sh chế độ sự kiện (`G3_BT_EVENTS=1`) in W/S/P. Commit `acc68f2`, `8553179`-era; dòng đếm CLAMPED trong rec-check hiện diện ở kết quả B2 (0 ở mọi kịch bản lần này).
- B2+B3' XONG: G3 dừng container lệch rq S2 2,22%, S3 2,20%, S5 1,63%; ghép theo mốc thời gian (`scripts/m6b13_pair.py`): d = rq_ns − (S−W) S2 mean +1227 ns (n=501), S3 mean +879 ns (n=501), S5 n=8 mean +343 ns; mọi wakeup cùng CPU, không MIGRATED. Commit `e623d83`.
- B6 XONG (phép đo chính): (a) bpftrace tối giản gắn trước: lệch 0,18–0,50% (+0,07–0,10 µs/wakeup); (b) tối giản gắn sau: 10,45% và 8,82% (+1,81, +1,43 µs/wakeup), lần b2 bất thường (tổng bpftrace 19187349658 ns); (c) mở rộng: 2,38–2,82% (+0,93–1,08 µs/wakeup). Lệch phụ thuộc thứ tự gắn. Commit `ce5269e`.
- B5 XONG (đọc code): mark_wakeup lấy `bpf_ktime_get_ns()` TRƯỚC khi tra task storage (dòng 670/673); hids_sched_switch gọi read_now SAU khi tra storage prev (612/614) và next (633/636), mốc dùng chung.
- M6b-1.3 ĐÓNG: R031 viết xong, tag `m6b1.3`, chờ kiến trúc sư trả lời mục 8 của R031 (mở nhiệm vụ riêng về mất G7b? đóng câu lệch rq theo B6? đo lại b2?).
- Sự cố lúc chạy phần A đợt 1: sửa `scripts/g3.sh` (B1) trong lúc job G7b đang chạy làm cây git bẩn → các lần chạy sau bị g7.sh từ chối; đã chạy lại toàn bộ hai mẻ với cây sạch. Lần relaunch đầu hỏng vì systemd-run sai thư mục làm việc (đường dẫn tương đối); đã sửa bằng `cd /root/hids` trong lệnh.

## Bước đang làm (M6c)

- Nhiệm vụ: `docs/tasks/M6c.md` (PMU trong bản ghi 64 byte + sửa cuộc đua ngắt của kiến trúc sư + bộ overhead cuối). File kiến trúc sư đã đặt sẵn: `bpf/sys_enter.bpf.c` (sha256 `8b05464…`, đã commit cùng nhiệm vụ ở `12749a9`), `analysis/m6c_stats.py` (`8c39000…`). `kernel.perf_event_paranoid = 1` (đạt ≤ 1, không đổi sysctl).
- Đã xong: đặc tả 64 byte + bit7 PMU trong `.cursor/rules/hids.mdc`; recfmt 48/56/64 (`RecordSize=64`, `RecordSize56`, `FlagPMU`, `Inst`/`Cyc`); loader `-pmu auto|on|off` (perf_event_open per CPU online, fd vào `hids_pmu_inst`/`hids_pmu_cyc` tại index = cpu id, `hids_pmu_on`); header `pmu: on|off` + `pmu_events:`; host TSV thêm `pmu_inst_delta`/`pmu_cyc_delta` ở cuối; rec-export thêm `inst,cyc,pmu_ok` ở cuối; rec-stat tỉ lệ PMU không-FIRST; `scripts/bin_header.py` nhận 64. Commit `6eb65d7` + gofmt `hostsample`.
- Smoke: `-pmu on` 100% bản ghi không-FIRST có cờ PMU (1.140.933 bản ghi); `-pmu off` 0%. File 56 byte cũ đọc được bằng rec-stat/rec-check mới.
- Tiếp theo: build từ commit sạch → cổng (đọc lại file cũ, G7a ×2, G7b ×3, G7b-nho, G3 ×3 on + ×1 off, G11, G8/G9a/G9b/G10) → bộ overhead mục 4 → E4p → R032, tag `m6c`.

## Bước tiếp theo

- Theo đúng thứ tự trong `docs/tasks/M6c.md`. Mục nào không đạt: dừng, dán nguyên văn.

## Việc đang chạy

- (không có) — mọi unit M6c đã xong. Sau cùng: `bpftool prog show | grep -c hids_` = 0, không còn collector, 12 container chạy.

## Bước đang làm (M6c-1)

- Nhiệm vụ: `docs/tasks/M6c-1.md`. Thứ tự: 1 → 2 → 3 → 5 → 4 → 6. Báo cáo R033, tag `m6c.1`.
- LƯU Ý: `tools/coreclk.c` sha256 thực tế `3d2c9005…` KHÁC giá trị trong nhiệm vụ (`88ef821e…`) → theo lệnh "sai → DỪNG", KHÔNG dùng coreclk (mục 5b dừng, ghi vào R033 mục 8). Nội dung file đúng mô tả coreclk; không sửa.
- Phần 1 XONG: 1a `-pmu off|host|on` mặc định host (commit `d2db255`), 1b STEALCHECK thử lại 3 cửa sổ, 1c pre24h đếm tổng đoạn host, 1d bản sao `m6c1_overhead.sh`/`m6c1_e4p.sh`/`g3_swap.sh` (READY 20s + KHONG_READY chạy lại; production `-pmu host`; wrk gốc `/usr/bin/wrk`; pgtest theo M5h). `make build` xong.
- Cập nhật: `tools/coreclk.c` đã được người dùng thay bằng bản đúng `88ef821e…` (commit "M6c-1: tools/coreclk.c ban kien truc su 88ef821e") → mục 5b ĐƯỢC làm. Bản cũ trong repo lúc bắt đầu là `3d2c9005…` (ghi vào R033 mục 7).
- Phần 2 XONG: G7a ×4 mất 0, header `pmu:` host/on/off/host(mặc định) đúng; G3 mặc định host: phần dư max ≤ 500 ns, CLAMPED 0/tổng, recursion_misses = 0 (27 chương trình × S1–S5); hostcheck host = số, off = `na`. Lệch rq G3 so với bpftrace TONG (S2 10,56%, S3 26,33%, S5 7,64%) là đối tượng chẩn đoán của phần 3, không phải tiêu chí phần 2.
- Phần 3 XONG (dữ liệu `validation/m6c1-20261021/part3/`, file `pair3d.txt` + `pair3d-swap.txt`): thứ tự thường + on: trung vị hiệu (bpftrace − collector) S2 = +7,769 µs; off: −1,403 µs; thứ tự đảo: on +0,451 µs, off +0,382 µs (S2). Đã sửa 2 lỗi của bản sao: STEALCHECK in `nguong_ns=0` khi lệch âm lớn nhất (commit 1b-fix, đã build lại) và `g3_swap.sh` thừa ký tự `\&\&` khiến lượt swap đầu không chạy kịch bản nào (đã chạy lại).
- Phần 5a: E4 gốc (`scripts/m4.sh`) khởi động KHÁC mô tả — hiệu chuẩn ở bước `calibrate` riêng trên máy rảnh (dòng 487), lúc chạy `e4_workers` (dòng 308) thì stress-ng chạy TRƯỚC (dòng 315), `sleep 2` (dòng 318), rồi wl mới chạy với `-loops` đọc `mem_steps` từ file (không hiệu chuẩn lại). Theo BỔ SUNG đề bài của người dùng (đã lưu nguyên văn vào `docs/tasks/M6c-1.md`): KHÔNG dừng nữa; `scripts/m6c1_e4p.sh` chạy theo giao thức kiến trúc sư (wl hiệu chuẩn + tự kiểm mem khi máy rảnh → stress-ng → chờ 10 s → go), khác biệt ghi vào R033.
- Phần 4 XONG (unit `hids-m6c1p4`, 2026-10-21 19:19 → 23:34 +07, `overhead_exit=0`, dữ liệu `validation/m6c1-20261021/part4/`): overhead chính xong; đường CPU theo tốc độ xong; G7-cap nproc=1 `recs=57203693 mat=0`, nproc=2 `recs=53262308 mat=64071301` (exit=1), nproc=4 `recs=52486414 mat=204385788` (exit=1). 12 container đã chạy lại, kernel sạch (hids_ = 0).
- Phần 5b XONG (`validation/m6c1-20261021/coreclk/coreclk.log`): cycles:u ≈ 2,494 tỉ vs chu_ky_ky_vong 2,4 tỉ (tỉ số ≈ 1,039); GHz_wall 1,888–1,933; chi tiết tính trong R033.
- Phần 5a XONG (3 job: job đầu chết vì STEALCHECK từ chối 1 lần + `wait_ready` của bản sao dùng `exit 1`; đã sửa bản sao, chạy lại đủ 9/9 ô): L0 CPI 1,92–1,94; L12 CPI 3,68–3,74; L22 CPI 5,95–6,40; GHz hiệu dụng 1,95–1,98; inst tăng theo L (câu 8.2 của R033).
- M6c-1 ĐÓNG: R033 viết xong, tag `m6c.1`, đã push (remote khớp local). Việc đang chạy: (không có) — unit `hids-*` trống, `bpftool prog show | grep -c hids_` = 0, 12 container chạy. Chờ kiến trúc sư trả lời 6 câu hỏi mục 8 của R033.

## Bước đang làm (M6c-2)

- Nhiệm vụ: `docs/tasks/M6c-2.md`. Báo cáo R034, tag `m6c.2`.
- Phần 1 XONG (chỉ dùng dữ liệu cũ, file `validation/m6c2-20261022/part1.txt`): C1 bản ghi/giây 10 lượt mỗi ô (T1 trung vị 1.261.136,9/s, mất tổng 0); C2 = 0 bản ghi mọi lượt (cgroup decoy). Đối chiếu 1c: R026/M5h T1 C0 141,84 ns, T3 C0 4901,59 TPS, T4 C0 140081 RPS; R021/M5f T3 C0 ≈ 4965 TPS, T4 C0 142675 RPS.
- Phần 2 XONG: STEALCHECK theo TỔNG mọi CPU (|Σvmw − Σrq| ≤ max(5 ms, 1% Σvmw)), bảng per-CPU mỗi cửa sổ; G7a ×1 mất 0; G3 ×1: G5 max ≤ 500, CLAMPED 0/tổng, recursion_misses = 0 trên 31 chương trình. Dữ liệu `validation/m6c2-20261022/part23/`.
- Phần 3 XONG: `scripts/freq_stamp.sh`; CPU 12 trung vị 1,9359 GHz, CPU 20 trung vị 1,9349 GHz (máy rảnh, container dừng). Quy ước đã ghi vào `.cursor/rules/hids.mdc`.
- Phần 4 XONG: E4p cơ chế gốc đủ 9/9 ô, attempt 1, 500/500 khoảng mỗi ô; inst 14170548–14170579 ở mọi mức; dấu tần số L=22 là 2,5239 GHz (khác L0/L12 ~1,93 — câu 8.1 của R034).
- M6c-2 ĐÓNG: R034 viết xong, tag `m6c.2`, đã push. Việc đang chạy: (không có) — unit `hids-*` trống, `bpftool prog show | grep -c hids_` = 0, 12 container chạy.
- Trả lời của kiến trúc sư về R034 mục 8 (nhận 2026-10-22, ghi nguyên văn):
  1. Không đo lại L=22; so sánh giữa các mức bằng cyc, CPI, inst (không phụ thuộc tần số); cpu_ns luôn kèm GHz hiệu dụng của mức đó; việc tần số nhảy 1,93→2,52 GHz là phát hiện: turbo có nhưng host dùng chung nên lúc có lúc không; quy ước bổ sung: freq_stamp trước VÀ sau mỗi khối đo, lệch >2% thì ghi chú khối đó.
  2. Câu 8.2 của R033 đóng: inst không đổi với cơ chế -loops. Ghi nhận lỗi trong tools/wl.c self_test_mem_10ms: biến sum không được cộng dồn nên nhánh điều chỉnh mem_steps là mã chết; không sửa trong nhiệm vụ nào hiện tại.

## Bước đang làm (M6c-3)

- Nhiệm vụ: `docs/tasks/M6c-3.md`. Báo cáo R035, tag `m6c.3`. BPF mới của kiến trúc sư `9994b03f…` (lấy mẫu PMU), đã commit và build đạt.
- Phần 2 XONG (commit `30b221b`): `-pmu sample=K` (K 2…1000; nạp `hids_pmu_sample`, header `pmu: sample=K`); STEALCHECK in thêm dòng `STEALCHECK canh_bao cpu=<n> lech_ns=<...>` khi tổng đạt nhưng một CPU lệch > 50 ms.
- Phần 3 XONG: G7a ×4 mất 0, header đúng 4 chế độ; G3 sample=20 (phần dư ≤ 500, CLAMPED 0, recursion 0, PMU 4,97–4,99%) và on (PMU 100%); G11 lệch inst 43, cyc 7761, cờ 100%; G11s đạt (sample20: 15 khoảng, inst +0,79%, cyc +1,55%; sample50: 6 khoảng, +0,77%/+1,04%); T1: C0 186,5 / host 817,9 / sample50 805,7 / sample20 952,9 / on 3766,5 ns/syscall; pre24h10 sample=20: CPU 0,80% lõi, RSS 183730176 B, drops 0, host 600 dòng, PMU 4,9883%. Hai lần G3 đầu hỏng do wrapper/driver cùng dừng container và wl trượt tự kiểm — đã chạy lại nguyên trạng.
- M6c-3 ĐÓNG: R035 viết xong, tag `m6c.3`, đã push. Việc đang chạy: (không có) — unit `hids-*` trống, `bpftool prog show | grep -c hids_` = 0, 12 container chạy. Chờ kiến trúc sư chốt K cho LAB-1 (câu 8.1 của R035).

## M6c: ĐÓNG (R032)

- Bản ghi 64 byte + PMU xong: recfmt 48/56/64, loader `-pmu auto|on|off`, header `pmu:`, host `pmu_inst_delta`/`pmu_cyc_delta`, rec-export `inst,cyc,pmu_ok`, rec-stat tỉ lệ PMU. Đồng bộ Go `irqState.Gen`.
- Cổng: file cũ 1003=1003=1003; G7a on/off mất 0; G7b khớp tuyệt đối (mất 6,5–18,8%); G7b-nhỏ khớp 6770559; G3 ×4 phần dư ≤500, CLAMPED 0/tổng, recursion 0; G11 lệch inst 43 (≈0%), cyc ≤0,0002%, cờ PMU 100%; G8/G9a/G9b/G10 PASS (host lines=471 là lỗi đếm một đoạn xoay của pre24h, tổng thật 602).
- Overhead cuối (mỗi ô 10 lượt): T1 C0 184, C1 3746, C1n 797, C2 243 ns/syscall; T4 C1 −27,0%, C1n −8,5%; T3 C1 −69,4% TPS; T4-R50 C1 độ trễ sụp (p99 335 ms). Đường CPU (-pmu on): 1.5k→1,87%, 10k→4,43%, 99k→23,62%, đạt tối đa ~207k/s ở mức đích 500k (CPU 47,97%, drops 0). G7-cap: 267k/528k/874k bản ghi/giây (1/2/4 proc), mất 0.
- E4p đủ 9 ô: CPI 1,71 (L0) → 3,05–3,25 (L12) → 5,04–5,68 (L22); GHz hiệu dụng 1,90–1,97 không đổi; inst giảm theo L do wl hiệu chuẩn lại dưới tải.
- Chờ kiến trúc sư: (1) chấp nhận chi phí PMU? (2) lệch rq G3 đổi chiều theo PMU (on: thấp hơn 16–41%; off: cao hơn 3,6–8,8%); (3) sửa cách đếm host lines của pre24h? Tag `m6c`, R032.

## Kết quả cổng cuối M6b-1.2 (binary fa60c56)

- G7b lần 1: `tong bo dem mat: 54193` (tiêu chí = 0, không đạt); chạy lại xác nhận: mất = 0. Cả hai lần ghi nguyên văn trong R030.
- pre24h lần 1 (trong job final): G3 S5 max=6298 → dừng trước G9b; lần 2 (`final2/`): đạt toàn bộ — G7a, G7b-nho (mat=seq_thieu=2401672), G3 max ≤500, G9b (lo_hong=0, seq_thieu=0, mat=0), host 600 dòng.
- gate: đạt toàn bộ (G7a, G3, G8 khớp perf, G9a rec-chain 0/0, G10 PAUSE/RESUME/bo_vi_dia=16815920/mat=0, host).
- Chạy 1 giờ: CPU 1.42% một lõi, RSS 193466368 B, records_per_sec không âm, kernel drops = 0, proc drops = 0.
- Sau cùng: `bpftool prog show | grep -c hids_` = 0, không còn collector. Tag `m6b1.2`, R030 đã viết; chờ kiến trúc sư quyết về lệch rq (câu 2) và mất G7b lần 1.

## Kết quả M6b-1.2 tới trước cổng cuối

- Câu 1: sau 1.1 (proc bỏ deadline) idle 1.98% / 24h ~6.9%; sau 1.2 (`-rb-poll` 200ms) idle 0.25% / 24h 1.34–1.46% lõi. Đường CPU theo tốc độ (ổn định, từ status.tsv): ~1.5k/s → 1.43%; ~10k/s → 3.83%; ~97k/s → 21.37%; ~475k/s → 114.97%; mất kernel = 0 ở mọi mức.
- Câu 2: bpftrace đã thêm `@rq_sau_preempt_ns` + `@rq_tong_ns` (sửa lỗi lấy `nsecs` hai lần bằng một biến `$now`). Lệch rq so với TỔNG bpftrace: container dừng — S2 9.13%, S3 11.02%, S5 3.21%; container chạy — S2 7.80%, S3 9.88%, S5 7.13%. Tiêu chí ≤5% không đạt (trừ S5 lúc dừng container). G5 max ≤500 cả hai lần; file `validation/m6b12-20261020/cau2-summary.txt`.
- Phần dư S5 7979: bản ghi chỉ số 1277 của tid 281298 trong `out/g3-S5-200335.bin`, cờ CLAMPED, irq_ns=17361 > dt_ns=9382, cpu_ns=0. File `validation/m6b12-20261020/s5-residual/s5-7979.txt`. Không sửa gì.

## Dọn trước M6b-1.2 (xong 2026-10-20)

- Đã ghi nhận lọc lịch sử lần 2 ở mục trên (bảng đối chiếu `docs/commit-map-loc-2.txt`, dùng TAG).
- `.gitignore` đã thêm `hey.csv`; không commit log/dữ liệu thô (`pgbench.log`, `pglog.*`, `perf.data`, `hey.csv`, `*.bin`, `*.bin.zst`).
- Đã commit `validation/m6b1-20261010/`, `validation/m6b1-20261019/`, `validation/m6b1-pre24h-20261019/` (150 file, chỉ kết quả tóm tắt). File > 10 MB trong các thư mục này chỉ gồm 3 file `.bin` (1.7 GB, 1.7 GB, 9.4 GB ở `m6b1-20261019/g9|g10/`) — dữ liệu thô, đã bị `.gitignore` loại, không commit.
- `make build` tạo lại đúng `internal/syscallbpf/sysenter_x86_bpfel.o` (151576 B) và `internal/procbpf/procevents_x86_bpfel.o` (41200 B) từ nguồn BPF (sha256 ở mục sha256 của R029); đã commit cả hai.
- Đã `git push github --all` (master `50b3668..d2b461a`) và `git push github --tags` (Everything up-to-date); remote khớp local: master `d2b461a`, tag `m6b1` `59c0211`, tag `m6b1.1` `0f7f948`.

## Kết quả C đợt 3 (unit hids-m6b11-c3)

- gate exit=0, đạt toàn bộ: G7a, G3 đầy đủ, G8 (exec/fork/exit khớp perf, `/true` = 500), G9 (rec-chain lo_hong=0, seq_thieu=0), G10 (PAUSE_DISK, RESUME_DISK, bo_vi_dia=17282608, kernel mat=0), host ~600 dòng, cpu_user không giảm. Sau chạy: `bpftool prog show | grep -c hids_` = 0, không còn collector.

## Kết quả C đợt 2 (unit hids-m6b11-c2)

- pre24h exit=0, đạt toàn bộ: G7a (1000001, mat=0), G7b-nho (mat=seq_thieu=(perf-ban_ghi)=4211457), G3 recursion_misses=0, G5 max S1=0, S2=499, S3=499, S4=0, S5=499 (≤500), G9b (lo_hong=0, seq_thieu=0, kernel_mat=0), host 600 dòng, bộ đếm không giảm.
- Lệch rq collector so với bpftrace đợt 2: S2=5.02%, S3=8.43%, S5=0.96% (đợt 1: S2=3.32%, S3=10.91%, S5=5.05%). Tiêu chí thêm ≤5%: S3 vượt cả hai đợt; S2/S5 lúc vượt lúc không.
- gate đợt 2: G7a PASS; G3 đầy đủ (gồm G-real, G-irq, G7d) chạy xong; **G8 FAIL: exit collector=501, perf=502** (exec 501=501, fork 501=501). gate dừng tại G8 nên G9/G10/host-stats của gate chưa chạy.

## Kết quả C đợt 1 (unit hids-m6b11-c, binary 8faaec1)

- G7a PASS (ban_ghi=1000001 mat=0); G7b-nho PASS (mat=seq_thieu=(perf-ban_ghi)=3288965).
- G3 (pre24h): recursion_misses=0; G5 max S1=0, S2=500, S3=500, S4=0, **S5=7979 ns → FAIL tiêu chí ≤500** (1/1502 khoảng >1000 ns). pre24h dừng tại đây (chưa chạy G9b, host10m).
- rq collector lệch bpftrace: S2=3.32%, **S3=10.91%**, **S5=5.05%** (tiêu chí thêm ≤5%: S3, S5 vượt). File: `validation/m6b11-20261020/C/g3-bpftrace-compare.txt`.
- gate.sh đợt 1: G3 lỗi do `wl` tự kiểm hiệu chuẩn lệch >5% rồi thoát sớm (không phải tiêu chí collector); G8/G10 chưa chạy.
- Chạy 1 giờ (C/run1h): CPU 9.87% một lõi (346.816s/3513s), RSS cuối 193638400 B, records_per_sec min 385.72 max 408.32, **số dòng âm = 0** (kể cả qua xoay file 14:00Z), kernel drops = 0, proc drops = 0.

## Vướng mắc / chờ kiến trúc sư

- A3: mục tiêu CPU ≤2% lõi không đạt trong phạm vi sửa được phép (nguyên nhân ở tương tác đường đọc ring buffer 10 ms với sysmon Go). Cần kiến trúc sư quyết định (câu hỏi mục 8 trong R029).
- C/G3: lệch rq collector so với bpftrace ở S3 vượt 5% trong cả hai đợt đo (10.91% và 8.43%); S2, S5 có đợt vượt nhẹ. Cần kiến trúc sư quyết định tiêu chí/định nghĩa (mục 8 trong R029).

## Bước đang làm (LAB-1) — cập nhật 2026-10-24

- Nhiệm vụ: `docs/tasks/LAB-1.md`. Báo cáo: `LAB-1-ketqua.txt` (bước 5+7 khi driver xong).
- Bước 0: preconditions OK (tag m6c.3, hids_=0, paranoid=1, đĩa 165G, lab0 Up). `make build` OK. Sha256 5 file kiến trúc sư khớp.
- Bước 1 XONG: commit `6a914ee` — "LAB-1: chot giao thuc va detector C5 truoc khi ghi du lieu (kien truc su)". `docs/giao-thuc-lab1.md` sha256 `08a7a1fb…`; `detector_c5.py` tự-kiểm OK.
- Bước 2 XONG: `scripts/lab1_benign_gen.sh`; thử 10 phút `validation/lab1-20261024/gen-test/` — wrk2 120.01 rps, pgbench ~99.6 tps, SIGTERM sạch.
- Bước 3 ĐANG CHẠY: unit `hids-lab1-lieu` từ 13:20:45Z; log `validation/lab1-20261024/lieu/lieu-systemd.log`; dự kiến xong ~14:50Z. D2 ghi hoãn.
- Tiếp: nếu liều đạt → unit `hids-lab1-driver` (4→4b→6); kiểm 10 phút đầu; dừng phiên. Bước 5+7 khi người dùng báo driver xong.

## Việc đang chạy

- **hids-lab1-lieu** — `/bin/bash scripts/lab1_lieu.sh validation/lab1-20261024/lieu` — bắt đầu 2026-10-24T13:20:45Z — dự kiến ~14:50Z — log `validation/lab1-20261024/lieu/lieu-systemd.log` — status `out/jobs/lab1-lieu.status`

## Bước đang làm (LAB-1) — DỪNG 2026-10-24

- Nhiệm vụ: `docs/tasks/LAB-1.md`. Báo cáo: `LAB-1-ketqua.txt`.
- Bước 0–2 XONG. Bước 1 commit `6a914ee`.
- Bước 3 DỪNG: D1 ĐẠT (Spearman rq≈1, cpu đổi 0,33%); D3 KHÔNG ĐẠT (rq_med 0→4,68e6 ns, other_change_pct=inf). D2 hoãn. D4/E5 không hoàn tất (wl pid / dừng sau D3).
- Không khởi động `hids-lab1-driver`. Chờ kiến trúc sư quyết D3.

## Việc đang chạy

- (không có) — `bpftool prog show | grep -c hids_` = 0; lab0-postgres/nginx Up.

## Việc đang chạy (LAB-1 phu luc 1.2)

- **hids-lab1-lieu-v12** LAB1_ONLY=d3d4e5 — bắt đầu 2026-10-24T14:13:14+00:00 — log validation/lab1-20261024/lieu/lieu-v12-systemd.log

## Bước đang làm (LAB-1) — DỪNG sau phụ lục 1.2 (2026-10-24)

- Commit phụ lục: `f552dbd`. Chạy lại D3 với worker {0,2,4,7}, `-loops mem_steps`, tiêu chí mới.
- D3 KHÔNG ĐẠT: rq_med L7 = 4281949 ns > thresh 1988636 ns (Spearman cpu ĐẠT). D1 giữ ĐẠT.
- D4/E5/driver chưa chạy. Báo cáo cập nhật `LAB-1-ketqua.txt`.

## Việc đang chạy

- (không có)
