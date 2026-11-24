-- Run this in the Supabase SQL Editor. Only this Auth email can edit the portfolio.

create table if not exists public.portfolio_content (
  id text primary key check (id = 'main'),
  content jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.portfolio_content enable row level security;

grant select on public.portfolio_content to anon, authenticated;
grant insert, update on public.portfolio_content to authenticated;

drop policy if exists "Anyone can read portfolio" on public.portfolio_content;
create policy "Anyone can read portfolio"
  on public.portfolio_content
  for select
  to anon, authenticated
  using (true);

drop policy if exists "Portfolio admin can insert" on public.portfolio_content;
create policy "Portfolio admin can insert"
  on public.portfolio_content
  for insert
  to authenticated
  with check (
    lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com')
  );

drop policy if exists "Portfolio admin can update" on public.portfolio_content;
create policy "Portfolio admin can update"
  on public.portfolio_content
  for update
  to authenticated
  using (lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com'))
  with check (lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com'));

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'portfolio-media',
  'portfolio-media',
  true,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Portfolio admin can read image objects" on storage.objects;
create policy "Portfolio admin can read image objects"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'portfolio-media'
    and lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com')
  );

drop policy if exists "Portfolio admin can upload images" on storage.objects;
create policy "Portfolio admin can upload images"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'portfolio-media'
    and lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com')
  );

drop policy if exists "Portfolio admin can update images" on storage.objects;
create policy "Portfolio admin can update images"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'portfolio-media'
    and lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com')
  )
  with check (
    bucket_id = 'portfolio-media'
    and lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com')
  );

drop policy if exists "Portfolio admin can delete images" on storage.objects;
create policy "Portfolio admin can delete images"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'portfolio-media'
    and lower(auth.jwt() ->> 'email') = lower('abdullakoorimmanil@gmail.com')
  );
