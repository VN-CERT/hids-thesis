# R044 — M6i-c3 phép thử quyết định: nền trượt 24 giờ (c5_score 1.4.2)

1. Số báo cáo: **R044**. Ngày giờ: **2026-11-09 00:35** (giờ máy). Mốc: **M6i-c3**. Commit kiến trúc sư: `faea352`. Commit báo cáo: `56250d8`. Tag: `m6i.4` (đã push `github`).

## Bối cảnh (nguyên văn nhiệm vụ)

R043 (nền tĩnh): ở điểm vận hành báo động giả thấp (ngân sách 1 %), tải D3-7 KHÔNG tách khỏi nền (bdg D3-7 ≈ 0,0007 khi nền 1 %); tín hiệu D3 chỉ rõ ở mức phát hiện 0,90 (nơi ngưỡng bị kéo xuống rất thấp nên cả nền cũng báo động). Kết luận tạm: C5 ÂM TÍNH như detector vận hành với nền tĩnh. Giả thuyết: nền trôi 10–15 %/ngày (R041-b F3) nhấn chìm tín hiệu D3 nhỏ; nền TRƯỢT 24 giờ (median/MAD học trên 24 h liền trước mỗi cửa sổ, cùng hồ sơ) có thể khử trôi và làm D3 nhô lên ở ngân sách thấp. M6i-c3 là phép thử quyết định: nếu nền trượt tách được D3-7 ở báo động giả nền ≤ 5 % → C5 DƯƠNG TÍNH CÓ ĐIỀU KIỆN (cho tranh chấp bộ nhớ); nếu không → ÂM TÍNH CHỐT, bài đứng trên hệ đo + phát hiện vật lý + kết quả âm tính trung thực.

## 2. Mục tiêu

Phép thử nền trượt 24 h trên lab1c (A, D, E). Không ghi đè thư mục cũ (ra `score-v142-*`). Không kết luận đạt/không kiểu PASS/FAIL cổng; mục 8 ghi kết luận thẳng theo tiêu chí nhiệm vụ.

## 3. Đã làm gì

- CAI `goi-195-m6ic3` XONG; sha `75279c3e…`; commit `faea352`.
- (0) Hồi quy `score-v142-compat` vs R039: **KHOP**.
- (1) Lab1c CH∈{A,D,E} `--nen-truot-gio 24 --ho-so lop` + muc/nhãn như R043 → `out/c5-lab1c/score-v142-<CH>`.
- (2) **Không chạy production** — §1 không tách D3-7 ở bdg nền ≤ 5 %.
- (3) Hình `out/c5-lab1/hinh-v142/` (H-truot, H-troi).
- (5) Đóng gói `/root/chep_file/luu-tru/HIDS-R044-<ngày>.zip` sau push.

## 4. Lệnh

```bash
python3 analysis/c5_score.py --features out/c5-prod/features_all.tsv \
  --train-until 434858090000000 --chieu-phanra A --ho-so tat --mien-tuyen-tinh \
  --n-toi-thieu 0 --dai-che-do khong --out out/c5-prod/score-v142-compat

systemd-run --unit=hids-m6ic3-score --collect bash -c 'cd /root/hids && bash scripts/c5_m6ic3_score.sh'
# (không chạy prod vì không tách)
```

## 5. Kết quả

### (a) Hồi quy

```
KHOP tom_tat / scores_* (7 cột) / tradeoff_*
OK_ALL
```

### (b) BẢNG QUYẾT ĐỊNH §1

Tiêu chí đọc thẳng: với nền trượt, ở ngân sách có `bdg_nen_kiem_tra ≤ 0,05`, `muc_D3-7` có **> 3×** bdg nền không?

Nguồn: `out/c5-lab1/r044-tables/bang_quyet_dinh.tsv`.

