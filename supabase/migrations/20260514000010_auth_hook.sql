-- =============================================================================
-- 20260514000010 — Custom Access Token Hook
-- =============================================================================
-- O QUE FAZ:
--   Toda vez que o Supabase Auth emite um JWT (login, refresh), esta função
--   roda e adiciona claims customizadas. Aqui colocamos:
--     - memberships: lista de { company_id, role } do usuário
--     - active_company_id: empresa atualmente "selecionada" (vem do user_metadata)
--
-- POR QUE IMPORTA:
--   Sem isso, toda RLS faria SELECT em memberships para descobrir o role,
--   recursivamente. Com isso, o role já vem no JWT e fica disponível via
--   auth.jwt() -> 'app_metadata' -> 'memberships'.
--
-- COMO O FRONTEND USA:
--   Quando o usuário troca de empresa (clica num seletor), chamamos
--   set_active_company(uuid) que atualiza user_metadata. No próximo refresh
--   do token, o active_company_id estará atualizado.
--
-- REFERÊNCIA:
--   https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook
-- =============================================================================

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    _user_id            uuid;
    _claims             jsonb;
    _memberships        jsonb;
    _active_company_id  uuid;
BEGIN
    _user_id := (event ->> 'user_id')::uuid;
    _claims := event -> 'claims';

    -- Lista de memberships do usuário (formato compacto)
    SELECT COALESCE(
        jsonb_agg(jsonb_build_object(
            'company_id', m.company_id,
            'role', m.role
        )),
        '[]'::jsonb
    )
    INTO _memberships
    FROM public.memberships m
    WHERE m.user_id = _user_id;

    -- Empresa ativa: vem de raw_user_meta_data.active_company_id se válida,
    -- senão pega a primeira empresa do usuário.
    SELECT COALESCE(
        (
            SELECT (u.raw_user_meta_data ->> 'active_company_id')::uuid
            FROM auth.users u
            WHERE u.id = _user_id
              AND (u.raw_user_meta_data ->> 'active_company_id')::uuid IN (
                  SELECT company_id FROM public.memberships WHERE user_id = _user_id
              )
        ),
        (
            SELECT m.company_id
            FROM public.memberships m
            WHERE m.user_id = _user_id
            ORDER BY m.joined_at ASC
            LIMIT 1
        )
    )
    INTO _active_company_id;

    -- Injeta em app_metadata (NÃO em user_metadata!)
    -- app_metadata só é modificável pelo backend/admin = não pode ser
    -- forjado pelo cliente. user_metadata é editável pelo usuário.
    _claims := jsonb_set(
        _claims,
        '{app_metadata}',
        COALESCE(_claims -> 'app_metadata', '{}'::jsonb) ||
        jsonb_build_object(
            'memberships', _memberships,
            'active_company_id', _active_company_id
        )
    );

    event := jsonb_set(event, '{claims}', _claims);
    RETURN event;
EXCEPTION
    WHEN OTHERS THEN
        -- Falha aqui = login quebra. Logamos e retornamos sem claims extras.
        RAISE WARNING 'custom_access_token_hook falhou para %: %', _user_id, SQLERRM;
        RETURN event;
END;
$$;

-- O Auth Hook chama esta função como o role `supabase_auth_admin`
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;

-- Garantir que o auth admin consegue ler memberships (sem isso, falha silente)
GRANT SELECT ON TABLE public.memberships TO supabase_auth_admin;

-- =============================================================================
-- set_active_company — função para o frontend trocar de empresa
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_active_company(_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Valida que o user é membro da empresa
    IF NOT public.is_member_of(_company_id) THEN
        RAISE EXCEPTION 'Usuário não é membro desta empresa.'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Atualiza user_metadata (será refletido no próximo refresh do token)
    UPDATE auth.users
    SET raw_user_meta_data =
        COALESCE(raw_user_meta_data, '{}'::jsonb) ||
        jsonb_build_object('active_company_id', _company_id)
    WHERE id = auth.uid();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_active_company(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_active_company(uuid) TO authenticated;

COMMENT ON FUNCTION public.set_active_company(uuid) IS
    'Troca a empresa ativa do usuário. O cliente deve chamar supabase.auth.refreshSession() em seguida para receber o JWT atualizado.';
