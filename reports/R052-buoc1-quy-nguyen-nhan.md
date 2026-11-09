# R052 — Bước 1: quy nguyên nhân báo động

1. Số báo cáo: **R052**. Ngày giờ: **2026-11-09 08:56** (giờ máy). Mốc: **buoc1**. Tag: `buoc1`.  
   Chỉ đọc + tính; không chạy lại lab; không chạm LAB-2 trên 201; không sửa `c5_score`/detector.

## 1. Tiêu chí đạt/trượt (CHỐT TRƯỚC khi chạy — nguyên văn)

> ĐẠT nếu: (a) ≥80% cửa sổ báo động do liều tranh chấp (twin dưới D3-7, nền dưới D1/D3) được gán 'môi trường'; VÀ (b) ≥80% cửa sổ báo động B4 được gán 'hành vi'. Phép gán dùng quy tắc thống kê CỐ ĐỊNH (không học), định nghĩa dưới.

## 2. Mục tiêu

Phép thử quyết định RQ5: gán MOI_TRUONG | HANH_VI cho cửa sổ vượt ngưỡng T² bộ D @ ngân sách 1%, theo quy tắc cố định trong `scripts/quy_nguyen_nhan.py`.

## 3. Đã làm

- Lưu `docs/tasks/buoc1.md`.
- Viết `scripts/quy_nguyen_nhan.py` (sha256 đầu `fb43f75975ca…`).
- Chạy trên `out/c5-lab1c/features_ghep.tsv` + nhãn lab1c; output `out/c5-lab1c/quy-nguyen-nhan/`.

### Định nghĩa quy tắc (cố định trong script)

Hằng số: `Z_VUOT=3.0`, `CPI_PHANG=2.0`, `NGAN_SACH=0.01`, `TRAIN_UNTIL=1006289550843307`, nhánh `PHANRA_5tp`, bộ chiều D.

1. **Phần dư:** với c ∈ {rq, steal, irq, cpu, vol, x_arr, x_inst, cpi} (cột `ctx_rq_med`…`cpi_med` giá trị thô):  
   `z_c = (med_W(c) − med_nen(c)) / MAD_nen(c)`.  
   Nền = cửa sổ `nguon=nen` muc 0 của cùng tid (≥8); nếu thiếu → nền lớp `(cgroup_id, k)` (≥20).

2. **Ứng viên theo ưu thế** `|z_c|` max:  
   - rq / steal / irq / cpi → MOI_TRUONG  
   - cpu & `z_cpi>0` → MOI_TRUONG; cpu & `z_cpi≤0` → HANH_VI  
   - vol / x_arr / x_inst & `|z_cpi|<2` → HANH_VI; nếu `|z_cpi|≥2` → MOI_TRUONG

3. **Đồng pha:** tid khác có cửa sổ giao `[start,stop]`, cùng cgroup (nếu 0 peer → cả VM). Peer “đồng pha” nếu cùng thành phần ưu thế, cùng dấu, `|z|≥3`.  
   - `(n_dong_pha+1) ≥ ceil(n_active/2)` → MOI_TRUONG (ghi đè)  
   - ngược lại (kể cả 0 peer) → HANH_VI (ghi đè)

Detector báo động: Hotelling T² bộ D như `c5_score --t2` (không sửa file đó).

## 4. Lệnh

```bash
python3 scripts/quy_nguyen_nhan.py \
  --features out/c5-lab1c/features_ghep.tsv \
  --nhan lab/nhan-tan-cong-lab1c.tsv \
  --nhan-tid lab/nhan-tid-lab1c.tsv \
  --muc lab/muc-lab1c.tsv \
  --train-until 1006289550843307 \
  --ngan-sach 0.01 \
  --out out/c5-lab1c/quy-nguyen-nhan
```

## 5. Kết quả

### Detector

| | |
|--|--|
| T² thr @0.01 | **68.6219** (khớp `t2fair-v15-D`) |
| n_train | 502334 |
| n_alarm (mọi cửa sổ ≥ thr) | 5413 |
| dims | own_cv + x_arr_* + x_inst_med |

### Bảng theo tập A/B/C/D

Nguồn: `out/c5-lab1c/quy-nguyen-nhan/tong_hop.tsv`

