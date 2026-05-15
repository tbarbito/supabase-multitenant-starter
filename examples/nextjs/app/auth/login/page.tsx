'use client';

import { useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';

export default function LoginPage() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);
    if (error) {
      setError(error.message);
      return;
    }
    router.push(params.get('redirect') ?? '/dashboard');
    router.refresh();
  }

  return (
    <div className="container" style={{ maxWidth: 420 }}>
      <h1>Entrar</h1>
      <form onSubmit={onSubmit} className="card" style={{ marginTop: 16 }}>
        <label className="label">Email</label>
        <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="input" />
        <label className="label">Senha</label>
        <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} className="input" />
        <button className="btn" disabled={loading}>{loading ? 'Entrando…' : 'Entrar'}</button>
        {error && <p className="error">{error}</p>}
      </form>
      <p>
        Não tem conta? <Link href="/auth/signup">Criar agora</Link>
      </p>
    </div>
  );
}
