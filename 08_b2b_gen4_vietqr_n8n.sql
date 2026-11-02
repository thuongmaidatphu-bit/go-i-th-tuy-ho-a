-- ==============================================================================
-- 08: ĐẤT PHÚ GEN 4 - B2B AI BOT CONFIGS, VIETQR ZERO-FLOAT & N8N SCHEMA
-- Khớp 100% với luồng 6 Node n8n (b2b_merchants, b2b_bot_configs, b2b_ai_orders)
-- ==============================================================================

-- 1. Bảng Chủ Cửa Hàng / Hộ Kinh Doanh Thuê Bot (b2b_merchants)
CREATE TABLE IF NOT EXISTS public.b2b_merchants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    business_name TEXT NOT NULL,
    owner_phone TEXT NOT NULL,
    owner_zalo_id TEXT, -- Để n8n bắn cảnh báo Human Handoff & Báo cáo ROI tối Chủ Nhật
    subscription_plan TEXT NOT NULL DEFAULT 'monthly_199k' CHECK (subscription_plan IN ('monthly_199k', 'yearly_1990k', 'pro_499k')),
    referred_by_agent TEXT, -- Mã Đại lý / Cựu nhân viên ngân hàng giới thiệu (hưởng 30-50% tháng đầu)
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Bảng Cấu Hình Bot 15 Phút & Tài Khoản VietQR Zero-Float (b2b_bot_configs)
CREATE TABLE IF NOT EXISTS public.b2b_bot_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES public.b2b_merchants(id) ON DELETE CASCADE,
    zalo_oa_id TEXT UNIQUE,
    fb_page_id TEXT UNIQUE,
    viber_bot_id TEXT UNIQUE,
    -- 3 Thao tác Onboarding 15 phút của Chủ tiệm:
    bank_code TEXT NOT NULL DEFAULT 'MB', -- Mã BIN/Ngân hàng VietQR (MB, VCB, ICB, BIDV...)
    bank_account_number TEXT NOT NULL,    -- Số tài khoản của chính chủ tiệm (Zero-Float: tiền về thẳng chủ tiệm)
    bank_account_name TEXT NOT NULL,      -- Tên chủ tài khoản
    items_catalog JSONB NOT NULL DEFAULT '[]'::jsonb, -- Danh mục 5-10 món chính + giá chuẩn (Chống chém gió)
    ai_system_prompt TEXT NOT NULL DEFAULT 'Chỉ tư vấn đúng các món trong bảng giá. Nếu khách hỏi món ngoài danh mục, trả lời: "Dạ món này cửa hàng hiện chưa có, em xin báo chủ tiệm hỗ trợ Anh/Chị ngay ạ!"',
    human_handoff_until TIMESTAMPTZ NOT NULL DEFAULT NOW() - INTERVAL '1 minute', -- Tự động tạm dừng 30 phút khi khách gõ "gặp chủ tiệm"
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Bảng Đơn Hàng AI Đã Chốt & Sinh Mã VietQR (b2b_ai_orders)
CREATE TABLE IF NOT EXISTS public.b2b_ai_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    merchant_id UUID NOT NULL REFERENCES public.b2b_merchants(id) ON DELETE CASCADE,
    order_code TEXT NOT NULL DEFAULT ('DP' || LPAD(FLOOR(RANDOM() * 100000)::TEXT, 5, '0')),
    channel_source TEXT NOT NULL DEFAULT 'zalo',
    customer_zalo_id TEXT,
    customer_name TEXT DEFAULT 'Khách hàng',
    customer_phone TEXT NOT NULL,
    customer_address TEXT,
    items_summary TEXT,
    total_amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    vietqr_url TEXT,
    status TEXT NOT NULL DEFAULT 'pending_payment' CHECK (status IN ('pending_payment', 'paid', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. View Báo Cáo ROI Tự Động Tối Chủ Nhật Hàng Tuần (Weekly ROI Report)
CREATE OR REPLACE VIEW public.v_b2b_weekly_roi_report AS
SELECT 
    m.id AS merchant_id,
    m.business_name,
    m.owner_phone,
    m.owner_zalo_id,
    168 AS hours_online,
    COUNT(o.id) AS total_orders_closed,
    COALESCE(SUM(o.total_amount), 0) AS total_vietqr_revenue
FROM public.b2b_merchants m
LEFT JOIN public.b2b_ai_orders o 
    ON o.merchant_id = m.id 
    AND o.created_at >= (NOW() - INTERVAL '7 days')
GROUP BY m.id, m.business_name, m.owner_phone, m.owner_zalo_id;

-- 5. Bật Row Level Security (RLS) Phân Tách Tuyệt Đối Giữa Các Cửa Hàng
ALTER TABLE public.b2b_merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.b2b_bot_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.b2b_ai_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchant chỉ xem dữ liệu của chính mình" ON public.b2b_merchants;
CREATE POLICY "Merchant chỉ xem dữ liệu của chính mình" ON public.b2b_merchants
    FOR ALL USING (owner_user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Merchant quản lý cấu hình bot riêng" ON public.b2b_bot_configs;
CREATE POLICY "Merchant quản lý cấu hình bot riêng" ON public.b2b_bot_configs
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.b2b_merchants m WHERE m.id = b2b_bot_configs.merchant_id AND (m.owner_user_id = auth.uid() OR public.is_admin()))
    );

DROP POLICY IF EXISTS "Merchant chỉ xem đơn hàng của tiệm mình" ON public.b2b_ai_orders;
CREATE POLICY "Merchant chỉ xem đơn hàng của tiệm mình" ON public.b2b_ai_orders
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.b2b_merchants m WHERE m.id = b2b_ai_orders.merchant_id AND (m.owner_user_id = auth.uid() OR public.is_admin()))
    );

-- 6. Dữ liệu mẫu kiểm thử luồng n8n
INSERT INTO public.b2b_merchants (id, business_name, owner_phone, subscription_plan, referred_by_agent) VALUES
('b2b00000-0000-0000-0000-000000000001', 'Đặc Sản Xứ Nẫu Chị Ba', '0914882341', 'monthly_199k', 'AGENT_VCB_TUYHOA_01'),
('b2b00000-0000-0000-0000-000000000002', 'Hệ Thống Sữa Tã Năm Tiền', '0989112567', 'yearly_1990k', 'AGENT_MB_PHUYEN_02')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.b2b_bot_configs (merchant_id, zalo_oa_id, bank_code, bank_account_number, bank_account_name, items_catalog) VALUES
(
    'b2b00000-0000-0000-0000-000000000001',
    'zalo_oa_440199281',
    'MB',
    '0914882341',
    'NGUYEN THI BA',
    '[{"name": "Bò Một Nắng Krông Pa 500g", "price": 280000}, {"name": "Combo Bò Một Nắng 1Kg", "price": 550000}, {"name": "Nước Mắm Gành Đỏ Cặp 2 Chai", "price": 160000}]'::jsonb
)
ON CONFLICT (zalo_oa_id) DO NOTHING;
