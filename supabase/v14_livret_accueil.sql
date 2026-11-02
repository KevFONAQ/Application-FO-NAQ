-- V14 : rubrique « Livret d'accueil », lisible par tous les inscrits (abonnés compris), sans téléchargement
alter table public.documents drop constraint if exists documents_section_check;
alter table public.documents add constraint documents_section_check check (section in ('textes', 'gazette', 'tract', 'cr', 'guide'));

drop policy if exists "documents: lecture selon rôle" on public.documents;
create policy "documents: lecture selon rôle" on public.documents
  for select to authenticated
  using (is_public or section in ('tract', 'gazette', 'guide') or public.current_role_app()::text in ('adherent', 'admin', 'gestionnaire'));

drop policy if exists "storage: lecture selon rôle" on storage.objects;
create policy "storage: lecture selon rôle" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents' and exists (
      select 1 from public.documents d
       where d.storage_path = storage.objects.name
         and (d.is_public or d.section in ('tract', 'gazette', 'guide') or public.current_role_app()::text in ('adherent', 'admin', 'gestionnaire'))
    )
  );
