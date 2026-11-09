import { spawnSync } from "node:child_process";

const API_URL = process.env.API_URL ?? process.env.SUPABASE_URL;
const ANON_KEY = process.env.ANON_KEY ?? process.env.PUBLISHABLE_KEY ?? process.env.SUPABASE_ANON_KEY;
const DB_URL = process.env.DB_URL ?? process.env.POSTGRES_URL;
if (!API_URL || !ANON_KEY || !DB_URL) {
  throw new Error("Local Supabase API URL, publishable/anon key and database URL are required");
}

const ORG_ID = "10000000-0000-0000-0000-000000000001";
const MODULE_ID = "50000000-0000-0000-0000-000000000001";
const DEPENDENCY_ID = "50000000-0000-0000-0000-000000000002";
const PASSWORD = "Local-Test-Pass-2026!";

async function jsonRequest(url, options = {}) {
  const response = await fetch(url, options);
  const raw = await response.text();
  let body;
  try { body = raw ? JSON.parse(raw) : null; } catch { body = raw; }
  return { response, body, raw };
}

async function createUser(label) {
  const email = `${label}@mr-rahaman.test`;
  const signup = await jsonRequest(`${API_URL}/auth/v1/signup`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD })
  });
  if (!signup.response.ok) throw new Error(`GoTrue signup failed for ${label}: ${signup.raw}`);
  const userId = signup.body?.user?.id ?? signup.body?.id;
  if (!userId) throw new Error(`GoTrue signup did not return user id for ${label}: ${signup.raw}`);

  const login = await jsonRequest(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD })
  });
  if (!login.response.ok || !login.body?.access_token) {
    throw new Error(`GoTrue password sign-in failed for ${label}: ${login.raw}`);
  }
  return { id: userId, token: login.body.access_token };
}

async function rpc(name, args, token, expected = "success") {
  const headers = { apikey: ANON_KEY, "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const { response, body, raw } = await jsonRequest(`${API_URL}/rest/v1/rpc/${name}`, {
    method: "POST", headers, body: JSON.stringify(args)
  });
  if (expected === "success" && !response.ok) {
    throw new Error(`${name} expected success, got ${response.status}: ${raw}`);
  }
  if (expected === "denied" && response.ok) {
    throw new Error(`${name} unexpectedly succeeded: ${raw}`);
  }
  return { status: response.status, body, raw };
}

function psql(sql) {
  const result = spawnSync("psql", [DB_URL, "-v", "ON_ERROR_STOP=1", "-c", sql], {
    encoding: "utf8",
    env: process.env
  });
  if (result.status !== 0) {
    throw new Error(`psql failed: ${result.stderr || result.stdout}`);
  }
  return result.stdout.trim();
}

