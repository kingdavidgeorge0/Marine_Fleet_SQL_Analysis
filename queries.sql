-- ============================================================
-- MARINE FLEET RELIABILITY & MAINTENANCE ANALYSIS
-- Full exploratory SQL — MySQL 8
-- Cleaned and corrected from the original working session.
-- Where a bug was caught mid-analysis, the broken version is kept
-- as a comment alongside the fix — the debugging is part of the story.
-- ============================================================

-- ------------------------------------------------------------
-- 0. TABLE PREVIEWS
-- ------------------------------------------------------------
SELECT * FROM vessels;
SELECT * FROM engines;
SELECT * FROM crew;
SELECT * FROM maintenance_logs;
SELECT * FROM voyages;
SELECT * FROM incidents;
SELECT * FROM inspections;


-- ------------------------------------------------------------
-- DATA QUALITY CHECKS
-- ------------------------------------------------------------

-- Duplicate primary keys in maintenance_logs (import correctly rejects these)
SELECT maintenance_id, COUNT(*)
FROM maintenance_logs
GROUP BY maintenance_id
HAVING COUNT(*) > 1;

-- Null audit across the two columns known to have missing values
SELECT
    COUNT(*) - COUNT(cost) AS null_cost_count,
    ROUND((COUNT(*) - COUNT(cost)) * 100.0 / COUNT(*), 2) AS null_cost_pct
FROM maintenance_logs;

SELECT
    COUNT(*) - COUNT(oil_pressure_bar) AS null_oil_pressure_count,
    ROUND((COUNT(*) - COUNT(oil_pressure_bar)) * 100.0 / COUNT(*), 2) AS null_oil_pressure_pct
FROM inspections;

-- Decision: nulls are left as NULL, not deleted or imputed.
-- Deleting a row discards valid data in every other column; imputing (e.g. a
-- column average) would manufacture false precision with no reliable column
-- to estimate from. SQL aggregates (AVG/SUM/COUNT(col)) already skip NULLs.

-- Vendor casing inconsistency check
SELECT DISTINCT vendor FROM maintenance_logs;
-- A handful of rows have lowercase vendor names; normalized with UPPER()
-- in every query that groups or filters by vendor from here on.


-- ------------------------------------------------------------
-- QUESTION 1: Do older engines break down more?
-- ------------------------------------------------------------
-- Caveat: engines were installed/maintained since 1998, but maintenance
-- records only went online 2022-2025. Re-scoped to:
-- "During 2022-2025, did older engines break down more frequently?"

WITH maintenance_cte AS (
    SELECT m.engine_id, COUNT(m.maintenance_id) AS no_of_times, e.install_date
    FROM maintenance_logs m
    JOIN engines e ON m.engine_id = e.engine_id
    GROUP BY m.engine_id, e.install_date
)
SELECT YEAR(install_date) AS install_year,
       SUM(no_of_times), AVG(no_of_times), MIN(no_of_times), MAX(no_of_times)
FROM maintenance_cte
GROUP BY YEAR(install_date)
ORDER BY install_year;

-- Answer: No obvious indication that older engines break down more often.


-- ------------------------------------------------------------
-- QUESTION 2: Are older engines more expensive to maintain?
-- ------------------------------------------------------------
WITH cost_cte AS (
    SELECT m.engine_id, SUM(m.cost) AS total_repair_cost,
           AVG(m.cost) AS avg_repair_cost, e.install_date
    FROM maintenance_logs m
    JOIN engines e ON m.engine_id = e.engine_id
    GROUP BY m.engine_id, e.install_date
)
SELECT YEAR(install_date) AS install_year,
       SUM(total_repair_cost), AVG(avg_repair_cost),
       MIN(total_repair_cost), MAX(total_repair_cost)
FROM cost_cte
GROUP BY YEAR(install_date)
ORDER BY install_year;

-- Answer: No. Older engines do not cost more to maintain.


-- ------------------------------------------------------------
-- QUESTION 3: Do engines from a particular manufacturer break down more?
-- ------------------------------------------------------------
SELECT manufacturer, COUNT(incident_id) AS incident_count
FROM incidents i
JOIN engines e ON i.engine_id = e.engine_id
GROUP BY manufacturer
ORDER BY incident_count DESC;

-- Controlling for severity
SELECT manufacturer, COUNT(severity) AS severe_count
FROM incidents i
JOIN engines e ON i.engine_id = e.engine_id
WHERE severity = 'Severe'
GROUP BY manufacturer
ORDER BY severe_count DESC;

