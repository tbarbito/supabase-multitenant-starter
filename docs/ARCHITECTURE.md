# Arquitetura

Este documento explica **as decisões** por trás do template. Para uso prático, veja [`QUICKSTART.md`](QUICKSTART.md).

---

## 1. Modelo de dados

```
┌─────────────────┐
│  auth.users     │ (gerenciada pelo Supabase Auth — não modificamos)
└────────┬────────┘
         │ 1:1
┌────────▼────────┐
│  profiles       │ Dados públicos do usuário
└────────┬────────┘
         │ N:N (via memberships)
┌────────▼────────┐         ┌─────────────────┐
│  memberships    │◄────────┤   companies     │ Tenant root
│  (role)         │         └────────┬────────┘
└─────────────────┘                  │
                                     │ 1:N
                            ┌────────▼────────┐
                            │  invitations    │
                            │  audit_log      │
                            └─────────────────┘
```

### Por que N:N (memberships)?

A escolha mais importante do template. Alternativas:

| Modelo | Prós | Contras |
|---|---|---|
| 1:1 (`profile.company_id`) | Simples | Usuário só em 1 empresa — limitação séria |
| Empresa como dono do user | Modelo "empresa-first" | Não permite migração entre empresas |
| **N:N via memberships** | Flexível, padrão Slack/Notion/Linear | +1 tabela, RLS um pouco mais complexa |

**Escolhemos N:N** porque:
- Um consultor que atende várias empresas precisa de logins separados se for 1:1 → ruim.
- Quando você decide migrar de 1:1 para N:N depois, é refactor caro (migration de dados + reescrita de policies).
- Slack, Notion, Linear, Vercel — todos usam N:N. É o padrão de mercado.

### Por que `profiles` separada de `auth.users`?

- `auth.users` é gerenciada pelo Supabase Auth (GoTrue). Adicionar colunas pode quebrar com atualizações futuras.
- `profiles` permite RLS-controlled access aos dados públicos sem dar permissões em `auth.users`.
- Trigger `handle_new_user` mantém as duas em sincronia.

### Por que ENUMs em vez de tabela `roles`?

- Lista pequena e estável (4 valores).
- ENUMs são indexáveis e mais performáticos que JOIN com tabela.
- Trade-off: adicionar novo role exige migration. Mas isso é uma decisão estratégica, não corriqueira.

---

## 2. Custom JWT Claims (Auth Hook)

### O problema

Toda RLS policy precisa do role do usuário na empresa. Sem otimização:

```sql
-- Cada query faz 1 lookup adicional em memberships
CREATE POLICY ... USING (
    EXISTS (SELECT 1 FROM memberships
            WHERE user_id = auth.uid() AND company_id = ...)
);
```

Para uma query que toca 5 tabelas, isso é 5 lookups extras — mesmo com cache do planner.

### A solução

`custom_access_token_hook` injeta os memberships no JWT em **um único momento** (login/refresh). RLS lê do JWT em vez do banco:

```sql
-- Hipotético: ler direto do JWT
SELECT (auth.jwt() -> 'app_metadata' -> 'memberships') ...
```

Na prática, mantemos as policies usando helper functions (`has_role_in()`) para legibilidade, mas elas têm `STABLE` que permite o planner cachear o resultado dentro da query.

### Por que `app_metadata` e não `user_metadata`?

| Campo | Quem edita | Uso |
|---|---|---|
| `user_metadata` | Cliente (qualquer authenticated user) | Preferências do usuário |
| `app_metadata` | Apenas backend / service_role | Autorização, roles, flags |

Usar `user_metadata` para roles = vulnerabilidade crítica (usuário se promove a admin via SDK).

---

## 3. Sistema de convites

### Fluxo

```
1. Admin → POST /invitations
           { company_id, email, role }

2. Edge Function:
   - Gera token (32 bytes via Web Crypto)
   - Calcula hash SHA-256
   - Insere em invitations (apenas hash no DB)
   - Envia email com URL contendo o token em claro

3. Destinatário → clica no link → /invite/<token>

4. Frontend (se não autenticado): redireciona para login/signup

5. Frontend (autenticado) → POST /invitations/accept
                            { token }

6. Edge Function:
   - Recalcula hash do token recebido
   - Busca invitation por token_hash (sem revelar se existe)
   - Valida: status=pending, não expirado, email confere
   - Cria membership + marca como accepted
```

