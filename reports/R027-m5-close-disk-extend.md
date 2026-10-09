# R027 — Đóng M5, mở rộng đĩa root (~3 TB)

1. **Số báo cáo:** R027  
   **Ngày giờ:** 2026-10-09 15:10 (UTC+7)  
   **Mốc:** M5 (đóng sau duyệt R026)  
   **Git:** tag `m5h` (cây HEAD sau commit dọn validation/STATE)

2. **Mục tiêu**  
   Ghi nhận mở rộng filesystem `/` sau khi gắn đĩa `sdc` (~2,9 TB); báo cho kiến trúc sư cấu hình lưu trữ hiện tại.

3. **Đã làm gì**  
   - `pvcreate /dev/sdc` → `vgextend ubuntu-vg /dev/sdc` → `lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` → `resize2fs` (online).  
   - Không reboot, không đổi sysctl.

4. **Lệnh (lặp lại)**  
   ```bash
   sudo pvcreate /dev/sdc
   sudo vgextend ubuntu-vg /dev/sdc
   sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
   sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
   df -hT /
   lsblk
   sudo pvs && sudo vgs && sudo lvs
   ```

5. **Kết quả (nguyên văn)**

   **Trước (tham chiếu R018/R026):** LV `ubuntu-lv` ~697 GiB trên PV `sda3` + `sdb`; VG hết chỗ trống.

   **`df -hT /` sau mở rộng:**  
   ```
   Filesystem                        Type  Size  Used Avail Use% Mounted on
   /dev/mapper/ubuntu--vg-ubuntu--lv ext4  3.6T  189G  3.3T   6% /
   ```

   **`lsblk` (rút gọn):**  
   ```
   sda                         200G disk
   ├─sda3                    196.9G part LVM2_member
   sdb                         500G disk LVM2_member
   sdc                         2.9T disk LVM2_member
   └─ubuntu--vg-ubuntu--lv     3.6T lvm  ext4        /
   ```

   **`pvs`:**  
   ```
   /dev/sda3  ubuntu-vg  <196.95g    0
   /dev/sdb   ubuntu-vg  <500.00g    0
   /dev/sdc   ubuntu-vg    <2.93t    0
   ```

   **`vgs`:**  
   ```
   ubuntu-vg   3 PV   1 LV   VSize 3.61t   VFree 0
   ```

   **`lvs` (phân đoạn):**  
   ```
   ubuntu-lv  3.61t  /dev/sda3:0-50417
   ubuntu-lv  3.61t  /dev/sdb:0-127998
   ubuntu-lv  3.61t  /dev/sdc:0-767998
   ```

6. **File dữ liệu**  
   - (Không — chỉ thay đổi cấu hình LVM/ext4 trên máy.)

7. **Quyết định đã tự đưa ra**  
   - Gắn toàn bộ `sdc` vào VG `ubuntu-vg` hiện có và mở rộng LV `ubuntu-lv` duy nhất (không tách mount riêng).

8. **Cần kiến trúc sư quyết định**  
   - (Không.)

9. **Việc người dùng cần làm tay**  
   - (Không.)

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Dữ liệu `.bin` lớn vẫn nằm ngoài git (`*.bin` trong `.gitignore`); dung lượng đĩa dùng cho validation/`out/` bench tiếp theo.
