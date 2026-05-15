-- =============================================================================
-- 20260514000002 — Tabela profiles
-- =============================================================================
-- Por que NÃO mexer em auth.users:
--   - auth.users é gerenciada pelo GoTrue. Adicionar colunas pode quebrar
--     atualizações futuras do Supabase.
--   - public.profiles é a extensão "segura": 1:1 com auth.users via FK.
--   - Permite que o cliente leia dados públicos do usuário sem precisar de
--     permissão na schema auth.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.profiles (
    -- PK = FK para auth.users. Garante 1:1 e deleta junto se o user for removido.
    id                  uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Dados públicos do perfil
    full_name           text,
    avatar_url          text,
    locale              text NOT NULL DEFAULT 'pt-BR',

    -- Email duplicado aqui (citext) para facilitar buscas/joins sem cruzar schemas.
    -- Mantido em sincronia via trigger em auth.users.
    email               extensions.citext NOT NULL,

    -- Soft delete: NUNCA deletamos perfis de verdade. Garante rastreabilidade
    -- em audit_log e compliance LGPD (direito ao esquecimento via anonimização).
    deleted_at          timestamptz,

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

-- Email não pode duplicar entre perfis ativos. Permite reaproveitar email
-- de um perfil soft-deletado (ex: usuário voltou).
CREATE UNIQUE INDEX IF NOT EXISTS profiles_email_active_uidx
    ON public.profiles (email)
    WHERE deleted_at IS NULL;

-- Index para queries "todos os perfis ativos"
CREATE INDEX IF NOT EXISTS profiles_active_idx
    ON public.profiles (id)
    WHERE deleted_at IS NULL;

COMMENT ON TABLE public.profiles IS
    'Dados públicos do usuário. 1:1 com auth.users. Não conter PII sensível aqui (CPF, telefone, etc) — usar tabela separada com RLS mais estrita.';

COMMENT ON COLUMN public.profiles.deleted_at IS
    'Soft delete. RLS filtra automaticamente registros com deleted_at IS NOT NULL.';
