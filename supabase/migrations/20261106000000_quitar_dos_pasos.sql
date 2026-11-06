-- Héctor pidió quitar la verificación en dos pasos (6-nov-2026): en el iPhone la página
-- se recargaba al cambiar a la app de autenticación y generaba otra clave, y no podía entrar.
-- El panel de plataforma y el acceso de soporte vuelven a pedir solo la sesión normal.
-- Para volver a exigirla: restaurar el cuerpo de 20261024000000 (aal = 'aal2').
create or replace function privado.sesion_mfa() returns boolean
language sql stable set search_path = '' as $$
  select true
$$;
