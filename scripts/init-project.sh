#!/usr/bin/env bash
# =============================================================================
# init-project.sh — Bootstrap de um novo projeto a partir do template
# =============================================================================
# Uso:
#   bash scripts/init-project.sh <nome-do-projeto>
#
# O que faz:
#   - Renomeia config.toml com o nome do novo projeto
#   - Limpa CHANGELOG e cria 0.1.0 zerado
#   - Remove .git e re-inicializa (pra começar histórico limpo)
# =============================================================================

set -euo pipefail

PROJECT_NAME="${1:-}"
if [[ -z "$PROJECT_NAME" ]]; then
    echo "Uso: bash scripts/init-project.sh <nome-do-projeto>"
    exit 1
fi

# Valida slug
if ! [[ "$PROJECT_NAME" =~ ^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$ ]]; then
    echo "Nome inválido. Use lowercase, números e hífens (3-50 chars)."
    exit 1
fi

echo "→ Renomeando projeto para: $PROJECT_NAME"
sed -i.bak "s/^project_id = .*/project_id = \"$PROJECT_NAME\"/" supabase/config.toml
rm supabase/config.toml.bak

echo "→ Atualizando package.json do exemplo Next.js"
sed -i.bak "s/\"name\": \".*\"/\"name\": \"$PROJECT_NAME\"/" examples/nextjs/package.json
rm examples/nextjs/package.json.bak

echo "→ Resetando CHANGELOG"
cat > CHANGELOG.md <<'EOF'
# Changelog

## [Unreleased]
EOF

echo "→ Removendo .git existente e re-inicializando"
rm -rf .git
git init -b main >/dev/null
git add -A
git commit -m "chore: bootstrap from supabase-multitenant-starter" >/dev/null

echo ""
echo "✓ Projeto '$PROJECT_NAME' inicializado!"
echo ""
echo "Próximos passos:"
echo "  1. supabase start"
echo "  2. supabase db reset   # aplica migrations + seed"
echo "  3. cd examples/nextjs && cp .env.example .env.local"
echo "  4. npm install && npm run dev"
echo ""
