-- Disposable local Supabase Auth/JWT integration fixture only.
-- Auth users are created by GoTrue first; IDs are supplied by the test runner.
\set ON_ERROR_STOP on
begin;

insert into public.organizations(id,organization_key,name,status,created_by)
values
 ('10000000-0000-0000-0000-000000000001','jwt-test-main','JWT/RLS Integration Test Org','active', :'requester_id'),
 ('10000000-0000-0000-0000-000000000002','jwt-test-other','JWT/RLS Isolation Test Org','active', :'outsider_id');

insert into public.app_roles(id,organization_id,role_key,role_name,is_system,is_active)
values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','jwt_requester','JWT Test Requester',false,true),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','jwt_approver','JWT Test Approver',false,true),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','jwt_applier','JWT Test Applier',false,true),
 ('20000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','jwt_no_permissions','JWT Test No Permissions',false,true),
 ('20000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000002','jwt_other_org','JWT Test Other Organization',false,true);

insert into public.organization_members(id,organization_id,user_id,role_id,member_status,joined_at)
values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',:'requester_id','20000000-0000-0000-0000-000000000001','active',now()),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',:'approver_id','20000000-0000-0000-0000-000000000002','active',now()),
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001',:'apply_id','20000000-0000-0000-0000-000000000003','active',now()),
 ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001',:'unauthorized_id','20000000-0000-0000-0000-000000000004','active',now()),
 ('30000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000002',:'outsider_id','20000000-0000-0000-0000-000000000005','active',now());

insert into public.role_permissions(id,organization_id,role_id,permission_id)
select v.id,v.org_id,v.role_id,p.id
from (values
 ('40000000-0000-0000-0000-000000000001'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000001'::uuid,'module.request'),
 ('40000000-0000-0000-0000-000000000002'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000001'::uuid,'approval.approve'),
 ('40000000-0000-0000-0000-000000000003'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000001'::uuid,'module.read'),
 ('40000000-0000-0000-0000-000000000004'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000002'::uuid,'approval.approve'),
 ('40000000-0000-0000-0000-000000000005'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000002'::uuid,'module.read'),
 ('40000000-0000-0000-0000-000000000006'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000003'::uuid,'module.manage'),
 ('40000000-0000-0000-0000-000000000007'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000003'::uuid,'module.read'),
 ('40000000-0000-0000-0000-000000000008'::uuid,'10000000-0000-0000-0000-000000000001'::uuid,'20000000-0000-0000-0000-000000000003'::uuid,'audit.read'),
 ('40000000-0000-0000-0000-000000000009'::uuid,'10000000-0000-0000-0000-000000000002'::uuid,'20000000-0000-0000-0000-000000000005'::uuid,'module.read')
) as v(id,org_id,role_id,permission_key)
join public.permissions p on p.permission_key=v.permission_key;

insert into public.platform_modules(id,module_key,module_name,category,current_version,is_core,is_active)
values
 ('50000000-0000-0000-0000-000000000001','jwt_test_sales','JWT Test Sales','test','1.0.0',false,true),
 ('50000000-0000-0000-0000-000000000002','jwt_test_dependency','JWT Test Dependency','test','1.0.0',false,true);

insert into public.module_dependencies(id,module_id,depends_on_module_id,minimum_version,is_mandatory)
values
 ('60000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000002',
  '1.0.0',true);

insert into public.organization_modules(id,organization_id,module_id,status,installed_version,configuration,enabled_at,enabled_by)
values
 ('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001','active','1.0.0','{}'::jsonb,now(),:'requester_id'),
 ('70000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000002','disabled','1.0.0','{}'::jsonb,null,null);

commit;
