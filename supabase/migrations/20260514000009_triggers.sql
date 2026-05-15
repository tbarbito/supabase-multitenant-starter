-- =============================================================================
-- 20260514000009 — Triggers
-- =============================================================================
-- Cada trigger tem um propósito específico:
--   1. set_updated_at        → mantém updated_at sincronizado
--   2. handle_new_user       → cria profile + (opcionalmente) primeira empresa
--   3. sync_profile_email    → mantém profiles.email = auth.users.email
--   4. set_company_creator   → owner automático ao criar empresa
--   5. guard_membership_change → impede remover/rebaixar último owner
--   6. audit_membership_changes → loga mudanças de role/saída
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. set_updated_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
CREATE TRIGGER profiles_set_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS companies_set_updated_at ON public.companies;
CREATE TRIGGER companies_set_updated_at
    BEFORE UPDATE ON public.companies
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 2. handle_new_user
-- -----------------------------------------------------------------------------
-- Roda DEPOIS que auth.users insere um novo usuário (signup).
-- Cria public.profiles e — se a flag estiver ativa — cria uma empresa nova
-- com o usuário como owner.
--
-- CRÍTICO: este trigger NÃO PODE FALHAR, ou o signup quebra. Por isso,
-- envolvemos em BEGIN..EXCEPTION e logamos qualquer erro sem propagar.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    _auto_create_company  boolean;
    _new_company_id       uuid;
    _company_name         text;
    _company_slug         text;
BEGIN
    -- Cria profile
    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', split_part(NEW.email, '@', 1)),
        NEW.raw_user_meta_data ->> 'avatar_url'
    )
    ON CONFLICT (id) DO NOTHING;

    -- Decide se cria empresa automaticamente.
    -- Flag pode ser passada via raw_user_meta_data.skip_auto_company = true
    -- (útil quando o signup acontece via aceite de convite).
    _auto_create_company := COALESCE(
        (NEW.raw_user_meta_data ->> 'skip_auto_company')::boolean,
        false
    ) = false;

    IF _auto_create_company THEN
        _company_name := COALESCE(
            NEW.raw_user_meta_data ->> 'company_name',
            'Workspace de ' || split_part(NEW.email, '@', 1)
        );

        -- Slug: lowercase, sem acentos, sem espaços + sufixo random pra evitar colisão
        _company_slug := lower(regexp_replace(
            split_part(NEW.email, '@', 1) || '-' || substring(NEW.id::text from 1 for 6),
            '[^a-z0-9-]', '-', 'g'
        ));

        INSERT INTO public.companies (name, slug, created_by)
        VALUES (_company_name, _company_slug, NEW.id)
        RETURNING id INTO _new_company_id;

        -- Membership como owner (o trigger set_company_creator também faria,
        -- mas explícito aqui pra clareza e para evitar dependência de ordem)
        INSERT INTO public.memberships (company_id, user_id, role, invited_by)
        VALUES (_new_company_id, NEW.id, 'owner', NEW.id)
        ON CONFLICT (company_id, user_id) DO NOTHING;
    END IF;

    RETURN NEW;

EXCEPTION
    WHEN OTHERS THEN
        -- Loga o erro mas NÃO propaga — signup precisa funcionar mesmo se
        -- a criação do profile falhar (operador corrige depois).
        RAISE WARNING 'handle_new_user falhou para %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- -----------------------------------------------------------------------------
-- 3. sync_profile_email
-- -----------------------------------------------------------------------------
-- Quando o email muda em auth.users (mudança de email + confirmação),
-- atualiza também em public.profiles para manter consistência.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_profile_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.email IS DISTINCT FROM OLD.email THEN
        UPDATE public.profiles
        SET email = NEW.email
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'sync_profile_email falhou para %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_email_changed ON auth.users;
CREATE TRIGGER on_auth_user_email_changed
    AFTER UPDATE OF email ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.sync_profile_email();

