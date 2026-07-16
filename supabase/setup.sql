-- =============================================
-- Elchai Internal Document Q&A — Supabase Setup
-- Vector store for n8n AI knowledge base pipeline
-- Embedding model: text-embedding-3-small (1536 dims)
-- =============================================

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Create documents table
CREATE TABLE IF NOT EXISTS documents (
  id          bigserial PRIMARY KEY,
  content     text,
  metadata    jsonb,
  embedding   vector(1536)
);

-- 3. Create index for fast cosine similarity search
CREATE INDEX IF NOT EXISTS documents_embedding_idx
  ON documents
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

-- 4. Create the match_documents function (used by n8n vector store node)
CREATE OR REPLACE FUNCTION match_documents (
  query_embedding   vector(1536),
  match_count       int DEFAULT 5,
  filter            jsonb DEFAULT '{}'
)
RETURNS TABLE (
  id         bigint,
  content    text,
  metadata   jsonb,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    documents.id,
    documents.content,
    documents.metadata,
    1 - (documents.embedding <=> query_embedding) AS similarity
  FROM documents
  WHERE documents.metadata @> filter  -- fixed: explicit table prefix to avoid ambiguity
  ORDER BY documents.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- =============================================
-- Optional: clear all documents (reset knowledge base)
-- Run manually only when you want to re-index from scratch
-- TRUNCATE TABLE documents;
-- =============================================
