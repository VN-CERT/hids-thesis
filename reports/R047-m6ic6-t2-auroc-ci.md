# R047 — M6i-c6 gói thí nghiệm gộp: T² đa chiều + AUROC CI/p/null (c5_score v1.5)

1. Số báo cáo: **R047**. Ngày giờ: **2026-11-09 03:40** (giờ máy). Mốc: **M6i-c6**. Commit kiến trúc sư: `929c593`. Commit báo cáo: `704c86a`. Tag: `m6i.7`.

Ghi chú phiên bản: chuỗi `VERSION` trong file = `1.4.5`; nhiệm vụ/CAI gọi **v1.5**; sha khớp điều kiện.

## Mục đích (nguyên văn nhiệm vụ)

Chat viết bài (reviewer Q1) đòi ba thứ để câu kết C5 chặt: (1) detector NGƯỠNG ĐA CHIỀU (Hotelling T²/Mahalanobis) thay max|z| — chặn phản biện 'các anh dùng detector ngưỡng dở nhất'; nếu T² CŨNG không tách D3 ở báo động giả thấp → negative mạnh hơn hẳn. (2) NULL twin-vs-twin AUROC — chứng minh tấn-công-vs-song-sinh ngang với benign-vs-benign (nhiễu ngẫu nhiên). (3) CI95 bootstrap + p Mann-Whitney cho bảng AUROC — chuẩn thống kê Q1. M6i-c6 chạy cả ba. T² vẫn là detector NGƯỠNG (thống kê cố định, không học) nên trong phạm vi Bài 1; mô hình học để Bài 2.

## 2. Mục tiêu

AUROC đầy đủ (CI/p/null) + detector T² trên lab1c bộ A/D/E; so với max|z| R043; R047. Không đo lại, không rsync, không ghi đè (ra `-v15-`). Không sửa file kiến trúc sư.

## 3. Đã làm gì

- CAI `goi-195-m6ic6` XONG; sha `b82f4e23f3a6…`; commit `929c593`.
- (0) Hồi quy `score-v15-compat` vs R039: **KHOP**.
- (1) `--auroc` → `out/c5-lab1c/auroc-v15/` (đã ghi file; lỗi `outdir` R046 đã hết).
- (2) `--t2` CH∈{D,E,A} → `out/c5-lab1c/t2-v15-<CH>/`.
- (3) Hình `hinh-v15/` (H-t2, H-auroc-ci).
- (5) Zip lưu trữ sau push.

## 4. Lệnh

```bash
python3 analysis/c5_score.py --features out/c5-prod/features_all.tsv \
  --train-until 434858090000000 --chieu-phanra A --ho-so tat --mien-tuyen-tinh \
  --n-toi-thieu 0 --dai-che-do khong --out out/c5-prod/score-v15-compat

python3 analysis/c5_score.py --features out/c5-lab1c/features_ghep.tsv \
  --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
  --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --auroc --out out/c5-lab1c/auroc-v15

for CH in D E A; do
  python3 analysis/c5_score.py --features out/c5-lab1c/features_ghep.tsv \
    --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
    --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --chieu-phanra $CH --t2 \
    --out out/c5-lab1c/t2-v15-$CH
done
```

## 5. Kết quả

### (a) Hồi quy

```
tom_tat first4: KHOP
scores_* first7: KHOP
tradeoff_*: KHOP
OK_ALL
User 106.88s Elapsed 1:49.80 RSS 3149460 kB
```

### (b) BẢNG R047-A — AUROC CI/p/null (rút)

Nguồn đầy đủ: `out/c5-lab1/r047-tables/bang_auroc_ci.tsv` / `auroc_don_chieu.tsv`.

**PHANRA — x_inst_med & cpi_med (hai chiều đáng chú ý)**

