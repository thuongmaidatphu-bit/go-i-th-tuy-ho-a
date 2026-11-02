-- =========================================================================
-- ĐẤT PHÚ KÍN KẼ OS™ — MASTER DATABASE SCHEMA: GỌI THỢ QUANH ĐÂY 6K
-- CÔNG TY TNHH THƯƠNG MẠI ĐẤT PHÚ (MST: 4401020233)
-- Tích hợp đầy đủ 6 Module: Tiếp nhận -> PostGIS -> n8n -> RBAC -> VietQR -> Rating
-- =========================================================================

-- Kích hoạt tiện ích không gian & UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- -------------------------------------------------------------------------
-- MODULE 1: TIẾP NHẬN NHU CẦU & DANH MỤC SỰ CỐ (DEMAND INTENT CATALOG)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dp_demand_categories (
  id VARCHAR(30) PRIMARY KEY, -- 'dienlanh', 'diennuoc', 'thongnghet', 'xemay', 'khoacua', 'maygiat', 'suanha', 'bocxep'
  name VARCHAR(100) NOT NULL,
  subtitle VARCHAR(150),
  icon VARCHAR(50) NOT NULL,
  default_price_k3 BIGINT NOT NULL DEFAULT 500000,
  warranty_months INT NOT NULL DEFAULT 6,
  sort_order INT DEFAULT 1,
  is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.dp_demand_symptoms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category_id VARCHAR(30) REFERENCES public.dp_demand_categories(id) ON DELETE CASCADE,
  symptom_text VARCHAR(255) NOT NULL,
  is_popular BOOLEAN DEFAULT TRUE
);

-- -------------------------------------------------------------------------
-- MODULE 2 & 4: HỒ SƠ THỢ, PHÂN QUYỀN RBAC & VỊ TRÍ POSTGIS
-- -------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE dp_worker_tier AS ENUM ('gold_master', 'silver_tech', 'probation');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.dp_technicians (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name VARCHAR(120) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  tier dp_worker_tier NOT NULL DEFAULT 'silver_tech',
  skills TEXT[] NOT NULL DEFAULT ARRAY['dienlanh'],
  assigned_district VARCHAR(50) DEFAULT 'TP. Tuy Hòa',
  duty_status VARCHAR(20) NOT NULL DEFAULT 'off_duty', -- 'on_duty', 'busy', 'off_duty'
  current_location GEOGRAPHY(Point, 4326),
  last_gps_ping TIMESTAMPTZ DEFAULT NOW(),
  rating NUMERIC(3,2) DEFAULT 5.00,
  total_completed_jobs INT DEFAULT 0,
  wallet_balance_vnd BIGINT DEFAULT 0,
  is_verified_6k BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tech_location ON public.dp_technicians USING GIST(current_location);
CREATE INDEX IF NOT EXISTS idx_tech_duty ON public.dp_technicians(duty_status, tier);

-- -------------------------------------------------------------------------
-- MODULE 3: ĐƠN CỨU HỘ & HÀNG ĐỢI ĐIỀU PHỐI TỰ ĐỘNG (DISPATCH ENGINE)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dp_dispatch_orders (
  id VARCHAR(30) PRIMARY KEY, -- 'NC-xxxxxx'
  customer_id UUID REFERENCES auth.users(id),
  customer_name VARCHAR(120) NOT NULL,
  customer_phone VARCHAR(20) NOT NULL,
  customer_address TEXT NOT NULL,
  customer_coords GEOGRAPHY(Point, 4326) NOT NULL,
  category_id VARCHAR(30) REFERENCES public.dp_demand_categories(id),
  symptoms_selected TEXT[],
  detailed_notes TEXT,
  urgency_level VARCHAR(30) DEFAULT 'urgent_15m', -- 'urgent_15m', 'today_2h', 'appointment'
  price_k3 BIGINT NOT NULL DEFAULT 500000,
  assigned_technician_id UUID REFERENCES public.dp_technicians(id),
  assigned_at TIMESTAMPTZ,
  countdown_seconds_left INT DEFAULT 180, -- 3 phút đếm ngược xác nhận
  status VARCHAR(30) NOT NULL DEFAULT 'pending_dispatch', -- 'pending_dispatch', 'dispatched', 'in_progress', 'completed_k5', 'cancelled'
  otp_code VARCHAR(6) DEFAULT '6821',
  geostamp_photo_url TEXT,
  escrow_locked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dispatch_status ON public.dp_dispatch_orders(status);
CREATE INDEX IF NOT EXISTS idx_dispatch_coords ON public.dp_dispatch_orders USING GIST(customer_coords);

-- Function PostGIS: Tìm thợ trực ca gần nhất trong bán kính R mét
CREATE OR REPLACE FUNCTION public.fn_find_nearest_workers(
  p_lng DOUBLE PRECISION,
  p_lat DOUBLE PRECISION,
  p_category VARCHAR,
  p_radius_meters INT DEFAULT 10000
)
RETURNS TABLE (
  technician_id UUID,
  full_name VARCHAR,
  phone VARCHAR,
  tier dp_worker_tier,
  rating NUMERIC,
  distance_meters DOUBLE PRECISION,
  distance_km NUMERIC,
  eta_minutes INT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    t.id AS technician_id,
    t.full_name,
    t.phone,
    t.tier,
    t.rating,
    ST_Distance(t.current_location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)) AS distance_meters,
    ROUND((ST_Distance(t.current_location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)) / 1000)::numeric, 1) AS distance_km,
    GREATEST(8, ROUND((ST_Distance(t.current_location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)) / 1000 * 3.2))::INT) AS eta_minutes
  FROM public.dp_technicians t
  WHERE t.duty_status = 'on_duty'
    AND p_category = ANY(t.skills)
    AND ST_DWithin(t.current_location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326), p_radius_meters)
  ORDER BY 
    CASE WHEN t.tier = 'gold_master' THEN 1 WHEN t.tier = 'silver_tech' THEN 2 ELSE 3 END,
    distance_meters ASC
  LIMIT 5;
