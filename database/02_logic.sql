-- 02_logic.sql  Functions and procedures
-- Run each block with "Run Script" (F5) so the "/" terminators are honoured.
-- Procedures do NOT commit: call COMMIT afterwards (APEX processes commit automatically).

-- ------------------------------------------------------------
-- Config reader
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION kp_cfg(p_code IN VARCHAR2) RETURN NUMBER IS
    v NUMBER;
BEGIN
    SELECT param_value INTO v FROM kp_config WHERE param_code = p_code;
    RETURN v;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'Missing kp_config parameter: ' || p_code);
END;
/

-- ------------------------------------------------------------
-- Pricing: linear between crs_worst and crs_best (no cliff edges).
-- crs >= crs_best => rate_best ; crs < crs_worst => NULL (manual review)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION kp_interest_rate(p_crs IN NUMBER) RETURN NUMBER IS
    v_cb NUMBER := kp_cfg('crs_best');
    v_cw NUMBER := kp_cfg('crs_worst');
    v_rb NUMBER := kp_cfg('rate_best');
    v_rw NUMBER := kp_cfg('rate_worst');
BEGIN
    IF p_crs IS NULL OR p_crs < 0 OR p_crs > 100 THEN
        RAISE_APPLICATION_ERROR(-20002, 'CRS must be between 0 and 100.');
    ELSIF p_crs >= v_cb THEN
        RETURN v_rb;
    ELSIF p_crs < v_cw THEN
        RETURN NULL;
    ELSE
        RETURN ROUND(v_rw - (p_crs - v_cw) * (v_rw - v_rb) / (v_cb - v_cw), 2);
    END IF;
END;
/

-- ------------------------------------------------------------
-- Loan creation (codes in, so APEX / API callers never juggle ids)
-- Pricing CRS = LEAST(latest OBSERVED crs, its forecasted_crs).
-- Flat interest: principal * rate * months / 1200.
-- CRS below crs_worst => loan stored as REVIEW with no rate (not an error).
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE kp_create_loan(
    p_loan_code   IN VARCHAR2,
    p_farmer_code IN VARCHAR2,
    p_plot_code   IN VARCHAR2,
    p_principal   IN NUMBER,
    p_term_months IN NUMBER DEFAULT 12
) IS
    v_farmer_id farmers.farmer_id%TYPE;
    v_plot_id   farm_plots.plot_id%TYPE;
    v_owner     farm_plots.farmer_id%TYPE;
    v_score_id  climate_scores.score_id%TYPE;
    v_pcrs      NUMBER;
    v_rate      NUMBER;
    v_interest  NUMBER(14,2);
    v_total     NUMBER(14,2);
    v_status    VARCHAR2(20);
BEGIN
    IF p_principal IS NULL OR p_principal <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Principal must be greater than zero.');
    END IF;
    IF p_term_months IS NULL OR p_term_months < 1 OR p_term_months > 120 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Term must be between 1 and 120 months.');
    END IF;

    BEGIN
        SELECT farmer_id INTO v_farmer_id FROM farmers WHERE farmer_code = p_farmer_code;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20010, 'Farmer not found: ' || p_farmer_code);
    END;

    BEGIN
        SELECT plot_id, farmer_id INTO v_plot_id, v_owner FROM farm_plots WHERE plot_code = p_plot_code;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20011, 'Plot not found: ' || p_plot_code);
    END;

    IF v_owner <> v_farmer_id THEN
        RAISE_APPLICATION_ERROR(-20012, 'Plot ' || p_plot_code || ' does not belong to farmer ' || p_farmer_code);
    END IF;

    BEGIN
        SELECT score_id, LEAST(crs, NVL(forecasted_crs, crs))
          INTO v_score_id, v_pcrs
          FROM (SELECT score_id, crs, forecasted_crs
                  FROM climate_scores
                 WHERE plot_id = v_plot_id AND is_forecast = 0
                 ORDER BY assessment_date DESC, score_id DESC)
         WHERE ROWNUM = 1;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20013, 'No observed climate score for plot ' || p_plot_code);
    END;

    v_rate := kp_interest_rate(v_pcrs);
    IF v_rate IS NULL THEN
        v_status := 'REVIEW';
    ELSE
        v_status   := 'PENDING';
        v_interest := ROUND(p_principal * (v_rate / 100) * (p_term_months / 12), 2);
        v_total    := p_principal + v_interest;
    END IF;

    INSERT INTO loans (loan_code, farmer_id, plot_id, score_id, pricing_crs, principal_amount,
                       annual_interest_rate, term_months, estimated_total_interest,
                       estimated_total_repayment, status)
    VALUES (p_loan_code, v_farmer_id, v_plot_id, v_score_id, v_pcrs, p_principal,
            v_rate, p_term_months, v_interest, v_total, v_status);
END;
/

