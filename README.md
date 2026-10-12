# Marine Fleet Reliability & Maintenance Analysis

A SQL-driven analysis of a 140-vessel marine fleet, examining engine reliability, maintenance economics, and operational efficiency using MySQL. Built to answer the kind of questions a fleet operations manager would actually ask: which engines fail most, which vendors are overcharging, and whether inspection data can predict a breakdown before it happens.

## Dataset

- **140 vessels** (5 classes: Ro-Ro Ferry, General Cargo, Oil Tanker, Container Ship, Bulk Carrier) across 7 related tables
- **181 engines**, 90 crew members, ~4,200 maintenance records, ~4,600 voyages, 459 incidents, ~14,300 inspection readings
- 2022–2025 operational window (engines installed as early as 1998 — see Data Quality Notes)
- Full schema: [`schema.sql`](schema.sql) · Data dictionary: [`data_dictionary.md`](data_dictionary.md)

**Schema overview** — `engines` is the relational hub, connecting vessels to maintenance, incidents, and inspections:

```
vessels ──< engines ──< maintenance_logs
                   ├──< incidents
                   └──< inspections
vessels ──< voyages
crew ──< maintenance_logs, inspections
```

## Data Quality Process

Before analysis, every table was checked for nulls, duplicates, and referential integrity. Two real issues surfaced:

