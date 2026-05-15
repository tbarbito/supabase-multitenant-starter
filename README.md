# Supabase Multi-tenant Starter

> Template open source para SaaS multi-tenant com autenticação, empresas, papéis (RBAC), convites por email e auditoria — pronto para usar como base de novos projetos.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Supabase](https://img.shields.io/badge/Supabase-%23000000.svg?logo=supabase&logoColor=white)](https://supabase.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-blue.svg)](https://postgresql.org)

---

## O que este template entrega

| Recurso | Status |
|---|---|
| Auth completo (signup/login/recovery, MFA opcional, OAuth) | ✅ |
| Multi-tenant **N:N** (um usuário em várias empresas com papéis diferentes) | ✅ |
| RBAC com 4 níveis: `owner`, `admin`, `member`, `viewer` | ✅ |
| **Row Level Security** em todas as tabelas, com testes pgTAP | ✅ |
| Convites por email com token criptográfico de 1 uso + expiração | ✅ |
| **Audit log append-only** (append-only via RLS, imutável) | ✅ |
| Soft delete em profiles e companies | ✅ |
| **Custom JWT claims** (memberships e empresa ativa no token) | ✅ |
| Proteções: último owner não pode ser removido, admin não auto-promove | ✅ |
| Exemplo funcional Next.js 15 (App Router + SSR) | ✅ |
| CI: lint SQL + testes RLS + geração de types TypeScript | ✅ |

---

## Stack

- **Banco**: PostgreSQL 15 (via Supabase)
- **Auth**: Supabase Auth (GoTrue)
- **Edge Functions**: Deno (TypeScript)
- **Email**: Resend (ou SMTP custom)
- **Frontend exemplo**: Next.js 15 + React 19 + App Router
- **Testes**: pgTAP

---

## Começo rápido (5 minutos)

### Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) (para o Supabase rodar local)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`npm i -g supabase` ou via brew)
- [Node.js 20+](https://nodejs.org/) (para o exemplo Next.js)

### Passos

```bash
# 1. Clone o template
git clone https://github.com/SEU-USUARIO/supabase-multitenant-starter.git meu-projeto
cd meu-projeto

# 2. Sobe o Supabase local (Postgres + Auth + Studio + tudo via Docker)
supabase start

# 3. Aplica as migrations
supabase db reset   # roda migrations + seed.sql

# 4. Roda o exemplo Next.js
cd examples/nextjs
cp .env.example .env.local
# preencha NEXT_PUBLIC_SUPABASE_ANON_KEY com o valor do `supabase status`
npm install
npm run dev
```

Abra `http://localhost:3000`. Use as credenciais de seed:

- **alice@example.com** / `Teste!Senha#2026` (owner de "Acme Corp")
- **bob@example.com** / `Teste!Senha#2026` (admin de "Acme Corp" + owner de "Bob Studio")

---

## Para usar em produção

1. **Crie um projeto novo e limpo** em [supabase.com](https://supabase.com).
2. Conecte o CLI: `supabase link --project-ref SEU-REF`
3. Aplique as migrations: `supabase db push`
4. Deploy da Edge Function: `supabase functions deploy invitations`
5. Configure variáveis: `supabase secrets set RESEND_API_KEY=...`
6. Habilite o **Custom Access Token Hook** no painel:
   `Authentication → Hooks → Custom Access Token → Use a Postgres function → public.custom_access_token_hook`

---

## Estrutura do projeto

```
.
├── supabase/
│   ├── migrations/        # SQL versionado (PostgreSQL puro)
│   ├── functions/         # Edge Functions (Deno + TypeScript)
│   ├── tests/             # Testes pgTAP de RLS
│   ├── seed.sql           # Dados de exemplo p/ dev
│   └── config.toml        # Config local do Supabase CLI
├── examples/
│   └── nextjs/            # App de referência (App Router + SSR)
├── docs/
│   ├── ARCHITECTURE.md    # Decisões de arquitetura e por quê
│   ├── SECURITY.md        # Modelo de ameaças e mitigações
│   └── QUICKSTART.md      # Tutorial passo a passo
├── .github/workflows/     # CI: lint + tests + types
├── .env.example
├── LICENSE                # MIT
└── README.md
```

---

## Documentação

- 📐 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — modelo de dados e decisões
- 🔐 [`docs/SECURITY.md`](docs/SECURITY.md) — modelo de ameaças, RLS, hardening
- 🚀 [`docs/QUICKSTART.md`](docs/QUICKSTART.md) — tutorial completo passo a passo

---

## ⚠️ Avisos críticos de segurança

1. **NUNCA exponha `SUPABASE_SERVICE_ROLE_KEY` no frontend.** Esta chave bypassa toda RLS. Use apenas em Edge Functions, backends Node/Python, ou scripts admin.
2. **Email confirmation está ativada por padrão** — não desligue em produção.
3. **Política de senha**: mínimo 12 caracteres com maiúscula, minúscula, número e símbolo. Configurável em `supabase/config.toml`.
4. **Auth Hook (custom JWT claims) precisa estar habilitado** no painel Supabase em produção, senão `app_metadata.memberships` ficará vazio.
5. **Rate limit**: o Supabase já protege endpoints de auth, mas considere adicionar limites por IP nas suas Edge Functions.

Veja [`docs/SECURITY.md`](docs/SECURITY.md) para o checklist completo.

---

## Contribuindo

PRs são bem-vindos. Antes de abrir:

1. Rode os testes locais: `supabase test db`
2. Garanta que o lint SQL passa: `supabase db lint`
3. Atualize a documentação se mudar comportamento

---

## Licença

MIT — veja [LICENSE](LICENSE).

---

## Créditos

Criado por [Tiago Barbieri (Barbito)](https://github.com/tbarbito) na [BiizHubFlow](https://biizhubflow.com).

Inspirações: Supabase docs, [Supabase Auth Helpers](https://github.com/supabase/auth-helpers), padrões de multi-tenancy de Slack, Linear e Vercel.