| CH | branch | ngan_sach | bdg_nen_tinh | bdg_nen_truot | muc_D3-7_tinh | muc_D3-7_truot | muc_D1-16_tinh | muc_D1-16_truot | D3_gt_3x_nen_truot |
|----|--------|----------:|-------------:|--------------:|--------------:|---------------:|---------------:|----------------:|--------------------|
| A | PHANRA | 0.01 | 0 | 0 | 0 | 0 | 0.0138 | 0.0112 | KHONG |
| A | PHANRA | 0.05 | 0.0681 | 0.0681 | 0.0099 | 0.029 | 0.0257 | 0.0441 | NEN>0.05 |
| A | BASE | 0.01 | 0 | 0.0674 | 0 | 0 | 0.0138 | 0.0138 | NEN>0.05 |
| A | BASE | 0.05 | 0.0681 | 0.1168 | 0.0099 | 0.0639 | 0.0257 | 0.1017 | NEN>0.05 |
| D | PHANRA | 0.01 | 0 | 0 | 0.0007 | 0.0007 | 0.0158 | 0.002 | KHONG |
| D | PHANRA | 0.05 | 0.0683 | 0.0685 | 0.0079 | 0.0286 | 0.0234 | 0.0428 | NEN>0.05 |
| D | BASE | 0.01 | 0 | 0.0674 | 0 | 0 | 0.0138 | 0.0138 | NEN>0.05 |
| D | BASE | 0.05 | 0.0681 | 0.1168 | 0.0099 | 0.0639 | 0.0257 | 0.1017 | NEN>0.05 |
| E | PHANRA | 0.01 | 0 | 0.0676 | 0.0007 | 0.0007 | 0.0145 | 0.0145 | NEN>0.05 |
| E | PHANRA | 0.05 | 0.0683 | 0.1152 | 0.0105 | 0.0537 | 0.0263 | 0.0596 | NEN>0.05 |
| E | BASE | 0.01 | 0 | 0.0674 | 0 | 0 | 0.0138 | 0.0138 | NEN>0.05 |
| E | BASE | 0.05 | 0.0681 | 0.1168 | 0.0099 | 0.0639 | 0.0257 | 0.1017 | NEN>0.05 |

Đọc: **không bộ PHANRA nào** đạt `muc_D3-7 > 3× bdg_nen` khi `bdg_nen_truot ≤ 0,05`. Ở chỗ nền trượt ≤ 0,05 (A/D @0.01: nen=0), `muc_D3-7` cũng ≈ 0 — không tách. Ở @0.05, nền trượt đã > 0,05 và D3-7 vẫn ≤ nền. Nền trượt **không cứu** Δt thô (BASE) cũng không cứu PHANRA theo tiêu chí này.

### (c) §2 Production

**Bỏ.** Ghi: nền trượt không cứu, âm tính chốt — không chạy `score-v142-*-tid-truot`.

### (d) Hình

| file | |
|------|--|
| `out/c5-lab1/hinh-v142/H-truot_D3-7.svg` | CH=E: đường D3-7 tĩnh (`duong_tranh_chap`) vs điểm trượt (`nen_truot`) |
| `out/c5-lab1/hinh-v142/H-troi_bdg_nen.svg` | bdg nền @0.01: hai nửa cửa sổ nen (proxy) tĩnh vs trượt tổng |

Lab1c là **một phiên** (không phải ngày 6–7 lab 7 ngày): H-troi dùng median `start_ns` làm proxy hai nửa; chi tiết `out/c5-lab1/r044-tables/h_troi_bdg.tsv`.

### (e) Thời gian / RSS

| bộ | elapsed | RSS_kB | so với v141 (cùng CH, không trượt) |
|----|---------|-------:|-------------------------------------|
| lab1c A v142 | 2:32.11 | 1192056 | v141 ~1:10 → **chậm ~2×** |
| lab1c D v142 | 2:24.40 | 1192028 | |
| lab1c E v142 | 2:16.89 | 1192056 | v141 E ~1:03 |
| prod compat | 1:57.49 | 3076400 | |

### (f) sha256 (7 file)

```
75279c3e979c1837c6622d025cc43db71067ec6ae2a6715b52bedb511cb0b16c  analysis/c5_score.py
5b106f59840b0361f163f896b08bb24ca4781caea8cd374fa6eb379d885d8fd9  analysis/detector_c5.py
(docs/tasks/M6i.md, docs/STATE.md, scripts/c5_m6ic3_score.sh — ghi trong r044-tables/sha256.txt lúc commit)
```

(File đủ 7 dòng trong `out/c5-lab1/r044-tables/sha256.txt`.)

