# R046 — M6i-c5 AUROC đơn-chiều: chặn phản biện "ngưỡng dở" và định lượng R045 (c5_score 1.4.4)

1. Số báo cáo: **R046**. Ngày giờ: **2026-11-09 02:22** (giờ máy). Mốc: **M6i-c5**. Commit kiến trúc sư: `b865878`. Commit báo cáo: `PENDING`. Tag: `m6i.6`.

## Mục đích (nguyên văn nhiệm vụ)

R045 (ablation) cho thấy detector ngưỡng max|z| trên đặc trưng phân rã không tách lớp tấn công đổi-nhịp ở báo động giả thấp; cột song sinh chứng minh cú nhảy x_inst dưới D3-7 là hiệu ứng TẢI, không phải tín hiệu tấn công. M6i-c5 định lượng điều này THEO CÁCH KHÔNG PHỤ THUỘC NGƯỠNG: AUROC đơn-chiều (Mann-Whitney) của từng đặc trưng phân biệt (a) tấn công vs nền mức 0 — phép so NGÂY THƠ dễ gây ảo giác; (b) tấn công vs SONG SINH benign cùng mức tải — phép so CÓ KIỂM SOÁT. Kỳ vọng: (a) AUROC cao (tấn công khác nền rảnh — nhưng đó là khác do TẢI, không do độc hại); (b) AUROC ≈ 0,5 (tấn công không khác benign-cùng-tải) → chứng minh đặc trưng đơn lẻ không mang tín hiệu tấn công, bất kể ngưỡng. Đây là bằng chứng chặt cho negative result Bài 1 và mở đất Bài 2 (cần mô hình đa chiều học được + tải mạnh hơn). KHÔNG mô hình học — chỉ thống kê hạng.

## 2. Mục tiêu

Chạy chế độ `--auroc` (c5_score 1.4.4) trên lab1c; bảng vs-nền vs vs-song-sinh; hình H-auroc; R046. Không đo lại, không rsync, không ghi đè thư mục cũ (ra `-v144-`). Không sửa file kiến trúc sư.

## 3. Đã làm gì

- CAI `goi-195-m6ic5` XONG; sha `c8526ba14a46…`; commit `b865878`.
- (0) Hồi quy `score-v144-compat` vs R039: **KHOP**.
- (1) `--auroc` lab1c → bảng in stdout; file `auroc_don_chieu.tsv` khôi phục từ log (xem mục 7 — lỗi `outdir` của bản 1.4.4).
- (2) BẢNG R046 từ 6 chiều chỉ định.
- (3) Hình `out/c5-lab1/hinh-v144/H-auroc.svg`.
- (5) Đóng gói `/root/chep_file/luu-tru/HIDS-R046-<ngày>.zip` sau push.

## 4. Lệnh

```bash
python3 analysis/c5_score.py --features out/c5-prod/features_all.tsv \
  --train-until 434858090000000 --chieu-phanra A --ho-so tat --mien-tuyen-tinh \
  --n-toi-thieu 0 --dai-che-do khong --out out/c5-prod/score-v144-compat

python3 analysis/c5_score.py --features out/c5-lab1c/features_ghep.tsv \
  --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
  --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --auroc --out out/c5-lab1c/auroc-v144
```

## 5. Kết quả

### (a) Hồi quy

```
tom_tat first4: KHOP
scores_* first7: KHOP
tradeoff_*: KHOP
OK_ALL
User 105.92s Elapsed 1:48.72 RSS 3149652 kB
```

### (b) BẢNG R046 §2

Nguồn: `out/c5-lab1/r046-tables/bang_auroc.tsv` (rút từ `auroc_don_chieu.tsv`).

Tiêu chí đọc thẳng: `|AUROC−0,5| > 0,15` ở vs-song-sinh tại D1/D3 → có chút tín hiệu có kiểm soát.

**PHANRA_5tp**

