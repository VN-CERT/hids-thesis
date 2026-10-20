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
- Đang làm: C — đã viết `scripts/m6b11_gate.sh` (pre-check `bpftool prog show | grep -c hids_` = 0, chạy nguyên vẹn `m6b1_pre24h.sh` + `m6b1_gate.sh`, trích xuất bpftrace S2/S3/S5) và `scripts/m6b11_1h.sh` (1 giờ cấu hình 24h). Chuẩn bị commit + build lại + chạy qua systemd (dự kiến ~2 giờ).

## Bước tiếp theo

- Theo đúng thứ tự A → B → C → D trong task. Mục nào không đạt: dừng, dán nguyên văn.

## Việc đang chạy

- (không có)

## Vướng mắc / chờ kiến trúc sư

- (không)
