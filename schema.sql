-- =========================================================
-- Marine Fleet Operations & Maintenance — Portfolio Dataset
-- MySQL-compatible schema
-- =========================================================

CREATE DATABASE IF NOT EXISTS marine_fleet;
USE marine_fleet;

DROP TABLE IF EXISTS inspections;
DROP TABLE IF EXISTS incidents;
DROP TABLE IF EXISTS maintenance_logs;
DROP TABLE IF EXISTS voyages;
DROP TABLE IF EXISTS engines;
DROP TABLE IF EXISTS crew;
DROP TABLE IF EXISTS vessels;

CREATE TABLE vessels (
    vessel_id       INT PRIMARY KEY,
    vessel_name     VARCHAR(100),
    vessel_class    VARCHAR(50),
    build_year      INT,
    gross_tonnage   INT,
    flag_state      VARCHAR(50),
    home_port       VARCHAR(50)
);

CREATE TABLE crew (
    technician_id    INT PRIMARY KEY,
    name             VARCHAR(100),
    role             VARCHAR(50),
    years_experience INT,
    home_region      VARCHAR(50)
);

CREATE TABLE engines (
    engine_id       INT PRIMARY KEY,
    vessel_id       INT,
    engine_model    VARCHAR(50),
    manufacturer    VARCHAR(50),
    install_date    DATE,
    rated_power_kw  INT,
    FOREIGN KEY (vessel_id) REFERENCES vessels(vessel_id)
);

CREATE TABLE maintenance_logs (
    maintenance_id     INT PRIMARY KEY,
    engine_id           INT,
    maintenance_date     DATE,
    maintenance_type     VARCHAR(50),
    cost                 DECIMAL(10,2),
    vendor               VARCHAR(100),
    region               VARCHAR(50),
    technician_id        INT,
    notes                VARCHAR(255),
    FOREIGN KEY (engine_id) REFERENCES engines(engine_id),
    FOREIGN KEY (technician_id) REFERENCES crew(technician_id)
);

CREATE TABLE voyages (
    voyage_id         INT PRIMARY KEY,
    vessel_id         INT,
    departure_port    VARCHAR(50),
    arrival_port      VARCHAR(50),
    departure_date    DATE,
    arrival_date      DATE,
    distance_nm       INT,
    fuel_consumed_tons DECIMAL(8,2),
    route_region      VARCHAR(50),
    season            VARCHAR(10),
    FOREIGN KEY (vessel_id) REFERENCES vessels(vessel_id)
);

CREATE TABLE incidents (
    incident_id      INT PRIMARY KEY,
    vessel_id        INT,
    engine_id        INT,
    incident_date    DATE,
    incident_type    VARCHAR(50),
    severity         VARCHAR(20),
    downtime_hours   DECIMAL(6,1),
    FOREIGN KEY (vessel_id) REFERENCES vessels(vessel_id),
    FOREIGN KEY (engine_id) REFERENCES engines(engine_id)
);

CREATE TABLE inspections (
    inspection_id     INT PRIMARY KEY,
    engine_id         INT,
    inspection_date   DATE,
    vibration_level   DECIMAL(5,2),
    oil_pressure_bar  DECIMAL(5,2),
    temperature_c     DECIMAL(5,1),
    inspector_id      INT,
    result            VARCHAR(10),
    FOREIGN KEY (engine_id) REFERENCES engines(engine_id),
    FOREIGN KEY (inspector_id) REFERENCES crew(technician_id)
);

-- =========================================================
-- After running this schema, import each CSV via:
-- Table Data Import Wizard in MySQL Workbench (right-click
-- the schema -> Table Data Import Wizard), one file per table.
-- Import order matters because of foreign keys:
--   vessels -> crew -> engines -> maintenance_logs -> voyages
--   -> incidents -> inspections
-- =========================================================
