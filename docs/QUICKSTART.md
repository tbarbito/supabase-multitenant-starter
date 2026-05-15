# Quickstart — Passo a passo

Guia completo para colocar o template rodando, do zero ao primeiro deploy em produção.

---

## Parte 1 — Desenvolvimento local

### 1.1 Instalar pré-requisitos

```bash
# Docker (escolha o método pra sua OS)
# Ubuntu:
curl -fsSL https://get.docker.com | sh

# Supabase CLI
npm install -g supabase
# ou via Homebrew: brew install supabase/tap/supabase

# Node.js 20+ (para o exemplo Next.js)
# Use nvm ou o gerenciador de sua preferência
```

### 1.2 Clonar e iniciar

```bash
git clone https://github.com/SEU-USUARIO/supabase-multitenant-starter.git meu-projeto
cd meu-projeto

# Sobe Postgres + Auth + Studio + Storage local via Docker
supabase start
```

Saída esperada:
```
API URL: http://localhost:54321
GraphQL URL: http://localhost:54321/graphql/v1
DB URL: postgresql://postgres:postgres@localhost:54322/postgres
Studio URL: http://localhost:54323
Inbucket URL: http://localhost:54324
anon key: eyJ...
service_role key: eyJ...   ← NUNCA exponha no frontend
```

**Anote a `anon key`** — você vai usar no `.env.local` do Next.js.

### 1.3 Aplicar migrations + seed

```bash
supabase db reset
```

Isso roda todas as migrations em ordem + executa `seed.sql`. Você terá 2 usuários e 2 empresas de teste prontos.

### 1.4 Rodar o exemplo Next.js

```bash
cd examples/nextjs
cp .env.example .env.local
```

Edite `.env.local`:
```bash
NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ... # cole a anon key aqui
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

```bash
npm install
npm run dev
```

Acesse [http://localhost:3000](http://localhost:3000) e faça login com:
- `alice@example.com` / `Teste!Senha#2026`
- `bob@example.com` / `Teste!Senha#2026`

### 1.5 Servir as Edge Functions

Em outro terminal:
```bash
supabase functions serve invitations --env-file .env
```

(Edite `.env` na raiz se quiser configurar Resend para envio real de email.)

### 1.6 Acessar o Studio (Supabase admin local)

