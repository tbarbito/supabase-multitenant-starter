-- =============================================================================
-- 20260514000006 — Tabela audit_log
-- =============================================================================
-- Princípios:
--   1. APPEND-ONLY: RLS impede UPDATE e DELETE (mesmo para service_role via app).
--   2. Captura ator, ação, alvo, IP/UA e metadata.
--   3. Particionável por created_at quando crescer (ver comentário no final).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.audit_log (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- Quem fez (NULL = sistema, ex: cron de limpeza de convites expirados)
    actor_user_id   uuid REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Em qual tenant
    company_id      uuid REFERENCES public.companies(id) ON DELETE SET NULL,

    -- O quê
    action          public.audit_action NOT NULL,

    -- Alvo (opcional — depende do tipo de ação)
    target_user_id  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    target_table    text,
    target_id       text,

    -- Contexto de rede (preenchido pela aplicação via set_config)
    ip_address      inet,
    user_agent      text,

    -- Diff / payload da ação (ex: { "role": { "from": "member", "to": "admin" } })
    metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Index para "histórico desta empresa"
CREATE INDEX IF NOT EXISTS audit_log_company_created_idx
    ON public.audit_log (company_id, created_at DESC);

-- Index para "tudo que este usuário fez"
CREATE INDEX IF NOT EXISTS audit_log_actor_created_idx
    ON public.audit_log (actor_user_id, created_at DESC);

-- Index para queries por tipo de ação
CREATE INDEX IF NOT EXISTS audit_log_action_idx
    ON public.audit_log (action, created_at DESC);

COMMENT ON TABLE public.audit_log IS
    'Log imutável de ações sensíveis. APPEND-ONLY via RLS (sem UPDATE/DELETE policies).';

-- =============================================================================
-- NOTA SOBRE PARTICIONAMENTO
-- =============================================================================
-- Quando esta tabela passar de ~50M de linhas, considere converter para
-- PARTITION BY RANGE (created_at) com partições mensais. Exemplo:
--
--   ALTER TABLE public.audit_log
--     PARTITION BY RANGE (created_at);
--
-- + criar partições mensais via cron (pg_partman ou script próprio).
-- Por enquanto, mantemos simples — a maioria dos projetos nunca chega lá.
-- =============================================================================
