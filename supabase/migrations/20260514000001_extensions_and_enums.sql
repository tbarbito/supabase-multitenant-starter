-- =============================================================================
-- 20260514000001 — Extensões e tipos enumerados
-- =============================================================================
-- Objetivo: instalar extensões necessárias e criar os ENUMs usados por todo o
-- schema. ENUMs são preferíveis a CHECK(IN (...)) porque:
--   - São indexáveis com menor footprint
--   - Mais legíveis em queries
--   - Mantêm consistência entre tabelas
-- =============================================================================

-- pgcrypto: para gen_random_bytes() em tokens de convite e gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- citext: emails case-insensitive sem precisar de LOWER() em toda query
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA extensions;

-- =============================================================================
-- ENUM: app_role
-- =============================================================================
-- Hierarquia (do mais ao menos privilegiado):
--   owner   → pode tudo, incluindo deletar a empresa e transferir ownership.
--             Toda empresa tem PELO MENOS 1 owner (constraint na app).
--   admin   → pode gerenciar membros e configurações, NÃO pode deletar empresa
--             nem rebaixar/promover owners.
--   member  → usuário regular. Lê/escreve dados de negócio da empresa.
--   viewer  → somente leitura. Útil para auditoria, contadores externos, etc.
-- =============================================================================
DO $$ BEGIN
    CREATE TYPE public.app_role AS ENUM ('owner', 'admin', 'member', 'viewer');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- =============================================================================
-- ENUM: invitation_status
-- =============================================================================
DO $$ BEGIN
    CREATE TYPE public.invitation_status AS ENUM (
        'pending',   -- convite enviado, aguardando aceite
        'accepted',  -- convite aceito, membership criado
        'revoked',   -- cancelado pelo remetente antes do aceite
        'expired'    -- passou da data de expiração sem aceite
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- =============================================================================
-- ENUM: audit_action
-- =============================================================================
-- Lista fechada de ações auditadas. Ampliar conforme o produto evolui.
-- =============================================================================
DO $$ BEGIN
    CREATE TYPE public.audit_action AS ENUM (
        'company.created',
        'company.updated',
        'company.deleted',
        'member.invited',
        'member.joined',
        'member.role_changed',
        'member.removed',
        'member.left',
        'invitation.revoked',
        'ownership.transferred'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
