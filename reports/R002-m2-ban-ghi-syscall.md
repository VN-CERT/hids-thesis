# R002 — M2 — Bản ghi syscall, lọc, ring buffer, đếm mất

## 1. Thông tin chung
- Số báo cáo: R002
- Ngày giờ: 2026-10-06 22:47 (giờ máy)
- Mốc: M2
- Git commit: `5573cf7` (toàn bộ số liệu trong báo cáo này đo bằng binary build từ cây sạch, header ghi `git_commit: 5573cf7`, không có `dirty`)
- Máy: Ubuntu 24.04, kernel 6.8.0-142-generic, VM VMware, 24 CPU.

## 2. Mục tiêu
Hai phần:
1. Trả lời câu hỏi về dấu `dirty` của lần chạy G1, và lưu dữ liệu kiểm chứng G1 vào git.
2. Làm mốc M2: ghi bản ghi syscall 48 byte cho các thread được chọn vào một ring buffer dùng chung, đếm chính xác số bản ghi mất, và có công cụ thống kê để đối chiếu với perf.

## 3. Đã làm gì

### 3.1. Theo yêu cầu bổ sung trước M2
- Chạy `git diff --stat m1` và `git status --short`, kết quả ở mục 5.1. **Không có file mã nguồn nào thay đổi so với tag `m1`**; chỉ có bốn file tài liệu được thêm sau tag. Dấu `dirty` trong header file G1 đến từ các file tài liệu chưa commit lúc đó, không phải từ mã đo.
- Commit thư mục `validation/g1-20261006/` (1,4 MB). Thư mục này không nằm trong `.gitignore`.
- Ghi kết quả G1 vào `docs/STATE.md`: G1 ĐẠT theo kiến trúc sư, `vmw_steal_time` = `/proc/stat` = (Ready + Co-stop của vCenter), lệch ≤ 0,001%; đường đo steal chính thức là `vmw_steal_time`.

### 3.2. Theo phản hồi của kiến trúc sư cho M1
1. Giữ nguyên cách nạp typed ksym bằng `BPF_PSEUDO_BTF_ID` tự gán.
2. Giữ hai dòng header `user_hz` và `tsc_source`.
3. Đã đặt `git config --local user.name "hids-bot"` và `user.email "hids-bot@localhost"`.
4. `internal/buildinfo.WarnIfDirty` in cảnh báo ra stderr khi binary build từ cây làm việc còn thay đổi chưa commit; cả `steal-probe` và `hids-collect` đều gọi. Header vẫn ghi hậu tố `-dirty`.
5. Báo cáo M1 đổi tên thành `reports/R001-m1-steal-probe.md`.
6. Bảng flags đã ghi vào `.cursor/rules/hids.mdc`. Mục "Ghi nhận cho M3" (fail-closed khi `vmw_ns` lệch `rq_steal_ns`) đã ghi vào `docs/STATE.md`, chưa làm.

### 3.3. M2
- `bpf/sys_enter.bpf.c`: chương trình `hids_sys_enter` gắn vào `tp_btf/sys_enter`. Thứ tự lọc: so `tgid` với tgid của collector (so sánh thanh ghi, rẻ nhất) → tra `tgid` trong map PID đích → nếu có lọc cgroup thì so `bpf_get_current_cgroup_id()` rồi duyệt tổ tiên bằng `bpf_get_current_ancestor_cgroup_id` cho từng level, dừng khi helper trả về 0 (hết tổ tiên), tối đa 16 level.
- Trạng thái theo thread lưu trong `BPF_MAP_TYPE_TASK_STORAGE`: `seen` (đã ghi được bản ghi nào cho thread này chưa) và `gap_pending` (lần trước ghi hụt).
- Một ring buffer dùng chung, kích thước đặt bằng `-ringbuf-mb`, mặc định 64 MiB.
- `seq` là bộ đếm per-CPU (`BPF_MAP_TYPE_PERCPU_ARRAY`), tăng cho **mọi** lần định ghi, kể cả khi ring buffer đầy. Khi `bpf_ringbuf_reserve` thất bại: tăng bộ đếm mất per-CPU và bật `gap_pending`; bản ghi thành công kế tiếp của thread đó mang bit `GAP_BEFORE`.
- M2 ghi `cpu_ns = steal_ns = irq_ns = rq_ns = vol_us = 0`, `cgroup_id = bpf_get_current_cgroup_id()`, `tid` = thread id, `syscall_nr = id`.
- `bin/hids-collect`: tham số `-cgroup` (lặp được), `-pid` (lặp được), `-duration`, `-out`, `-ringbuf-mb`. File `.bin` có phần đầu văn bản kết thúc bằng `#END`, sau đó là các bản ghi 48 byte nối tiếp. Khi kết thúc ghi `out/<tên>.bin.stats` chứa `seq` và bộ đếm mất của từng CPU.
- `bin/rec-stat`: thống kê file `.bin`.
- `tools/sysinj.c`: công cụ bơm syscall, biên dịch bằng gcc thành `bin/sysinj`.
- `scripts/g7.sh a|b|c`: ba phép đo G7a, G7b, G7c. Tôi **không chạy** G7a với N=1000000, G7b và G7c; chỉ chạy thử G7a với N=10000 để tự kiểm.