-- ------------------------------------------------------------
-- Controlled status changes (+ audit trail)
-- Loans:   PENDING->APPROVED|DECLINED, REVIEW->DECLINED,
--          APPROVED->ACTIVE|DECLINED, ACTIVE->REPAID
--          (REVIEW loans have no rate: price manually, out of scope for demo)
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE kp_set_loan_status(p_loan_code IN VARCHAR2, p_new IN VARCHAR2) IS
    v_old loans.status%TYPE;
    v_ok  BOOLEAN;
BEGIN
    BEGIN
        SELECT status INTO v_old FROM loans WHERE loan_code = p_loan_code FOR UPDATE;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20020, 'Loan not found: ' || p_loan_code);
    END;

    v_ok := (v_old = 'PENDING'  AND p_new IN ('APPROVED','DECLINED'))
         OR (v_old = 'REVIEW'   AND p_new = 'DECLINED')
         OR (v_old = 'APPROVED' AND p_new IN ('ACTIVE','DECLINED'))
         OR (v_old = 'ACTIVE'   AND p_new = 'REPAID');
    IF NOT v_ok THEN
        RAISE_APPLICATION_ERROR(-20021, 'Illegal loan transition ' || v_old || ' -> ' || p_new);
    END IF;

    UPDATE loans SET status = p_new WHERE loan_code = p_loan_code;
    INSERT INTO kp_audit_log (entity, entity_code, old_status, new_status)
    VALUES ('LOAN', p_loan_code, v_old, p_new);
END;
/

-- Payouts: PENDING->APPROVED|REJECTED, APPROVED->PAID|REJECTED
CREATE OR REPLACE PROCEDURE kp_set_payout_status(p_payout_code IN VARCHAR2, p_new IN VARCHAR2) IS
    v_old payouts.status%TYPE;
    v_ok  BOOLEAN;
BEGIN
    BEGIN
        SELECT status INTO v_old FROM payouts WHERE payout_code = p_payout_code FOR UPDATE;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20030, 'Payout not found: ' || p_payout_code);
    END;

    v_ok := (v_old = 'PENDING'  AND p_new IN ('APPROVED','REJECTED'))
         OR (v_old = 'APPROVED' AND p_new IN ('PAID','REJECTED'));
    IF NOT v_ok THEN
        RAISE_APPLICATION_ERROR(-20031, 'Illegal payout transition ' || v_old || ' -> ' || p_new);
    END IF;

    UPDATE payouts
       SET status  = p_new,
           paid_at = CASE WHEN p_new = 'PAID' THEN SYSTIMESTAMP ELSE paid_at END
     WHERE payout_code = p_payout_code;
    INSERT INTO kp_audit_log (entity, entity_code, old_status, new_status)
    VALUES ('PAYOUT', p_payout_code, v_old, p_new);
END;
/

-- ------------------------------------------------------------
-- Payout trigger
--  * Event must have crossed its threshold (event-level gate).
--  * Only plots in the event county WITH an APPROVED/ACTIVE loan are paid.
--  * Plot-level check: the plot's own latest observed index (drought_risk for
--    DROUGHT, flood_index for FLOOD) must also reach the threshold; if the plot
--    has no such value, the event index is used.
--  * Amount = principal * payout_cap_share * (min_share + (1-min_share) * severity)
--    severity = (idx - threshold)/(extreme - threshold), capped at 1.
--  * Idempotent: re-running creates nothing new (UNIQUE event_id+plot_id).
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE kp_trigger_payouts(p_event_code IN VARCHAR2) IS
    v_event_id  climate_events.event_id%TYPE;
    v_county    climate_events.county%TYPE;
    v_type      climate_events.event_type%TYPE;
    v_index     climate_events.index_value%TYPE;
    v_threshold climate_events.threshold_value%TYPE;
    v_extreme   climate_events.extreme_value%TYPE;
    v_cap       NUMBER := kp_cfg('payout_cap_share');
    v_min       NUMBER := kp_cfg('payout_min_share');
    v_span      NUMBER;
