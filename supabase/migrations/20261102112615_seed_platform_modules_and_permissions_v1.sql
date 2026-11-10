BEGIN;

INSERT INTO public.platform_modules
  (module_key, module_name, description, category, current_version, is_core)
VALUES
  ('organization_management','Organization Management','Organizations, branches and business profile','core','1.0.0',true),
  ('identity_access','Identity & Access','Members, roles, invitations and branch access','core','1.0.0',true),
  ('module_registry','Module Registry','Install, enable, disable and configure modules','core','1.0.0',true),
  ('approval_governance','Approval Governance','Approval requests and controlled changes','core','1.0.0',true),
  ('audit_security','Audit & Security','Audit trail and security review','core','1.0.0',true),
  ('business_dashboard','Business Dashboard','Operational overview and KPIs','business','1.0.0',false),
  ('reports_analytics','Reports & Analytics','Business reports and analytics','business','1.0.0',false),
  ('inventory_management','Inventory Management','Stock, warehouse and item control','business','1.0.0',false),
  ('sales_management','Sales Management','Sales orders, invoices and customers','business','1.0.0',false),
  ('purchase_management','Purchase Management','Suppliers and purchase orders','business','1.0.0',false),
  ('finance_accounting','Finance & Accounting','Cash, bank, expenses and accounting','business','1.0.0',false),
  ('hr_payroll','HR & Payroll','Staff, attendance and payroll','business','1.0.0',false),
  ('crm','Customer Relationship','Customer records and follow-ups','business','1.0.0',false),
  ('notifications','Notifications','In-app and external notifications','platform','1.0.0',false),
  ('file_documents','Files & Documents','Document metadata and file workflows','platform','1.0.0',false)
ON CONFLICT (module_key) DO UPDATE SET
  module_name = EXCLUDED.module_name,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  current_version = EXCLUDED.current_version,
  is_core = EXCLUDED.is_core,
  updated_at = now();

INSERT INTO public.permissions (permission_key, description, module_key)
VALUES
  ('organization.read','View organization profile','organization_management'),
  ('organization.update','Update organization profile','organization_management'),
  ('branch.read','View branches','organization_management'),
  ('branch.manage','Create and manage branches','organization_management'),
  ('member.read','View organization members','identity_access'),
  ('member.invite','Invite organization members','identity_access'),
  ('member.manage','Manage member status and assignments','identity_access'),
  ('role.read','View roles','identity_access'),
  ('role.manage','Create and manage roles','identity_access'),
  ('permission.read','View permission catalogue','identity_access'),
  ('branch.access.read','View member branch access','identity_access'),
  ('branch.access.manage','Manage member branch access','identity_access'),
  ('module.read','View module registry and status','module_registry'),
  ('module.request','Request module changes','module_registry'),
  ('module.manage','Approve and execute module changes','module_registry'),
  ('approval.read','View approval requests','approval_governance'),
  ('approval.approve','Approve or reject eligible requests','approval_governance'),
  ('approval.manage','Manage approval workflow configuration','approval_governance'),
  ('audit.read','Read audit history','audit_security'),
  ('security.review','Review security posture and incidents','audit_security'),
  ('dashboard.read','View business dashboard','business_dashboard'),
  ('reports.read','View reports and analytics','reports_analytics'),
  ('inventory.read','View inventory and stock','inventory_management'),
  ('inventory.manage','Manage inventory and stock','inventory_management'),
  ('sales.read','View sales records','sales_management'),
  ('sales.manage','Manage sales records','sales_management'),
  ('purchase.read','View purchase records','purchase_management'),
  ('purchase.manage','Manage purchases and suppliers','purchase_management'),
  ('finance.read','View finance and accounting records','finance_accounting'),
  ('finance.manage','Manage finance and accounting records','finance_accounting'),
  ('hr.read','View HR and payroll records','hr_payroll'),
  ('hr.manage','Manage HR and payroll records','hr_payroll'),
  ('crm.read','View customer relationship records','crm'),
  ('crm.manage','Manage customer relationship records','crm'),
  ('notification.manage','Configure notification channels','notifications'),
  ('document.read','View document records','file_documents'),
  ('document.manage','Manage document records and workflows','file_documents')
ON CONFLICT (permission_key) DO UPDATE SET
  description = EXCLUDED.description,
  module_key = EXCLUDED.module_key;

COMMIT;

