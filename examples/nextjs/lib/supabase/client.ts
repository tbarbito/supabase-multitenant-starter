// =============================================================================
// Cliente Supabase browser-side
// =============================================================================
// Usado em Client Components. NUNCA importar service_role aqui — só anon key.
// =============================================================================

import { createBrowserClient } from '@supabase/ssr';

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
