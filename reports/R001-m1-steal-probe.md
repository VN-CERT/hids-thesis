# R001 — M1 — Công cụ đọc bộ đếm steal theo từng CPU

## 1. Thông tin chung
- Số báo cáo: R001
- Ngày giờ: 2026-10-06 22:05 (giờ máy)
- Mốc: M1
- Git commit: `14c2ee1` (tag `m1`). Các file quy trình (`.cursor/rules/workflow.mdc`, `docs/STATE.md`, `reports/`) nằm ở commit ngay sau đó.
- Máy: Ubuntu 24.04, kernel 6.8.0-142-generic, VM VMware, 24 CPU, TSC 1995312 kHz.

## 2. Mục tiêu
Làm công cụ đọc bộ đếm steal của từng CPU, để kiểm chứng số đo trước khi xây collector ở mốc M2. Công cụ phải in giá trị đo được cạnh giá trị tham chiếu của kernel, không tự kết luận đúng sai.

## 3. Đã làm gì
1. Sinh `bpf/vmlinux.h` từ `/sys/kernel/btf/vmlinux` bằng `bpftool`.
2. Viết chương trình BPF `hids_steal_snap` (`bpf/steal_snap.bpf.c`). Chương trình chạy theo yêu cầu, không gắn vào sự kiện nào. Với mỗi CPU từ 0 đến `nr_cpus - 1` (user space truyền vào, tối đa 64), chương trình gọi `bpf_per_cpu_ptr` lên hai biến per-CPU của kernel và đọc:
   - `vmw_steal_time.clock`: bộ đếm steal của VMware stealclock, đơn vị chu kỳ vTSC.
   - `runqueues.prev_steal_time`: bộ đếm steal của scheduler, đơn vị ns.
   Mỗi CPU được ghi kèm `bpf_ktime_get_ns()` tại lúc đọc vào một mảng toàn cục.
3. Viết `bin/steal-probe`. Mỗi chu kỳ: chụp snapshot BPF, rồi đọc ngay `/proc/stat` để lấy cột steal của từng CPU. Ghi ra CSV, mỗi CPU một dòng.
4. Viết `bin/steal-summary`. Chế độ mặc định in bảng theo từng CPU kèm dòng TỔNG. Chế độ `-bucket 20s` in tổng steal theo từng khối 20 giây. Có lọc `-from`/`-to` theo giờ máy.
5. Viết `scripts/g1.sh` để chạy phép đo 600 giây có tạo tải. Script này tôi **chưa chạy** theo đúng yêu cầu.
6. Tự kiểm: build sạch, chạy thử 30 giây, kiểm tra bộ đếm không giảm, đối chiếu với `/proc/stat`, kiểm tra kernel sạch sau khi thoát.

## 4. Lệnh build, lệnh chạy
```
cd /root/hids

# Build (sinh lại mã BPF rồi build hai binary)
make build

# Đo thử 30 giây, mỗi giây một lần
sudo ./bin/steal-probe -duration 30s -out out/m1-selfcheck.csv

# Tổng hợp
./bin/steal-summary out/m1-selfcheck.csv
./bin/steal-summary -bucket 20s out/m1-selfcheck.csv

# Chỉ xét một khoảng giờ
./bin/steal-summary -from 22:01:30 -to 22:01:45 out/m1-selfcheck.csv

# Phép đo 600 giây có tạo tải (người dùng chạy, xem mục 9)
sudo bash scripts/g1.sh
```

## 5. Kết quả (output nguyên văn)

### 5.1. Build
```
$ make clean && make build
rm -f bin/steal-probe bin/steal-summary
rm -f internal/stealbpf/*.o
go generate ./...
go build -ldflags "-X hids/internal/buildinfo.Commit=14c2ee1-dirty" -o bin/steal-probe ./cmd/steal-probe
go build -ldflags "-X hids/internal/buildinfo.Commit=14c2ee1-dirty" -o bin/steal-summary ./cmd/steal-summary
```