-- -----------------------------------------------------------------------------
-- 4. set_company_creator
-- -----------------------------------------------------------------------------
-- Quando uma empresa é criada via INSERT direto (não pelo handle_new_user),
-- garante que o criador é owner.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_company_creator()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.created_by IS NOT NULL THEN
        INSERT INTO public.memberships (company_id, user_id, role, invited_by)
        VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by)
        ON CONFLICT (company_id, user_id) DO NOTHING;

        PERFORM public.log_audit(
            'company.created'::public.audit_action,
            NEW.id, NULL, 'companies', NEW.id::text,
            jsonb_build_object('name', NEW.name, 'slug', NEW.slug)
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS companies_set_creator ON public.companies;
CREATE TRIGGER companies_set_creator
    AFTER INSERT ON public.companies
    FOR EACH ROW EXECUTE FUNCTION public.set_company_creator();

-- -----------------------------------------------------------------------------
-- 5. guard_membership_change — proteções críticas
-- -----------------------------------------------------------------------------
-- a) Impede que o ÚLTIMO owner seja removido ou rebaixado
-- b) Impede que admin se auto-promova a owner (só owner promove a owner)
-- c) Impede que owner rebaixe a si mesmo se for o único owner
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_membership_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    _caller_role public.app_role;
    _owners_count int;
BEGIN
    _caller_role := public.current_user_role_in(COALESCE(NEW.company_id, OLD.company_id));

    -- Caso DELETE ou UPDATE que tira role de 'owner'
    IF (TG_OP = 'DELETE' AND OLD.role = 'owner')
       OR (TG_OP = 'UPDATE' AND OLD.role = 'owner' AND NEW.role <> 'owner') THEN

        SELECT public.count_owners(OLD.company_id) INTO _owners_count;
        IF _owners_count <= 1 THEN
            RAISE EXCEPTION 'Não é possível remover/rebaixar o último owner da empresa. Transfira o ownership antes.'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- Promoção a owner: somente owner pode fazer
    IF TG_OP = 'UPDATE' AND OLD.role <> 'owner' AND NEW.role = 'owner' THEN
        IF _caller_role <> 'owner' THEN
            RAISE EXCEPTION 'Apenas owners podem promover outros usuários a owner.'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
    END IF;

    -- INSERT direto de owner: só permitido se o caller já for owner OU se for o
    -- bootstrap (caller é o próprio user sendo inserido — handle_new_user)
    IF TG_OP = 'INSERT' AND NEW.role = 'owner' THEN
        IF NEW.user_id <> public.auth_uid() AND _caller_role <> 'owner' THEN
            -- Se não há auth.uid() (chamada via service_role/trigger), permite.
            IF public.auth_uid() IS NOT NULL THEN
                RAISE EXCEPTION 'Apenas owners podem adicionar outros owners.'
                    USING ERRCODE = 'insufficient_privilege';
            END IF;
        END IF;
    END IF;

    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS memberships_guard ON public.memberships;
CREATE TRIGGER memberships_guard
    BEFORE INSERT OR UPDATE OR DELETE ON public.memberships
    FOR EACH ROW EXECUTE FUNCTION public.guard_membership_change();

-- -----------------------------------------------------------------------------
-- 6. audit_membership_changes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_membership_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.log_audit(
            'member.joined'::public.audit_action,
            NEW.company_id, NEW.user_id, 'memberships',
            NEW.company_id::text || ':' || NEW.user_id::text,
            jsonb_build_object('role', NEW.role)
        );
    ELSIF TG_OP = 'UPDATE' AND OLD.role IS DISTINCT FROM NEW.role THEN
        PERFORM public.log_audit(
            'member.role_changed'::public.audit_action,
            NEW.company_id, NEW.user_id, 'memberships',
            NEW.company_id::text || ':' || NEW.user_id::text,
            jsonb_build_object('from', OLD.role, 'to', NEW.role)
        );
    ELSIF TG_OP = 'DELETE' THEN
        -- Se o user removeu a si mesmo = member.left, senão = member.removed
        IF OLD.user_id = public.auth_uid() THEN
            PERFORM public.log_audit(
                'member.left'::public.audit_action,
                OLD.company_id, OLD.user_id, 'memberships',
                OLD.company_id::text || ':' || OLD.user_id::text,
                jsonb_build_object('role', OLD.role)
            );
        ELSE
            PERFORM public.log_audit(
                'member.removed'::public.audit_action,
                OLD.company_id, OLD.user_id, 'memberships',
                OLD.company_id::text || ':' || OLD.user_id::text,
                jsonb_build_object('role', OLD.role)
            );
        END IF;
    END IF;
    RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS memberships_audit ON public.memberships;
CREATE TRIGGER memberships_audit
    AFTER INSERT OR UPDATE OR DELETE ON public.memberships
    FOR EACH ROW EXECUTE FUNCTION public.audit_membership_changes();
