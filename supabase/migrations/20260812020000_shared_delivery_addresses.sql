-- Shared delivery address book (Shipping + BOL Delivery Address).
-- Document Generator–owned; synced across Windows/Android.

CREATE TABLE IF NOT EXISTS public.shared_delivery_addresses (
  address_key text PRIMARY KEY,
  ship_to_name text NOT NULL DEFAULT '',
  address text NOT NULL,
  carrier text NOT NULL DEFAULT '',
  account_numbers text NOT NULL DEFAULT '',
  last_used_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shared_delivery_address_tombstones (
  address_key text PRIMARY KEY,
  deleted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.shared_delivery_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_delivery_address_tombstones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_shared_delivery_addresses"
  ON public.shared_delivery_addresses;
CREATE POLICY "anon_all_shared_delivery_addresses"
  ON public.shared_delivery_addresses FOR ALL TO anon
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "anon_all_shared_delivery_address_tombstones"
  ON public.shared_delivery_address_tombstones;
CREATE POLICY "anon_all_shared_delivery_address_tombstones"
  ON public.shared_delivery_address_tombstones FOR ALL TO anon
  USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.shared_delivery_addresses TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.shared_delivery_address_tombstones TO anon;

DROP TRIGGER IF EXISTS shared_delivery_addresses_touch_updated
  ON public.shared_delivery_addresses;
CREATE TRIGGER shared_delivery_addresses_touch_updated
  BEFORE UPDATE ON public.shared_delivery_addresses
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
