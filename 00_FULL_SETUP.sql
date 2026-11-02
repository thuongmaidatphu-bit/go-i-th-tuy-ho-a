-- ==============================================================================
-- BỘ CẤU HÌNH ĐẦY ĐỦ (ALL-IN-ONE) CHO SUPABASE E-COMMERCE
-- Dự án: Đất Phú OneBase (Chợ Phiên Tuy Hòa - Phú Yên)
-- Hướng dẫn: Mở Supabase Dashboard -> Chọn SQL Editor -> Tạo New Query -> Dán toàn bộ nội dung file này vào và bấm 'RUN'.
-- ==============================================================================

-- BƯỚC 1: EXTENSIONS & ENUMS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('customer', 'vendor', 'admin', 'shipper');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'shipping', 'completed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payment_status AS ENUM ('unpaid', 'paid', 'refunded');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payment_method AS ENUM ('vietqr', 'cod', 'momo', 'bank_transfer');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- BƯỚC 2: CÁC BẢNG DỮ LIỆU CỐT LÕI
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL DEFAULT '',
    phone TEXT,
    avatar_url TEXT,
    role user_role NOT NULL DEFAULT 'customer',
    address JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    icon_url TEXT,
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vendor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    description TEXT,
    images TEXT[] NOT NULL DEFAULT '{}',
    is_published BOOLEAN NOT NULL DEFAULT FALSE,
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    view_count INT NOT NULL DEFAULT 0,
    rating_avg NUMERIC(2, 1) NOT NULL DEFAULT 5.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    sku TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    price NUMERIC(15, 2) NOT NULL CHECK (price >= 0),
    compare_at_price NUMERIC(15, 2) CHECK (compare_at_price >= price),
    stock_quantity INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cart_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity INT NOT NULL CHECK (quantity > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, variant_id)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_code TEXT UNIQUE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    vendor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    subtotal NUMERIC(15, 2) NOT NULL DEFAULT 0,
    shipping_fee NUMERIC(15, 2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(15, 2) NOT NULL DEFAULT 0,
    status order_status NOT NULL DEFAULT 'pending',
    payment_status payment_status NOT NULL DEFAULT 'unpaid',
    payment_method payment_method NOT NULL DEFAULT 'vietqr',
    shipping_address JSONB NOT NULL,
    customer_note TEXT,
    tracking_number TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    variant_title TEXT NOT NULL,
    price NUMERIC(15, 2) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    total NUMERIC(15, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    payment_method payment_method NOT NULL,
    transaction_code TEXT,
    amount NUMERIC(15, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    provider_response JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_vendor ON public.products(vendor_id);
CREATE INDEX IF NOT EXISTS idx_products_published ON public.products(is_published);
CREATE INDEX IF NOT EXISTS idx_products_search_gin ON public.products USING gin(name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_variants_product ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_cart_user ON public.cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_user ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);

-- BƯỚC 3: BẢO MẬT ROW LEVEL SECURITY (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Profiles Policies
DROP POLICY IF EXISTS "Cho phép xem thông tin hồ sơ cơ bản" ON public.profiles;
CREATE POLICY "Cho phép xem thông tin hồ sơ cơ bản" ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Người dùng tự cập nhật hồ sơ của chính mình" ON public.profiles;
CREATE POLICY "Người dùng tự cập nhật hồ sơ của chính mình" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Categories Policies
DROP POLICY IF EXISTS "Công khai danh mục hoạt động" ON public.categories;
CREATE POLICY "Công khai danh mục hoạt động" ON public.categories FOR SELECT USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS "Admin quản lý danh mục" ON public.categories;
CREATE POLICY "Admin quản lý danh mục" ON public.categories FOR ALL USING (public.is_admin());

-- Products Policies
DROP POLICY IF EXISTS "Khách hàng xem sản phẩm đã xuất bản" ON public.products;
CREATE POLICY "Khách hàng xem sản phẩm đã xuất bản" ON public.products FOR SELECT USING (is_published = true OR auth.uid() = vendor_id OR public.is_admin());

DROP POLICY IF EXISTS "Vendor quản lý sản phẩm của mình" ON public.products;
CREATE POLICY "Vendor quản lý sản phẩm của mình" ON public.products FOR INSERT WITH CHECK (auth.uid() = vendor_id OR public.is_admin());

DROP POLICY IF EXISTS "Vendor cập nhật sản phẩm của mình" ON public.products;
CREATE POLICY "Vendor cập nhật sản phẩm của mình" ON public.products FOR UPDATE USING (auth.uid() = vendor_id OR public.is_admin());

DROP POLICY IF EXISTS "Vendor xóa sản phẩm của mình" ON public.products;
CREATE POLICY "Vendor xóa sản phẩm của mình" ON public.products FOR DELETE USING (auth.uid() = vendor_id OR public.is_admin());

-- Variants Policies
DROP POLICY IF EXISTS "Xem biến thể của sản phẩm hợp lệ" ON public.product_variants;
CREATE POLICY "Xem biến thể của sản phẩm hợp lệ" ON public.product_variants FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_variants.product_id AND (p.is_published = true OR p.vendor_id = auth.uid() OR public.is_admin()))
);

DROP POLICY IF EXISTS "Vendor quản lý biến thể" ON public.product_variants;
CREATE POLICY "Vendor quản lý biến thể" ON public.product_variants FOR ALL USING (
    EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_variants.product_id AND (p.vendor_id = auth.uid() OR public.is_admin()))
);

-- Cart Policies
DROP POLICY IF EXISTS "Người dùng quản lý giỏ hàng của chính mình" ON public.cart_items;
CREATE POLICY "Người dùng quản lý giỏ hàng của chính mình" ON public.cart_items FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Orders Policies
DROP POLICY IF EXISTS "Khách hàng xem đơn của mình; Vendor xem đơn của gian hàng; Admin xem tất cả" ON public.orders;
CREATE POLICY "Khách hàng xem đơn của mình; Vendor xem đơn của gian hàng; Admin xem tất cả" ON public.orders FOR SELECT USING (
    auth.uid() = user_id OR auth.uid() = vendor_id OR public.is_admin()
);

DROP POLICY IF EXISTS "Khách hàng tạo đơn hàng cho chính mình" ON public.orders;
CREATE POLICY "Khách hàng tạo đơn hàng cho chính mình" ON public.orders FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Vendor/Admin cập nhật trạng thái đơn" ON public.orders;
CREATE POLICY "Vendor/Admin cập nhật trạng thái đơn" ON public.orders FOR UPDATE USING (auth.uid() = vendor_id OR public.is_admin());

-- Order Items Policies
DROP POLICY IF EXISTS "Xem chi tiết đơn hàng liên quan" ON public.order_items;
CREATE POLICY "Xem chi tiết đơn hàng liên quan" ON public.order_items FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_items.order_id AND (o.user_id = auth.uid() OR o.vendor_id = auth.uid() OR public.is_admin()))
);

