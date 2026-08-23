(function () {
  "use strict";

  const language = () => localStorage.getItem("echocity-language") === "en" ? "en" : "zh";
  const copy = {
    zh: {
      title: "施工过程记录",
      progress: "本次完成的工作（必填）",
      materials: "使用的材料（选填）",
      issues: "发现的问题（选填）",
      hours: "本次工时（选填）",
      photo: "上传本次施工照片（建议上传）",
      choose: "选择照片或拍照",
      none: "尚未选择照片",
      save: "保存施工记录",
      required: "请填写本次完成的工作。",
      large: "照片不能超过10MB。",
      saving: "正在上传并保存施工记录……",
      saved: "施工记录已保存，客户和平台现在可以看到。",
      failed: "提交失败，请稍后重试或联系平台。"
      ,milestone: "提交阶段成果", milestoneSummary: "阶段成果说明（必填）",
      milestoneSubmit: "提交阶段验收", milestoneSaved: "阶段成果已提交，等待客户验收。"
    },
    en: {
      title: "Construction progress record",
      progress: "Work completed this time (required)",
      materials: "Materials used (optional)",
      issues: "Issues found (optional)",
      hours: "Hours worked (optional)",
      photo: "Upload a construction photo (recommended)",
      choose: "Choose photo or take one",
      none: "No photo selected",
      save: "Save work record",
      required: "Describe the work completed.",
      large: "The photo must not exceed 10 MB.",
      saving: "Uploading and saving work record...",
      saved: "Work record saved. The customer and platform can now see it.",
      failed: "Submission failed. Try again or contact the platform."
      ,milestone: "Submit milestone", milestoneSummary: "Milestone summary (required)",
      milestoneSubmit: "Submit for stage review", milestoneSaved: "Milestone submitted for customer review."
    }
  };

  const el = (tag, props, children) => {
    const node = document.createElement(tag);
    Object.entries(props || {}).forEach(([key, value]) => {
      if (key === "className") node.className = value;
      else if (key === "text") node.textContent = value;
      else node.setAttribute(key, value);
    });
    (children || []).forEach(child => node.append(child));
    return node;
  };

  function imageMime(file) {
    if (file.type) return file.type.toLowerCase();
    const ext = (file.name.split(".").pop() || "").toLowerCase();
    return {
      jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png",
      webp: "image/webp", heic: "image/heic", heif: "image/heif"
    }[ext] || "";
  }

  function buildCard() {
    const t = copy[language()];
    const card = el("section", { id: "constructionRecordCard", className: "action-box" });
    const style = el("style", {}, []);
    style.textContent = [
      "#constructionRecordCard .wr-field{display:block;margin-top:13px;font-weight:800}",
      "#constructionRecordCard .wr-field input,#constructionRecordCard .wr-field textarea{display:block;width:100%;margin-top:7px;border:1px solid #ccd6e3;border-radius:11px;padding:12px;font:inherit;font-weight:400;background:#fff}",
      "#constructionRecordCard .wr-field textarea{min-height:88px;resize:vertical}",
      "#constructionRecordCard .wr-picker{position:relative;display:flex;align-items:center;justify-content:center;min-height:54px;margin-top:8px;padding:13px 18px;border:1px solid #8fb5a5;border-radius:12px;background:#eef8f3;color:#087a4b;font-weight:900;overflow:hidden}",
      "#constructionRecordCard .wr-picker input{position:absolute;inset:0;width:100%;height:100%;opacity:0;cursor:pointer}",
      "#constructionRecordCard .wr-file{margin-top:8px;color:#64748b;font-size:14px;word-break:break-all}",
      "#constructionRecordCard .wr-status{margin-top:12px;line-height:1.55}",
      "#constructionRecordCard .wr-success{color:#087a4b}",
      "#constructionRecordCard .wr-danger{color:#b42318}"
    ].join("");
    document.head.append(style);

    const progress = el("textarea", { id: "wrProgress", maxlength: "2000" });
    const materials = el("textarea", { id: "wrMaterials", maxlength: "1000" });
    const issues = el("textarea", { id: "wrIssues", maxlength: "1000" });
    const hours = el("input", { id: "wrHours", type: "number", min: "0", max: "24", step: "0.5" });
    const photo = el("input", { id: "wrPhoto", type: "file", accept: "image/*" });    
    const fileName = el("div", { id: "wrFileName", className: "wr-file", text: t.none });
    const button = el("button", { id: "wrSave", className: "primary", type: "button", disabled: "disabled" });
    button.textContent = t.save;
    const status = el("div", { id: "wrStatus", className: "wr-status" });
    const milestoneSummary = el("textarea", { id: "wrMilestoneSummary", maxlength: "2000" });
    const milestoneButton = el("button", { id: "wrMilestoneSubmit", className: "primary", type: "button" });
    milestoneButton.textContent = t.milestoneSubmit;
    const milestoneStatus = el("div", { id: "wrMilestoneStatus", className: "wr-status" });

    card.append(
      el("h2", { className: "section-title", text: t.title }),
      el("label", { className: "wr-field", text: t.progress }, [progress]),
      el("label", { className: "wr-field", text: t.materials }, [materials]),
      el("label", { className: "wr-field", text: t.issues }, [issues]),
      el("label", { className: "wr-field", text: t.hours }, [hours]),
      el("div", { className: "wr-field", text: t.photo }),
      el("label", { className: "wr-picker" }, [el("span", { text: t.choose }), photo]),
      fileName, button, status,
      el("h2", { className: "section-title", text: t.milestone }),
      el("label", { className: "wr-field", text: t.milestoneSummary }, [milestoneSummary]),
      milestoneButton, milestoneStatus
    );
    return { card, progress, materials, issues, hours, photo, fileName, button, status, milestoneSummary, milestoneButton, milestoneStatus };
  }

  async function initialize() {
    const query = new URLSearchParams(location.search);
    const secret = new URLSearchParams(location.hash.slice(1));
    const requestNo = query.get("request");
    const role = query.get("role") || "";
    const token = secret.get("token") || "";
    if (role !== "worker" || !requestNo || token.length < 32 || !window.echoCitySupabase) return;

    const client = window.echoCitySupabase;
    const result = await client.rpc("read_task_with_token", {
      p_request_no: requestNo, p_token: token, p_role: "worker"
    });
    if (result.error || !["in_progress", "working"].includes(result.data?.status)) return;

    const oldCard = document.getElementById("workerActionCard");
    if (oldCard) oldCard.classList.add("hidden");
    const ui = buildCard();
    (oldCard || document.getElementById("recordsCard")).insertAdjacentElement("afterend", ui.card);

    const refresh = () => {
      ui.button.disabled = ui.progress.value.trim().length < 2;
    };
    ui.progress.addEventListener("input", refresh);
    ui.photo.addEventListener("change", () => {
      ui.fileName.textContent = ui.photo.files[0]?.name || copy[language()].none;
    });

    ui.button.addEventListener("click", async () => {
      const t = copy[language()];
      const workProgress = ui.progress.value.trim();
      const file = ui.photo.files[0] || null;
      if (workProgress.length < 2) {
        ui.status.textContent = t.required;
        ui.status.className = "wr-status wr-danger";
        return;
      }
      if (file && file.size > 10485760) {
        ui.status.textContent = t.large;
        ui.status.className = "wr-status wr-danger";
        return;
      }

      ui.button.disabled = true;
      ui.status.textContent = t.saving;
      ui.status.className = "wr-status";
      try {
        let signed = null;
        let mime = null;
        if (file) {
          mime = imageMime(file);
          const sign = await client.functions.invoke("worker-process-upload", {
            body: { requestNo, token, fileName: file.name, fileSize: file.size, mimeType: mime }
          });
          if (sign.error || !sign.data?.uploadToken || !sign.data?.path) {
            throw sign.error || new Error("SIGNED_UPLOAD_FAILED");
          }
          signed = sign.data;
          const upload = await client.storage.from(signed.bucket)
            .uploadToSignedUrl(signed.path, signed.uploadToken, file, { contentType: mime });
          if (upload.error) throw upload.error;
        }

        const hoursValue = ui.hours.value === "" ? null : Number(ui.hours.value);
        const saved = await client.rpc("submit_work_record_with_token", {
          p_request_no: requestNo,
          p_token: token,
          p_work_progress: workProgress,
          p_materials_used: ui.materials.value.trim() || null,
          p_issues_found: ui.issues.value.trim() || null,
          p_work_hours: hoursValue,
          p_storage_path: signed?.path || null,
          p_file_name: file?.name || null,
          p_file_size: file?.size || null,
          p_mime_type: mime
        });
        if (saved.error) throw saved.error;

        ui.progress.value = "";
        ui.materials.value = "";
        ui.issues.value = "";
        ui.hours.value = "";
        ui.photo.value = "";
        ui.fileName.textContent = t.none;
        ui.status.textContent = t.saved;
        ui.status.className = "wr-status wr-success";
        const evidence = document.getElementById("evidenceCount");
        if (evidence && signed) location.reload();
      } catch (error) {
        console.error("work record submission error", error);
        ui.status.textContent = t.failed;
        ui.status.className = "wr-status wr-danger";
      } finally {
        refresh();
      }
    });
    ui.milestoneButton.addEventListener("click", async () => {
      const t = copy[language()];
      const summary = ui.milestoneSummary.value.trim();
      if (summary.length < 2) { ui.milestoneStatus.textContent = t.required; return; }
      ui.milestoneButton.disabled = true;
      const saved = await client.rpc("submit_milestone_with_token", { p_request_no: requestNo, p_token: token, p_summary: summary });
      if (saved.error) { ui.milestoneStatus.textContent = t.failed; ui.milestoneStatus.className = "wr-status wr-danger"; ui.milestoneButton.disabled = false; return; }
      ui.milestoneStatus.textContent = t.milestoneSaved; ui.milestoneStatus.className = "wr-status wr-success";
    });
    refresh();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initialize, { once: true });
  } else {
    initialize();
  }
})();
