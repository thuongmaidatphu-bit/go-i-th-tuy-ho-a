-- ==============================================================================
-- 06: AI SALES CHATBOT SAAS (HỆ THỐNG CHO THUÊ TRỢ LÝ BÁN HÀNG AI MULTI-TENANT)
-- ==============================================================================

-- 1. Bảng Quản lý Khách Thuê Bot (Tenants / Shops)
CREATE TABLE IF NOT EXISTS public.ai_tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    bot_code TEXT UNIQUE NOT NULL, -- Mã nhúng định danh, vd: 'shop-nam-tien'
    shop_name TEXT NOT NULL,
    bot_name TEXT NOT NULL DEFAULT 'Trợ Lý AI Bán Hàng',
    welcome_message TEXT NOT NULL DEFAULT 'Dạ em chào anh/chị! Em có thể tư vấn sản phẩm nào cho mình hôm nay ạ?',
    theme_color TEXT NOT NULL DEFAULT '#059669',
    bot_persona TEXT NOT NULL DEFAULT 'Thân thiện, nhiệt tình, luôn chủ động gợi ý sản phẩm kèm theo và khéo léo xin số điện thoại khách hàng để lên đơn.',
    plan_tier TEXT NOT NULL DEFAULT 'starter' CHECK (plan_tier IN ('starter', 'growth', 'enterprise')),
    monthly_fee NUMERIC(15, 2) NOT NULL DEFAULT 199000,
    message_quota INT NOT NULL DEFAULT 1000,
    messages_used INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Bảng Kho Tri Thức & Sản Phẩm Riêng Của Từng Shop (RAG Knowledge Base)
CREATE TABLE IF NOT EXISTS public.ai_knowledge_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.ai_tenants(id) ON DELETE CASCADE,
    item_type TEXT NOT NULL DEFAULT 'product' CHECK (item_type IN ('product', 'policy', 'faq')),
    title TEXT NOT NULL,
    price NUMERIC(15, 2) DEFAULT 0,
    promo_note TEXT,
    content TEXT NOT NULL,
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Bảng Khách Hàng Tiềm Năng & Đơn Hàng Do AI Tự Động Thu Thập (Captured Leads)
CREATE TABLE IF NOT EXISTS public.ai_leads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.ai_tenants(id) ON DELETE CASCADE,
    customer_name TEXT DEFAULT 'Khách hàng Web',
    customer_phone TEXT NOT NULL,
    interested_product TEXT,
    order_value NUMERIC(15, 2) DEFAULT 0,
    chat_summary TEXT,
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'closed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. Bảng Lịch Sử Hội Thoại (Chat Logs)
CREATE TABLE IF NOT EXISTS public.ai_chat_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.ai_tenants(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    sender TEXT NOT NULL CHECK (sender IN ('user', 'bot', 'human_agent')),
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes tối ưu truy vấn Multi-tenant
CREATE INDEX IF NOT EXISTS idx_ai_knowledge_tenant ON public.ai_knowledge_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ai_leads_tenant ON public.ai_leads(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ai_chat_logs_session ON public.ai_chat_logs(tenant_id, session_id);

-- Bật RLS
ALTER TABLE public.ai_tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_knowledge_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_chat_logs ENABLE ROW LEVEL SECURITY;

-- Policies cho Widget đọc cấu hình công khai và ghi nhận Lead
DROP POLICY IF EXISTS "Public read active tenant config" ON public.ai_tenants;
CREATE POLICY "Public read active tenant config" ON public.ai_tenants
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Public read tenant knowledge" ON public.ai_knowledge_items;
CREATE POLICY "Public read tenant knowledge" ON public.ai_knowledge_items
    FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS "Public insert leads from chatbox" ON public.ai_leads;
CREATE POLICY "Public insert leads from chatbox" ON public.ai_leads
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Public insert chat logs" ON public.ai_chat_logs;
CREATE POLICY "Public insert chat logs" ON public.ai_chat_logs
    FOR INSERT WITH CHECK (true);

-- 5. Hàm RPC kiểm tra hạn mức gói thuê & tăng bộ đếm tin nhắn
CREATE OR REPLACE FUNCTION public.increment_bot_usage(p_bot_code TEXT)
RETURNS JSONB AS $$
DECLARE
    v_tenant public.ai_tenants%ROWTYPE;
BEGIN
    SELECT * INTO v_tenant FROM public.ai_tenants WHERE bot_code = p_bot_code FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'Không tìm thấy mã Bot');
    END IF;

    IF NOT v_tenant.is_active OR v_tenant.expires_at < NOW() THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'Gói thuê đã hết hạn');
    END IF;

    IF v_tenant.messages_used >= v_tenant.message_quota THEN
        RETURN jsonb_build_object('allowed', false, 'reason', 'Đã hết lượt tin nhắn trong tháng');
    END IF;

    UPDATE public.ai_tenants
    SET messages_used = messages_used + 1, updated_at = NOW()
    WHERE id = v_tenant.id;

    RETURN jsonb_build_object(
        'allowed', true,
        'messages_used', v_tenant.messages_used + 1,
        'message_quota', v_tenant.message_quota
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Dữ liệu mẫu 3 Khách Hàng Đang Thuê Chatbox AI
INSERT INTO public.ai_tenants (id, bot_code, shop_name, bot_name, welcome_message, theme_color, plan_tier, monthly_fee, message_quota, messages_used) VALUES
(
    'a1000000-0000-0000-0000-000000000001',
    'bot-dac-san-phu-yen',
    'Đặc Sản Xứ Nẫu Chị Ba',
    'Út Nẫu AI - Chuyên Đặc Sản Phú Yên',
    'Dạ Út Nẫu chào anh/chị nghen! Anh/chị đang tìm Bò một nắng Krông Pa, Nước mắm Gành Đỏ hay Mực một nắng Sông Cầu để làm quà ạ?',
    '#d97706',
    'growth',
    499000,
    5000,
    1420
),
(
    'a1000000-0000-0000-0000-000000000002',
    'bot-sieu-thi-nam-tien',
    'Hệ Thống 10 Siêu Thị Sữa Tã Năm Tiền',
    'Trợ Lý Mẹ & Bé Năm Tiền',
    'Chào Ba Mẹ! Em là Trợ lý AI của Siêu thị Năm Tiền. Ba mẹ cần tìm sữa công thức, tã bỉm nội địa hay đồ ăn dặm cho bé mấy tháng tuổi ạ?',
    '#0284c7',
    'enterprise',
    1200000,
    20000,
    6850
),
(
    'a1000000-0000-0000-0000-000000000003',
    'bot-bep-chay-tam-duc',
    'Bếp Chay Thanh Tịnh Tâm Đức',
    'Trợ Lý Bếp Chay Tâm Đức',
    'Nam Mô A Di Đà Phật! Bếp Chay Tâm Đức xin kính chào quý khách. Quý gia chủ cần đặt Mâm cỗ giỗ chay tận nhà hay món chay thanh tịnh hằng ngày ạ?',
    '#059669',
    'starter',
    199000,
    1000,
    380
)
ON CONFLICT (bot_code) DO NOTHING;
