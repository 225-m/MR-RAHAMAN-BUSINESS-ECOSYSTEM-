-- DRAFT ONLY — DO NOT RUN AGAINST PRODUCTION
-- MR RAHAMAN Business Ecosystem / Branch Module
-- Aligns with inspected current schema; requires permission/RPC review before use.
-- This is a proposal, not an approved migration.

-- Preconditions:
-- 1) Confirm target metric catalogue and whether financials require double-entry accounting.
-- 2) Confirm the exact approval RPC contract; current approval_requests/actions tables exist,
--    but their mutation RPCs were not verified in this review.
-- 3) Add branch.target.read and branch.target.manage through permission governance,
--    then map them to roles deliberately. Do not auto-grant them.
-- 4) Confirm organization currency semantics and category catalogue.

begin;

create table if not exists public.branch_targets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid not null,
  metric_key text not null check (length(btrim(metric_key)) between 2 and 80),
  target_value numeric(18,4) not null check (target_value >= 0),
  unit text not null check (length(btrim(unit)) between 1 and 32),
  currency_code text,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft'
    check (status in ('draft','pending','approved','rejected','cancelled')),
  approval_request_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branch_targets_period_check check (period_start <= period_end),
  constraint branch_targets_branch_org_fk
    foreign key (branch_id, organization_id)
    references public.branches(id, organization_id) on delete restrict,
  constraint branch_targets_approval_org_fk
    foreign key (approval_request_id, organization_id)
    references public.approval_requests(id, organization_id) on delete restrict
);

create index if not exists branch_targets_org_branch_period_idx
  on public.branch_targets(organization_id, branch_id, period_start, period_end);
create index if not exists branch_targets_approval_idx
  on public.branch_targets(approval_request_id) where approval_request_id is not null;

alter table public.branch_targets enable row level security;
-- Policy design to be reviewed against exact target permission mappings:
create policy branch_targets_scoped_read
  on public.branch_targets for select to authenticated
  using (
    private.is_org_member(organization_id)
    and private.has_org_permission(organization_id, 'branch.target.read')
    and private.has_branch_access(organization_id, branch_id, 'branch.target.read')
  );
-- Intentionally no direct INSERT/UPDATE/DELETE policies:
-- all mutations must go through private permission-checked RPCs and audit atomically.

create table if not exists public.branch_financial_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid not null,
  entry_date date not null default current_date,
  direction text not null check (direction in ('income','expense')),
  category_key text not null check (length(btrim(category_key)) between 2 and 80),
  amount numeric(18,2) not null check (amount > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  payment_method text,
  reference_no text,
  description text,
  status text not null default 'draft'
    check (status in ('draft','pending_approval','posted','void')),
  approval_request_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  posted_by uuid references auth.users(id) on delete restrict,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branch_financial_posted_fields_check
    check ((status = 'posted' and posted_by is not null and posted_at is not null)
        or (status <> 'posted')),
  constraint branch_financial_branch_org_fk
    foreign key (branch_id, organization_id)
    references public.branches(id, organization_id) on delete restrict,
  constraint branch_financial_approval_org_fk
    foreign key (approval_request_id, organization_id)
    references public.approval_requests(id, organization_id) on delete restrict
);

create index if not exists branch_financial_org_branch_date_idx
  on public.branch_financial_entries(organization_id, branch_id, entry_date desc);
create index if not exists branch_financial_posted_report_idx
  on public.branch_financial_entries(organization_id, branch_id, entry_date)
  where status = 'posted';

alter table public.branch_financial_entries enable row level security;
create policy branch_financial_entries_scoped_read
  on public.branch_financial_entries for select to authenticated
  using (
    private.is_org_member(organization_id)
    and private.has_org_permission(organization_id, 'finance.read')
    and private.has_branch_access(organization_id, branch_id, 'finance.read')
  );
-- Intentionally no direct INSERT/UPDATE/DELETE policies:
-- write/post/void/reverse operations must be private RPCs using finance.manage.
-- Posted entries must be immutable; correction must be a separately audited reversal.

-- NOTE: This transaction is intentionally not followed by COMMIT in this draft.
-- Do not apply until preconditions, permission registry, RPCs, tests and rollback are approved.
rollback;
