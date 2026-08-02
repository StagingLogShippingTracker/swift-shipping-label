-- Saved BOL shipper signatures (PNG in storage) — shared across Swift Document Generator installs.

CREATE TABLE IF NOT EXISTS public.signatures (
  id text PRIMARY KEY,
  name text NOT NULL,
  storage_path text NOT NULL UNIQUE,
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.signatures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_signatures" ON public.signatures;
CREATE POLICY "anon_all_signatures"
  ON public.signatures FOR ALL TO anon
  USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.signatures TO anon;

DROP TRIGGER IF EXISTS signatures_touch_updated ON public.signatures;
CREATE TRIGGER signatures_touch_updated
  BEFORE UPDATE ON public.signatures
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'signatures',
  'signatures',
  true,
  2097152,
  ARRAY['image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "anon_select_signatures_storage" ON storage.objects;
CREATE POLICY "anon_select_signatures_storage"
  ON storage.objects FOR SELECT TO anon
  USING (bucket_id = 'signatures');

DROP POLICY IF EXISTS "anon_insert_signatures_storage" ON storage.objects;
CREATE POLICY "anon_insert_signatures_storage"
  ON storage.objects FOR INSERT TO anon
  WITH CHECK (bucket_id = 'signatures');

DROP POLICY IF EXISTS "anon_update_signatures_storage" ON storage.objects;
CREATE POLICY "anon_update_signatures_storage"
  ON storage.objects FOR UPDATE TO anon
  USING (bucket_id = 'signatures')
  WITH CHECK (bucket_id = 'signatures');

DROP POLICY IF EXISTS "anon_delete_signatures_storage" ON storage.objects;
CREATE POLICY "anon_delete_signatures_storage"
  ON storage.objects FOR DELETE TO anon
  USING (bucket_id = 'signatures');
