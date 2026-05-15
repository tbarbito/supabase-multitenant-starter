-- =============================================================================
-- 20260514000004 — Tabela memberships (relação N:N user ↔ company)
-- =============================================================================
-- Esta tabela é a CHAVE de toda a segurança multi-tenant. Quase toda RLS
-- consulta esta tabela. Por isso:
--   - Tem índices estratégicos
--   - Tem constraint de "pelo menos 1 owner por empresa" (enforced via trigger)
--   - PRIMARY KEY composto (company_id, user_id) impede duplicação
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.memberships (
    company_id      uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    role            public.app_role NOT NULL DEFAULT 'member',

    -- Audit fields
    invited_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    joined_at       timestamptz NOT NULL DEFAULT now(),

    -- Sem soft delete aqui: quando alguém sai/é removido, apagamos o vínculo.
    -- O histórico fica em audit_log.

    PRIMARY KEY (company_id, user_id)
);

-- Index reverso para a query "todas as empresas deste usuário"
-- (a PK já cobre o lado "todos os membros desta empresa")
CREATE INDEX IF NOT EXISTS memberships_user_id_idx
    ON public.memberships (user_id);

-- Index parcial: encontrar owners rapidamente (para validar "pelo menos 1 owner")
CREATE INDEX IF NOT EXISTS memberships_owners_idx
    ON public.memberships (company_id)
    WHERE role = 'owner';

COMMENT ON TABLE public.memberships IS
    'Relação N:N entre usuários e empresas, carrega o role. Núcleo de toda RLS do sistema.';

COMMENT ON COLUMN public.memberships.role IS
    'Papel do usuário NA empresa. Pode variar entre empresas para o mesmo usuário.';