### 5.2. Chạy đo 30 giây
```
$ cat out/m1-run.log
ghi vao out/m1-selfcheck.csv
co che BPF: SEC(syscall) + BPF_PROG_RUN, bpf_per_cpu_ptr(vmw_steal_time) + bpf_per_cpu_ptr(runqueues)
tsc_khz=1995312 nr_cpus=24 user_hz=100 interval=1s duration=30s
da ghi 30 chu ky x 24 CPU vao out/m1-selfcheck.csv
```

### 5.3. Kiểm tra `vmw_raw` không giảm theo thời gian trên mọi CPU
```
$ awk -F, '!/^#/ && $1 ~ /^[0-9]/ {cpu=$3; v=$4+0; if (cpu in p) {if (v < p[cpu]) {bad++; printf "GIAM cpu=%s: %d -> %d\n", cpu, p[cpu], v} else if (v == p[cpu]) eq++; else inc++} p[cpu]=v} END {printf "cap lien tiep: tang=%d bang=%d giam=%d\n", inc, eq, bad+0}' out/m1-selfcheck.csv
cap lien tiep: tang=693 bang=3 giam=0
```

### 5.4. Tổng hợp, chế độ mặc định
```
$ ./bin/steal-summary out/m1-selfcheck.csv
file: out/m1-selfcheck.csv
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# tsc_khz: 1995312
# tsc_source: dmesg | [    0.000000] vmware: TSC freq read from hypervisor : 1995.312 MHz
# bpf_mechanism: SEC(syscall) + BPF_PROG_RUN, bpf_per_cpu_ptr(vmw_steal_time) + bpf_per_cpu_ptr(runqueues)
# git_commit: 50a07bc-dirty
# interval: 1s
# duration: 30s
# user_hz: 100 (/proc/self/auxv AT_CLKTCK)
# reference: /proc/stat cot steal (1/USER_HZ giay), doc ngay sau moi lan chup BPF
khoang: 2026-10-06T22:01:20.967966371+07:00 .. 2026-10-06T22:01:49.968886264+07:00 (29.001 s theo dong ho may)
so dong: 720, so CPU: 24
USER_HZ dung de doi tick sang ms: 100 (header CSV: 100 (/proc/self/auxv AT_CLKTCK))
tham chieu: cot procstat_steal_ticks lay tu /proc/stat luc do

   cpu  mau  dvmw_ms   drq_ms  dprocstat_ms  dvmw/dprocstat  drq/dprocstat
     0   30    9.325    9.322        10.000           0.933          0.932
     1   30    4.751    4.738        10.000           0.475          0.474
     2   30    9.326    9.326        10.000           0.933          0.933
     3   30    7.141    7.141        10.000           0.714          0.714
     4   30    4.268    4.268        10.000           0.427          0.427
     5   30    6.645    6.645        10.000           0.665          0.665
     6   30    5.889    5.889         0.000               -              -
     7   30    8.686    8.683        10.000           0.869          0.868
     8   30    5.426    5.426        10.000           0.543          0.543
     9   30    5.726    5.724         0.000               -              -
    10   30    5.551    5.551        10.000           0.555          0.555
    11   30    6.755    6.731        10.000           0.676          0.673
    12   30    4.160    4.160        10.000           0.416          0.416
    13   30    5.788    5.788        10.000           0.579          0.579
    14   30    6.595    6.592         0.000               -              -
    15   30    5.290    5.278         0.000               -              -
    16   30    7.330    7.339        10.000           0.733          0.734
    17   30    6.049    6.049        10.000           0.605          0.605
    18   30    4.268    4.268        10.000           0.427          0.427
    19   30    4.624    4.624        10.000           0.462          0.462
    20   30    4.277    4.278        10.000           0.428          0.428
    21   30    7.203    7.201         0.000               -              -
    22   30    4.597    4.597         0.000               -              -
    23   30    4.170    4.170        10.000           0.417          0.417
  TONG  720  143.841  143.789       180.000           0.799          0.799
```

