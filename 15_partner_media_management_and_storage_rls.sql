-- ============================================================================
-- MIGRATION 15: QUẢN LÝ TỆP HÌNH ẢNH ĐỐI TÁC & SUPABASE STORAGE BUCKET RLS
-- Đơn vị: CÔNG TY TNHH THƯƠNG MẠI ĐẤT PHÚ (MST: 4401020233)
-- Hệ sinh thái: Đất Phú Kín Kẽ OS™ Gen 4 — Bucket `partner-media`
-- ============================================================================

-- 1. BẢNG QUẢN LÝ TỆP HÌNH ẢNH ĐỐI TÁC (partner_images)
CREATE TABLE IF NOT EXISTS public.partner_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_id VARCHAR(50) NOT NULL,
    partner_name VARCHAR(150),
    file_path TEXT NOT NULL,                     -- Đường dẫn URL trên Storage (/storage/images/...)
    file_name VARCHAR(255) NOT NULL,             -- Tên gốc của tệp
    category VARCHAR(50) DEFAULT 'PORTFOLIO',   -- PORTFOLIO, PROFILE, COVER, WORK_SAMPLE, PRICE_LIST
    file_size INT NOT NULL,                      -- Kích thước tệp (bytes)
    width INT,                                   -- Chiều rộng (px)
    height INT,                                  -- Chiều cao (px)
    location_geostamp VARCHAR(255),              -- Đóng dấu GPS (Ví dụ: P.5, TP. Tuy Hòa)
    moderation_status VARCHAR(20) DEFAULT 'approved', -- approved, flagged, pending, rejected
    flagged_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Chỉ mục tối ưu hóa tốc độ truy vấn Media Dashboard
CREATE INDEX IF NOT EXISTS idx_partner_images_partner ON public.partner_images(partner_id);
CREATE INDEX IF NOT EXISTS idx_partner_images_category ON public.partner_images(category);
CREATE INDEX IF NOT EXISTS idx_partner_images_status ON public.partner_images(moderation_status);
CREATE INDEX IF NOT EXISTS idx_partner_images_date ON public.partner_images(created_at DESC);

-- 2. THIẾT LẬP CHÍNH SÁCH BẢO MẬT RLS (ROW-LEVEL SECURITY)
ALTER TABLE public.partner_images ENABLE ROW LEVEL SECURITY;

-- Chính sách 1: Quản trị viên (Chủ sàn) toàn quyền quản lý, kiểm duyệt, xóa ảnh
CREATE POLICY "Admin full access on partner_images" 
ON public.partner_images 
FOR ALL 
USING (
    EXISTS (
        SELECT 1 FROM public.users 
        WHERE users.id = auth.uid() AND users.role = 'admin'
    )
);

-- Chính sách 2: Đối tác chỉ được thêm, sửa, xóa ảnh của chính gian hàng mình
CREATE POLICY "Partner can manage own images" 
ON public.partner_images 
FOR ALL 
USING (
    partner_id = (SELECT phone FROM public.users WHERE users.id = auth.uid()) OR
    partner_id = auth.uid()::text
);

-- Chính sách 3: Khách hàng công khai xem các ảnh đã duyệt (approved)
CREATE POLICY "Public read approved images" 
ON public.partner_images 
FOR SELECT 
USING (moderation_status = 'approved');

-- 3. VIEW THỐNG KÊ KHO DỮ LIỆU MEDIA CHO CHỦ SÀN (v_partner_media_stats)
CREATE OR REPLACE VIEW public.v_partner_media_stats AS
SELECT 
    category,
    COUNT(id) AS total_files,
    SUM(file_size) AS total_bytes,
    ROUND(SUM(file_size)::NUMERIC / 1048576, 2) AS total_megabytes,
    COUNT(CASE WHEN moderation_status = 'flagged' THEN 1 END) AS flagged_count
FROM public.partner_images
GROUP BY category
ORDER BY total_files DESC;

