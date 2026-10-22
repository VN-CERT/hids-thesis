# R035 — M6c-3: chế độ PMU lấy mẫu `-pmu sample=K`, cảnh báo STEALCHECK theo CPU, chi phí theo K

1. **Số báo cáo:** R035. **Ngày giờ:** 2026-10-22 15:20 (+07). **Mốc:** M6c-3. **Git commit:** `30b221b` (trước commit báo cáo này); tag `m6c.3` gắn ở bước kết thúc.
2. **Mục tiêu:** dùng BPF lấy mẫu PMU mới của kiến trúc sư (`hids_pmu_sample`) để đo inst/cyc chỉ ở 1 trong K khoảng, giảm chi phí PMU theo bản ghi; thêm cảnh báo STEALCHECK theo CPU; đo chi phí theo K bằng T1. Không sửa BPF (file kiến trúc sư `9994b03f…`, đã kiểm sha256, commit "M6c-3: BPF lay mau PMU (kien truc su, 9994b03f)"; `make build` đạt, không có lỗi verifier).

## 3. Đã làm gì

### Phần 2 — phía Go (commit `30b221b`)

- Cờ `-pmu` nhận `off | host | on | sample=K` (K nguyên 2…1000; sai → từ chối chạy, cả ở lớp CLI và lớp loader). `sample=K`: mở fd, nạp map như `on`, `hids_pmu_on=1`, nạp `hids_pmu_sample=K`; `on` nạp `hids_pmu_sample=0`; `host`/`off` không đổi. Header `.bin`: `pmu: sample=K`. `.cursor/rules/hids.mdc` đã mô tả chế độ sample; mặc định production vẫn `host`; `sample=20` là cấu hình thu dữ liệu lab/Bài 2 (kiến trúc sư chốt K sau báo cáo này).
- STEALCHECK: khi TỔNG đạt nhưng có một CPU |lech| > 50 ms, in thêm dòng `STEALCHECK canh_bao cpu=<n> lech_ns=<...>` (không từ chối, không đổi tiêu chí). Trong toàn bộ nhiệm vụ này không có lần khởi động nào có CPU lệch > 50 ms, nên dòng cảnh báo không xuất hiện lần nào (đếm trong log: 0 dòng `canh_bao`).

### Phần 3 — cổng (container dừng; mỗi khối đo có `freq_stamp.sh` trước và sau)

Dấu tần số của khối cổng (CPU 12): trước `trung vi GHz_wall=1.9345`, sau `trung vi GHz_wall=1.9397` (chênh 0,27%). Dữ liệu: `validation/m6c3-20261022/gates/`.

**G7a ×4** (`-zstd-level 0`), cả bốn lần đều mất 0:

```
--- G7a -pmu host ---       ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
--- G7a -pmu on ---         ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
--- G7a -pmu sample=20 ---  ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0
--- G7a -pmu sample=50 ---  ban ghi doc duoc: 1000001 | so lan dinh ghi: 1000001 | mat: 0

out/g7a-20261022-143105.bin   # pmu: host       # pmu_events: instructions:u,cycles:u
out/g7a-20261022-143114.bin   # pmu: on         # pmu_events: instructions:u,cycles:u
out/g7a-20261022-143128.bin   # pmu: sample=20  # pmu_events: instructions:u,cycles:u
out/g7a-20261022-143139.bin   # pmu: sample=50  # pmu_events: instructions:u,cycles:u
```

**G3 S1–S5 ×1 với `-pmu sample=20`** (lần đầu hỏng vì wl thoát sớm ở S1 — lỗi tự kiểm của workload, đã chạy lại; kết quả dưới đây của lần chạy lại giữ `.bin`):