## 4. Lệnh build, lệnh chạy
```
cd /root/hids

# Build (sinh lại mã BPF, biên dịch sysinj bằng gcc, build 4 binary Go)
make build

# Thu thập theo tiến trình
sudo ./bin/hids-collect -pid 12345 -duration 30s -out out/thu.bin

# Thu thập theo cgroup (lặp lại duoc, bat ca cgroup con)
sudo ./bin/hids-collect -cgroup /sys/fs/cgroup/system.slice/docker-<id>.scope -duration 70s -out out/thu.bin

# Thống kê
./bin/rec-stat out/thu.bin
./bin/rec-stat -nr 110 out/thu.bin
./bin/rec-stat -tgid 12345 out/thu.bin

# Ba phép đo G7 (người dùng chạy, xem mục 9)
sudo bash scripts/g7.sh a            # N mac dinh 1000000
sudo bash scripts/g7.sh b
sudo bash scripts/g7.sh c
```

## 5. Kết quả (output nguyên văn)

### 5.1. So sánh với tag m1 và ảnh hưởng tới binary dùng cho G1
```
$ git diff --stat m1
 .cursor/rules/workflow.mdc                   |  47 +++++
 docs/STATE.md                                |  38 +++++
 reports/INDEX.md                             |   5 +
 reports/R001-m1-doc-bo-dem-steal-theo-cpu.md | 246 +++++++++++++++++++++++++++
 4 files changed, 336 insertions(+)

$ git status --short
?? validation/

$ git diff --stat m1 -- bpf cmd internal go.mod go.sum Makefile scripts   # chi ma nguon
(trong = khong co thay doi ma nguon)

$ go build -ldflags "-X hids/internal/buildinfo.Commit=14c2ee1-dirty" -o /tmp/steal-probe-dungthu ./cmd/steal-probe
$ sha256sum bin/steal-probe /tmp/steal-probe-dungthu
08387b7ca05e5f3cbd0ccb3cec7cc1170e3c7eccf23daa9a32304d2322213ded  bin/steal-probe
2baf89c6191420df2e85b1e5fd6645e60f80b93f6df041a171d6c8b5a221df0b  /tmp/steal-probe-dungthu
```

Hai mã băm khác nhau, nên tôi so tiếp phần thông tin Go nhúng trong binary:

```
$ go version -m bin/steal-probe > /tmp/a; go version -m /tmp/steal-probe-dungthu > /tmp/b; diff /tmp/a /tmp/b
3c3
< 	mod	hids	v0.0.0-20261006150219-14c2ee177856+dirty	
---
> 	mod	hids	v0.0.0-20261006150700-dfc863b9979e+dirty	
18,19c18,19
< 	build	vcs.revision=14c2ee1778566be0de689ac43e7737e61ae36646
< 	build	vcs.time=2026-10-06T15:02:19Z
---
> 	build	vcs.revision=dfc863b9979e30d6719b50508e49a63828ed6538
> 	build	vcs.time=2026-10-06T15:07:00Z
(ket thuc diff)
```

