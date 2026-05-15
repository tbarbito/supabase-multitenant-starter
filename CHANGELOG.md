# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adere a [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Added
- Estrutura inicial do template multi-tenant.
- Tabelas: `profiles`, `companies`, `memberships`, `invitations`, `audit_log`.
- ENUMs: `app_role`, `invitation_status`, `audit_action`.
- Row Level Security em todas as tabelas com testes pgTAP.
- Helper functions: `is_member_of`, `has_role_in`, `current_user_role_in`, `count_owners`, `log_audit`.
- Triggers: `set_updated_at`, `handle_new_user`, `sync_profile_email`, `set_company_creator`, `guard_membership_change`, `audit_membership_changes`.
- Custom Access Token Hook para JWT com `memberships` e `active_company_id`.
- Edge Function `invitations` (create / accept / revoke) com token SHA-256 hash.
- Seed.sql com 2 usuários e 2 empresas de exemplo.
- Exemplo Next.js 15 com App Router, SSR auth, company switcher e gestão de membros.
- Documentação: README, SECURITY, ARCHITECTURE, QUICKSTART, CONTRIBUTING.
- GitHub Actions CI: lint SQL, testes pgTAP, geração de types TypeScript, deno check.

## [0.1.0] — TBD

Primeiro release público.
