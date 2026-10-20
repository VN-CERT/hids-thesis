# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-20 17:50 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin`. Hash cũ: `docs/commit-map-loc-bin.txt`.
- Lịch sử đã **lọc lần 2** (2026-10-20): loại các file > 95 MB (log thô `pgbench.log` của m5f/m5h; bản sao giữ ở `/srv/hids-data/validation-raw/`). Hash các commit sau `ff99545` đã đổi; bảng đối chiếu ở `docs/commit-map-loc-2.txt`.
- Tham chiếu bằng **TAG mốc**, không dùng hash; dữ liệu `*.bin` / `*.bin.zst` không vào git.

## Mốc hiện tại và mục tiêu

- **M5:** đóng (`m5h`).
- **M6b-1:** đóng (`m6b1`, R028).
- **M6b-1.1:** đóng (`m6b1.1`, R029). Kiến trúc sư đã trả lời mục 8 trong nhiệm vụ M6b-1.2.
- **M6b-1.2:** đóng (`m6b1.2`, R030) — CPU collector còn ~1,4% lõi ở cấu hình 24 giờ. Chờ kiến trúc sư quyết 3 câu hỏi trong R030 mục 8 (lệch rq so với tổng bpftrace, G7b một lần mất 54193, phần dư S5 CLAMPED).

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

## Bước tiếp theo

- Theo đúng thứ tự trong `docs/tasks/M6b-1.2.md`. Mục nào không đạt: dừng, dán nguyên văn.

## Việc đang chạy

- (không có)

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