| chieu | so_sanh | muc | auroc | CI95 | p | CI∌0.5? |
|-------|---------|-----|------:|------|--:|--------|
| x_inst_med | vs_nen_muc0 | * | 0.9457 | nan | 1.28e-133 | (chỉ p) |
| x_inst_med | vs_song_sinh | D3-7 | 0.4740 | [0.3583, 0.6039] | 0.672 | NO |
| x_inst_med | null_twin_twin | D3-7 | 0.5150 | [0.3362, 0.7063] | 0.871 | NO |
| cpi_med | vs_nen_muc0 | * | 0.2608 | nan | 8.51e-40 | (chỉ p) |
| cpi_med | vs_song_sinh | D3-7 | 0.2471 | [0.1397, 0.3603] | 3.69e-05 | **YES** |
| cpi_med | null_twin_twin | D3-7 | 0.4662 | [0.2825, 0.6562] | 0.715 | NO |

Đọc thẳng:

- (a) vs_nen cao/ảo đúng kỳ vọng (`x_inst_med` 0.95).
- (b) Chiều có `|AUROC−0,5|>0,15` **và** CI không chứa 0,5 ở D1/D3 (6 chiều): `cpi_med`, `own_med`, `cpu_med`, `x_arr_med` (PHANRA); `dt_med`/`x_arr_med` (BASELINE). AUROC thường **< 0,5**. `x_inst_med` **không** (CI chứa 0,5).
- (c) `null_twin_twin` ≈ 0,5 (trong 6 chiều, |AUROC−0,5| max ≈ 0,12; hầu hết CI chứa 0,5). `cpi_med` vs_song_sinh @D3-7 (0.247) **khác** null cùng mức (0.466) — tín hiệu có kiểm soát trên cpi, không phải nhiễu twin.

### (c) BẢNG R047-B — T² vs max|z| (CỐT LÕI)

Nguồn: `out/c5-lab1/r047-tables/bang_t2_vs_maxz.tsv`. max|z| lấy `score-v141-*` (R043), PHANRA.

| CH | ngan_sach | maxz bdg_nen | maxz phat | maxz D3-7 | maxz D1-8 | T² bdg_nen | T² phat | T² D3-7 | T² D1-8 | T² muc_0 |
|----|----------:|-------------:|----------:|----------:|----------:|-----------:|--------:|--------:|--------:|---------:|
| A | 0.01 | 0.0000 | 0.0000 | 0.0000 | 0.0041 | 0.0087 | 0.3189 | **0.4118** | 0.3922 | 0.1980 |
| A | 0.05 | 0.0681 | 0.0000 | 0.0099 | 0.0213 | 0.0530 | 0.8110 | 0.7843 | 0.7843 | 0.8515 |
| D | 0.01 | 0.0000 | 0.0000 | 0.0007 | 0.0081 | 0.0068 | 0.4072 | **0.4595** | 0.4595 | 0.3214 |
| D | 0.05 | 0.0683 | 0.2717 | 0.0079 | 0.0213 | 0.0548 | 1.0000 | 1.0000 | 1.0000 | 1.0000 |
| E | 0.01 | 0.0000 | 0.0000 | 0.0007 | 0.0047 | 0.0079 | 0.3583 | **0.3922** | 0.3922 | 0.2871 |
| E | 0.05 | 0.0683 | 0.2717 | 0.0105 | 0.0220 | 0.0400 | 0.3740 | 0.4118 | 0.3922 | 0.3168 |

Đọc thẳng @ ngân sách 0,01: **T² tách D3-7 rõ** (0,39–0,46) trong khi max|z| ≈ 0 và bdg_nen T² vẫn thấp (0,007–0,009). T² cũng nâng `muc_0` tấn công (0,20–0,32) — không chỉ D3. Kết: **không** còn câu “kể cả T² cũng không tách”; C5 **dương tính có điều kiện với detector ngưỡng đa chiều T²**.

### (d) Hình

| file | |
|------|--|
| `out/c5-lab1/hinh-v15/H-t2.svg` | muc_D3-7 @0.01: max|z| vs T² cho A/D/E |
| `out/c5-lab1/hinh-v15/H-auroc-ci.svg` | AUROC+CI95 ba so_sanh cho x_inst_med & cpi_med |

### (e) Thời gian / RSS

| bộ | elapsed | RSS_kB | user_s |
|----|---------|-------:|-------:|
| prod-compat | 1:49.80 | 3149460 | 106.88 |
| lab1c-auroc | 1:51.67 | 1008312 | 110.48 |
| lab1c-t2-D | 1:13.55 | 1116864 | 72.55 |
| lab1c-t2-E | 1:10.59 | 1101192 | 69.79 |
| lab1c-t2-A | 1:09.09 | 1132792 | 68.26 |

