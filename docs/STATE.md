# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-08 11:30 (giờ máy)

## Mốc hiện tại và mục tiêu
- **M5c:** Xong R018, tag `m5c` trên `ac5b8cf`. O1 bỏ; O4 thử fentry (giữ tracepoint); O5 không làm.

## Bước đã xong
- M5c chẩn đoán `validation/m5c-20261008/diag/`, regress fentry, fixed-rate tracepoint, G7 fentry + G3 `validation/g3-20261008-v3/`
- R018, tag `m5c` (commit `ac5b8cf`)

## Bước đang làm
Không.

## Bước tiếp theo
Chờ kiến trúc sư (BPF stats / baseline T1); hoặc mốc M6 tiếp theo.

## Việc đang chạy
Không.

## Vướng mắc / chờ kiến trúc sư
- `bpf-hids.tsv` rỗng dưới tải → O5 chưa đủ điều kiện.
- T1-C0 mini ~142 ns vs M5b ~195 ns (so chi phí quan sát).
