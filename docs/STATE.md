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

- **hids-m6d-a** (M6d phần A: calibrate → E1 → E3 → E4-cache, 3 lần/mức + freq_stamp)
  - lệnh: `systemd-run --unit=hids-m6d-a --collect bash -c 'cd /root/hids && bash scripts/m6d_a_driver.sh'`
  - bắt đầu: 2026-10-24 20:08
  - dự kiến xong: 2026-10-24 22:08 (~2 giờ)
  - log: `out/jobs/m6d-a.log`
  - trạng thái: `out/jobs/m6d-a.status`
  - dữ liệu: `validation/m6d-20261024/`

## Kết quả M6d phần A (2026-10-24)

- Unit `hids-m6d-a` exit=0; dữ liệu `validation/m6d-20261024/`.
- READY 30/30 (attempt=1). Báo cáo R036 (E2 chờ). Tag `m6d` chưa gắn.
- Cập nhật: 2026-10-24 21:31.

## M6d: ĐÓNG (R036, tag m6d)

- Phần A: E1/E3/E4-cache ×3/mức, READY 30/30, `validation/m6d-20261024/`.
- Phần B: E2 ×3/mức, `--cpu-method int64`, vm_steal_pct Unlimited 0,025% → 36000 17,794% → 24000 45,757% → 12000 68,333%; Unlimited cuối 0,021%. CPI ≈ 1,25; 12/12 attempt=1.
- Trả lời kiến trúc sư về R036 phần A (nhận 2026-10-24, CHẤP NHẬN, không chạy lại; ghi nguyên văn):
  1. E4-cache: inst không đổi, CPI giảm ~10 %, cpu_ns giảm 7 % — ghi là quan sát: `--cache` ở các mức này không bão hoà băng thông; CPI giảm phù hợp giả thuyết tần số uncore/mesh tăng khi lõi khác bận; E4-stream (R034) là ca tranh chấp bộ nhớ chính.
  2. E1: cpu_ns chỉ so tuyệt đối trong cùng dải GHz; bảng bài dùng rq và cyc; ghi tần số nhảy 1,93↔2,53; rq 9/12/26 ms nhất quán với CFS chia đều.
  3. E3 là kiểm không gán nhầm: vol = 300 s, cpu/rq vài chục µs, steal 0 — đạt.
- Cập nhật: 2026-10-24 22:33.

## Bước đang làm (M6e-E2b)

- XONG: `scripts/m6e_e2b.sh`, dữ liệu `validation/m6e-20261024/E2b/`, đã nối R036 mục E2b.
- 12/12 attempt=1; vm_steal_pct Unlimited 0,037% → 36000 29,992% → 24000 45,392% → 12000 68,052%; Unlimited cuối 0,025%.
- Oracle cpu20 vs hids_sum (steal+off): ti_le ≈ 1,00 ở các mức có limit (36000/24000/12000).
- Cập nhật: 2026-10-24 23:27.

## Việc đang chạy

- (không có) — E2b xong. 12 container chạy, `hids_` = 0.

