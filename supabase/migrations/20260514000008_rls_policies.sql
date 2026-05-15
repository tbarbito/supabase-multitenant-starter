-- =============================================================================
-- 20260514000008 — Row Level Security (RLS) policies
-- =============================================================================
-- REGRAS FUNDAMENTAIS:
--   1. RLS habilitado em TODAS as tabelas de public.
--   2. Sem policy = ninguém acessa (deny by default). Sempre é preciso criar.
--   3. Policies separadas por COMANDO (SELECT, INSERT, UPDATE, DELETE).
--      Isso evita o erro de uma policy "ALL" permitir mais do que se quer.
--   4. service_role BYPASS RLS — use apenas em backend, nunca no client.
--   5. anon (não autenticado) NÃO acessa nada por padrão.
-- =============================================================================

-- =============================================================================
-- profiles
-- =============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;  -- aplica até pra owners da tabela

-- Limpa policies pré-existentes (idempotência da migration)
DROP POLICY IF EXISTS profiles_select ON public.profiles;
DROP POLICY IF EXISTS profiles_insert ON public.profiles;
DROP POLICY IF EXISTS profiles_update ON public.profiles;

-- SELECT: o usuário vê o próprio perfil + perfis de quem compartilha uma
-- empresa com ele (para listar membros). Soft-deleted excluídos.
CREATE POLICY profiles_select ON public.profiles
    FOR SELECT
    TO authenticated
    USING (
        deleted_at IS NULL
        AND (
            id = public.auth_uid()
            OR EXISTS (
                SELECT 1
                FROM public.memberships m1
                JOIN public.memberships m2 ON m1.company_id = m2.company_id
                WHERE m1.user_id = public.auth_uid()
                  AND m2.user_id = public.profiles.id
            )
        )
    );

-- INSERT: apenas via trigger handle_new_user (que roda como SECURITY DEFINER).
-- Bloqueamos INSERT direto pelo cliente para evitar criação de perfis fantasma.
-- Nenhuma policy = nenhum INSERT permitido (deny by default).

-- UPDATE: usuário só atualiza o PRÓPRIO perfil.
CREATE POLICY profiles_update ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (id = public.auth_uid() AND deleted_at IS NULL)
    WITH CHECK (id = public.auth_uid() AND deleted_at IS NULL);

-- DELETE: nunca direto. Soft delete via UPDATE deleted_at por função específica.
-- Sem policy = bloqueado.

-- =============================================================================
-- companies
-- =============================================================================
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS companies_select ON public.companies;
DROP POLICY IF EXISTS companies_insert ON public.companies;
DROP POLICY IF EXISTS companies_update ON public.companies;
DROP POLICY IF EXISTS companies_delete ON public.companies;

-- SELECT: apenas membros (qualquer role) veem a empresa
CREATE POLICY companies_select ON public.companies
    FOR SELECT
    TO authenticated
    USING (
        deleted_at IS NULL
        AND public.is_member_of(id)
    );

-- INSERT: qualquer usuário autenticado pode criar uma empresa nova.
-- O trigger handle_new_company automaticamente o torna owner.
CREATE POLICY companies_insert ON public.companies
    FOR INSERT
    TO authenticated
    WITH CHECK (
        created_by = public.auth_uid()
    );

-- UPDATE: somente owner e admin podem editar (admin não pode mudar slug — ver trigger)
CREATE POLICY companies_update ON public.companies
    FOR UPDATE
    TO authenticated
    USING (
        deleted_at IS NULL
        AND public.has_role_in(id, 'admin')
    )
    WITH CHECK (
        public.has_role_in(id, 'admin')
    );

-- DELETE: somente owner. Mas usamos soft delete na app, então este DELETE
-- direto é uma proteção extra contra acidentes. Mantém o caminho disponível
-- pra wipe completo se necessário (LGPD - direito ao esquecimento).
CREATE POLICY companies_delete ON public.companies
    FOR DELETE
    TO authenticated
    USING (public.has_role_in(id, 'owner'));

