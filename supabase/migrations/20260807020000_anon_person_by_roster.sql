-- Allow Swift Document Generator (anon key) to autocomplete Swift Contact
-- from SLST employee roster names only.
create policy "anon_select_person_by_roster"
on public.dropdown_roster
for select
to anon
using (roster_type = 'person_by');
