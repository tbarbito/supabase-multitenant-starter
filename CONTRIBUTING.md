# Contribuindo

Obrigado pelo interesse em contribuir! 🎉

## Antes de começar

1. Abra uma **issue** descrevendo o que pretende fazer (bug, feature, melhoria de doc).
2. Espere feedback dos mantenedores antes de investir tempo em um PR grande.

## Setup local

```bash
git clone https://github.com/SEU-USUARIO/supabase-multitenant-starter.git
cd supabase-multitenant-starter
supabase start
supabase db reset
```

## Diretrizes de código

### SQL (migrations)

- Sempre idempotente: `CREATE ... IF NOT EXISTS`, `DROP POLICY IF EXISTS`.
- Comentários em PT-BR explicando POR QUÊ, não apenas O QUÊ.
- Toda função `SECURITY DEFINER` deve ter `SET search_path = ''` e usar nomes qualificados.
- Toda nova tabela em `public` deve ter `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY` na mesma migration.
- Para nova tabela, criar policies separadas por comando (SELECT/INSERT/UPDATE/DELETE).

### TypeScript (Next.js / Edge Functions)

- `strict: true` no tsconfig.
- Nunca usar `any` sem justificativa em comentário.
- Server Components por padrão; `'use client'` apenas quando necessário.
- `getUser()` em SSR (revalida JWT) em vez de `getSession()` (só lê cookie).

### Testes

- Adicione testes pgTAP em `supabase/tests/` para novas policies.
- Cubra casos negativos (o que NÃO pode ser feito).

## Checklist de PR

- [ ] `supabase db lint` passa sem erros
- [ ] `supabase test db` passa
- [ ] Documentação atualizada (`ARCHITECTURE.md`, `SECURITY.md` ou `QUICKSTART.md` conforme aplicável)
- [ ] CHANGELOG atualizado (se mudança visível ao usuário)
- [ ] Conventional Commits no título do PR (`feat:`, `fix:`, `docs:`, etc.)

## Commits

Seguimos [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` nova funcionalidade
- `fix:` correção de bug
- `docs:` mudança só em documentação
- `refactor:` reescrita sem mudança de comportamento
- `test:` adição ou ajuste de testes
- `chore:` infra, CI, dependências

Exemplo: `feat(invitations): adiciona limite de convites por dia`

## Código de conduta

Trate todos com respeito. Não toleramos assédio, discriminação ou comentários hostis. Veja [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