-- Controlling for installation-date spread across manufacturers (fleet-age parity check)
SELECT manufacturer,
       MAX(YEAR(install_date)) AS newest_install,
       MIN(YEAR(install_date)) AS oldest_install,
       COUNT(engine_id) AS engine_count
FROM engines
GROUP BY manufacturer;

-- See Finding #1 in README for the normalized (per-engine) version of this question.


-- ------------------------------------------------------------
-- QUESTION 4: Which vessels have more than one engine?
-- ------------------------------------------------------------

-- BUG CAUGHT: an earlier version used COUNT(...) OVER(PARTITION BY vessel_id)
-- (a window function, which preserves one row per engine) and then joined
-- that CTE back to `engines` again on vessel_id — multiplying rows
-- (e.g. a 2-engine vessel: 2 CTE rows x 2 engine rows = 4 duplicated rows).
-- Fixed by aggregating with GROUP BY instead of a window function, with
-- no extra join needed since the CTE already has everything required.

SELECT v.vessel_id, v.vessel_name,
       COUNT(e.engine_id) AS no_engines,
       GROUP_CONCAT(DISTINCT e.manufacturer SEPARATOR ', ') AS manufacturers
FROM engines e
JOIN vessels v ON e.vessel_id = v.vessel_id
GROUP BY v.vessel_id, v.vessel_name
HAVING COUNT(e.engine_id) > 1
ORDER BY no_engines DESC;

-- Answer: 41 vessels run more than one engine.


-- ------------------------------------------------------------
-- QUESTION 5: Which engine models break down the most?
-- ------------------------------------------------------------
SELECT e.engine_model, COUNT(i.incident_id) AS incident_count
FROM engines e
JOIN incidents i ON i.engine_id = e.engine_id
GROUP BY e.engine_model
ORDER BY incident_count DESC;

-- Which individual engines break down the most
SELECT engine_id, COUNT(incident_id) AS incident_count,
       GROUP_CONCAT(DISTINCT incident_type SEPARATOR ', ') AS incident_types
FROM incidents
GROUP BY engine_id
ORDER BY incident_count DESC
LIMIT 10;


-- ------------------------------------------------------------
-- QUESTION 6: What are the most frequent types of incidents?
-- ------------------------------------------------------------
SELECT incident_type,
       COUNT(CASE WHEN severity = 'Minor' THEN 1 END) AS no_of_minor,
       COUNT(CASE WHEN severity = 'Moderate' THEN 1 END) AS no_of_moderate,
       COUNT(CASE WHEN severity = 'Severe' THEN 1 END) AS no_of_severe,
       COUNT(incident_type) AS total
FROM incidents
GROUP BY incident_type
ORDER BY total DESC;


-- ------------------------------------------------------------
-- QUESTION 7 (3A): Breakdowns by severity and type
-- ------------------------------------------------------------
-- Which incident types are common but minor, or rare but severe?
SELECT incident_type,
       COUNT(CASE WHEN severity = 'Minor' THEN 1 END) AS no_of_minor,
       COUNT(CASE WHEN severity = 'Moderate' THEN 1 END) AS no_of_moderate,
       COUNT(CASE WHEN severity = 'Severe' THEN 1 END) AS no_of_severe,
       COUNT(incident_type) AS total,
       ROUND(COUNT(CASE WHEN severity = 'Severe' THEN 1 END) * 100.0 / COUNT(incident_type), 1) AS severe_pct,
       ROUND(COUNT(CASE WHEN severity = 'Minor' THEN 1 END) * 100.0 / COUNT(incident_type), 1) AS minor_pct
FROM incidents
GROUP BY incident_type
ORDER BY severe_pct DESC;

-- Finding: Electrical Fault has the lowest occurrence (60 of 459) but the
-- highest chance of being severe (23.3%). Engine Shutdown is the most
-- frequent type but has the lowest severe rate and highest minor rate.


-- ------------------------------------------------------------
-- QUESTION 8: Is there a correlation between distance traveled and breakdowns?
-- ------------------------------------------------------------
-- Fleet-wide per-vessel table (distance vs. incident count) — no CORR()
-- function in MySQL, so exported for a scatter plot in Excel/Tableau rather
-- than computed as a single coefficient here.
SELECT v.vessel_id,
       SUM(voy.distance_nm) AS total_distance,
       COUNT(DISTINCT i.incident_id) AS incident_count
FROM vessels v
LEFT JOIN voyages voy ON v.vessel_id = voy.vessel_id
LEFT JOIN incidents i ON v.vessel_id = i.vessel_id
GROUP BY v.vessel_id
ORDER BY total_distance DESC;