| chieu | auroc vs_nen_muc0 | \|−0.5\| | vs_ss @0 | @D1-8 | @D1-16 | @D3-7 |
|-------|------------------:|--------:|---------:|------:|-------:|------:|
| dt_med | nan | nan | nan | nan | nan | nan |
| own_med | 0.7722 | 0.2722 | 0.1791 | 0.2750 | 0.2819 | 0.3245 |
| cpu_med | 0.8412 | 0.3412 | 0.2119 | 0.3206 | 0.3314 | 0.3299 |
| cpi_med | 0.2608 | 0.2392 | 0.3514 | 0.2887 | 0.3578 | 0.2471 |
| x_arr_med | 0.9612 | 0.4612 | 0.6136 | 0.4865 | 0.3873 | 0.2776 |
| x_inst_med | 0.9457 | 0.4457 | 0.5636 | 0.4772 | 0.5328 | **0.4740** |

**BASELINE_dt_tho**

| chieu | auroc vs_nen_muc0 | \|−0.5\| | vs_ss @0 | @D1-8 | @D1-16 | @D3-7 |
|-------|------------------:|--------:|---------:|------:|-------:|------:|
| dt_med | 0.7224 | 0.2224 | 0.1922 | 0.2676 | 0.2892 | 0.3882 |
| own_med | nan | nan | nan | nan | nan | nan |
| cpu_med | nan | nan | nan | nan | nan | nan |
| cpi_med | nan | nan | nan | nan | nan | nan |
| x_arr_med | 0.9612 | 0.4612 | 0.6136 | 0.4865 | 0.3873 | 0.2776 |
| x_inst_med | 0.9457 | 0.4457 | 0.5636 | 0.4772 | 0.5328 | **0.4740** |

Đối chiếu: vs-nền cao (ảo giác tải) — ví dụ `x_inst_med` 0.9457, `x_arr_med` 0.9612 — trong khi vs-song-sinh @D3-7 của `x_inst_med` = 0.4740 (|−0.5|=0.026).

Chiều vượt ngưỡng `|AUROC−0,5| > 0,15` ở vs-song-sinh D1/D3 (6 chiều chỉ định): `cpi_med`, `x_arr_med`, `own_med`, `cpu_med` (PHANRA); `dt_med` (BASELINE, chủ yếu D1). AUROC các ô này thường **< 0,5** (tấn công xếp hạng thấp hơn song sinh trên chiều đó).

### (c) Hình

| file | |
|------|--|
| `out/c5-lab1/hinh-v144/H-auroc.svg` | PHANRA: mỗi chiều — AUROC vs_nen_muc0 vs AUROC vs_song_sinh @D3-7; đường tham chiếu 0,5 |

### (d) Thời gian / RSS

| bộ | elapsed | RSS_kB | user_s |
|----|---------|-------:|-------:|
| prod-compat | 1:48.72 | 3149652 | 105.92 |
| lab1c-auroc | 1:28.35 | 1002960 | 87.25 |

### (e) sha256 (7 file)

```
c8526ba14a46b3e8ce2a2040e61e0840e51eb6a22b7eee3303c739346f06d0e7  analysis/c5_score.py
5b106f59840b0361f163f896b08bb24ca4781caea8cd374fa6eb379d885d8fd9  analysis/detector_c5.py
5bd8e40c64ae327e238b24f114add9c274e780e0bc391eb3f54f6fb81b545154  out/c5-lab1/r046-tables/BUG_outdir.txt
029cad982927fc255b9eacb0705a6410343deb7822cef2259d229f9fed18e1ef  docs/tasks/M6i.md
6d1028bc7b1fdd1744fbd65a91a6863a379f4e6786327407d109fcccae46c5d2  docs/STATE.md
a62cd0d4269d51eaafeb65f5df88ab668b0aeef1f95a4da2cd90c6c1b17b3e2f  reports/R046-m6ic5-auroc-don-chieu.md
947fcb91cba3a36b01e1d4d5a631cc68b6547f6709a5da4e1aa1ae1264e40f78  lab/muc-lab1c.tsv
```

## 6. File dữ liệu

- `out/c5-prod/score-v144-compat/`
- `out/c5-lab1c/auroc-v144/` (`auroc_don_chieu.tsv`, `log.txt`, `BUG_outdir.txt`)
- `out/c5-lab1/hinh-v144/`, `out/c5-lab1/r046-tables/`
- Không đụng score-v143-* / score-v142-* / features_*.

## 7. Quyết định đã tự đưa ra

