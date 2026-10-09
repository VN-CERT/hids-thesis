# Trạng thái dự án HIDS

Cập nhật lần cuối: 2026-10-09 15:15 (giờ máy)

## Lịch sử git và tham chiếu phiên bản

- Lịch sử git đã được **viết lại** để loại mọi file `*.bin` (GitHub chặn file > 100 MB). **Mọi hash commit cũ không còn hợp lệ** trên nhánh hiện tại.
- Bảng đối chiếu hash cũ → mới: `docs/commit-map-loc-bin.txt`.
- **Từ nay khi tham chiếu phiên bản:** dùng **TAG mốc** (`m1`, `m2`, … `m5f`, `m5h`, …), **không** dùng hash commit trong báo cáo, STATE, hay task (trừ khi ghi rõ là hash mới sau rewrite và chỉ để tra cứu bảng map).
- Dữ liệu thô **không** đưa vào git: `*.bin` và `*.bin.zst` đã có trong `.gitignore`.

## Mốc hiện tại và mục tiêu

- **M5:** **đóng** — kiến trúc sư chấp nhận G3 + overhead m5h (R026) là bộ số cuối bài 1; tag `m5h`.
- **M6b:** chờ nhiệm vụ tiếp theo từ kiến trúc sư.

## Binary đo overhead M5h (`git_commit: 0dd2964-dirty`)

- Lệnh kiểm: `git diff --stat 0dd2964 HEAD -- bpf cmd internal go.mod go.sum Makefile` → **không có thay đổi** (mã collector/BPF/Go/Makefile giữa commit đo và HEAD/tag `m5h` giống nhau).
- `git log --oneline 0dd2964..HEAD`: chỉ commit **script/tài liệu/báo cáo** (`scripts/m5h.sh`, `scripts/hids_data_policy.sh`, R026, STATE); **không** commit sửa `bpf/`, `cmd/`, `internal/` (ngoài quy trình generate đã có trong repo).
- **Kết luận:** binary ghi `0dd2964-dirty` **không** khác mã nguồn collector so với commit `0dd2964` trên các đường dẫn trên; hậu tố `-dirty` do `make build` gắn khi cây còn thay đổi tracked ngoài các thư mục Makefile bỏ qua (`out/`, `validation/`, `reports/`, `internal/syscallbpf/`). Thường gặp khi bench: file script/tài liệu đang sửa chưa commit, và/hoặc `internal/stealbpf/*_bpfel.o` đổi sau `go generate` (**không** nằm danh sách bỏ qua). Bench đã chạy với `M5_SKIP_GIT_CHECK=1` (không tái lập từ git sạch).
- **Chính sách từ sau M5:** commit trước, `make build` sau; **không** dùng `M5_SKIP_GIT_CHECK` khi đo dữ liệu bài.

## Bộ số overhead cuối (m5h)

Nguồn: `reports/R026-m5h-overhead.md`, `validation/m5h-20261009/`.

**T1 — ns/syscall (mean ± sd, n=5):**

| cond | M5h mean±sd (ns) | % vs C0 |
|---|---|---|
| C0 | 141.84 ± 0.03 | — |
| C1-tracepoint | 411.81 ± 11.58 | +190.33% |
| C1-fentry | 403.73 ± 8.45 | +184.63% |
| C2-tracepoint | 182.33 ± 0.06 | +28.54% |
| C2-fentry | 182.33 ± 0.07 | +28.54% |

**T3 kịch trần — TPS (`m5f_parse_sat.tsv`, n=3):**

| cond | M5h mean±sd | M5h % vs C0 |
|---|---|---|
| C0 | 4901.59 ± 28.24 | — |
| C1 | 4139.95 ± 32.97 | −15.54% |
| C2 | 4805.78 ± 65.09 | −1.95% |

**T4 kịch trần — RPS (n=5):**

| cond | M5h mean±sd (RPS) | M5h % vs C0 |
|---|---|---|
| C0 | 140081 ± 335 | — |
| C1-tracepoint | 124100 ± 1076 | −11.34% |
| C1-fentry | 123955 ± 535 | −11.45% |
| C2-tracepoint | 134486 ± 384 | −3.92% |
| C2-fentry | 134655 ± 552 | −3.80% |

**Tải cố định — % CPU cgroup (kiến trúc sư từ `meta.txt`; thứ tự PG25, PG50, nginx25, nginx50):**

| cond | T3-R25 | T3-R50 | T4-R25 | T4-R50 |
|---|---|---|---|---|
| C1 | +10,0% | +11,8% | +11,3% | +10,7% |
| C2 | +2,8% | +3,0% | +3,4% | +3,2% |

## Lưu trữ đĩa (máy bench)

- **2026-10-09:** thêm PV `/dev/sdc` (~2,93 TiB) vào VG `ubuntu-vg`, mở rộng LV `ubuntu-lv` → filesystem `/` ext4 **~3,6 TiB**, ~3,3 TiB trống (`df` sau mở rộng). Chi tiết: `reports/R027-m5-close-disk-extend.md`.

## Bước đã xong (M5h / đóng M5)

- G3 + bench m5h: `validation/m5h-20261009/`; R026; tag `m5h`.
- Dọn: commit artifact validation (không `.bin`); STATE + R027 đĩa.

## Bước đang làm

- (không)

## Bước tiếp theo

- M6b (chờ task).

## Việc đang chạy

- (không)

## Vướng mắc / chờ kiến trúc sư

- O5 không làm.
