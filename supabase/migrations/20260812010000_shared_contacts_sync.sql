-- Swift Document Generator shared contact names (PM / Received By / shipper cert).
-- Owned by Document Generator — NOT the SLST dropdown_roster / person_by table.

CREATE TABLE IF NOT EXISTS public.shared_contacts (
  name_key text PRIMARY KEY,
  name text NOT NULL,
  last_used_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shared_contact_tombstones (
  name_key text PRIMARY KEY,
  deleted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.shared_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_contact_tombstones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_shared_contacts" ON public.shared_contacts;
CREATE POLICY "anon_all_shared_contacts"
  ON public.shared_contacts FOR ALL TO anon
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_shared_contact_tombstones"
  ON public.shared_contact_tombstones;
CREATE POLICY "anon_all_shared_contact_tombstones"
  ON public.shared_contact_tombstones FOR ALL TO anon
  USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.shared_contacts TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.shared_contact_tombstones TO anon;

DROP TRIGGER IF EXISTS shared_contacts_touch_updated ON public.shared_contacts;
CREATE TRIGGER shared_contacts_touch_updated
  BEFORE UPDATE ON public.shared_contacts
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
