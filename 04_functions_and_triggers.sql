-- ==============================================================================
-- 04: FUNCTIONS & TRIGGERS (BUSINESS LOGIC)
-- Hệ thống Thương Mại Điện Tử Đất Phú OneBase trên Supabase
-- ==============================================================================

-- 1. Trigger tự động cập nhật timestamp updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER tr_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER tr_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER tr_variants_updated_at
    BEFORE UPDATE ON public.product_variants
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE TRIGGER tr_orders_updated_at
    BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2. Tự động khởi tạo Profile khi có User đăng ký qua Supabase Auth
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

-- Gắn trigger vào bảng auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. HÀM TẠO ĐƠN HÀNG NGUYÊN TỬ (Atomic Place Order Transaction)
-- Tự động khóa dòng kiểm tra tồn kho, trừ kho, tạo đơn, tạo line-items và dọn giỏ hàng
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
    v_shipping_fee NUMERIC(15, 2) := 0; -- Có thể tùy chỉnh logic phí ship
    cart_rec RECORD;
    v_vendor_id UUID := NULL;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Bạn cần đăng nhập để đặt hàng.';
    END IF;

    -- Kiểm tra giỏ hàng có rỗng không
    IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE user_id = v_user_id) THEN
        RAISE EXCEPTION 'Giỏ hàng của bạn đang trống!';
    END IF;

    -- Sinh mã đơn hàng chuẩn (VD: DP-261028-XXXX)
    v_order_code := 'DP-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');

    -- Tạo đơn hàng tạm thời
    INSERT INTO public.orders (
        order_code,
        user_id,
        subtotal,
        shipping_fee,
        total_amount,
        shipping_address,
        payment_method,
        customer_note
    )
    VALUES (
        v_order_code,
        v_user_id,
        0,
        v_shipping_fee,
        0,
        p_shipping_address,
        p_payment_method,
        p_customer_note
    )
    RETURNING id INTO v_order_id;

    -- Lặp qua từng item trong giỏ hàng, khóa dòng variant để trừ tồn kho chống race-condition
    FOR cart_rec IN
        SELECT 
            c.id AS cart_item_id,
            c.variant_id,
            c.quantity,
            v.title AS variant_title,
            v.price,
            v.stock_quantity,
            p.name AS product_name,
            p.vendor_id
        FROM public.cart_items c
        JOIN public.product_variants v ON c.variant_id = v.id
        JOIN public.products p ON v.product_id = p.id
        WHERE c.user_id = v_user_id
        FOR UPDATE OF v -- KHÓA DÒNG BIẾN THỂ TRÁNH BÁN QUÁ KHO (Overselling)
    LOOP
        -- Kiểm tra tồn kho
        IF cart_rec.stock_quantity < cart_rec.quantity THEN
            RAISE EXCEPTION 'Sản phẩm "% - %" chỉ còn % sản phẩm trong kho!', 
                cart_rec.product_name, cart_rec.variant_title, cart_rec.stock_quantity;
        END IF;

        -- Trừ tồn kho
        UPDATE public.product_variants
        SET stock_quantity = stock_quantity - cart_rec.quantity
        WHERE id = cart_rec.variant_id;

        -- Ghi nhận Vendor ID đại diện (nếu có)
        IF v_vendor_id IS NULL THEN
            v_vendor_id := cart_rec.vendor_id;
        END IF;

        -- Thêm chi tiết đơn hàng
        INSERT INTO public.order_items (
            order_id,
            variant_id,
            product_name,
            variant_title,
            price,
            quantity,
            total
        )
        VALUES (
            v_order_id,
            cart_rec.variant_id,
            cart_rec.product_name,
            cart_rec.variant_title,
            cart_rec.price,
            cart_rec.quantity,
            (cart_rec.price * cart_rec.quantity)
        );

        v_subtotal := v_subtotal + (cart_rec.price * cart_rec.quantity);
    END LOOP;

    -- Tính toán tổng tiền cuối cùng
    v_total := v_subtotal + v_shipping_fee;

    -- Cập nhật đơn hàng
    UPDATE public.orders
    SET 
        vendor_id = v_vendor_id,
        subtotal = v_subtotal,
        total_amount = v_total
    WHERE id = v_order_id;

    -- Dọn sạch giỏ hàng của user
    DELETE FROM public.cart_items WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_code', v_order_code,
        'total_amount', v_total
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. HÀM HỦY ĐƠN HÀNG & TỰ ĐỘNG HOÀN LẠI TỒN KHO
CREATE OR REPLACE FUNCTION public.cancel_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT 'Khách hàng yêu cầu hủy'
)
RETURNS JSONB AS $$
DECLARE
    v_order public.orders%ROWTYPE;
    item_rec RECORD;
BEGIN
    SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy đơn hàng!';
    END IF;

    -- Chỉ cho phép hủy khi đang ở trạng thái pending hoặc confirmed
    IF v_order.status NOT IN ('pending', 'confirmed') THEN
        RAISE EXCEPTION 'Đơn hàng đang giao hoặc đã hoàn tất, không thể tự động hủy!';
    END IF;

    -- Kiểm tra quyền: Chủ đơn hoặc Admin
    IF v_order.user_id != auth.uid() AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'Bạn không có quyền hủy đơn hàng này!';
    END IF;

    -- Hoàn lại tồn kho cho từng sản phẩm
    FOR item_rec IN SELECT variant_id, quantity FROM public.order_items WHERE order_id = p_order_id LOOP
        IF item_rec.variant_id IS NOT NULL THEN
            UPDATE public.product_variants
            SET stock_quantity = stock_quantity + item_rec.quantity
            WHERE id = item_rec.variant_id;
        END IF;
    END LOOP;

    -- Cập nhật trạng thái đơn
    UPDATE public.orders 
    SET status = 'cancelled', customer_note = COALESCE(customer_note || ' | Lý do hủy: ' || p_reason, p_reason)
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'message', 'Đã hủy đơn hàng và hoàn lại số lượng tồn kho.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