-- 4. HÀM KIỂM DUYỆT ẢNH HÀNG LOẠT (fn_moderate_media_batch)
CREATE OR REPLACE FUNCTION public.fn_moderate_media_batch(
    p_image_ids UUID[],
    p_action VARCHAR(20), -- 'approve', 'flag', 'delete'
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INT := 0;
BEGIN
    IF p_action = 'delete' THEN
        DELETE FROM public.partner_images 
        WHERE id = ANY(p_image_ids);
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RETURN jsonb_build_object('success', true, 'action', 'deleted', 'affectedRows', v_count);
    ELSIF p_action = 'flag' THEN
        UPDATE public.partner_images 
        SET moderation_status = 'flagged', flagged_reason = p_reason
        WHERE id = ANY(p_image_ids);
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RETURN jsonb_build_object('success', true, 'action', 'flagged', 'affectedRows', v_count);
    ELSE
        UPDATE public.partner_images 
        SET moderation_status = 'approved', flagged_reason = NULL
        WHERE id = ANY(p_image_ids);
        GET DIAGNOSTICS v_count = ROW_COUNT;
        RETURN jsonb_build_object('success', true, 'action', 'approved', 'affectedRows', v_count);
    END IF;
END;
$$;

-- 5. KÍCH HOẠT REALTIME CHO BẢNG MEDIA
ALTER PUBLICATION supabase_realtime ADD TABLE public.partner_images;

-- 6. DỮ LIỆU KHỞI TẠO (SEED DATA MEDIA THỰC TẾ)
INSERT INTO public.partner_images (
    partner_id, partner_name, file_path, file_name, 
    category, file_size, width, height, location_geostamp, moderation_status
) VALUES 
(
    'w_01', 
    'Nguyễn Văn Đạt (Điện Lạnh 6K)', 
    'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?auto=format&fit=crop&w=800&q=80', 
    'lap_dat_dieu_hoa_inverter_p5.jpg', 
    'PORTFOLIO', 
    412500, 
    1080, 720, 
    'P.5, TP. Tuy Hòa', 
    'approved'
),
(
    'w_01', 
    'Nguyễn Văn Đạt (Điện Lạnh 6K)', 
    'https://images.unsplash.com/photo-1581092160607-ee22621dd758?auto=format&fit=crop&w=800&q=80', 
    've_sinh_may_giat_cua_ngang.jpg', 
    'WORK_SAMPLE', 
    389200, 
    1080, 810, 
    'P. Phú Đông, TP. Tuy Hòa', 
    'approved'
),
(
    'shop-dienlanh-tuyhoa', 
    'Điện Lạnh Phú Yên Center', 
    'https://images.unsplash.com/photo-1581092335397-9583fe92d232?auto=format&fit=crop&w=800&q=80', 
    'bien_hieu_showroom_nguyen_hue.jpg', 
    'COVER', 
    524100, 
    1200, 675, 
    'Đường Nguyễn Huệ, TP. Tuy Hòa', 
    'approved'
),
(
    'w_02', 
    'Trần Minh Khoa (Điện Nước)', 
    'https://images.unsplash.com/photo-1607472586893-edb57bdc0e39?auto=format&fit=crop&w=800&q=80', 
    'lap_he_thong_ong_nhiet_pvc.jpg', 
    'PORTFOLIO', 
    345600, 
    1080, 720, 
    'Xã Hòa An, H. Phú Hòa', 
    'approved'
),
(
    'w_03', 
    'Lê Hoàng Nam (Thợ Khóa)', 
    'https://images.unsplash.com/photo-1558002038-1055907df827?auto=format&fit=crop&w=800&q=80', 
    'mo_khoa_van_tay_thong_minh.jpg', 
    'WORK_SAMPLE', 
    298400, 
    960, 640, 
    'P.9, TP. Tuy Hòa', 
    'approved'
);
