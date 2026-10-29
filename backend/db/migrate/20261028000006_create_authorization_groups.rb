class CreateAuthorizationGroups < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web role';
        END IF;
      END $guard$;

      CREATE FUNCTION app_private.authorization_group_operations() RETURNS text[]
      LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $fn$
        SELECT ARRAY['consultar_monitoramentos', 'consultar_comunicacoes', 'consultar_dashboard',
          'cadastrar_monitoramento', 'editar_monitoramento', 'desativar_monitoramento',
          'consultar_agenda', 'cadastrar_compromisso', 'remarcar_compromisso', 'cancelar_compromisso']::text[]
      $fn$;

      CREATE TABLE app_private.authorization_groups (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id uuid NOT NULL REFERENCES public.tenants(id),
        name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120 AND name ~ '[^[:space:]]' AND name !~ '[[:cntrl:]]'),
        UNIQUE (tenant_id, id)
      );
      CREATE UNIQUE INDEX authorization_group_name_per_tenant
        ON app_private.authorization_groups(tenant_id, lower(name));

      CREATE TABLE app_private.authorization_group_rules (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id uuid NOT NULL,
        group_id uuid NOT NULL,
        operation text NOT NULL CHECK (operation = ANY(app_private.authorization_group_operations())),
        effect text NOT NULL CHECK (effect IN ('allow', 'deny')),
        court text CHECK (court IS NULL OR (operation = 'consultar_comunicacoes' AND court ~ '^[A-Za-z][A-Za-z0-9]{1,31}$')),
        FOREIGN KEY (tenant_id, group_id) REFERENCES app_private.authorization_groups(tenant_id, id) ON DELETE CASCADE
      );
      CREATE UNIQUE INDEX authorization_rule_per_group
        ON app_private.authorization_group_rules(tenant_id, group_id, operation, effect, COALESCE(court, ''));

      CREATE TABLE app_private.authorization_group_memberships (
        tenant_id uuid NOT NULL,
        group_id uuid NOT NULL,
        membership_id uuid NOT NULL,
        PRIMARY KEY (tenant_id, group_id, membership_id),
        FOREIGN KEY (tenant_id, group_id) REFERENCES app_private.authorization_groups(tenant_id, id) ON DELETE CASCADE,
        FOREIGN KEY (tenant_id, membership_id) REFERENCES app_private.tenant_memberships(tenant_id, id) ON DELETE CASCADE
      );
      CREATE INDEX authorization_groups_by_membership
        ON app_private.authorization_group_memberships(tenant_id, membership_id, group_id);

      -- Private tables are reachable only through the fixed definers below. FORCE
      -- RLS also covers their owner; runtime receives no direct table privileges.
      ALTER TABLE app_private.authorization_groups ENABLE ROW LEVEL SECURITY;
      ALTER TABLE app_private.authorization_groups FORCE ROW LEVEL SECURITY;
      CREATE POLICY authorization_groups_definer ON app_private.authorization_groups
        TO advocacia_migrator USING (true) WITH CHECK (true);
      ALTER TABLE app_private.authorization_group_rules ENABLE ROW LEVEL SECURITY;
      ALTER TABLE app_private.authorization_group_rules FORCE ROW LEVEL SECURITY;
      CREATE POLICY authorization_rules_definer ON app_private.authorization_group_rules
        TO advocacia_migrator USING (true) WITH CHECK (true);
      ALTER TABLE app_private.authorization_group_memberships ENABLE ROW LEVEL SECURITY;
      ALTER TABLE app_private.authorization_group_memberships FORCE ROW LEVEL SECURITY;
      CREATE POLICY authorization_memberships_definer ON app_private.authorization_group_memberships
        TO advocacia_migrator USING (true) WITH CHECK (true);

      CREATE FUNCTION app_private.valid_authorization_rule(p_rule jsonb) RETURNS boolean
      LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $fn$
      BEGIN
        IF jsonb_typeof(p_rule) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
        IF p_rule - ARRAY['operation', 'effect', 'court'] <> '{}'::jsonb
          OR NOT p_rule ?& ARRAY['operation', 'effect']
          OR jsonb_typeof(p_rule->'operation') IS DISTINCT FROM 'string'
          OR jsonb_typeof(p_rule->'effect') IS DISTINCT FROM 'string'
          OR COALESCE(jsonb_typeof(p_rule->'court'), 'null') NOT IN ('string', 'null') THEN RETURN false; END IF;
        RETURN COALESCE((p_rule->>'operation') = ANY(app_private.authorization_group_operations())
          AND (p_rule->>'effect') IN ('allow', 'deny')
          AND ((p_rule->>'court') IS NULL OR ((p_rule->>'operation') = 'consultar_comunicacoes'
            AND (p_rule->>'court') ~ '^[A-Za-z][A-Za-z0-9]{1,31}$')), false);
      END $fn$;

      -- Internal document builder has no runtime EXECUTE privilege. Its tenant
      -- argument is supplied only by the owner-checked administration function.
      CREATE FUNCTION app_private.authorization_group_document(p_tenant uuid, p_group uuid) RETURNS jsonb
      LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $fn$
        SELECT jsonb_build_object('id', grp.id, 'name', grp.name,
          'rules', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', rule.id,
            'operation', rule.operation, 'effect', rule.effect, 'court', rule.court) ORDER BY rule.id)
            FROM app_private.authorization_group_rules AS rule
            WHERE rule.tenant_id = grp.tenant_id AND rule.group_id = grp.id), '[]'::jsonb),
          'membership_ids', COALESCE((SELECT jsonb_agg(association.membership_id ORDER BY association.membership_id)
            FROM app_private.authorization_group_memberships AS association
            WHERE association.tenant_id = grp.tenant_id AND association.group_id = grp.id), '[]'::jsonb))
        FROM app_private.authorization_groups AS grp WHERE grp.tenant_id = p_tenant AND grp.id = p_group
      $fn$;

      CREATE FUNCTION app_private.manage_authorization_groups(p_action text, p_group uuid, p_input jsonb) RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        tenant uuid;
        group_identifier uuid;
        rule_identifier uuid;
        member_identifier uuid;
        group_name text;
        candidate jsonb;
        allowed_keys text[];
      BEGIN
        tenant := app_private.require_owner();
        IF p_action IS NULL OR p_action NOT IN ('catalog', 'list', 'show', 'create', 'update', 'destroy',
          'create_rule', 'update_rule', 'destroy_rule', 'assign_membership', 'remove_membership')
          OR jsonb_typeof(p_input) IS DISTINCT FROM 'object' THEN
          RAISE EXCEPTION 'Invalid group operation' USING ERRCODE = '22023';
        END IF;
        allowed_keys := CASE p_action
          WHEN 'create' THEN ARRAY['name'] WHEN 'update' THEN ARRAY['name']
          WHEN 'create_rule' THEN ARRAY['operation', 'effect', 'court']
          WHEN 'update_rule' THEN ARRAY['rule_id', 'operation', 'effect', 'court']
          WHEN 'destroy_rule' THEN ARRAY['rule_id']
          WHEN 'assign_membership' THEN ARRAY['membership_id']
          WHEN 'remove_membership' THEN ARRAY['membership_id'] ELSE ARRAY[]::text[] END;
        IF p_input - allowed_keys <> '{}'::jsonb THEN
          RAISE EXCEPTION 'Unexpected group input' USING ERRCODE = '22023';
        END IF;
        -- Serialize every permission change against protected operations, including
        -- the no-groups state where no association row exists to lock. Acquire
        -- this tenant lock before any group or membership row lock.
        PERFORM app_private.lock_authorization(p_action NOT IN ('catalog', 'list', 'show'));
        IF app_private.require_owner() IS DISTINCT FROM tenant THEN
          RAISE EXCEPTION 'Owner context changed' USING ERRCODE = '42501';
        END IF;
        IF p_action = 'catalog' THEN
          RETURN (SELECT jsonb_agg(jsonb_build_object('operation', operation,
            'scope', CASE WHEN operation = 'consultar_comunicacoes' THEN 'court' ELSE 'tenant' END)
            ORDER BY operation) FROM unnest(app_private.authorization_group_operations()) AS operation);
        ELSIF p_action = 'list' THEN
          RETURN (SELECT COALESCE(jsonb_agg(app_private.authorization_group_document(tenant, grp.id)
            ORDER BY grp.name, grp.id), '[]'::jsonb)
            FROM app_private.authorization_groups AS grp WHERE grp.tenant_id = tenant);
        END IF;
        IF p_action IN ('create', 'update') THEN
          IF jsonb_typeof(p_input->'name') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'Invalid group name' USING ERRCODE = '22023';
          END IF;
          group_name := btrim(regexp_replace(p_input->>'name', '[[:space:]]+', ' ', 'g'));
          IF length(group_name) NOT BETWEEN 1 AND 120 OR group_name ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'Invalid group name' USING ERRCODE = '22023';
          END IF;
        END IF;
        IF p_action = 'create' THEN
          INSERT INTO app_private.authorization_groups(tenant_id, name) VALUES (tenant, group_name) RETURNING id INTO group_identifier;
          IF app_private.require_owner() IS DISTINCT FROM tenant THEN
            RAISE EXCEPTION 'Owner context changed' USING ERRCODE = '42501';
          END IF;
          RETURN app_private.authorization_group_document(tenant, group_identifier);
        END IF;

        SELECT grp.id INTO group_identifier FROM app_private.authorization_groups AS grp
          WHERE grp.tenant_id = tenant AND grp.id = p_group FOR UPDATE;
        -- A lock may have waited past credential expiry or revocation. Re-evaluate
        -- the authenticated owner, rather than trusting the pre-lock result.
        IF app_private.require_owner() IS DISTINCT FROM tenant THEN
          RAISE EXCEPTION 'Owner required' USING ERRCODE = '42501';
        END IF;
        IF group_identifier IS NULL THEN RAISE EXCEPTION 'Group not found' USING ERRCODE = 'P0002'; END IF;
        IF p_action = 'show' THEN
          RETURN app_private.authorization_group_document(tenant, group_identifier);
        ELSIF p_action = 'update' THEN
          UPDATE app_private.authorization_groups SET name = group_name WHERE tenant_id = tenant AND id = group_identifier;
        ELSIF p_action = 'destroy' THEN
          DELETE FROM app_private.authorization_groups WHERE tenant_id = tenant AND id = group_identifier;
          IF app_private.require_owner() IS DISTINCT FROM tenant THEN
            RAISE EXCEPTION 'Owner context changed' USING ERRCODE = '42501';
          END IF;
          RETURN '{}'::jsonb;
        ELSIF p_action = 'create_rule' THEN
          IF NOT app_private.valid_authorization_rule(p_input) THEN
            RAISE EXCEPTION 'Invalid group rule' USING ERRCODE = '22023';
          END IF;
          INSERT INTO app_private.authorization_group_rules(tenant_id, group_id, operation, effect, court)
            VALUES (tenant, group_identifier, p_input->>'operation', p_input->>'effect', p_input->>'court');
        ELSIF p_action IN ('update_rule', 'destroy_rule') THEN
          IF jsonb_typeof(p_input->'rule_id') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'Invalid rule reference' USING ERRCODE = '22023';
          END IF;
          SELECT rule.id, jsonb_build_object('operation', rule.operation, 'effect', rule.effect, 'court', rule.court)
            INTO rule_identifier, candidate FROM app_private.authorization_group_rules AS rule
            WHERE rule.tenant_id = tenant AND rule.group_id = group_identifier AND rule.id = (p_input->>'rule_id')::uuid;
          IF rule_identifier IS NULL THEN RAISE EXCEPTION 'Rule not found' USING ERRCODE = 'P0002'; END IF;
          IF p_action = 'destroy_rule' THEN
            DELETE FROM app_private.authorization_group_rules WHERE tenant_id = tenant AND id = rule_identifier;
          ELSE
            candidate := candidate || (p_input - 'rule_id');
            IF p_input - 'rule_id' = '{}'::jsonb OR NOT app_private.valid_authorization_rule(candidate) THEN
              RAISE EXCEPTION 'Invalid group rule' USING ERRCODE = '22023';
            END IF;
            UPDATE app_private.authorization_group_rules SET operation = candidate->>'operation',
              effect = candidate->>'effect', court = candidate->>'court' WHERE tenant_id = tenant AND id = rule_identifier;
          END IF;
        ELSIF p_action IN ('assign_membership', 'remove_membership') THEN
          IF jsonb_typeof(p_input->'membership_id') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'Invalid membership reference' USING ERRCODE = '22023';
          END IF;
          SELECT membership.id INTO member_identifier FROM app_private.tenant_memberships AS membership
            WHERE membership.tenant_id = tenant AND membership.id = (p_input->>'membership_id')::uuid
              AND (p_action = 'remove_membership' OR membership.revoked_at IS NULL) FOR UPDATE;
          IF app_private.require_owner() IS DISTINCT FROM tenant THEN
            RAISE EXCEPTION 'Owner required' USING ERRCODE = '42501';
          END IF;
          IF member_identifier IS NULL THEN RAISE EXCEPTION 'Membership not found' USING ERRCODE = 'P0002'; END IF;
          IF p_action = 'assign_membership' THEN
            INSERT INTO app_private.authorization_group_memberships(tenant_id, group_id, membership_id)
              VALUES (tenant, group_identifier, member_identifier) ON CONFLICT DO NOTHING;
          ELSE
            DELETE FROM app_private.authorization_group_memberships
              WHERE tenant_id = tenant AND group_id = group_identifier AND membership_id = member_identifier;
          END IF;
        END IF;
        -- DML can wait on rows or unique indexes after the earlier decision.
        -- An expired/revoked session aborts the function and rolls it back.
        IF app_private.require_owner() IS DISTINCT FROM tenant THEN
          RAISE EXCEPTION 'Owner context changed' USING ERRCODE = '42501';
        END IF;
        RETURN app_private.authorization_group_document(tenant, group_identifier);
      END $fn$;

      -- No identity, membership or tenant parameter exists. Invalid context is an
      -- error, never []: that value deliberately enables the no-groups read policy.
      CREATE FUNCTION app_private.session_group_rules() RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE selected_membership uuid; selected_tenant uuid;
      BEGIN
        selected_tenant := app_private.lock_authorization(false);
        selected_membership := app_private.current_membership_id();
        IF selected_membership IS NULL OR selected_tenant IS NULL THEN
          RAISE EXCEPTION 'Valid membership required' USING ERRCODE = '42501';
        END IF;
        RETURN (SELECT COALESCE(jsonb_agg(group_rules.rules ORDER BY group_rules.group_id), '[]'::jsonb)
          FROM (SELECT association.group_id, COALESCE((
            SELECT jsonb_agg(jsonb_build_object('operation', rule.operation, 'effect', rule.effect, 'court', rule.court) ORDER BY rule.id)
            FROM app_private.authorization_group_rules AS rule
            WHERE rule.tenant_id = selected_tenant AND rule.group_id = association.group_id), '[]'::jsonb) AS rules
            FROM app_private.authorization_group_memberships AS association
            WHERE association.tenant_id = selected_tenant AND association.membership_id = selected_membership) AS group_rules);
      END $fn$;

      REVOKE ALL ON app_private.authorization_groups, app_private.authorization_group_rules,
        app_private.authorization_group_memberships FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_coletor;
      REVOKE ALL ON FUNCTION app_private.authorization_group_operations(), app_private.valid_authorization_rule(jsonb),
        app_private.authorization_group_document(uuid,uuid), app_private.manage_authorization_groups(text,uuid,jsonb),
        app_private.session_group_rules() FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_coletor;
      GRANT EXECUTE ON FUNCTION app_private.manage_authorization_groups(text,uuid,jsonb),
        app_private.session_group_rules() TO advocacia_runtime;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION app_private.session_group_rules();
      DROP FUNCTION app_private.manage_authorization_groups(text,uuid,jsonb);
      DROP FUNCTION app_private.authorization_group_document(uuid,uuid);
      DROP FUNCTION app_private.valid_authorization_rule(jsonb);
      DROP TABLE app_private.authorization_group_memberships;
      DROP TABLE app_private.authorization_group_rules;
      DROP TABLE app_private.authorization_groups;
      DROP FUNCTION app_private.authorization_group_operations();
    SQL
  end
end
