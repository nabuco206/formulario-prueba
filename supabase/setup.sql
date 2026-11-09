-- Para la tabla public.tbl_personas existente: ejecutar en SQL Editor.
-- Revisa las políticas existentes: otras políticas pueden permitir leer o modificar datos.
alter table public.tbl_personas enable row level security;

grant insert (nombre, rut) on public.tbl_personas to anon;

create policy "formulario_insertar_personas" on public.tbl_personas
  for insert to anon
  with check (
    char_length(btrim(nombre)) between 1 and 100
    and char_length(btrim(rut)) between 1 and 30
  );
