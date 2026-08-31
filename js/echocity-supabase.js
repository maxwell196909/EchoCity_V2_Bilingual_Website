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

// Keep authentication inside the short-video experience. The feed may also
// be opened directly during testing, so it needs its own clear login entry.
document.addEventListener("DOMContentLoaded", async () => {
  if (!/\/assets\/video-feed-v4\.html$/.test(window.location.pathname)) return;
  if (document.getElementById("echocityVideoAuthEntry")) return;

  const button = document.createElement("button");
  button.id = "echocityVideoAuthEntry";
  button.type = "button";
  button.textContent = "登录 / 注册";
  Object.assign(button.style, {
    position: "fixed",
    top: "max(58px, calc(env(safe-area-inset-top) + 48px))",
    right: "10px",
    zIndex: "75",
    border: "1px solid rgba(255,255,255,.38)",
    borderRadius: "999px",
    padding: "9px 13px",
    background: "rgba(17,24,39,.82)",
    color: "#fff",
    fontWeight: "900",
    fontSize: "13px",
    boxShadow: "0 4px 16px rgba(0,0,0,.28)",
    backdropFilter: "blur(8px)",
    webkitBackdropFilter: "blur(8px)"
  });
  document.body.appendChild(button);

  try {
    const { data } = await window.echoCitySupabase.auth.getUser();
    const user = data?.user || null;
    if (user) {
      button.textContent = "我的";
      button.onclick = () => { window.location.href = "me.html"; };
    } else {
      button.onclick = () => {
        const ret = encodeURIComponent(window.location.pathname.split("/").pop() + window.location.search);
        window.location.href = "video-auth.html?return=" + ret;
      };
    }
  } catch (error) {
    button.onclick = () => { window.location.href = "video-auth.html?return=video-feed-v4.html"; };
  }
});

console.log("EchoCity connected to Supabase.");