**Diễn giải:** bốn file thay đổi so với tag `m1` đều là tài liệu (`.cursor/rules/workflow.mdc`, `docs/STATE.md`, `reports/INDEX.md`, `reports/R001-...md`). Không có file nào trong `bpf/`, `cmd/`, `internal/`, `go.mod`, `go.sum`, `Makefile`, `scripts/` thay đổi. Hai binary chỉ khác nhau ở dấu vết VCS mà Go tự nhúng (số commit HEAD và giờ commit); phần mã thực thi sinh ra từ cùng một bộ mã nguồn. Vậy **thay đổi đó không làm khác binary `bin/steal-probe` đã dùng cho G1**: dấu `dirty` chỉ phản ánh các file tài liệu chưa commit tại thời điểm build.

### 5.2. Build sạch
```
$ make clean && make build
rm -f bin/steal-probe bin/steal-summary bin/hids-collect bin/rec-stat bin/sysinj
rm -f internal/stealbpf/*.o internal/syscallbpf/*.o
go generate ./...
cc -O2 -Wall -Wextra -o bin/sysinj tools/sysinj.c
go build -ldflags "-X hids/internal/buildinfo.Commit=5573cf7" -o bin/steal-probe ./cmd/steal-probe
go build -ldflags "-X hids/internal/buildinfo.Commit=5573cf7" -o bin/steal-summary ./cmd/steal-summary
go build -ldflags "-X hids/internal/buildinfo.Commit=5573cf7" -o bin/hids-collect ./cmd/hids-collect
go build -ldflags "-X hids/internal/buildinfo.Commit=5573cf7" -o bin/rec-stat ./cmd/rec-stat

$ git status --short
(trong = cay sach)
```

### 5.3. Chạy thử G7a với N=10000
```
$ bash scripts/g7.sh a 10000
=== G7a: mot sysinj, N=10000 ===
sysinj pid=273259

--- N theo thiet ke: 10000

--- perf stat, tat ca syscall (nguyen van) ---

 Performance counter stats for process id '273259':

            13,707      raw_syscalls:sys_enter                                                

       3.003175828 seconds time elapsed

--- perf stat, rieng getppid id == 110 (nguyen van) ---

 Performance counter stats for process id '273259':

            10,000      raw_syscalls:sys_enter                                                

       3.003123930 seconds time elapsed

--- log collector ---
ghi vao out/g7a-20261006-224548.bin
loc pid: 273259 | loc cgroup: khong co | ring buffer: 64 MiB
ban ghi doc duoc: 13645 | so lan dinh ghi: 13645 | mat: 0
du lieu: out/g7a-20261006-224548.bin | thong ke: out/g7a-20261006-224548.bin.stats

--- rec-stat ---
file: out/g7a-20261006-224548.bin
# hids-collect
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# git_commit: 5573cf7
# record_size: 48
# filter_pid: 273259
# filter_cgroup: khong co
# ringbuf_bytes: 67108864
# start_mono_ns: 13568914127346
# start_wall: 2026-10-06T22:45:48.619239433+07:00
# duration: khong gioi han

tong so ban ghi trong file : 13645
so ban ghi sau khi loc     : 13645
bo loc                     : khong co
ts_enter nho nhat / lon nhat: 13568914916834 / 13571874127031 (ns, CLOCK_MONOTONIC)
ban ghi co co FIRST        : 1
ban ghi co co GAP_BEFORE   : 0
ban ghi co syscall_nr=110  : 10000

so ban ghi theo tgid (1 tien trinh)
    tgid  ban_ghi      nguon_tgid
  273259    13645  ? (suy tu tid)

so ban ghi theo tid (1 thread)
     tid  tgid  ban_ghi
  273259     ?    13645

top 4 syscall_nr (tong cong 4 gia tri khac nhau)
  syscall_nr  ban_ghi
         110    10000
          21     1822
         230     1822
         231        1

theo tung CPU (lay tu out/g7a-20261006-224548.bin.stats)
   cpu  seq_cuoi  mat
     6       740    0
     7        72    0
     8      1442    0
     9     10779    0
    14       612    0
  TONG     13645    0

doi chieu seq (toan cuc)
  so lan dinh ghi (tong seq_cuoi cua moi CPU): 13645
  so ban ghi collector doc duoc             : 13645
  so ban ghi dem duoc trong file            : 13645
  tong bo dem mat (ring buffer day)         : 0
  dinh ghi - ban ghi doc duoc               : 0

ghi chu: ban ghi 48 byte khong co truong cpu nen khong tach duoc ban ghi
theo CPU; vi vay khong in duoc seq nho nhat/lon nhat va so lo hong seq cua
tung CPU. Xem muc 8 cua bao cao R002.

du lieu: out/g7a-20261006-224548.bin
```