## 6. File dữ liệu

- `out/c5-prod/score-v142-compat/`
- `out/c5-lab1c/score-v142-{A,D,E}/` (+ `nen_truot_*.tsv`)
- `out/c5-lab1/hinh-v142/`, `out/c5-lab1/r044-tables/`
- Không đụng `score-v14*` / `score-v141*` / features lớn.

## 7. Quyết định đã tự đưa ra

1. Khi `bdg_nen_truot=0` và `muc_D3-7=0`: ghi **KHONG** tách (không coi 0>3×0 là tách có nghĩa).
2. H-troi: lab1c một phiên → proxy hai nửa theo median start; ghi rõ trong bảng.
3. Hình H-truot dùng CH=E (fallback theo PROMPT khi không bộ nào tách).

## 8. KẾT LUẬN THẲNG

**Nền trượt 24 giờ không cứu C5 → ÂM TÍNH CHỐT** (theo tiêu chí nhiệm vụ).

Số:
- PHANRA A/D/E: không dòng nào `D3_gt_3x_nen_truot=CO` khi `bdg_nen ≤ 0,05`.
- Ví dụ E @0.01 trượt: `bdg_nen=0.0676` (>5 %), `muc_D3-7=0.0007` ≪ nền.
- Ví dụ D @0.01 trượt: `bdg_nen=0`, `muc_D3-7=0.0007` — không tách lên trên nền vận hành.
- BASELINE cũng không được cứu (cùng kiểu: hoặc nen>5 %, hoặc D3≈0).

Bài C5 đứng trên hệ đo + phát hiện vật lý + kết quả âm tính trung thực với detector vận hành ở ngân sách báo động giả thấp.

## 9. Việc người dùng cần làm tay

Tải zip lưu trữ bằng WinSCP từ `/root/chep_file/luu-tru/` (sau khi tạo ở bước 5).

## 10. Tiếp theo

Không đề xuất đo thêm cho C5 phát hiện tranh chấp bộ nhớ bằng detector này ở ngân sách thấp. Kiến trúc sư có thể đóng mốc C5 hoặc chuyển trọng tâm sang hệ đo / phát hiện vật lý.

## Thay đổi ngoài phạm vi

```
 docs/STATE.md                                    |  10 ++
 out/c5-lab1/hinh-v142/H-troi_bdg_nen.svg         |  16 +++
 out/c5-lab1/hinh-v142/H-truot_D3-7.svg           |  12 ++
 out/c5-lab1/r044-tables/bang_quyet_dinh.tsv      |  13 +++
 out/c5-lab1/r044-tables/h_troi_bdg.tsv           |   4 +
 out/c5-lab1/r044-tables/ket_luan_tach.txt        |   1 +
 out/c5-lab1/r044-tables/lab1c-A-tom_tat_ns.tsv   |  10 ++
 out/c5-lab1/r044-tables/lab1c-D-tom_tat_ns.tsv   |  10 ++
 out/c5-lab1/r044-tables/lab1c-E-tom_tat_ns.tsv   |  10 ++
 out/c5-lab1/r044-tables/nen_truot_BASE_A.tsv     |   4 +
 out/c5-lab1/r044-tables/nen_truot_BASE_D.tsv     |   4 +
 out/c5-lab1/r044-tables/nen_truot_BASE_E.tsv     |   4 +
 out/c5-lab1/r044-tables/nen_truot_PHANRA_5tp.tsv |   4 +
 out/c5-lab1/r044-tables/nen_truot_PHANRA_A.tsv   |   4 +
 out/c5-lab1/r044-tables/nen_truot_PHANRA_D.tsv   |   4 +
 out/c5-lab1/r044-tables/nen_truot_PHANRA_E.tsv   |   4 +
 out/c5-lab1/r044-tables/sha256.txt               |   7 ++
 reports/INDEX.md                                 |   1 +
 reports/R044-m6ic3-nen-truot-quyet-dinh.md       | 135 +++++++++++++++++++++++
 scripts/c5_m6ic3_score.sh                        |  32 ++++++
 20 files changed, 289 insertions(+)
Không sửa detector_c5.py. Không ghi đè score-v141-/v14-.
```
