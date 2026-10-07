# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-07 21:35 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M5b:** Tối ưu overhead (O1–O3 xong); chẩn đoán bước 1, G7/G3, đo lại M5, R017, tag `m5b`.

## Bước đã xong
- O1 ringbuf NO_WAKEUP + poll 10 ms (`7e9e915`)
- O3 zstd + recfmt (`dd54480`)
- M5b task, `-discard`, `m5b_diag.sh`, `m5b.sh` (`8235e7d`, `30e2d4c`)
- M5 m6a (tag `m5`, R016)

## Bước đang làm
Chạy kiểm chứng M5b (diag, G7, G3, ma trận M5).

## Bước tiếp theo
Hoàn tất `m5b.sh`, viết R017, gắn tag `m5b`. O4 chỉ nếu C2 > 3% sau đo.

## Việc đang chạy
| Tên | Lệnh | Bắt đầu | Log |
|-----|------|---------|-----|
| hids-m5b-diag | `scripts/m5b_diag.sh` | ~21:30 | `out/jobs/m5b-diag.log`, `validation/m5b-20261007/diag/` |
| hids-g7-m5b | `g7.sh a; g7.sh d; g7.sh b-nho` | ~21:35 | `out/jobs/g7-m5b.log` |

## Vướng mắc / chờ kiến trúc sư
- O4 (fentry `x64_sys_call`) chưa làm; chờ kết quả C2 sau M5b.
