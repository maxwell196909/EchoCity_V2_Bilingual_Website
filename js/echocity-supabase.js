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

document.addEventListener("DOMContentLoaded", async () => {
  const path = window.location.pathname;

  // Temporary test-mode UX while mainland SMS enterprise qualification is pending.
  // Keep phone login visible as the production direction, but prevent repeated 503 hook errors.
  if (/\/assets\/video-auth\.html$/.test(path)) {
    const sendOtp = document.getElementById("sendOtp");
    const phoneBox = document.getElementById("phoneBox");
    const emailBox = document.getElementById("emailBox");
    const status = document.getElementById("status");
    if (sendOtp) {
      sendOtp.disabled = true;
      sendOtp.textContent = "手机号登录开通中";
      sendOtp.style.opacity = ".55";
      sendOtp.style.cursor = "not-allowed";
    }
    if (phoneBox && emailBox) {
      phoneBox.style.display = "none";
      emailBox.classList.add("showBlock");
    }
    if (status) {
      status.textContent = "测试阶段请先使用邮箱登录。中国大陆手机号验证码将在企业短信资质和运营商报备完成后恢复。";
      status.className = "status show";
    }
    return;
  }

  // Keep authentication inside the short-video experience. The feed may also
  // be opened directly during testing, so it needs its own clear login entry.
  if (!/\/assets\/video-feed-v4\.html$/.test(path)) return;
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