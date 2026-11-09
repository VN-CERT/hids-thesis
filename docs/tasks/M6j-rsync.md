M6j-rsync — kéo LAB-2 pha 1 về 195. Chỉ rsync + kiểm, chưa chấm. KHÔNG đụng dữ liệu cũ.
1. rsync từ 201 (chỉ đọc bên 201): validation/lab2-20261108/ → /root/hids/validation/lab2-20261108/; lab/nhan-tan-cong-lab2.tsv và lab/nhan-tid-lab2.tsv → /root/hids/lab/. In dung lượng, số file .bin theo thư mục (A2/B2/C2 × mức), số dòng + 3 dòng đầu mỗi file nhãn.
2. Kiểm nhãn: mỗi run_id (9 phiên) có ≥1 tid trong nhan-tid-lab2; in bảng run_id, lop (A2/B2/C2), muc, n_tid, oracle. 
3. KHÔNG trích đặc trưng, KHÔNG chấm — chỉ xác nhận dữ liệu về đủ. Ghi out/jobs/m6j-rsync.status. In ra chat. DỪNG.
