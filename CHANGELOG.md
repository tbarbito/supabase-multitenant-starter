# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

## [0.1.0] — 2026-05-15

Primeiro release público.

### Added

- Estrutura inicial do template multi-tenant para Supabase.
- Schema PostgreSQL: tabelas `profiles`, `companies`, `memberships` (N:N), `invitations`, `audit_log`.
- ENUMs: `app_role` (owner/admin/member/viewer), `invitation_status`, `audit_action`.
- Row Level Security habilitada e **forçada** em todas as tabelas, com testes pgTAP (15/15 passando).
- Helper functions com `SECURITY DEFINER` + `search_path=""` (anti-hijacking): `is_member_of`, `has_role_in`, `current_user_role_in`, `count_owners`, `auth_uid`, `log_audit`, `set_active_company`.
- Triggers de invariantes: `set_updated_at`, `handle_new_user`, `sync_profile_email`, `set_company_creator`, `guard_membership_change` (impede remoção do último owner e auto-promoção), `audit_membership_changes`.
- **Custom Access Token Hook** que injeta `memberships` e `active_company_id` no JWT (em `app_metadata`, não forjável pelo cliente).
- Edge Function `invitations` (create / accept / revoke) com token CSPRNG de 256 bits e armazenamento apenas do SHA-256 hash.
- Soft delete em `profiles` e `companies`.
- Audit log **append-only** (sem policies de UPDATE/DELETE).
- Seed.sql com 2 usuários e 2 empresas de exemplo para desenvolvimento.
- Exemplo Next.js 15 + React 19 com App Router, SSR auth via `@supabase/ssr`, middleware de refresh, company switcher e gestão de membros.
- Documentação completa: `README.md`, `SECURITY.md` (modelo de ameaças), `ARCHITECTURE.md` (decisões e justificativas), `QUICKSTART.md` (dev → produção), `CONTRIBUTING.md`.
- GitHub Actions CI: lint SQL, testes pgTAP, geração de types TypeScript, deno check da Edge Function, type-check do Next.js.
- Script `scripts/init-project.sh` para usar o template como base de novos projetos.

### Validated (E2E local)

- 10/10 migrations aplicam sem erro.
- 15/15 testes pgTAP de RLS passam.
- TypeScript `tsc --noEmit` exit 0.
- `next build` produz bundle limpo (11 rotas, ~170 kB First Load).
- 5 cenários de ataque bloqueados: member tentando convidar, auto-promoção a owner via REST, leitura anônima, member deletando empresa, token de convite forjado.
