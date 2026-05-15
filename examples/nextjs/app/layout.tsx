import './globals.css';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Supabase Multi-tenant Starter',
  description: 'Template open source para SaaS multi-tenant com Supabase',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