-- ------------------------------------------------------------
-- QUESTION 9 (1A): Which engine model has the highest breakdown rate,
-- normalized against how many engines of that model are in service?
-- ------------------------------------------------------------
-- BUG CAUGHT: original used LEFT JOIN starting FROM incidents, which drops
-- any engine model with zero incidents entirely (no incidents row to join
-- from). Fixed by starting FROM engines instead. Also
-- COUNT(DISTINCT engine_id, 2) doesn't round anything — wrapped the
-- division in ROUND(..., 2) instead.

SELECT e.engine_model,
       COUNT(DISTINCT e.engine_id) AS engine_count,
       COUNT(i.incident_id) AS incident_count,
       ROUND(COUNT(i.incident_id) / COUNT(DISTINCT e.engine_id), 2) AS incidents_per_engine
FROM engines e
LEFT JOIN incidents i ON i.engine_id = e.engine_id
GROUP BY e.engine_model
ORDER BY incidents_per_engine DESC;

-- Finding: MAN 6L23/30 has both the highest raw incident count and the
-- highest incidents-per-engine rate (5.11, vs. 1.81-2.10 for every other
-- model) — see Finding #1 in README.


-- ------------------------------------------------------------
-- QUESTION 10 (2A): Does maintenance frequency predict breakdowns?
-- ------------------------------------------------------------
-- Idea: compare each engine's average gap between consecutive maintenance
-- events against its total incident count.

-- BUG CAUGHT (join condition): original paired records with
-- `m1.maintenance_id + 1 = m2.maintenance_id`, assuming maintenance_id
-- increments by exactly 1 for consecutive records on the same engine.
-- The dataset has 42 duplicate IDs rejected on import, leaving gaps —
-- any engine with a gap at that point silently lost that interval pair.
-- Fixed with LAG() OVER (PARTITION BY engine_id ORDER BY maintenance_date),
-- which is correct regardless of ID gaps.

-- BUG CAUGHT (fan-out): original then joined the per-gap CTE directly to
-- the unaggregated `incidents` table before grouping. An engine with 10
-- gaps and 3 incidents produced 30 joined rows, so COUNT(incident_id)
-- returned 30, not 3. Fixed with COUNT(DISTINCT incident_id).

WITH gap_cte AS (
    SELECT engine_id, maintenance_date,
           DATEDIFF(
               maintenance_date,
               LAG(maintenance_date) OVER (PARTITION BY engine_id ORDER BY maintenance_date)
           ) AS date_interval
    FROM maintenance_logs
),
gap_summary AS (
    SELECT engine_id, ROUND(AVG(date_interval), 2) AS avg_gap_days
    FROM gap_cte
    WHERE date_interval IS NOT NULL
    GROUP BY engine_id
)
SELECT g.engine_id, g.avg_gap_days, COUNT(DISTINCT i.incident_id) AS incident_count
FROM gap_summary g
LEFT JOIN incidents i ON g.engine_id = i.engine_id
GROUP BY g.engine_id, g.avg_gap_days
ORDER BY avg_gap_days DESC;

