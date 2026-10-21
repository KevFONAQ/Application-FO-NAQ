-- Recherche dans le texte des PDF : à exécuter une fois dans Supabase > SQL Editor > Run
alter table public.documents add column if not exists text_pages int, add column if not exists text_chars int;

create table if not exists public.document_pages (
  document_id uuid not null references public.documents(id) on delete cascade,
  page        int  not null,
  content     text not null,
  norm        text not null,
  primary key (document_id, page)
);
alter table public.document_pages enable row level security;

-- Autorisations explicites (nouvelle règle Supabase du 30 octobre)
grant select, insert, update, delete on public.document_pages to authenticated;
grant select, insert, update, delete on public.document_pages to service_role;
revoke all on public.document_pages from anon;

drop policy if exists "pages: lecture selon document" on public.document_pages;
create policy "pages: lecture selon document" on public.document_pages
  for select to authenticated
  using (exists (select 1 from public.documents d where d.id = document_id));

drop policy if exists "pages: écriture admin" on public.document_pages;
create policy "pages: écriture admin" on public.document_pages
  for all to authenticated
  using (public.current_role_app() = 'admin')
  with check (public.current_role_app() = 'admin');

create or replace function public.search_pages(terms text[])
returns table (document_id uuid, page int, snippet text, doc_hits bigint)
language sql stable security invoker set search_path = public as $$
  with t as (
    select array_agg('%' || replace(replace(replace(x, '\', '\\'), '%', '\%'), '_', '\_') || '%') as pats,
           (array_agg(x))[1] as first
    from unnest(terms) as x where length(trim(x)) > 0
  ), m as (
    select dp.document_id, dp.page,
           substring(dp.content from greatest(1, strpos(dp.norm, t.first) - 70) for 220) as snippet,
           count(*) over (partition by dp.document_id) as doc_hits,
           row_number() over (partition by dp.document_id order by dp.page) as rn
    from public.document_pages dp, t
    where t.pats is not null and dp.norm like all (t.pats)
  )
  select m.document_id, m.page, m.snippet, m.doc_hits from m where m.rn <= 3
  order by m.document_id, m.page limit 150;
$$;
revoke execute on function public.search_pages(text[]) from public, anon;
grant execute on function public.search_pages(text[]) to authenticated;