- **42 duplicate primary keys** in `maintenance_logs` — resolved by keeping the first occurrence (MySQL's own primary key constraint rejects re-inserting the rest on import).
- **Nulls in `cost` (1%) and `oil_pressure_bar` (2%)** — left as `NULL` rather than deleted or imputed. Deleting the row would discard valid data in every other column; imputing (e.g. with a column average) would manufacture false precision with no other field in the dataset that could reasonably estimate the missing value. SQL aggregates (`AVG`, `SUM`, `COUNT(col)`) already skip `NULL`s automatically, so no further handling was needed for most queries.

**A note on record order vs. event order:** `maintenance_id` reflects *insertion* order, not chronological order of the maintenance event. Two engines maintained in the same real-world period can have IDs far apart if their records were loaded in different batches. Every time-ordered analysis below uses `ORDER BY maintenance_date` explicitly rather than relying on ID sequence — a subtle bug that silently produces plausible-looking but wrong results if missed.

## Key Findings

### 1. One engine model drives a disproportionate share of breakdowns

```sql
SELECT e.engine_model,
       COUNT(DISTINCT e.engine_id) AS engine_count,
       COUNT(i.incident_id) AS incident_count,
       ROUND(COUNT(i.incident_id) / COUNT(DISTINCT e.engine_id), 2) AS incidents_per_engine
FROM engines e
LEFT JOIN incidents i ON i.engine_id = e.engine_id
GROUP BY e.engine_model
ORDER BY incidents_per_engine DESC;
```

| engine_model | engine_count | incident_count | incidents_per_engine |
|---|---|---|---|
| MAN 6L23/30 | 35 | 179 | **5.11** |
| Bergen C25:33 | 40 | 79 | 1.98 |
| Caterpillar 3512 | 46 | 84 | 1.83 |
| Wartsila 32 | 31 | 56 | 1.81 |
| MaK M32 | 29 | 61 | 2.10 |

MAN 6L23/30 breaks down **2.4× more often per engine** than the next-highest model — not a marginal difference, and normalized by fleet share (`LEFT JOIN` + `COUNT(DISTINCT engine_id)`) so it isn't just a raw-count artifact of having more of them in service.

### 2. Inspection readings spike before a breakdown — a real leading indicator

```sql
WITH baseline AS (
    SELECT AVG(vibration_level) AS vib_base, AVG(oil_pressure_bar) AS oil_base
    FROM inspections i
    WHERE NOT EXISTS (
        SELECT 1 FROM incidents c
        WHERE c.engine_id = i.engine_id
        AND DATEDIFF(c.incident_date, i.inspection_date) BETWEEN 0 AND 30
    )
),
near_incident AS (
    SELECT AVG(i.vibration_level) AS vib_near, AVG(i.oil_pressure_bar) AS oil_near
    FROM incidents c
    JOIN inspections i ON c.engine_id = i.engine_id
        AND DATEDIFF(c.incident_date, i.inspection_date) BETWEEN 0 AND 30
)
SELECT * FROM baseline, near_incident;
```

| | vibration_level | oil_pressure_bar |
|---|---|---|
| Baseline (no incident in next 30 days) | 4.00 | 5.00 |
| Within 30 days before an incident | **7.60** | **3.18** |

Vibration readings nearly **double**, and oil pressure drops by **~36%**, in the month before an engine fails — a pattern that could realistically feed an early-warning threshold. The baseline deliberately excludes any inspection within 30 days of an incident (not "Pass" results — an earlier pass was tried as the baseline and rejected as circular logic, since a pass trivially correlates with no imminent failure).

### 3. One maintenance vendor consistently overcharges for identical work

```sql
SELECT UPPER(vendor) AS vendor, COUNT(*) AS n_jobs, ROUND(AVG(cost),2) AS avg_cost
FROM maintenance_logs
WHERE cost IS NOT NULL AND maintenance_type = 'Turbocharger Overhaul'
GROUP BY UPPER(vendor)
ORDER BY avg_cost DESC;
```

| vendor | jobs (Turbocharger Overhaul) | avg_cost |
|---|---|---|
| **Pacific Rim Marine** | 99 | **$12,189.68** |
| Baltic Ship Repair | 75 | $9,117.82 |
| Poseidon Marine Services | 84 | $9,111.34 |
| Atlantic Fleet Solutions | 108 | $8,988.98 |
| SouthPoint Ship Services | 86 | $8,918.11 |

Pacific Rim Marine charges **~33–37% more** than every other vendor for the identical job type, with a large enough sample (99 jobs) to rule out a few outliers skewing the average. The gap holds across the vendor's overall average too ($4,768/job vs. $3,327–$3,563 for others), so it isn't explained by doing a different mix of work.

### 4. Does maintenance frequency predict breakdowns? — No detectable relationship

```sql
WITH gap_cte AS (
    SELECT engine_id, maintenance_date,
           DATEDIFF(maintenance_date, LAG(maintenance_date) OVER (PARTITION BY engine_id ORDER BY maintenance_date)) AS date_interval
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
GROUP BY g.engine_id, g.avg_gap_days;
```

Correlation between average days-between-maintenance and incident count across all 181 engines: **r ≈ 0.03** — effectively no relationship. Worth reporting as-is rather than discarding: an earlier version of this query had a join bug (pairing consecutive `maintenance_id`s instead of consecutive `maintenance_date`s per engine, which breaks silently whenever an ID gap exists) that would have produced a misleading result. The corrected version is the one shown above.

### Supporting findings
- **Fuel efficiency drops 26% on the Arctic route in Winter** (23.47 nm/ton vs. a fleet-wide average of 31.92 nm/ton) — the only route/season combination that stands out this sharply.
- **Total maintenance cost scales almost exactly 2× with engine count** ($87,555/vessel for single-engine vessels vs. $167,185/vessel for dual-engine vessels), while cost *per job* is statistically flat regardless of configuration — the total scales with volume of work, not price per job.
- **Electrical Fault is the rarest incident type (60 of 459) but has the highest severity rate (23.3% severe)** — infrequent but disproportionately dangerous when it occurs, versus Engine Shutdown, which is more common and more often minor.

## Limitations

- **No explicit link between an incident and the maintenance event that resolved it.** The schema has no foreign key connecting them. Both date-proximity and incident-type/maintenance-type matching were tested as possible inference methods and neither produced a reliable signal — reported here as a tested-and-rejected hypothesis, not silently dropped. A production schema would add a `resolved_by_maintenance_id` column to close this gap.
- **Maintenance records only begin in 2022, while engines were installed as early as 1998.** Any "lifetime cost" or "age vs. reliability" question is only valid within the observed 2022–2025 window, not across an engine's full service life — treated throughout as a digitization cutoff (a plausible real-world "the tracking system went live in 2022" scenario) rather than missing data to patch over.

## Tech Stack
MySQL 8 · MySQL Workbench · CTEs, window functions (`LAG`, `DENSE_RANK`, `RANK`), correlated subqueries, `EXISTS`/`NOT EXISTS`, conditional aggregation (`CASE WHEN` pivots)
