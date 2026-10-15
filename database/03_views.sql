-- 03_views.sql  Stable interface for Roles 3 (dashboard) and 4 (interfaces).
-- Column names here are the API contract: add columns freely, never rename/remove.

-- Latest OBSERVED score per plot (forecast rows are ignored for "current").
CREATE OR REPLACE VIEW v_farm_risk_latest AS
SELECT
    fp.plot_id, fp.plot_code, f.farmer_id, f.farmer_code, f.full_name AS farmer_name,
    fp.county, fp.latitude, fp.longitude, fp.area_hectares,
    cs.score_id, cs.assessment_date,
    cs.crs, cs.forecasted_crs,
    LEAST(cs.crs, NVL(cs.forecasted_crs, cs.crs)) AS pricing_crs,
    cs.ndvi, cs.rainfall_pct,
    GREATEST(0, 100 - cs.rainfall_pct) AS rainfall_deficit_pct,   -- derived: 0 when rain >= normal
    cs.temp_stress, cs.drought_risk, cs.flood_index,
    CASE
        WHEN cs.crs IS NULL THEN 'NO DATA'
        WHEN cs.crs >= 80   THEN 'RESILIENT'
        WHEN cs.crs >= 60   THEN 'MODERATE'
        WHEN cs.crs >= 40   THEN 'VULNERABLE'
        ELSE 'HIGH RISK'
    END AS risk_band,
    CASE WHEN cs.crs IS NULL THEN NULL
         ELSE kp_interest_rate(LEAST(cs.crs, NVL(cs.forecasted_crs, cs.crs)))
    END AS indicative_rate
FROM farm_plots fp
JOIN farmers f ON f.farmer_id = fp.farmer_id
LEFT JOIN (SELECT c.*,
                  ROW_NUMBER() OVER (PARTITION BY c.plot_id
                                     ORDER BY c.assessment_date DESC, c.score_id DESC) AS rn
             FROM climate_scores c
            WHERE c.is_forecast = 0) cs
       ON cs.plot_id = fp.plot_id AND cs.rn = 1;

CREATE OR REPLACE VIEW v_loan_portfolio AS
SELECT l.loan_id, l.loan_code, l.farmer_id, f.farmer_code, f.full_name AS farmer_name,
       l.plot_id, fp.plot_code, fp.county,
       l.pricing_crs, cs.crs AS scored_crs, cs.forecasted_crs,
       l.principal_amount, l.annual_interest_rate, l.term_months,
       l.estimated_total_interest, l.estimated_total_repayment, l.status, l.created_at
FROM loans l
JOIN farmers f     ON f.farmer_id = l.farmer_id
JOIN farm_plots fp ON fp.plot_id  = l.plot_id
LEFT JOIN climate_scores cs ON cs.score_id = l.score_id;

CREATE OR REPLACE VIEW v_payout_events AS
SELECT p.payout_id, p.payout_code, ce.event_code, ce.event_type, ce.county, ce.observed_date,
       ce.index_value, ce.threshold_value, ce.extreme_value,
       fp.plot_id, fp.plot_code, f.full_name AS farmer_name,
       p.loan_id, l.loan_code, p.payout_amount, p.status, p.triggered_at, p.paid_at
FROM payouts p
JOIN climate_events ce ON ce.event_id = p.event_id
JOIN farm_plots fp     ON fp.plot_id  = p.plot_id
JOIN farmers f         ON f.farmer_id = fp.farmer_id
JOIN loans l           ON l.loan_id   = p.loan_id;

CREATE OR REPLACE VIEW v_kpi_summary AS
SELECT
    (SELECT COUNT(*) FROM farm_plots)                                        AS total_plots,
    (SELECT ROUND(AVG(crs), 2) FROM v_farm_risk_latest)                      AS average_latest_crs,
    (SELECT COUNT(*) FROM v_farm_risk_latest WHERE risk_band = 'HIGH RISK')  AS high_risk_plots,
    (SELECT COUNT(*) FROM loans WHERE status IN ('PENDING','REVIEW','APPROVED','ACTIVE')) AS open_loans,
    (SELECT NVL(SUM(principal_amount), 0) FROM loans WHERE status IN ('APPROVED','ACTIVE')) AS live_loan_principal,
    (SELECT COUNT(*) FROM payouts WHERE status IN ('PENDING','APPROVED'))    AS pending_payouts,
    (SELECT NVL(SUM(payout_amount), 0) FROM payouts WHERE status IN ('PENDING','APPROVED')) AS pending_payout_amount
FROM dual;

-- Data-quality visibility for the Role 1 hand-off
CREATE OR REPLACE VIEW v_load_summary AS
SELECT load_id,
       COUNT(*)                                              AS rows_total,
       SUM(CASE WHEN reject_reason IS NULL THEN 1 ELSE 0 END)     AS rows_accepted,
       SUM(CASE WHEN reject_reason IS NOT NULL THEN 1 ELSE 0 END) AS rows_rejected
FROM stg_role1_rows
GROUP BY load_id;

CREATE OR REPLACE VIEW v_load_rejects AS
SELECT load_id, row_num, plot_code, farmer_code, assessment_date, crs_score, reject_reason
FROM stg_role1_rows
WHERE reject_reason IS NOT NULL;

-- ------------------------------------------------------------
-- OPTIONAL: REST endpoints via ORDS AutoREST (Autonomous DB / APEX).
-- auto_rest_auth => FALSE makes them PUBLIC READ: fine for a demo on mock data,
-- never for real farmer data. If this step errors, enable the same four views
-- in Database Actions > REST instead.
-- ------------------------------------------------------------
BEGIN
    ORDS.ENABLE_SCHEMA(p_enabled => TRUE);
    FOR v IN (SELECT column_value AS name
                FROM TABLE(sys.odcivarchar2list('V_FARM_RISK_LATEST','V_LOAN_PORTFOLIO',
                                                'V_PAYOUT_EVENTS','V_KPI_SUMMARY'))) LOOP
        ORDS.ENABLE_OBJECT(p_enabled        => TRUE,
                           p_schema         => SYS_CONTEXT('USERENV','CURRENT_SCHEMA'),
                           p_object         => v.name,
                           p_object_type    => 'VIEW',
                           p_object_alias   => LOWER(v.name),
                           p_auto_rest_auth => FALSE);
    END LOOP;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ORDS step skipped: ' || SQLERRM);
END;
/
