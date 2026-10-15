-- 00_reset.sql
-- DESTRUCTIVE: drops every KilimoPesa object in THIS schema. Run only on a scratch/demo schema.
-- Safe to run on an empty schema (nothing to drop = no error).

BEGIN
  FOR o IN (SELECT object_name, object_type
              FROM user_objects
             WHERE (object_type = 'VIEW' AND object_name IN
                      ('V_FARM_RISK_LATEST','V_LOAN_PORTFOLIO','V_PAYOUT_EVENTS',
                       'V_KPI_SUMMARY','V_LOAD_SUMMARY','V_LOAD_REJECTS'))
                OR (object_type IN ('PROCEDURE','FUNCTION') AND object_name LIKE 'KP\_%' ESCAPE '\')) LOOP
    EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' "' || o.object_name || '"';
  END LOOP;

  FOR t IN (SELECT table_name
              FROM user_tables
             WHERE table_name IN ('PAYOUTS','CLIMATE_EVENTS','LOANS','CLIMATE_SCORES',
                                  'FARM_PLOTS','FARMERS','STG_ROLE1_ROWS','STG_ROLE1_JSON',
                                  'KP_CONFIG','KP_AUDIT_LOG')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/