-- Payments Policies
DROP POLICY IF EXISTS "Xem giao dịch thanh toán của đơn hàng liên quan" ON public.payments;
CREATE POLICY "Xem giao dịch thanh toán của đơn hàng liên quan" ON public.payments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = payments.order_id AND (o.user_id = auth.uid() OR o.vendor_id = auth.uid() OR public.is_admin()))
);

-- BƯỚC 4: FUNCTIONS & TRIGGERS
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_profiles_updated_at ON public.profiles;
CREATE TRIGGER tr_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS tr_products_updated_at ON public.products;
CREATE TRIGGER tr_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS tr_variants_updated_at ON public.product_variants;
CREATE TRIGGER tr_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS tr_orders_updated_at ON public.orders;
CREATE TRIGGER tr_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Trigger tự tạo Profile từ auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email, 'Thành viên mới'),
        COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'customer'),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Hàm Đặt Hàng Nguyên Tử (Atomic Place Order)
CREATE OR REPLACE FUNCTION public.place_order(
    p_shipping_address JSONB,
    p_payment_method payment_method DEFAULT 'vietqr',
    p_customer_note TEXT DEFAULT ''
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_order_id UUID;
    v_order_code TEXT;
    v_subtotal NUMERIC(15, 2) := 0;
    v_total NUMERIC(15, 2) := 0;
    v_shipping_fee NUMERIC(15, 2) := 0;
    cart_rec RECORD;
    v_vendor_id UUID := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Bạn cần đăng nhập để đặt hàng.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE user_id = v_user_id) THEN
        RAISE EXCEPTION 'Giỏ hàng của bạn đang trống!';
    END IF;

    v_order_code := 'DP-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');

    INSERT INTO public.orders (order_code, user_id, subtotal, shipping_fee, total_amount, shipping_address, payment_method, customer_note)
    VALUES (v_order_code, v_user_id, 0, v_shipping_fee, 0, p_shipping_address, p_payment_method, p_customer_note)
    RETURNING id INTO v_order_id;

    FOR cart_rec IN
        SELECT c.id AS cart_item_id, c.variant_id, c.quantity, v.title AS variant_title, v.price, v.stock_quantity, p.name AS product_name, p.vendor_id
        FROM public.cart_items c
        JOIN public.product_variants v ON c.variant_id = v.id
        JOIN public.products p ON v.product_id = p.id
        WHERE c.user_id = v_user_id
        FOR UPDATE OF v
    LOOP
        IF cart_rec.stock_quantity < cart_rec.quantity THEN
            RAISE EXCEPTION 'Sản phẩm "% - %" chỉ còn % sản phẩm trong kho!', cart_rec.product_name, cart_rec.variant_title, cart_rec.stock_quantity;
        END IF;

        UPDATE public.product_variants SET stock_quantity = stock_quantity - cart_rec.quantity WHERE id = cart_rec.variant_id;

        IF v_vendor_id IS NULL THEN
            v_vendor_id := cart_rec.vendor_id;
        END IF;

        INSERT INTO public.order_items (order_id, variant_id, product_name, variant_title, price, quantity, total)
        VALUES (v_order_id, cart_rec.variant_id, cart_rec.product_name, cart_rec.variant_title, cart_rec.price, cart_rec.quantity, (cart_rec.price * cart_rec.quantity));

        v_subtotal := v_subtotal + (cart_rec.price * cart_rec.quantity);
    END LOOP;

    v_total := v_subtotal + v_shipping_fee;

    UPDATE public.orders SET vendor_id = v_vendor_id, subtotal = v_subtotal, total_amount = v_total WHERE id = v_order_id;
    DELETE FROM public.cart_items WHERE user_id = v_user_id;

    RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'order_code', v_order_code, 'total_amount', v_total);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- BƯỚC 5: NẠP DỮ LIỆU MẪU ĐẶC SẢN ĐẤT PHÚ
