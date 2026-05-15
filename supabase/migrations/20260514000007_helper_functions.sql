-- =============================================================================
-- 20260514000007 — Helper functions (SECURITY DEFINER)
-- =============================================================================
-- POR QUE SECURITY DEFINER:
--   As RLS policies precisam consultar memberships. Se a policy de memberships
--   também precisar consultar memberships, vira loop infinito de RLS.
--   A solução: criar funções com SECURITY DEFINER que bypassam RLS para a
--   consulta interna, mas que validam input com cuidado.
--
-- POR QUE `SET search_path = ''`:
--   SECURITY DEFINER sem search_path explícito permite que um atacante crie
--   uma função com mesmo nome em schema temporário e sequestre a execução
--   (CVE-2018-1058 e similares). Setamos search_path vazio e usamos nomes
--   totalmente qualificados (public.tabela, auth.tabela).
--
-- POR QUE STABLE/IMMUTABLE quando possível:
--   Permite que o planner cacheie o resultado dentro de uma query, melhorando
--   muito a performance de RLS que chama helpers repetidamente.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- auth_uid() — wrapper conveniente sobre auth.uid()
-- Retorna o uuid do usuário autenticado (NULL se anônimo)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auth_uid()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT auth.uid()
$$;

REVOKE EXECUTE ON FUNCTION public.auth_uid() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_uid() TO authenticated, anon, service_role;

-- -----------------------------------------------------------------------------
-- is_member_of(company_id) — usuário pertence a esta empresa?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_member_of(_company_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.company_id = _company_id
          AND m.user_id = auth.uid()
    )
$$;

REVOKE EXECUTE ON FUNCTION public.is_member_of(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_member_of(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- has_role_in(company_id, required_role) — usuário tem AO MENOS o role pedido?
-- Hierarquia: owner > admin > member > viewer
-- Ex: has_role_in(x, 'admin') retorna true para owners E admins.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_role_in(_company_id uuid, _required public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.company_id = _company_id
          AND m.user_id = auth.uid()
          AND CASE m.role
                WHEN 'owner'  THEN 4
                WHEN 'admin'  THEN 3
                WHEN 'member' THEN 2
                WHEN 'viewer' THEN 1
              END >=
              CASE _required
                WHEN 'owner'  THEN 4
                WHEN 'admin'  THEN 3
                WHEN 'member' THEN 2
                WHEN 'viewer' THEN 1
              END
    )
$$;

REVOKE EXECUTE ON FUNCTION public.has_role_in(uuid, public.app_role) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_role_in(uuid, public.app_role) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- current_user_role_in(company_id) — retorna o role do usuário, ou NULL.
-- Útil para o frontend descobrir o role sem fazer query separada.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_user_role_in(_company_id uuid)
RETURNS public.app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT m.role
    FROM public.memberships m
    WHERE m.company_id = _company_id
      AND m.user_id = auth.uid()
    LIMIT 1
$$;

REVOKE EXECUTE ON FUNCTION public.current_user_role_in(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_user_role_in(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- count_owners(company_id) — quantos owners a empresa tem?
-- Usada no trigger que impede rebaixar/remover o último owner.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.count_owners(_company_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT count(*)::int
    FROM public.memberships m
    WHERE m.company_id = _company_id
      AND m.role = 'owner'
$$;

REVOKE EXECUTE ON FUNCTION public.count_owners(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.count_owners(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- log_audit(...) — helper para inserir em audit_log com contexto
-- Aceita campos opcionais via NULL. IP/UA vêm de set_config('request.headers')
-- preenchido pelo PostgREST automaticamente.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_audit(
    _action         public.audit_action,
    _company_id     uuid    DEFAULT NULL,
    _target_user_id uuid    DEFAULT NULL,
    _target_table   text    DEFAULT NULL,
    _target_id      text    DEFAULT NULL,
    _metadata       jsonb   DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    _id bigint;
    _ip inet;
    _ua text;
BEGIN
    -- Extrai IP e User-Agent do request (preenchidos pelo PostgREST/Edge Functions).
    -- Se não estiver disponível (ex: chamada de outro trigger), fica NULL.
    BEGIN
        _ip := nullif(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', '')::inet;
    EXCEPTION WHEN OTHERS THEN
        _ip := NULL;
    END;

    BEGIN
        _ua := current_setting('request.headers', true)::jsonb ->> 'user-agent';
    EXCEPTION WHEN OTHERS THEN
        _ua := NULL;
    END;

    INSERT INTO public.audit_log (
        actor_user_id, company_id, action,
        target_user_id, target_table, target_id,
        ip_address, user_agent, metadata
    ) VALUES (
        auth.uid(), _company_id, _action,
        _target_user_id, _target_table, _target_id,
        _ip, _ua, COALESCE(_metadata, '{}'::jsonb)
    )
    RETURNING id INTO _id;

    RETURN _id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.log_audit(public.audit_action, uuid, uuid, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_audit(public.audit_action, uuid, uuid, text, text, jsonb) TO authenticated, service_role;
