import Link from 'next/link';

export default function Home() {
  return (
    <div className="container">
      <h1>Supabase Multi-tenant Starter</h1>
      <p style={{ margin: '16px 0', color: '#666' }}>
        Template open source para SaaS multi-tenant com autenticação, empresas, papéis e convites.
      </p>
      <div style={{ display: 'flex', gap: 12 }}>
        <Link href="/auth/login" className="btn">Entrar</Link>
        <Link href="/auth/signup" className="btn ghost">Criar conta</Link>
      </div>
    </div>
  );
}
