-- Private Storage bucket for book media (docs/CONTRACTS.md §1, §4): a user may
-- only read/write objects under their own `<auth.uid()>/…` prefix.

insert into storage.buckets (id, name, public)
values ('pop-books', 'pop-books', false)
on conflict (id) do nothing;

create policy "pop_books_select_own"
  on storage.objects for select
  using (
    bucket_id = 'pop-books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "pop_books_insert_own"
  on storage.objects for insert
  with check (
    bucket_id = 'pop-books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "pop_books_update_own"
  on storage.objects for update
  using (
    bucket_id = 'pop-books'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'pop-books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "pop_books_delete_own"
  on storage.objects for delete
  using (
    bucket_id = 'pop-books'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
