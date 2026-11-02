-- =========================================================================
-- ĐẤT PHÚ KÍN KẼ OS™ — MODULE GIAN HÀNG SỐ & KHO ẢNH DỊCH VỤ THỢ 6K
-- CÔNG TY TNHH THƯƠNG MẠI ĐẤT PHÚ (MST: 4401020233)
-- Phân quyền RLS: Thợ toàn quyền gian hàng của mình, Khách hàng xem công khai
-- =========================================================================

-- 1. BẢNG GIAN HÀNG SỐ CÁ NHÂN CỦA THỢ (dp_technician_storefronts)
CREATE TABLE IF NOT EXISTS public.dp_technician_storefronts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  technician_id UUID NOT NULL REFERENCES public.dp_technicians(id) ON DELETE CASCADE UNIQUE,
  store_title VARCHAR(150) NOT NULL, -- Ví dụ: "Điện Lạnh Phú Yên Chuyên Nghiệp - Thợ Phú"
  store_slug VARCHAR(150) UNIQUE,     -- 'dien-lanh-tho-phu-tuy-hoa'
  bio_description TEXT,              -- Giới thiệu 10 năm kinh nghiệm Inverter...
  service_district VARCHAR(100) DEFAULT 'TP. Tuy Hòa & Phú Hòa',
  cover_image_url TEXT,
  avatar_url TEXT,
  hotline VARCHAR(20),
  zalo_number VARCHAR(20),
  is_published BOOLEAN DEFAULT TRUE,
  verified_status VARCHAR(30) DEFAULT 'verified_6k', -- 'pending', 'verified_6k', 'suspended'
  views_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_storefront_tech ON public.dp_technician_storefronts(technician_id);
CREATE INDEX IF NOT EXISTS idx_storefront_published ON public.dp_technician_storefronts(is_published, verified_status);

