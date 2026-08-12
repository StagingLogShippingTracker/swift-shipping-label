-- Generated PDF history (source of truth across Windows/Android).
-- Local filled/ is a cache only.

CREATE TABLE IF NOT EXISTS public.generated_documents (
  id text PRIMARY KEY,
  kind text NOT NULL,
  title text NOT NULL DEFAULT '',
  customer text NOT NULL DEFAULT '',
  sales_order text NOT NULL DEFAULT '',
  file_name text NOT NULL,
  storage_path text NOT NULL UNIQUE,
  byte_size integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS generated_documents_kind_created_idx
  ON public.generated_documents (kind, created_at DESC);

ALTER TABLE public.generated_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_generated_documents"
  ON public.generated_documents;
CREATE POLICY "anon_all_generated_documents"
  ON public.generated_documents FOR ALL TO anon
  USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.generated_documents TO anon;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'generated-documents',
  'generated-documents',
  true,
  20971520,
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "anon_select_generated_documents_storage"
  ON storage.objects;
CREATE POLICY "anon_select_generated_documents_storage"
  ON storage.objects FOR SELECT TO anon
  USING (bucket_id = 'generated-documents');

DROP POLICY IF EXISTS "anon_insert_generated_documents_storage"
  ON storage.objects;
CREATE POLICY "anon_insert_generated_documents_storage"
  ON storage.objects FOR INSERT TO anon
  WITH CHECK (bucket_id = 'generated-documents');

DROP POLICY IF EXISTS "anon_update_generated_documents_storage"
  ON storage.objects;
CREATE POLICY "anon_update_generated_documents_storage"
  ON storage.objects FOR UPDATE TO anon
  USING (bucket_id = 'generated-documents')
  WITH CHECK (bucket_id = 'generated-documents');

DROP POLICY IF EXISTS "anon_delete_generated_documents_storage"
  ON storage.objects;
CREATE POLICY "anon_delete_generated_documents_storage"
  ON storage.objects FOR DELETE TO anon
  USING (bucket_id = 'generated-documents');
