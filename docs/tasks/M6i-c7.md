M6i-c7 rút gọn — xác nhận T² công bằng (c5_score v1.5 đã cài, sha b82f4e23…; nếu khác DỪNG). KHÔNG ghi đè, ra thư mục -fair-.
1. T² với CÙNG train-until như max|z| (1006289550843307), bộ D/E/A:
   for CH in D E A; do python3 analysis/c5_score.py --features out/c5-lab1c/features_ghep.tsv --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --train-until 1006289550843307 --chieu-phanra $CH --t2 --out out/c5-lab1c/t2fair-v15-$CH; done
   In bảng so @ngân sách 0,01 và 0,05, mỗi CH: T²-công-bằng (bdg_nen, phat_hien, muc_D3-7, muc_0) ĐẶT CẠNH T²-R047 (out/c5-lab1c/t2-v15-$CH) và max|z|-R043 (số từ R047 bảng R047-B). Đọc thẳng: T²-công-bằng CÒN tách D3-7 ở bdg thấp không?
2. Bộ D T²-công-bằng: 20 cửa sổ tấn công muc_0 điểm cao nhất — tid, nguồn, điểm T², 3 chiều đóng góp lớn nhất. Nếu khó, ghi "để sau".
In kết quả ra chat, commit nhỏ, tag m6i.8. Không kết luận.