async function restGet(path, token) {
  const { response, body, raw } = await jsonRequest(`${API_URL}/rest/v1/${path}`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` }
  });
  if (!response.ok) throw new Error(`REST GET failed ${response.status}: ${raw}`);
  return body;
}

async function main() {
  const [requester, approver, applier, unauthorized, outsider, platformOwner] = await Promise.all([
    createUser("requester"), createUser("approver"), createUser("applier"),
    createUser("unauthorized"), createUser("outsider"), createUser("platform-owner")
  ]);

  const seed = spawnSync("psql", [
    DB_URL, "-v", "ON_ERROR_STOP=1",
    "-v", `requester_id=${requester.id}`,
    "-v", `approver_id=${approver.id}`,
    "-v", `apply_id=${applier.id}`,
    "-v", `unauthorized_id=${unauthorized.id}`,
    "-v", `outsider_id=${outsider.id}`,
    "-f", "supabase/tests/fixtures/module_lifecycle_v1_jwt_seed.sql"
  ], { encoding: "utf8", env: process.env });
  if (seed.status !== 0) throw new Error(`JWT fixture seed failed: ${seed.stderr || seed.stdout}`);

  psql(`insert into public.platform_admin_roles(user_id,role_key,granted_by,expires_at,revoked_at)
    values ('${platformOwner.id}'::uuid,'platform_owner','${platformOwner.id}'::uuid,null,null);`);

  const requesterContext = await rpc("current_access_context_v1", {}, requester.token);
  const requesterOrg = requesterContext.body?.organizations?.find(org => org.organization_id === ORG_ID);
  if (!requesterOrg || !requesterOrg.permissions.includes("module.request") || !requesterOrg.permissions.includes("module.read")) {
    throw new Error("Requester access context did not return only its database-backed permissions");
  }
  if (requesterContext.body?.is_platform_owner !== false) throw new Error("Organization requester was incorrectly classified as Platform Owner");

  const approverContext = await rpc("current_access_context_v1", {}, approver.token);
  const approverOrg = approverContext.body?.organizations?.find(org => org.organization_id === ORG_ID);
  if (!approverOrg || !approverOrg.permissions.includes("approval.approve") || approverOrg.permissions.includes("module.manage")) {
    throw new Error("Approver access context permission separation is incorrect");
  }

  const unauthorizedContext = await rpc("current_access_context_v1", {}, unauthorized.token);
  const unauthorizedOrg = unauthorizedContext.body?.organizations?.find(org => org.organization_id === ORG_ID);
  if (!unauthorizedOrg || unauthorizedOrg.permissions.length !== 0) {
    throw new Error("Member without role grants received unexpected permissions");
  }

  const outsiderContext = await rpc("current_access_context_v1", {}, outsider.token);
  if (outsiderContext.body?.organizations?.some(org => org.organization_id === ORG_ID)) {
    throw new Error("Cross-organization access context leak");
  }
  console.log("PASS: current_access_context_v1 returns only caller memberships and database-derived permissions");

  const noContext = await rpc("current_access_context_v1", {}, null, "denied");
  console.log(`PASS: unauthenticated current access context denied (${noContext.status})`);

  const noToken = await rpc("module_request_change_v1", {
    p_organization_id: ORG_ID, p_module_key: "jwt_test_sales",
    p_request_type: "disable", p_reason: "Unauthenticated test"
  }, null, "denied");
  console.log(`PASS: unauthenticated RPC denied (${noToken.status})`);

  const request = await rpc("module_request_change_v1", {
    p_organization_id: ORG_ID, p_module_key: "jwt_test_sales",
    p_request_type: "disable", p_reason: "JWT/RLS lifecycle integration test"
  }, requester.token);
  const changeId = request.body?.module_change_request_id;
  const approvalId = request.body?.approval_request_id;
  if (!changeId || !approvalId) throw new Error(`Request RPC returned unexpected payload: ${request.raw}`);
  console.log("PASS: GoTrue-issued requester JWT created module request");

  await rpc("module_approval_decide_v1", {
    p_organization_id: ORG_ID, p_approval_request_id: approvalId,
    p_decision: "approved", p_comment: "self approval test"
  }, requester.token, "denied");
  console.log("PASS: requester cannot approve own request");

  await rpc("module_approval_decide_v1", {
    p_organization_id: ORG_ID, p_approval_request_id: approvalId,
    p_decision: "approved", p_comment: "unauthorized approval test"
  }, unauthorized.token, "denied");
  await rpc("module_request_change_v1", {
    p_organization_id: ORG_ID, p_module_key: "jwt_test_sales",
    p_request_type: "disable", p_reason: "Unauthorized request test"
  }, unauthorized.token, "denied");
  console.log("PASS: member without request/approval permissions denied");

  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID, p_module_change_request_id: changeId
  }, applier.token, "denied");
  console.log("PASS: pending request cannot be applied");

  await rpc("module_approval_decide_v1", {
    p_organization_id: ORG_ID, p_approval_request_id: approvalId,
    p_decision: "approved", p_comment: "independent approver"
  }, approver.token);
  console.log("PASS: independent approver JWT approved request");

  psql(`delete from public.role_permissions
    where role_id='20000000-0000-0000-0000-000000000002'::uuid
      and permission_id=(select id from public.permissions where permission_key='approval.approve');`);
  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID, p_module_change_request_id: changeId
  }, applier.token, "denied");
  psql(`insert into public.role_permissions(id,organization_id,role_id,permission_id)
    select '40000000-0000-0000-0000-000000000010'::uuid,
      '10000000-0000-0000-0000-000000000001'::uuid,
      '20000000-0000-0000-0000-000000000002'::uuid,p.id
    from public.permissions p where p.permission_key='approval.approve';`);
  console.log("PASS: revoked approver permission blocks later apply");

  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID, p_module_change_request_id: changeId
  }, applier.token);
  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID, p_module_change_request_id: changeId
  }, applier.token, "denied");
  console.log("PASS: separate apply actor succeeded; replay denied");

  const outsideRows = await restGet(
    `organization_modules?select=id&organization_id=eq.${ORG_ID}`, outsider.token
  );
  if (!Array.isArray(outsideRows) || outsideRows.length !== 0) {
    throw new Error(`Cross-organization RLS leak: ${JSON.stringify(outsideRows)}`);
  }
  console.log("PASS: cross-organization SELECT is isolated");

  const directWrite = await jsonRequest(
    `${API_URL}/rest/v1/organization_modules?id=eq.70000000-0000-0000-0000-000000000001`,
    {
      method: "PATCH",
      headers: {
        apikey: ANON_KEY, Authorization: `Bearer ${applier.token}`,
        "Content-Type": "application/json", Prefer: "return=representation"
      },
      body: JSON.stringify({ status: "active" })
    }
  );
  if (directWrite.response.ok) throw new Error("Authenticated direct organization_modules UPDATE unexpectedly succeeded");
  console.log(`PASS: authenticated direct module table UPDATE denied (${directWrite.response.status})`);

  const auditRows = await restGet(
    `module_audit_logs?select=id,action&approval_request_id=eq.${approvalId}`, applier.token
  );
  const expectedAudit = new Set([
    "MODULE_CHANGE_REQUESTED", "MODULE_CHANGE_APPROVED", "MODULE_DISABLED_AFTER_APPROVAL"
  ]);
  for (const action of expectedAudit) {
    if (!auditRows.some(row => row.action === action)) {
      throw new Error(`Audit event missing: ${action}; got ${JSON.stringify(auditRows)}`);
    }
  }
  console.log("PASS: request, approval and apply audit events visible to authorized auditor");

  const dependencyRequest = await rpc("module_request_change_v1", {
    p_organization_id: ORG_ID, p_module_key: "jwt_test_sales",
    p_request_type: "enable", p_reason: "Mandatory dependency integration test"
  }, requester.token);
  await rpc("module_approval_decide_v1", {
    p_organization_id: ORG_ID, p_approval_request_id: dependencyRequest.body.approval_request_id,
    p_decision: "approved", p_comment: "dependency test approval"
  }, approver.token);
  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID,
    p_module_change_request_id: dependencyRequest.body.module_change_request_id
  }, applier.token, "denied");
  psql(`update public.organization_modules set status='active',enabled_at=now()
    where organization_id='${ORG_ID}'::uuid
      and module_id='${DEPENDENCY_ID}'::uuid;`);
  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID,
    p_module_change_request_id: dependencyRequest.body.module_change_request_id
  }, applier.token);
  console.log("PASS: mandatory dependency blocks enable until dependency is active");

  const rejectedRequest = await rpc("module_request_change_v1", {
    p_organization_id: ORG_ID, p_module_key: "jwt_test_sales",
    p_request_type: "disable", p_reason: "Rejected request integration test"
  }, requester.token);
  await rpc("module_approval_decide_v1", {
    p_organization_id: ORG_ID, p_approval_request_id: rejectedRequest.body.approval_request_id,
    p_decision: "rejected", p_comment: "test rejection"
  }, approver.token);
  await rpc("module_apply_approved_change_v1", {
    p_organization_id: ORG_ID,
    p_module_change_request_id: rejectedRequest.body.module_change_request_id
  }, applier.token, "denied");
  console.log("PASS: rejected request cannot be applied");

  const expiredRequest = await rpc("module_request_change_v1", {
    p_organization_id: ORG_ID, p_module_key: "jwt_test_sales",
    p_request_type: "disable", p_reason: "Expired request integration test"
  }, requester.token);
  psql(`update public.approval_requests set expires_at=now()-interval '1 second'
    where id='${expiredRequest.body.approval_request_id}'::uuid;`);
  await rpc("module_approval_decide_v1", {
    p_organization_id: ORG_ID, p_approval_request_id: expiredRequest.body.approval_request_id,
    p_decision: "approved", p_comment: "expired approval test"
  }, approver.token, "denied");
  console.log("PASS: expired approval cannot be decided");

  const privateFunctionCheck = psql(`select
    (not has_function_privilege('authenticated','private.module_request_change_v1(uuid,text,text,text)','EXECUTE'))
    and (not has_function_privilege('authenticated','private.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE'))
    and (not has_function_privilege('authenticated','private.module_apply_approved_change_v1(uuid,uuid)','EXECUTE'))
    and has_function_privilege('authenticated','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
    and has_function_privilege('authenticated','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
    and has_function_privilege('authenticated','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE') as ok;`);
  if (!privateFunctionCheck.includes("t")) throw new Error("Private/public RPC execute grants are incorrect");
  console.log("PASS: authenticated can execute only the intended public lifecycle wrappers");

  const platformOwnerContext = await rpc("current_access_context_v1", {}, platformOwner.token);
  if (platformOwnerContext.body?.is_platform_owner !== true) {
    throw new Error("Initial Platform Owner was not recognized by current_access_context_v1");
  }

  await rpc("platform_owner_grant_v1", {
    p_target_user_id: requester.id,
    p_reason: "Transfer single verified Platform Owner slot"
  }, platformOwner.token);
  const secondOwnerContext = await rpc("current_access_context_v1", {}, requester.token);
  if (secondOwnerContext.body?.is_platform_owner !== true) {
    throw new Error("Transferred Platform Owner was not recognized in access context");
  }
  const formerOwnerContext = await rpc("current_access_context_v1", {}, platformOwner.token);
  if (formerOwnerContext.body?.is_platform_owner === true) {
    throw new Error("Former Platform Owner retained access after handover");
  }
  console.log("PASS: active Platform Owner atomically transfers the single Owner slot to a verified user");

  await rpc("platform_owner_revoke_v1", {
    p_target_user_id: requester.id,
    p_reason: "Attempt to remove final active Owner"
  }, requester.token, "denied");
  console.log("PASS: final active Owner cannot be revoked");

  const platformAudit = await rpc("platform_owner_audit_list_v1", { p_limit: 50 }, requester.token);
  if (!Array.isArray(platformAudit.body) || platformAudit.body.length !== 2 ||
      !platformAudit.body.some(row => row.action === "platform_owner.granted") ||
      !platformAudit.body.some(row => row.action === "platform_owner.revoked")) {
    throw new Error("Platform Owner handover audit trail is incomplete: " + platformAudit.raw);
  }
  const directPlatformAudit = await jsonRequest(`${API_URL}/rest/v1/platform_audit_logs?select=id`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${requester.token}` }
  });
  if (directPlatformAudit.response.ok) throw new Error("Authenticated user can read platform_audit_logs directly");
  console.log("PASS: paired handover events are audited and audit history is Owner-RPC-only");

  await rpc("platform_owner_audit_list_v1", { p_limit: 50 }, platformOwner.token, "denied");
  console.log("PASS: former Platform Owner loses access to platform audit history");

  console.log("PASS: local GoTrue JWT + PostgREST + PostgreSQL RLS Module Lifecycle suite completed");
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