-- Finding: correlation between avg_gap_days and incident_count across all
-- 181 engines is r ~ 0.03 — essentially no relationship. Reported as a
-- genuine null result rather than discarded (see Finding #4 in README).


-- ------------------------------------------------------------
-- QUESTION 11 (4A): Can inspection readings predict an incident in advance?
-- ------------------------------------------------------------
-- Baseline attempt #1 (rejected): using 'Pass' results as the baseline.
--   SELECT result, AVG(vibration_level), AVG(oil_pressure_bar), AVG(temperature_c)
--   FROM inspections WHERE result = 'Pass' GROUP BY result;
-- This is circular logic — a 'Pass' trivially correlates with no imminent
-- failure, since 'result' is itself derived from the same readings.

-- Corrected baseline: inspections that did NOT occur within 30 days before
-- any incident on that engine, compared against inspections that did.

WITH baseline AS (
    SELECT AVG(vibration_level) AS vib_base, AVG(oil_pressure_bar) AS oil_base,
           AVG(temperature_c) AS temp_base
    FROM inspections i
    WHERE NOT EXISTS (
        SELECT 1 FROM incidents c
        WHERE c.engine_id = i.engine_id
        AND DATEDIFF(c.incident_date, i.inspection_date) BETWEEN 0 AND 30
    )
),
near_incident AS (
    SELECT AVG(i.vibration_level) AS vib_near, AVG(i.oil_pressure_bar) AS oil_near,
           AVG(i.temperature_c) AS temp_near
    FROM incidents c
    JOIN inspections i ON c.engine_id = i.engine_id
        AND DATEDIFF(c.incident_date, i.inspection_date) BETWEEN 0 AND 30
)
SELECT * FROM baseline, near_incident;

-- Finding: vibration nearly doubles (4.00 -> 7.60) and oil pressure drops
-- ~36% (5.00 -> 3.18) in the 30 days before an incident — see Finding #2
-- in README.


-- ------------------------------------------------------------
-- QUESTION 12 (5A): Fuel efficiency by route region and season, combined
-- ------------------------------------------------------------
SELECT route_region, season,
       ROUND(AVG(distance_nm / fuel_consumed_tons), 2) AS avg_nm_per_ton
FROM voyages
GROUP BY route_region, season
ORDER BY avg_nm_per_ton;

-- Pivoted view for easier scanning across seasons
SELECT route_region,
    ROUND(AVG(CASE WHEN season = 'Fall' THEN distance_nm / fuel_consumed_tons END), 2) AS fall_eff,
    ROUND(AVG(CASE WHEN season = 'Spring' THEN distance_nm / fuel_consumed_tons END), 2) AS spring_eff,
    ROUND(AVG(CASE WHEN season = 'Summer' THEN distance_nm / fuel_consumed_tons END), 2) AS summer_eff,
    ROUND(AVG(CASE WHEN season = 'Winter' THEN distance_nm / fuel_consumed_tons END), 2) AS winter_eff
FROM voyages
GROUP BY route_region
ORDER BY route_region;

-- Finding: Arctic + Winter sits at 23.47 nm/ton, a 26% drop from the
-- fleet-wide average of 31.92 nm/ton — the only route/season combination
-- that stands out this sharply (see Finding #5 in README).


-- ------------------------------------------------------------
-- QUESTION 13 (6A): Shortest port pairing
-- ------------------------------------------------------------
-- BUG CAUGHT: an earlier version filtered WHERE time_taken = min_time_taken
-- AND distance_nm = min_distance. If the fastest-time voyage and the
-- shortest-distance voyage on a route aren't the same voyage, neither row
-- satisfies both conditions and the route silently disappears. Fixed with
-- DENSE_RANK() on distance alone.

WITH distance_cte AS (
    SELECT voyage_id,
           CONCAT(departure_port, ' to ', arrival_port) AS ports,
           distance_nm, departure_date, arrival_date,
           DATEDIFF(arrival_date, departure_date) AS time_taken,
           DENSE_RANK() OVER (PARTITION BY departure_port, arrival_port ORDER BY distance_nm) AS distance_rank,
           route_region
    FROM voyages
)
SELECT *
FROM distance_cte
WHERE distance_rank = 1;


-- ------------------------------------------------------------
-- QUESTION 14 (7A/8A): Longest and most frequent route
-- ------------------------------------------------------------
WITH distance_cte AS (
    SELECT voyage_id,
           CONCAT(departure_port, ' to ', arrival_port) AS ports,
           COUNT(voyage_id) OVER (PARTITION BY departure_port, arrival_port) AS no_voyages,
           AVG(distance_nm) OVER (PARTITION BY departure_port, arrival_port) AS avg_distance,
           ROUND(AVG(DATEDIFF(arrival_date, departure_date))
                 OVER (PARTITION BY departure_port, arrival_port), 2) AS avg_time,
           route_region
    FROM voyages
)
SELECT DISTINCT ports, no_voyages, avg_distance, avg_time,
       DENSE_RANK() OVER (ORDER BY avg_distance DESC) AS distance_rank,
       DENSE_RANK() OVER (ORDER BY no_voyages DESC) AS no_voyages_rank,
       DENSE_RANK() OVER (ORDER BY avg_time DESC) AS time_rank
FROM distance_cte
ORDER BY no_voyages_rank;

-- Finding: Santos -> Rotterdam is the most frequent route (102 voyages,
-- ~4,522 nm average).


-- ------------------------------------------------------------
-- QUESTION 15 (8A continued): Vendor cost comparison
-- ------------------------------------------------------------
SELECT maintenance_type,
    ROUND(AVG(CASE WHEN UPPER(vendor) = 'ATLANTIC FLEET SOLUTIONS' THEN cost END), 2) AS atlantic_avg_cost,
    ROUND(AVG(CASE WHEN UPPER(vendor) = 'BALTIC SHIP REPAIR' THEN cost END), 2) AS baltic_avg_cost,
    ROUND(AVG(CASE WHEN UPPER(vendor) = 'PACIFIC RIM MARINE' THEN cost END), 2) AS pacific_rim_avg_cost,
    ROUND(AVG(CASE WHEN UPPER(vendor) = 'SOUTHPOINT SHIP SERVICES' THEN cost END), 2) AS southpoint_avg_cost,
    ROUND(AVG(CASE WHEN UPPER(vendor) = 'POSEIDON MARINE SERVICES' THEN cost END), 2) AS poseidon_avg_cost
FROM maintenance_logs
GROUP BY maintenance_type;

-- Controlled comparison: same job type, across vendors (used in README)
SELECT UPPER(vendor) AS vendor, COUNT(*) AS n_jobs, ROUND(AVG(cost), 2) AS avg_cost
FROM maintenance_logs
WHERE cost IS NOT NULL AND maintenance_type = 'Turbocharger Overhaul'
GROUP BY UPPER(vendor)
ORDER BY avg_cost DESC;

-- Finding: Pacific Rim Marine averages $12,189.68 for a Turbocharger
-- Overhaul vs. $8,918-$9,118 for every other vendor (~33-37% higher),
-- on a comparable sample size (99 jobs) — see Finding #3 in README.


-- ------------------------------------------------------------
-- QUESTION 16 (9A): Most expensive engines / vessels to maintain
-- ------------------------------------------------------------

-- BUG CAUGHT: original ranked with DENSE_RANK() OVER (ORDER BY SUM(cost))
-- with no DESC — ranked ascending, so rank 1 was the *cheapest* engine,
-- not the most expensive.

SELECT engine_id,
       DENSE_RANK() OVER (ORDER BY SUM(cost) DESC) AS cost_rank,
       ROUND(SUM(cost), 2) AS total_cost
FROM maintenance_logs
WHERE cost IS NOT NULL
GROUP BY engine_id
ORDER BY cost_rank
LIMIT 10;

-- Most expensive vessels to maintain
WITH vme_cte AS (
    SELECT e.vessel_id, v.vessel_name, m.maintenance_id, m.engine_id,
           m.maintenance_date, m.maintenance_type, m.cost, m.vendor
    FROM maintenance_logs m
    JOIN engines e ON m.engine_id = e.engine_id
    JOIN vessels v ON e.vessel_id = v.vessel_id
)
SELECT vessel_id,
       GROUP_CONCAT(DISTINCT engine_id SEPARATOR ', ') AS engine_ids,
       DENSE_RANK() OVER (ORDER BY SUM(cost) DESC) AS cost_rank,
       ROUND(SUM(cost), 2) AS total_cost
FROM vme_cte
WHERE cost IS NOT NULL
GROUP BY vessel_id
ORDER BY cost_rank
LIMIT 10;

-- Average maintenance cost per vessel: single-engine vs. dual-engine
WITH vessel_engine_count AS (
    SELECT v.vessel_id, v.vessel_name, COUNT(DISTINCT e.engine_id) AS engine_count
    FROM vessels v
    JOIN engines e ON v.vessel_id = e.vessel_id
    GROUP BY v.vessel_id, v.vessel_name
)
SELECT vec.engine_count,
       SUM(m.cost) AS total_cost,
       COUNT(DISTINCT vec.vessel_id) AS n_vessels,
       ROUND(SUM(m.cost) / COUNT(DISTINCT vec.vessel_id), 2) AS cost_per_vessel
FROM vessel_engine_count vec
JOIN engines e ON vec.vessel_id = e.vessel_id
JOIN maintenance_logs m ON e.engine_id = m.engine_id
WHERE m.cost IS NOT NULL
GROUP BY vec.engine_count;

-- Finding: $87,554.79/vessel (single-engine, n=99) vs. $167,184.55/vessel
-- (dual-engine, n=41) — total cost scales almost exactly 2x with engine
-- count, while cost per individual job stays flat regardless of
-- configuration (see Supporting Findings in README).


-- ============================================================
-- DEAD ENDS (kept deliberately — a tested-and-rejected hypothesis
-- is still a finding worth documenting)
-- ============================================================

-- Attempted: linking an incident to the maintenance record that resolved
-- it, via matching incident_type to a plausible maintenance_type
-- (e.g. 'Turbocharger Failure' incident -> 'Turbocharger Overhaul' repair)
-- within a reasonable window afterward. No reliable match rate above
-- chance was found — the schema has no explicit foreign key linking
-- incidents to maintenance_logs, and neither date proximity nor type
-- matching recovers that relationship reliably. See "Honest Limitations"
-- in README.