BEGIN
    BEGIN
        SELECT event_id, county, event_type, index_value, threshold_value, extreme_value
          INTO v_event_id, v_county, v_type, v_index, v_threshold, v_extreme
          FROM climate_events
         WHERE event_code = p_event_code;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20040, 'Climate event not found: ' || p_event_code);
    END;

    IF v_index < v_threshold THEN
        RAISE_APPLICATION_ERROR(-20041, 'Threshold not reached; no payouts created.');
    END IF;

    v_span := GREATEST(v_extreme - v_threshold, 0.0001);

    INSERT INTO payouts (payout_code, event_id, plot_id, loan_id, payout_amount, status)
    SELECT 'KP-' || p_event_code || '-' || x.plot_id,
           v_event_id,
           x.plot_id,
           x.loan_id,
           ROUND(x.principal_amount * v_cap
                 * (v_min + (1 - v_min) * LEAST(1, (x.idx - v_threshold) / v_span)), 2),
           'PENDING'
      FROM (
            SELECT l.plot_id, l.loan_id, l.principal_amount,
                   CASE v_type
                        WHEN 'DROUGHT' THEN NVL(s.drought_risk, v_index)
                        ELSE NVL(s.flood_index, v_index)
                   END AS idx
              FROM (SELECT l1.*,
                           ROW_NUMBER() OVER (PARTITION BY l1.plot_id ORDER BY l1.loan_id DESC) AS rn
                      FROM loans l1
                     WHERE l1.status IN ('APPROVED','ACTIVE')) l
              JOIN farm_plots fp ON fp.plot_id = l.plot_id AND l.rn = 1
              LEFT JOIN (SELECT c.plot_id, c.drought_risk, c.flood_index,
                                ROW_NUMBER() OVER (PARTITION BY c.plot_id
                                                   ORDER BY c.assessment_date DESC, c.score_id DESC) AS rn
                           FROM climate_scores c
                          WHERE c.is_forecast = 0) s
                     ON s.plot_id = l.plot_id AND s.rn = 1
             WHERE UPPER(fp.county) = UPPER(v_county)
           ) x
     WHERE x.idx >= v_threshold
       AND NOT EXISTS (SELECT 1 FROM payouts p
                        WHERE p.event_id = v_event_id AND p.plot_id = x.plot_id);
END;
/

