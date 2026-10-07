# R012 — M4.4: đóng M4 (E2, phân rã, E2.png)

1. **Số báo cáo:** R012 — 2026-10-07 — M4.4 — git commit: *(sau commit, tag `m4`)*
2. **Mục tiêu:** Sửa công thức kiểm steal 10s; hoàn thiện báo cáo E2 và bảng phân rã E1/E2 (không chạy lại E2).
3. **Đã làm:** `measure_vm_steal_pct_10s` mẫu số = tổng Δ jiffies dòng `cpu`; `m4.py --m4-close` → `E2.png` (3 boxplot log, ghi `vm_steal_probe_pct`); `decompose-E1.csv`, `decompose-E2.csv`; `scripts/m4.sh m4-close`.
4. **Lệnh:** `sudo bash scripts/m4.sh m4-close`
5. **Bảng E2 (burn) — trích `summary.csv`:**

| level | n | dt_mean_us | steal_mean_us | steal_p90_us | steal_gt0_frac | steal_total_ns | vm_steal_probe_pct | vm_steal_pct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Unlimited | 500 | 11010.81 | 40.97 | 125.03 | 0.354 | 20485894 | 0.015 | 0.014 |
| 36000 | 500 | 20277.67 | 8459.10 | 0.00 | 0.084 | 4229549137 | 38.701 | 71.176 |
| 24000 | 500 | 22637.41 | 10046.10 | 146.74 | 0.266 | 5023048354 | 58.590 | 140.495 |
| 12000 | 500 | 60083.39 | 40168.89 | 135.16 | 0.188 | 20084447179 | 78.425 | 412.908 |

6. **Phân rã mức tăng E2 (ns, Δ mean so với Unlimited):**

| kind | level | Δdt | Δcpu | Δsteal | Δirq | Δrq | Δvol | check |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| burn | 36000 | 9266857 | -24188 | 8418126 | 774709 | 885192 | 0 | 786983 |
| burn | 24000 | 11626598 | 14085 | 10005125 | -1095 | 1608483 | 0 | 0 |
| burn | 12000 | 49072581 | 131310 | 40127923 | 2021 | 8811327 | 0 | 0 |
| sleep | 36000 | 5458078 | -1811 | 26 | -18 | 17017 | 5442886 | 21 |
| sleep | 24000 | 20936218 | 508 | 0 | 24 | 136601 | 20799096 | 11 |
| sleep | 12000 | 44243755 | -264 | 0 | -22 | 536775 | 43707272 | 6 |

   E1: `validation/m4-20261007/decompose-E1.csv`
7. **File:** `validation/m4-20261007/E2.png`, `decompose-E1.csv`, `decompose-E2.csv`, `summary.csv`
8. **Quyết định:** Dòng `check` ≠ 0 khi steal lớn (đợt) không khớp tổng thành phần tức thời — ghi nhận, không sửa đặc tả.
9. **Người dùng:** Không.
10. **Tiếp theo:** M5 overhead (R013).