Hai con số đối chiếu chính: perf đếm riêng `getppid` được **10.000**, collector đếm `syscall_nr=110` được **10.000**, đúng bằng N theo thiết kế. Số tổng khác nhau (perf 13.707, collector 13.645) vì perf gắn vào tiến trình nhanh hơn collector nạp và gắn chương trình BPF, nên perf đếm thêm vài chục syscall của vòng chờ `/tmp/hids-go` trước khi collector kịp gắn. Phần bơm `getppid` chỉ bắt đầu 2 giây sau khi cả hai đã gắn xong, nên con số đó khớp tuyệt đối.

### 5.4. Kiểm tra bộ lọc cgroup (chuẩn bị cho G7c)
```
$ mkdir -p /sys/fs/cgroup/hids-test/con    # cgroup tam de kiem tra, xoa o cuoi
cgroup cha inode=14940, cgroup con inode=15019

--- (1) loc theo cgroup CHA, tien trinh nam trong cgroup CON (kiem tra duyet to tien) ---
sysinj=273866  cgroup cua no: 0::/hids-test/con
ban ghi doc duoc: 23651 | so lan dinh ghi: 23651 | mat: 0
du lieu: out/cg-ancestor.bin | thong ke: out/cg-ancestor.bin.stats
tong so ban ghi trong file : 23651
ban ghi co syscall_nr=110  : 20000

--- (2) loc dung cgroup CON (khop truc tiep) ---
ban ghi doc duoc: 8653 | so lan dinh ghi: 8653 | mat: 0
du lieu: out/cg-exact.bin | thong ke: out/cg-exact.bin.stats
tong so ban ghi trong file : 8653
ban ghi co syscall_nr=110  : 5000

$ rmdir /sys/fs/cgroup/hids-test/con /sys/fs/cgroup/hids-test
da xoa cgroup tam
```

Cả hai đường đều đúng số: lọc theo cgroup cha bắt được tiến trình nằm trong cgroup con (20.000 `getppid`), lọc đúng cgroup con cũng khớp (5.000 `getppid`).

Ngoài ra tôi đã thử trực tiếp trên cgroup của container `caddy`: khi container rảnh thì thu được 0 bản ghi, khi chạy `docker exec caddy ...` thì thu được 691 bản ghi của 9 tiến trình trong cgroup đó.

### 5.5. Kernel sạch sau khi collector thoát
```
$ pgrep -a hids-collect
(khong co tien trinh nao)
$ bpftool prog list | grep -ci hids
0
$ bpftool link list | grep -ci hids
0
$ bpftool map list | grep -ciE "hids_|ringbuf"
0
$ ls -la /sys/fs/bpf
total 0
drwx-----T 2 root root 0 Oct  6 18:59 .
drwxr-xr-x 9 root root 0 Oct  6 22:00 ..
```

## 6. File dữ liệu đã tạo
- `/root/hids/validation/g1-20261006/` — dữ liệu kiểm chứng G1, đã commit, giữ lâu dài:
  - `g1-20261006-220848.csv` (14.411 dòng)
  - `g1-summary.txt`
  - `vcenter-ready-costop-run.csv.csv`
- `/root/hids/out/g7a-20261006-224548.bin` — dữ liệu lần chạy thử G7a N=10000 (13.645 bản ghi, 655 KB).
- `/root/hids/out/g7a-20261006-224548.bin.stats` — seq và bộ đếm mất theo từng CPU.
- `/root/hids/out/g7a-20261006-224548-perf-all.txt`, `...-perf-getppid.txt`, `...-collect.log`, `...-sysinj.log`.

Các file thử nghiệm cgroup đã xoá sau khi lấy số.

