-- Functional rollback verification; run only after customer service settings integration test.
\set ON_ERROR_STOP on

do $rollback$
begin
  if to_regprocedure('public.customer_service_feature_settings_v1()') is not null
     or to_regprocedure('public.set_customer_service_feature_v1(text,boolean,text)') is not null then
    raise exception 'Public settings RPC wrappers remain after rollback';
  end if;
  if to_regprocedure('private.customer_service_feature_settings_v1()') is not null
     or to_regprocedure('private.set_customer_service_feature_v1(text,boolean,text)') is not null
     or to_regprocedure('private.has_platform_permission(text)') is not null then
    raise exception 'Private settings functions remain after rollback';
  end if;
  if to_regclass('private.platform_permissions') is null
     or to_regclass('private.platform_role_permissions') is null
     or to_regclass('private.customer_service_feature_settings') is null
     or to_regclass('private.customer_service_feature_audit') is null then
    raise exception 'Rollback removed a retained configuration or audit table';
  end if;
  if (select count(*) from private.customer_service_feature_settings) <> 7 then
    raise exception 'Rollback removed feature configuration rows';
  end if;
  if (select count(*) from private.customer_service_feature_audit) < 1 then
    raise exception 'Rollback removed audit history';
  end if;
  if not (select relrowsecurity from pg_class where oid='private.customer_service_feature_settings'::regclass)
     or not (select relrowsecurity from pg_class where oid='private.customer_service_feature_audit'::regclass) then
    raise exception 'Rollback disabled RLS on retained tables';
  end if;
  if has_table_privilege('anon','private.customer_service_feature_settings','select')
     or has_table_privilege('authenticated','private.customer_service_feature_settings','select')
     or has_table_privilege('service_role','private.customer_service_feature_settings','select') then
    raise exception 'Rollback left direct table access grants';
  end if;
end $rollback$;

select 'PASS: settings RPCs removed while feature settings, private permission mappings, RLS, and append-only audit history are preserved' as result;
