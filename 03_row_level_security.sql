-- ==============================================================================
-- 03: ROW LEVEL SECURITY (RLS) POLICIES
-- Hệ thống Thương Mại Điện Tử Đất Phú OneBase trên Supabase
-- ==============================================================================

-- Bật RLS trên toàn bộ bảng
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

-- Helper Function: Kiểm tra người dùng có phải Admin không
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 1. Profiles
-- ------------------------------------------------------------------------------
CREATE POLICY "Cho phép xem thông tin hồ sơ cơ bản"
    ON public.profiles FOR SELECT
    USING (true);

CREATE POLICY "Người dùng tự cập nhật hồ sơ của chính mình"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id);

-- ------------------------------------------------------------------------------
-- 2. Categories
-- ------------------------------------------------------------------------------
CREATE POLICY "Công khai danh mục hoạt động"
    ON public.categories FOR SELECT
    USING (is_active = true OR public.is_admin());

CREATE POLICY "Admin quản lý danh mục"
    ON public.categories FOR ALL
    USING (public.is_admin());

-- ------------------------------------------------------------------------------
-- 3. Products
-- ------------------------------------------------------------------------------
CREATE POLICY "Khách hàng xem sản phẩm đã xuất bản"
    ON public.products FOR SELECT
    USING (is_published = true OR auth.uid() = vendor_id OR public.is_admin());

CREATE POLICY "Vendor quản lý sản phẩm của mình"
    ON public.products FOR INSERT
    WITH CHECK (auth.uid() = vendor_id OR public.is_admin());

CREATE POLICY "Vendor cập nhật sản phẩm của mình"
    ON public.products FOR UPDATE
    USING (auth.uid() = vendor_id OR public.is_admin());

CREATE POLICY "Vendor xóa sản phẩm của mình"
    ON public.products FOR DELETE
    USING (auth.uid() = vendor_id OR public.is_admin());

-- ------------------------------------------------------------------------------
-- 4. Product Variants
-- ------------------------------------------------------------------------------
CREATE POLICY "Xem biến thể của sản phẩm hợp lệ"
    ON public.product_variants FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.products p
            WHERE p.id = product_variants.product_id
            AND (p.is_published = true OR p.vendor_id = auth.uid() OR public.is_admin())
        )
    );

CREATE POLICY "Vendor quản lý biến thể"
    ON public.product_variants FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.products p
            WHERE p.id = product_variants.product_id
            AND (p.vendor_id = auth.uid() OR public.is_admin())
        )
    );

-- ------------------------------------------------------------------------------
-- 5. Cart Items (Chỉ chủ giỏ hàng mới có quyền)
-- ------------------------------------------------------------------------------
CREATE POLICY "Người dùng quản lý giỏ hàng của chính mình"
    ON public.cart_items FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ------------------------------------------------------------------------------
-- 6. Orders
-- ------------------------------------------------------------------------------
CREATE POLICY "Khách hàng xem đơn của mình; Vendor xem đơn của gian hàng; Admin xem tất cả"
    ON public.orders FOR SELECT
    USING (
        auth.uid() = user_id 
        OR auth.uid() = vendor_id 
        OR public.is_admin()
    );

CREATE POLICY "Khách hàng tạo đơn hàng cho chính mình"
    ON public.orders FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Vendor/Admin cập nhật trạng thái đơn"
    ON public.orders FOR UPDATE
    USING (auth.uid() = vendor_id OR public.is_admin());

-- ------------------------------------------------------------------------------
-- 7. Order Items
-- ------------------------------------------------------------------------------
CREATE POLICY "Xem chi tiết đơn hàng liên quan"
    ON public.order_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.orders o
            WHERE o.id = order_items.order_id
            AND (o.user_id = auth.uid() OR o.vendor_id = auth.uid() OR public.is_admin())
        )
    );

-- ------------------------------------------------------------------------------
-- 8. Payments
-- ------------------------------------------------------------------------------
CREATE POLICY "Xem giao dịch thanh toán của đơn hàng liên quan"
    ON public.payments FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.orders o
            WHERE o.id = payments.order_id
            AND (o.user_id = auth.uid() OR o.vendor_id = auth.uid() OR public.is_admin())
        )
    );
