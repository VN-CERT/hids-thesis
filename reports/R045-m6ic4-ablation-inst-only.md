# R045 — M6i-c4 ablation "chỉ-inst": quy trách nhiệm vì sao bộ chiều có x_inst vẫn sụp dưới D3 (c5_score 1.4.3)

1. Số báo cáo: **R045**. Ngày giờ: **2026-11-09 02:00** (giờ máy). Mốc: **M6i-c4**. Commit kiến trúc sư: `33fd542`. Commit báo cáo: `6bf13cc` (bổ sung hash `9b488d0`). Tag: `m6i.5`.

## Câu hỏi khoa học (nguyên văn nhiệm vụ)

R043/R044: bộ chiều D (arr+inst+own_cv) và E (own+inst) CHỨA x_inst — đại lượng R041-d chứng minh gần hằng số qua 7 ngày (nginx worker +1,8 % trong khi cpu +19 %, cpi +16 %) — nhưng detector max|z| vẫn sụp dưới D3 (không tách ở báo động giả thấp). Giả thuyết: max|z| lấy CỰC ĐẠI qua chiều, nên một chiều NHIỄU (own hoặc arr biến thiên theo lưu lượng request) làm nổ điểm, nhấn chìm tính bất biến của inst. M6i-c4 quy trách nhiệm bằng ablation: chấm detector với từng tập con chiều và SO cả hai trục — báo động giả (trên nền trôi) VÀ phát hiện (trên cửa sổ tấn công). Kết luận có thể: (1) chỉ-inst KHÔNG sụp false-alarm dưới D3 nhưng cũng KHÔNG phát hiện tấn công (inst bất biến cả hai chiều → vô dụng kiểu khác); (2) chỉ-inst tách được tấn công ở báo động giả thấp (→ chiều own/arr là thủ phạm, bằng chứng lõi + hình mạnh nhất bài); (3) không rõ. Báo cáo trung thực cái nào.

## 2. Mục tiêu

Ablation lab1c các tập chiều I / Iarr / own_only / arr_only / E / D (c5_score 1.4.3, detector 1.3 giữ nguyên). Không đo lại, không rsync, không ghi đè thư mục cũ (ra `-v143-`). Không kết luận đạt/không kiểu PASS/FAIL cổng; mục 8 ghi kết luận thẳng theo (1)/(2)/(3).

## 3. Đã làm gì

- CAI `goi-195-m6ic4` XONG; sha `59a537a24ffe…`; commit `33fd542`.
- (0) Hồi quy `score-v143-compat` vs R039: **KHOP** (tom_tat 4 cột / scores_* 7 cột / tradeoff_* byte).
- (1) Lab1c CH∈{I,Iarr,own_only,arr_only,E,D} `--ho-so lop` nền tĩnh → `out/c5-lab1c/score-v143-<CH>` (unit `hids-m6ic4-score` exit=0).
- (2) BẢNG ABLATION PHANRA @0.01 và @0.05.
- (3) Phân tích x_inst_med tấn công D3-7 vs nền theo lớp dịch vụ.
- (4) Hình `out/c5-lab1/hinh-v143/H-ablation.svg`.
- (6) Đóng gói `/root/chep_file/luu-tru/HIDS-R045-<ngày>.zip` sau push.

## 4. Lệnh

```bash
python3 analysis/c5_score.py --features out/c5-prod/features_all.tsv \
  --train-until 434858090000000 --chieu-phanra A --ho-so tat --mien-tuyen-tinh \
  --n-toi-thieu 0 --dai-che-do khong --out out/c5-prod/score-v143-compat

systemd-run --unit=hids-m6ic4-score --collect bash -c 'cd /root/hids && bash scripts/c5_m6ic4_score.sh'
```

## 5. Kết quả

### (a) Hồi quy

```
score-v143-compat vs out/c5-prod/score (R039)
tom_tat first4: KHOP
scores_* first7: KHOP
tradeoff_*: KHOP (byte)
OK_ALL
time: User 116.67s Elapsed 1:59.94 RSS 3077264 kB
```

### (b) BẢNG ABLATION §2 (PHANRA)

Nguồn: `out/c5-lab1/r045-tables/bang_ablation.tsv`.

Cổng CH=I: ngưỡng @0.01 = **71.5542** (không 1e12). x_inst_med không MAD=0. `n_huan_luyen` PHANRA I = 167762 (thấp hơn ~502k của E/D) vì nhiều cửa sổ thiếu x_inst_med (PMU sample).

