-- ==============================================================================
-- 05: SEED DATA (DỮ LIỆU MẪU ĐẤT PHÚ CHỢ PHIÊN)
-- ==============================================================================

-- 1. Thêm danh mục sản phẩm mẫu
INSERT INTO public.categories (id, name, slug, display_order) VALUES
('c1000000-0000-0000-0000-000000000001', 'Siêu Thị Mẹ & Bé (Sữa Tã)', 'sua-ta-me-va-be', 1),
('c1000000-0000-0000-0000-000000000002', 'Đặc Sản Xứ Nẫu & OCOP', 'dac-san-xu-nau-ocop', 2),
('c1000000-0000-0000-0000-000000000003', 'Bếp Chay Thanh Tịnh', 'bep-chay-thanh-tinh', 3),
('c1000000-0000-0000-0000-000000000004', 'Thiết Bị IT & Camera An Ninh', 'it-camera-an-ninh', 4)
ON CONFLICT (slug) DO NOTHING;

-- 2. Thêm sản phẩm mẫu
INSERT INTO public.products (id, category_id, name, slug, description, images, is_published, is_featured, rating_avg) VALUES
(
    'd1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'Bò Một Nắng Krông Pa Chấm Muối Kiến Vàng',
    'bo-mot-nang-krong-pa',
    'Đặc sản bò cỏ chăn thả tự nhiên vùng Krông Pa, phơi đúng một nắng giòn rụm, kèm muối kiến vàng rừng nguyên chất xứ Nẫu.',
    ARRAY['https://images.unsplash.com/photo-1544025162-d76694265947?w=800'],
    true,
    true,
    5.0
),
(
    'd1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000002',
    'Nước Mắm Gành Đỏ Truyền Thống 40 Độ Đạm',
    'nuoc-mam-ganh-do-truyen-thong',
    'Nước mắm ủ chượp từ cá cơm than vịnh Xuân Đài, thơm đượm, hậu vị ngọt tự nhiên, không hóa chất phụ gia.',
    ARRAY['https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=800'],
    true,
    true,
    4.9
),
(
    'd1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000003',
    'Mâm Cỗ Giỗ Chay 8 Món Thanh Tịnh Tâm Đức',
    'mam-co-gio-chay-8-mon',
    'Mâm cỗ chay đầy đặn gồm nem nấm, chả giò sen, soup hạt sen, gỏi tiến vua, nấm đùi gà kho tiêu. Nấu mới 100% bằng nguyên liệu sạch.',
    ARRAY['https://images.unsplash.com/photo-1540420773420-3366772f4999?w=800'],
    true,
    true,
    5.0
),
(
    'd1000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000004',
    'Camera WiFi Ngoài Trời EZVIZ H8c Xoay 360 Độ',
    'camera-ezviz-h8c-360',
    'Camera giám sát ngoài trời chịu nắng mưa, ban đêm có màu, phát hiện dáng người AI, hỗ trợ lắp đặt tận nơi Tuy Hòa.',
    ARRAY['https://images.unsplash.com/photo-1557597774-9d273605dfa9?w=800'],
    true,
    true,
    4.8
)
ON CONFLICT (slug) DO NOTHING;

-- 3. Thêm biến thể sản phẩm & tồn kho
INSERT INTO public.product_variants (product_id, sku, title, price, compare_at_price, stock_quantity, attributes) VALUES
('d1000000-0000-0000-0000-000000000001', 'BOMN-500G', 'Gói hút chân không 500g', 280000, 310000, 50, '{"weight": "500g"}'),
('d1000000-0000-0000-0000-000000000001', 'BOMN-1KG', 'Gói quà tặng 1kg (Tặng kèm 2 hũ muối kiến)', 550000, 600000, 30, '{"weight": "1kg"}'),
('d1000000-0000-0000-0000-000000000002', 'NMGD-CAP-500ML', 'Cặp 2 chai thủy tinh 500ml', 160000, 180000, 100, '{"volume": "1000ml"}'),
('d1000000-0000-0000-0000-000000000003', 'MCCHAY-8MON', 'Set trọn gói 1 mâm (Bàn ghế + Bát đĩa sành)', 850000, 950000, 10, '{"set": "8 món"}'),
('d1000000-0000-0000-0000-000000000004', 'CAM-H8C-NO-CARD', 'Camera kèm công lắp đặt cơ bản', 890000, 990000, 20, '{"storage": "chưa thẻ"}'),
('d1000000-0000-0000-0000-000000000004', 'CAM-H8C-64GB', 'Camera + Thẻ nhớ Sandisk 64GB + Công lắp đặt', 1050000, 1190000, 15, '{"storage": "thẻ 64GB"}')
ON CONFLICT (sku) DO NOTHING;
