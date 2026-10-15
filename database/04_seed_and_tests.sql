-- 04_seed_and_tests.sql
-- Seeds demo data THROUGH the real loader (so the loader is tested too), runs the
-- end-to-end story, then prints PASS/FAIL checks.
-- Re-running this file needs 00_reset.sql + 01..03 first (loan codes are unique).

DECLARE
    v_load NUMBER;
    v_json CLOB := q'~[
 {"plot_id":"PLOT_001","farmer_code":"FARM_001","farmer_name":"Wanjiru N.","county":"Kajiado",
  "latitude":-1.8521,"longitude":36.7821,"area_hectares":2.5,"assessment_date":"2026-10-01","is_forecast":false,
  "ndvi":0.62,"rainfall_pct":110.0,"temp_stress":0.20,"drought_risk":0.10,"flood_index":0.05,
  "crs_score":82.4,"forecasted_crs":80.1},
 {"plot_id":"PLOT_002","farmer_code":"FARM_002","farmer_name":"Kiptoo L.","county":"Kajiado",
  "latitude":-1.7000,"longitude":36.9000,"area_hectares":1.8,"assessment_date":"2026-10-01","is_forecast":false,
  "ndvi":0.38,"rainfall_pct":72.0,"temp_stress":0.45,"drought_risk":0.48,
  "crs_score":67.0,"forecasted_crs":62.0},
 {"plot_id":"PLOT_003","farmer_code":"FARM_003","farmer_name":"Amina H.","county":"Kajiado",
  "latitude":-1.9500,"longitude":36.8200,"area_hectares":3.1,"assessment_date":"2026-10-01","is_forecast":false,
  "ndvi":0.21,"rainfall_pct":48.0,"temp_stress":0.70,"drought_risk":0.78,
  "crs_score":48.0,"forecasted_crs":45.0},
 {"plot_id":"PLOT_001","farmer_code":"FARM_001","farmer_name":"Wanjiru N.","county":"Kajiado",
  "latitude":-1.8521,"longitude":36.7821,"area_hectares":2.5,"assessment_date":"2026-11-01","is_forecast":true,
  "ndvi":0.55,"rainfall_pct":90.0,"temp_stress":0.30,"drought_risk":0.25,
  "crs_score":78.0},
 {"plot_id":"PLOT_999","farmer_code":"FARM_999","farmer_name":"Bad Row","county":"Kajiado",
  "latitude":-1.9,"longitude":36.8,"area_hectares":1.0,"assessment_date":"2026-10-01","is_forecast":false,
  "crs_score":140}
]~';
BEGIN
    INSERT INTO stg_role1_json (payload) VALUES (v_json) RETURNING load_id INTO v_load;
    kp_load_role1(v_load);

    kp_create_loan('LOAN-DEMO-001', 'FARM_001', 'PLOT_001', 50000, 12);
    kp_create_loan('LOAN-DEMO-002', 'FARM_002', 'PLOT_002', 30000, 12);
    kp_create_loan('LOAN-DEMO-003', 'FARM_003', 'PLOT_003', 40000, 12);

    FOR l IN (SELECT loan_code FROM loans ORDER BY loan_id) LOOP
        kp_set_loan_status(l.loan_code, 'APPROVED');
        kp_set_loan_status(l.loan_code, 'ACTIVE');
    END LOOP;

    INSERT INTO climate_events (event_code, county, event_type, observed_date,
                                index_value, threshold_value, extreme_value, description)
    VALUES ('EVT-DROUGHT-KAJIADO-2026-10', 'Kajiado', 'DROUGHT', DATE '2026-10-10',
            0.82, 0.70, 0.90, 'Demo drought event (mock data)');

    kp_trigger_payouts('EVT-DROUGHT-KAJIADO-2026-10');
    kp_trigger_payouts('EVT-DROUGHT-KAJIADO-2026-10');   -- second run must create nothing
    COMMIT;
END;
/

-- ============================================================
-- TESTS: every row should say PASS
-- ============================================================
SELECT 'T01 rate(80)=8'                  AS test, CASE WHEN kp_interest_rate(80) = 8 THEN 'PASS' ELSE 'FAIL' END AS result FROM dual
UNION ALL SELECT 'T02 rate(60)=10',        CASE WHEN kp_interest_rate(60) = 10 THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T03 rate(40)=12',        CASE WHEN kp_interest_rate(40) = 12 THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T04 rate(39.99) is NULL',CASE WHEN kp_interest_rate(39.99) IS NULL THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T05 no cliff at 80',     CASE WHEN ABS(kp_interest_rate(79.99) - kp_interest_rate(80)) <= 0.01 THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T06 loader: 4 accepted, 1 rejected',
       CASE WHEN (SELECT rows_accepted FROM v_load_summary) = 4
             AND (SELECT rows_rejected FROM v_load_summary) = 1 THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T07 reject reason = CRS_OUT_OF_RANGE',
       CASE WHEN (SELECT reject_reason FROM v_load_rejects) = 'CRS_OUT_OF_RANGE' THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T08 forecast row is not "current" (PLOT_001 crs=82.4)',
       CASE WHEN (SELECT crs FROM v_farm_risk_latest WHERE plot_code = 'PLOT_001') = 82.4 THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T09 LOAN-001: 8%, interest 4000, total 54000',
       CASE WHEN (SELECT annual_interest_rate || '/' || estimated_total_interest || '/' || estimated_total_repayment
                    FROM loans WHERE loan_code = 'LOAN-DEMO-001') = '8/4000/54000' THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T10 LOAN-002: priced on CRS 62 => 9.8%, interest 2940',
       CASE WHEN (SELECT annual_interest_rate || '/' || estimated_total_interest
                    FROM loans WHERE loan_code = 'LOAN-DEMO-002') = '9.8/2940' THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T11 LOAN-003: priced on CRS 45 => 11.5%, interest 4600',
       CASE WHEN (SELECT annual_interest_rate || '/' || estimated_total_interest
                    FROM loans WHERE loan_code = 'LOAN-DEMO-003') = '11.5/4600' THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T12 exactly one payout, for PLOT_003, amount 2800',
       CASE WHEN (SELECT COUNT(*) FROM payouts) = 1
             AND (SELECT plot_code || '/' || payout_amount FROM v_payout_events) = 'PLOT_003/2800'
            THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T13 no duplicate payouts after 2nd trigger run',
       CASE WHEN (SELECT COUNT(*) FROM (SELECT event_id, plot_id FROM payouts
                                         GROUP BY event_id, plot_id HAVING COUNT(*) > 1)) = 0
            THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T14 audit log has 6 loan transitions',
       CASE WHEN (SELECT COUNT(*) FROM kp_audit_log WHERE entity = 'LOAN') = 6 THEN 'PASS' ELSE 'FAIL' END FROM dual
UNION ALL SELECT 'T15 KPI total_plots = 3',
       CASE WHEN (SELECT total_plots FROM v_kpi_summary) = 3 THEN 'PASS' ELSE 'FAIL' END FROM dual;

-- Compile check: this must return NO ROWS. If it returns rows, send me the text column.
SELECT name, type, line, position, text FROM user_errors ORDER BY name, sequence;

-- Handy look at what Roles 3 and 4 will consume
SELECT plot_code, farmer_name, county, crs, forecasted_crs, pricing_crs, risk_band, indicative_rate
  FROM v_farm_risk_latest ORDER BY crs DESC;
