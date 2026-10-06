#!/usr/bin/env python3
import subprocess
from pathlib import Path

root = Path("/root/hids")
comm = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=root, text=True).strip()
v = root / "validation/g3-20261007"
parts = ["S1", "S2", "S3", "S4", "S5", "G-real", "G-irq", "G7d"]
body = []
cpu_lines = []
for p in parts:
    text = (v / f"{p}-ketqua.txt").read_text()
    body.append(f"### {p}\n\n```\n{text}\n```\n")
    for line in text.splitlines():
        if "thoi gian chay:" in line and "CPU collector" in line:
            cpu_lines.append(f"- {p}: {line.strip()}")
            break

report = f"""# Báo cáo R005 — M3 PHẦN 2 (mục F–J)

1. **Số báo cáo:** R005 | **Ngày giờ:** 2026-10-07 00:42 (giờ máy) | **Mốc:** M3 PHẦN 2 | **Git commit:** {comm}

2. **Mục tiêu**  
Hoàn thành M3 mục F–J: `tools/wl.c`, `bin/rec-check`, `scripts/g3.sh`, tự chạy G3, lưu `validation/g3-20261007/`, tag `m3`.

3. **Đã làm gì**  
- `tools/wl.c`, `bin/rec-check`, `scripts/g3.sh`, `scripts/g3_window.py`, `scripts/g3-driver.sh`.  
- Tự chạy S1–S5, G-real, G-irq, G7d.  
- Sửa chờ `wl` bằng `wchan=pipe_read`; giảm `clock_gettime` trong vòng đốt CPU của `wl`.

4. **Lệnh build, lệnh chạy**  
```
make build
sudo bash scripts/g3.sh
```

5. **Kết quả** (nguyên văn từ `validation/g3-20261007/*-ketqua.txt`):

{"".join(body)}

**recursion_misses:** tong 0 tren 30 chuong trinh BPF (moi chuong trinh 0, xem cuoi log trong tung *-ketqua.txt).

**Chi phí CPU collector (getrusage):**  
{chr(10).join(cpu_lines)}

6. **File dữ liệu:** `/root/hids/validation/g3-20261007/`, log `/root/hids/out/jobs/g3-driver.log`

7. **Quyết định tự đưa ra**  
Chờ `pipe_read`; biên cửa sổ từ hai syscall `read` sau `getuid`; G-real chỉ PID trong cgroup.procs hai mốc.

8. **Cần kiến trúc sư**  
G-real tập thread và tổng sched; G-irq đơn vị đối chiếu (bcc usec vs collector ns); wl vẫn sinh nr=228 trong S1/S3/S4 ở lần chạy này.

9. **Việc người dùng:** không.

10. **Tiếp theo:** chạy lại S1–S5 với wl spin 262144; G-irq với parse bcc đã sửa. DỪNG, không M4.
"""
(root / "reports/R005-m3-phan2-g3-wl-rec-check.md").write_text(report)
print("ok", len(report))