## 7. Quyết định đã tự đưa ra và lý do
1. **Vòng đọc ring buffer dùng `Flush()` chứ không dùng `SetDeadline()`.** `SetDeadline` của `cilium/ebpf` giữ cùng một mutex với `ReadInto`, nên gọi nó trong khi vòng đọc đang chờ dữ liệu sẽ treo cả hai. Tôi đã gặp đúng lỗi này khi thử lần đầu (collector không thoát, file 0 byte). `Flush()` không giữ mutex đó, nó làm `ReadInto` trả về hết bản ghi đang nằm trong ring buffer rồi trả về `ErrFlushed`. Khi dừng, collector gỡ tracepoint trước (không còn bản ghi mới), rồi flush và đọc vét cho tới khi một lần flush không còn bản ghi nào.
2. **Tính dấu `dirty` lúc chạy recipe của `make`, không phải lúc đọc Makefile.** `make clean` xoá các file `.o` đang được git theo dõi, nên nếu tính sớm thì `make clean && make build` sẽ tự gắn nhãn `dirty` cho một cây hoàn toàn sạch.
3. **`rec-stat` suy `tgid` từ `tid` khi tiến trình đã thoát.** `/proc/<tid>/status` không còn sau khi tiến trình kết thúc. Với tiến trình đơn luồng (như `sysinj`) thì `tid` chính là `tgid`. Bảng in rõ cột `nguon_tgid` là `/proc` hay `? (suy tu tid)` để không nhầm.
4. **Thêm hai tham số `-from-mono` và `-to-mono` cho `rec-stat`.** G7c cần đếm số bản ghi nằm trong cửa sổ monotonic của perf, mà đặc tả `rec-stat` chỉ có `-tgid` và `-nr`. Hai tham số này cộng thêm, không đổi hành vi mặc định.
5. **Collector từ chối chạy khi không có bộ lọc nào.** Không có `-pid` và không có `-cgroup` thì không bản ghi nào được chọn, chạy cũng vô ích; báo lỗi rõ hơn là chạy im lặng.
6. **`-out` để trống thì tự đặt tên** `out/hids-<ngày giờ>.bin`.
7. **Mốc thời gian bắt đầu đọc bằng `CLOCK_MONOTONIC`** qua `unix.ClockGettime` (không cgo), cùng đồng hồ với `bpf_ktime_get_ns()`, để so được với mốc `python3 time.monotonic_ns()` dùng trong G7c.
8. **`syscall_nr` cắt xuống 16 bit** đúng theo đặc tả bản ghi. Trên x86-64 số syscall nằm trong khoảng 0..~460 nên không mất thông tin; chỉ các syscall x32 (bit 30) mới bị cắt, nhưng x32 không bật trên máy này.
9. **Kích thước ring buffer phải là lũy thừa của 2** (kernel yêu cầu); `-ringbuf-mb` kiểm tra điều kiện này và báo lỗi rõ thay vì để kernel từ chối.
10. **Tạo cgroup tạm `/sys/fs/cgroup/hids-test` để kiểm tra bộ lọc** rồi xoá ngay sau khi lấy số. Đây là thao tác bình thường trên cgroup v2, không đụng tới cấu hình kernel, và cần thiết vì container `caddy` lúc rảnh không sinh syscall nào nên không kiểm chứng được gì.

## 8. Cần kiến trúc sư quyết định
**Bản ghi 48 byte không có trường CPU, nên `rec-stat` không in được phần "theo từng CPU: seq nhỏ nhất, seq lớn nhất, số lỗ hổng seq, tổng số seq bị thiếu".**

Lý do: `seq` là bộ đếm per-CPU, mọi CPU đều bắt đầu từ 1, và tất cả bản ghi đi chung một ring buffer. Khi đọc file ra, không có cách nào xác định bản ghi nào thuộc CPU nào. Lần chạy thử cho thấy chỉ một thread đơn luồng trong 3 giây đã chạy trên 5 CPU khác nhau (6, 7, 8, 9, 14), nên đây không phải trường hợp hiếm.

Hiện `rec-stat` in phần rigorous được: bảng từng CPU lấy từ file `.stats` (`seq_cuoi` = số lần định ghi trên CPU đó, và bộ đếm mất), cộng với đối chiếu toàn cục (tổng số lần định ghi, số bản ghi đọc được, tổng số mất, hiệu hai số đó). Trong lần chạy thử cả bốn con số khớp nhau tuyệt đối.

