import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const allowedOrigins = new Set([
  "https://maxwell196909.github.io",
  "https://echocity.org",
  "https://www.echocity.org",
  "https://maxwellchengresearch.com",
  "https://www.maxwellchengresearch.com"
]);

function cors(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin)
    ? origin
    : "https://maxwell196909.github.io";

  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers":
      "authorization,x-client-info,apikey,content-type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Vary": "Origin"
  };
}

function json(
  body: unknown,
  status: number,
  origin: string | null
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors(origin),
      "Content-Type": "application/json"
    }
  });
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");

  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: cors(origin) });
  }

  if (request.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405, origin);
  }

  if (origin && !allowedOrigins.has(origin)) {
    return json({ error: "ORIGIN_NOT_ALLOWED" }, 403, origin);
  }

  try {
    const body = await request.json();
    const requestNo = String(body.requestNo || "")
      .trim()
      .toUpperCase();
    const token = String(body.token || "").trim();
    const fileName = String(body.fileName || "").slice(0, 180);
    const mimeType = String(body.mimeType || "").toLowerCase();
    const fileSize = Number(body.fileSize || 0);

    if (
      !/^REQ-[A-Z0-9-]{4,80}$/.test(requestNo) ||
      token.length < 32 ||
      token.length > 128
    ) {
      return json({ error: "INVALID_TASK_LINK" }, 400, origin);
    }

    const extensions: Record<string, string> = {
      "image/jpeg": "jpg",
      "image/png": "png",
      "image/webp": "webp",
      "image/heic": "heic",
      "image/heif": "heif"
    };
    const maxFileBytes = 10 * 1024 * 1024;

    if (
      !extensions[mimeType] ||
      !Number.isSafeInteger(fileSize) ||
      fileSize < 1 ||
      fileSize > maxFileBytes
    ) {
      return json({ error: "INVALID_PRESTART_PHOTO" }, 400, origin);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "SERVER_CONFIG_ERROR" }, 500, origin);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });

    const { data: task, error: taskError } = await admin.rpc(
      "read_task_with_token",
      {
        p_request_no: requestNo,
        p_token: token,
        p_role: "worker"
      }
    );

    if (taskError || !task) {
      return json(
        { error: "TASK_LINK_EXPIRED_OR_INVALID" },
        403,
        origin
      );
    }

    if (
      task.status !== "arrived" ||
      task.current_actor !== "worker" ||
      task.next_action !== "prestart_confirmation"
    ) {
      return json(
        { error: "TASK_NOT_READY_FOR_PRESTART" },
        409,
        origin
      );
    }

    const path =
      `${requestNo}/worker/prestart/${Date.now()}-` +
      `${crypto.randomUUID()}.${extensions[mimeType]}`;

    const { data: signed, error: signError } =
      await admin.storage
        .from("work-evidence")
        .createSignedUploadUrl(path, { upsert: false });

    if (signError || !signed?.token) {
      console.error("Signed upload creation failed:", signError);
      return json({ error: "SIGNED_UPLOAD_FAILED" }, 500, origin);
    }

    return json(
      {
        bucket: "work-evidence",
        path,
        uploadToken: signed.token,
        maxFileBytes,
        originalFileName: fileName
      },
      200,
      origin
    );
  } catch (error) {
    console.error("worker-prestart-upload failed:", error);
    return json({ error: "UNEXPECTED_ERROR" }, 500, origin);
  }
});
