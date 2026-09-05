import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const allowedOrigins = new Set([
  "https://maxwellchengresearch.com",
  "https://www.maxwellchengresearch.com",
  "https://maxwell196909.github.io",
  "https://echocity.org",
  "https://www.echocity.org"
]);

function cors(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin)
    ? origin
    : "https://maxwell196909.github.io";

  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization,x-client-info,apikey,content-type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Vary": "Origin"
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(origin), "Content-Type": "application/json" }
  });
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (request.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405, origin);
  if (origin && !allowedOrigins.has(origin)) return json({ error: "ORIGIN_NOT_ALLOWED" }, 403, origin);

  try {
    const body = await request.json();
    const requestNo = String(body.requestNo || "").trim().toUpperCase();
    const taskToken = String(body.token || "").trim();
    const fileName = String(body.fileName || "").slice(0, 180);
    const mimeType = String(body.mimeType || "").toLowerCase();
    const fileSize = Number(body.fileSize || 0);

    const allowedTypes: Record<string, string> = {
      "image/jpeg": "jpg",
      "image/png": "png",
      "image/webp": "webp",
      "image/heic": "heic",
      "image/heif": "heif"
    };

    if (!/^REQ-[A-Z0-9-]{4,80}$/.test(requestNo) || taskToken.length < 32 || taskToken.length > 128) {
      return json({ error: "INVALID_TASK_LINK" }, 400, origin);
    }

    if (!allowedTypes[mimeType] || !Number.isSafeInteger(fileSize) || fileSize < 1 || fileSize > 10 * 1024 * 1024) {
      return json({ error: "INVALID_WORK_PHOTO" }, 400, origin);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) return json({ error: "SERVER_CONFIG_ERROR" }, 500, origin);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: valid, error: tokenError } = await admin.rpc("validate_task_access_token", {
      p_request_no: requestNo,
      p_role: "worker",
      p_token: taskToken
    });

    if (tokenError || valid !== true) {
      return json({ error: "TASK_LINK_EXPIRED_OR_INVALID" }, 403, origin);
    }

    const { data: task, error: taskError } = await admin
      .from("service_requests")
      .select("request_no,assigned_worker_phone,status,work_started_at")
      .eq("request_no", requestNo)
      .single();

    if (taskError || !task) return json({ error: "TASK_NOT_FOUND" }, 404, origin);

    if (!["in_progress", "working", "milestone_rework"].includes(task.status) || !task.work_started_at) {
      return json({ error: "TASK_NOT_READY_FOR_WORK_EVIDENCE" }, 409, origin);
    }

    const phone = String(task.assigned_worker_phone || "").replace(/\D/g, "");
    if (!phone) return json({ error: "WORKER_PHONE_REQUIRED" }, 409, origin);

    const path = `${requestNo}/${phone}/process-photos/${Date.now()}-${crypto.randomUUID()}.${allowedTypes[mimeType]}`;
    const { data: signed, error: signedError } = await admin.storage
      .from("work-evidence")
      .createSignedUploadUrl(path, { upsert: false });

    if (signedError || !signed?.token) {
      console.error("Signed upload creation failed:", signedError);
      return json({ error: "SIGNED_UPLOAD_FAILED" }, 500, origin);
    }

    return json({
      bucket: "work-evidence",
      path,
      uploadToken: signed.token,
      maxFileBytes: 10 * 1024 * 1024,
      acceptedTypes: Object.keys(allowedTypes),
      originalFileName: fileName
    }, 200, origin);
  } catch (error) {
    console.error("worker-process-upload failed:", error);
    return json({ error: "UNEXPECTED_ERROR" }, 500, origin);
  }
});