1. **Lỗi kiến trúc sư không sửa:** `--auroc` dùng `outdir` trước khi gán (`outdir = a.out` nằm sau khối auroc) → `UnboundLocalError` sau khi đã in bảng ra stdout. Khôi phục `auroc_don_chieu.tsv` từ `log.txt`. Không sửa `c5_score.py`.
2. `dt_med` nan trên PHANRA / `own|cpu|cpi` nan trên BASELINE: cột không có giá trị hữu ích trên nhánh đó — ghi nan, không suy.
3. Ngưỡng “lệch rõ” theo nhiệm vụ: `|AUROC−0,5| > 0,15`.

## 8. KẾT LUẬN THẲNG

- **Ảo giác vs nền:** đúng kỳ vọng — nhiều chiều AUROC vs_nen_muc0 rất cao (`x_arr_med` 0.9612, `x_inst_med` 0.9457, `cpu_med` 0.8412).
- **Có kiểm soát (vs song sinh):** `x_inst_med` ≈ 0,5 ở mọi mức (D3-7: 0.4740, |−0.5|=0.026) — củng cố R045: inst không mang tín hiệu tấn công có kiểm soát.
- **Không phải mọi chiều ≈ 0,5:** lớn nhất trong 6 chiều chỉ định ở D1/D3 là **`cpi_med` @ D3-7**, AUROC=0.2471, **|AUROC−0,5|=0.2529** (PHANRA). Tiếp theo `x_arr_med` @D3-7 |−0.5|=0.2224; `own_med`/`cpu_med` cũng > 0,15 ở một số mức D1/D3.
- Các lệch > 0,15 thường là AUROC **dưới** 0,5 (hướng ngược), sức tách vừa — không đủ để nói “một chiều đơn lẻ tách rõ tấn công khỏi benign-cùng-tải” theo kiểu vận hành, nhưng cũng **không** được ghi câu “mọi chiều ≈ 0,5”.
- Phản biện “ngưỡng dở”: với `x_inst_med` (trọng tâm R045) AUROC có kiểm soát ≈ 0,5 → thất bại không do chọn ngưỡng max|z|. Các chiều own/cpu/cpi/arr có tín hiệu hạng yếu có kiểm soát nhưng detector max|z| đa chiều ở R043–R045 vẫn không tách D3 ở BDG thấp.

## 9. Việc người dùng cần làm tay

Tải zip lưu trữ bằng WinSCP từ `/root/chep_file/luu-tru/`.

## 10. Tiếp theo

Kiến trúc sư có thể sửa `outdir = a.out` trước khối `--auroc` (một dòng). Có thể cân nhắc Bài 2 (mô hình đa chiều học được) vì tín hiệu đơn-chiều có kiểm soát chỉ yếu/đảo chiều trên vài đặc trưng.

## Thay đổi ngoài phạm vi

```
 docs/STATE.md                               |  15 +++
 out/c5-lab1/hinh-v144/H-auroc.svg           |  47 ++++++++++
 out/c5-lab1/r046-tables/BUG_outdir.txt      |   3 +
 out/c5-lab1/r046-tables/auroc_don_chieu.tsv | 126 +++++++++++++++++++++++++
 out/c5-lab1/r046-tables/bang_auroc.tsv      |  13 +++
 out/c5-lab1/r046-tables/hoi_quy.txt         |   5 +
 out/c5-lab1/r046-tables/ket_luan.txt        |   2 +
 out/c5-lab1/r046-tables/sha256.txt          |   6 ++
 out/c5-lab1/r046-tables/thoi_gian.tsv       |   3 +
 out/c5-lab1c/auroc-v144/BUG_outdir.txt      |   3 +
 out/c5-lab1c/auroc-v144/auroc_don_chieu.tsv | 126 +++++++++++++++++++++++++
 out/c5-lab1c/auroc-v144/log.txt             | 130 ++++++++++++++++++++++++++
 reports/INDEX.md                            |   1 +
 reports/R046-m6ic5-auroc-don-chieu.md       | 137 ++++++++++++++++++++++++++++
 14 files changed, 617 insertions(+)
Không sửa detector_c5.py / logic AUROC kiến trúc sư. Không ghi đè score-v143-.
```
