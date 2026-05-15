'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';

export default function SignupPage() {
  const router = useRouter();
  const [fullName, setFullName] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setInfo(null);

    if (password.length < 12) {
      setError('A senha deve ter pelo menos 12 caracteres.');
      return;
    }

    setLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName, company_name: companyName },
        emailRedirectTo: `${location.origin}/auth/callback`,
      },
    });
    setLoading(false);

    if (error) {
      setError(error.message);
      return;
    }

    setInfo('Cadastro criado. Confira seu email para confirmar a conta antes de fazer login.');
    setTimeout(() => router.push('/auth/login'), 4000);
  }

  return (
    <div className="container" style={{ maxWidth: 420 }}>
      <h1>Criar conta</h1>
      <form onSubmit={onSubmit} className="card" style={{ marginTop: 16 }}>
        <label className="label">Nome completo</label>
        <input required value={fullName} onChange={(e) => setFullName(e.target.value)} className="input" />

        <label className="label">Nome da sua empresa/workspace</label>
        <input required value={companyName} onChange={(e) => setCompanyName(e.target.value)} className="input" placeholder="Ex: Minha Startup Ltda" />

        <label className="label">Email</label>
        <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="input" />

        <label className="label">Senha (mín. 12 caracteres, com maiúscula, minúscula, número e símbolo)</label>
        <input type="password" required minLength={12} value={password} onChange={(e) => setPassword(e.target.value)} className="input" />

        <button className="btn" disabled={loading}>{loading ? 'Criando…' : 'Criar conta'}</button>
        {error && <p className="error">{error}</p>}
        {info && <p className="success">{info}</p>}
      </form>
      <p>
        Já tem conta? <Link href="/auth/login">Entrar</Link>
      </p>
    </div>
  );
}