```
S1-ketqua.txt: g5_max_ns=0
S2-ketqua.txt: g5_max_ns=499
S3-ketqua.txt: g5_max_ns=497
S4-ketqua.txt: g5_max_ns=0
S5-ketqua.txt: g5_max_ns=498
so khoang CLAMPED va |phan du| > 500 ns: 0 / tong (moi kich ban)
recursion_misses: tong 0 tren moi chuong trinh (135 dong chuong trinh cua 5 kich ban, max = 0)
ti le ban ghi khong-FIRST co co PMU (rec-stat):
S1: 15/302 = 4.9669%
S2: 50/1002 = 4.9900%
S3: 50/1002 = 4.9900%
S4: 15/302 = 4.9669%
S5: 75/1504 = 4.9867%
```

**G3 S1–S5 ×1 với `-pmu on`** (hồi quy): phần dư max S1=0, S2=500, S3=499, S4=0, S5=500; CLAMPED & |dư| > 500 ns = 0 / tổng; recursion_misses tổng 0. Tỉ lệ cờ PMU (rec-stat): S1 302/302 = 100.0000%; S2 1002/1002 = 100.0000%; S3 1002/1002 = 100.0000%; S4 302/302 = 100.0000%; S5 1504/1504 = 100.0000%.

**G11 ×1 với `-pmu on`** (hồi quy, script `m6c_g11.sh` như M6c; nguyên văn):

```
=== G11 S1: wl cpu 10000 300 (CPU 20), perf stat -e instructions:u,cycles:u ===
     4,695,079,886      instructions:u
     5,788,722,041      cycles:u
collector: ban ghi trong cua so=301 khong_FIRST=301 co_PMU=301
ti le PMU (khong-FIRST): 301/301 = 100.0000%
tong inst collector = 4695079843
tong cyc collector = 5788714280
=== G11 S3: wl mixed 2000 3000 500 (CPU 20) ===
     1,609,649,346      instructions:u
     1,991,896,089      cycles:u
collector: ban ghi trong cua so=1001 khong_FIRST=1001 co_PMU=1001
ti le PMU (khong-FIRST): 1001/1001 = 100.0000%
tong inst collector = 1609649303
tong cyc collector = 1991892427
```

Lệch ở S1: inst 4695079843 so với 4695079886 (chênh 43); cyc 5788714280 so với 5788722041 (chênh 7761). Tiêu chí ≤ 1% và cờ 100%: đạt.

**G11s (lấy mẫu đúng).** S1 `cpu 10000 300` ghim CPU 20. Nguyên văn:

```
[on] so khoang khong-FIRST: 302, co co PMU: 302, khong co nhung inst/cyc != 0: 0
[on] inst: trung_vi=15654346.0 p10=15654345 p90=15654346
[on] cyc: trung_vi=19418440.0 p10=18779836 p90=19632425
[sample20] so khoang khong-FIRST: 302, co co PMU: 15, khong co nhung inst/cyc != 0: 0
[sample20] inst: trung_vi=15778390.0 p10=15778389 p90=15778391
[sample20] cyc: trung_vi=19719346.0 p10=18506206 p90=19852452
[sample50] so khoang khong-FIRST: 302, co co PMU: 6, khong co nhung inst/cyc != 0: 0
[sample50] inst: trung_vi=15775102.0 p10=15775102 p90=15775102
[sample50] cyc: trung_vi=19621149.0 p10=19369656 p90=19812723
```

Số khoảng có cờ: sample=20 → 15 (kỳ vọng 15 ± 1); sample=50 → 6 (kỳ vọng 6). Mọi khoảng không cờ có inst = cyc = 0 (cột "khong co nhung inst/cyc != 0" = 0 ở cả ba). Lệch trung vị của các khoảng có cờ so với (a) `-pmu on`: sample=20 — inst (15778390 − 15654346) / 15654346 = +0,79%; cyc (19719346 − 19418440) / 19418440 = +1,55%. sample=50 — inst +0,77%; cyc +1,04%. Tiêu chí inst ≤ 1%, cyc ≤ 3%: đạt ở cả hai.

