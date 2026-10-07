# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 16:45 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M6a:** Xong (tag `m6a`, R014). Chờ người dùng chạy E2 lần 3; sau đó chạy lại M5.

## Bước đã xong (M6a)
- Dừng M5, archive `validation/m5-20261007-truoc-m6a/`
- Sửa irq trừ steal, bản ghi 56 byte + `steal_off_ns`, công cụ, `m4.py` E2 prep
- Tự kiểm G7a/G7d, G3 S1–S5 → `validation/g3-20261007-m6a/`
- Commit `5121d30`, tag `m6a`, báo cáo R014

## Bước đang làm
Không (Cursor dừng theo nhiệm vụ M6a).

## Bước tiếp theo
- **Người dùng:** `sudo bash scripts/m4.sh e2` (E2 lần 3 trên mã M6a)
- Sau E2: chạy lại `scripts/m5.sh`

## Việc đang chạy
Không.

## Vướng mắc / chờ kiến trúc sư quyết định
- `steal_off` S2 G3 ≈ 4 ms (kỳ vọng ≈ 0 trên máy rảnh) — xem R014 mục 8.