[http://localhost:54323](http://localhost:54323) — explore tabelas, queries, logs.

### 1.7 Verificar emails enviados (dev)

[http://localhost:54324](http://localhost:54324) — Inbucket captura emails do Supabase Auth (signup confirmation, recovery).

---

## Parte 2 — Customização

### 2.1 Adicionar uma tabela de negócio (exemplo: `projects`)

Crie uma nova migration:

```bash
supabase migration new add_projects
```

No arquivo gerado:

```sql
CREATE TABLE IF NOT EXISTS public.projects (
    id          uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    company_id  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name        text NOT NULL,
    created_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- SEMPRE habilitar RLS
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects FORCE ROW LEVEL SECURITY;

-- Membros leem
CREATE POLICY projects_select ON public.projects
    FOR SELECT TO authenticated
    USING (public.is_member_of(company_id));

-- Members+ criam
CREATE POLICY projects_insert ON public.projects
    FOR INSERT TO authenticated
    WITH CHECK (
        public.has_role_in(company_id, 'member')
        AND created_by = public.auth_uid()
    );

-- Members+ atualizam
CREATE POLICY projects_update ON public.projects
    FOR UPDATE TO authenticated
    USING (public.has_role_in(company_id, 'member'));

-- Admin+ deleta
CREATE POLICY projects_delete ON public.projects
    FOR DELETE TO authenticated
    USING (public.has_role_in(company_id, 'admin'));
```

Aplique:
```bash
supabase db push   # ou: supabase db reset (apaga e recria + seed)
```

**Padrão a seguir** para qualquer tabela de negócio:
1. Coluna `company_id uuid NOT NULL REFERENCES companies(id)`
2. `ENABLE` + `FORCE ROW LEVEL SECURITY`
3. Policies separadas por comando, usando `is_member_of()` e `has_role_in()`

### 2.2 Adicionar um novo role

Edite a migration `20260514000001_extensions_and_enums.sql` (ou crie uma migration de alteração):

```sql
ALTER TYPE public.app_role ADD VALUE 'guest' BEFORE 'viewer';
```

Atualize `has_role_in()` para incluir o novo valor na hierarquia.

### 2.3 Adicionar OAuth (Google)

1. Crie credenciais OAuth em [console.cloud.google.com](https://console.cloud.google.com)
2. Edite `supabase/config.toml`:
   ```toml
   [auth.external.google]
   enabled = true
   client_id = "..."
   secret = "..."
   ```
3. `supabase stop && supabase start`

---

## Parte 3 — Deploy em produção

### 3.1 Criar projeto Supabase em nuvem

1. Acesse [supabase.com](https://supabase.com) → New Project
2. Anote: **Project Reference** e **DB Password**
3. **NÃO** misture este projeto com outros — use um dedicado pro template

### 3.2 Conectar CLI

```bash
supabase login
supabase link --project-ref SEU-REF
```

### 3.3 Aplicar schema

```bash
supabase db push
```

> ⚠️ Isso **não roda** `seed.sql` (apenas migrations). Seed é só para dev.

### 3.4 Deploy das Edge Functions

```bash
supabase functions deploy invitations
```

Configure secrets (não vão para o repo):
```bash
supabase secrets set RESEND_API_KEY=re_seu_token \
                    INVITATION_FROM_EMAIL=convites@seudominio.com \
                    INVITATION_FROM_NAME="Seu App" \
                    SITE_URL=https://seudominio.com
```

### 3.5 Habilitar Auth Hook no painel

Crítico — sem isso, `app_metadata.memberships` não é populado:

1. Vá em **Authentication → Hooks** (no painel Supabase)
2. **Custom Access Token** → "Use a Postgres function"
3. Selecione `public.custom_access_token_hook`
4. Save

### 3.6 Configurar Site URL e Redirect URLs

Em **Authentication → URL Configuration**:
- Site URL: `https://seudominio.com`
- Redirect URLs: `https://seudominio.com/**`

### 3.7 Habilitar MFA (recomendado)

**Authentication → Providers → MFA** — habilite TOTP.

Para forçar MFA em admins, faça isso na sua app (verifique `aal2` claim antes de operações sensíveis).

### 3.8 Deploy do frontend Next.js

Exemplo com Vercel:
```bash
cd examples/nextjs
vercel
```

Configure as env vars no painel da Vercel:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_SITE_URL`

### 3.9 Checklist final

Veja [`SECURITY.md` § 4](SECURITY.md#4-checklist-de-produção).

---

## Parte 4 — Operação

### Rodar testes RLS

```bash
supabase test db
```

### Gerar types TypeScript

```bash
cd examples/nextjs
npm run types
# gera lib/database.types.ts
```

### Backup manual do banco

```bash
supabase db dump -f backup-$(date +%Y%m%d).sql
```

### Resetar local sem perder dados de prod

```bash
supabase db reset   # APENAS LOCAL — nunca rode em prod
```

---

## Troubleshooting

| Problema | Causa provável | Solução |
|---|---|---|
| `app_metadata.memberships` vazio | Auth Hook não habilitado | Painel → Auth → Hooks → habilite custom_access_token_hook |
| Signup falha sem erro claro | Trigger `handle_new_user` quebrou | Cheque logs do Postgres: `supabase logs db` |
| RLS bloqueia operação que deveria permitir | Policy WITH CHECK inconsistente com USING | Teste com `EXPLAIN` + `SET ROLE authenticated` no Studio |
| Convite "Resend falhou" no log | `RESEND_API_KEY` não configurado | `supabase secrets set RESEND_API_KEY=...` |
| Frontend "Invalid JWT" após algumas horas | Refresh do JWT não está rodando | Confira que `middleware.ts` chama `getUser()` |
| `permission denied for table memberships` no Auth Hook | Falta GRANT para supabase_auth_admin | Aplicada na migration 10, mas confira `\dp memberships` |

---

## Suporte e contribuição

- Issues: [github.com/.../issues](#)
- Discussions: [github.com/.../discussions](#)
- Security: via [GitHub Security Advisory](https://github.com/tbarbito/supabase-multitenant-starter/security/advisories/new)