**Chi phí theo K.** T1 sysinj N=10.000.000 ghim CPU 12, 10 lượt xen kẽ 5 điều kiện, TSV "load cond run value" chạy `python3 analysis/m6c_stats.py` (không sửa script; mốc C0). Nguyên văn:

```
load	cond	n	mean	sd	ci95_lo	ci95_hi	pct_vs_C0	pct_ci95_lo	pct_ci95_hi	p_perm
T1	C0	10	186.4990	3.2380	184.1828	188.8152	0.0000	-	-	-
T1	C1-host	10	817.9060	14.6247	807.4448	828.3672	338.5578	332.0289	344.9560	0.0001
T1	C1-sample50	10	805.6880	16.8301	793.6493	817.7267	332.0066	325.0670	338.7832	0.0001
T1	C1-sample20	10	952.8610	53.1576	914.8370	990.8850	410.9202	393.1482	428.3030	0.0001
T1	C1-on	10	3766.5460	158.9752	3652.8299	3880.2621	1919.6065	1866.6303	1976.1677	0.0001
```

Hiệu số so với C1-host tính từ các trung bình trên: sample50 = 805,6880 − 817,9060 = −12,2180 ns/syscall; sample20 = 952,8610 − 817,9060 = +134,9550 ns/syscall; on = 3766,5460 − 817,9060 = +2948,6400 ns/syscall. Kỳ vọng của kiến trúc sư (không phải tiêu chí): sample20 ≈ host + 150; sample50 ≈ host + 60; on ≈ host + 2950. File: `validation/m6c3-20261022/gates/T1.tsv`, `T1.stats.txt`, `T1.log` (mỗi lượt C1 đều có bản ghi/giây > 0, mất 0; không có KHONG_READY).

**Chạy thử cấu hình 24 giờ 10 phút** (`-datadir`, `-pmu sample=20`, như pre24h; dữ liệu `validation/m6c3-20261022/pre24h10/`). Dấu tần số CPU 12: trước 1,9267 GHz, sau 1,9362 GHz. Nguyên văn tóm tắt:

```
thoi_gian_thuc_s=602
host_lines=600
hai cot PMU cua host stream (3 dong cuoi):
15236273 31478212
20124422 49244096
149939778 137428562
# pmu: sample=20
tong so ban ghi trong file : 7278
ti le ban ghi khong-FIRST co co PMU: 363/7277 = 4.9883%
cpu,seq_cuoi,mat (moi CPU): mat = 0 tren ca 24 CPU
status.tsv dong cuoi: kernel_drops_delta=0, proc_drops_delta=0, cpu_seconds_total=4.820, rss_bytes=183730176
```

Tức: CPU collector = 4,820 s / 602 s ≈ 0,80% một lõi; RSS cuối 183730176 byte; kernel drops = 0; proc drops = 0; host lines = 600 (cộng mọi đoạn, trừ header); hai cột PMU cuối của host stream là số; tỉ lệ cờ PMU trong `.bin` = 4,9883%.

Cuối cổng: `bpftool prog show | grep -c hids_` = 0, không còn tiến trình collector, 12 container chạy đủ.

## 4. Lệnh build, lệnh chạy (để chạy lại được)

- Build: `make build` (trước đó kiểm sha256 5 file; commit BPF riêng, commit Go riêng).
- Cổng: `bash scripts/m6c3_gates.sh validation/m6c3-20261022/gates` (unit `hids-m6c3gates`); G3 chạy lại bằng `HIDS_COLLECT_EXTRA="-pmu sample=20" bash scripts/m6b12_g3.sh stop <out>` và `HIDS_COLLECT_EXTRA="-pmu on" ...` (unit `hids-m6c3g3`, `hids-m6c3g3b`, `hids-m6c3g3c`).
- Chạy thử 10 phút: `bash scripts/m6c3_pre24h10.sh validation/m6c3-20261022/pre24h10` (unit `hids-m6c3pre`).

