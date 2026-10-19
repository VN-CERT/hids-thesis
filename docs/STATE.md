# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-19 17:10 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, `m6b1`, …), **không** dùng hash commit trong báo cáo/STATE (trừ tra cứu).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5:** **đóng** — tag `m5h`.
- **M6b-1:** siết cổng + mục 1–3 trước 24h; rồi `hidsrun-24h` → `/srv/hids-data/<hostname>/`; R028 + tag `m6b1`.

## Bước đã xong (M6b-1)

- Tính năng longrun, procbpf, rec-chain, deploy unit mẫu.
- Kiến trúc sư duyệt G8, G9a, G10 ĐẠT; sha256 ba file khớp.
- Host-stats 10 phút trong gate cũ đang chạy / sắp xong (`validation/m6b1-20261019/host10m`).

## Bước đang làm

1. Xoá `M6B1_SKIP_*` khỏi `scripts/m6b1_gate.sh`, commit.
2. Build binary sạch (có sửa SIGTERM) → chạy mục 1 (G7a, G7b-nho, G3 S1–S5), mục 2 G9b, mục 3 host 10 phút (`scripts/m6b1_pre24h.sh`).
3. Sau đó 24h unit `hidsrun-24h`, R028, tag `m6b1`.

## Bước tiếp theo

- Nếu mục 1–3 đạt: khởi động 24h; viết R028; tag `m6b1`.
- Mục nào không đạt: DỪNG, dán nguyên văn.

## Việc đang chạy

- **hids-m6b1-pre24h** — mục 1–3 trước 24h; binary `git_commit=1a88508`; bắt đầu 2026-10-19 ~17:15; dự kiến ~35–45 phút; log `out/jobs/m6b1-pre24h.log`, status `out/jobs/m6b1-pre24h.status`.
- Gate cũ `hids-m6b1-gate`: G8/G9a/G10 PASS; host data 600 dòng MONOTONIC_OK nhưng script exit=1 (`lines` unbound — lỗi bash, không đổi tiêu chí).

## Vướng mắc / chờ kiến trúc sư

- (không)
