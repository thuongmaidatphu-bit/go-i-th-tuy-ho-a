-- =========================================================================
-- ĐẤT PHÚ KÍN KẼ OS™ - WORKER ROLE-BASED ACCESS CONTROL (RBAC) & ROW-LEVEL SECURITY (RLS)
-- CÔNG TY TNHH THƯƠNG MẠI ĐẤT PHÚ (MST: 4401020233)
-- Hệ thống phân quyền tổng đài điều phối thợ kỹ thuật 6K & PostGIS 10km
-- =========================================================================

-- 1. KÍCH HOẠT EXTENSIONS CẦN THIẾT
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 2. ĐỊNH NGHĨA ENUMS PHÂN QUYỀN & TRẠNG THÁI
DO $$ BEGIN
  CREATE TYPE dp_user_role AS ENUM (
    'admin_dispatcher',   -- Tổng đài viên / Điều phối viên toàn quyền
    'area_master',        -- Thợ trưởng khu vực (Tuy Hòa, Phú Hòa, Đông Hòa)
    'technician',         -- Thợ kỹ thuật thực chiến 6K
    'customer'            -- Khách hàng sử dụng dịch vụ
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE dp_duty_status AS ENUM (
    'on_duty',            -- Trực ca sẵn sàng (Nhận tín hiệu GPS & n8n dispatch)
    'busy',               -- Đang bận xử lý đơn tận nhà khách
    'off_duty'            -- Hết ca / Tạm nghỉ (Hệ thống loại khỏi vòng quét)
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE dp_order_status AS ENUM (
    'pending_dispatch',   -- Chờ thợ tiếp nhận
    'dispatched',         -- Đã có thợ nhận ca, đang di chuyển
    'arrived_geostamp',   -- Thợ đã tới, chụp ảnh Geostamp K4
    'in_progress',        -- Đang sửa chữa
    'completed_k5',       -- Khách đọc OTP nghiệm thu thành công (Giải ngân 95/5)
    'cancelled'           -- Hủy đơn
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. BẢNG HỒ SƠ THỢ KỸ THUẬT (dp_workers_profile)
CREATE TABLE IF NOT EXISTS public.dp_workers_profile (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name VARCHAR(120) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  role dp_user_role NOT NULL DEFAULT 'technician',
  skills TEXT[] NOT NULL DEFAULT ARRAY['dienlanh'], -- ['dienlanh', 'diennuoc', 'xemay', 'khoacua']
  assigned_zone VARCHAR(50) DEFAULT 'TUY_HOA_ZONE_A',
  duty_status dp_duty_status NOT NULL DEFAULT 'off_duty',
  current_location GEOGRAPHY(Point, 4326), -- Tọa độ GPS thực tế của thợ
  last_location_ping TIMESTAMPTZ DEFAULT NOW(),
  rating NUMERIC(2,1) DEFAULT 5.0,
  completed_jobs INT DEFAULT 0,
  wallet_balance_vnd BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index không gian PostGIS phục vụ quét radar bán kính 10km
CREATE INDEX IF NOT EXISTS idx_workers_location ON public.dp_workers_profile USING GIST(current_location);
CREATE INDEX IF NOT EXISTS idx_workers_duty ON public.dp_workers_profile(duty_status, role);

-- 4. BẢNG ĐƠN ĐIỀU PHỐI DỊCH VỤ CỨU HỘ 6K (dp_orders)
CREATE TABLE IF NOT EXISTS public.dp_orders (
  id VARCHAR(30) PRIMARY KEY, -- Mã NC-xxxxxx hoặc REQ-xxxxxx
  customer_id UUID REFERENCES auth.users(id),
  customer_name VARCHAR(120) NOT NULL,
  customer_phone VARCHAR(20) NOT NULL,
  customer_address TEXT NOT NULL,
  delivery_location GEOGRAPHY(Point, 4326), -- Tọa độ khách hàng
  service_category VARCHAR(50) NOT NULL,
  demand_notes TEXT,
  urgency_level VARCHAR(30) DEFAULT 'urgent_15m',
  price_k3 BIGINT NOT NULL DEFAULT 500000,
  assigned_technician_id UUID REFERENCES public.dp_workers_profile(id),
  assigned_at TIMESTAMPTZ,
  status dp_order_status NOT NULL DEFAULT 'pending_dispatch',
  otp_code VARCHAR(6) DEFAULT '6821', -- Mã OTP 4-6 số K5
  geostamp_photo_url TEXT,
  escrow_settled BOOLEAN DEFAULT FALSE,
  worker_share_95 BIGINT DEFAULT 0,
  platform_share_05 BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_status ON public.dp_orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_technician ON public.dp_orders(assigned_technician_id);
CREATE INDEX IF NOT EXISTS idx_orders_location ON public.dp_orders USING GIST(delivery_location);

-- 5. BẢNG ĐỐI SOÁT CHỐT CA HẰNG NGÀY (dp_worker_shifts)
CREATE TABLE IF NOT EXISTS public.dp_worker_shifts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  worker_id UUID REFERENCES public.dp_workers_profile(id) ON DELETE CASCADE,
  shift_date DATE DEFAULT CURRENT_DATE,
  start_duty_at TIMESTAMPTZ NOT NULL,
  end_duty_at TIMESTAMPTZ,
  total_completed_orders INT DEFAULT 0,
  gross_revenue_vnd BIGINT DEFAULT 0,
  worker_earnings_95 BIGINT DEFAULT 0,
  platform_fee_05 BIGINT DEFAULT 0,
  cash_cod_collected BIGINT DEFAULT 0,
  vietqr_bank_collected BIGINT DEFAULT 0,
  settlement_status VARCHAR(30) DEFAULT 'pending_audit', -- 'audited', 'paid'
  audited_by UUID,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================================================
-- HÀM TIỆN ÍCH LẤY VAI TRÒ & PROFILE ID TỪ auth.uid()
-- =========================================================================
CREATE OR REPLACE FUNCTION public.get_current_worker_profile()
RETURNS public.dp_workers_profile AS $$
  SELECT * FROM public.dp_workers_profile WHERE user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS dp_user_role AS $$
  SELECT role FROM public.dp_workers_profile WHERE user_id = auth.uid() LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- =========================================================================
-- 6. THIẾT LẬP ROW-LEVEL SECURITY (RLS) TRÊN BẢNG dp_orders
-- =========================================================================
ALTER TABLE public.dp_orders ENABLE ROW LEVEL SECURITY;

-- Policy 1: ADMIN DISPATCHER (Toàn quyền xem & cập nhật tất cả đơn)
CREATE POLICY "admin_dispatcher_full_access" ON public.dp_orders
  FOR ALL
  TO authenticated
  USING (
    public.get_current_user_role() = 'admin_dispatcher'
  )
  WITH CHECK (
    public.get_current_user_role() = 'admin_dispatcher'
  );

-- Policy 2: AREA MASTER (Xem & gán đơn trong khu vực phụ trách)
CREATE POLICY "area_master_zone_access" ON public.dp_orders
  FOR SELECT
  TO authenticated
  USING (
    public.get_current_user_role() = 'area_master'
  );

CREATE POLICY "area_master_update_orders" ON public.dp_orders
  FOR UPDATE
  TO authenticated
  USING (
    public.get_current_user_role() = 'area_master'
  )
  WITH CHECK (
    public.get_current_user_role() = 'area_master'
  );

-- Policy 3: TECHNICIAN (Chỉ thấy đơn của chính mình HOẶC đơn chờ nhận trong bán kính 10km khi đang ON_DUTY)
CREATE POLICY "technician_select_assigned_or_nearby" ON public.dp_orders
  FOR SELECT
  TO authenticated
  USING (
    -- Thợ được xem đơn nếu đã được gán trực tiếp cho thợ đó
    assigned_technician_id = (public.get_current_worker_profile()).id
    OR (
      -- HOẶC đơn đang ở trạng thái chờ tiếp nhận, thợ đang trực ca (on_duty)
      status = 'pending_dispatch'
      AND (public.get_current_worker_profile()).duty_status = 'on_duty'
      -- Và đơn nằm trong bán kính 10,000 mét (10km) tính từ GPS thợ
      AND ST_DWithin(
        delivery_location,
        (public.get_current_worker_profile()).current_location,
        10000
      )
    )
  );

-- Policy 4: TECHNICIAN UPDATE (Chỉ cập nhật đơn của chính mình khi nhận việc)
CREATE POLICY "technician_update_assigned_only" ON public.dp_orders
  FOR UPDATE
  TO authenticated
  USING (
    -- Chỉ cập nhật đơn của chính mình hoặc tự nhận đơn pending
    assigned_technician_id = (public.get_current_worker_profile()).id
    OR (status = 'pending_dispatch' AND (public.get_current_worker_profile()).duty_status = 'on_duty')
  )
  WITH CHECK (
    assigned_technician_id = (public.get_current_worker_profile()).id
  );

-- =========================================================================
-- 7. CHÍNH SÁCH BẢO VỆ DỮ LIỆU KHÁCH HÀNG (MASKED CUSTOMER CONTACT VIEW)
-- Nguyên tắc: Chỉ mở số điện thoại & địa chỉ chi tiết khi thợ ĐÃ BẤM NHẬN ĐƠN
-- =========================================================================
CREATE OR REPLACE VIEW public.view_orders_technician_feed AS
SELECT 
  o.id,
  o.service_category,
  o.demand_notes,
  o.urgency_level,
  o.price_k3,
  o.status,
  o.created_at,
  -- PostGIS tính khoảng cách thời gian thực tới thợ (mét)
  ROUND(ST_Distance(o.delivery_location, (public.get_current_worker_profile()).current_location)::numeric, 0) AS distance_meters,
  -- BẢO MẬT THÔNG TIN: Nếu thợ chưa nhận đơn -> Che số điện thoại & địa chỉ
  CASE 
    WHEN o.assigned_technician_id = (public.get_current_worker_profile()).id 
         OR public.get_current_user_role() IN ('admin_dispatcher', 'area_master')
    THEN o.customer_name
    ELSE LEFT(o.customer_name, 2) || '***'
  END AS customer_display_name,
  
  CASE 
    WHEN o.assigned_technician_id = (public.get_current_worker_profile()).id 
         OR public.get_current_user_role() IN ('admin_dispatcher', 'area_master')
    THEN o.customer_phone
    ELSE LEFT(o.customer_phone, 4) || '***' || RIGHT(o.customer_phone, 3)
  END AS customer_display_phone,

  CASE 
    WHEN o.assigned_technician_id = (public.get_current_worker_profile()).id 
         OR public.get_current_user_role() IN ('admin_dispatcher', 'area_master')
    THEN o.customer_address
    ELSE 'Khu vực bán kính ~' || ROUND((ST_Distance(o.delivery_location, (public.get_current_worker_profile()).current_location)/1000)::numeric, 1) || 'km (Tuy Hòa, Phú Yên)'
  END AS customer_display_address
FROM public.dp_orders o;

-- =========================================================================
-- 8. FUNCTION XÁC THỰC MÃ OTP K5 & TỰ ĐỘNG CHIA DOANH THU 95% THỢ / 5% SÀN
-- =========================================================================
CREATE OR REPLACE FUNCTION public.execute_verify_otp_k5(
  p_order_id VARCHAR,
  p_input_otp VARCHAR
)
RETURNS JSONB AS $$
DECLARE
  v_order RECORD;
  v_worker_amount BIGINT;
  v_platform_fee BIGINT;
BEGIN
  -- Lấy thông tin đơn hàng
  SELECT * INTO v_order FROM public.dp_orders WHERE id = p_order_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Không tìm thấy mã đơn hàng');
  END IF;

  -- Kiểm tra mã OTP do khách cung cấp
  IF v_order.otp_code != p_input_otp THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mã OTP nghiệm thu chưa chính xác!');
  END IF;

  -- Tính toán 95% Thợ / 5% Sàn Đất Phú
  v_worker_amount := ROUND(v_order.price_k3 * 0.95);
  v_platform_fee := v_order.price_k3 - v_worker_amount;

  -- Cập nhật đơn hàng
  UPDATE public.dp_orders
  SET 
    status = 'completed_k5',
    escrow_settled = TRUE,
    worker_share_95 = v_worker_amount,
    platform_share_05 = v_platform_fee,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Cộng tiền tức thì vào ví thợ
  UPDATE public.dp_workers_profile
  SET 
    wallet_balance_vnd = wallet_balance_vnd + v_worker_amount,
    completed_jobs = completed_jobs + 1,
    duty_status = 'on_duty' -- Thợ hoàn thành đơn, quay lại trạng thái đón khách
  WHERE id = v_order.assigned_technician_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Nghiệm thu OTP K5 thành công!',
    'order_id', p_order_id,
    'worker_credit_vnd', v_worker_amount,
    'platform_fee_vnd', v_platform_fee,
    'qr_warranty_months', 6
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
