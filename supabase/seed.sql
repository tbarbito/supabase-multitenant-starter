-- =============================================================================
-- seed.sql — Dados de exemplo para desenvolvimento local
-- =============================================================================
-- Este script roda automaticamente quando você executa `supabase db reset`.
-- NÃO usar em produção. Cria 2 usuários de teste e 2 empresas.
--
-- Credenciais:
--   alice@example.com    senha: Teste!Senha#2026     → owner de "Acme Corp"
--   bob@example.com      senha: Teste!Senha#2026     → admin de "Acme Corp" + owner de "Bob Studio"
-- =============================================================================

-- IMPORTANTE: criar usuários via auth.users diretamente NÃO dispara o trigger
-- handle_new_user em todos os ambientes (depende da versão do GoTrue).
-- Usamos a função admin do Supabase via SQL para garantir consistência.
-- Como SQL puro não tem acesso a essa função, fazemos via INSERT + chamada
-- manual ao trigger.

DO $$
DECLARE
    _alice_id uuid := '11111111-1111-1111-1111-111111111111'::uuid;
    _bob_id   uuid := '22222222-2222-2222-2222-222222222222'::uuid;
    _acme_id  uuid;
    _bob_co_id uuid;
BEGIN
    -- Alice
    INSERT INTO auth.users (
        instance_id, id, aud, role, email,
        encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        _alice_id,
        'authenticated', 'authenticated',
        'alice@example.com',
        crypt('Teste!Senha#2026', gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Alice Silva","skip_auto_company":true}'::jsonb,
        now(), now(),
        '', '', '', ''
    )
    ON CONFLICT (id) DO NOTHING;

    -- Bob
    INSERT INTO auth.users (
        instance_id, id, aud, role, email,
        encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        _bob_id,
        'authenticated', 'authenticated',
        'bob@example.com',
        crypt('Teste!Senha#2026', gen_salt('bf')),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{"full_name":"Bob Pereira","skip_auto_company":true}'::jsonb,
        now(), now(),
        '', '', '', ''
    )
    ON CONFLICT (id) DO NOTHING;

    -- Profiles (caso o trigger não tenha rodado)
    INSERT INTO public.profiles (id, email, full_name)
    VALUES
        (_alice_id, 'alice@example.com', 'Alice Silva'),
        (_bob_id, 'bob@example.com', 'Bob Pereira')
    ON CONFLICT (id) DO NOTHING;

    -- Empresa Acme Corp (Alice = owner, Bob = admin)
    INSERT INTO public.companies (name, slug, plan, created_by)
    VALUES ('Acme Corp', 'acme-corp', 'pro', _alice_id)
    RETURNING id INTO _acme_id;

    INSERT INTO public.memberships (company_id, user_id, role, invited_by) VALUES
        (_acme_id, _alice_id, 'owner', _alice_id),
        (_acme_id, _bob_id,   'admin', _alice_id)
    ON CONFLICT (company_id, user_id) DO NOTHING;

    -- Empresa Bob Studio (Bob = owner solo)
    INSERT INTO public.companies (name, slug, plan, created_by)
    VALUES ('Bob Studio', 'bob-studio', 'free', _bob_id)
    RETURNING id INTO _bob_co_id;

    INSERT INTO public.memberships (company_id, user_id, role, invited_by) VALUES
        (_bob_co_id, _bob_id, 'owner', _bob_id)
    ON CONFLICT (company_id, user_id) DO NOTHING;

    RAISE NOTICE 'Seed concluído. Acme Corp: %, Bob Studio: %', _acme_id, _bob_co_id;
END $$;
