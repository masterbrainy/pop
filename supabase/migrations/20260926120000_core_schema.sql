-- Pop! core schema (docs/CONTRACTS.md §4): kids, books, pages, reactor_sessions,
-- rate_limits. RLS on every table: a user sees and writes only their own rows.

create table public.kids (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 60),
  reading_level text not null check (reading_level in ('listener', 'early_reader', 'reader')),
  interests jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index kids_user_id_idx on public.kids (user_id);

alter table public.kids enable row level security;

create policy "kids_select_own" on public.kids
  for select using (user_id = auth.uid());
create policy "kids_insert_own" on public.kids
  for insert with check (user_id = auth.uid());
create policy "kids_update_own" on public.kids
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "kids_delete_own" on public.kids
  for delete using (user_id = auth.uid());


create table public.books (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kid_id uuid not null references public.kids(id) on delete cascade,
  brief jsonb not null default '{}'::jsonb,
  bible jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft', 'finished')),
  title text,
  cover_path text,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);

create index books_user_id_idx on public.books (user_id);
create index books_kid_id_idx on public.books (kid_id);

alter table public.books enable row level security;

create policy "books_select_own" on public.books
  for select using (user_id = auth.uid());
create policy "books_insert_own" on public.books
  for insert with check (user_id = auth.uid());
create policy "books_update_own" on public.books
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "books_delete_own" on public.books
  for delete using (user_id = auth.uid());


create table public.pages (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  index int not null check (index >= 0),
  version int not null default 1 check (version >= 1),
  text text not null default '',
  art_prompt text,
  still_path text,
  layers jsonb,
  motion jsonb,
  clip_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (book_id, index, version)
);

create index pages_book_id_idx on public.pages (book_id);

alter table public.pages enable row level security;

-- pages has no user_id of its own; ownership is via the owning book.
create policy "pages_select_own" on public.pages
  for select using (
    exists (select 1 from public.books b where b.id = pages.book_id and b.user_id = auth.uid())
  );
create policy "pages_insert_own" on public.pages
  for insert with check (
    exists (select 1 from public.books b where b.id = pages.book_id and b.user_id = auth.uid())
  );
create policy "pages_update_own" on public.pages
  for update using (
    exists (select 1 from public.books b where b.id = pages.book_id and b.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.books b where b.id = pages.book_id and b.user_id = auth.uid())
  );
create policy "pages_delete_own" on public.pages
  for delete using (
    exists (select 1 from public.books b where b.id = pages.book_id and b.user_id = auth.uid())
  );


create table public.reactor_sessions (
  session_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  opened_at timestamptz not null default now(),
  ended_at timestamptz
);

create index reactor_sessions_user_id_idx on public.reactor_sessions (user_id);
create index reactor_sessions_open_idx on public.reactor_sessions (user_id) where ended_at is null;

alter table public.reactor_sessions enable row level security;

create policy "reactor_sessions_select_own" on public.reactor_sessions
  for select using (user_id = auth.uid());
create policy "reactor_sessions_insert_own" on public.reactor_sessions
  for insert with check (user_id = auth.uid());
create policy "reactor_sessions_update_own" on public.reactor_sessions
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());


create table public.rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  fn text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (user_id, fn, window_start)
);

alter table public.rate_limits enable row level security;

-- Read-only to the owning user; every write goes through hit_rate_limit()
-- below, which runs as security definer and bypasses RLS. No direct
-- insert/update/delete policies are granted to authenticated users.
create policy "rate_limits_select_own" on public.rate_limits
  for select using (user_id = auth.uid());


-- Atomic, per-user, per-function, fixed-window rate limiter. security definer
-- so it can write rate_limits (which authenticated users cannot write
-- directly), and search_path is pinned so it can't be hijacked by a
-- session-local search_path change.
create or replace function public.hit_rate_limit(
  p_fn text,
  p_limit int,
  p_window_seconds int
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_window_start timestamptz;
  v_count int;
begin
  if v_user_id is null then
    raise exception 'hit_rate_limit requires an authenticated user' using errcode = '28000';
  end if;
  if p_window_seconds <= 0 then
    raise exception 'p_window_seconds must be positive' using errcode = '22023';
  end if;

  v_window_start := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limits (user_id, fn, window_start, count)
  values (v_user_id, p_fn, v_window_start, 1)
  on conflict (user_id, fn, window_start)
  do update set count = public.rate_limits.count + 1
  returning count into v_count;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.hit_rate_limit(text, int, int) from public;
revoke all on function public.hit_rate_limit(text, int, int) from anon;
grant execute on function public.hit_rate_limit(text, int, int) to authenticated;
