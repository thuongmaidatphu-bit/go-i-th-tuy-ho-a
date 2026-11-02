-- ==============================================================================
-- 07: OMNI-CHANNEL MESSAGING (ZALO OA, FACEBOOK MESSENGER, VIBER BOT)
-- Hệ thống Nhận & Trả lời Tin nhắn Đa kênh Tự động bằng AI
-- ==============================================================================

-- 1. Định nghĩa nguồn kênh tin nhắn
DO $$ BEGIN
    CREATE TYPE messaging_channel AS ENUM ('website', 'zalo', 'facebook', 'viber');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Bảng Cấu hình Kết nối Kênh của từng Shop thuê (Tenant Channel Connections)
CREATE TABLE IF NOT EXISTS public.ai_channel_connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES public.ai_tenants(id) ON DELETE CASCADE,
    channel messaging_channel NOT NULL,
    channel_name TEXT NOT NULL, -- VD: 'Fanpage Đặc Sản Chị Ba', 'Zalo OA Siêu Thị Năm Tiền'
    external_page_id TEXT NOT NULL, -- Facebook Page ID, Zalo OA ID, hoặc Viber Bot URI
    access_token TEXT, -- Page Access Token / Zalo OA Token / Viber Auth Token
    verify_token TEXT DEFAULT encode(gen_random_bytes(12), 'hex'),
    ai_auto_reply BOOLEAN NOT NULL DEFAULT TRUE, -- Cho phép bật/tắt AI để nhân viên nhảy vào chat
    is_connected BOOLEAN NOT NULL DEFAULT TRUE,
    last_webhook_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, channel, external_page_id)
);

-- 3. Bổ sung cột nguồn kênh (channel_source) vào bảng Leads và Chat Logs
ALTER TABLE public.ai_leads 
    ADD COLUMN IF NOT EXISTS channel_source messaging_channel NOT NULL DEFAULT 'website',
    ADD COLUMN IF NOT EXISTS external_sender_id TEXT;

ALTER TABLE public.ai_chat_logs 
    ADD COLUMN IF NOT EXISTS channel_source messaging_channel NOT NULL DEFAULT 'website',
    ADD COLUMN IF NOT EXISTS external_sender_id TEXT,
    ADD COLUMN IF NOT EXISTS sender_name TEXT DEFAULT 'Khách hàng';

-- Index tra cứu nhanh khi Webhook từ Zalo/Facebook/Viber bắn về
CREATE INDEX IF NOT EXISTS idx_channel_lookup ON public.ai_channel_connections(channel, external_page_id);

-- Bật RLS
ALTER TABLE public.ai_channel_connections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public view active channel connections" ON public.ai_channel_connections;
CREATE POLICY "Public view active channel connections" ON public.ai_channel_connections
    FOR SELECT USING (is_connected = true);

-- 4. Dữ liệu kết nối mẫu cho 3 Shop thuê
INSERT INTO public.ai_channel_connections (tenant_id, channel, channel_name, external_page_id, ai_auto_reply, is_connected) VALUES
('a1000000-0000-0000-0000-000000000001', 'zalo', 'Zalo OA Đặc Sản Xứ Nẫu Chị Ba', 'zalo_oa_440199281', true, true),
('a1000000-0000-0000-0000-000000000001', 'facebook', 'Fanpage Bò Một Nắng Chị Ba Phú Yên', 'fb_page_109283746', true, true),
('a1000000-0000-0000-0000-000000000001', 'viber', 'Viber Chị Ba Wholesale', 'viber_bot_chiba', true, true),
('a1000000-0000-0000-0000-000000000002', 'zalo', 'Zalo OA Siêu Thị Mẹ & Bé Năm Tiền', 'zalo_oa_998877665', true, true),
('a1000000-0000-0000-0000-000000000002', 'facebook', 'Fanpage Hệ Thống Sữa Tã Năm Tiền', 'fb_page_554433221', true, true)
ON CONFLICT DO NOTHING;
