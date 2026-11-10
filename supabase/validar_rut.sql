-- Ejecutar después de cuotas.sql, en instalaciones nuevas o existentes.
begin;

create or replace function cuotas_privado.rut_valido(p_rut text) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  v_formato text;
  v_normalizado text;
  v_cuerpo text;
  v_suma integer := 0;
  v_resultado integer;
  v_esperado text;
  i integer;
begin
  if p_rut is null or length(p_rut) > 30 then return false; end if;
  v_formato := regexp_replace(upper(p_rut), '[[:space:]]', '', 'g');
  if v_formato !~ '^([0-9]{1,8}|[0-9]{1,3}[.][0-9]{3}|[0-9]{1,2}[.][0-9]{3}[.][0-9]{3})-?[0-9K]$' then
    return false;
  end if;
  v_normalizado := regexp_replace(v_formato, '[.-]', '', 'g');
  v_cuerpo := left(v_normalizado, length(v_normalizado) - 1);
  if v_cuerpo::integer = 0 then return false; end if;

  for i in 1..length(v_cuerpo) loop
    v_suma := v_suma + substring(reverse(v_cuerpo) from i for 1)::integer * (2 + (i - 1) % 6);
  end loop;
  v_resultado := (11 - (v_suma % 11)) % 11;
  v_esperado := case when v_resultado = 10 then 'K' else v_resultado::text end;
  return right(v_normalizado, 1) = v_esperado;
end;
$$;

create or replace function cuotas_privado.verificar_rut_vecino() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.rut is distinct from old.rut then
    if not cuotas_privado.rut_valido(new.rut) then
      raise exception 'Ingresa un RUT válido con su dígito verificador';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function cuotas_privado.rut_valido(text) from public, anon, authenticated;
revoke all on function cuotas_privado.verificar_rut_vecino() from public, anon, authenticated;
drop trigger if exists vecinos_validar_rut on cuotas_privado.vecinos;
create trigger vecinos_validar_rut before insert or update of rut on cuotas_privado.vecinos
for each row execute function cuotas_privado.verificar_rut_vecino();
commit;