## 5. Kết quả kiểm — output nguyên văn

Đã dán ở mục 3. File đầy đủ: `validation/m6c3-20261022/gates/` (g7a.txt, g7a-pmu-headers.txt, g3-sample20b, g3-sample20c, g3-on, g11, g11s.txt, T1.tsv, T1.stats.txt, freq-truoc.txt, freq-sau.txt), `pre24h10/` (run.log, tomtat.txt, cpu-rss.tsv, data/), log job `out/jobs/m6c3gates.log`, `m6c3g3*.log`, `m6c3pre.log`.

## 6. File dữ liệu đã tạo

- `validation/m6c3-20261022/gates/`, `validation/m6c3-20261022/pre24h10/`
- Script mới: `scripts/m6c3_gates.sh`, `scripts/m6c3_g11s.sh`, `scripts/m6c3_pre24h10.sh`
- Sửa: `cmd/hids-collect/main.go`, `internal/syscallbpf/loader.go`, `.cursor/rules/hids.mdc`; BPF mới của kiến trúc sư `bpf/sys_enter.bpf.c` (không sửa nội dung) và binding sinh lại `internal/syscallbpf/sysenter_x86_bpfel.{go,o}`.

## 7. Quyết định đã tự đưa ra và lý do

1. Lần G3 đầu tiên trong driver cổng hỏng vì wrapper `m6b12_g3.sh` tự dừng container trong khi driver ngoài đã dừng hết (lệnh `docker stop` không có đối số → lỗi), và lần G3 sample=20 kế tiếp hỏng ở S1 vì wl thoát sớm trước cửa sổ đo (tự kiểm hiệu chuẩn của wl trượt — lỗi workload đã biết từ M6c). Cả hai lần đều chạy lại nguyên trạng, không sửa script cổng hay tiêu chí; kết quả trong báo cáo là của lần chạy lại đạt.
2. File TSV của T1 ban đầu ghi ngăn cách bằng dấu cách, `m6c_stats.py` yêu cầu tab nên báo lỗi `ValueError: 'load' is not in list`; đã chuyển đúng định dạng tab (không đổi số) rồi chạy lại. Lỗi nguyên văn:

```
Traceback (most recent call last):
  File "/root/hids/analysis/m6c_stats.py", line 129, in <module>
    main(sys.argv[1])
  File "/root/hids/analysis/m6c_stats.py", line 97, in main
    idx = {k: header.index(k) for k in ("load", "cond", "run", "value")}
              ^^^^^^^^^^^^^^^
ValueError: 'load' is not in list
```

3. G11 chạy bằng script `m6c_g11.sh` có sẵn (vốn đã gắn `-pmu on`), gồm cả S1 và S3 như M6c; báo cáo in cả hai, S1 là kịch bản nhiệm vụ yêu cầu.

## Thay đổi ngoài phạm vi nhiệm vụ

`git diff --stat m6c.2..HEAD -- scripts analysis internal cmd tools bpf` (nguyên văn):

```
 bpf/sys_enter.bpf.c                       |  62 +++++++++++++----
 cmd/hids-collect/main.go                  |  26 ++++++-
 internal/syscallbpf/loader.go             |  27 ++++++--
 internal/syscallbpf/sysenter_x86_bpfel.go |   6 ++
 internal/syscallbpf/sysenter_x86_bpfel.o  | Bin 170592 -> 177560 bytes
 scripts/m6c3_g11s.sh                      |  81 ++++++++++++++++++++++
 scripts/m6c3_gates.sh                     | 110 ++++++++++++++++++++++++++++++
 scripts/m6c3_pre24h10.sh                  |  55 +++++++++++++++
 8 files changed, 347 insertions(+), 20 deletions(-)
```

