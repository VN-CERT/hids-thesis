# R048 — M6i-c7: T² công bằng cùng train-until max|z|

1. Số báo cáo: **R048**. Ngày giờ: **2026-11-09 04:03** (giờ máy). Mốc: **M6i-c7**. Commit: `790b403`. Tag: `m6i.8`.

Ghi chú: `sha256(analysis/c5_score.py)=b82f4e23…` khớp điều kiện nhiệm vụ; chuỗi `VERSION` trong file vẫn `1.4.5` (như R047).

## 2. Mục tiêu

Xác nhận Hotelling T² với **cùng** `--train-until 1006289550843307` như max|z| (R043); so cạnh T²-R047 (cắt 70% mặc định) và max|z|-R043 (bảng R047-B). Không ghi đè `t2-v15-*`. Không kết luận.

## 3. Đã làm gì

- Lưu nhiệm vụ `docs/tasks/M6i-c7.md`.
- Chạy T² fair → `out/c5-lab1c/t2fair-v15-{D,E,A}/` (unit `hids-m6ic7-t2fair`, exit=0).
- Bảng so: `out/c5-lab1/r048-tables/bang_t2fair_vs_r047_maxz.tsv`.
- Mục 2 (20 cửa sổ muc_0 + đóng góp chiều): **để sau** (`--t2` không ghi điểm từng cửa sổ / phân rã đóng góp).

## 4. Lệnh

```bash
sha256sum analysis/c5_score.py
# b82f4e23f3a617bdf914671e89b27d08deeaf0c6061fd34e3dda9b47ce0a0d6e

for CH in D E A; do
  python3 analysis/c5_score.py \
    --features out/c5-lab1c/features_ghep.tsv \
    --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
    --muc lab/muc-lab1c.tsv --n-toi-thieu 30 \
    --train-until 1006289550843307 \
    --chieu-phanra $CH --t2 \
    --out out/c5-lab1c/t2fair-v15-$CH
done
```

## 5. Kết quả

### (a) Bảng so @ ngân sách 0,01 và 0,05 (PHANRA)

Nguồn fair: `out/c5-lab1c/t2fair-v15-$CH/t2_tradeoff.tsv`. T²-R047 / max|z|: bảng R047-B (`out/c5-lab1/r047-tables/bang_t2_vs_maxz.tsv`).

| CH | ns | fair bdg_nen | fair phat | fair D3-7 | fair muc_0 | T²-R047 bdg | T²-R047 phat | T²-R047 D3-7 | T²-R047 muc_0 | maxz bdg | maxz phat | maxz D3-7 | fair=R047? |
|----|---:|-------------:|----------:|----------:|-----------:|------------:|-------------:|-------------:|--------------:|---------:|----------:|----------:|:----------:|
| A | 0.01 | 0.0087 | 0.3189 | 0.4118 | 0.1980 | 0.0087 | 0.3189 | 0.4118 | 0.1980 | 0.0000 | 0.0000 | 0.0000 | 1 |
| A | 0.05 | 0.0530 | 0.8110 | 0.7843 | 0.8515 | 0.0530 | 0.8110 | 0.7843 | 0.8515 | 0.0681 | 0.0000 | 0.0099 | 1 |
| D | 0.01 | 0.0068 | 0.4072 | 0.4595 | 0.3214 | 0.0068 | 0.4072 | 0.4595 | 0.3214 | 0.0000 | 0.0000 | 0.0007 | 1 |
| D | 0.05 | 0.0548 | 1.0000 | 1.0000 | 1.0000 | 0.0548 | 1.0000 | 1.0000 | 1.0000 | 0.0683 | 0.2717 | 0.0079 | 1 |
| E | 0.01 | 0.0079 | 0.3583 | 0.3922 | 0.2871 | 0.0079 | 0.3583 | 0.3922 | 0.2871 | 0.0000 | 0.0000 | 0.0007 | 1 |
| E | 0.05 | 0.0400 | 0.3740 | 0.4118 | 0.3168 | 0.0400 | 0.3740 | 0.4118 | 0.3168 | 0.0683 | 0.2717 | 0.0105 | 1 |

Mọi dòng: `fair_eq_R047=1` (cùng `n_train=502334`).

### (b) Đọc thẳng @ ns=0,01 (số cạnh nhau)

| CH | fair muc_D3-7 | fair bdg_nen | maxz D3-7 (R047-B) |
|----|--------------:|-------------:|-------------------:|
| D | 0.4595 | 0.0068 | 0.0007 |
| E | 0.3922 | 0.0079 | 0.0007 |
| A | 0.4118 | 0.0087 | 0.0000 |

### (c) Mục 2 — 20 cửa sổ tấn công muc_0

**để sau** (`--t2` chỉ ghi `t2_tradeoff.tsv`, không xuất điểm/cửa sổ hay đóng góp từng chiều).

### (d) Thời gian

| bộ | elapsed (wall) |
|----|----------------|
| t2fair-D | ~1:13 (trong khung 03:54–03:55) |
| t2fair-E | ~1:15 |
| t2fair-A | ~1:12 |
| tổng unit | 03:54:46 → 03:58:26 |

## 6. File dữ liệu

- `out/c5-lab1c/t2fair-v15-D/` `t2fair-v15-E/` `t2fair-v15-A/` (`t2_tradeoff.tsv`, `log.txt`, `time.txt`)
- `out/c5-lab1/r048-tables/bang_t2fair_vs_r047_maxz.tsv`
- Không đụng `t2-v15-*`, `score-v141-*`, `features_ghep.tsv`.

## 7. Quyết định tự đưa ra

1. Ra thư mục `t2fair-v15-$CH` (không ghi đè `t2-v15-*`).
2. Bảng so lấy max|z| đúng cột R047-B (không tính lại max|z|).
3. Mục 2 ghi "để sau" vì thiếu xuất điểm từng cửa sổ từ `--t2`.

## 8. Cần kiến trúc sư quyết định

(không trong phạm vi rút gọn)

## 9. Việc người dùng cần làm tay

(không)

## 10. Lỗi còn tồn tại / việc tiếp theo đề xuất

- Mục 2 (top-20 + đóng góp chiều) chưa làm.
