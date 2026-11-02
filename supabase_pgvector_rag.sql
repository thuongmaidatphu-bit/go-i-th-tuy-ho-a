-- ============================================================================
-- ĐẤT PHÚ ONEBASE (KÍN KẼ OS™) — CẤU HÌNH CƠ SỞ DỮ LIỆU VECTOR RAG (SUPABASE PGVECTOR)
-- Dùng để lưu trữ các đoạn tài liệu chính sách (Chunks) và Vector Embeddings (768d / 64d)
-- ============================================================================

-- 1. Kích hoạt tiện ích mở rộng pgvector trên PostgreSQL / Supabase
create extension if not exists vector;

-- 2. Tạo bảng lưu trữ tài liệu đã chia đoạn (Chunks) & Vector Embedding
create table if not exists public.dp_knowledge_embeddings (
    id uuid primary key default gen_random_uuid(),
    chunk_code text not null,                      -- Mã đoạn: VD CHK-001, CHK-002
    shop_id text not null default 'datphu-kythuat',-- Mã gian hàng sở hữu tài liệu
    doc_title text not null,                       -- Tên tài liệu chính sách gốc
    chunk_index integer not null default 0,        -- Thứ tự đoạn trong tài liệu
    content text not null,                         -- Nội dung văn bản của đoạn (Chunk)
    token_count integer not null default 0,        -- Số lượng từ/token
    embedding_model text not null default 'kinke-semantic-64d',
    embedding vector(768),                         -- Vector 768 chiều (Chuẩn Gemini text-embedding-004)
    embedding_json jsonb,                          -- Lưu dự phòng mảng float JSON cho mọi số chiều (64d / 768d)
    metadata jsonb default '{}'::jsonb,            -- Metadata bổ sung (danh mục, ngày hiệu lực, người tải)
    created_at timestamptz not null default now()
);

-- 3. Tạo chỉ mục HNSW tăng tốc tìm kiếm tương đồng Cosine (Cosine Similarity Search)
create index if not exists idx_dp_knowledge_shop on public.dp_knowledge_embeddings(shop_id);

-- 4. Hàm RPC truy xuất Top-K đoạn chính sách có độ tương đồng Cosine cao nhất
create or replace function public.match_dp_knowledge_chunks(
    query_embedding vector(768),
    match_shop_id text,
    match_threshold float default 0.35,
    match_count int default 3
)
returns table (
    id uuid,
    chunk_code text,
    shop_id text,
    doc_title text,
    content text,
    similarity float
)
language sql stable
as $$
    select
        ke.id,
        ke.chunk_code,
        ke.shop_id,
        ke.doc_title,
        ke.content,
        1 - (ke.embedding <=> query_embedding) as similarity
    from public.dp_knowledge_embeddings ke
    where ke.shop_id = match_shop_id
      and 1 - (ke.embedding <=> query_embedding) > match_threshold
    order by ke.embedding <=> query_embedding
    limit match_count;
$$;