INSERT INTO public.categories (id, name, slug, display_order) VALUES
('c1000000-0000-0000-0000-000000000001', 'Siêu Thị Mẹ & Bé (Sữa Tã)', 'sua-ta-me-va-be', 1),
('c1000000-0000-0000-0000-000000000002', 'Đặc Sản Xứ Nẫu & OCOP', 'dac-san-xu-nau-ocop', 2),
('c1000000-0000-0000-0000-000000000003', 'Bếp Chay Thanh Tịnh', 'bep-chay-thanh-tinh', 3),
('c1000000-0000-0000-0000-000000000004', 'Thiết Bị IT & Camera An Ninh', 'it-camera-an-ninh', 4)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.products (id, category_id, name, slug, description, images, is_published, is_featured, rating_avg) VALUES
('d1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'Bò Một Nắng Krông Pa Chấm Muối Kiến Vàng', 'bo-mot-nang-krong-pa', 'Bò cỏ phơi 1 nắng giòn ngọt kèm muối kiến rừng.', ARRAY['https://images.unsplash.com/photo-1544025162-d76694265947?w=800'], true, true, 5.0),
('d1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000002', 'Nước Mắm Gành Đỏ Truyền Thống 40 Độ Đạm', 'nuoc-mam-ganh-do-truyen-thong', 'Ủ chượp cá cơm than vịnh Xuân Đài thơm ngon tự nhiên.', ARRAY['https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=800'], true, true, 4.9),
('d1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000003', 'Mâm Cỗ Giỗ Chay 8 Món Thanh Tịnh Tâm Đức', 'mam-co-gio-chay-8-mon', 'Mâm cỗ chay thanh tịnh gồm 8 món chay nguyên vị phục vụ tận nơi.', ARRAY['https://images.unsplash.com/photo-1540420773420-3366772f4999?w=800'], true, true, 5.0),
('d1000000-0000-0000-0000-000000000004', 'c1000000-0000-0000-0000-000000000004', 'Camera WiFi Ngoài Trời EZVIZ H8c Xoay 360 Độ', 'camera-ezviz-h8c-360', 'Chống nước, ban đêm có màu, cảnh báo còi hú, hỗ trợ lắp đặt Tuy Hòa.', ARRAY['https://images.unsplash.com/photo-1557597774-9d273605dfa9?w=800'], true, true, 4.8)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.product_variants (product_id, sku, title, price, compare_at_price, stock_quantity, attributes) VALUES
('d1000000-0000-0000-0000-000000000001', 'BOMN-500G', 'Gói hút chân không 500g', 280000, 310000, 50, '{"weight": "500g"}'),
('d1000000-0000-0000-0000-000000000001', 'BOMN-1KG', 'Gói quà tặng 1kg (Tặng kèm 2 hũ muối kiến)', 550000, 600000, 30, '{"weight": "1kg"}'),
('d1000000-0000-0000-0000-000000000002', 'NMGD-CAP-500ML', 'Cặp 2 chai thủy tinh 500ml', 160000, 180000, 100, '{"volume": "1000ml"}'),
('d1000000-0000-0000-0000-000000000003', 'MCCHAY-8MON', 'Set trọn gói 1 mâm (Bàn ghế + Bát đĩa sành)', 850000, 950000, 10, '{"set": "8 món"}'),
('d1000000-0000-0000-0000-000000000004', 'CAM-H8C-NO-CARD', 'Camera kèm công lắp đặt cơ bản', 890000, 990000, 20, '{"storage": "chưa thẻ"}'),
('d1000000-0000-0000-0000-000000000004', 'CAM-H8C-64GB', 'Camera + Thẻ nhớ Sandisk 64GB + Công lắp đặt', 1050000, 1190000, 15, '{"storage": "thẻ 64GB"}')
ON CONFLICT (sku) DO NOTHING;