END;
$$ LANGUAGE plpgsql STABLE;

-- -------------------------------------------------------------------------
-- MODULE 5: TÀI CHÍNH, ĐỐI SOÁT VIETQR & CHỐT CA THỢ (SETTLEMENT)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dp_shift_settlements (
  id VARCHAR(30) PRIMARY KEY, -- 'SHIFT-YYYYMMDD-Wxx'
  technician_id UUID REFERENCES public.dp_technicians(id) ON DELETE CASCADE,
  shift_date DATE DEFAULT CURRENT_DATE,
  total_completed_jobs INT DEFAULT 0,
  gross_revenue_vnd BIGINT DEFAULT 0,
  worker_share_95 BIGINT DEFAULT 0,
  platform_fee_05 BIGINT DEFAULT 0,
  cash_cod_collected BIGINT DEFAULT 0,
  vietqr_bank_collected BIGINT DEFAULT 0,
  net_payout_due_vnd BIGINT DEFAULT 0, -- worker_share_95 - cash_cod_collected
  payout_status VARCHAR(30) DEFAULT 'ready_for_payout', -- 'ready_for_payout', 'settled_vcb'
  bank_reference_id VARCHAR(50),
  settled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- -------------------------------------------------------------------------
-- MODULE 6: ĐÁNH GIÁ XẾP HẠNG & KHIẾU NẠI ESCROW (RATING & DISPUTE LOOP)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dp_technician_reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id VARCHAR(30) REFERENCES public.dp_dispatch_orders(id),
  technician_id UUID REFERENCES public.dp_technicians(id),
  rating_stars INT CHECK (rating_stars BETWEEN 1 AND 5),
  feedback_tags TEXT[],
  customer_comment TEXT,
  qr_warranty_code VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.dp_dispute_cases (
  id VARCHAR(30) PRIMARY KEY, -- 'DISP-xxxxxx'
  order_id VARCHAR(30) REFERENCES public.dp_dispatch_orders(id),
  technician_id UUID REFERENCES public.dp_technicians(id),
  customer_phone VARCHAR(20) NOT NULL,
  dispute_reason VARCHAR(100) NOT NULL,
  description TEXT NOT NULL,
  escrow_locked_until TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 HOURS'),
  resolution_status VARCHAR(30) DEFAULT 'investigating_15m', -- 'refunded_100', 'dismissed', 'resolved'
  assigned_area_master_id UUID,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

-- =========================================================================
-- SEED DỮ LIỆU BAN ĐẦU CHO CÔNG TY THƯƠNG MẠI ĐẤT PHÚ
-- =========================================================================
INSERT INTO public.dp_demand_categories (id, name, subtitle, icon, default_price_k3, warranty_months, sort_order)
VALUES 
  ('dienlanh', 'Điện Lạnh & Điều Hòa', 'Inverter • VRV • Tủ Đông', 'fa-snowflake', 500000, 6, 1),
  ('diennuoc', 'Sự Cố Điện Dân Dụng', 'Chập Cháy • Phao Tự Động', 'fa-bolt-lightning', 350000, 12, 2),
  ('thongnghet', 'Cấp Thoát Nước & Cống', 'Áp Lực Cao • Không Đục Phá', 'fa-faucet-drip', 250000, 3, 3),
  ('xemay', 'Cứu Hộ Xe Máy 78 & Cũ', 'Lưu Động 24/7 • Kiểm Định 18 Mục', 'fa-motorcycle', 200000, 6, 4),
  ('khoacua', 'Khóa Cửa & Nhôm Kính', 'Khóa Vân Tay • Cửa Xệ Kính', 'fa-key', 180000, 6, 5),
  ('maygiat', 'Máy Giặt & Gia Dụng', 'Khử Khuẩn • Bo Mạch Gia Đình', 'fa-soap', 280000, 6, 6),
  ('suanha', 'Chống Thấm & Cải Tạo', 'Ốp Lát Gạch • Sơn Sửa Tiệm', 'fa-trowel-bricks', 300000, 12, 7),
  ('bocxep', 'Bốc Xếp & Vận Chuyển', 'Chuyển Trọ • Dọn Tiệm Khẩn Cấp', 'fa-dolly', 150000, 1, 8)
ON CONFLICT (id) DO NOTHING;

-- Nạp 5 thợ thực chiến Tuy Hòa
INSERT INTO public.dp_technicians (id, full_name, phone, tier, skills, assigned_district, duty_status, current_location, rating, total_completed_jobs)
VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Nguyễn Văn Phú', '0977.334.455', 'gold_master', ARRAY['dienlanh', 'maygiat'], 'P.5, TP. Tuy Hòa', 'on_duty', ST_SetSRID(ST_MakePoint(109.3015, 13.0935), 4326), 5.00, 142),
  ('a0000000-0000-0000-0000-000000000002', 'Trần Minh Khoa', '0935.889.900', 'silver_tech', ARRAY['diennuoc'], 'Phú Hòa / Tuy Hòa', 'on_duty', ST_SetSRID(ST_MakePoint(109.2890, 13.0780), 4326), 4.90, 98),
  ('a0000000-0000-0000-0000-000000000003', 'Lê Hoàng Nam', '0905.112.233', 'silver_tech', ARRAY['xemay'], 'P.7, TP. Tuy Hòa', 'on_duty', ST_SetSRID(ST_MakePoint(109.3170, 13.0980), 4326), 4.90, 86),
  ('a0000000-0000-0000-0000-000000000004', 'Võ Tấn Lực', '0988.990.011', 'gold_master', ARRAY['thongnghet', 'diennuoc', 'bocxep'], 'Đông Hòa / Tuy Hòa', 'on_duty', ST_SetSRID(ST_MakePoint(109.3250, 13.0550), 4326), 5.00, 115),
  ('a0000000-0000-0000-0000-000000000005', 'Đặng Văn Hùng', '0918.442.211', 'silver_tech', ARRAY['khoacua', 'suanha'], 'Bình Kiến, Tuy Hòa', 'on_duty', ST_SetSRID(ST_MakePoint(109.2950, 13.1120), 4326), 4.80, 74)
ON CONFLICT (phone) DO NOTHING;
