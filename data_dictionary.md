# Data Dictionary — Marine Fleet Operations & Maintenance

A synthetic dataset simulating fleet operations for a mid-size marine operator, spanning **2022–2025**. Framed as if feeding a maintenance-cost and reliability dashboard for a fleet operations manager.

## Tables

### `vessels`
One row per ship in the fleet.
| Column | Type | Description |
|---|---|---|
| vessel_id | INT (PK) | Unique vessel identifier |
| vessel_name | VARCHAR | Vessel name |
| vessel_class | VARCHAR | Bulk Carrier, Container Ship, Oil Tanker, General Cargo, Ro-Ro Ferry |
| build_year | INT | Year the vessel was built |
| gross_tonnage | INT | Gross tonnage |
| flag_state | VARCHAR | Country of registration |
| home_port | VARCHAR | Vessel's home port |

### `crew`
Technicians, engineers, and inspectors who service the fleet.
| Column | Type | Description |
|---|---|---|
| technician_id | INT (PK) | Unique crew member identifier |
| name | VARCHAR | Full name |
| role | VARCHAR | Maintenance Technician, Chief Engineer, Inspector, Marine Surveyor |
| years_experience | INT | Years of professional experience |
| home_region | VARCHAR | Primary operating region |

### `engines`
One or more engines per vessel.
| Column | Type | Description |
|---|---|---|
| engine_id | INT (PK) | Unique engine identifier |
| vessel_id | INT (FK) | References vessels.vessel_id |
| engine_model | VARCHAR | Engine model |
| manufacturer | VARCHAR | Engine manufacturer |
| install_date | DATE | Date engine was installed |
| rated_power_kw | INT | Rated power output (kW) |

### `maintenance_logs`
Every maintenance event performed on an engine.
| Column | Type | Description |
|---|---|---|
| maintenance_id | INT (PK) | Unique maintenance record identifier |
| engine_id | INT (FK) | References engines.engine_id |
| maintenance_date | DATE | Date of the service |
| maintenance_type | VARCHAR | Routine Inspection, Oil Change, Fuel Injector Service, Turbocharger Overhaul, Cylinder Head Repair, Cooling System Service, Emergency Repair |
| cost | DECIMAL | Cost of the service (USD) |
| vendor | VARCHAR | Servicing company |
| region | VARCHAR | Region where service was performed |
| technician_id | INT (FK) | References crew.technician_id |
| notes | VARCHAR | Free-text notes (mostly blank) |

### `voyages`
Individual voyages made by each vessel.
| Column | Type | Description |
|---|---|---|
| voyage_id | INT (PK) | Unique voyage identifier |
| vessel_id | INT (FK) | References vessels.vessel_id |
| departure_port / arrival_port | VARCHAR | Ports of departure and arrival |
| departure_date / arrival_date | DATE | Voyage dates |
| distance_nm | INT | Distance traveled, nautical miles |
| fuel_consumed_tons | DECIMAL | Fuel consumed during the voyage |
| route_region | VARCHAR | Primary operating region of the route |
| season | VARCHAR | Season of departure |

### `incidents`
Mechanical incidents / failures logged against an engine.
| Column | Type | Description |
|---|---|---|
| incident_id | INT (PK) | Unique incident identifier |
| vessel_id | INT (FK) | References vessels.vessel_id |
| engine_id | INT (FK) | References engines.engine_id |
| incident_date | DATE | Date of the incident |
| incident_type | VARCHAR | Engine Shutdown, Fuel System Failure, Overheating, Turbocharger Failure, Electrical Fault, Vibration Anomaly |
| severity | VARCHAR | Minor, Moderate, Severe |
| downtime_hours | DECIMAL | Hours of downtime caused |

### `inspections`
Routine sensor/inspection readings taken on engines (independent of incidents).
| Column | Type | Description |
|---|---|---|
| inspection_id | INT (PK) | Unique inspection identifier |
| engine_id | INT (FK) | References engines.engine_id |
| inspection_date | DATE | Date of inspection |
| vibration_level | DECIMAL | Vibration reading (0–10 scale) |
| oil_pressure_bar | DECIMAL | Oil pressure reading (bar) |
| temperature_c | DECIMAL | Engine temperature (°C) |
| inspector_id | INT (FK) | References crew.technician_id |
| result | VARCHAR | Pass / Fail |

## Known Data Quality Notes
This dataset intentionally includes realistic imperfections you'll want to handle before analysis:
- A small number of duplicate rows in `maintenance_logs`
- Inconsistent text casing in `home_port` and `vendor` fields
- A handful of missing values in `cost` and `oil_pressure_bar`

## A Note on Findings
This dataset has several non-obvious patterns planted in it on purpose — some visible with basic aggregation, others requiring window functions or multi-table joins to surface. They are not documented here. Query your way to them.
