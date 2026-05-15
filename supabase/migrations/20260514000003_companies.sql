-- =============================================================================
-- 20260514000003 — Tabela companies (empresas / organizações / workspaces)
-- =============================================================================
-- Esta é a "tenant root". Toda tabela de dados de negócio futura deve ter
-- company_id como FK e RLS baseada em membership.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.companies (
    id              uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),

    -- Nome de exibição
    name            text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 120),

    -- Slug único para URLs amigáveis (ex: empresa-x na URL /empresa-x/dashboard)
    -- Lower-case, sem espaços, [a-z0-9-]
    slug            text NOT NULL UNIQUE
                    CHECK (slug ~ '^[a-z0-9](?:[a-z0-9-]{0,48}[a-z0-9])?$'),

    -- Branding opcional
    logo_url        text,

    -- Plano comercial (free, pro, enterprise...) — exemplo, customizar
    plan            text NOT NULL DEFAULT 'free',

    -- Metadados livres (configs específicas do produto, integrações, etc).
    -- Use jsonb e índices GIN se for buscar dentro.
    metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,

    -- Soft delete
    deleted_at      timestamptz,

    created_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS companies_active_idx
    ON public.companies (id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS companies_created_by_idx
    ON public.companies (created_by);

COMMENT ON TABLE public.companies IS
    'Tenant root. Toda tabela de negócio deve referenciar companies.id e ter RLS baseada em memberships.';

COMMENT ON COLUMN public.companies.slug IS
    'Identificador URL-safe único globalmente. Validação por regex impede caracteres perigosos em rotas.';