| CH | ngan_sach | bdg_nen_kiem_tra | phat_hien | theo_muc D3-7 | theo_muc D1-8 | nguong |
|----|----------:|-----------------:|----------:|--------------:|--------------:|-------:|
| I | 0.01 | 0.0081 | 0.3228 | 0.0263 | 0.0151 | 71.5542 |
| I | 0.05 | 0.0701 | 0.4173 | 0.0768 | 0.0591 | 9.1703 |
| Iarr | 0.01 | 0.0000 | 0.0000 | 0.0007 | 0.0081 | 45869.3369 |
| Iarr | 0.05 | 0.0737 | 0.3228 | 0.0194 | 0.0220 | 66.0871 |
| own_only | 0.01 | 0.0000 | 0.0000 | 0.0000 | 0.0041 | 65511.0762 |
| own_only | 0.05 | 0.0681 | 0.0000 | 0.0099 | 0.0213 | 1216.6801 |
| arr_only | 0.01 | 0.0000 | 0.0000 | 0.0000 | 0.0075 | 45869.3369 |
| arr_only | 0.05 | 0.0719 | 0.3299 | 0.0218 | 0.0292 | 70.8568 |
| E | 0.01 | 0.0000 | 0.0000 | 0.0007 | 0.0047 | 65511.0762 |
| E | 0.05 | 0.0683 | 0.2717 | 0.0105 | 0.0220 | 1216.8462 |
| D | 0.01 | 0.0000 | 0.0000 | 0.0007 | 0.0081 | 45868.9904 |
| D | 0.05 | 0.0683 | 0.2717 | 0.0079 | 0.0213 | 1221.3397 |

Đọc thẳng @0.01:

- **I**: bdg nền thấp (0.0081); `phat_hien` tổng 0.3228 — nhưng `phat_hien_id` cho thấy **B1@D3-7 = 0.0000** (tấn công bộ nhớ nginx); phần phát hiện đến từ **B4** (stress-ng ≈0.645). `theo_muc D3-7 = 0.0263` không cao.
- **Iarr / own_only / arr_only / E / D**: `phat_hien = 0`, `theo_muc D3-7 ≈ 0` — không tách ở ngân sách 1 %.
- Không tập nào có **phát_hien cao ở D3-7** kèm bdg nền thấp theo nghĩa tách tấn công bộ nhớ.

### (c) §3 x_inst dưới tấn công D3-7

Nguồn: `out/c5-lab1/r045-tables/x_inst_duoi_tan_cong.tsv` (PHANRA, x_n_pmu≥3; ánh xạ R041-b: 76058=nginx, 75979=postgres).

| lop_dich_vu | cgroup_id | n_nen | med_nen | n_tan_cong_D3_7 | med_tan_cong_D3_7 | ti_so | n_song_sinh_D3_7 | med_song_sinh_D3_7 |
|-------------|----------:|------:|--------:|----------------:|------------------:|------:|-----------------:|-------------------:|
| nginx | 76058 | 86003 | 808.0 | 238 | 806.0 | **0.998** | 406 | 823.0 |
| postgres | 75979 | 422599 | 210.0 | 811 | 3008.0 | 14.324 | 1611 | 3008.0 |

- **nginx** (nạn nhân B1): tỉ số tấn công/nền ≈ **1** → x_inst **không đổi** dưới tấn công bộ nhớ D3.
- **postgres**: med tấn công = med song sinh D3-7 = 3008 → mức tăng theo **cửa sổ mức D3-7** (cả tấn công lẫn song sinh), không phải tín hiệu riêng của tấn công.

### (d) Hình

| file | |
|------|--|
| `out/c5-lab1/hinh-v143/H-ablation.svg` | 6 tập chiều × (bdg_nen, phat_hien, theo_muc D3-7) @ ngân sách 0.01 |

### (e) Thời gian / RSS

| bộ | elapsed | RSS_kB | user_s |
|----|---------|-------:|-------:|
| prod-compat | 1:59.94 | 3077264 | 116.67 |
| lab1c-I | 0:55.27 | 1161568 | 54.33 |
| lab1c-Iarr | 0:56.39 | 1159032 | 55.55 |
| lab1c-own_only | 1:04.40 | 1158884 | 63.40 |
| lab1c-arr_only | 0:59.72 | 1158844 | 58.83 |
| lab1c-E | 1:05.82 | 1161636 | 64.79 |
| lab1c-D | 1:04.79 | 1161620 | 63.88 |

### (f) sha256 (7 file)

```
59a537a24ffef0365ee4d49a38e472aaa513d08edd0c7c18093ca8dda76ae197  analysis/c5_score.py
5b106f59840b0361f163f896b08bb24ca4781caea8cd374fa6eb379d885d8fd9  analysis/detector_c5.py
a264ead0fb8b9642a66d55c2ffd286778af5701bd09770e457a19146e26391df  scripts/c5_m6ic4_score.sh
258a464ed9783edff58a9509749ee367095c13b75e7492cce67a4a199c59d819  docs/tasks/M6i.md
a26b6e4d656020430ecf9f6fd43b3ddcf6dd372da5476e452a5e2330377fbefd  docs/STATE.md
e5ea66b4e4857245f336006cf7cb96b22e399142ee88b387d2388adbb0ec0148  reports/R045-m6ic4-ablation-inst-only.md
947fcb91cba3a36b01e1d4d5a631cc68b6547f6709a5da4e1aa1ae1264e40f78  lab/muc-lab1c.tsv
```


## 6. File dữ liệu