Các phương án để có được số liệu theo từng CPU:
- **A. Nhét số CPU vào 8 bit cao của `seq`** (`seq = cpu << 24 | bộ đếm`). Giữ nguyên 48 byte và vẫn "tăng dần theo CPU". Hệ quả: bộ đếm mỗi CPU chỉ đếm được tới 16,7 triệu rồi quay vòng; với tốc độ đo thực tế thì khoảng vài giờ mỗi CPU. Đổi ý nghĩa con số `seq` nên phải sửa đặc tả bản ghi.
- **B. Dùng 8 bit cao của `flags` (bit 8..15) làm số CPU.** Giữ nguyên 48 byte và giữ nguyên ý nghĩa `seq`. Hệ quả: trái với dòng "các bit còn lại = 0" trong bảng flags vừa chốt, và chỉ đủ cho 256 CPU.
- **C. Mỗi CPU một ring buffer riêng** (map-of-maps). Khi đó CPU biết được ngay lúc đọc, không cần sửa bản ghi. Hệ quả: trái với quyết định "một ring buffer dùng chung" và mất thứ tự toàn cục; kiến trúc sư đã hẹn xem lại ở M5.
- **D. Giữ nguyên như hiện tại.** Chỉ có số liệu theo CPU ở mức tổng (số lần định ghi và số mất), không có lỗ hổng seq theo từng CPU. Việc kiểm tra mất mát vẫn làm được bằng đối chiếu toàn cục.

Tôi không tự chọn vì cả bốn phương án đều đụng tới đặc tả bản ghi hoặc quyết định kiến trúc. Hiện đang chạy theo D.

## 9. Việc người dùng cần làm tay
Ba phép đo G7 tôi không chạy. Các bước:

1. Mở terminal, vào thư mục dự án:
   ```
   cd /root/hids
   ```
2. Chạy G7a (một tiến trình bơm 1.000.000 syscall, mất khoảng 10 giây):
   ```
   sudo bash scripts/g7.sh a 2>&1 | tee out/g7a-ketqua.txt
   ```
3. Chạy G7b (24 tiến trình bơm song song, đồng thời chạy `stress-ng --cpu 24`; máy sẽ rất nặng trong lúc chạy, chọn thời điểm phù hợp):
   ```
   sudo bash scripts/g7.sh b 2>&1 | tee out/g7b-ketqua.txt
   ```
4. Chạy G7c (lọc theo cgroup của container `caddy`, mất khoảng 75 giây):
   ```
   sudo bash scripts/g7.sh c 2>&1 | tee out/g7c-ketqua.txt
   ```
   Lưu ý: container `caddy` lúc rảnh gần như không gọi syscall nào, nên nếu muốn thấy số khác 0 thì trong 60 giây đó hãy tạo ít tải cho nó, ví dụ mở một terminal khác và chạy:
   ```
   for i in $(seq 1 200); do docker exec caddy ls / >/dev/null; done
   ```
5. Gửi lại cho tôi ba file `out/g7a-ketqua.txt`, `out/g7b-ketqua.txt`, `out/g7c-ketqua.txt`, và đường dẫn các file `.bin` mà script in ra ở cuối.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất
Lỗi còn tồn tại:
- Chưa có lỗi nào chặn công việc. `make clean && make build` sạch, `gofmt` và `go vet` không báo gì, kernel không còn gì sau khi collector thoát.
- Phần "theo từng CPU" của `rec-stat` chưa đầy đủ, chờ quyết định ở mục 8.
- Chưa đo ở tốc độ cao thật (1.000.000 syscall × 24 tiến trình). Tốc độ đó mới biết ring buffer 64 MiB có đủ không và bộ đếm mất có hoạt động đúng trong thực tế không. Trong lần chạy thử nhỏ, bộ đếm mất bằng 0 nên đường mã xử lý mất (`GAP_BEFORE`) chưa được chạy qua bằng dữ liệu thật.
- `hids-collect` ghi thẳng ra file bằng một luồng. Ở G7b (24 triệu bản ghi, khoảng 1,1 GB) có thể nghẽn ở đĩa. Nếu G7b cho thấy mất nhiều, tôi đề xuất xem lại ở M5 như kiến trúc sư đã dự tính.

Việc tiếp theo đề xuất:
1. Người dùng chạy ba phép đo G7 theo mục 9, tôi phân tích và viết báo cáo R003.
2. Kiến trúc sư chọn phương án cho mục 8.
3. Sau đó bắt đầu M3: đo thật năm thành phần của Δt, kèm kiểm tra fail-closed `vmw_ns` so với `rq_steal_ns` lúc khởi động như đã ghi trong `docs/STATE.md`.