### Por que armazenar apenas hash?

- **Dump do banco não vaza tokens válidos.** Mesmo que um atacante exporte a tabela `invitations`, ele tem hashes inutilizáveis.
- **Comparação por hash é tempo-constante.** Postgres `=` em strings de mesmo tamanho não tem timing leak relevante (e a SHA-256 vai pro mesmo tamanho).

### Por que `gen_random_bytes(32)` (256 bits)?

- 256 bits de entropia = computacionalmente inviável de adivinhar (mesmo com bilhões de tentativas/s).
- Hex-encoded (64 chars) — URL-safe sem precisar URL-encoding.
- Padrão usado por Github, Gitlab, Vercel para tokens de convite/API.

---

## 4. Audit log append-only

### Por que append-only?

Auditoria adulterada perde valor jurídico/forense. Garantimos:
- **Sem policy de UPDATE** → ninguém edita registros.
- **Sem policy de DELETE** → ninguém apaga.
- Mesmo service_role rodando código da app não consegue (a não ser que use `BYPASS RLS` explícito).

### Retenção

Para tabelas pequenas (~1M linhas), não é problema. Para crescer:

```sql
ALTER TABLE public.audit_log PARTITION BY RANGE (created_at);
```

+ partições mensais via `pg_partman`. TRUNCATE de partição antiga é rápido e não fere o append-only (não é DELETE).

---

## 5. Soft delete

Aplicado em `profiles` e `companies`. **Não** aplicado em `memberships` (saída é registrada no audit_log).

### Por quê?

- **Recuperação acidental**: usuário deletou empresa por engano.
- **LGPD com hard delete via anonimização**: troca dados pessoais por placeholders, mantém integridade referencial.
- **Análise temporal**: "quantas empresas foram deletadas no Q1?"

### Como funciona

- Coluna `deleted_at timestamptz`.
- Index parcial `WHERE deleted_at IS NULL` — queries de "registros ativos" são rápidas.
- RLS adiciona `AND deleted_at IS NULL` em policies de SELECT.
- Para "deletar de verdade" (LGPD), use service_role + função admin.

---

## 6. Convenções

### Nomes
- Tabelas: snake_case, plural (`profiles`, `memberships`)
- Funções: snake_case, verbo (`is_member_of`, `has_role_in`, `log_audit`)
- Triggers: tabela_acao (`profiles_set_updated_at`, `on_auth_user_created`)
- Index: tabela_coluna_tipo (`memberships_user_id_idx`)

### Migrations
- Nome: `YYYYMMDDHHMMSS_descricao.sql` (Supabase CLI gera com `--name`)
- Idempotentes: `CREATE ... IF NOT EXISTS`, `DROP POLICY IF EXISTS`
- Comentários explicando POR QUÊ, não apenas O QUÊ

### Funções
- Sempre `LANGUAGE sql` ou `plpgsql` explícito
- `STABLE`/`IMMUTABLE` quando aplicável (planner cacheia)
- `SECURITY DEFINER` + `SET search_path = ''` é obrigatório para qualquer função que bypassa RLS
- `REVOKE EXECUTE FROM PUBLIC` + `GRANT` explícito ao role correto

---

## 7. Decisões deliberadas (e não implementadas)

| Decisão | Por que NÃO incluímos |
|---|---|
| Billing/Stripe integration | Específico demais — cada produto tem regras diferentes |
| Email templates customizados | Resend basta para 90% dos casos; trocar é fácil |
| Frontend genérico (não Next.js) | Next.js é o stack mais usado com Supabase; outros são portáveis |
| Notificações in-app | Escopo aumenta muito; Realtime cobre o caso básico |
| Workspace > Project (Notion-like) | Diferentes produtos = diferentes hierarquias — adicione conforme precisar |

---

## 8. Extensões recomendadas

Quando começar a usar para um produto real, considere:

- **`pg_cron`**: jobs agendados dentro do Postgres (limpar convites expirados, etc).
- **`pgvector`**: se for adicionar features de IA.
- **`pgsodium`**: para criptografia de campos sensíveis (CPF, telefone) em tabela própria.
- **`pg_stat_statements`**: identificar queries lentas em produção.