- `out/c5-prod/score-v143-compat/`
- `out/c5-lab1c/score-v143-{I,Iarr,own_only,arr_only,E,D}/`
- `out/c5-lab1/hinh-v143/`, `out/c5-lab1/r045-tables/`
- Không đụng `score` / `score-v13*` / `score-v14*` / `score-v141*` / `score-v142*` / `features_*`.

## 7. Quyết định đã tự đưa ra

1. Bảng ablation lấy `phat_hien` + `bdg_nen_kiem_tra` từ `tom_tat_ngan_sach`, `theo_muc D3-7/D1-8` từ `theo_muc_ns_PHANRA_5tp`.
2. §3: cửa sổ tấn công = giao nhãn lop≠N muc=D3-7; nền = `nguon=nen` cùng cgroup; thêm cột song sinh D3-7 để phân biệt tín hiệu kỳ/môi trường.
3. Kết luận (1)/(2) đọc theo **tấn công bộ nhớ B1@D3-7**, không gộp B4 stress-ng vào “tách D3”.

## 8. KẾT LUẬN THẲNG

**Kết luận (1):** chỉ-inst **không** sụp false-alarm kiểu ngưỡng 1e12 ở ngân sách thấp (bdg_nen @0.01 = 0.0081), nhưng cũng **không** phát hiện tấn công bộ nhớ D3 (B1@D3-7 = 0.0000). x_inst trên nginx tỉ số tấn công/nền ≈ 1 (bất biến cả hai chiều) → vô dụng kiểu khác cho phát hiện D3.

Số:

- I @0.01: bdg_nen=0.0081; phat_hien tổng=0.3228 nhưng B1@D3-7=0; theo_muc D3-7=0.0263.
- E/D/Iarr/own_only/arr_only @0.01: phat_hien=0, D3-7≈0 — không cứu bằng cách bỏ own/arr.
- nginx med_nen=808, med_tan_cong_D3_7=806, ti_so≈0.998.
- Không đạt (2): không có tập chiều nào tách tấn công bộ nhớ ở báo động giả thấp.

Giả thuyết “own/arr nhiễu nhấn chìm inst” **không** được chứng minh bằng ablation này: bỏ own/arr (tập I) vẫn không phát hiện B1@D3-7 vì bản thân x_inst không đổi dưới tấn công.

## 9. Việc người dùng cần làm tay

Tải zip lưu trữ bằng WinSCP từ `/root/chep_file/luu-tru/` (sau khi tạo ở bước 6).

## 10. Tiếp theo

Không đề xuất thêm ablation chiều cho detector max|z| trên D3 với x_inst. Kiến trúc sư có thể đóng chuỗi C5 hoặc chuyển trọng tâm sang hệ đo / phát hiện vật lý (đã âm tính chốt ở R044).

## Thay đổi ngoài phạm vi

```
 docs/STATE.md                                      |  17 +++
 out/c5-lab1/hinh-v143/H-ablation.svg               |  65 +++++++++
 out/c5-lab1/r045-tables/bang_ablation.tsv          |  13 ++
 out/c5-lab1/r045-tables/cong_I.txt                 |   4 +
 out/c5-lab1/r045-tables/hoi_quy.txt                |   6 +
 out/c5-lab1/r045-tables/lab1c-D-theo_muc_ns.tsv    |  13 ++
 out/c5-lab1/r045-tables/lab1c-D-tom_tat_ns.tsv     |  10 ++
 out/c5-lab1/r045-tables/lab1c-E-theo_muc_ns.tsv    |  13 ++
 out/c5-lab1/r045-tables/lab1c-E-tom_tat_ns.tsv     |  10 ++
 out/c5-lab1/r045-tables/lab1c-I-theo_muc_ns.tsv    |  13 ++
 out/c5-lab1/r045-tables/lab1c-I-tom_tat_ns.tsv     |  10 ++
 out/c5-lab1/r045-tables/lab1c-Iarr-theo_muc_ns.tsv |  13 ++
 out/c5-lab1/r045-tables/lab1c-Iarr-tom_tat_ns.tsv  |  10 ++
 .../r045-tables/lab1c-arr_only-theo_muc_ns.tsv     |  13 ++
 .../r045-tables/lab1c-arr_only-tom_tat_ns.tsv      |  10 ++
 .../r045-tables/lab1c-own_only-theo_muc_ns.tsv     |  13 ++
 .../r045-tables/lab1c-own_only-tom_tat_ns.tsv      |  10 ++
 out/c5-lab1/r045-tables/sha256.txt                 |  17 +++
 out/c5-lab1/r045-tables/thoi_gian.tsv              |   8 ++
 out/c5-lab1/r045-tables/x_inst_duoi_tan_cong.tsv   |   3 +
 reports/INDEX.md                                   |   1 +
 reports/R045-m6ic4-ablation-inst-only.md           | 156 +++++++++++++++++++++
 scripts/c5_m6ic4_score.sh                          |  32 +++++
 23 files changed, 460 insertions(+)
Không sửa detector_c5.py. Không ghi đè score-v14-/v141-/v142-.
```
