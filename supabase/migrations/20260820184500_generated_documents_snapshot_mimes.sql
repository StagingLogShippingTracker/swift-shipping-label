-- History snapshots need JSON + PNG beside the PDF. PDF-only MIME made
-- form.json / logo_*.png uploads fail, then prune-on-open deleted every row.

UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'application/pdf',
  'application/json',
  'image/png',
  'image/jpeg'
]
WHERE id = 'generated-documents';