-- 2. BẢNG DỊCH VỤ NIÊM YẾT TẠI GIAN HÀNG (dp_storefront_services)
CREATE TABLE IF NOT EXISTS public.dp_storefront_services (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  storefront_id UUID NOT NULL REFERENCES public.dp_technician_storefronts(id) ON DELETE CASCADE,
  service_title VARCHAR(150) NOT NULL,
  category_id VARCHAR(30) REFERENCES public.dp_demand_categories(id),
  fixed_price_k3 BIGINT NOT NULL DEFAULT 350000,
  warranty_duration VARCHAR(50) DEFAULT '6 tháng (K6)',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. BẢNG KHO ẢNH CÔNG TRÌNH THỰC TẾ (dp_portfolio_images)
CREATE TABLE IF NOT EXISTS public.dp_portfolio_images (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  storefront_id UUID NOT NULL REFERENCES public.dp_technician_storefronts(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  title VARCHAR(200) NOT NULL, -- Ví dụ: "Lắp đặt dàn nóng máy lạnh Daikin Inverter tại Phường 7"
  category_tag VARCHAR(50) DEFAULT 'dienlanh',
  location_geostamp VARCHAR(100) DEFAULT 'P.7, TP. Tuy Hòa',
  work_completed_date DATE DEFAULT CURRENT_DATE,
  moderation_status VARCHAR(30) DEFAULT 'approved', -- 'pending_review', 'approved', 'rejected'
  moderated_at TIMESTAMPTZ DEFAULT NOW(),
  moderated_by VARCHAR(50) DEFAULT 'n8n_auto_moderator',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_portfolio_storefront ON public.dp_portfolio_images(storefront_id, moderation_status);

-- =========================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- =========================================================================

-- BẬT RLS CHO CẢ 3 BẢNG
ALTER TABLE public.dp_technician_storefronts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dp_storefront_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dp_portfolio_images ENABLE ROW LEVEL SECURITY;

-- 1. POLICIES CHO dp_technician_storefronts
-- Khách hàng & Công chúng: Xem công khai các gian hàng đã xuất bản & xác thực
CREATE POLICY "public_view_published_storefronts" ON public.dp_technician_storefronts
  FOR SELECT
  TO public, authenticated
  USING (is_published = TRUE AND verified_status = 'verified_6k');

-- Thợ kỹ thuật: Toàn quyền SELECT, INSERT, UPDATE trên gian hàng của chính mình
CREATE POLICY "technician_manage_own_storefront" ON public.dp_technician_storefronts
  FOR ALL
  TO authenticated
  USING (
    technician_id IN (SELECT id FROM public.dp_technicians WHERE user_id = auth.uid())
  )
  WITH CHECK (
    technician_id IN (SELECT id FROM public.dp_technicians WHERE user_id = auth.uid())
  );

-- 2. POLICIES CHO dp_storefront_services
-- Xem công khai các dịch vụ đang hoạt động
CREATE POLICY "public_view_active_services" ON public.dp_storefront_services
  FOR SELECT
  TO public, authenticated
  USING (is_active = TRUE);

-- Thợ chỉnh sửa dịch vụ gian hàng của mình
CREATE POLICY "technician_manage_own_services" ON public.dp_storefront_services
  FOR ALL
  TO authenticated
  USING (
    storefront_id IN (
      SELECT s.id FROM public.dp_technician_storefronts s
      JOIN public.dp_technicians t ON s.technician_id = t.id
      WHERE t.user_id = auth.uid()
    )
  )
  WITH CHECK (
    storefront_id IN (
      SELECT s.id FROM public.dp_technician_storefronts s
      JOIN public.dp_technicians t ON s.technician_id = t.id
      WHERE t.user_id = auth.uid()
    )
  );

-- 3. POLICIES CHO dp_portfolio_images
-- Xem công khai các ảnh đã được duyệt (approved)
CREATE POLICY "public_view_approved_portfolio_images" ON public.dp_portfolio_images
  FOR SELECT
  TO public, authenticated
  USING (moderation_status = 'approved');

-- Thợ thêm, sửa, xóa ảnh của chính gian hàng mình
CREATE POLICY "technician_manage_own_portfolio_images" ON public.dp_portfolio_images
  FOR ALL
  TO authenticated
  USING (
    storefront_id IN (
      SELECT s.id FROM public.dp_technician_storefronts s
      JOIN public.dp_technicians t ON s.technician_id = t.id
      WHERE t.user_id = auth.uid()
    )
  )
  WITH CHECK (
    storefront_id IN (
      SELECT s.id FROM public.dp_technician_storefronts s
      JOIN public.dp_technicians t ON s.technician_id = t.id
      WHERE t.user_id = auth.uid()
    )
  );

-- =========================================================================
-- SEED GIAN HÀNG & KHO ẢNH THỰC TẾ MẪU
-- =========================================================================
INSERT INTO public.dp_technician_storefronts (
  technician_id, store_title, store_slug, bio_description, service_district, hotline, zalo_number
) VALUES (
  'a0000000-0000-0000-0000-000000000001',
  '❄️ Trung Tâm Điện Lạnh & Inverter Thợ Phú Tuy Hòa',
  'dien-lanh-tho-phu-tuy-hoa',
  '12 năm kinh nghiệm sửa chữa điện lạnh gia dụng tại Phú Yên. Chuyên Inverter Daikin, Panasonic, Toshiba. Hút chân không gas chuẩn đồng hồ, bảo hành 6 tháng bằng mã QR K6.',
  'TP. Tuy Hòa, Phú Hòa & lân cận',
  '0977.334.455',
  '0977334455'
) ON CONFLICT (technician_id) DO NOTHING;

-- Nạp ảnh mẫu vào kho ảnh
INSERT INTO public.dp_portfolio_images (storefront_id, image_url, title, category_tag, location_geostamp)
SELECT 
  s.id,
  'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?auto=format&fit=crop&w=600&q=80',
  'Lắp đặt hoàn thiện bộ máy lạnh Inverter Daikin 1.5HP tại Phường 5, TP. Tuy Hòa',
  'dienlanh',
  'Số 12 Nguyễn Huệ, P.5, Tuy Hòa'
FROM public.dp_technician_storefronts s
WHERE s.store_slug = 'dien-lanh-tho-phu-tuy-hoa'
ON CONFLICT DO NOTHING;
