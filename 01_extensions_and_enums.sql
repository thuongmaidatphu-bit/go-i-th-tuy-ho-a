-- ==============================================================================
-- 01: EXTENSIONS & ENUMS
-- Hệ thống Thương Mại Điện Tử Đất Phú OneBase trên Supabase
-- ==============================================================================

-- 1. Kích hoạt các Extensions cần thiết
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- 2. Định nghĩa các kiểu ENUM chuẩn hóa
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('customer', 'vendor', 'admin', 'shipper');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'shipping', 'completed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payment_status AS ENUM ('unpaid', 'paid', 'refunded');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE payment_method AS ENUM ('vietqr', 'cod', 'momo', 'bank_transfer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