-- ------------------------------------------------------------
-- Role 1 JSON loader: stage -> validate -> MERGE (farmers, plots, scores)
-- Bad rows are kept in stg_role1_rows with a reject_reason (see v_load_rejects)
-- and never reach the core tables. Re-loading the same data is harmless.
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE kp_load_role1(p_load_id IN NUMBER) IS
    v_n NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_n FROM stg_role1_json WHERE load_id = p_load_id;
    IF v_n = 0 THEN
        RAISE_APPLICATION_ERROR(-20050, 'Unknown load_id: ' || p_load_id);
    END IF;

    DELETE FROM stg_role1_rows WHERE load_id = p_load_id;

    INSERT INTO stg_role1_rows
           (load_id, row_num, plot_code, farmer_code, farmer_name, county, latitude, longitude,
            area_hectares, assessment_date, is_forecast_txt, ndvi, rainfall_pct, temp_stress,
            drought_risk, flood_index, crs_score, forecasted_crs)
    SELECT s.load_id, jt.row_num, jt.plot_code, jt.farmer_code, jt.farmer_name, jt.county,
           jt.latitude, jt.longitude, jt.area_hectares,
           TO_DATE(jt.assessment_date_txt DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD'),
           LOWER(jt.is_forecast_txt), jt.ndvi, jt.rainfall_pct, jt.temp_stress,
           jt.drought_risk, jt.flood_index, jt.crs_score, jt.forecasted_crs
      FROM stg_role1_json s,
           JSON_TABLE(s.payload, '$[*]' COLUMNS (
               row_num             FOR ORDINALITY,
               plot_code           VARCHAR2(40)  PATH '$.plot_id',
               farmer_code         VARCHAR2(30)  PATH '$.farmer_code',
               farmer_name         VARCHAR2(120) PATH '$.farmer_name',
               county              VARCHAR2(80)  PATH '$.county',
               latitude            NUMBER        PATH '$.latitude',
               longitude           NUMBER        PATH '$.longitude',
               area_hectares       NUMBER        PATH '$.area_hectares',
               assessment_date_txt VARCHAR2(10)  PATH '$.assessment_date',
               is_forecast_txt     VARCHAR2(5)   PATH '$.is_forecast',
               ndvi                NUMBER        PATH '$.ndvi',
               rainfall_pct        NUMBER        PATH '$.rainfall_pct',
               temp_stress         NUMBER        PATH '$.temp_stress',
               drought_risk        NUMBER        PATH '$.drought_risk',
               flood_index         NUMBER        PATH '$.flood_index',
               crs_score           NUMBER        PATH '$.crs_score',
               forecasted_crs      NUMBER        PATH '$.forecasted_crs')) jt
     WHERE s.load_id = p_load_id;

    UPDATE stg_role1_rows
       SET reject_reason = CASE
            WHEN plot_code   IS NULL THEN 'MISSING_PLOT_ID'
            WHEN farmer_code IS NULL THEN 'MISSING_FARMER_CODE'
            WHEN county      IS NULL THEN 'MISSING_COUNTY'
            WHEN assessment_date IS NULL THEN 'BAD_OR_MISSING_DATE'
            WHEN is_forecast_txt IS NULL OR is_forecast_txt NOT IN ('true','false') THEN 'BAD_IS_FORECAST'
            WHEN crs_score IS NULL OR crs_score NOT BETWEEN 0 AND 100 THEN 'CRS_OUT_OF_RANGE'
            WHEN forecasted_crs IS NOT NULL AND forecasted_crs NOT BETWEEN 0 AND 100 THEN 'FORECAST_CRS_OUT_OF_RANGE'
            WHEN latitude IS NULL OR longitude IS NULL
              OR latitude  NOT BETWEEN -5 AND 5.5
              OR longitude NOT BETWEEN 33.5 AND 42 THEN 'COORDS_INVALID_FOR_KENYA'
            WHEN area_hectares IS NULL OR area_hectares <= 0 THEN 'BAD_AREA'
            WHEN ndvi IS NOT NULL AND ndvi NOT BETWEEN -1 AND 1 THEN 'NDVI_OUT_OF_RANGE'
            WHEN rainfall_pct IS NOT NULL AND rainfall_pct < 0 THEN 'RAINFALL_NEGATIVE'
            WHEN (temp_stress IS NOT NULL AND temp_stress NOT BETWEEN 0 AND 1)
              OR (drought_risk IS NOT NULL AND drought_risk NOT BETWEEN 0 AND 1)
              OR (flood_index  IS NOT NULL AND flood_index  NOT BETWEEN 0 AND 1) THEN 'INDEX_OUT_OF_RANGE'
            ELSE NULL
           END
     WHERE load_id = p_load_id;

    MERGE INTO farmers f
    USING (SELECT farmer_code, MAX(farmer_name) AS farmer_name, MAX(county) AS county
             FROM stg_role1_rows
            WHERE load_id = p_load_id AND reject_reason IS NULL
            GROUP BY farmer_code) r
       ON (f.farmer_code = r.farmer_code)
     WHEN MATCHED THEN UPDATE SET f.full_name = NVL(r.farmer_name, f.full_name),
                                  f.county    = r.county
     WHEN NOT MATCHED THEN INSERT (farmer_code, full_name, county)
          VALUES (r.farmer_code, NVL(r.farmer_name, r.farmer_code), r.county);

    MERGE INTO farm_plots p
    USING (SELECT x.plot_code, fm.farmer_id, x.county, x.latitude, x.longitude, x.area_hectares
             FROM (SELECT st.*,
                          ROW_NUMBER() OVER (PARTITION BY st.plot_code
                                             ORDER BY st.assessment_date DESC, st.row_num DESC) AS rn
                     FROM stg_role1_rows st
                    WHERE st.load_id = p_load_id AND st.reject_reason IS NULL) x
             JOIN farmers fm ON fm.farmer_code = x.farmer_code
            WHERE x.rn = 1) r
       ON (p.plot_code = r.plot_code)
     WHEN MATCHED THEN UPDATE SET p.county = r.county, p.latitude = r.latitude,
                                  p.longitude = r.longitude, p.area_hectares = r.area_hectares
     WHEN NOT MATCHED THEN INSERT (plot_code, farmer_id, county, latitude, longitude, area_hectares)
          VALUES (r.plot_code, r.farmer_id, r.county, r.latitude, r.longitude, r.area_hectares);

    MERGE INTO climate_scores c
    USING (SELECT pl.plot_id, x.assessment_date,
                  CASE x.is_forecast_txt WHEN 'true' THEN 1 ELSE 0 END AS is_forecast,
                  x.crs_score, x.forecasted_crs, x.ndvi, x.rainfall_pct,
                  x.temp_stress, x.drought_risk, x.flood_index
             FROM (SELECT st.*,
                          ROW_NUMBER() OVER (PARTITION BY st.plot_code, st.assessment_date, st.is_forecast_txt
                                             ORDER BY st.row_num DESC) AS rn
                     FROM stg_role1_rows st
                    WHERE st.load_id = p_load_id AND st.reject_reason IS NULL) x
             JOIN farm_plots pl ON pl.plot_code = x.plot_code
            WHERE x.rn = 1) s
       ON (c.plot_id = s.plot_id AND c.assessment_date = s.assessment_date AND c.is_forecast = s.is_forecast)
     WHEN MATCHED THEN UPDATE SET c.crs = s.crs_score, c.forecasted_crs = s.forecasted_crs,
            c.ndvi = s.ndvi, c.rainfall_pct = s.rainfall_pct, c.temp_stress = s.temp_stress,
            c.drought_risk = s.drought_risk, c.flood_index = s.flood_index
     WHEN NOT MATCHED THEN INSERT (plot_id, assessment_date, is_forecast, crs, forecasted_crs,
            ndvi, rainfall_pct, temp_stress, drought_risk, flood_index)
          VALUES (s.plot_id, s.assessment_date, s.is_forecast, s.crs_score, s.forecasted_crs,
            s.ndvi, s.rainfall_pct, s.temp_stress, s.drought_risk, s.flood_index);
END;
/