### 5.5. Tổng hợp, chế độ khối 20 giây
```
$ ./bin/steal-summary -bucket 20s out/m1-selfcheck.csv
file: out/m1-selfcheck.csv
# uname_r: 6.8.0-142-generic
# nr_cpus: 24
# tsc_khz: 1995312
# tsc_source: dmesg | [    0.000000] vmware: TSC freq read from hypervisor : 1995.312 MHz
# bpf_mechanism: SEC(syscall) + BPF_PROG_RUN, bpf_per_cpu_ptr(vmw_steal_time) + bpf_per_cpu_ptr(runqueues)
# git_commit: 50a07bc-dirty
# interval: 1s
# duration: 30s
# user_hz: 100 (/proc/self/auxv AT_CLKTCK)
# reference: /proc/stat cot steal (1/USER_HZ giay), doc ngay sau moi lan chup BPF
khoang: 2026-10-06T22:01:20.967966371+07:00 .. 2026-10-06T22:01:49.968886264+07:00 (29.001 s theo dong ho may)
so dong: 720, so CPU: 24
USER_HZ dung de doi tick sang ms: 100 (header CSV: 100 (/proc/self/auxv AT_CLKTCK))
tham chieu: cot procstat_steal_ticks lay tu /proc/stat luc do

khoi 20s, tong tren tat ca CPU, chenh lech giua hai lan chup lien tiep

   bat_dau   vmw_ms    rq_ms  procstat_ms
  22:01:20   90.844   90.805      100.000
  22:01:40   52.997   52.985       80.000
      TONG  143.841  143.789      180.000
```

### 5.6. Kiểm tra kernel sạch sau khi tiến trình thoát
```
$ ./bin/steal-probe -duration 3s -out out/kiemtra-dondep.csv &
ghi vao out/kiemtra-dondep.csv
co che BPF: SEC(syscall) + BPF_PROG_RUN, bpf_per_cpu_ptr(vmw_steal_time) + bpf_per_cpu_ptr(runqueues)
tsc_khz=1995312 nr_cpus=24 user_hz=100 interval=1s duration=3s
$ bpftool prog list | grep -i hids   # trong khi chay
214: syscall  name hids_steal_snap  tag 2647e38a08f4e946  gpl
da ghi 3 chu ky x 24 CPU vao out/kiemtra-dondep.csv
$ bpftool prog list | grep -ci hids   # sau khi thoat
0
$ ls -la /sys/fs/bpf
total 0
drwx-----T 2 root root 0 Oct  6 18:59 .
drwxr-xr-x 9 root root 0 Oct  6 22:00 ..
```

### 5.7. Kiểm tra đường dự phòng (chỉ đọc `runqueues`)
```
$ ./bin/steal-probe -no-vmw -duration 3s -out out/kiemtra-duphong.csv
khong nap duoc ban doc vmw_steal_time, chuyen sang ban chi co runqueues:
bo qua ban doc vmw_steal_time theo yeu cau (-no-vmw)
ghi vao out/kiemtra-duphong.csv
co che BPF: SEC(syscall) + BPF_PROG_RUN, chi bpf_per_cpu_ptr(runqueues) (ksym vmw_steal_time khong nap duoc)
tsc_khz=1995312 nr_cpus=24 user_hz=100 interval=1s duration=3s
da ghi 3 chu ky x 24 CPU vao out/kiemtra-duphong.csv

$ sed -n "5p;12p" out/kiemtra-duphong.csv
# bpf_mechanism: SEC(syscall) + BPF_PROG_RUN, chi bpf_per_cpu_ptr(runqueues) (ksym vmw_steal_time khong nap duoc)
11132649663410,2026-10-06T22:05:12.354675061+07:00,0,,,114571529614,11457

$ tail -3 out/steal-probe.log
bo qua ban doc vmw_steal_time theo yeu cau (-no-vmw)
=== 2026-10-06T22:05:12+07:00 khong nap duoc ban doc vmw_steal_time, chuyen sang ban chi co runqueues ===
bo qua ban doc vmw_steal_time theo yeu cau (-no-vmw)
```

