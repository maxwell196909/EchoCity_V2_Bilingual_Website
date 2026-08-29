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

function fallbackReply(message: string, language: "zh" | "en") {
  const text = message.toLowerCase();
  let module = "none";
  let moduleLabel = "";
  let nextAction = "";

  if (/维修资金|维修基金|repair fund|投标|标书|技术方案|工程咨询|服务需求|申请/.test(text)) {
    module = "customer";
    moduleLabel = language === "zh" ? "客户服务" : "Customer services";
    nextAction = language === "zh" ? "进入客户服务目录并提交需求" : "Open the customer catalog and submit a request";
  } else if (/任务|接单|到达|开工|施工|里程碑|完工|worker|my task/.test(text)) {
    module = "worker";
    moduleLabel = language === "zh" ? "服务人员工作台" : "Worker dashboard";
    nextAction = language === "zh" ? "查询并处理我的任务" : "Find and manage my tasks";
  } else if (/平台|审核|报价|派工|验收|结算|admin|dispatch|quote/.test(text)) {
    module = "admin";
    moduleLabel = language === "zh" ? "平台管理工作台" : "Platform dashboard";
    nextAction = language === "zh" ? "进入平台审核、报价与派工" : "Open platform review, quoting, and dispatch";
  }

  const answer = language === "zh"
    ? (module === "none"
      ? "我已收到你的问题。请再说明你是要提交服务需求、查询工作任务，还是进行平台审核与派工？"
      : `我已识别你的需求，建议进入“${moduleLabel}”。你可以先打开对应模块，按页面提示继续。`)
    : (module === "none"
      ? "I received your question. Are you submitting a service request, finding a work task, or managing platform review and dispatch?"
      : `I identified your need. Open “${moduleLabel}” and continue with the page guidance.`);

  return {
    answer,
    module,
    moduleLabel,
    nextAction,
    degraded: true,
    diagnostic_code: "AI_CREDIT_FALLBACK"
  };
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
      if (openai.status === 429 && upstreamCode === "credit_balance_exhausted") {
        return Response.json(fallbackReply(message, language), { status: 200, headers });
      }
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
