# Modelo de Segurança

Este documento descreve o **modelo de ameaças**, as **mitigações implementadas** e o **checklist de hardening** para produção.

---

## 1. Modelo de ameaças

| # | Ameaça | Mitigação |
|---|---|---|
| T1 | Usuário lê dados de outra empresa | RLS em todas as tabelas, `is_member_of()` em todas as policies |
| T2 | Usuário escreve em empresa que não pertence | `WITH CHECK` em todas as policies de INSERT/UPDATE |
| T3 | Atacante forja role no JWT | Roles vêm de `app_metadata` (server-only), não `user_metadata` |
| T4 | SQL injection via input | Sem `EXECUTE` dinâmico; queries parametrizadas no Supabase SDK |
| T5 | Schema hijacking em SECURITY DEFINER | Todas as funções têm `SET search_path = ''` e usam nomes qualificados |
| T6 | Vazamento de token de convite | Token nunca armazenado em claro (apenas SHA-256); URL HTTPS only |
| T7 | Timing attack no aceite de convite | Comparação por hash em tempo constante (SHA-256) |
| T8 | Admin se auto-promove a owner | Trigger `guard_membership_change` bloqueia |
| T9 | Último owner removido (empresa órfã) | Trigger bloqueia DELETE/UPDATE que reduz `count_owners()` a 0 |
| T10 | service_role exposto no frontend | Documentação + ausência da chave nos exemplos client-side |
| T11 | Audit log adulterado | Sem policies de UPDATE/DELETE — append-only |
| T12 | DoS via signup em massa | Email confirmation + Supabase rate limit + (recomendado) CAPTCHA |
| T13 | Email enumeration via "esqueci a senha" | Supabase Auth retorna sucesso genérico independente do email existir |
| T14 | Sessão zumbi após logout em um dispositivo | `enable_refresh_token_rotation = true` + JWT curto (1h) |
| T15 | XSS injetando código em campos | Frontend usa React (escape automático); HTML em emails é escapado |

---

## 2. Defesa em camadas

### Camada 1: Row Level Security (RLS)

- **TODAS** as tabelas de `public` têm `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY`.
- Sem policy = sem acesso (deny by default).
- Policies separadas por comando (SELECT/INSERT/UPDATE/DELETE) — nunca usar `FOR ALL`.

### Camada 2: Helper functions com SECURITY DEFINER

- `is_member_of()`, `has_role_in()`, etc. rodam como dono da função (bypassa RLS para a query interna), mas:
  - Têm `SET search_path = ''` (previne schema hijacking)
  - Usam nomes totalmente qualificados (`public.memberships`, `auth.uid()`)
  - `REVOKE EXECUTE FROM PUBLIC` + `GRANT` explícito a `authenticated`

### Camada 3: Triggers de invariantes

- `guard_membership_change` impede:
  - Remover/rebaixar último owner
  - Admin auto-promover a owner
- `handle_new_user` é tolerante a erros (não quebra signup se profile falhar)

### Camada 4: Custom JWT Claims (Auth Hook)

- `app_metadata.memberships` é injetado no token pelo backend.
- Cliente **não consegue forjar** (campo é immutable do lado do cliente).
- Permite RLS consultar role sem hit no banco em toda query.

### Camada 5: Auditoria

- Tabela `audit_log` é append-only via RLS.
- Toda mudança crítica passa por `log_audit()`.
- IP e User-Agent capturados automaticamente.

---

## 3. Boas práticas críticas

### ✅ FAÇA

- Use `getUser()` (revalida JWT) em vez de `getSession()` (só lê cookie) em SSR.
- Habilite **email confirmation** (`enable_confirmations = true`).
- Use **MFA** para owners e admins.
- Rote a **anon key** se suspeitar de vazamento (no painel do Supabase).
- Configure **Site URL** corretamente — JWT é válido apenas para o site configurado.
- Use HTTPS em produção (Supabase já força).
- Habilite o **Custom Access Token Hook** no painel.
- Configure **alertas** no painel para tentativas de login anormais.
- Faça **backups regulares** (Supabase faz, mas confira retenção do seu plano).
- Use **branch deployments** do Supabase para testar migrations antes de prod.

### ❌ NÃO FAÇA

- ❌ Nunca exponha `SUPABASE_SERVICE_ROLE_KEY` no frontend (incluindo `NEXT_PUBLIC_*`).
- ❌ Nunca desabilite RLS "só pra testar" e esqueça ligado.
- ❌ Nunca confie em `user_metadata` para autorização — é editável pelo próprio usuário.
- ❌ Nunca crie função `SECURITY DEFINER` sem `SET search_path = ''`.
- ❌ Nunca armazene tokens de convite em claro.
- ❌ Nunca permita criação de admin/owner via API pública sem autorização explícita.
- ❌ Nunca use `FOR ALL` em policy — sempre separe por comando.
- ❌ Nunca skip de hooks de pre-commit (incluindo SQL lint).

---

## 4. Checklist de produção

Antes de ir pro ar:

- [ ] Site URL configurada corretamente no painel
- [ ] Email confirmation habilitada
- [ ] Política de senha forte habilitada (mín. 12 chars + classes)
- [ ] Custom Access Token Hook habilitado e apontando para `public.custom_access_token_hook`
- [ ] MFA habilitado (opcional para member, obrigatório para admin/owner)
- [ ] CAPTCHA configurado nos endpoints públicos (signup, reset password)
- [ ] Webhook de alertas configurado (login from new device, etc)
- [ ] Backup automático ativo
- [ ] `RESEND_API_KEY` (ou SMTP) configurado nos secrets das Edge Functions
- [ ] Service role key NÃO está no repositório nem em variáveis públicas
- [ ] CORS configurado restritivo nas Edge Functions (não `*` em produção)
- [ ] Rate limiting adicional configurado se o caso de uso exigir
- [ ] Logs do Supabase sendo retidos ou enviados para SIEM externo
- [ ] LGPD/GDPR: política de retenção de `audit_log` documentada
- [ ] LGPD/GDPR: rota de exportação/anonimização do usuário implementada

---

## 5. LGPD / GDPR

### Direito ao esquecimento

Usar **anonimização** em vez de DELETE completo, para preservar audit_log:

```sql
-- Exemplo de função admin (rodar como service_role)
UPDATE auth.users
SET email = 'anonymized-' || id || '@deleted.local'
WHERE id = '<user_id>';

UPDATE public.profiles
SET email = 'anonymized@deleted.local',
    full_name = '[anonimizado]',
    avatar_url = NULL,
    deleted_at = now()
WHERE id = '<user_id>';
```

### Direito ao acesso (export)

Implementar Edge Function `/me/export` que retorna JSON com:
- Profile do usuário
- Lista de memberships
- Audit log das próprias ações (`WHERE actor_user_id = auth.uid()`)

### Retenção de audit log

Por padrão, audit_log não é purgado. Sugestões:
- Manter 1 ano completo
- Após 1 ano, manter apenas ações críticas (`company.deleted`, `ownership.transferred`)
- Job de retenção rodando como service_role (fora do RLS)

---

## 6. Reportando vulnerabilidades

Se você encontrou uma falha de segurança neste template, **NÃO abra issue pública**.

Envie para: `security@biizhubflow.com` (substitua pelo seu email)

Aceitamos disclosure responsável e creditamos quem reportar.
