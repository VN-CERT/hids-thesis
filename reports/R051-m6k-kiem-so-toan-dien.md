# R051 — M6k: kiểm số toàn diện trước viết bài

1. Số báo cáo: **R051**. Ngày giờ: **2026-11-09 07:45** (giờ máy). Mốc: **M6k**. Tag: `m6k` (tip lúc gắn). Chỉ đọc + tính; không sửa detector/dữ liệu; không chạm LAB-2 trên 201.

## 2. Mục tiêu

Đối chiếu mọi số sẽ vào bài với dữ liệu gốc trên đĩa. Mỗi mục: SỐ THẬT + nguồn; thiếu → `KHÔNG CÓ TRÊN ĐĨA`. Không kết luận văn.

## 3. Đã làm

- Lưu `docs/tasks/M6k.md`.
- Đọc R041-d / R039 / R036 / R034 / LAB-PROD-1 / features / labels.
- Chạy thêm: `c5_score --chieu-phanra own_only --t2` → `out/c5-lab1c/t2-pmuoff-own/` (không ghi đè t2fair/t2-v15).

## 4. Lệnh (C7)

```bash
python3 analysis/c5_score.py --features out/c5-lab1c/features_ghep.tsv \
  --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
  --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --train-until 1006289550843307 \
  --chieu-phanra own_only --t2 --out out/c5-lab1c/t2-pmuoff-own
```

## 5. Bảng kiểm số

### A. Phát hiện vật lý D1 — DVFS / CPI

#### A1 — tỉ số vs nền (R041-d)

Nguồn: `out/c5-lab1/dap-ung/R041-d/ti_so_vs_nen_mo_rong.tsv`  
Cột có: `ti_x_inst_med`, `ti_cpi_med`, `ti_cpu_med`, `ti_dt_med`. **Không có** `ti_x_cyc_med` / `x_cyc`.  
`f_ratio_approx = ti_inst × ti_cpi / ti_cpu` (vì f=cyc/cpu và cyc≈inst×cpi theo median).

Lọc: `muc` bắt đầu `BEN-D1-8` hoặc `BEN-D1-16`, `n≥20`.

| nhóm | n_rows | med ti_inst | med ti_cpi | med ti_cpu | med ti_dt | med f_ratio_approx |
|------|-------:|------------:|-----------:|-----------:|----------:|-------------------:|
| nginx BEN-D1-8 | 4 | 0.7327 | 0.9384 | 0.8578 | 0.9527 | 0.7967 |
| postgres BEN-D1-8 | 15 | **1.0000** | **0.8005** | 0.8718 | 0.8780 | **0.9423** |
| nginx BEN-D1-16 | 3 | 0.5070 | 1.0995 | 0.8842 | 0.9805 | 0.6305 |
| postgres BEN-D1-16 | 14 | **1.0000** | **0.8006** | 0.8675 | 0.8622 | **0.9416** |

Postgres dày (k=5..7), ví dụ D1-8:

| lop | muc | n | ti_inst | ti_cpi | ti_cpu | f~ |
|-----|-----|--:|--------:|-------:|-------:|---:|
| postgres\|k=7 | BEN-D1-8-r1 | 242 | 1.0000 | 0.8396 | 0.8910 | 0.9423 |
| postgres\|k=7 | BEN-D1-8-r2 | 243 | 1.0000 | 0.8346 | 0.8919 | 0.9358 |
| postgres\|k=6 | BEN-D1-8-r1 | 161 | 1.0000 | 0.8307 | 0.8799 | 0.9440 |

**Kết luận số A1:** trên postgres dày, `ti_inst≈1`, `ti_cpi≈0,80–0,84`, `f_ratio_approx≈0,93–0,94` (**giảm**, không >1).  
`x_cyc` tuyệt đối / `f=x_cyc/cpu` cho đúng cửa sổ BEN-D1 trong `features_ghep`/`features_all`: **KHÔNG CÓ** (`features_all` không cột `x_cyc_med`; `features_ghep` không giao thời gian BEN-D1 lab1).

#### A2 — dấu tần số coreclk phiên D1

`grep coreclk|GHz_wall` trong `validation/lab1*`:

- Có file `validation/lab1-20261024/lieu/freq-truoc-D3*.txt`, `freq-*-D4*.txt`, log lieu-v14/v15 — **D3/D4**, không phải BEN-D1.
- Ví dụ: `freq-truoc-D4-v15.txt` trung vị GHz_wall=**2.5303**.
- **KHÔNG CÓ TRÊN ĐĨA** dấu `GHz_wall` gắn riêng phiên BEN-D1-8 / BEN-D1-16.

