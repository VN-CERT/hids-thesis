# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-20 17:50 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin`. Hash cũ: `docs/commit-map-loc-bin.txt`.
- Tham chiếu bằng **TAG mốc**; dữ liệu `*.bin` / `*.bin.zst` không vào git.

## Mốc hiện tại và mục tiêu

- **M5:** đóng (`m5h`).
- **M6b-1:** đóng (`m6b1`, R028).
- **M6b-1.1:** đang làm — chẩn đoán CPU collector ~9,7% lõi, sửa `records_per_sec`, chạy lại cổng, tag `m6b1.1`, R029 (`docs/tasks/M6b-1.1.md`).

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

## Bước tiếp theo

- Theo đúng thứ tự A → B → C → D trong task. Mục nào không đạt: dừng, dán nguyên văn.

## Việc đang chạy

- (không có)

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
