const allowedOrigins = new Set([
  "https://maxwell196909.github.io",
  "https://echocity.org",
  "https://www.echocity.org",
  "capacitor://localhost",
  "http://localhost",
  "https://localhost"
]);

function cors(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin) ? origin : "https://maxwell196909.github.io";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "content-type, apikey",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin"
  };
}

function authorized(req: Request) {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}");
    return Object.values(keys).includes(req.headers.get("apikey"));
  } catch {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  const headers = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers });
  if (!authorized(req)) return Response.json({ error: "Unauthorized" }, { status: 401, headers });

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return Response.json({ error: "OPENAI_API_KEY is not configured", diagnostic_code: "OPENAI_KEY_MISSING" }, { status: 503, headers });

  try {
    const body = await req.json();
    const message = String(body.message || "").trim().slice(0, 2000);
    const language = body.language === "en" ? "en" : "zh";
    const history = Array.isArray(body.history) ? body.history.slice(-8) : [];
    if (!message) return Response.json({ error: "Message is required" }, { status: 400, headers });

    const system = `You are Echo, the service guide for EchoCity. Answer in ${language === "zh" ? "Simplified Chinese" : "English"}.
Help users identify and use EchoCity services. Be concise, practical, warm, and ask one useful follow-up question when information is missing.
EchoCity modules:
- customer: housing special repair fund applications; engineering/project management consulting; bidding documents; technical proposals; technical defense coaching; overseas engineering consulting; submitting and tracking service needs.
- worker: assigned tasks, acceptance, arrival, start, photos/videos, milestones, completion.
- admin: request review, standards, quotation, dispatch, supervision, milestone and final acceptance.
Return only JSON with keys: answer, module, moduleLabel, nextAction.
module must be customer, worker, admin, or none. Recommend a module only when reasonably clear. Do not invent laws, approvals, prices, or guarantees.`;

    const messages = [
      { role: "system", content: system },
      ...history.map((item: any) => ({
        role: item.role === "assistant" ? "assistant" : "user",
        content: String(item.content || "").slice(0, 1500)
      })),
      { role: "user", content: message }
    ];

    const openai = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: "gpt-5-mini",
        messages,
        response_format: { type: "json_object" },
        max_completion_tokens: 700
      })
    });

    const requestId = openai.headers.get("x-request-id") || "";
    const data = await openai.json();
    if (!openai.ok) {
      const upstreamCode = String(data?.error?.code || data?.error?.type || "unknown").slice(0, 80);
      console.error("OpenAI upstream error", {
        status: openai.status,
        code: upstreamCode,
        request_id: requestId
      });
      return Response.json({
        error: "AI service unavailable",
        diagnostic_code: "OPENAI_UPSTREAM_ERROR",
        upstream_status: openai.status,
        upstream_code: upstreamCode,
        request_id: requestId
      }, { status: 502, headers });
    }

    const result = JSON.parse(data.choices?.[0]?.message?.content || "{}");
    const modules = new Set(["customer", "worker", "admin", "none"]);
    const output = {
      answer: String(result.answer || ""),
      module: modules.has(result.module) ? result.module : "none",
      moduleLabel: String(result.moduleLabel || ""),
      nextAction: String(result.nextAction || "")
    };
    if (!output.answer) throw new Error("Empty AI answer");
    return Response.json(output, { headers });
  } catch (error) {
    console.error("echo-assistant", error instanceof Error ? error.message : "unknown");
    return Response.json({ error: "Request failed", diagnostic_code: "ECHO_INTERNAL_ERROR" }, { status: 500, headers });
  }
});