| tap | n_bao_dong | n_MOI_TRUONG | n_HANH_VI | n_KHONG_GAN | pct_MOI_TRUONG | pct_HANH_VI | uu_the_top | n_can_du_lieu_dong_pha |
|-----|----------:|-------------:|----------:|------------:|---------------:|------------:|------------|----------------------:|
| A (twin N1 @D3-7∪D1-16) | 7 | 0 | 7 | 0 | **0.00%** | 100.00% | x_inst:4, x_arr:3 | 0 |
| B (nen @D1/D3) | **0** | 0 | 0 | 0 | nan | nan | — | 0 |
| C (B4 @D3-7) | 17 | 0 | 17 | 0 | 0.00% | **100.00%** | x_arr:17 | 0 |
| D (B1) | 1 | 0 | 1 | 0 | 0.00% | 100.00% | x_arr:1 | 0 |

Ghi chú số:

- **B = 0:** trong `features_ghep` không có cửa sổ `nguon=nen` giao khoảng muc D1/D3 lab1c (lab ghi `lab1c/bn/…`). Tập (a) chỉ còn twin (A).
- Đồng pha: mọi cửa sổ A/C đều có peer giao (`can_du_lieu=0`); **không** thiếu quần thể trên đĩa cho các báo động này. Không đánh dấu `[cần dữ liệu]`.

### (a) twin+nen → môi trường

| | |
|--|--|
| n (A∪B unique) | 7 |
| n gán MOI_TRUONG | 0 |
| pct | **0.00%** |
| ≥80%? | **không** |

### (b) B4 → hành vi

| | |
|--|--|
| n B4 báo động | 17 |
| n gán HANH_VI | 17 |
| pct | **100.00%** |
| ≥80%? | **có** |

### Ví dụ — 5 cửa sổ twin@D3-7 (A)

| tid | start_ns | nhan | uu_the | z_uu | n_dong_pha/n_active | cand |
|-----|----------|------|--------|------|---------------------|------|
| 944933 | 1538787855094418 | HANH_VI | x_inst | 10.4 | 11/120 | MOI_TRUONG |
| 944933 | 1538847855094418 | HANH_VI | x_inst | 92.6 | 8/107 | HANH_VI |
| 944933 | 1538877855094418 | HANH_VI | x_inst | 265 | 7/99 | HANH_VI |
| 944933 | 1538907855094418 | HANH_VI | x_arr | −4.03e5 | 41/92 | HANH_VI |
| 944933 | 1538937855094418 | HANH_VI | x_inst | 355 | 5/84 | HANH_VI |

### Ví dụ — 5 cửa sổ B4 (C)

| tid | start_ns | nhan | uu_the | z_uu | n_dong_pha/n_active | cand |
|-----|----------|------|--------|------|---------------------|------|
| 946044 | 1540207666092000 | HANH_VI | x_arr | 1.44e5 | 5/66 | MOI_TRUONG |
| 946044 | 1540237666092000 | HANH_VI | x_arr | 1.44e5 | 6/73 | MOI_TRUONG |
| 946044 | 1540267666092000 | HANH_VI | x_arr | 1.44e5 | 6/80 | MOI_TRUONG |
| 946044 | 1540297666092000 | HANH_VI | x_arr | 1.44e5 | 6/87 | MOI_TRUONG |
| 946044 | 1540327666092000 | HANH_VI | x_arr | 1.44e5 | 7/92 | MOI_TRUONG |

## 6. File dữ liệu

- `scripts/quy_nguyen_nhan.py`
- `out/c5-lab1c/quy-nguyen-nhan/{chi_tiet,tong_hop,ket_luan}.tsv`, `run.log`
- Nguồn: `features_ghep.tsv`, `lab/nhan-*-lab1c.tsv`, `lab/muc-lab1c.tsv`

## 7. Quyết định tự đưa ra

1. Detector = T² bộ D @0.01 (max\|z\| score-v143-D có `phat_hien=0` với B4).
2. `Z_VUOT=3`, `CPI_PHANG=2` cố định, ghi trong script.
3. Đồng pha ưu tiên cùng cgroup; 0 peer thì VM; 0 peer VM → HANH_VI + `can_du_lieu`.
4. Ghi đè bước 3 áp cả hai chiều (MOI↔HANH) theo ngưỡng nửa quần thể.

## 8. Cần kiến trúc sư

(không bắt buộc — kết luận số đã chốt theo tiêu chí)

## 9. Việc tay

(không)

## 10. Kết luận ĐẠT/TRƯỢT (theo số tiêu chí)

| điều kiện | số | đạt? |
|-----------|-----|------|
| (a) twin+nen ≥80% MOI_TRUONG | 0/7 = 0.00% | không |
| (b) B4 ≥80% HANH_VI | 17/17 = 100.00% | có |
| (a) ∧ (b) | | **TRƯỢT** |

DỪNG (tag `buoc1`).
