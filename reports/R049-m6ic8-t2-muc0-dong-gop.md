# R049 — M6i-c8: đóng góp T² ở tấn công muc_0 (mục 2 R048)

1. Số báo cáo: **R049**. Ngày giờ: **2026-11-09 04:12** (giờ máy). Mốc: **M6i-c8**. Tag: `m6i.9` (tip lúc gắn). Nối mục 2 còn treo của R048.

## 2. Mục tiêu

Phân tích T² (bộ D, train-until 1006289550843307) bắt gì trên cửa sổ tấn công **muc_0**; không sửa `c5_score`/`detector_c5`.

## 3. Đã làm gì

- CAI `goi-195-m6ic8` XONG → `scripts/t2_muc0_analyze.py`.
- Sửa 1 dòng đường dẫn import: `scripts/c5_score.py` → `analysis/c5_score.py` (file CAI trỏ sai chỗ; không đụng toán học).
- Chạy lệnh nhiệm vụ → `out/c5-lab1/r048-tables/t2_muc0_dong_gop.txt`.

## 4. Lệnh

```bash
cd /root/hids && python3 scripts/t2_muc0_analyze.py \
  out/c5-lab1c/features_ghep.tsv \
  lab/nhan-tan-cong-lab1c.tsv lab/nhan-tid-lab1c.tsv lab/muc-lab1c.tsv \
  D 1006289550843307 \
  | tee out/c5-lab1/r048-tables/t2_muc0_dong_gop.txt
```

## 5. Kết quả (nguyên văn)

```
# T2 muc_0 (tan cong khong tai), bo chieu=D, 84 cua so; 20 diem cao nhat:
rank	tid	nguon	t2	chieu_dong_gop_lon_nhat(3)
1	905609	lab1c/bn/B4-0-c-20261107	131692.78	x_inst_med=100.1%  x_arr_p90=0.2%  x_arr_med=-0.1%
2	905609	lab1c/bn/B4-0-c-20261107	131680.71	x_inst_med=100.1%  x_arr_p90=0.2%  x_arr_med=-0.1%
3	905609	lab1c/bn/B4-0-c-20261107	131679.27	x_inst_med=100.1%  x_arr_p90=0.2%  x_arr_med=-0.1%
4	905609	lab1c/bn/B4-0-c-20261107	131677.32	x_inst_med=100.1%  x_arr_p90=0.2%  x_arr_med=-0.1%
5	905609	lab1c/bn/B4-0-c-20261107	102258.02	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.1%
6	905609	lab1c/bn/B4-0-c-20261107	102256.69	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.1%
7	905609	lab1c/bn/B4-0-c-20261107	88143.86	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.2%
8	905609	lab1c/bn/B4-0-c-20261107	88142.40	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.2%
9	905609	lab1c/bn/B4-0-c-20261107	75001.26	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.2%
10	905609	lab1c/bn/B4-0-c-20261107	66238.28	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.2%
11	905609	lab1c/bn/B4-0-c-20261107	66237.63	x_inst_med=100.1%  x_arr_p90=0.3%  x_arr_med=-0.2%
12	905609	lab1c/bn/B4-0-c-20261107	65140.06	x_inst_med=100.1%  x_arr_p90=0.4%  x_arr_med=-0.2%
13	905609	lab1c/bn/B4-0-c-20261107	29500.29	x_inst_med=100.1%  x_arr_p90=0.5%  x_arr_med=-0.2%
14	905609	lab1c/bn/B4-0-c-20261107	28097.45	x_inst_med=100.1%  x_arr_p90=0.5%  x_arr_med=-0.2%
15	905609	lab1c/bn/B4-0-c-20261107	28069.25	x_inst_med=100.1%  x_arr_p90=0.5%  x_arr_med=-0.2%
16	905609	lab1c/bn/B4-0-c-20261107	16932.27	x_inst_med=100.1%  x_arr_p90=0.7%  x_arr_med=-0.3%
17	905609	lab1c/bn/B4-0-c-20261107	11059.34	x_inst_med=100.0%  x_arr_p90=0.9%  x_arr_med=-0.3%
18	948236	lab1c/slow/B1-60s-0-c-20261107	172.80	x_inst_med=78.8%  x_arr_p90=12.8%  x_arr_iqr=7.5%
19	948236	lab1c/slow/B1-60s-0-c-20261107	172.80	x_inst_med=78.8%  x_arr_p90=12.8%  x_arr_iqr=7.5%
20	948236	lab1c/slow/B1-60s-0-c-20261107	125.59	x_inst_med=69.3%  x_arr_p90=15.8%  x_arr_iqr=12.0%

# dong gop trung binh (20 cua so cao nhat), theo chieu:
  x_inst_med: 96.4%
  x_arr_p90: 2.4%
  x_arr_iqr: 1.2%
  x_arr_med: 0.3%
  own_cv: -0.0%
  x_arr_cv: -0.4%
```

## 6. File dữ liệu

- `out/c5-lab1/r048-tables/t2_muc0_dong_gop.txt`
- `scripts/t2_muc0_analyze.py` (sha sau sửa path: `de77eb2f…`)

## 7. Quyết định tự đưa ra

1. Báo cáo riêng R049 (ngắn) thay vì sửa thân R048.
2. Sửa path import tới `analysis/c5_score.py` — không đổi logic đóng góp.

## 8. Đọc thẳng (theo khung nhiệm vụ)

Trên 20 cửa sổ tấn công muc_0 điểm T² cao nhất (bộ D):

- Đóng góp trung bình lớn nhất: **`x_inst_med` = 96,4%**.
- `own_cv` ≈ 0%; các `x_arr_*` cộng lại ~3–4%.
- 17/20 cửa sổ top là tid `905609` nguồn **B4-0** (stress-ng --cpu 1 bật/nghỉ); 3 cửa sổ còn lại B1-60s vẫn lấy `x_inst_med` làm chiều #1 (69–79%).

Theo tiêu chí nhiệm vụ: chiều chính là **x_inst (tải)** → khung đọc là T² ở muc_0 đang bắt **dư âm tải**, không phải nhịp (`own_cv`/`x_arr`).

## 9. Việc người dùng cần làm tay

(không)

## 10. Lỗi / tiếp theo

- DỪNG theo nhiệm vụ (tag `m6i.9`).
