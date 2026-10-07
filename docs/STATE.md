# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 18:55 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M5 (m6a):** Chạy lại overhead collector; output `validation/m5-20261007-m6a/`.

## Chạy lại cho bài báo
- **E2:** Bản cuối dùng `stress-ng --cpu-method int64` cho tải nền C3 trong M5. E2 lần 3 dùng phương pháp mặc định của stress-ng, có thể tranh chấp bộ nhớ → cpu trung bình dao động ~1–9%.

## Bước đã xong
- E2 lần 3, R015 (`d227f9f`)
- M6a tag, R014

## Bước đang làm
- Khởi động `scripts/m5.sh` (m6a, OUTROOT `validation/m5-20261007-m6a`).

## Bước tiếp theo
- Khi M5 xong: tag `m5`, báo cáo R016.

## Việc đang chạy
- **hids-m5-m6a** — `systemd-run --unit=hids-m5-m6a` — bắt đầu sau commit M5 script — dự kiến nhiều giờ — log `out/jobs/m5-m6a.log` — trạng thái `out/jobs/m5-m6a.status`

## Vướng mắc / chờ kiến trúc sư
- Không.