-- =============================================================================
-- memberships
-- =============================================================================
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS memberships_select ON public.memberships;
DROP POLICY IF EXISTS memberships_insert ON public.memberships;
DROP POLICY IF EXISTS memberships_update ON public.memberships;
DROP POLICY IF EXISTS memberships_delete ON public.memberships;

-- SELECT: membro vê todos os outros membros das empresas em que está.
-- Vê também o próprio membership (mesmo que seja a primeira vez listando).
CREATE POLICY memberships_select ON public.memberships
    FOR SELECT
    TO authenticated
    USING (
        user_id = public.auth_uid()
        OR public.is_member_of(company_id)
    );

-- INSERT: dois caminhos legítimos:
--   (a) trigger handle_new_user/handle_new_company (SECURITY DEFINER, bypassa)
--   (b) Edge Function accept_invitation (usa service_role, bypassa)
-- Nenhuma policy = INSERT direto bloqueado para authenticated.

-- UPDATE: admin+ pode mudar o role de membros.
-- WITH CHECK garante que o role novo é válido e que o admin não pode se
-- auto-promover a owner (verificado no trigger guard_membership_change).
CREATE POLICY memberships_update ON public.memberships
    FOR UPDATE
    TO authenticated
    USING (public.has_role_in(company_id, 'admin'))
    WITH CHECK (public.has_role_in(company_id, 'admin'));

-- DELETE: dois cenários:
--   (a) Usuário sai da empresa (deleta o próprio membership)
--   (b) Admin remove um membro
-- O trigger guard_membership_change impede deletar o último owner.
CREATE POLICY memberships_delete ON public.memberships
    FOR DELETE
    TO authenticated
    USING (
        user_id = public.auth_uid()   -- sair da empresa
        OR public.has_role_in(company_id, 'admin')  -- admin removendo membro
    );

-- =============================================================================
-- invitations
-- =============================================================================
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS invitations_select ON public.invitations;
DROP POLICY IF EXISTS invitations_insert ON public.invitations;
DROP POLICY IF EXISTS invitations_update ON public.invitations;
DROP POLICY IF EXISTS invitations_delete ON public.invitations;

-- SELECT: admin+ vê os convites da própria empresa.
-- NOTA: o destinatário NÃO consulta invitations diretamente — ele acessa via
-- Edge Function pública que recebe o token e valida.
CREATE POLICY invitations_select ON public.invitations
    FOR SELECT
    TO authenticated
    USING (public.has_role_in(company_id, 'admin'));

-- INSERT: admin+ cria convites para a própria empresa.
-- Token é gerado e hasheado client-side (Edge Function) com service_role.
CREATE POLICY invitations_insert ON public.invitations
    FOR INSERT
    TO authenticated
    WITH CHECK (
        public.has_role_in(company_id, 'admin')
        AND invited_by = public.auth_uid()
    );

-- UPDATE: admin+ pode revogar (status: pending → revoked).
-- Aceite é feito via Edge Function com service_role.
CREATE POLICY invitations_update ON public.invitations
    FOR UPDATE
    TO authenticated
    USING (public.has_role_in(company_id, 'admin'))
    WITH CHECK (public.has_role_in(company_id, 'admin'));

-- DELETE: não permitido pelo cliente. Convites antigos são limpos por
-- job de manutenção rodando como service_role.

-- =============================================================================
-- audit_log — APPEND-ONLY
-- =============================================================================
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_log_select ON public.audit_log;
DROP POLICY IF EXISTS audit_log_insert ON public.audit_log;

-- SELECT: admin+ vê o log da própria empresa.
CREATE POLICY audit_log_select ON public.audit_log
    FOR SELECT
    TO authenticated
    USING (
        company_id IS NOT NULL
        AND public.has_role_in(company_id, 'admin')
    );

-- INSERT: apenas via função log_audit() (SECURITY DEFINER).
-- Não permitimos INSERT direto do cliente para evitar logs forjados.

-- UPDATE/DELETE: NUNCA. Append-only. Sem policy = bloqueado.
-- Para retenção, criar job que TRUNCA partições antigas (quando particionado),
-- rodando como superuser via cron — fora do RLS.
