import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const root = process.cwd();
const html = fs.readFileSync(path.join(root, "branch-preview/index.html"), "utf8");
const locationData = fs.readFileSync(path.join(root, "branch-preview/data/bangladesh-admin-hierarchy.json"));
const ORG = "60000000-0000-0000-0000-000000000001";
const MODULE = "70000000-0000-0000-0000-000000000001";
const REQUEST = "80000000-0000-0000-0000-000000000001";
const APPROVAL = "90000000-0000-0000-0000-000000000001";

const permissions = {
  requester: ["branch.read", "module.read", "module.request"],
  approver: ["branch.read", "module.read", "approval.read", "approval.approve"],
  applier: ["branch.read", "module.read", "approval.read", "module.manage"],
  viewer: ["branch.read", "module.read", "approval.read"]
};
const state = {
  moduleStatus: "disabled",
  changes: [],
  approvals: []
};

function json(res, status, value) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(value));
}
async function body(req) {
  let raw = "";
  for await (const chunk of req) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://127.0.0.1:4173");
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/branch-preview/")) {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); res.end(html); return;
    }
    if (req.method === "GET" && url.pathname === "/data/bangladesh-admin-hierarchy.json") {
      res.writeHead(200, { "content-type": "application/json" }); res.end(locationData); return;
    }
    if (req.method === "POST" && url.pathname === "/__mock/query") {
      const input = await body(req), actor = input.actor || "viewer", perms = permissions[actor] || [];
      let rows = [];
      if (input.table === "branch_dashboard_v1") return json(res, 200, { data: { total_branches: 0, active_branches: 0, inactive_branches: 0, suspended_branches: 0, branches_with_profile: 0, total_daily_capacity: 0, active_contacts: 0 }, error: null });
      if (input.table === "platform_modules") rows = [{ id: MODULE, module_key: "browser_test_sales", module_name: "Browser Test Sales", description: "Isolated browser test module", current_version: "1.0.0", is_core: false, is_active: true }];
      if (input.table === "organization_modules") {
        if (!perms.includes("module.read")) return json(res, 403, { data: null, error: { message: "module.read required" } });
        rows = state.moduleStatus === "disabled" ? [] : [{ module_id: MODULE, status: state.moduleStatus, installed_version: "1.0.0" }];
      }
      if (input.table === "module_change_requests") {
        if (!perms.includes("module.read")) return json(res, 403, { data: null, error: { message: "module.read required" } });
        rows = state.changes;
      }
      if (input.table === "approval_requests") {
        if (!perms.includes("approval.read")) return json(res, 403, { data: null, error: { message: "approval.read required" } });
        rows = state.approvals;
      }
      return json(res, 200, { data: rows, error: null });
    }
    if (req.method === "POST" && url.pathname === "/__mock/rpc") {
      const input = await body(req), actor = input.actor || "viewer", perms = permissions[actor] || [], args = input.args || {};
      if (input.name === "current_access_context_v1") {
        return json(res, 200, { data: { organizations: [{ organization_id: ORG, organization_name: "Browser Test Organization", permissions: perms }] }, error: null });
      }
      if (input.name === "branch_list_v1") return json(res, 200, { data: [], error: null });
      if (input.name === "module_request_change_v1") {
        if (!perms.includes("module.request") || !perms.includes("module.read")) return json(res, 403, { data: null, error: { message: "module.request and module.read required" } });
        if (state.changes.some(c => ["pending", "approved"].includes(c.status))) return json(res, 409, { data: null, error: { message: "unresolved request exists" } });
        const change = { id: REQUEST, organization_id: ORG, module_id: MODULE, request_type: args.p_request_type, requested_by: actor, approval_request_id: APPROVAL, status: "pending", reason: args.p_reason, created_at: new Date().toISOString() };
        const approval = { id: APPROVAL, requested_by: actor, status: "pending", request_type: "module_change", reason: args.p_reason, expires_at: new Date(Date.now() + 86400000).toISOString(), created_at: change.created_at };
        state.changes = [change, ...state.changes]; state.approvals = [approval, ...state.approvals];
        return json(res, 200, { data: { module_change_request_id: REQUEST, approval_request_id: APPROVAL, status: "pending" }, error: null });
      }
      if (input.name === "module_approval_decide_v1") {
        if (!perms.includes("approval.approve")) return json(res, 403, { data: null, error: { message: "approval.approve required" } });
        const approval = state.approvals.find(a => a.id === args.p_approval_request_id);
        const change = state.changes.find(c => c.approval_request_id === args.p_approval_request_id);
        if (!approval || !change || approval.requested_by === actor || approval.status !== "pending") return json(res, 403, { data: null, error: { message: "independent approval required" } });
        approval.status = args.p_decision; change.status = args.p_decision;
        return json(res, 200, { data: change.id, error: null });
      }
      if (input.name === "module_apply_approved_change_v1") {
        if (!perms.includes("module.manage")) return json(res, 403, { data: null, error: { message: "module.manage required" } });
        const change = state.changes.find(c => c.id === args.p_module_change_request_id);
        const approval = state.approvals.find(a => a.id === change?.approval_request_id);
        if (!change || change.status !== "approved" || approval?.status !== "approved" || approval.requested_by === actor) return json(res, 403, { data: null, error: { message: "approved independent request required" } });
        state.moduleStatus = change.request_type === "enable" ? "active" : "disabled";
        change.status = "completed";
        return json(res, 200, { data: change.id, error: null });
      }
      return json(res, 404, { data: null, error: { message: "unknown mock RPC: " + input.name } });
    }
    res.writeHead(404); res.end("not found");
  } catch (error) {
    json(res, 500, { error: { message: error.message } });
  }
});

