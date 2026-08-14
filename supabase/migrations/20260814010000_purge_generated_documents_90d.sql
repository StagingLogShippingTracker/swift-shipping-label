-- Delete generated PDF history (rows + Storage objects) after 90 days.

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION public.purge_generated_documents_older_than(
  retention_days integer DEFAULT 90
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  rec record;
  n integer := 0;
BEGIN
  IF retention_days < 1 THEN
    retention_days := 90;
  END IF;

  FOR rec IN
    SELECT id, storage_path
    FROM public.generated_documents
    WHERE created_at < (now() - make_interval(days => retention_days))
  LOOP
    DELETE FROM storage.objects
    WHERE bucket_id = 'generated-documents'
      AND name = rec.storage_path;
    DELETE FROM public.generated_documents
    WHERE id = rec.id;
    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_generated_documents_older_than(integer)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_generated_documents_older_than(integer)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_generated_documents_older_than(integer)
  TO postgres;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-generated-documents-90d') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'purge-generated-documents-90d';
  END IF;
  PERFORM cron.schedule(
    'purge-generated-documents-90d',
    '15 4 * * *',
    $cron$SELECT public.purge_generated_documents_older_than(90)$cron$
  );
END
$$;
