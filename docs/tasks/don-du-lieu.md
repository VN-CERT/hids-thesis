Thêm chính sách dọn dữ liệu (lưu vào docs/tasks/don-du-lieu.md):
1. Các script đo overhead và benchmark (m5*.sh, g7.sh phần b/b-nho): xoá file .bin ngay sau khi đã tóm tắt xong và đã kiểm số bản ghi; chỉ giữ .stats, .periodic, result.txt và summary.
2. Thí nghiệm dùng làm dữ liệu cho bài báo (M4, thư viện liều, thu dài ngày) thì GIỮ dữ liệu thô, đánh dấu bằng biến KEEP_RAW=1.
3. Mọi job chạy lâu: trước khi bắt đầu, nếu dung lượng trống < 20 GB thì từ chối chạy và báo; khi kết thúc in df -h.
4. Thêm target make clean-out: xoá dữ liệu thô trong out/ cũ hơn 2 ngày, KHÔNG đụng validation/ và out/jobs/.
Commit. Không cần viết báo cáo riêng; ghi vào báo cáo kế tiếp.
