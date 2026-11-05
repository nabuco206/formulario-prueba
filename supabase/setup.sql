-- Ejecutar una vez en Supabase: SQL Editor → New query → Run
create table public.respuestas (
  id bigint generated always as identity primary key,
  nombre text not null check (char_length(nombre) between 1 and 100),
  edad int not null check (edad between 0 and 120),
  creado_en timestamptz not null default now()
);

alter table public.respuestas enable row level security;

-- El público solo puede insertar; no puede leer, editar ni borrar.
create policy "insertar_publico" on public.respuestas
  for insert to anon with check (true);