## 6. File dữ liệu đã tạo
- `/root/hids/out/m1-selfcheck.csv` — dữ liệu đo thử 30 giây, 24 CPU, 720 dòng.
- `/root/hids/out/m1-run.log` — log màn hình của lần chạy trên.
- `/root/hids/out/steal-probe.log` — log lỗi nạp BPF nguyên văn (hiện chỉ có log của lần thử đường dự phòng).

Hai file `out/kiemtra-dondep.csv` và `out/kiemtra-duphong.csv` chỉ dùng để kiểm tra rồi xoá ngay.

## 7. Quyết định đã tự đưa ra và lý do
1. **Cơ chế chạy chương trình BPF**: dùng đúng phương án ưu tiên `SEC("syscall")` + `BPF_PROG_RUN`. Verifier chấp nhận ngay, nên không dùng đến phương án dự phòng `tp_btf/sched_switch`.
2. **Cách khai báo ksym** (xem thêm mục 8): loader bắt buộc của dự án không nạp được biến ksym có kiểu, nên tôi khai báo extern có kiểu nhưng bỏ thuộc tính `__ksym`, rồi user space ghi BTF id thật của biến vào lệnh nạp. `bpf_per_cpu_ptr` vẫn được dùng như yêu cầu.
3. **`-out` để trống thì tự đặt tên** `out/steal-<ngày giờ>.csv`, để lệnh kiểm nhanh không cần truyền tham số.
4. **Thêm cờ `-no-vmw`** cho `steal-probe` để ép chạy đường dự phòng. Không có cờ này thì không thể kiểm tra đường dự phòng khi máy vẫn đọc được `vmw_steal_time`.
5. **USER_HZ đọc từ `/proc/self/auxv` (AT_CLKTCK)**, nếu không có thì gọi `getconf CLK_TCK`. Dự án không được dùng cgo nên không gọi trực tiếp `sysconf`; cả hai nguồn đều là giá trị kernel cung cấp, không hard-code.
6. **Số CPU lấy từ `/sys/devices/system/cpu/online`** chứ không dùng số CPU mà tiến trình Go nhìn thấy, vì số sau có thể bị giới hạn bởi affinity.
7. **Ghi file CSV sau mỗi chu kỳ** để dữ liệu không mất khi dừng giữa chừng (quan trọng cho phép đo 600 giây).
8. **Cột `vmw_raw`/`vmw_ns` để trống** khi không đọc được, thay vì ghi số 0, để phân biệt "không đo được" với "bằng 0".
9. **Chế độ `-bucket` cộng chênh lệch giữa hai lần chụp liên tiếp** rồi gán vào khối chứa lần chụp sau, nên không bỏ sót khoảng thời gian giữa hai khối. Chế độ mặc định lấy hiệu giá trị cuối trừ giá trị đầu.
10. **Commit git dùng tác giả một lần** `root <root@uni-lms-app.local>` vì máy chưa đặt `user.name`/`user.email`. Tôi không ghi vào cấu hình git của máy.

## 8. Cần kiến trúc sư quyết định
1. **Cách nạp typed ksym.** Loader bắt buộc (`github.com/cilium/ebpf` v0.22.0, không cgo) từ chối biến ksym có kiểu, báo nguyên văn:
   ```
   can't load BPF from ELF: load virtual .ksyms section: data section .ksyms:
   expected vmw_steal_time to be *Void, not *btf.Var: not supported
   ```
   Thư viện chỉ phân giải ksym thành một địa chỉ dạng số, trong khi `bpf_per_cpu_ptr` đòi con trỏ có kiểu per-CPU.
   - Phương án A (đang dùng): khai báo extern có kiểu, bỏ `__ksym`, user space tra BTF id thật của biến trong `/sys/kernel/btf/vmlinux` rồi ghi vào lệnh `ld_imm64` dưới dạng `BPF_PSEUDO_BTF_ID`. Đây đúng là việc libbpf làm cho typed ksym. Hệ quả: giữ nguyên `bpf_per_cpu_ptr`, verifier vẫn kiểm kiểu theo BTF kernel, offset trường do CO-RE sinh; đổi lại có khoảng 40 dòng mã sửa lệnh trong `internal/stealbpf/loader.go`.
   - Phương án B: tự cộng địa chỉ `__per_cpu_offset[cpu]` rồi `bpf_probe_read_kernel`. Hệ quả: không cần sửa lệnh, nhưng mất kiểm tra kiểu của verifier và phải tự làm số học địa chỉ.
   - Phương án C: đổi sang libbpf qua cgo. Hệ quả: trái quy tắc hiện tại của dự án.
   Cần duyệt một phương án để dùng thống nhất cho M2.