const mockSdk = `
(() => {
  const actor = new URLSearchParams(location.search).get("actor") || "viewer";
  class Query {
    constructor(table) { this.table = table; this.filters = {}; }
    select() { return this; }
    eq(key, value) { this.filters[key] = value; return this; }
    order() { return this; }
    limit() { return this; }
    async execute(single = false) {
      const response = await fetch("/__mock/query", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ table: this.table, filters: this.filters, actor }) });
      const result = await response.json();
      if (!response.ok) return { data: null, error: result.error || { message: "query failed" } };
      return { data: single ? (result.data?.[0] || null) : result.data, error: null };
    }
    maybeSingle() { return this.execute(true); }
    then(resolve, reject) { return this.execute(false).then(resolve, reject); }
  }
  window.supabase = {
    createClient() {
      return {
        auth: {
          getUser: async () => ({ data: { user: { id: actor, email: actor + "@example.test", email_confirmed_at: new Date().toISOString() } }, error: null }),
          onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
          signOut: async () => ({ error: null })
        },
        from: table => new Query(table),
        rpc: async (name, args) => {
          const response = await fetch("/__mock/rpc", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name, args, actor }) });
          const result = await response.json();
          return response.ok ? { data: result.data, error: null } : { data: null, error: result.error || { message: "RPC failed" } };
        }
      };
    }
  };
})();
`;

const browser = await chromium.launch({ headless: true });
let failures = [];
try {
  await new Promise(resolve => server.listen(4173, "127.0.0.1", resolve));
  async function openActor(actor, viewport = { width: 1280, height: 900 }) {
    const context = await browser.newContext({ viewport, isMobile: viewport.width < 600, hasTouch: viewport.width < 600 });
    const page = await context.newPage();
    await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0", route => route.fulfill({ status: 200, contentType: "application/javascript", body: mockSdk }));
    page.on("dialog", dialog => dialog.accept(dialog.type() === "confirm" ? undefined : "Automated lifecycle browser test"));
    await page.goto("http://127.0.0.1:4173/?actor=" + actor);
    await page.getByText("Module Lifecycle", { exact: false }).waitFor();
    await page.waitForTimeout(200);
    return { context, page };
  }

  const requester = await openActor("requester");
  const requestButton = requester.page.locator('[data-module-request="browser_test_sales"]');
  await requestButton.waitFor();
  await requestButton.click();
  await requester.page.getByText("Request জমা হয়েছে", { exact: false }).waitFor();
  if (await requester.page.locator("[data-module-decision]").count() !== 0) throw new Error("Requester saw an approval action for their own request");
  console.log("PASS: requester can submit; requester cannot approve own request");

  const approver = await openActor("approver");
  await approver.page.getByRole("button", { name: "Approve" }).waitFor();
  if (await approver.page.locator("[data-module-apply]").count() !== 0) throw new Error("Approver saw Apply without module.manage");
  await approver.page.getByRole("button", { name: "Approve" }).click();
  await approver.page.getByText("Request independently approved", { exact: false }).waitFor();
  console.log("PASS: separate approver can approve; approver cannot Apply without module.manage");

  const applier = await openActor("applier");
  await applier.page.getByRole("button", { name: "Apply approved change" }).waitFor();
  await applier.page.getByRole("button", { name: "Apply approved change" }).click();
  await applier.page.getByText("Approved module change Apply হয়েছে", { exact: false }).waitFor();
  await applier.page.getByText("active", { exact: true }).waitFor();
  console.log("PASS: separate apply actor applies approved request and module status refreshes");

  const viewer = await openActor("viewer");
  if (await viewer.page.locator("[data-module-request]").count() !== 0) throw new Error("Viewer without module.request saw Request controls");
  if (await viewer.page.locator("[data-module-decision]").count() !== 0) throw new Error("Viewer without approval.approve saw decision controls");
  if (await viewer.page.locator("[data-module-apply]").count() !== 0) throw new Error("Viewer without module.manage saw Apply controls");
  console.log("PASS: least-privilege UI hides request, approval and apply controls");

  const mobile = await openActor("viewer", { width: 390, height: 844 });
  const layout = await mobile.page.evaluate(() => ({ width: window.innerWidth, scrollWidth: document.documentElement.scrollWidth }));
  if (layout.scrollWidth > layout.width + 1) throw new Error("Mobile viewport has horizontal overflow: " + JSON.stringify(layout));
  await mobile.page.locator("#moduleLifecycle").scrollIntoViewIfNeeded();
  if (!(await mobile.page.locator("#moduleLifecycle").isVisible())) throw new Error("Module Lifecycle panel is not visible on mobile viewport");
  console.log("PASS: mobile-sized Chromium viewport has no horizontal overflow and renders Module Lifecycle");

  for (const item of [requester, approver, applier, viewer, mobile]) await item.context.close();
} catch (error) {
  failures.push(error);
  throw error;
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
