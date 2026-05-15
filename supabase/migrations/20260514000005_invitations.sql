-- =============================================================================
-- 20260514000005 — Tabela invitations
-- =============================================================================
-- Fluxo de convite:
--   1. Admin/owner cria registro com email + role + token único.
--   2. Edge Function envia email com link contendo o token.
--   3. Destinatário clica, faz login/signup, e a Edge Function aceita o convite
--      criando o membership e marcando como 'accepted'.
--
-- Segurança do token:
--   - 32 bytes (256 bits) de entropia via gen_random_bytes (CSPRNG).
--   - Hexencoded (64 chars) — seguro pra URL sem url-encoding.
--   - Hash do token no DB (não armazenamos o token em claro).
--   - Comparação em tempo constante (via hash) — previne timing attacks.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.invitations (
    id                  uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),

    company_id          uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,

    -- Email do convidado (case-insensitive)
    email               extensions.citext NOT NULL,

    role                public.app_role NOT NULL DEFAULT 'member',

    -- HASH do token (SHA-256). O token em si é gerado e enviado por email,
    -- e NUNCA persistido em claro. Quando o usuário envia o token de volta,
    -- comparamos o hash dele com este campo.
    token_hash          text NOT NULL,

    status              public.invitation_status NOT NULL DEFAULT 'pending',

    -- Quem convidou — para o destinatário ver "Convidado por João Silva"
    invited_by          uuid REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Data de expiração (padrão: 7 dias via app)
    expires_at          timestamptz NOT NULL,

    accepted_at         timestamptz,
    revoked_at          timestamptz,

    created_at          timestamptz NOT NULL DEFAULT now(),

    -- Garantias de integridade:
    -- - status accepted ⇒ accepted_at preenchido
    -- - status revoked ⇒ revoked_at preenchido
    CONSTRAINT invitations_accepted_check
        CHECK ((status = 'accepted' AND accepted_at IS NOT NULL) OR status <> 'accepted'),
    CONSTRAINT invitations_revoked_check
        CHECK ((status = 'revoked' AND revoked_at IS NOT NULL) OR status <> 'revoked'),

    -- Não permite 2 convites pendentes para o mesmo email na mesma empresa.
    -- Permite re-convidar após aceite/revogação/expiração.
    CONSTRAINT invitations_unique_pending_per_email_per_company UNIQUE NULLS NOT DISTINCT (company_id, email, status)
);

-- Index para lookup por token na hora de aceitar
CREATE INDEX IF NOT EXISTS invitations_token_hash_idx
    ON public.invitations (token_hash)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS invitations_company_idx
    ON public.invitations (company_id, status);

CREATE INDEX IF NOT EXISTS invitations_email_idx
    ON public.invitations (email)
    WHERE status = 'pending';

COMMENT ON TABLE public.invitations IS
    'Convites pendentes/processados. Token NUNCA armazenado em claro — apenas o SHA-256 hash.';

COMMENT ON COLUMN public.invitations.token_hash IS
    'SHA-256 do token de 32 bytes. Comparação por hash previne timing attacks e vazamento via dump de DB.';
