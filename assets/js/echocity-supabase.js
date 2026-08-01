const ECHOCITY_SUPABASE_URL =
  "https://dpljvspwcfglxfesxdmf.supabase.co";

const ECHOCITY_SUPABASE_KEY =
  "sb_publishable_CngX8tJBl6eGAJUWTSt9HA_KtxTvM1-";

window.echoCitySupabase = window.supabase.createClient(
  ECHOCITY_SUPABASE_URL,
  ECHOCITY_SUPABASE_KEY
);

function getSupabaseClient() {
  return window.echoCitySupabase;
}