Ngoài ra: `.cursor/rules/hids.mdc`, `docs/STATE.md`, `docs/tasks/M6c-3.md`, báo cáo này, `reports/INDEX.md`. Không sửa nội dung file kiến trúc sư nào khác; BPF chỉ chép nguyên bản kiến trúc sư đưa.

sha256 của 5 file kiến trúc sư, kiểm trước mỗi lần build và lúc viết báo cáo:

```
9994b03f359ee5205354515f80bd4dd67f4919daca6b585702f4dc54796648c0  bpf/sys_enter.bpf.c
39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec  bpf/proc_events.bpf.c
9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd  analysis/m5f_parse.py
8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25  analysis/m6c_stats.py
88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706  tools/coreclk.c
```

Cả 5 giá trị khớp với giá trị kiến trúc sư ghi trong nhiệm vụ.

## 8. Cần kiến trúc sư quyết định

1. **K nào cho LAB-1 / thu dữ liệu Bài 2:** số đo T1 đợt này (ns/syscall, trung bình 10 lượt): C0 = 186,4990; host = 817,9060; sample=50 = 805,6880 (host −12,2180); sample=20 = 952,8610 (host +134,9550); on = 3766,5460 (host +2948,6400). Kiến trúc sư chốt K cho cấu hình thu dữ liệu lab/Bài 2 (đề bài ghi `sample=20` là cấu hình dự kiến, chốt sau báo cáo này).
2. **sample=50 rẻ hơn host trong đợt này:** trung bình sample=50 thấp hơn host 12,2 ns/syscall (sd của hai điều kiện là 16,8 và 14,6) trong khi kỳ vọng là host + ~60. Kiến trúc sư quyết có cần đo lại riêng cặp host/sample=50 với nhiều lượt hơn để tách khỏi nhiễu hay chấp nhận số này.

## 9. Việc người dùng cần làm tay

Không có. Mọi job đã xong, 12 container đã khởi động lại, kernel sạch.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất

- Không có cổng nào không đạt: G7a ×4 mất 0; G3 sample=20 và on đều phần dư ≤ 500 ns, CLAMPED 0/tổng, recursion_misses 0; G11 lệch inst 43 (≈0%), cyc 7761 (≈0,00013%), cờ 100%; G11s đạt tiêu chí inst ≤ 1%, cyc ≤ 3% ở cả sample=20 và sample=50; chạy thử 10 phút: drops 0, host lines 600, tỉ lệ PMU 4,9883%.
- Dòng `STEALCHECK canh_bao` chưa xuất hiện lần nào trong nhiệm vụ (không có CPU nào lệch > 50 ms khi tổng đạt); mã đã có và biên dịch trong binary, chờ lần khởi động nào có CPU lệch lớn để thấy dòng thật.
- Đề xuất: chờ kiến trúc sư chốt K (câu 8.1) rồi mở nhiệm vụ thu dữ liệu; không tự mở rộng phạm vi.

## Phụ lục — Trả lời của kiến trúc sư về mục 8 (nhận 2026-10-22, ghi nguyên văn)

1. K = 20 cho LAB-1 và thu dữ liệu Bài 2 (`-pmu sample=20`); chi phí đo được +135 ns/syscall so với host ở vi mô xấu nhất, tức ≈1,5% CPU ở tải PostgreSQL kịch trần (436k bản ghi/giây trên 4 CPU) — chấp nhận. Mặc định production vẫn host.
2. Không đo lại cặp host/sample=50. Ghi nhận chưa giải thích: theo số đếm lần đọc (một khoảng lấy mẫu = 2 lần pmu_read = 4 RDPMC ≈ 5,9 µs cho mỗi K syscall) thì kỳ vọng sample=20 ≈ +295 ns, sample=50 ≈ +118 ns; đo được +135 và −12, đều thấp hơn kỳ vọng ~160 ns. Không ảnh hưởng quyết định. G11s lần sau chạy wl với -loops cố định cho cả hai lần.