---

### B. Lỗi số production / troi

#### B3 — RSS

Nguồn: `validation/prod1/suc-khoe.tsv` + `validation/prod1/LAB-PROD-1-FINAL.txt`

| | bytes | /1024² MiB | /10⁶ MB |
|--|------:|----------:|--------:|
| đầu (2026-10-24T23:09:51) | 187273216 | **178.60** | 187.27 |
| cuối (2026-11-02T08:00:17) | 226652160 | **216.15** | 226.65 |
| tỉ lệ | | | **+21.03%** |

Số “187→227 MiB”: khớp nếu hiểu **MB thập phân (10⁶ byte)** (187.3→226.7); **không** phải MiB nhị phân (178.6→216.2). Delta ≈ +37.6 MiB / +39.4 MB. **Không** phải +7,9%.

#### B4 — dung lượng

| nguồn | số |
|-------|-----|
| `du -sh /srv/hids-data/prod1-benign` | **16G** |
| `suc-khoe` cột `dung_luong_GB` cuối | **15.6175** |
| span wall đầu→cuối suc-khoe | **8.368** ngày |
| GB/ngày (15.6175/8.368) | **1.866** |
| số ngày lịch trong tên `.bin` | **10** (20261024…20261102) |
| 10×1.9 | 19 (≠16) |
| 8.37×1.9 | 15.9 ≈ 16 |

**1,9 GB/ngày** ≈ tốc độ theo span suc-khoe (1.87); **16 GB** = tổng `du` trên đĩa. Không mâu thuẫn nếu không nhân 9×1.9 cứng (span ≠ 9 ngày đầy).

#### B5 — tốc độ bản ghi

| nguồn | số |
|-------|-----|
| `suc-khoe` rps median (n=203) | **2521.43**/s |
| `suc-khoe` rps p95 | **3616.42**/s |
| periodic cuối `dinh_ghi` (field4) | **1955192177** bản ghi |
| 1955192177 / 723026 s | **2704.18**/s |

Khớp bậc ~2500/s (median suc-khoe); trung bình cả đợt hơi cao hơn (~2700).

#### B6 — x_inst_med nginx k=6 qua 7 ngày

Nguồn: `out/c5-lab1/dap-ung/R041-d/troi_theo_ngay.tsv`  
Header: `… cpi_med_d* | x_inst_med_d1..d7 | x_arr_med_d1..d7 | n_d1..d7`

| ngày | x_inst_med (nginx\|k=6) | x_arr_med | n |
|-----:|------------------------:|----------:|--:|
| d1 | **785** | 4.34074e+06 | 26245 |
| d7 | **819** | 4.41687e+06 | 25979 |

**4,34×10⁶ = `x_arr_med_d1` (ns), không phải x_inst.**  
x_inst bất biến thật: **~785→819** (per-record median lệnh).

---

### C. C5 — PMU-off / Δt-thô / B4

#### C7 — T² own_only (không inst/cpi) @0,01

Nguồn: `out/c5-lab1c/t2-pmuoff-own/t2_tradeoff.tsv`  
Chiều: `own_med, own_p90, own_iqr, own_cv`.

| branch | ns | bdg_nen | phat_hien | muc_0 | muc_D3-7 |
|--------|---:|--------:|----------:|------:|---------:|
| PHANRA_5tp | 0.01 | 0.0033 | **0.0000** | 0.0000 | **0.0000** |
| PHANRA_5tp | 0.05 | 0.0466 | 0.0000 | 0.0000 | 0.0000 |

Đối chứng T² bộ D (có inst) fair @0,01: `muc_D3-7=0.4595` (100% B4, R048/R050 số).

**Kết luận số C7:** T² **không** inst @0,01: `muc_D3-7=0` → **không** bắt B4 ở D3-7.

#### C8 — T² BASELINE Δt-thô @0,01

Nguồn: `out/c5-lab1c/t2fair-v15-{D,E,A}/t2_tradeoff.tsv` (giống nhau cho BASELINE)

| branch | ns | bdg_nen | phat_hien | muc_D3-7 | muc_0 |
|--------|---:|--------:|----------:|---------:|------:|
| BASELINE_dt_tho | 0.01 | 0.0067 | **0.0000** | **0.0000** | 0.0000 |

PHANRA D cùng file @0,01: phat=0.4072, muc_D3-7=0.4595.

#### C9 — B4 có quota/throttle?

