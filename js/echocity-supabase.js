// EchoCity Supabase connection
// Use only the browser-safe Project URL and Publishable Key.

const ECHOCITY_SUPABASE_URL = "https://dpljvspwcfglxfesxdmf.supabase.co";
const ECHOCITY_SUPABASE_KEY = "sb_publishable_CngX8tJBl6eGAJUWTSt9HA_KtxTvM1-";

if (!window.supabase) {
  throw new Error("Supabase library has not been loaded.");
}

window.echoCitySupabase = window.supabase.createClient(
  ECHOCITY_SUPABASE_URL,
  ECHOCITY_SUPABASE_KEY
);

console.log("EchoCity connected to Supabase.");