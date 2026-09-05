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

// Mobile/iPad video publishing: replace large uploads to echocity-videos
// with Supabase Storage resumable TUS uploads. Small files and covers keep
// using the normal SDK upload path.
(() => {
  const client = window.echoCitySupabase;
  if (!client?.storage?.from) return;
  const originalFrom = client.storage.from.bind(client.storage);

  const setProgress = (text, isError = false) => {
    const el = document.getElementById("status");
    if (!el) return;
    el.textContent = text;
    el.className = "status show" + (isError ? " danger" : "");
  };

  client.storage.from = function patchedFrom(bucket) {
    const bucketClient = originalFrom(bucket);
    if (bucket !== "echocity-videos") return bucketClient;

    const originalUpload = bucketClient.upload.bind(bucketClient);
    bucketClient.upload = async function resumableVideoUpload(path, file, options = {}) {
      if (!file || typeof file.size !== "number" || file.size <= 6 * 1024 * 1024) {
        return originalUpload(path, file, options);
      }

      try {
        const { data: sessionData, error: sessionError } = await client.auth.getSession();
        const token = sessionData?.session?.access_token;
        if (sessionError || !token) {
          return { data: null, error: sessionError || new Error("登录会话已失效，请重新登录") };
        }

        setProgress("正在准备分片上传……");
        const tusModule = await import("https://esm.sh/tus-js-client@4.3.1");
        const Upload = tusModule.Upload;
        const endpoint = "https://dpljvspwcfglxfesxdmf.storage.supabase.co/storage/v1/upload/resumable";
        const contentType = options.contentType || file.type || "video/mp4";

        return await new Promise((resolve) => {
          const upload = new Upload(file, {
            endpoint,
            retryDelays: [0, 3000, 5000, 10000, 20000],
            chunkSize: 6 * 1024 * 1024,
            uploadDataDuringCreation: true,
            removeFingerprintOnSuccess: true,
            headers: {
              authorization: `Bearer ${token}`,
              "x-upsert": options.upsert ? "true" : "false"
            },
            metadata: {
              bucketName: bucket,
              objectName: path,
              contentType,
              cacheControl: String(options.cacheControl || "3600")
            },
            onError(error) {
              console.error("EchoCity resumable video upload failed", error);
              setProgress("视频上传失败：" + (error?.message || "网络或存储异常"), true);
              resolve({ data: null, error });
            },
            onProgress(bytesUploaded, bytesTotal) {
              const pct = bytesTotal ? Math.min(100, Math.round(bytesUploaded / bytesTotal * 100)) : 0;
              setProgress(`正在上传视频…… ${pct}%`);
            },
            onSuccess() {
              setProgress("视频上传完成，正在提交审核信息……");
              resolve({ data: { path }, error: null });
            }
          });
          upload.start();
        });
      } catch (error) {
        console.error("EchoCity resumable upload initialization failed", error);
        setProgress("视频上传初始化失败：" + (error?.message || "请重试"), true);
        return { data: null, error };
      }
    };
    return bucketClient;
  };
})();

document.addEventListener("DOMContentLoaded", async () => {
  const path = window.location.pathname;

  // Complete the dedicated worker flow: once the platform confirms payment,
  // surface the receipt-confirmation entry directly on the normal worker task page.
  if (/\/assets\/worker-tasks\.html$/.test(path)) {
    const q = new URLSearchParams(window.location.search);
    const h = new URLSearchParams(window.location.hash.slice(1));
    const requestNo = String(q.get("request_no") || q.get("request") || "").trim().toUpperCase();
    const workerToken = String(
      q.get("worker_token") || q.get("task_token") || q.get("token") || h.get("token") || ""
    ).trim();

    if (/^REQ-[A-Z0-9-]{4,80}$/.test(requestNo) && workerToken.length >= 32 && workerToken.length <= 128) {
      try {
        const { data: settlement, error } = await window.echoCitySupabase.rpc(
          "get_order_settlement_with_token",
          { p_request_no: requestNo, p_role: "worker", p_token: workerToken }
        );

        if (!error && settlement?.status === "payment_confirmed") {
          const addReceiptButton = () => {
            if (document.getElementById("echocityWorkerSettlementEntry")) return true;
            const actions = document.querySelector(".task-actions");
            if (!actions) return false;

            const button = document.createElement("button");
            button.id = "echocityWorkerSettlementEntry";
            button.type = "button";
            button.className = "success-button";
            button.textContent = "确认收款";
            button.onclick = () => {
              window.location.href = `worker-settlement.html?request=${encodeURIComponent(requestNo)}#token=${encodeURIComponent(workerToken)}`;
            };
            actions.appendChild(button);
            return true;
          };

          if (!addReceiptButton()) {
            const observer = new MutationObserver(() => {
              if (addReceiptButton()) observer.disconnect();
            });
            observer.observe(document.body, { childList: true, subtree: true });
            window.setTimeout(() => observer.disconnect(), 15000);
          }
        }
      } catch (error) {
        console.warn("Worker settlement entry check failed:", error);
      }
    }
  }

  // Temporary test-mode UX while mainland SMS enterprise qualification is pending.
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

  // Keep authentication inside the short-video experience.
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