| nguồn | nội dung |
|-------|----------|
| `/root/chep_file/LAB-1c-PROMPT-201.md` | B4 = mỗi 22 s: `stress-ng --cpu 1 --timeout 2s` trong cgroup nginx |
| `validation/lab1c-20261107/bn/B4-D3-7-c-20261107/cgroup-limits.txt` | `memory.max=max cpu.max=max 100000` |
| nhãn B4 | `period=22;duty=2/20` — bật 2 s / chu kỳ 22 s |

**Không** có cpu quota throttle (cpu.max=max). B4 = full CPU 2 s rồi nghỉ — không phải “throttled miner” kiểu cgroup quota.

#### C10 — B4 OVERFLOW / u32

| | |
|--|--|
| cột flag OVERFLOW/CLAMPED trong `features_ghep` | **KHÔNG CÓ** |
| cửa sổ PHANRA B4 (10 tid) | n=128, x_inst finite=125 |
| x_inst_med min/med/max | 5 / 213199 / **1530533** |
| u32 max | 4294967295 |
| sat ≥0.99×u32 | **0** |

---

### D. Đề cương §6 / generator / collector

#### D11 — E1–E4 (R036 / R034)

Nguồn collector cuối m6c.3: `reports/R036-m6d-eseries-a-e2-cho.md`, E4p gốc: `reports/R034-…`.

| mục | số trên đĩa | nguồn |
|-----|-------------|--------|
| E1 rq trung vị L0/L1/L2/L3 | 0 / 8.96e6 / 1.20e7 / 2.60e7 ns | R036 E1 |
| E1 ratio_cpu L1/L2/L3 vs 0 | 0.973 / 0.767 / 0.982 | R036 |
| E1 ratio_CPI | ≈1.00 | R036 |
| E1 Δt ×3,67 | **KHÔNG CÓ** trong R036 | — |
| E2 vm_steal_pct | Unlim 0.025% → 36000 **17.794%** → 24000 **45.757%** → 12000 **68.333%** | R036 |
| E3 vol_us | ≈**300000130** (300 s) | R036 |
| E4-cache inst | ≈14170547–8; CPI L0 **1.92** → L4 **1.72** (giảm) | R036 |
| E4p-stream (R034) inst | **14170548–14170579** | R034 |
| E4p CPI L0/L12/L22 (run) | ~**1.92** / ~**3.45** / ~**6.40** | R034 L=0/12/22 |

Số đề cương inst/CPI **khớp R034 E4p** (M6c.2), không phải bảng E4-cache R036.

#### D12 — Generator open/closed

| | |
|--|--|
| `validation/lab1-20261024/gen-test/pgbench-nhip1.log` | `pgbench -R 100 -c 16 -j 4 -T 290 …` |
| `validation/lab1-20261024/gen-test/gen.log` | `nhip=1 rps=120 tps=100` |
| `validation/lab1-20261024/gen-test/tom-tat.txt` | wrk2 Requests/sec 120.01 (mức 120) |
| chep M6i-c1 | “vòng hở (wrk2 −R, pgbench −R)” |

→ **open-loop** (`-R` tốc độ cố định). Dòng wrk2 đầy đủ argv lab1: không lưu trong `gen.log` (chỉ rps=120); mẫu overhead: `wrk2 -t4 -c64 -d60s -R <rate> …`.

#### D13 — Cấu hình collector

| hằng | giá trị | nguồn |
|------|---------|--------|
| ring buffer mặc định | **64 MiB** | `internal/syscallbpf/loader.go` `DefaultRingbufMB = 64` |
| zstd mặc định | **level 2** (`-zstd-level` 0..3) | `cmd/hids-collect/main.go` |
| IRQ pairs | **13** (hard+soft+11 vector) | `bpf/sys_enter.bpf.c` HIDS_IRQ_PAIR list |
| steal fail-closed | cửa sổ 3 s ×≤3; \|Σvmw−Σrq\| ≤ max(**5 ms**, **1%**×Σvmw) | `docs/tasks/M6c-2.md` / rules hids.mdc |

## 6. File dữ liệu

- `out/c5-lab1c/t2-pmuoff-own/t2_tradeoff.tsv`
- Nguồn đọc: R041-d, R036, R034, LAB-PROD-1-FINAL, suc-khoe, troi_theo_ngay, t2fair-v15-D, LAB-1c-PROMPT

## 7. Quyết định tự đưa ra

1. `f_ratio` dùng `ti_inst×ti_cpi/ti_cpu` vì thiếu `ti_cyc` / không giao BEN-D1 với `x_cyc` trong features hiện có.
2. Báo cáo R051 (không sửa R039/R047 số cũ).

## 8. Cần kiến trúc sư

(không — nhiệm vụ kiểm số)

## 9. Việc tay

(không)

## 10. Tiếp theo

DỪNG (tag `m6k`).
