// =============================================================================
// Cliente Supabase server-side (App Router)
// =============================================================================
// Usado em Server Components, Server Actions e Route Handlers.
// Lê cookies via next/headers. NUNCA expor service_role aqui.
// =============================================================================

import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Server Component não consegue setar cookies — ignora silenciosamente.
            // O middleware vai refresh quando necessário.
          }
        },
      },
    },
  );
}
