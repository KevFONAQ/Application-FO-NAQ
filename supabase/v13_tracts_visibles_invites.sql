-- V13 : les tracts sont visibles par tous les inscrits (invités compris), toujours sans téléchargement
drop policy if exists "documents: lecture selon rôle" on public.documents;
create policy "documents: lecture selon rôle" on public.documents
  for select to authenticated
  using (is_public or section = 'tract' or public.current_role_app()::text in ('adherent', 'admin', 'gestionnaire'));

drop policy if exists "storage: lecture selon rôle" on storage.objects;
create policy "storage: lecture selon rôle" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents' and exists (
      select 1 from public.documents d
       where d.storage_path = storage.objects.name
         and (d.is_public or d.section = 'tract' or public.current_role_app()::text in ('adherent', 'admin', 'gestionnaire'))
    )
  );