2. **Hai dòng comment thêm trong header CSV.** Đặc tả yêu cầu header gồm: `uname -r`, số CPU, `tsc_khz`, cơ chế BPF, git commit, interval. Tôi thêm `user_hz` (vì `steal-summary` cần để đổi tick sang ms, và dùng đúng giá trị lúc đo thay vì giá trị lúc phân tích) và `tsc_source` (dòng kernel log nguyên văn, để truy nguồn `tsc_khz`), cùng `duration` và `reference`. Cần duyệt giữ hay bỏ.
3. **Độ phân giải của nguồn tham chiếu.** Khi máy rảnh, `/proc/stat` chỉ phân giải 10 ms nên Δ theo từng CPU chỉ nhận giá trị 0 hoặc 10 ms, làm tỉ lệ theo từng CPU rất thô; chỉ dòng TỔNG là so sánh được. Nếu cần nguồn tham chiếu mịn hơn cho M2, xin chỉ định nguồn (ví dụ `/proc/<tid>/schedstat` hoặc perf) để tôi lấy thêm.

## 9. Việc người dùng cần làm tay
Phép đo 600 giây cần thao tác trên vCenter nên tôi không chạy. Các bước:

1. Mở terminal trên máy này, vào thư mục dự án:
   ```
   cd /root/hids
   ```
2. Chuẩn bị sẵn thao tác trên vCenter mà anh/chị muốn thực hiện (ví dụ tạo tranh chấp CPU trên host).
3. Chạy lệnh sau bằng root. Script chạy đúng 600 giây, in ra từng phút:
   ```
   sudo bash scripts/g1.sh
   ```
4. Đến giây thứ 60 script tự chạy `/root/dk2.sh` (tải 24 vCPU trong 7 phút). Không cần làm gì thêm.
5. Trong lúc script chạy, thực hiện thao tác trên vCenter theo kế hoạch. Ghi lại giờ bắt đầu và giờ kết thúc thao tác (theo đồng hồ máy này) để đối chiếu.
6. Khi script kết thúc, nó in ra đường dẫn file dữ liệu và hai lệnh tổng hợp. Chạy cả hai lệnh đó và gửi lại cho tôi:
   - đường dẫn file `out/g1-<ngày giờ>.csv`,
   - output của hai lệnh `steal-summary`,
   - giờ bắt đầu và kết thúc thao tác vCenter ở bước 5.

Lưu ý: `/root/dk2.sh` tạo tải nặng 24 vCPU trong 7 phút, sẽ làm chậm các dịch vụ khác trên máy. Hãy chọn thời điểm phù hợp.

## 10. Lỗi còn tồn tại, việc tiếp theo đề xuất
Lỗi còn tồn tại:
- Chưa có lỗi nào chặn công việc. `make build` sạch, `go vet` không báo gì, kernel sạch sau khi thoát.
- `runqueues.prev_steal_time` chỉ được kernel cập nhật theo tick (HZ=1000) nên trễ tới khoảng 1 ms so với `vmw_steal_time.clock` đọc tức thời. Đây là tính chất của nguồn dữ liệu, không phải lỗi công cụ.
- Chưa có số liệu khi máy bị steal nặng, vì chưa chạy `scripts/g1.sh`.

Việc tiếp theo đề xuất:
1. Người dùng chạy `scripts/g1.sh` theo mục 9, tôi phân tích và viết báo cáo R002.
2. Kiến trúc sư trả lời ba câu hỏi ở mục 8.
3. Sau khi có câu trả lời, bắt đầu M2 theo đặc tả bản ghi 48 byte đã chốt.
