-- =============================================================================
-- Testes pgTAP — validação das RLS policies
-- =============================================================================
-- Roda com: supabase test db
-- Cobre os cenários críticos de segurança que NÃO podem regredir.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path TO extensions, public, auth;

-- =============================================================================
-- Setup: cria 3 usuários e 1 empresa (alice=owner, bob=member, eve=fora)
-- =============================================================================
SELECT plan(15);

INSERT INTO auth.users (id, email, instance_id, aud, role, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, confirmation_token, email_change, email_change_token_new, recovery_token, created_at, updated_at)
VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'alice@test.com', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '', now(), '{}'::jsonb, '{"skip_auto_company":true}'::jsonb, '', '', '', '', now(), now()),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'bob@test.com',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '', now(), '{}'::jsonb, '{"skip_auto_company":true}'::jsonb, '', '', '', '', now(), now()),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'eve@test.com',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '', now(), '{}'::jsonb, '{"skip_auto_company":true}'::jsonb, '', '', '', '', now(), now())
ON CONFLICT DO NOTHING;

INSERT INTO public.companies (id, name, slug, created_by) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Test Co', 'test-co', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
ON CONFLICT DO NOTHING;

-- O trigger set_company_creator já adicionou alice como owner.
-- Bob entra como member (via service_role bypassando policy de INSERT).
INSERT INTO public.memberships (company_id, user_id, role) VALUES
    ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'member')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- Helpers: alternar entre contextos authenticated/superuser
-- =============================================================================
CREATE OR REPLACE FUNCTION test_as_user(_uid uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', _uid, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION test_reset() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('role', 'postgres', true);
END $$;

-- =============================================================================
-- Test 1: owner vê a própria empresa
-- =============================================================================
SELECT test_as_user('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT ok(
    EXISTS(SELECT 1 FROM public.companies WHERE id = '11111111-1111-1111-1111-111111111111'),
    'owner consegue ler própria empresa'
);

-- =============================================================================
-- Test 2: não-membro NÃO vê a empresa
-- =============================================================================
SELECT test_as_user('cccccccc-cccc-cccc-cccc-cccccccccccc');

SELECT ok(
    NOT EXISTS(SELECT 1 FROM public.companies WHERE id = '11111111-1111-1111-1111-111111111111'),
    'não-membro NÃO consegue ler empresa alheia'
);

-- =============================================================================
-- Test 3: anônimo não vê nada
-- =============================================================================
SELECT test_reset();
SELECT set_config('role', 'anon', true);

SELECT ok(
    NOT EXISTS(SELECT 1 FROM public.companies),
    'anônimo não vê nenhuma empresa'
);

-- =============================================================================
-- Test 4: member não consegue UPDATE em company (RLS bloqueia silenciosamente)
-- =============================================================================
-- RLS UPDATE que não bate na USING NÃO joga erro — apenas afeta 0 linhas.
-- Validamos comparando o nome antes e depois.
SELECT test_as_user('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

UPDATE public.companies SET name = 'Hacked' WHERE id = '11111111-1111-1111-1111-111111111111';

SELECT test_reset();  -- volta a superuser para conseguir ler o nome real

SELECT is(
    (SELECT name FROM public.companies WHERE id = '11111111-1111-1111-1111-111111111111'),
    'Test Co',
    'member NÃO consegue alterar nome da empresa (RLS bloqueia silenciosamente)'
);

-- =============================================================================
-- Test 5: owner pode atualizar empresa
-- =============================================================================
SELECT test_as_user('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

UPDATE public.companies SET name = 'Test Co (renomeada)'
WHERE id = '11111111-1111-1111-1111-111111111111';

SELECT test_reset();

SELECT is(
    (SELECT name FROM public.companies WHERE id = '11111111-1111-1111-1111-111111111111'),
    'Test Co (renomeada)',
    'owner consegue atualizar empresa'
);

-- =============================================================================
-- Test 6: não permite remover o último owner
-- =============================================================================
-- Removemos Bob (como superuser) para deixar só Alice como owner.
DELETE FROM public.memberships
WHERE company_id = '11111111-1111-1111-1111-111111111111'
  AND user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

-- Tentativa de remover Alice — trigger guard_membership_change deve bloquear.
-- SQLSTATE 23514 = check_violation
SELECT test_as_user('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT throws_ok(
    $$DELETE FROM public.memberships WHERE company_id = '11111111-1111-1111-1111-111111111111' AND user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
    '23514',
    NULL,
    'remoção do último owner é bloqueada'
);

-- =============================================================================
-- Test 7: não permite rebaixar o último owner
-- =============================================================================
SELECT throws_ok(
    $$UPDATE public.memberships SET role = 'member' WHERE company_id = '11111111-1111-1111-1111-111111111111' AND user_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
    '23514',
    NULL,
    'rebaixar último owner é bloqueado'
);

-- =============================================================================
-- Test 8: has_role_in retorna corretamente para hierarquia
-- =============================================================================
SELECT test_as_user('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

SELECT ok(public.has_role_in('11111111-1111-1111-1111-111111111111', 'viewer'::public.app_role),
    'owner tem role >= viewer');
SELECT ok(public.has_role_in('11111111-1111-1111-1111-111111111111', 'admin'::public.app_role),
    'owner tem role >= admin');
SELECT ok(public.has_role_in('11111111-1111-1111-1111-111111111111', 'owner'::public.app_role),
    'owner tem role >= owner');

-- Re-adiciona Bob (como superuser, bypassando ausência de policy INSERT)
SELECT test_reset();
INSERT INTO public.memberships (company_id, user_id, role) VALUES
    ('11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'member')
ON CONFLICT DO NOTHING;

SELECT test_as_user('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

SELECT ok(public.has_role_in('11111111-1111-1111-1111-111111111111', 'viewer'::public.app_role),
    'member tem role >= viewer');
SELECT ok(NOT public.has_role_in('11111111-1111-1111-1111-111111111111', 'admin'::public.app_role),
    'member NÃO tem role >= admin');

-- =============================================================================
-- Test 9: audit_log é INSERT-only pelo cliente (deve dar 42501 = insufficient_privilege)
-- =============================================================================
SELECT throws_ok(
    $$INSERT INTO public.audit_log (action, company_id) VALUES ('company.created', '11111111-1111-1111-1111-111111111111')$$,
    '42501',
    NULL,
    'INSERT direto em audit_log é bloqueado (deve usar log_audit())'
);

-- =============================================================================
-- Test 10/11: profile só pode ser atualizado pelo dono
-- =============================================================================
UPDATE public.profiles SET full_name = 'Bob (próprio)' WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

SELECT test_reset();

SELECT is(
    (SELECT full_name FROM public.profiles WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
    'Bob (próprio)',
    'usuário atualiza próprio perfil'
);

SELECT test_as_user('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
UPDATE public.profiles SET full_name = 'Hacked' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

SELECT test_reset();
SELECT isnt(
    (SELECT full_name FROM public.profiles WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
    'Hacked',
    'usuário não consegue alterar perfil alheio'
);

-- =============================================================================
SELECT * FROM finish();
ROLLBACK;