### (f) sha256 (7 file)

```
b82f4e23f3a617bdf914671e89b27d08deeaf0c6061fd34e3dda9b47ce0a0d6e  analysis/c5_score.py
5b106f59840b0361f163f896b08bb24ca4781caea8cd374fa6eb379d885d8fd9  analysis/detector_c5.py
11d68f6f14a2761f58fa23bfae36e43628124da97c0d54f58abbf890daca5e21  scripts/c5_m6ic6_run.sh
3403ab760c3afbf8b62b7e0314cb65d2403eb21fb9b8d94c09ece2b5a4859553  docs/tasks/M6i.md
c779b2c739076281d12983fcc40b670220986cbf01d5db9ef8e9b1ab1b7a821b  docs/STATE.md
b87a43b8576e2481bc70a31d3f7c4786aaf98738c3fb8b0f309a5a9bbd7a33a4  reports/R047-m6ic6-t2-auroc-ci.md
947fcb91cba3a36b01e1d4d5a631cc68b6547f6709a5da4e1aa1ae1264e40f78  lab/muc-lab1c.tsv
```

## 6. File dữ liệu

- `out/c5-prod/score-v15-compat/`
- `out/c5-lab1c/auroc-v15/`, `out/c5-lab1c/t2-v15-{A,D,E}/`
- `out/c5-lab1/hinh-v15/`, `out/c5-lab1/r047-tables/`
- Không đụng auroc-v144 / score-v143-* / score-v141-* / features_*.

## 7. Quyết định đã tự đưa ra

1. So max|z| với `score-v141-*` (R043, cùng lab1c `--ho-so lop`) — gần nhất với bộ A/D/E đã công bố.
2. T² theo lệnh nhiệm vụ (không `--train-until` → cắt 70% mặc định; fit hiệp phương sai gộp nền muc 0) — khác hồ sơ lop của max|z|; ghi rõ khi đọc số.
3. “Tách” T²: so `muc_D3-7` với `bdg_nen` cùng ngân sách (không yêu cầu >3× như R044).

## 8. KẾT LUẬN THẲNG

1. **T² có tách D3 ở báo động giả thấp:** có. Ví dụ PHANRA D @0.01: `muc_D3-7=0.4595` vs `bdg_nen=0.0068` (max|z| cùng chỗ: D3-7=0.0007, phat=0). E/A tương tự (~0,39–0,41 vs bdg ~0,008).
2. **null twin-vs-twin ≈ 0,5:** có (6 chiều chỉ định; |AUROC−0,5| max ~0,12; CI thường chứa 0,5).
3. **AUROC vs-song-sinh khác 0,5 có ý nghĩa (CI∌0,5):** có trên `cpi_med` (D3-7: 0.247 [0.140, 0.360]), `own_med`, `cpu_med`, `x_arr_med`, …; **`x_inst_med` không** (D3-7 CI [0.358, 0.604]).
4. **Kết C5:** không còn negative chốt kiểu “mọi detector ngưỡng đều thất bại”. **Dương tính có điều kiện với Hotelling T²** (ngưỡng đa chiều, không học). max|z| vẫn âm tính như R043–R045; phản biện “max|z| dở” có chỗ đứng một phần — T² cứu được phát hiện ở BDG thấp trên lab1c. Bài 2 (học đa chiều) vẫn mở nếu cần cải thiện thêm / tổng quát hóa.

## 9. Việc người dùng cần làm tay

Tải zip từ `/root/chep_file/luu-tru/`.

## 10. Tiếp theo

Kiến trúc sư có thể: (i) chạy lại T² với cùng `train-until` + hồ sơ lop như max|z| để so sánh công bằng hơn; (ii) phân tích vì sao `muc_0` tấn công cũng cao dưới T²; (iii) quyết định câu kết bài C5 theo T².

## Thay đổi ngoài phạm vi

```
(điền sau commit)
Không sửa detector_c5.py. Không ghi đè thư mục -v144/-v143/-v141.
```
