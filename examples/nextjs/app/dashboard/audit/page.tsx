import { redirect } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';

const ACTION_LABELS: Record<string, string> = {
  'company.created': 'Empresa criada',
  'company.updated': 'Empresa atualizada',
  'company.deleted': 'Empresa removida',
  'member.invited': 'Membro convidado',
  'member.joined': 'Membro entrou',
  'member.role_changed': 'Papel alterado',
  'member.removed': 'Membro removido',
  'member.left': 'Membro saiu',
  'invitation.revoked': 'Convite revogado',
  'ownership.transferred': 'Ownership transferido',
};

export default async function AuditPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/auth/login');

  // RLS filtra automaticamente: só admin+ vê o log da empresa ativa
  const { data: logs } = await supabase
    .from('audit_log')
    .select('id, action, actor_user_id, target_user_id, metadata, created_at, profiles!audit_log_actor_user_id_fkey(full_name, email)')
    .order('created_at', { ascending: false })
    .limit(100);

  return (
    <div className="container">
      <Link href="/dashboard">← Voltar ao dashboard</Link>
      <h1 style={{ marginTop: 16 }}>Auditoria</h1>
      <p style={{ color: '#666', marginBottom: 16 }}>Últimas 100 ações na empresa ativa.</p>

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Quando</th>
              <th>Quem</th>
              <th>Ação</th>
              <th>Detalhes</th>
            </tr>
          </thead>
          <tbody>
            {(logs ?? []).map((l: any) => (
              <tr key={l.id}>
                <td>{new Date(l.created_at).toLocaleString('pt-BR')}</td>
                <td>{l.profiles?.full_name ?? l.profiles?.email ?? 'sistema'}</td>
                <td>{ACTION_LABELS[l.action] ?? l.action}</td>
                <td><code style={{ fontSize: 12 }}>{JSON.stringify(l.metadata)}</code></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
