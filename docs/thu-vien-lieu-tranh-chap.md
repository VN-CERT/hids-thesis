# Thư viện liều tranh chấp — đặc tả

> Mục đích: tạo tranh chấp tài nguyên ở các MỨC biết trước và đo được, để (1) đặc trưng hoá tác động lên từng thành phần thời gian, (2) chạy tấn công ở nhiều mức tranh chấp, (3) sinh dữ liệu cho tăng cường của Bài 2.
> Phiên bản 0.2 — 20/10/2026.

## 0. Nguyên tắc

- Mỗi "liều" là một (loại tranh chấp, mức) chạy trong một khoảng thời gian biết trước, có mốc mono_ns đầu/cuối.
- Workload nạn nhân (cái bị đo) chạy LƯỢNG CÔNG VIỆC CỐ ĐỊNH, để mọi thay đổi thời gian là do liều, không do workload đổi.
- Mỗi liều có **oracle**: một đại lượng hệ thống độc lập xác nhận mức tranh chấp thật (vmw_steal_time, cpu.stat throttled_usec, số worker, v.v.).
- Chạy trên máy nạn nhân lab (và sau này trên VM lab khác), KHÔNG trên production.

## 0b. Ba máy (phân biệt cấu hình)

| Máy | Vai trò | Cấu hình | Chạy gì |
|---|---|---|---|
| uni-lms-app (…95) | máy test — đã làm M1–M6b | 24 vCPU, Xeon Gold 6330, L3 42 MiB | E1–E4 GỐC (đã xong, dữ liệu của bài) |
| hids-collector (55.201) | lab nạn nhân | 8 vCPU, 16 GB | thư viện liều MỚI, E5, đối chứng F1, bị tấn công |
| hids-acttack (55.202) | lab tấn công | 8 vCPU, 16 GB | công cụ tấn công |

E1–E4 trên máy test GIỮ NGUYÊN. Thư viện liều và E5 chạy trên lab nạn nhân (8 vCPU). Mọi con số phụ thuộc số vCPU hoặc xung nhịp phải tính lại theo máy đang chạy, KHÔNG chép cứng từ máy test.

## 1. Bốn trục tranh chấp

### D1 — tranh chấp hàng đợi chạy (rq)
- Cách tạo: chạy N tiến trình bận (stress-ng --cpu) ghim cùng CPU với workload nạn nhân.
- Mức: N = 0, 1, 2, 3, 4 (tiến trình cạnh tranh trên mỗi CPU của workload).
- Oracle: rq của collector tăng tuyến tính theo N; đối chiếu bpftrace @rq.
- Thành phần kỳ vọng bị ảnh hưởng: rq. cpu gần như không đổi.

### D2 — steal của hypervisor
- Cách tạo: đặt CPU limit trên vCenter (PowerCLI) ở các mức, có khối finally luôn gỡ limit.
- Mức: đặt theo PHẦN TRĂM công suất danh định của chính VM, không chép cứng MHz từ máy test (24 vCPU). Công suất danh định ≈ (số vCPU) × (xung nhịp danh định MHz). Lab nạn nhân 8 vCPU × ~2000 MHz ≈ 16000 MHz là 100%. Các mức: không limit / 75% / 50% / 25% của con số đó. Tính lại nếu VM khác số vCPU. Ghi rõ MHz thực đặt và % tương ứng vào nhãn.
- Oracle: vmw_steal_time; đối chiếu vCenter Ready + Co-stop; số liệu realtime vCenter chỉ giữ ~1 giờ, lấy ngay.
- Thành phần kỳ vọng: steal (khoảng đốt), steal_off (khoảng ngủ).

### D3 — tranh chấp bộ nhớ (cache + băng thông)
- Cách tạo: stress-ng --cache và --stream với số worker tăng dần, trên các CPU khác.
- Mức: 0, 4, 12, 22 worker (như E4 trên máy test).
- Oracle (CẦN vPMC): số lệnh thực thi và/hoặc trượt LLC trên mỗi khoảng; CPI = cycles/instructions. Nếu KHÔNG có vPMC: tác vụ "chim hoàng yến" (duyệt con trỏ trên bộ đệm cỡ LLC ~1 ms mỗi giây), lấy thời gian của nó làm chỉ số.
- Thành phần kỳ vọng: cpu phình (×1,5 đến ×4), rq và steal ≈ 0. ĐÂY là trục mà "trừ đi" không xử lý được → cần conditioning.

### D4 — throttle cgroup (CFS quota) — cho E5
- Cách tạo: chạy workload nạn nhân trong một container có giới hạn CPU: docker run --cpus=X (hoặc đặt cpu.max trong cgroup v2).
- Mức: không giới hạn / --cpus=2 / --cpus=1 / --cpus=0.5.
- Oracle: nr_throttled và throttled_usec trong cpu.stat của cgroup đó (đã nằm trong luồng host mỗi giây của collector).
- Thành phần kỳ vọng: thời gian bị throttle rơi vào rq (vì task ở trạng thái chạy được nhưng không được cấp CPU); steal = 0. Đây là nguồn trễ mà stealclock KHÔNG thấy.

## 2. Thí nghiệm E5 (throttle) — thiết kế cụ thể

- Workload nạn nhân: chương trình hành vi biết trước (kiểu wl) hoặc pgbench lượng cố định, trong container.
- Với mỗi mức D4: chạy ~60 giây, lượng công việc cố định.
- Đo: Δrq của collector so với Δthrottled_usec trong cpu.stat (kỳ vọng tương quan mạnh); kiểm steal ≈ 0 để chắc throttle không bị nhầm thành steal.
- Kết quả đưa vào Bài 1 (F5) và làm một chiều điều kiện của Bài 2.

## 3. Thí nghiệm đối chứng F1 (run_delay)

- Mục đích: kiểm giả thuyết "kernel ghi ~6 µs sau wakeup vào sum_exec thay vì run_delay, do CPU đích đang rảnh".
- Thiết kế: lặp kịch bản S2 (ngủ/dậy 500 lần) ở hai điều kiện:
  - (a) CPU đích để rảnh (như hiện tại);
  - (b) giữ CPU đích luôn bận bằng một tiến trình quay vòng ưu tiên thấp trên cùng CPU.
- Kỳ vọng: nếu khoảng lệch (collector rq − kernel run_delay) biến mất ở (b), thì nó gắn với việc đánh thức CPU từ trạng thái rảnh.
- Oracle: bpftrace @rq_sau_wakeup_ns ở cả hai điều kiện.
- Tái lập trên ≥ 2 kernel (cần một VM lab chạy kernel 6.8 bản khác) bằng bpftrace + schedstat, KHÔNG cần collector.

## 4. Ghi nhãn mỗi liều

Mỗi liều sinh một dòng `lab/nhan-lieu.tsv`:
```
dose_id  truc(D1..D4)  muc  t_bat_dau_mono_ns  t_ket_thuc_mono_ns  oracle_ten  oracle_gia_tri  ghi_chu
```

## 5. Dùng chung với tấn công

- Khi chạy một tấn công lớp B ở "mức tranh chấp k", nghĩa là: bật liều tương ứng (một hoặc nhiều trục) TRƯỚC, để ổn định, rồi chạy tấn công trong lúc liều đang chạy.
- Bản ghi collector lúc đó mang cả dấu vết tấn công lẫn tranh chấp — đúng tình huống production mà Bài 2 cần chứng minh.
