-- Schema chunk 1 - paste into the Supabase SQL Editor and run.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20250201000001_schemas.sql =====
CREATE SCHEMA IF NOT EXISTS rep_raw;
CREATE SCHEMA IF NOT EXISTS rep_staging;
CREATE SCHEMA IF NOT EXISTS rep_warehouse;

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;


-- ===== 20250201000002_rep_raw.sql =====
-- Landing zone tables. All columns TEXT; salesforce_id is the Salesforce record Id unique per object.
-- Populated by the ingest Edge Functions or run-ingest.js via upsert on salesforce_id.
-- All column additions from incremental migrations are merged into the CREATE TABLE statements here.

CREATE TABLE rep_raw.academic_record (
    salesforce_id              TEXT UNIQUE,
    row_id                     INTEGER,
    person_id                  TEXT,   -- Person__c (Master-Detail to Contact)
    school_institution_id      TEXT,   -- School_Institution__c (Lookup to School)
    district_id                TEXT,   -- District__c
    district_name              TEXT,   -- District_Name__c
    country_name               TEXT,   -- CountryName__c (Formula Text)
    contact_record_type        TEXT,   -- ContactRecordType__c (Formula Text)
    record_type_id             TEXT,
    academic_record_type       TEXT,   -- RecordType.Name; used in staging to split School vs Post School
    form                       TEXT,
    year                       TEXT,
    received_financial_support TEXT,
    repeated                   TEXT,
    accommodation              TEXT,
    attendance_issues          TEXT,
    attendance_issues_detail   TEXT,
    donor_code_id              TEXT,   -- Donor_Code__c → dim_roc_donor
    project_code_id            TEXT,   -- Project_Codes__c → dim_roc_project_code
    donor_activity_id          TEXT,   -- Donor_Activity__c → dim_roc_donor_activity
    date_dropped_out           TEXT,
    start_date                 TEXT,
    end_date                   TEXT,
    unique_id                  TEXT
);

CREATE TABLE rep_raw.contacts (
    salesforce_id               TEXT UNIQUE,
    row_id                      INTEGER,
    record_type_id              TEXT,
    record_type_name            TEXT,   -- RecordType.Name; used for CAMA derivation
    gender                      TEXT,   -- Contact_Gender__c
    country_id                  TEXT,   -- Country__c (Lookup ID)
    country_name                TEXT,   -- CountryName__c
    district_id                 TEXT,   -- District__c (Lookup ID)
    wg_difficulty_overall       TEXT,
    lg_social_support_recipient TEXT,
    active_on_bursary           TEXT,
    date_joined_cama            TEXT,
    school_id                   TEXT,   -- School__c
    orphan_status               TEXT,
    donor_activity_id           TEXT,   -- Donor_Activity__c → dim_roc_donor_activity
    donor_code_id               TEXT,   -- Donor_Code__c → dim_roc_donor
    project_code_id             TEXT    -- Project_Codes__c → dim_roc_project_code
);

CREATE TABLE rep_raw.schools (
    salesforce_id                TEXT UNIQUE,
    row_id                       INTEGER,
    school_name                  TEXT,   -- Name
    province                     TEXT,   -- Province__c (Formula Text)
    district_id                  TEXT,   -- District__c (Master-Detail ID)
    district_name                TEXT,   -- DistrictName__c (Formula Text)
    country                      TEXT,   -- Country__c (Formula Text)
    school_type                  TEXT,
    secondary_school_type        TEXT,
    accommodation_type           TEXT,
    date_camfed_began_support    TEXT,
    number_of_active_lgs         TEXT,   -- Number_of_active_LGs_at_this_school__c
    school_active_on_bursary     TEXT,
    active_partner_school        TEXT,
    ever_been_partner_school     TEXT,
    affiliated_school            TEXT,
    cpp_in_place                 TEXT,
    snf_only_school              TEXT,
    monitoring_school            TEXT,
    gea_school                   TEXT,
    merp                         TEXT,
    twc                          TEXT,
    latitude                     TEXT,   -- Geo_Point__Latitude__s
    longitude                    TEXT,   -- Geo_Point__Longitude__s
    donor_id                     TEXT,   -- Donor__c → dim_roc_donor
    donor_2_id                   TEXT,   -- X2nd_Donor__c
    donor_3_id                   TEXT,   -- X3rd_Donor__c
    unique_id                    TEXT,
    record_type_id               TEXT,   -- RecordTypeId
    cpp_committee_present        TEXT,   -- CPP_Committe_Present__c (sic)
    cpp_posted                   TEXT,   -- CPP_Posted__c
    bursary_clients_current_year TEXT,   -- Bursary_Clients_Current_Year__c
    cama_supported_cohort        TEXT,   -- CAMA_Supported_Cohort__c
    country_number               TEXT,   -- CountryNumber__c
    district_code                TEXT,   -- District_ID__c (school's own district code, not FK)
    grades_covered               TEXT,   -- Grades_Covered__c
    latest_mv_date               TEXT,   -- Latest_MV_Date_to_School__c
    latest_tm_update             TEXT,   -- Latest_TM_Update__c
    pupil_council_present        TEXT,   -- Pupil_Council_Present__c
    research_participation       TEXT,   -- Research_participation__c
    resources_received           TEXT,   -- Resources_Received__c
    school_donor                 TEXT,   -- School_Donor__c
    year_lg_programme_started    TEXT    -- Year_LG_Programme_started__c
);

CREATE TABLE rep_raw.guides (
    salesforce_id                  TEXT UNIQUE,
    row_id                         INTEGER,
    contact_id                     TEXT,   -- Contact__c (Master-Detail)
    school_id                      TEXT,   -- School__c
    district_id                    TEXT,   -- District__c
    guide_status                   TEXT,
    guide_type                     TEXT,
    guide_specialty                TEXT,   -- Guide_Speciality__c
    guide_dropout_reason           TEXT,
    date_joined_guide_programme    TEXT,
    date_completed_guide_programme TEXT,   -- Date_CompletedLeft_Guide_Programme__c
    trained_in_climate_education   TEXT,
    donor_id                       TEXT,   -- Donor__c → dim_roc_donor
    guide_name                     TEXT,   -- Name
    contact_record_type            TEXT    -- RecordType.Name from Contact relationship
);

CREATE TABLE rep_raw.cama_members (
    salesforce_id                 TEXT UNIQUE,
    row_id                        INTEGER,
    contact_id                    TEXT,
    school_id_code                TEXT,
    schoolinstitution_school_name TEXT,
    districtschool                TEXT,
    country_country_name          TEXT,
    full_name                     TEXT,
    date_joined_cama              TEXT,
    partner_school                TEXT
);

CREATE TABLE rep_raw.countries (
    salesforce_id TEXT UNIQUE,
    row_id        INTEGER,
    country_name  TEXT,   -- Name
    unique_id     TEXT    -- Unique_ID__c
);

CREATE TABLE rep_raw.districts (
    salesforce_id             TEXT UNIQUE,
    row_id                    INTEGER,
    country_id                TEXT,   -- Country__c (Master-Detail ID)
    district_name             TEXT,   -- Name
    province                  TEXT,
    terrain                   TEXT,
    active_partner_district   TEXT,
    date_camfed_began_work    TEXT,
    country_name              TEXT,   -- CountryName__c (Formula Text)
    region_id                 TEXT,   -- Region__c → dim_roc_geography
    unique_id                 TEXT,
    active_schools            TEXT,
    inactive_schools          TEXT,
    partner_schools           TEXT,
    primary_partner_schools   TEXT,
    secondary_partner_schools TEXT,
    total_schools             TEXT
);

CREATE TABLE rep_raw.grant_recipients (
    salesforce_id       TEXT UNIQUE,
    row_id              INTEGER,
    person_id           TEXT,   -- Person__c (Lookup to Contact)
    district_id         TEXT,   -- District__c (Formula Text in source)
    country             TEXT,   -- Country__c (Formula Text)
    record_type_id      TEXT,
    amount_given        TEXT,
    status              TEXT,
    grant_name          TEXT,   -- Name
    donor_id            TEXT,   -- Donor__c → dim_roc_donor
    unique_id           TEXT,
    grant_date          TEXT,   -- Date__c
    contact_record_type TEXT    -- RecordType.Name from Contact relationship
);

CREATE TABLE rep_raw.loan_recipients (
    salesforce_id       TEXT UNIQUE,
    row_id              INTEGER,
    loan_name           TEXT,   -- Name (Auto Number)
    district            TEXT,   -- District__c (Formula Text)
    country             TEXT,   -- Country__c (Formula Text)
    loan_type_id        TEXT,   -- Loan_Type__c (Lookup)
    record_type_id      TEXT,
    loan_value          TEXT,   -- Loan_Value__c
    disbursal_date      TEXT,
    currency_iso_code   TEXT,
    kiva_client_id      TEXT,
    donor_code_id       TEXT,   -- Donor_Code__c → dim_roc_donor
    historical          TEXT,
    written_off         TEXT,
    active              TEXT,
    completed           TEXT,
    default_loan        TEXT,   -- Default__c (reserved word renamed)
    delinquent          TEXT,
    default_date        TEXT,
    repayment_term      TEXT,
    contact_record_id   TEXT,   -- Contact_Record_ID__c (Formula Text)
    repayment_status    TEXT,
    group_loan          TEXT,
    loan_status         TEXT,   -- Loan_Status__c
    status              TEXT,   -- Status__c
    contact_record_type TEXT,   -- RecordType.Name from Contact relationship
    client_id           TEXT    -- Client_ID__c
);

CREATE TABLE rep_raw.dimension_1_roc (
    salesforce_id     TEXT UNIQUE,
    row_id            INTEGER,
    active            TEXT,
    available_country TEXT,
    description       TEXT,
    name              TEXT,
    reporting_code    TEXT
);

CREATE TABLE rep_raw.dimension_2_roc (
    salesforce_id     TEXT UNIQUE,
    row_id            INTEGER,
    active            TEXT,
    available_country TEXT,
    description       TEXT,
    name              TEXT,
    reporting_code    TEXT
);

CREATE TABLE rep_raw.dimension_3_roc (
    salesforce_id     TEXT UNIQUE,
    row_id            INTEGER,
    active            TEXT,
    available_country TEXT,
    description       TEXT,
    name              TEXT,
    reporting_code    TEXT,
    start_date        TEXT,
    end_date          TEXT
);

CREATE TABLE rep_raw.dimension_4_roc (
    salesforce_id     TEXT UNIQUE,
    row_id            INTEGER,
    active            TEXT,
    available_country TEXT,
    description       TEXT,
    name              TEXT,
    reporting_code    TEXT,
    dimension_3_id    TEXT   -- Dimension_3__c (parent Dimension_3_ROC__c ID)
);

CREATE TABLE rep_raw.all_kpis (
    salesforce_id   TEXT UNIQUE,
    row_id          INTEGER,
    batch_id        TEXT,
    kpi_no          TEXT,
    indicator_group TEXT,
    indicator       TEXT,
    disaggregation1 TEXT,
    disaggregation2 TEXT,
    updated_date    TEXT,
    year_of_kpis    TEXT,
    value_type      TEXT,
    ghana           TEXT,
    malawi          TEXT,
    tanzania        TEXT,
    zambia          TEXT,
    zimbabwe        TEXT,
    total           TEXT
);

CREATE TABLE rep_raw.level_one_kpis (
    salesforce_id          TEXT UNIQUE,
    row_id                 INTEGER,
    batch_id               TEXT,
    country                TEXT,
    year                   TEXT,
    kpi                    TEXT,
    school_level           TEXT,
    annual_newly_supported TEXT,
    type                   TEXT,
    gender                 TEXT,
    disaggregation_gender  TEXT,
    value                  TEXT
);


-- ===== 20250201000003_rep_warehouse_dims.sql =====
-- Dimension tables (structure only). Data is populated by the ETL procedures.
-- dim_date is seeded separately in 20250201000003_dim_date_seed.sql.
--
-- dim_school, dim_contact, and dim_roc_* use partial unique indexes (not full UNIQUE)
-- so multiple SCD Type 2 versions of the same entity can coexist,
-- with only one current row enforced per business key.

CREATE TABLE rep_warehouse.dim_date (
    id           INTEGER  PRIMARY KEY,  -- YYYYMMDD e.g. 20240115
    date_value   DATE     NOT NULL UNIQUE,
    year         SMALLINT NOT NULL,
    quarter      SMALLINT NOT NULL,
    month        SMALLINT NOT NULL,
    month_name   TEXT     NOT NULL,
    week_of_year SMALLINT NOT NULL,
    day          SMALLINT NOT NULL,
    day_of_week  SMALLINT NOT NULL,    -- 0 = Sunday, 6 = Saturday
    day_name     TEXT     NOT NULL,
    is_weekend   BOOLEAN  NOT NULL
);

-- ── ROC Dimension tables ─────────────────────────────────────────────────────
-- Four-level donor/reporting attribution hierarchy from Salesforce.
--   Dim 1 (Geography)      ← District.Region__c lookup
--   Dim 2 (Project Code)   ← Academic_Record.Project_Codes__c, Contact.Project_Codes__c
--   Dim 3 (Donor)          ← Academic_Record.Donor_Code__c, Loan.Donor_Code__c, etc.
--   Dim 4 (Donor Activity) ← Academic_Record.Donor_Activity__c; child of Dim 3

CREATE TABLE rep_warehouse.dim_roc_geography (
    id                 SERIAL      PRIMARY KEY,
    source_roc_id      TEXT        NOT NULL,
    name               TEXT,
    reporting_code     TEXT,
    available_country  TEXT,
    active             BOOLEAN,
    scd_effective_from DATE,
    scd_effective_to   DATE,
    scd_is_current     BOOLEAN     NOT NULL DEFAULT true,
    scd_version        INTEGER     NOT NULL DEFAULT 1,
    lin_source_system  TEXT,
    lin_source_file    TEXT,
    lin_load_batch_id  TEXT,
    lin_inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash  TEXT,
    lin_superseded_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX uix_dim_roc_geography_current
    ON rep_warehouse.dim_roc_geography (source_roc_id)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_roc_geography_code
    ON rep_warehouse.dim_roc_geography (reporting_code)
    WHERE scd_is_current = true;


CREATE TABLE rep_warehouse.dim_roc_project_code (
    id                 SERIAL      PRIMARY KEY,
    source_roc_id      TEXT        NOT NULL,
    name               TEXT,
    reporting_code     TEXT,
    available_country  TEXT,
    active             BOOLEAN,
    scd_effective_from DATE,
    scd_effective_to   DATE,
    scd_is_current     BOOLEAN     NOT NULL DEFAULT true,
    scd_version        INTEGER     NOT NULL DEFAULT 1,
    lin_source_system  TEXT,
    lin_source_file    TEXT,
    lin_load_batch_id  TEXT,
    lin_inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash  TEXT,
    lin_superseded_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX uix_dim_roc_project_code_current
    ON rep_warehouse.dim_roc_project_code (source_roc_id)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_roc_project_code_code
    ON rep_warehouse.dim_roc_project_code (reporting_code)
    WHERE scd_is_current = true;


CREATE TABLE rep_warehouse.dim_roc_donor (
    id                 SERIAL      PRIMARY KEY,
    source_roc_id      TEXT        NOT NULL,
    name               TEXT,
    reporting_code     TEXT,
    available_country  TEXT,
    active             BOOLEAN,
    start_date         DATE,
    end_date           DATE,
    scd_effective_from DATE,
    scd_effective_to   DATE,
    scd_is_current     BOOLEAN     NOT NULL DEFAULT true,
    scd_version        INTEGER     NOT NULL DEFAULT 1,
    lin_source_system  TEXT,
    lin_source_file    TEXT,
    lin_load_batch_id  TEXT,
    lin_inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash  TEXT,
    lin_superseded_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX uix_dim_roc_donor_current
    ON rep_warehouse.dim_roc_donor (source_roc_id)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_roc_donor_code
    ON rep_warehouse.dim_roc_donor (reporting_code)
    WHERE scd_is_current = true;


CREATE TABLE rep_warehouse.dim_roc_donor_activity (
    id                 SERIAL      PRIMARY KEY,
    source_roc_id      TEXT        NOT NULL,
    donor_id           INTEGER     REFERENCES rep_warehouse.dim_roc_donor(id),
    name               TEXT,
    reporting_code     TEXT,
    available_country  TEXT,
    active             BOOLEAN,
    scd_effective_from DATE,
    scd_effective_to   DATE,
    scd_is_current     BOOLEAN     NOT NULL DEFAULT true,
    scd_version        INTEGER     NOT NULL DEFAULT 1,
    lin_source_system  TEXT,
    lin_source_file    TEXT,
    lin_load_batch_id  TEXT,
    lin_inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash  TEXT,
    lin_superseded_at  TIMESTAMPTZ
);

CREATE UNIQUE INDEX uix_dim_roc_donor_activity_current
    ON rep_warehouse.dim_roc_donor_activity (source_roc_id)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_roc_donor_activity_code
    ON rep_warehouse.dim_roc_donor_activity (reporting_code)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_roc_donor_activity_donor
    ON rep_warehouse.dim_roc_donor_activity (donor_id);


-- ── Core dimensions ──────────────────────────────────────────────────────────

CREATE TABLE rep_warehouse.dim_geography (
    id                  SERIAL      PRIMARY KEY,
    country             TEXT        NOT NULL,
    province            TEXT,
    district            TEXT,
    is_country          BOOLEAN     NOT NULL DEFAULT false,
    roc_geography_id    INTEGER     REFERENCES rep_warehouse.dim_roc_geography(id),
    scd_effective_from  DATE,
    scd_effective_to    DATE,
    scd_is_current      BOOLEAN     NOT NULL DEFAULT true,
    scd_version         INTEGER     NOT NULL DEFAULT 1,
    lin_source_system   TEXT,
    lin_source_file     TEXT,
    lin_load_batch_id   TEXT,
    lin_inserted_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash   TEXT,
    lin_superseded_at   TIMESTAMPTZ,
    UNIQUE (country, province, district, scd_version)
);

-- Partial unique index so country-level rows (NULL province/district) are
-- deduplicated correctly despite NULL != NULL in standard UNIQUE constraints.
CREATE UNIQUE INDEX uix_dim_geography_country_only
    ON rep_warehouse.dim_geography (country)
    WHERE province IS NULL AND district IS NULL AND scd_is_current = true;

CREATE INDEX idx_dim_geography_country
    ON rep_warehouse.dim_geography (country);

CREATE INDEX idx_dim_geography_current
    ON rep_warehouse.dim_geography (country, province, district)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_geography_roc_geo
    ON rep_warehouse.dim_geography (roc_geography_id);


CREATE TABLE rep_warehouse.dim_school (
    id                        SERIAL   PRIMARY KEY,
    source_school_id          TEXT     NOT NULL,
    school_name               TEXT,
    geography_id              INTEGER  REFERENCES rep_warehouse.dim_geography(id),
    province                  TEXT,
    district                  TEXT,
    country                   TEXT,
    school_type               TEXT,
    accommodation_type        TEXT,
    date_camfed_began_support TIMESTAMP,
    active_on_bursary         BOOLEAN,
    cpp_in_place              BOOLEAN,
    snf_only                  BOOLEAN,
    monitoring_school         BOOLEAN,
    gea_school                BOOLEAN,
    merp                      BOOLEAN,
    active_partner_school     BOOLEAN,
    affiliated_school         BOOLEAN,
    latitude                  NUMERIC,
    longitude                 NUMERIC,
    roc_donor_id              INTEGER  REFERENCES rep_warehouse.dim_roc_donor(id),
    scd_effective_from        DATE,
    scd_effective_to          DATE,
    scd_is_current            BOOLEAN  NOT NULL DEFAULT true,
    scd_version               INTEGER  NOT NULL DEFAULT 1,
    lin_source_system         TEXT,
    lin_source_file           TEXT,
    lin_load_batch_id         TEXT,
    lin_inserted_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash         TEXT,
    lin_superseded_at         TIMESTAMPTZ
);

CREATE UNIQUE INDEX uix_dim_school_current
    ON rep_warehouse.dim_school (source_school_id)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_school_geography
    ON rep_warehouse.dim_school (geography_id);

CREATE INDEX idx_dim_school_roc_donor
    ON rep_warehouse.dim_school (roc_donor_id);


CREATE TABLE rep_warehouse.dim_contact (
    id                          SERIAL   PRIMARY KEY,
    source_contact_id           TEXT     NOT NULL,
    country                     TEXT,
    gender                      TEXT,
    wg_difficulty_overall       TEXT,
    lg_social_support_recipient BOOLEAN,
    active_on_bursary           BOOLEAN,
    orphan_status               TEXT,
    district_of_origin          TEXT,
    district_of_residence       TEXT,
    birth_date                  DATE,
    roc_donor_id                INTEGER  REFERENCES rep_warehouse.dim_roc_donor(id),
    roc_project_code_id         INTEGER  REFERENCES rep_warehouse.dim_roc_project_code(id),
    roc_donor_activity_id       INTEGER  REFERENCES rep_warehouse.dim_roc_donor_activity(id),
    scd_effective_from          DATE,
    scd_effective_to            DATE,
    scd_is_current              BOOLEAN  NOT NULL DEFAULT true,
    scd_version                 INTEGER  NOT NULL DEFAULT 1,
    lin_source_system           TEXT,
    lin_source_file             TEXT,
    lin_load_batch_id           TEXT,
    lin_inserted_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash           TEXT,
    lin_superseded_at           TIMESTAMPTZ
);

CREATE UNIQUE INDEX uix_dim_contact_current
    ON rep_warehouse.dim_contact (source_contact_id)
    WHERE scd_is_current = true;

CREATE INDEX idx_dim_contact_source_id
    ON rep_warehouse.dim_contact (source_contact_id);


CREATE TABLE rep_warehouse.dim_kpi (
    id                 SERIAL      PRIMARY KEY,
    source_kpi_id      TEXT,
    kpi_group          TEXT,
    indicator          TEXT,
    scd_effective_from DATE,
    scd_effective_to   DATE,
    scd_is_current     BOOLEAN     NOT NULL DEFAULT true,
    scd_version        INTEGER     NOT NULL DEFAULT 1,
    lin_source_system  TEXT,
    lin_source_file    TEXT,
    lin_load_batch_id  TEXT,
    lin_inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash  TEXT,
    lin_superseded_at  TIMESTAMPTZ,
    UNIQUE (source_kpi_id, scd_version)
);

CREATE INDEX idx_dim_kpi_source_id
    ON rep_warehouse.dim_kpi (source_kpi_id)
    WHERE scd_is_current = true;


-- ===== 20250201000004_dim_date_seed.sql =====
-- Static reference table: one row per day from 1990-01-01 to 2030-12-31.
-- Never truncated by ETL runs.

INSERT INTO rep_warehouse.dim_date
    (id, date_value, year, quarter, month, month_name,
     week_of_year, day, day_of_week, day_name, is_weekend)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::integer,
    d::date,
    EXTRACT(YEAR    FROM d)::smallint,
    EXTRACT(QUARTER FROM d)::smallint,
    EXTRACT(MONTH   FROM d)::smallint,
    TRIM(TO_CHAR(d, 'Month')),
    EXTRACT(WEEK    FROM d)::smallint,
    EXTRACT(DAY     FROM d)::smallint,
    EXTRACT(DOW     FROM d)::smallint,
    TRIM(TO_CHAR(d, 'Day')),
    EXTRACT(DOW     FROM d) IN (0, 6)
FROM generate_series('1990-01-01'::date, '2030-12-31'::date, '1 day'::interval) d;


-- ===== 20250201000005_rep_warehouse_facts.sql =====
-- Fact tables and ETL batch log. Append-only; never modified after insert.

CREATE TABLE rep_warehouse.etl_batch_log (
    batch_id      TEXT        PRIMARY KEY,
    started_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at   TIMESTAMPTZ,
    status        TEXT        NOT NULL DEFAULT 'running',  -- running | success | failed
    source_system TEXT,
    rows_inserted INTEGER,
    rows_closed   INTEGER,
    error_message TEXT
);

CREATE TABLE rep_warehouse.fact_children_supported (
    id                         BIGSERIAL   PRIMARY KEY,
    source_contact_id          TEXT,
    contact_id                 INTEGER     REFERENCES rep_warehouse.dim_contact(id),
    source_school_id           TEXT,
    school_id                  INTEGER     REFERENCES rep_warehouse.dim_school(id),
    geography_id               INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    year                       SMALLINT,
    year_date_id               INTEGER     REFERENCES rep_warehouse.dim_date(id),
    form                       TEXT,
    contact_record_type        TEXT,
    attendance_issues          BOOLEAN,
    received_financial_support BOOLEAN,
    repeated                   BOOLEAN,
    roc_donor_id               INTEGER     REFERENCES rep_warehouse.dim_roc_donor(id),
    roc_project_code_id        INTEGER     REFERENCES rep_warehouse.dim_roc_project_code(id),
    lin_is_current             BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type            TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system          TEXT,
    lin_source_file            TEXT,
    lin_load_batch_id          TEXT,
    lin_inserted_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash          TEXT,
    lin_superseded_at          TIMESTAMPTZ,
    lin_source_row_number      INTEGER
);

CREATE INDEX idx_fact_cs_business_hash ON rep_warehouse.fact_children_supported (lin_business_hash);
CREATE INDEX idx_fact_cs_contact_id    ON rep_warehouse.fact_children_supported (contact_id);
CREATE INDEX idx_fact_cs_school_id     ON rep_warehouse.fact_children_supported (school_id);
CREATE INDEX idx_fact_cs_geography_id  ON rep_warehouse.fact_children_supported (geography_id);
CREATE INDEX idx_fact_cs_year          ON rep_warehouse.fact_children_supported (year);
CREATE INDEX idx_fact_cs_roc_donor     ON rep_warehouse.fact_children_supported (roc_donor_id);


CREATE TABLE rep_warehouse.fact_guide_assignment (
    id                          BIGSERIAL   PRIMARY KEY,
    source_contact_id           TEXT,
    contact_id                  INTEGER     REFERENCES rep_warehouse.dim_contact(id),
    source_school_id            TEXT,
    school_id                   INTEGER     REFERENCES rep_warehouse.dim_school(id),
    geography_id                INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    date_joined_guide_programme TIMESTAMP,
    date_joined_id              INTEGER     REFERENCES rep_warehouse.dim_date(id),
    date_left_guide_programme   TIMESTAMP,
    date_left_id                INTEGER     REFERENCES rep_warehouse.dim_date(id),
    guide_type                  TEXT,
    guide_status                TEXT,
    guide_specialty             TEXT,
    guide_dropout_reason        TEXT,
    trained_in_climate_education BOOLEAN,
    roc_donor_id                INTEGER     REFERENCES rep_warehouse.dim_roc_donor(id),
    lin_is_current              BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type             TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system           TEXT,
    lin_source_file             TEXT,
    lin_load_batch_id           TEXT,
    lin_inserted_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash           TEXT,
    lin_superseded_at           TIMESTAMPTZ,
    lin_source_row_number       INTEGER
);

CREATE INDEX idx_fact_ga_business_hash ON rep_warehouse.fact_guide_assignment (lin_business_hash);
CREATE INDEX idx_fact_ga_contact_id    ON rep_warehouse.fact_guide_assignment (contact_id);
CREATE INDEX idx_fact_ga_school_id     ON rep_warehouse.fact_guide_assignment (school_id);
CREATE INDEX idx_fact_ga_geography_id  ON rep_warehouse.fact_guide_assignment (geography_id);
CREATE INDEX idx_fact_ga_roc_donor     ON rep_warehouse.fact_guide_assignment (roc_donor_id);


CREATE TABLE rep_warehouse.fact_cama_membership (
    id                    BIGSERIAL   PRIMARY KEY,
    source_contact_id     TEXT,
    contact_id            INTEGER     REFERENCES rep_warehouse.dim_contact(id),
    source_school_id      TEXT,
    school_id             INTEGER     REFERENCES rep_warehouse.dim_school(id),
    geography_id          INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    date_joined_cama      TIMESTAMP,
    date_joined_id        INTEGER     REFERENCES rep_warehouse.dim_date(id),
    partner_school        BOOLEAN,
    lin_is_current        BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type       TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system     TEXT,
    lin_source_file       TEXT,
    lin_load_batch_id     TEXT,
    lin_inserted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash     TEXT,
    lin_superseded_at     TIMESTAMPTZ,
    lin_source_row_number INTEGER
);

CREATE INDEX idx_fact_cm_business_hash ON rep_warehouse.fact_cama_membership (lin_business_hash);
CREATE INDEX idx_fact_cm_contact_id    ON rep_warehouse.fact_cama_membership (contact_id);
CREATE INDEX idx_fact_cm_school_id     ON rep_warehouse.fact_cama_membership (school_id);
CREATE INDEX idx_fact_cm_geography_id  ON rep_warehouse.fact_cama_membership (geography_id);


CREATE TABLE rep_warehouse.fact_post_school_support (
    id                         BIGSERIAL   PRIMARY KEY,
    source_contact_id          TEXT,
    contact_id                 INTEGER     REFERENCES rep_warehouse.dim_contact(id),
    geography_id               INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    year                       SMALLINT,
    year_date_id               INTEGER     REFERENCES rep_warehouse.dim_date(id),
    received_financial_support BOOLEAN,
    accommodation              TEXT,
    form                       TEXT,
    roc_donor_id               INTEGER     REFERENCES rep_warehouse.dim_roc_donor(id),
    lin_is_current             BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type            TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system          TEXT,
    lin_source_file            TEXT,
    lin_load_batch_id          TEXT,
    lin_inserted_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash          TEXT,
    lin_superseded_at          TIMESTAMPTZ,
    lin_source_row_number      INTEGER
);

CREATE INDEX idx_fact_ps_business_hash ON rep_warehouse.fact_post_school_support (lin_business_hash);
CREATE INDEX idx_fact_ps_contact_id    ON rep_warehouse.fact_post_school_support (contact_id);
CREATE INDEX idx_fact_ps_geography_id  ON rep_warehouse.fact_post_school_support (geography_id);
CREATE INDEX idx_fact_ps_year          ON rep_warehouse.fact_post_school_support (year);


CREATE TABLE rep_warehouse.fact_grants (
    id                    BIGSERIAL   PRIMARY KEY,
    source_grant_id       TEXT        UNIQUE,
    source_contact_id     TEXT,
    contact_id            INTEGER     REFERENCES rep_warehouse.dim_contact(id),
    geography_id          INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    grant_type            TEXT,
    grant_status          TEXT,
    amount_given          NUMERIC,
    grant_date            TIMESTAMP,
    grant_date_id         INTEGER     REFERENCES rep_warehouse.dim_date(id),
    roc_donor_id          INTEGER     REFERENCES rep_warehouse.dim_roc_donor(id),
    lin_is_current        BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type       TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system     TEXT,
    lin_source_file       TEXT,
    lin_load_batch_id     TEXT,
    lin_inserted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash     TEXT,
    lin_superseded_at     TIMESTAMPTZ,
    lin_source_row_number INTEGER
);

CREATE INDEX idx_fact_gr_contact_id   ON rep_warehouse.fact_grants (contact_id);
CREATE INDEX idx_fact_gr_geography_id ON rep_warehouse.fact_grants (geography_id);
CREATE INDEX idx_fact_gr_roc_donor    ON rep_warehouse.fact_grants (roc_donor_id);
CREATE INDEX idx_fact_gr_date_id      ON rep_warehouse.fact_grants (grant_date_id);


CREATE TABLE rep_warehouse.fact_loans (
    id                    BIGSERIAL   PRIMARY KEY,
    source_loan_id        TEXT        UNIQUE,
    geography_id          INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    loan_type             TEXT,
    status                TEXT,
    loan_status           TEXT,
    disbursal_date        TIMESTAMP,
    disbursal_date_id     INTEGER     REFERENCES rep_warehouse.dim_date(id),
    loan_value            NUMERIC,
    currency_iso_code     TEXT,
    contact_record_id     TEXT,
    roc_donor_id          INTEGER     REFERENCES rep_warehouse.dim_roc_donor(id),
    lin_is_current        BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type       TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system     TEXT,
    lin_source_file       TEXT,
    lin_load_batch_id     TEXT,
    lin_inserted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash     TEXT,
    lin_superseded_at     TIMESTAMPTZ,
    lin_source_row_number INTEGER
);

CREATE INDEX idx_fact_lo_geography_id  ON rep_warehouse.fact_loans (geography_id);
CREATE INDEX idx_fact_lo_disbursal_id  ON rep_warehouse.fact_loans (disbursal_date_id);
CREATE INDEX idx_fact_lo_roc_donor     ON rep_warehouse.fact_loans (roc_donor_id);


CREATE TABLE rep_warehouse.fact_observed_kpi (
    id                       BIGSERIAL  PRIMARY KEY,
    kpi_id                   INTEGER    REFERENCES rep_warehouse.dim_kpi(id),
    geography_id             INTEGER    REFERENCES rep_warehouse.dim_geography(id),
    year                     SMALLINT,
    year_date_id             INTEGER    REFERENCES rep_warehouse.dim_date(id),
    disaggregation_level_one TEXT,
    disaggregation_level_two TEXT,
    value_type               TEXT,
    row_scope                TEXT,      -- ANNUAL | CUMULATIVE | SUBTOTAL | BENCHMARK | DETAIL
    value                    TEXT,      -- preserved as TEXT; cast to numeric in views as needed
    updated_date             DATE,
    lin_is_current           BOOLEAN    NOT NULL DEFAULT true,
    lin_change_type          TEXT       NOT NULL DEFAULT 'INSERT',
    lin_source_system        TEXT,
    lin_source_file          TEXT,
    lin_load_batch_id        TEXT,
    lin_inserted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash        TEXT,
    lin_superseded_at        TIMESTAMPTZ,
    lin_source_row_number    INTEGER
);

CREATE INDEX idx_fact_ok_business_hash ON rep_warehouse.fact_observed_kpi (lin_business_hash);
CREATE INDEX idx_fact_ok_kpi_id        ON rep_warehouse.fact_observed_kpi (kpi_id);
CREATE INDEX idx_fact_ok_geography_id  ON rep_warehouse.fact_observed_kpi (geography_id);
CREATE INDEX idx_fact_ok_year          ON rep_warehouse.fact_observed_kpi (year);
CREATE INDEX idx_fact_ok_row_scope     ON rep_warehouse.fact_observed_kpi (row_scope);


CREATE TABLE rep_warehouse.fact_level_one_kpis (
    id                     BIGSERIAL   PRIMARY KEY,
    kpi_id                 INTEGER     REFERENCES rep_warehouse.dim_kpi(id),
    geography_id           INTEGER     REFERENCES rep_warehouse.dim_geography(id),
    year_date_id           INTEGER     REFERENCES rep_warehouse.dim_date(id),
    year                   SMALLINT,
    school_level           TEXT,
    annual_newly_supported TEXT,
    fund_type              TEXT,
    gender                 TEXT,
    disaggregation_gender  TEXT,
    value                  NUMERIC,
    lin_is_current         BOOLEAN     NOT NULL DEFAULT true,
    lin_change_type        TEXT        NOT NULL DEFAULT 'INSERT',
    lin_source_system      TEXT,
    lin_source_file        TEXT,
    lin_load_batch_id      TEXT,
    lin_inserted_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lin_business_hash      TEXT,
    lin_superseded_at      TIMESTAMPTZ,
    lin_source_row_number  INTEGER
);

CREATE INDEX idx_fact_l1_business_hash ON rep_warehouse.fact_level_one_kpis (lin_business_hash);
CREATE INDEX idx_fact_l1_kpi_id        ON rep_warehouse.fact_level_one_kpis (kpi_id);
CREATE INDEX idx_fact_l1_geography_id  ON rep_warehouse.fact_level_one_kpis (geography_id);
CREATE INDEX idx_fact_l1_year          ON rep_warehouse.fact_level_one_kpis (year);

-- Unique expression index for fact_level_one_kpis UPSERT in kpi_upload_level_one().
-- COALESCE placeholders make NULLs participate in uniqueness.
CREATE UNIQUE INDEX uix_fact_level_one_kpis
    ON rep_warehouse.fact_level_one_kpis (
        year,
        COALESCE(geography_id,            -1),
        COALESCE(school_level,            ''),
        COALESCE(annual_newly_supported,  ''),
        COALESCE(fund_type,               ''),
        COALESCE(gender,                  '')
    );


-- ===== 20250201000006_rep_warehouse_views.sql =====
-- Flat views over each fact table. Pre-join all dimensions for frontend and BI queries.

CREATE OR REPLACE VIEW rep_warehouse.view_children_supported AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.month                        AS year_month,
    dd.month_name                   AS year_month_name,
    dd.quarter                      AS year_quarter,
    f.form,
    f.contact_record_type,
    f.attendance_issues,
    f.received_financial_support,
    f.repeated,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    d2.name                         AS project_code_name,
    d2.reporting_code               AS project_code,
    s.school_name,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_children_supported f
LEFT JOIN rep_warehouse.dim_contact         ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school           s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography        g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date            dd  ON dd.id = f.year_date_id
LEFT JOIN rep_warehouse.dim_roc_donor       d3  ON d3.id = f.roc_donor_id
LEFT JOIN rep_warehouse.dim_roc_project_code d2 ON d2.id = f.roc_project_code_id;


CREATE OR REPLACE VIEW rep_warehouse.view_guide_assignment AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    f.date_joined_guide_programme,
    joined_dd.year                  AS joined_year,
    joined_dd.month                 AS joined_month,
    joined_dd.month_name            AS joined_month_name,
    joined_dd.quarter               AS joined_quarter,
    f.date_left_guide_programme,
    left_dd.year                    AS left_year,
    left_dd.month                   AS left_month,
    left_dd.month_name              AS left_month_name,
    left_dd.quarter                 AS left_quarter,
    f.guide_type,
    f.guide_status,
    f.guide_specialty,
    f.guide_dropout_reason,
    f.trained_in_climate_education,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    s.school_name,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_guide_assignment f
LEFT JOIN rep_warehouse.dim_contact  ct       ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s        ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g        ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date      joined_dd ON joined_dd.id = f.date_joined_id
LEFT JOIN rep_warehouse.dim_date      left_dd   ON left_dd.id   = f.date_left_id
LEFT JOIN rep_warehouse.dim_roc_donor d3        ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_cama_membership AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    f.date_joined_cama,
    dd.year                         AS join_year,
    dd.month                        AS join_month,
    dd.month_name                   AS join_month_name,
    dd.quarter                      AS join_quarter,
    f.partner_school,
    s.school_name,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_cama_membership f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.date_joined_id;


CREATE OR REPLACE VIEW rep_warehouse.view_post_school_support AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.month                        AS year_month,
    dd.month_name                   AS year_month_name,
    dd.quarter                      AS year_quarter,
    f.received_financial_support,
    f.accommodation,
    f.form,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_post_school_support f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_grants AS
SELECT
    f.id,
    f.source_grant_id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    f.grant_type,
    f.grant_status,
    f.amount_given,
    f.grant_date,
    dd.year                         AS grant_year,
    dd.month                        AS grant_month,
    dd.month_name                   AS grant_month_name,
    dd.quarter                      AS grant_quarter,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_grants f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.grant_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_loans AS
SELECT
    f.id,
    f.source_loan_id,
    f.loan_type,
    f.status                        AS loan_status_raw,
    f.loan_status,
    f.loan_value,
    f.currency_iso_code,
    f.contact_record_id,
    f.disbursal_date,
    dd.year                         AS disbursal_year,
    dd.month                        AS disbursal_month,
    dd.month_name                   AS disbursal_month_name,
    dd.quarter                      AS disbursal_quarter,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_loans f
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.disbursal_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_donor_summary AS
SELECT
    d3.id                           AS donor_id,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    d3.available_country,
    d3.active,
    d3.start_date                   AS donor_start_date,
    d3.end_date                     AS donor_end_date,
    COUNT(DISTINCT f_cs.id)         AS children_supported_count,
    COUNT(DISTINCT f_ga.id)         AS guides_count,
    COUNT(DISTINCT f_gr.id)         AS grants_count,
    COUNT(DISTINCT f_lo.id)         AS loans_count
FROM rep_warehouse.dim_roc_donor d3
LEFT JOIN rep_warehouse.fact_children_supported f_cs ON f_cs.roc_donor_id = d3.id
LEFT JOIN rep_warehouse.fact_guide_assignment   f_ga ON f_ga.roc_donor_id = d3.id
LEFT JOIN rep_warehouse.fact_grants             f_gr ON f_gr.roc_donor_id = d3.id
LEFT JOIN rep_warehouse.fact_loans              f_lo ON f_lo.roc_donor_id = d3.id
WHERE d3.scd_is_current = true
GROUP BY d3.id, d3.name, d3.reporting_code, d3.available_country, d3.active,
         d3.start_date, d3.end_date;


CREATE OR REPLACE VIEW rep_warehouse.view_school_map AS
SELECT
    s.id,
    s.source_school_id,
    s.school_name,
    s.school_type,
    s.latitude,
    s.longitude,
    s.active_on_bursary,
    s.active_partner_school,
    s.monitoring_school,
    s.gea_school,
    s.cpp_in_place,
    s.snf_only,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country,
    rg.name                         AS roc_geography_name,
    rg.reporting_code               AS roc_geography_code
FROM rep_warehouse.dim_school s
LEFT JOIN rep_warehouse.dim_geography     g  ON g.id  = s.geography_id  AND g.scd_is_current = true
LEFT JOIN rep_warehouse.dim_roc_donor     d3 ON d3.id = s.roc_donor_id  AND d3.scd_is_current = true
LEFT JOIN rep_warehouse.dim_roc_geography rg ON rg.id = g.roc_geography_id AND rg.scd_is_current = true
WHERE s.scd_is_current = true
  AND s.latitude IS NOT NULL
  AND s.longitude IS NOT NULL;


CREATE OR REPLACE VIEW rep_warehouse.view_observed_kpi AS
SELECT
    f.id,
    k.source_kpi_id                 AS kpi_id,
    k.kpi_group,
    k.indicator,
    f.disaggregation_level_one,
    f.disaggregation_level_two,
    f.row_scope,
    f.lin_source_row_number,
    f.value_type,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.month                        AS year_month,
    dd.month_name                   AS year_month_name,
    dd.quarter                      AS year_quarter,
    f.value,                        -- TEXT: may be numeric, 'Not Applicable', etc.
    f.updated_date,
    g.country
FROM rep_warehouse.fact_observed_kpi f
LEFT JOIN rep_warehouse.dim_kpi      k  ON  k.id = f.kpi_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id;


-- Specialised KPI views — always query these instead of view_observed_kpi directly
-- to avoid aggregation errors from mixing row_scope values.

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_counts AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE value_type = 'Count'
  AND row_scope  = 'ANNUAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_percentages AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric * 100 END AS value_pct
FROM rep_warehouse.view_observed_kpi
WHERE value_type = 'Percentage'
  AND row_scope  = 'ANNUAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_targets AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'CUMULATIVE'
  AND disaggregation_level_one = 'Cumulative (2020-2030)';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_cumulative AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'CUMULATIVE'
  AND disaggregation_level_one IN ('Cumulative (all-time)', 'Cumulative');

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_detail AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'DETAIL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_subtotals AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'SUBTOTAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_benchmarks AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'BENCHMARK';

CREATE OR REPLACE VIEW rep_warehouse.view_level_one_kpis AS
SELECT
    f.id,
    k.source_kpi_id                 AS kpi_id,
    k.kpi_group,
    k.indicator,
    f.school_level,
    f.annual_newly_supported,
    f.fund_type,
    f.gender,
    f.disaggregation_gender,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.quarter                      AS year_quarter,
    f.value,
    g.country
FROM rep_warehouse.fact_level_one_kpis f
LEFT JOIN rep_warehouse.dim_kpi      k  ON  k.id = f.kpi_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id;


-- ===== 20250201000007_etl_functions.sql =====
-- ETL functions: per-table staging, warehouse load, and orchestration wrappers.
--
-- Per-table functions read app.batch_id / app.source_system / app.source_file from
-- the session (set by the top-level wrappers etl_run_salesforce / etl_run_kpis).
-- All functions are SECURITY DEFINER with statement_timeout = 0 to survive long ETL runs.


-- ══════════════════════════════════════════════════════════════════════════════
-- STAGING — Salesforce tables
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_dimension_1_roc()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.dimension_1_roc;
    CREATE TABLE rep_staging.dimension_1_roc AS
    SELECT
        salesforce_id,
        (active = 'true') AS active,
        available_country,
        description,
        name,
        reporting_code
    FROM rep_raw.dimension_1_roc;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_dimension_2_roc()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.dimension_2_roc;
    CREATE TABLE rep_staging.dimension_2_roc AS
    SELECT
        salesforce_id,
        (active = 'true') AS active,
        available_country,
        description,
        name,
        reporting_code
    FROM rep_raw.dimension_2_roc;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_dimension_3_roc()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.dimension_3_roc;
    CREATE TABLE rep_staging.dimension_3_roc AS
    SELECT
        salesforce_id,
        (active = 'true') AS active,
        available_country,
        description,
        name,
        reporting_code,
        start_date,
        end_date
    FROM rep_raw.dimension_3_roc;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_dimension_4_roc()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.dimension_4_roc;
    CREATE TABLE rep_staging.dimension_4_roc AS
    SELECT
        salesforce_id,
        (active = 'true') AS active,
        available_country,
        description,
        name,
        reporting_code,
        dimension_3_id
    FROM rep_raw.dimension_4_roc;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_countries()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.countries;
    CREATE TABLE rep_staging.countries AS
    SELECT
        salesforce_id,
        country_name,
        unique_id
    FROM rep_raw.countries
    WHERE country_name IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_districts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.districts;
    CREATE TABLE rep_staging.districts AS
    SELECT
        salesforce_id,
        country_id,
        district_name,
        province,
        terrain,
        (active_partner_district = 'true') AS active_partner_district,
        date_camfed_began_work,
        country_name,
        region_id,
        unique_id
    FROM rep_raw.districts
    WHERE district_name IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_contacts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.contacts;
    CREATE TABLE rep_staging.contacts AS
    SELECT
        salesforce_id,
        record_type_id,
        gender,
        country_id,
        country_name,
        district_id,
        wg_difficulty_overall,
        (lg_social_support_recipient = 'true') AS lg_social_support_recipient,
        (active_on_bursary = 'true')           AS active_on_bursary,
        date_joined_cama,
        school_id,
        orphan_status,
        donor_activity_id,
        donor_code_id,
        project_code_id
    FROM rep_raw.contacts
    WHERE salesforce_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_schools()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.schools;
    CREATE TABLE rep_staging.schools AS
    SELECT
        salesforce_id                         AS school_id,
        school_name,
        province,
        district_id,
        district_name                         AS district,
        country,
        school_type,
        accommodation_type,
        date_camfed_began_support,
        number_of_active_lgs                  AS active_lg_count,
        (school_active_on_bursary = 'true')   AS active_on_bursary,
        (active_partner_school = 'true')      AS active_partner_school,
        (affiliated_school = 'true')          AS affiliated_school,
        (cpp_in_place = 'true')               AS cpp_in_place,
        (snf_only_school = 'true')            AS snf_only,
        (monitoring_school = 'true')          AS monitoring_school,
        (gea_school = 'true')                 AS gea_school,
        (merp = 'true')                       AS merp,
        latitude,
        longitude,
        donor_id,
        unique_id
    FROM rep_raw.schools
    WHERE salesforce_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        row_id,
        salesforce_id,
        person_id                              AS contact_id,
        school_institution_id                  AS school_id,
        district_id,
        district_name                          AS district,
        country_name                           AS country,
        contact_record_type,
        form,
        CASE WHEN year ~ '^\d{4}$' THEN year::smallint END AS year,
        (received_financial_support = 'true')  AS received_financial_support,
        (repeated = 'true')                    AS repeated,
        (attendance_issues = 'true')           AS attendance_issues,
        accommodation,
        donor_code_id,
        project_code_id,
        donor_activity_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND (contact_record_type IS NULL OR contact_record_type != 'Post School');
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_post_school_clients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.post_school_clients;
    CREATE TABLE rep_staging.post_school_clients AS
    SELECT
        row_id,
        salesforce_id,
        person_id                              AS contact_id,
        district_id,
        district_name                          AS district,
        country_name                           AS country,
        contact_record_type,
        form,
        CASE WHEN year ~ '^\d{4}$' THEN year::smallint END AS year,
        (received_financial_support = 'true')  AS received_financial_support,
        accommodation,
        donor_code_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND contact_record_type = 'Post School';
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_guides()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.guides;
    CREATE TABLE rep_staging.guides AS
    SELECT
        row_id,
        salesforce_id,
        contact_id,
        school_id,
        district_id,
        contact_record_type,
        guide_type,
        guide_status,
        guide_specialty,
        guide_dropout_reason,
        date_joined_guide_programme::timestamp    AS date_joined_guide_programme,
        date_completed_guide_programme::timestamp AS date_left_guide_programme,
        (trained_in_climate_education = 'true')   AS trained_in_climate_education,
        donor_id
    FROM rep_raw.guides
    WHERE contact_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_cama_members()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.cama_members;
    CREATE TABLE rep_staging.cama_members AS
    SELECT
        row_id,
        contact_id,
        school_id_code                AS school_id,
        schoolinstitution_school_name AS school_name,
        districtschool                AS district,
        country_country_name          AS country,
        full_name,
        NULLIF(date_joined_cama, '')::TIMESTAMP AS date_joined_cama,
        (partner_school != '0')       AS partner_school
    FROM rep_raw.cama_members
    WHERE contact_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_grant_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.grant_recipients;
    CREATE TABLE rep_staging.grant_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS grant_id,
        person_id                     AS contact_id,
        contact_record_type,
        district_id                   AS district,
        country,
        record_type_id                AS grant_type,
        status                        AS grant_status,
        amount_given,
        grant_date,
        donor_id
    FROM rep_raw.grant_recipients
    WHERE salesforce_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_loan_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.loan_recipients;
    CREATE TABLE rep_staging.loan_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS loan_id,
        client_id,
        contact_record_type,
        district,
        country,
        loan_type_id                  AS loan_type,
        record_type_id                AS record_type,
        status,
        loan_status,
        disbursal_date,
        loan_value,
        currency_iso_code,
        contact_record_id,
        donor_code_id
    FROM rep_raw.loan_recipients
    WHERE salesforce_id IS NOT NULL;
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- STAGING — KPI tables
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_all_kpis()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.all_kpis;
    CREATE TABLE rep_staging.all_kpis AS
    SELECT
        row_id,
        kpi_no::text                    AS kpi_id,
        indicator_group                 AS kpi_group,
        indicator,
        disaggregation1                 AS disaggregation_level_one,
        disaggregation2                 AS disaggregation_level_two,
        updated_date,
        year_of_kpis::smallint          AS year,
        value_type,
        CASE
            WHEN disaggregation1 ILIKE '%cumulative%'
              OR disaggregation2 ILIKE '%cumulative%'                       THEN 'CUMULATIVE'
            WHEN disaggregation2 ILIKE 'benchmark'
              OR disaggregation2 ILIKE '%poverty line%'                     THEN 'BENCHMARK'
            WHEN disaggregation1 = 'Total'
              OR disaggregation2 = 'Total'
              OR disaggregation2 ILIKE '%total'
              OR disaggregation2 ILIKE 'overall'
              OR disaggregation2 ILIKE 'combined'
              OR disaggregation2 ILIKE '%total%'                            THEN 'SUBTOTAL'
            WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                     'New since last year','Annual reach per LG')
              OR disaggregation2 = 'Annual'                                 THEN 'ANNUAL'
            ELSE                                                                  'DETAIL'
        END                             AS row_scope,
        'Ghana'                         AS country,
        ghana::text                     AS value
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND ghana IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Malawi', malawi::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND malawi IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Tanzania', tanzania::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND tanzania IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Zambia', zambia::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND zambia IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Zimbabwe', zimbabwe::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND zimbabwe IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Total', total::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND total IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_level_one_kpis()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.level_one_kpis;
    CREATE TABLE rep_staging.level_one_kpis AS
    SELECT
        row_id,
        TRIM(country)                                           AS country,
        year::SMALLINT                                          AS year,
        TRIM(kpi)                                               AS kpi,
        TRIM(school_level)                                      AS school_level,
        TRIM(annual_newly_supported)                            AS annual_newly_supported,
        TRIM(type)                                              AS fund_type,
        TRIM(gender)                                            AS gender,
        TRIM(disaggregation_gender)                             AS disaggregation_gender,
        CASE
            WHEN REPLACE(value::TEXT, ',', '') ~ '^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$'
            THEN REPLACE(value::TEXT, ',', '')::NUMERIC
        END                                                     AS value
    FROM rep_raw.level_one_kpis
    WHERE country IS NOT NULL
      AND kpi    IS NOT NULL;
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- WAREHOUSE LOAD — Salesforce dimensions
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_geography()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    UPDATE rep_warehouse.dim_roc_geography w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT salesforce_id,
               MD5(concat_ws('||',
                   COALESCE(name, ''), COALESCE(reporting_code, ''),
                   COALESCE(available_country, ''), active::text
               )) AS biz_hash
        FROM rep_staging.dimension_1_roc
    ) incoming
    WHERE w.source_roc_id      = incoming.salesforce_id
      AND w.scd_is_current     = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_roc_geography
        (source_roc_id, name, reporting_code, available_country, active,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id, name, reporting_code, available_country, active,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_roc_geography WHERE source_roc_id = salesforce_id), 0) + 1,
        MD5(concat_ws('||', COALESCE(name,''), COALESCE(reporting_code,''), COALESCE(available_country,''), active::text)),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_1_roc
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_roc_geography w
        WHERE w.source_roc_id = salesforce_id AND w.scd_is_current = true
    )
    ORDER BY salesforce_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_project_code()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    UPDATE rep_warehouse.dim_roc_project_code w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT salesforce_id,
               MD5(concat_ws('||',
                   COALESCE(name, ''), COALESCE(reporting_code, ''),
                   COALESCE(available_country, ''), active::text
               )) AS biz_hash
        FROM rep_staging.dimension_2_roc
    ) incoming
    WHERE w.source_roc_id      = incoming.salesforce_id
      AND w.scd_is_current     = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_roc_project_code
        (source_roc_id, name, reporting_code, available_country, active,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id, name, reporting_code, available_country, active,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_roc_project_code WHERE source_roc_id = salesforce_id), 0) + 1,
        MD5(concat_ws('||', COALESCE(name,''), COALESCE(reporting_code,''), COALESCE(available_country,''), active::text)),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_2_roc
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_roc_project_code w
        WHERE w.source_roc_id = salesforce_id AND w.scd_is_current = true
    )
    ORDER BY salesforce_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_donor()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    UPDATE rep_warehouse.dim_roc_donor w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT salesforce_id,
               MD5(concat_ws('||',
                   COALESCE(name, ''), COALESCE(reporting_code, ''),
                   COALESCE(available_country, ''), active::text,
                   COALESCE(start_date, ''), COALESCE(end_date, '')
               )) AS biz_hash
        FROM rep_staging.dimension_3_roc
    ) incoming
    WHERE w.source_roc_id      = incoming.salesforce_id
      AND w.scd_is_current     = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_roc_donor
        (source_roc_id, name, reporting_code, available_country, active, start_date, end_date,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id, name, reporting_code, available_country, active,
        start_date::date, end_date::date,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_roc_donor WHERE source_roc_id = salesforce_id), 0) + 1,
        MD5(concat_ws('||', COALESCE(name,''), COALESCE(reporting_code,''), COALESCE(available_country,''),
                            active::text, COALESCE(start_date,''), COALESCE(end_date,''))),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_3_roc
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_roc_donor w
        WHERE w.source_roc_id = salesforce_id AND w.scd_is_current = true
    )
    ORDER BY salesforce_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_donor_activity()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    UPDATE rep_warehouse.dim_roc_donor_activity w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT salesforce_id,
               MD5(concat_ws('||',
                   COALESCE(name, ''), COALESCE(reporting_code, ''),
                   COALESCE(available_country, ''), active::text,
                   COALESCE(dimension_3_id, '')
               )) AS biz_hash
        FROM rep_staging.dimension_4_roc
    ) incoming
    WHERE w.source_roc_id      = incoming.salesforce_id
      AND w.scd_is_current     = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_roc_donor_activity
        (source_roc_id, donor_id, name, reporting_code, available_country, active,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (s.salesforce_id)
        s.salesforce_id,
        d3.id,
        s.name, s.reporting_code, s.available_country, s.active,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_roc_donor_activity WHERE source_roc_id = s.salesforce_id), 0) + 1,
        MD5(concat_ws('||', COALESCE(s.name,''), COALESCE(s.reporting_code,''), COALESCE(s.available_country,''),
                            s.active::text, COALESCE(s.dimension_3_id,''))),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_4_roc s
    LEFT JOIN rep_warehouse.dim_roc_donor d3
        ON d3.source_roc_id = s.dimension_3_id AND d3.scd_is_current = true
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_roc_donor_activity w
        WHERE w.source_roc_id = s.salesforce_id AND w.scd_is_current = true
    )
    ORDER BY s.salesforce_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_geography()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    -- country rows from countries table
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country, roc_geography_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT
        c.country_name, NULL, NULL, true, NULL::INTEGER,
        CURRENT_DATE, true, 1,
        MD5(c.country_name),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.countries c
    WHERE c.country_name IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = c.country_name AND g.province IS NULL AND g.district IS NULL
      );

    -- district rows
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country, roc_geography_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (d.country_name, d.province, d.district_name)
        d.country_name,
        d.province,
        d.district_name,
        false,
        rg.id,
        CURRENT_DATE, true, 1,
        MD5(concat_ws('||', d.country_name, d.province, d.district_name)),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.districts d
    LEFT JOIN rep_warehouse.dim_roc_geography rg
        ON rg.source_roc_id = d.region_id AND rg.scd_is_current = true
    WHERE d.country_name IS NOT NULL AND d.district_name IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = d.country_name AND g.district = d.district_name
      )
    ORDER BY d.country_name, d.province, d.district_name;

    -- fallback country rows from schools
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT
        s.country, NULL, NULL, true,
        CURRENT_DATE, true, 1,
        MD5(s.country),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.schools s
    WHERE s.country IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = s.country AND g.province IS NULL AND g.district IS NULL
      );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_school()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    UPDATE rep_warehouse.dim_school w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT DISTINCT ON (s.school_id)
            s.school_id AS source_school_id,
            MD5(concat_ws('||',
                COALESCE(s.school_name, ''),
                COALESCE(s.province, ''),
                COALESCE(s.district, ''),
                COALESCE(s.country, ''),
                COALESCE(s.school_type, ''),
                COALESCE(s.accommodation_type, ''),
                COALESCE(s.date_camfed_began_support::text, ''),
                COALESCE(s.active_on_bursary::text, ''),
                COALESCE(s.cpp_in_place::text, ''),
                COALESCE(s.snf_only::text, ''),
                COALESCE(s.monitoring_school::text, ''),
                COALESCE(s.gea_school::text, ''),
                COALESCE(s.active_partner_school::text, ''),
                COALESCE(s.affiliated_school::text, ''),
                COALESCE(s.latitude, ''),
                COALESCE(s.longitude, ''),
                COALESCE(s.donor_id, '')
            )) AS biz_hash
        FROM rep_staging.schools s
        WHERE s.school_id IS NOT NULL
        ORDER BY s.school_id
    ) incoming
    WHERE w.source_school_id = incoming.source_school_id
      AND w.scd_is_current   = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_school
        (source_school_id, school_name, geography_id, province, district, country,
         school_type, accommodation_type, date_camfed_began_support,
         active_on_bursary, cpp_in_place, snf_only, monitoring_school,
         gea_school, merp, active_partner_school, affiliated_school,
         latitude, longitude, roc_donor_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (s.school_id)
        s.school_id,
        s.school_name,
        dg.id,
        s.district, s.district, s.country,
        s.school_type,
        s.accommodation_type,
        s.date_camfed_began_support::timestamp,
        s.active_on_bursary, s.cpp_in_place, s.snf_only, s.monitoring_school,
        s.gea_school, s.merp, s.active_partner_school, s.affiliated_school,
        s.latitude::numeric, s.longitude::numeric,
        d3.id,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_school WHERE source_school_id = s.school_id), 0) + 1,
        MD5(concat_ws('||',
            COALESCE(s.school_name, ''),
            COALESCE(s.province, ''),
            COALESCE(s.district, ''),
            COALESCE(s.country, ''),
            COALESCE(s.school_type, ''),
            COALESCE(s.accommodation_type, ''),
            COALESCE(s.date_camfed_began_support::text, ''),
            COALESCE(s.active_on_bursary::text, ''),
            COALESCE(s.cpp_in_place::text, ''),
            COALESCE(s.snf_only::text, ''),
            COALESCE(s.monitoring_school::text, ''),
            COALESCE(s.gea_school::text, ''),
            COALESCE(s.active_partner_school::text, ''),
            COALESCE(s.affiliated_school::text, ''),
            COALESCE(s.latitude, ''),
            COALESCE(s.longitude, ''),
            COALESCE(s.donor_id, '')
        )),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.schools s
    LEFT JOIN rep_warehouse.dim_geography dg
        ON dg.country = s.country AND dg.district = s.district AND dg.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_donor d3
        ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
    WHERE s.school_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_school w
          WHERE w.source_school_id = s.school_id AND w.scd_is_current = true
      )
    ORDER BY s.school_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_contact()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS _etl_contacts;
    CREATE TEMP TABLE _etl_contacts (
        contact_id                  TEXT PRIMARY KEY,
        country                     TEXT,
        gender                      TEXT,
        wg_difficulty_overall       TEXT,
        lg_social_support_recipient BOOLEAN,
        active_on_bursary           BOOLEAN,
        orphan_status               TEXT,
        district                    TEXT,
        donor_code_id               TEXT,
        project_code_id             TEXT,
        donor_activity_id           TEXT
    );

    INSERT INTO _etl_contacts
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id,
        country_name,
        gender,
        wg_difficulty_overall,
        lg_social_support_recipient,
        active_on_bursary,
        orphan_status,
        district_id,
        donor_code_id,
        project_code_id,
        donor_activity_id
    FROM rep_staging.contacts
    WHERE salesforce_id IS NOT NULL
    ORDER BY salesforce_id;

    INSERT INTO _etl_contacts (contact_id, country, district, donor_code_id, project_code_id, donor_activity_id)
    SELECT contact_id, country, district_id, donor_code_id, project_code_id, donor_activity_id
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, country, district_id, donor_code_id, project_code_id, donor_activity_id
        FROM rep_staging.academic_record
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO _etl_contacts (contact_id, district)
    SELECT contact_id, district_id
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, district_id
        FROM rep_staging.guides
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO _etl_contacts (contact_id, country, district)
    SELECT contact_id, country, district
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, country, district
        FROM rep_staging.cama_members
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO _etl_contacts (contact_id, country, district)
    SELECT contact_id, country, district
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, country, district
        FROM rep_staging.grant_recipients
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    UPDATE rep_warehouse.dim_contact w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT
            contact_id,
            MD5(concat_ws('||',
                COALESCE(country, ''),
                COALESCE(gender, ''),
                COALESCE(wg_difficulty_overall, ''),
                COALESCE(lg_social_support_recipient::text, ''),
                COALESCE(active_on_bursary::text, ''),
                COALESCE(orphan_status, ''),
                COALESCE(district, ''),
                COALESCE(donor_code_id, '')
            )) AS biz_hash
        FROM _etl_contacts
    ) incoming
    WHERE w.source_contact_id = incoming.contact_id
      AND w.scd_is_current    = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_contact
        (source_contact_id, country, gender, wg_difficulty_overall,
         lg_social_support_recipient, active_on_bursary, orphan_status,
         district_of_residence,
         roc_donor_id, roc_project_code_id, roc_donor_activity_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT
        i.contact_id,
        i.country, i.gender, i.wg_difficulty_overall,
        i.lg_social_support_recipient, i.active_on_bursary, i.orphan_status,
        i.district,
        d3.id,
        d2.id,
        d4.id,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_contact WHERE source_contact_id = i.contact_id), 0) + 1,
        MD5(concat_ws('||',
            COALESCE(i.country, ''),
            COALESCE(i.gender, ''),
            COALESCE(i.wg_difficulty_overall, ''),
            COALESCE(i.lg_social_support_recipient::text, ''),
            COALESCE(i.active_on_bursary::text, ''),
            COALESCE(i.orphan_status, ''),
            COALESCE(i.district, ''),
            COALESCE(i.donor_code_id, '')
        )),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM _etl_contacts i
    LEFT JOIN rep_warehouse.dim_roc_donor          d3 ON d3.source_roc_id = i.donor_code_id     AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_project_code   d2 ON d2.source_roc_id = i.project_code_id   AND d2.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_donor_activity d4 ON d4.source_roc_id = i.donor_activity_id AND d4.scd_is_current = true
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_contact w
        WHERE w.source_contact_id = i.contact_id AND w.scd_is_current = true
    );
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- WAREHOUSE LOAD — Salesforce facts
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_children_supported()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_children_supported
        (source_contact_id, contact_id, source_school_id, school_id, geography_id,
         year, year_date_id, form, contact_record_type,
         attendance_issues, received_financial_support, repeated,
         roc_donor_id, roc_project_code_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
        s.year, dd.id, s.form, s.contact_record_type,
        s.attendance_issues, s.received_financial_support, s.repeated,
        d3.id, d2.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(concat_ws('||',
            COALESCE(s.contact_id, ''),
            COALESCE(s.school_id, ''),
            COALESCE(s.year::text, ''),
            COALESCE(s.contact_record_type, '')
        )),
        s.row_id
    FROM rep_staging.academic_record s
    LEFT JOIN rep_warehouse.dim_contact          dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school            ds  ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date              dd  ON dd.id = ((s.year::text || '0101')::integer)
    LEFT JOIN rep_warehouse.dim_roc_donor         d3  ON d3.source_roc_id = s.donor_code_id   AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_project_code  d2  ON d2.source_roc_id = s.project_code_id AND d2.scd_is_current = true
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_children_supported f
        WHERE f.lin_business_hash = MD5(concat_ws('||',
            COALESCE(s.contact_id, ''),
            COALESCE(s.school_id, ''),
            COALESCE(s.year::text, ''),
            COALESCE(s.contact_record_type, '')
        ))
    );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_guide_assignment()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_guide_assignment
        (source_contact_id, contact_id, source_school_id, school_id, geography_id,
         date_joined_guide_programme, date_joined_id,
         date_left_guide_programme,   date_left_id,
         guide_type, guide_status, guide_specialty, guide_dropout_reason,
         trained_in_climate_education, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(ds.geography_id,
            (SELECT id FROM rep_warehouse.dim_geography WHERE country = dct.country
             AND district = dct.district_of_residence AND scd_is_current = true LIMIT 1)
        ),
        s.date_joined_guide_programme, dd_joined.id,
        s.date_left_guide_programme,   dd_left.id,
        s.guide_type, s.guide_status, s.guide_specialty, s.guide_dropout_reason,
        s.trained_in_climate_education,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.contact_id, '')),
        s.row_id
    FROM rep_staging.guides s
    LEFT JOIN rep_warehouse.dim_contact dct      ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school  ds       ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd_joined ON dd_joined.id = TO_CHAR(s.date_joined_guide_programme, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_date    dd_left   ON dd_left.id   = TO_CHAR(s.date_left_guide_programme,   'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3      ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_guide_assignment f
        WHERE f.lin_business_hash = MD5(COALESCE(s.contact_id, ''))
    );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_cama_membership()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_cama_membership
        (source_contact_id, contact_id, source_school_id, school_id, geography_id,
         date_joined_cama, date_joined_id, partner_school,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(ds.geography_id,
            (SELECT id FROM rep_warehouse.dim_geography WHERE country = s.country
             AND district = s.district AND scd_is_current = true LIMIT 1)
        ),
        s.date_joined_cama, dd.id,
        s.partner_school,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(concat_ws('||', COALESCE(s.contact_id, ''), COALESCE(s.school_id, ''))),
        s.row_id
    FROM rep_staging.cama_members s
    LEFT JOIN rep_warehouse.dim_contact dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school  ds  ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd  ON dd.id = TO_CHAR(s.date_joined_cama::timestamp, 'YYYYMMDD')::integer
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_cama_membership f
        WHERE f.lin_business_hash = MD5(concat_ws('||', COALESCE(s.contact_id, ''), COALESCE(s.school_id, '')))
    );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_post_school_support()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_post_school_support
        (source_contact_id, contact_id, geography_id,
         year, year_date_id, received_financial_support, accommodation, form, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
        s.year, dd.id,
        s.received_financial_support,
        s.accommodation,
        s.form,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(concat_ws('||', COALESCE(s.contact_id, ''), COALESCE(s.year::text, ''))),
        s.row_id
    FROM rep_staging.post_school_clients s
    LEFT JOIN rep_warehouse.dim_contact  dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = ((s.year::text || '0101')::integer)
    LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.source_roc_id = s.donor_code_id AND d3.scd_is_current = true
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_post_school_support f
        WHERE f.lin_business_hash = MD5(concat_ws('||', COALESCE(s.contact_id, ''), COALESCE(s.year::text, '')))
    );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_grants()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_grants
        (source_grant_id, source_contact_id, contact_id, geography_id,
         grant_type, grant_status, amount_given, grant_date, grant_date_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.grant_id, s.contact_id, dct.id,
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
        s.grant_type, s.grant_status, s.amount_given::numeric, s.grant_date::timestamp, dd.id,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.grant_id, '')),
        s.row_id
    FROM rep_staging.grant_recipients s
    LEFT JOIN rep_warehouse.dim_contact  dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = TO_CHAR(s.grant_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
    ON CONFLICT (source_grant_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_loans()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_loans
        (source_loan_id, geography_id, loan_type, status, loan_status,
         disbursal_date, disbursal_date_id,
         loan_value, currency_iso_code, contact_record_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.loan_id,
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
        s.loan_type, s.status, s.loan_status,
        s.disbursal_date::timestamp, dd.id,
        s.loan_value::numeric,
        s.currency_iso_code,
        s.contact_record_id,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.loan_id, '')),
        s.row_id
    FROM rep_staging.loan_recipients s
    LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = TO_CHAR(s.disbursal_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.source_roc_id = s.donor_code_id AND d3.scd_is_current = true
    ON CONFLICT (source_loan_id) DO NOTHING;
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- WAREHOUSE LOAD — KPI dimensions and facts
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_geography_kpi()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT
        s.country, NULL, NULL, true,
        CURRENT_DATE, true, 1,
        MD5(s.country),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.level_one_kpis s
    WHERE s.country IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = s.country AND g.province IS NULL AND g.district IS NULL
      );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_kpi()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    UPDATE rep_warehouse.dim_kpi w
    SET
        scd_is_current    = false,
        scd_effective_to  = CURRENT_DATE - 1,
        lin_superseded_at = NOW()
    FROM (
        SELECT DISTINCT ON (kpi_id)
            kpi_id,
            MD5(concat_ws('||', COALESCE(kpi_group, ''), COALESCE(indicator, ''))) AS biz_hash
        FROM rep_staging.all_kpis
        ORDER BY kpi_id
    ) incoming
    WHERE w.source_kpi_id     = incoming.kpi_id
      AND w.scd_is_current    = true
      AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

    INSERT INTO rep_warehouse.dim_kpi
        (source_kpi_id, kpi_group, indicator,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (kpi_id)
        kpi_id, kpi_group, indicator,
        CURRENT_DATE, true,
        COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_kpi WHERE source_kpi_id = kpi_id), 0) + 1,
        MD5(concat_ws('||', COALESCE(kpi_group, ''), COALESCE(indicator, ''))),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.all_kpis
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_kpi w
        WHERE w.source_kpi_id = kpi_id AND w.scd_is_current = true
    )
    ORDER BY kpi_id;

    INSERT INTO rep_warehouse.dim_kpi
        (source_kpi_id, kpi_group, indicator,
         scd_effective_from, scd_is_current, scd_version,
         lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (kpi)
        kpi,
        REGEXP_REPLACE(kpi, '[^0-9\.]', '', 'g') AS kpi_group,
        'KPI ' || kpi                             AS indicator,
        CURRENT_DATE, true, 1,
        MD5(concat_ws('||', REGEXP_REPLACE(kpi, '[^0-9\.]', '', 'g'), 'KPI ' || kpi)),
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.level_one_kpis
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.dim_kpi w
        WHERE w.source_kpi_id = kpi AND w.scd_is_current = true
    )
    ORDER BY kpi;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_observed_kpi()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        dk.id,
        (SELECT id FROM rep_warehouse.dim_geography
         WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1),
        s.year, dd.id,
        s.disaggregation_level_one, s.disaggregation_level_two, s.value_type, s.row_scope,
        s.value, s.updated_date::date,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(concat_ws('||',
            COALESCE(s.kpi_id, ''),
            COALESCE(s.country, ''),
            COALESCE(s.year::text, ''),
            COALESCE(s.disaggregation_level_one, ''),
            COALESCE(s.disaggregation_level_two, '')
        )),
        s.row_id
    FROM rep_staging.all_kpis s
    LEFT JOIN rep_warehouse.dim_kpi  dk ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date dd ON dd.id = ((s.year::text || '0101')::integer)
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_observed_kpi f
        WHERE f.lin_business_hash = MD5(concat_ws('||',
            COALESCE(s.kpi_id, ''),
            COALESCE(s.country, ''),
            COALESCE(s.year::text, ''),
            COALESCE(s.disaggregation_level_one, ''),
            COALESCE(s.disaggregation_level_two, '')
        ))
    );
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_level_one_kpis()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_level_one_kpis
        (kpi_id, geography_id, year_date_id, year,
         school_level, annual_newly_supported, fund_type, gender, disaggregation_gender, value,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        dk.id, dg.id, dd.id,
        s.year,
        s.school_level, s.annual_newly_supported, s.fund_type, s.gender, s.disaggregation_gender, s.value,
        true, 'INSERT',
        current_setting('app.source_system', true),
        'level_one_kpis.csv',
        current_setting('app.batch_id',      true),
        MD5(concat_ws('||',
            COALESCE(s.kpi, ''),
            COALESCE(s.country, ''),
            COALESCE(s.year::text, ''),
            COALESCE(s.school_level, ''),
            COALESCE(s.annual_newly_supported, ''),
            COALESCE(s.fund_type, ''),
            COALESCE(s.gender, ''),
            COALESCE(s.disaggregation_gender, '')
        )),
        s.row_id
    FROM rep_staging.level_one_kpis s
    LEFT JOIN rep_warehouse.dim_kpi       dk ON dk.source_kpi_id = s.kpi    AND dk.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography  dg ON dg.country      = s.country AND dg.province IS NULL AND dg.district IS NULL
    LEFT JOIN rep_warehouse.dim_date       dd ON dd.id = ((s.year::TEXT || '0101')::INTEGER)
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_level_one_kpis f
        WHERE f.lin_business_hash = MD5(concat_ws('||',
            COALESCE(s.kpi, ''),
            COALESCE(s.country, ''),
            COALESCE(s.year::text, ''),
            COALESCE(s.school_level, ''),
            COALESCE(s.annual_newly_supported, ''),
            COALESCE(s.fund_type, ''),
            COALESCE(s.gender, ''),
            COALESCE(s.disaggregation_gender, '')
        ))
    );
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- Orchestration wrappers — thin loops over per-table functions
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_staging()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    PERFORM rep_warehouse.etl_stage_dimension_1_roc();
    PERFORM rep_warehouse.etl_stage_dimension_2_roc();
    PERFORM rep_warehouse.etl_stage_dimension_3_roc();
    PERFORM rep_warehouse.etl_stage_dimension_4_roc();
    PERFORM rep_warehouse.etl_stage_countries();
    PERFORM rep_warehouse.etl_stage_districts();
    PERFORM rep_warehouse.etl_stage_contacts();
    PERFORM rep_warehouse.etl_stage_schools();
    PERFORM rep_warehouse.etl_stage_academic_record();
    PERFORM rep_warehouse.etl_stage_post_school_clients();
    PERFORM rep_warehouse.etl_stage_guides();
    PERFORM rep_warehouse.etl_stage_cama_members();
    PERFORM rep_warehouse.etl_stage_grant_recipients();
    PERFORM rep_warehouse.etl_stage_loan_recipients();
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_kpi_staging()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    PERFORM rep_warehouse.etl_stage_all_kpis();
    PERFORM rep_warehouse.etl_stage_level_one_kpis();
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_warehouse()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    PERFORM rep_warehouse.etl_load_dim_roc_geography();
    PERFORM rep_warehouse.etl_load_dim_roc_project_code();
    PERFORM rep_warehouse.etl_load_dim_roc_donor();
    PERFORM rep_warehouse.etl_load_dim_roc_donor_activity();
    PERFORM rep_warehouse.etl_load_dim_geography();
    PERFORM rep_warehouse.etl_load_dim_school();
    PERFORM rep_warehouse.etl_load_dim_contact();
    PERFORM rep_warehouse.etl_load_fact_children_supported();
    PERFORM rep_warehouse.etl_load_fact_guide_assignment();
    PERFORM rep_warehouse.etl_load_fact_cama_membership();
    PERFORM rep_warehouse.etl_load_fact_post_school_support();
    PERFORM rep_warehouse.etl_load_fact_grants();
    PERFORM rep_warehouse.etl_load_fact_loans();
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_kpi_warehouse()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    PERFORM rep_warehouse.etl_load_dim_geography_kpi();
    PERFORM rep_warehouse.etl_load_dim_kpi();
    PERFORM rep_warehouse.etl_load_fact_observed_kpi();
    PERFORM rep_warehouse.etl_load_fact_level_one_kpis();
END;
$$;

-- Top-level pipeline wrappers — set session variables, log to etl_batch_log, call sub-steps.
-- etl_run_salesforce accepts an optional p_batch_id to share the UUID with ingest_run.run_id.
-- etl_run_kpis generates its own UUID (KPI pipeline runs independently of Salesforce ingest).

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce(
    p_source_system TEXT DEFAULT 'Salesforce_CAMFED',
    p_source_file   TEXT DEFAULT 'salesforce',
    p_batch_id      TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw
AS $$
DECLARE
    v_batch_id TEXT;
    v_err_msg  TEXT;
BEGIN
    v_batch_id := COALESCE(p_batch_id, gen_random_uuid()::text);

    PERFORM set_config('app.batch_id',      v_batch_id,      true);
    PERFORM set_config('app.source_system', p_source_system, true);
    PERFORM set_config('app.source_file',   p_source_file,   true);

    INSERT INTO rep_warehouse.etl_batch_log (batch_id, status, source_system)
    VALUES (v_batch_id, 'running', p_source_system);

    BEGIN
        PERFORM rep_warehouse.etl_run_staging();
        PERFORM rep_warehouse.etl_run_warehouse();

        UPDATE rep_warehouse.etl_batch_log
        SET status = 'success', finished_at = NOW()
        WHERE batch_id = v_batch_id;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT;
        UPDATE rep_warehouse.etl_batch_log
        SET status = 'failed', finished_at = NOW(), error_message = v_err_msg
        WHERE batch_id = v_batch_id;
        RAISE;
    END;

    RETURN v_batch_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_kpis(
    p_source_system TEXT DEFAULT 'Excel_CAMFED',
    p_source_file   TEXT DEFAULT 'kpis.xlsx'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw
AS $$
DECLARE
    v_batch_id TEXT;
    v_err_msg  TEXT;
BEGIN
    v_batch_id := gen_random_uuid()::text;

    PERFORM set_config('app.batch_id',      v_batch_id,      true);
    PERFORM set_config('app.source_system', p_source_system, true);
    PERFORM set_config('app.source_file',   p_source_file,   true);

    INSERT INTO rep_warehouse.etl_batch_log (batch_id, status, source_system)
    VALUES (v_batch_id, 'running', p_source_system);

    BEGIN
        PERFORM rep_warehouse.etl_run_kpi_staging();
        PERFORM rep_warehouse.etl_run_kpi_warehouse();

        UPDATE rep_warehouse.etl_batch_log
        SET status = 'success', finished_at = NOW()
        WHERE batch_id = v_batch_id;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT;
        UPDATE rep_warehouse.etl_batch_log
        SET status = 'failed', finished_at = NOW(), error_message = v_err_msg
        WHERE batch_id = v_batch_id;
        RAISE;
    END;

    RETURN v_batch_id;
END;
$$;


-- ══════════════════════════════════════════════════════════════════════════════
-- Grants
-- ══════════════════════════════════════════════════════════════════════════════

-- Staging — Salesforce
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_dimension_1_roc()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_dimension_2_roc()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_dimension_3_roc()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_dimension_4_roc()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_countries()           TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_districts()           TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_contacts()            TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_schools()             TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_academic_record()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_post_school_clients() TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_guides()              TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_cama_members()        TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_grant_recipients()    TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_loan_recipients()     TO service_role;

-- Staging — KPI
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_all_kpis()            TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_stage_level_one_kpis()      TO service_role;

-- Warehouse load — Salesforce
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_roc_geography()        TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_roc_project_code()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_roc_donor()            TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_roc_donor_activity()   TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_geography()            TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_school()               TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_contact()              TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_children_supported()  TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_guide_assignment()    TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_cama_membership()     TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_post_school_support() TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_grants()              TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_loans()               TO service_role;

-- Warehouse load — KPI
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_geography_kpi()        TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_kpi()                  TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_observed_kpi()        TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_level_one_kpis()      TO service_role;

-- Orchestration
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_staging()                   TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_kpi_staging()               TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_warehouse()                 TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_kpi_warehouse()             TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce(TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_kpis(TEXT, TEXT)            TO service_role;


-- ===== 20250201000008_ingest_state_machine.sql =====
-- Ingest run state machine: tables and lease helper functions.
--
-- ingest_run  — one row per pipeline run; at most one active run at a time.
-- ingest_fn_state — one row per ingest function per run; tracks cursor + progress.
--
-- The orchestrator claims runs via ingest_claim_run() (FOR UPDATE SKIP LOCKED),
-- extends the lease with ingest_heartbeat(), releases with ingest_release_run() when
-- the Edge Function budget is exhausted, and finishes with ingest_finish_run().

-- ── ingest_run ────────────────────────────────────────────────────────────────

CREATE TABLE rep_warehouse.ingest_run (
  run_id            TEXT        PRIMARY KEY,
  status            TEXT        NOT NULL DEFAULT 'in_progress'
                                CHECK (status IN ('in_progress', 'leased', 'completed', 'failed')),
  since             TEXT,                          -- SOQL delta filter; NULL = full load
  current_wave      SMALLINT    NOT NULL DEFAULT 1, -- wave currently in progress (1–4)
  max_pages         INTEGER,                        -- page cap for test runs; NULL = unlimited
  started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at       TIMESTAMPTZ,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  lease_owner       TEXT,
  lease_expires_at  TIMESTAMPTZ,
  attempt_count     INT         NOT NULL DEFAULT 0,
  started_by        TEXT        NOT NULL DEFAULT 'trigger',
  error             TEXT
);

-- Only one active run may exist at a time, whether resumable or currently leased.
CREATE UNIQUE INDEX ingest_run_single_active_idx
  ON rep_warehouse.ingest_run ((1))
  WHERE status IN ('in_progress', 'leased');

-- ── ingest_fn_state ───────────────────────────────────────────────────────────

CREATE TABLE rep_warehouse.ingest_fn_state (
  run_id         TEXT        NOT NULL REFERENCES rep_warehouse.ingest_run (run_id) ON DELETE CASCADE,
  fn_name        TEXT        NOT NULL,
  wave           SMALLINT    NOT NULL,
  status         TEXT        NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'running', 'completed', 'failed')),
  cursor         TEXT,                          -- Salesforce nextRecordsUrl for resuming pagination
  start_row_id   INT         NOT NULL DEFAULT 1,
  rows_fetched   INT         NOT NULL DEFAULT 0,
  pages_fetched  INT         NOT NULL DEFAULT 0, -- cumulative pages across resume ticks
  attempt_count  INT         NOT NULL DEFAULT 0,
  started_at     TIMESTAMPTZ,
  last_cursor_at TIMESTAMPTZ,
  last_error_at  TIMESTAMPTZ,
  finished_at    TIMESTAMPTZ,
  error          TEXT,
  PRIMARY KEY (run_id, fn_name)
);

-- ── Lease helper functions ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.ingest_start_run(
  p_run_id       TEXT,
  p_since        TEXT    DEFAULT NULL,
  p_started_by   TEXT    DEFAULT 'trigger',
  p_lease_owner  TEXT    DEFAULT NULL,
  p_lease_ms     INTEGER DEFAULT 360000,
  p_max_pages    INTEGER DEFAULT NULL
)
RETURNS TABLE (
  run_id       TEXT,
  since        TEXT,
  current_wave SMALLINT,
  status       TEXT,
  updated_at   TIMESTAMPTZ,
  max_pages    INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
  INSERT INTO rep_warehouse.ingest_run (
    run_id, since, current_wave, status, started_at, updated_at,
    last_heartbeat_at, lease_owner, lease_expires_at, attempt_count, started_by, max_pages
  )
  VALUES (
    p_run_id, p_since, 1, 'leased', NOW(), NOW(), NOW(),
    p_lease_owner,
    NOW() + (p_lease_ms * INTERVAL '1 millisecond'),
    1, p_started_by, p_max_pages
  )
  RETURNING
    ingest_run.run_id, ingest_run.since, ingest_run.current_wave,
    ingest_run.status, ingest_run.updated_at, ingest_run.max_pages;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.ingest_claim_run(
  p_lease_owner TEXT,
  p_lease_ms    INTEGER DEFAULT 360000
)
RETURNS TABLE (
  run_id       TEXT,
  since        TEXT,
  current_wave SMALLINT,
  status       TEXT,
  updated_at   TIMESTAMPTZ,
  max_pages    INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
  WITH candidate AS (
    SELECT r.run_id
    FROM rep_warehouse.ingest_run r
    WHERE r.status = 'in_progress'
       OR (r.status = 'leased' AND r.lease_expires_at IS NOT NULL AND r.lease_expires_at <= NOW())
    ORDER BY r.started_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  ), claimed AS (
    UPDATE rep_warehouse.ingest_run r
    SET status           = 'leased',
        lease_owner      = p_lease_owner,
        lease_expires_at = NOW() + (p_lease_ms * INTERVAL '1 millisecond'),
        updated_at       = NOW(),
        last_heartbeat_at = NOW(),
        attempt_count    = r.attempt_count + 1
    FROM candidate
    WHERE r.run_id = candidate.run_id
    RETURNING r.run_id, r.since, r.current_wave, r.status, r.updated_at, r.max_pages
  )
  SELECT claimed.run_id, claimed.since, claimed.current_wave,
         claimed.status, claimed.updated_at, claimed.max_pages
  FROM claimed;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.ingest_heartbeat(
  p_run_id       TEXT,
  p_lease_owner  TEXT,
  p_lease_ms     INTEGER DEFAULT 360000
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
BEGIN
  UPDATE rep_warehouse.ingest_run
  SET updated_at        = NOW(),
      last_heartbeat_at = NOW(),
      lease_expires_at  = NOW() + (p_lease_ms * INTERVAL '1 millisecond')
  WHERE run_id      = p_run_id
    AND status      = 'leased'
    AND lease_owner = p_lease_owner;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ingest_heartbeat: run % is not leased by %', p_run_id, p_lease_owner;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.ingest_release_run(
  p_run_id      TEXT,
  p_lease_owner TEXT,
  p_error       TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
BEGIN
  UPDATE rep_warehouse.ingest_run
  SET status            = 'in_progress',
      lease_owner       = NULL,
      lease_expires_at  = NULL,
      updated_at        = NOW(),
      last_heartbeat_at = NOW(),
      error             = COALESCE(p_error, error)
  WHERE run_id      = p_run_id
    AND status      = 'leased'
    AND lease_owner = p_lease_owner;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ingest_release_run: run % is not leased by %', p_run_id, p_lease_owner;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.ingest_finish_run(
  p_run_id      TEXT,
  p_lease_owner TEXT,
  p_status      TEXT,
  p_error       TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF p_status NOT IN ('completed', 'failed') THEN
    RAISE EXCEPTION 'ingest_finish_run: invalid status %', p_status;
  END IF;

  UPDATE rep_warehouse.ingest_run
  SET status            = p_status,
      finished_at       = NOW(),
      updated_at        = NOW(),
      last_heartbeat_at = NOW(),
      lease_owner       = NULL,
      lease_expires_at  = NULL,
      error             = p_error
  WHERE run_id      = p_run_id
    AND status      = 'leased'
    AND lease_owner = p_lease_owner;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ingest_finish_run: run % is not leased by %', p_run_id, p_lease_owner;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.ingest_start_run(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.ingest_claim_run(TEXT, INTEGER)                            TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.ingest_heartbeat(TEXT, TEXT, INTEGER)                      TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.ingest_release_run(TEXT, TEXT, TEXT)                       TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.ingest_finish_run(TEXT, TEXT, TEXT, TEXT)                  TO service_role;


-- ===== 20250201000009_ingest_cron.sql =====
-- pg_cron setup helpers for the ingest pipeline.
--
-- Why functions instead of scheduling directly in the migration:
--   - the HTTP target URL and service-role bearer token are environment-specific
--   - operators need a repeatable, explicit way to (re)configure and disable schedules
--
-- SECURITY: Pass p_vault_secret_name (recommended) to avoid storing the bearer token
-- in plaintext in cron.job. First store it in Supabase Vault:
--   SELECT vault.create_secret('Bearer <service-role-key>', 'ingest_auth_header');
-- Then call:
--   SELECT rep_warehouse.configure_ingest_cron('https://<project>.supabase.co', p_vault_secret_name := 'ingest_auth_header');
--
-- If p_vault_secret_name is provided the cron command resolves the token at runtime
-- from vault.decrypted_secrets — the key is never stored in cron.job.
-- Passing p_service_role_key directly embeds it in plaintext in cron.job; only use
-- this for local development where vault is unavailable.

CREATE OR REPLACE FUNCTION rep_warehouse.disable_ingest_cron()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
DECLARE
  v_job RECORD;
BEGIN
  FOR v_job IN
    SELECT jobid
    FROM cron.job
    WHERE jobname IN ('ingest-resume', 'ingest-trigger')
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.configure_ingest_cron(
  p_supabase_url       TEXT,
  p_service_role_key   TEXT DEFAULT NULL,
  p_vault_secret_name  TEXT DEFAULT NULL,
  p_resume_schedule    TEXT DEFAULT '*/5 * * * *',
  p_trigger_schedule   TEXT DEFAULT '0 2 * * *'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, public
AS $$
DECLARE
  v_auth_expr       TEXT;
  v_resume_command  TEXT;
  v_trigger_command TEXT;
BEGIN
  IF COALESCE(TRIM(p_supabase_url), '') = '' THEN
    RAISE EXCEPTION 'configure_ingest_cron: p_supabase_url is required';
  END IF;

  IF p_vault_secret_name IS NULL AND COALESCE(TRIM(p_service_role_key), '') = '' THEN
    RAISE EXCEPTION 'configure_ingest_cron: provide p_vault_secret_name (recommended) or p_service_role_key';
  END IF;

  -- Vault path: resolved at runtime, key never stored in cron.job.
  -- Direct path: key embedded in plaintext — only for local dev.
  IF p_vault_secret_name IS NOT NULL THEN
    v_auth_expr := format(
      '(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = %L)',
      p_vault_secret_name
    );
  ELSE
    RAISE WARNING 'configure_ingest_cron: embedding service_role_key in plaintext — use p_vault_secret_name in production';
    v_auth_expr := format('%L', 'Bearer ' || p_service_role_key);
  END IF;

  PERFORM rep_warehouse.disable_ingest_cron();

  v_resume_command := format($fmt$
    SELECT net.http_post(
      url     := %L,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', %s
      ),
      body    := '{}'::jsonb
    );
  $fmt$, p_supabase_url || '/functions/v1/ingest-orchestrator', v_auth_expr);

  v_trigger_command := format($fmt$
    SELECT net.http_post(
      url     := %L,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', %s
      ),
      body    := '{}'::jsonb
    );
  $fmt$, p_supabase_url || '/functions/v1/ingest-trigger', v_auth_expr);

  PERFORM cron.schedule('ingest-resume',  p_resume_schedule,  v_resume_command);
  PERFORM cron.schedule('ingest-trigger', p_trigger_schedule, v_trigger_command);
END;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.disable_ingest_cron() TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.configure_ingest_cron(TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION rep_warehouse.configure_ingest_cron(TEXT, TEXT, TEXT, TEXT, TEXT) IS
  'Configures the ingest pg_cron jobs. '
  'Preferred (production): SELECT rep_warehouse.configure_ingest_cron(''https://<project>.supabase.co'', p_vault_secret_name := ''ingest_auth_header''); '
  'Local dev only: SELECT rep_warehouse.configure_ingest_cron(''http://host.docker.internal:54321'', p_service_role_key := ''<key>'');';


-- ===== 20250201000010_kpi_upload.sql =====
-- KPI upload portal: audit tables and SQL functions.
--
-- The kpi-upload and kpi-level-one-upload Edge Functions insert parsed Excel rows into
-- rep_raw then call these functions to run staging, validation, and fact upsert.
-- Both functions are SECURITY DEFINER; on failure they commit the audit log row then
-- return a FAILED status (the Edge Function maps that to HTTP 4xx).

-- ── Upload audit tables ───────────────────────────────────────────────────────

-- One row per All_KPIs upload attempt (one per year in the file)
CREATE TABLE rep_raw.upload_log (
    id             BIGSERIAL   PRIMARY KEY,
    batch_id       TEXT        NOT NULL,
    year           INTEGER     NOT NULL,
    row_count      INTEGER     NOT NULL DEFAULT 0,
    rows_loaded    INTEGER     NOT NULL DEFAULT 0,
    rows_unmatched INTEGER     NOT NULL DEFAULT 0,
    rows_duplicate INTEGER     NOT NULL DEFAULT 0,
    status         TEXT        NOT NULL,   -- SUCCESS | FAILED
    error_msg      TEXT,
    uploaded_by    TEXT,
    source_file    TEXT,
    inserted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- KPI IDs in the upload file with no matching dim_kpi entry
CREATE TABLE rep_raw.unmatched_rows (
    id               BIGSERIAL   PRIMARY KEY,
    batch_id         TEXT        NOT NULL,
    kpi_id           TEXT        NOT NULL,
    row_count        INTEGER     NOT NULL DEFAULT 1,
    sample_year      INTEGER,
    sample_country   TEXT,
    sample_indicator TEXT,
    inserted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fact-key collisions within a single upload (DISTINCT ON picks one winner)
CREATE TABLE rep_raw.duplicate_rows (
    id                       BIGSERIAL   PRIMARY KEY,
    batch_id                 TEXT        NOT NULL,
    kpi_id                   TEXT        NOT NULL,
    kpi_group                TEXT,
    year                     INTEGER,
    disaggregation_level_one TEXT,
    disaggregation_level_two TEXT,
    row_scope                TEXT,
    occurrences              INTEGER     NOT NULL DEFAULT 2,
    row_ids                  TEXT[],
    inserted_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per Level 1 KPIs upload attempt
CREATE TABLE rep_raw.level_one_upload_log (
    id           BIGSERIAL   PRIMARY KEY,
    batch_id     TEXT        NOT NULL,
    rows_added   INTEGER     NOT NULL DEFAULT 0,
    rows_updated INTEGER     NOT NULL DEFAULT 0,
    total_rows   INTEGER     NOT NULL DEFAULT 0,
    status       TEXT        NOT NULL,   -- SUCCESS | FAILED
    error_msg    TEXT,
    uploaded_by  TEXT,
    source_file  TEXT,
    inserted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── kpi_upload_all ────────────────────────────────────────────────────────────
--
-- Processes one year of All_KPIs data already inserted into rep_raw.all_kpis.
-- Steps: rebuild staging → log unmatched/duplicates → year-scoped replace in fact table → audit log.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_all(
    p_batch_id    TEXT,
    p_year        INTEGER,
    p_source_file TEXT,
    p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path   = rep_warehouse, rep_staging, rep_raw, public
SET statement_timeout = 0
AS $$
DECLARE
    v_row_count      INTEGER := 0;
    v_total_staged   INTEGER := 0;
    v_rows_loaded    INTEGER := 0;
    v_rows_unmatched INTEGER := 0;
    v_rows_dup       INTEGER := 0;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    SELECT COUNT(*) INTO v_row_count
    FROM rep_raw.all_kpis
    WHERE batch_id = p_batch_id
      AND year_of_kpis IS NOT NULL
      AND year_of_kpis::integer = p_year;

    PERFORM rep_warehouse.etl_run_kpi_staging();

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis
    WHERE year = p_year;

    -- Unmatched KPI IDs
    SELECT COUNT(*) INTO v_rows_unmatched
    FROM rep_staging.all_kpis s
    LEFT JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
    WHERE dk.id IS NULL
      AND s.year = p_year;

    IF v_rows_unmatched > 0 THEN
        INSERT INTO rep_raw.unmatched_rows
            (batch_id, kpi_id, row_count, sample_year, sample_country, sample_indicator)
        SELECT
            p_batch_id,
            COALESCE(s.kpi_id, '(null)'),
            COUNT(*),
            MIN(s.year),
            MIN(s.country),
            MIN(s.indicator)
        FROM rep_staging.all_kpis s
        LEFT JOIN rep_warehouse.dim_kpi dk
               ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
        WHERE dk.id IS NULL
          AND s.year = p_year
        GROUP BY COALESCE(s.kpi_id, '(null)');
    END IF;

    -- Duplicate fact-key combinations
    WITH deduped_rows AS (
        SELECT DISTINCT
            kpi_id, kpi_group, year,
            disaggregation_level_one, disaggregation_level_two,
            row_scope, row_id
        FROM rep_staging.all_kpis
        WHERE year = p_year
    )
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_id, kpi_group, year,
        disaggregation_level_one, disaggregation_level_two,
        row_scope,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM deduped_rows
    GROUP BY kpi_id, kpi_group, year,
             disaggregation_level_one, disaggregation_level_two, row_scope
    HAVING COUNT(*) > 1;

    -- Year-scoped replace
    DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope
        )
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM rep_staging.all_kpis s
        WHERE s.year = p_year
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        (SELECT id FROM rep_warehouse.dim_geography
         WHERE country = s.country AND province IS NULL AND district IS NULL
         LIMIT 1),
        s.year,
        dd.id,
        s.disaggregation_level_one,
        s.disaggregation_level_two,
        s.value_type,
        s.row_scope,
        s.value,
        NULLIF(s.updated_date, '')::date,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    LEFT JOIN rep_warehouse.dim_kpi  dk ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date dd ON dd.id = ((s.year::text || '0101')::integer);

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

    SELECT COALESCE(SUM(occurrences - 1), 0) INTO v_rows_dup
    FROM rep_raw.duplicate_rows
    WHERE batch_id = p_batch_id;

    INSERT INTO rep_raw.upload_log
        (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, v_rows_unmatched, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     v_rows_unmatched,
        'rows_skipped_duplicate', v_rows_dup
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.upload_log
        (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, 0, 0, 0, 0,
         'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;


-- ── kpi_upload_level_one ──────────────────────────────────────────────────────
--
-- Processes Level 1 KPI rows already inserted into rep_raw.level_one_kpis.
-- Works directly from rep_raw (no staging step) to preserve batch scoping.
-- UPSERT into fact_level_one_kpis via the unique expression index.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_level_one(
    p_batch_id    TEXT,
    p_source_file TEXT,
    p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path   = rep_warehouse, rep_staging, rep_raw, public
SET statement_timeout = 0
AS $$
DECLARE
    v_total_rows   INTEGER := 0;
    v_rows_updated INTEGER := 0;
    v_rows_added   INTEGER := 0;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    SELECT COUNT(*) INTO v_total_rows
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                         -1),
            COALESCE(TRIM(s.school_level),          ''),
            COALESCE(TRIM(s.annual_newly_supported),''),
            COALESCE(TRIM(s.type),                  ''),
            COALESCE(TRIM(s.gender),                '')
        ) s.row_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year    IS NOT NULL
          AND s.country IS NOT NULL
          AND s.kpi     IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                         -1),
            COALESCE(TRIM(s.school_level),          ''),
            COALESCE(TRIM(s.annual_newly_supported),''),
            COALESCE(TRIM(s.type),                  ''),
            COALESCE(TRIM(s.gender),                ''),
            s.row_id DESC
    ) _t;

    SELECT COUNT(*) INTO v_rows_updated
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                         -1),
            COALESCE(TRIM(s.school_level),          ''),
            COALESCE(TRIM(s.annual_newly_supported),''),
            COALESCE(TRIM(s.type),                  ''),
            COALESCE(TRIM(s.gender),                '')
        )
            s.year::smallint                 AS year,
            dg.id                            AS geography_id,
            TRIM(s.school_level)             AS school_level,
            TRIM(s.annual_newly_supported)   AS annual_newly_supported,
            TRIM(s.type)                     AS fund_type,
            TRIM(s.gender)                   AS gender
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                         -1),
            COALESCE(TRIM(s.school_level),          ''),
            COALESCE(TRIM(s.annual_newly_supported),''),
            COALESCE(TRIM(s.type),                  ''),
            COALESCE(TRIM(s.gender),                ''),
            s.row_id DESC
    ) deduped
    WHERE EXISTS (
        SELECT 1 FROM rep_warehouse.fact_level_one_kpis f
        WHERE f.year                                   = deduped.year
          AND COALESCE(f.geography_id,           -1)  = COALESCE(deduped.geography_id,           -1)
          AND COALESCE(f.school_level,           '')  = COALESCE(deduped.school_level,           '')
          AND COALESCE(f.annual_newly_supported, '')  = COALESCE(deduped.annual_newly_supported, '')
          AND COALESCE(f.fund_type,              '')  = COALESCE(deduped.fund_type,              '')
          AND COALESCE(f.gender,                 '')  = COALESCE(deduped.gender,                 '')
    );

    v_rows_added := v_total_rows - v_rows_updated;

    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                         -1),
            COALESCE(TRIM(s.school_level),          ''),
            COALESCE(TRIM(s.annual_newly_supported),''),
            COALESCE(TRIM(s.type),                  ''),
            COALESCE(TRIM(s.gender),                '')
        )
            s.row_id,
            s.year::smallint                 AS year,
            TRIM(s.kpi)                      AS kpi,
            TRIM(s.school_level)             AS school_level,
            TRIM(s.annual_newly_supported)   AS annual_newly_supported,
            TRIM(s.type)                     AS fund_type,
            TRIM(s.gender)                   AS gender,
            TRIM(s.disaggregation_gender)    AS disaggregation_gender,
            CASE
                WHEN REPLACE(s.value::TEXT, ',', '') ~ '^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$'
                THEN REPLACE(s.value::TEXT, ',', '')::NUMERIC
            END                              AS value,
            dg.id                            AS geography_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                         -1),
            COALESCE(TRIM(s.school_level),          ''),
            COALESCE(TRIM(s.annual_newly_supported),''),
            COALESCE(TRIM(s.type),                  ''),
            COALESCE(TRIM(s.gender),                ''),
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_level_one_kpis
        (kpi_id, geography_id, year_date_id, year,
         school_level, annual_newly_supported, fund_type, gender, disaggregation_gender,
         value,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        (SELECT id FROM rep_warehouse.dim_kpi
          WHERE source_kpi_id = s.kpi AND scd_is_current = true
          LIMIT 1),
        s.geography_id,
        dd.id,
        s.year,
        s.school_level, s.annual_newly_supported, s.fund_type, s.gender, s.disaggregation_gender,
        s.value,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    LEFT JOIN rep_warehouse.dim_date dd ON dd.id = ((s.year::text || '0101')::integer)
    ON CONFLICT (
        year,
        COALESCE(geography_id,            -1),
        COALESCE(school_level,            ''),
        COALESCE(annual_newly_supported,  ''),
        COALESCE(fund_type,               ''),
        COALESCE(gender,                  '')
    )
    DO UPDATE SET
        kpi_id                = EXCLUDED.kpi_id,
        disaggregation_gender = EXCLUDED.disaggregation_gender,
        value                 = EXCLUDED.value,
        lin_is_current        = true,
        lin_change_type       = 'UPDATE',
        lin_source_system     = EXCLUDED.lin_source_system,
        lin_source_file       = EXCLUDED.lin_source_file,
        lin_load_batch_id     = EXCLUDED.lin_load_batch_id,
        lin_source_row_number = EXCLUDED.lin_source_row_number;

    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, uploaded_by, source_file)
    VALUES
        (p_batch_id, v_rows_added, v_rows_updated, v_total_rows,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',       'SUCCESS',
        'batch_id',     p_batch_id,
        'rows_added',   v_rows_added,
        'rows_updated', v_rows_updated,
        'total_rows',   v_total_rows,
        'message',      format('Loaded %s rows: %s added, %s updated',
                               v_total_rows, v_rows_added, v_rows_updated)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, 0, 0, 0, 'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_upload_all(TEXT, INTEGER, TEXT, TEXT)  TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_upload_level_one(TEXT, TEXT, TEXT)     TO service_role;


-- ===== 20250201000011_security.sql =====
-- Security: schema grants, RLS, view access, admin helpers.
--
-- Strategy:
--   rep_raw          — service_role only; anon/authenticated have no access
--   rep_warehouse    — dim/fact tables: RLS enabled with no permissive policy (default deny)
--                    — view_* views: GRANT SELECT TO authenticated only
--                    — etl_batch_log: authenticated can read (data freshness)
--                    — ingest_run / ingest_fn_state: admin-only SELECT
--   rep_raw audit    — upload_log, unmatched_rows, etc.: authenticated can read

-- ── rep_raw grants (service_role only) ───────────────────────────────────────

GRANT USAGE ON SCHEMA rep_raw TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA rep_raw TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA rep_raw TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA rep_raw
    GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA rep_raw
    GRANT ALL ON SEQUENCES TO service_role;

-- ── rep_warehouse grants (service_role) ──────────────────────────────────────

GRANT USAGE ON SCHEMA rep_warehouse TO service_role;
GRANT SELECT ON rep_warehouse.etl_batch_log TO service_role;
GRANT ALL ON rep_warehouse.ingest_run TO service_role;
GRANT ALL ON rep_warehouse.ingest_fn_state TO service_role;

-- ── rep_warehouse grants (authenticated) ─────────────────────────────────────

GRANT USAGE ON SCHEMA rep_warehouse TO authenticated;

-- ── Admin helper ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
$$;

-- ── RLS on dim/fact tables — default deny ─────────────────────────────────────
-- No permissive policies are added, so direct table queries are blocked for all roles.
-- Views run as their owner (bypassing RLS), so view_* access works via the grants below.

ALTER TABLE rep_warehouse.dim_roc_geography      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_roc_project_code   ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_roc_donor          ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_roc_donor_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_date               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_geography          ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_school             ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_contact            ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.dim_kpi                ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_children_supported  ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_guide_assignment    ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_cama_membership     ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_post_school_support ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_grants              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_loans               ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_observed_kpi        ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_warehouse.fact_level_one_kpis      ENABLE ROW LEVEL SECURITY;

-- ── etl_batch_log — authenticated can read ───────────────────────────────────

ALTER TABLE rep_warehouse.etl_batch_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY etl_batch_log_select
    ON rep_warehouse.etl_batch_log
    FOR SELECT TO authenticated
    USING (true);

-- ── ingest_run / ingest_fn_state — admin-only ────────────────────────────────

ALTER TABLE rep_warehouse.ingest_run ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON rep_warehouse.ingest_run TO authenticated;

CREATE POLICY admin_read_ingest_run
    ON rep_warehouse.ingest_run
    FOR SELECT TO authenticated
    USING (rep_warehouse.is_admin());

ALTER TABLE rep_warehouse.ingest_fn_state ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON rep_warehouse.ingest_fn_state TO authenticated;

CREATE POLICY admin_read_ingest_fn_state
    ON rep_warehouse.ingest_fn_state
    FOR SELECT TO authenticated
    USING (rep_warehouse.is_admin());

-- ── View grants (authenticated only; anon intentionally excluded) ─────────────

GRANT SELECT ON rep_warehouse.view_children_supported  TO authenticated;
GRANT SELECT ON rep_warehouse.view_guide_assignment    TO authenticated;
GRANT SELECT ON rep_warehouse.view_cama_membership     TO authenticated;
GRANT SELECT ON rep_warehouse.view_post_school_support TO authenticated;
GRANT SELECT ON rep_warehouse.view_grants              TO authenticated;
GRANT SELECT ON rep_warehouse.view_loans               TO authenticated;
GRANT SELECT ON rep_warehouse.view_observed_kpi        TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_counts          TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_percentages     TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_targets         TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_cumulative      TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_detail          TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_subtotals       TO authenticated;
GRANT SELECT ON rep_warehouse.view_kpi_benchmarks      TO authenticated;
GRANT SELECT ON rep_warehouse.view_level_one_kpis      TO authenticated;
GRANT SELECT ON rep_warehouse.view_donor_summary       TO authenticated;
GRANT SELECT ON rep_warehouse.view_school_map          TO authenticated;
GRANT SELECT ON rep_warehouse.etl_batch_log            TO authenticated;

-- ── rep_raw KPI audit tables — authenticated can read ────────────────────────

ALTER TABLE rep_raw.upload_log           ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_raw.unmatched_rows       ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_raw.duplicate_rows       ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_raw.level_one_upload_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY upload_log_select
    ON rep_raw.upload_log FOR SELECT TO authenticated USING (true);

CREATE POLICY unmatched_rows_select
    ON rep_raw.unmatched_rows FOR SELECT TO authenticated USING (true);

CREATE POLICY duplicate_rows_select
    ON rep_raw.duplicate_rows FOR SELECT TO authenticated USING (true);

CREATE POLICY level_one_upload_log_select
    ON rep_raw.level_one_upload_log FOR SELECT TO authenticated USING (true);

GRANT USAGE  ON SCHEMA rep_raw                    TO authenticated;
GRANT SELECT ON rep_raw.upload_log                TO authenticated;
GRANT SELECT ON rep_raw.unmatched_rows            TO authenticated;
GRANT SELECT ON rep_raw.duplicate_rows            TO authenticated;
GRANT SELECT ON rep_raw.level_one_upload_log      TO authenticated;

-- ── Admin helper function ─────────────────────────────────────────────────────
-- Manual admin helper — NOT called by the normal ingest pipeline.
-- Use to force a full table wipe before a manual re-seed:
--   SELECT rep_raw.truncate_table('academic_record');

CREATE OR REPLACE FUNCTION rep_raw.truncate_table(p_table TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    EXECUTE format('TRUNCATE rep_raw.%I', p_table);
END;
$$;


-- ===== 20250201000012_portal_whatsapp_users.sql =====
-- =============================================================================
-- rep_portal schema: WhatsApp user registry + district access workflow
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS rep_portal;

-- ---------------------------------------------------------------------------
-- Sequence: portal_id (CD100000, CD100001, ...)
-- ---------------------------------------------------------------------------
CREATE SEQUENCE rep_portal.whatsapp_portal_id_seq START 100000;

-- ---------------------------------------------------------------------------
-- Table 1: whatsapp_users
-- Core registry for both WhatsApp-registered and portal-only users.
-- Portal-only rows (auto-created by auth trigger) have phone = ''.
-- ---------------------------------------------------------------------------
CREATE TABLE rep_portal.whatsapp_users (
    id                BIGSERIAL    PRIMARY KEY,
    portal_id         TEXT         NOT NULL UNIQUE
                        DEFAULT ('CD' || nextval('rep_portal.whatsapp_portal_id_seq')::TEXT),
    phone             TEXT         NOT NULL,     -- not unique; '' for portal-only rows
    name              TEXT,
    email             TEXT,
    supabase_user_id  UUID         UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
    is_approver       BOOLEAN      NOT NULL DEFAULT FALSE,
    linked_at         TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX whatsapp_users_phone_idx     ON rep_portal.whatsapp_users (phone);
CREATE INDEX whatsapp_users_email_idx     ON rep_portal.whatsapp_users (email)     WHERE email IS NOT NULL;
CREATE INDEX whatsapp_users_portal_id_idx ON rep_portal.whatsapp_users (portal_id);

-- ---------------------------------------------------------------------------
-- Table 2: whatsapp_approver_districts
-- Districts an approver is responsible for. Only populated when is_approver = true.
-- ---------------------------------------------------------------------------
CREATE TABLE rep_portal.whatsapp_approver_districts (
    id               BIGSERIAL    PRIMARY KEY,
    whatsapp_user_id BIGINT       NOT NULL REFERENCES rep_portal.whatsapp_users(id) ON DELETE CASCADE,
    district_id      TEXT         NOT NULL,    -- dim_geography.source_district_id
    district_name    TEXT         NOT NULL,    -- denormalised for display
    assigned_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (whatsapp_user_id, district_id)
);

CREATE INDEX wad_user_idx     ON rep_portal.whatsapp_approver_districts (whatsapp_user_id);
CREATE INDEX wad_district_idx ON rep_portal.whatsapp_approver_districts (district_id);

-- ---------------------------------------------------------------------------
-- Table 3: whatsapp_district_access
-- Source of truth for a user's district membership.
-- status = 'approved' means the user IS an active member of that district.
-- One row per (requester, district); UNIQUE prevents duplicate requests.
-- ---------------------------------------------------------------------------
CREATE TABLE rep_portal.whatsapp_district_access (
    id               BIGSERIAL    PRIMARY KEY,
    requester_id     BIGINT       NOT NULL REFERENCES rep_portal.whatsapp_users(id) ON DELETE CASCADE,
    district_id      TEXT         NOT NULL,
    district_name    TEXT         NOT NULL,
    status           TEXT         NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'approved', 'rejected')),
    approver_id      BIGINT       REFERENCES rep_portal.whatsapp_users(id) ON DELETE SET NULL,
    decided_at       TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (requester_id, district_id)
);

CREATE INDEX wda_requester_idx ON rep_portal.whatsapp_district_access (requester_id);
CREATE INDEX wda_district_idx  ON rep_portal.whatsapp_district_access (district_id);
CREATE INDEX wda_status_idx    ON rep_portal.whatsapp_district_access (status);
CREATE INDEX wda_approver_idx  ON rep_portal.whatsapp_district_access (approver_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rep_portal.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER whatsapp_users_updated_at
  BEFORE UPDATE ON rep_portal.whatsapp_users
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

CREATE TRIGGER whatsapp_district_access_updated_at
  BEFORE UPDATE ON rep_portal.whatsapp_district_access
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

-- ---------------------------------------------------------------------------
-- Auth trigger: auto-create / link rep_portal.whatsapp_users when a Supabase
-- Auth user is created (via invite or signup).
-- Lives in public schema because triggers on auth.users must reference
-- a public-schema function.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
BEGIN
  -- If an existing WhatsApp-registered row has this email but no Supabase link, link it
  UPDATE rep_portal.whatsapp_users
  SET supabase_user_id = NEW.id,
      linked_at        = NOW()
  WHERE id = (
    SELECT id FROM rep_portal.whatsapp_users
    WHERE email = NEW.email AND supabase_user_id IS NULL
    ORDER BY created_at
    LIMIT 1
  );

  -- If nothing was linked, create a portal-only row (phone = '' satisfies NOT NULL)
  IF NOT FOUND THEN
    INSERT INTO rep_portal.whatsapp_users (phone, email, supabase_user_id, linked_at)
    VALUES ('', NEW.email, NEW.id, NOW());
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.on_auth_user_created();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE rep_portal.whatsapp_users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.whatsapp_approver_districts ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.whatsapp_district_access    ENABLE ROW LEVEL SECURITY;

CREATE POLICY wa_users_admin_select
  ON rep_portal.whatsapp_users
  FOR SELECT TO authenticated
  USING (rep_warehouse.is_admin());

CREATE POLICY wad_admin_select
  ON rep_portal.whatsapp_approver_districts
  FOR SELECT TO authenticated
  USING (rep_warehouse.is_admin());

CREATE POLICY wda_admin_select
  ON rep_portal.whatsapp_district_access
  FOR SELECT TO authenticated
  USING (rep_warehouse.is_admin());

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA rep_portal TO authenticated;
GRANT USAGE ON SCHEMA rep_portal TO service_role;

GRANT SELECT ON rep_portal.whatsapp_users,
               rep_portal.whatsapp_approver_districts,
               rep_portal.whatsapp_district_access    TO authenticated;

GRANT ALL ON rep_portal.whatsapp_users,
             rep_portal.whatsapp_approver_districts,
             rep_portal.whatsapp_district_access      TO service_role;

GRANT USAGE ON SEQUENCE rep_portal.whatsapp_portal_id_seq,
                        rep_portal.whatsapp_users_id_seq,
                        rep_portal.whatsapp_approver_districts_id_seq,
                        rep_portal.whatsapp_district_access_id_seq    TO service_role;


-- ===== 20250201000013_kpi_upload_dim_fix.sql =====
-- Fix KPI upload ETL: load dim_kpi before fact insert, enforce geography pre-check.
--
-- Changes:
--   1. etl_load_dim_kpi() — guarded with to_regclass() so it's safe to call when
--      only one of the two KPI staging tables exists.
--   2. kpi_upload_all() — rebuilds all_kpis staging, checks geography, loads dim_kpi,
--      then inserts facts with INNER JOIN (kpi_id and geography_id guaranteed non-null).
--      Unmatched-KPI tracking removed (dim_kpi is always loaded from the upload itself).
--   3. kpi_upload_level_one() — checks geography, rebuilds level_one staging, loads
--      dim_kpi, then upserts facts with INNER JOIN on dim_kpi.


-- ── 1. etl_load_dim_kpi: guard against missing staging tables ─────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_kpi()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    -- Load KPI definitions from all_kpis staging (if the table exists)
    IF to_regclass('rep_staging.all_kpis') IS NOT NULL THEN

        -- SCD2: expire rows whose indicator/group has changed
        UPDATE rep_warehouse.dim_kpi w
        SET
            scd_is_current    = false,
            scd_effective_to  = CURRENT_DATE - 1,
            lin_superseded_at = NOW()
        FROM (
            SELECT DISTINCT ON (kpi_id)
                kpi_id,
                MD5(concat_ws('||', COALESCE(kpi_group, ''), COALESCE(indicator, ''))) AS biz_hash
            FROM rep_staging.all_kpis
            ORDER BY kpi_id
        ) incoming
        WHERE w.source_kpi_id     = incoming.kpi_id
          AND w.scd_is_current    = true
          AND w.lin_business_hash IS DISTINCT FROM incoming.biz_hash;

        -- Insert new KPI definitions from all_kpis
        INSERT INTO rep_warehouse.dim_kpi
            (source_kpi_id, kpi_group, indicator,
             scd_effective_from, scd_is_current, scd_version,
             lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
        SELECT DISTINCT ON (kpi_id)
            kpi_id, kpi_group, indicator,
            CURRENT_DATE, true,
            COALESCE((SELECT MAX(scd_version) FROM rep_warehouse.dim_kpi WHERE source_kpi_id = kpi_id), 0) + 1,
            MD5(concat_ws('||', COALESCE(kpi_group, ''), COALESCE(indicator, ''))),
            current_setting('app.batch_id',      true),
            current_setting('app.source_system', true),
            current_setting('app.source_file',   true),
            NOW()
        FROM rep_staging.all_kpis
        WHERE NOT EXISTS (
            SELECT 1 FROM rep_warehouse.dim_kpi w
            WHERE w.source_kpi_id = kpi_id AND w.scd_is_current = true
        )
        ORDER BY kpi_id;

    END IF;

    -- Load KPI definitions from level_one_kpis staging (if the table exists)
    IF to_regclass('rep_staging.level_one_kpis') IS NOT NULL THEN

        INSERT INTO rep_warehouse.dim_kpi
            (source_kpi_id, kpi_group, indicator,
             scd_effective_from, scd_is_current, scd_version,
             lin_business_hash, lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
        SELECT DISTINCT ON (kpi)
            kpi,
            REGEXP_REPLACE(kpi, '[^0-9\.]', '', 'g') AS kpi_group,
            'KPI ' || kpi                             AS indicator,
            CURRENT_DATE, true, 1,
            MD5(concat_ws('||', REGEXP_REPLACE(kpi, '[^0-9\.]', '', 'g'), 'KPI ' || kpi)),
            current_setting('app.batch_id',      true),
            current_setting('app.source_system', true),
            current_setting('app.source_file',   true),
            NOW()
        FROM rep_staging.level_one_kpis
        WHERE NOT EXISTS (
            SELECT 1 FROM rep_warehouse.dim_kpi w
            WHERE w.source_kpi_id = kpi AND w.scd_is_current = true
        )
        ORDER BY kpi;

    END IF;
END;
$$;


-- ── 2. kpi_upload_all ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_all(
    p_batch_id    TEXT,
    p_year        INTEGER,
    p_source_file TEXT,
    p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path   = rep_warehouse, rep_staging, rep_raw, public
SET statement_timeout = 0
AS $$
DECLARE
    v_row_count         INTEGER := 0;
    v_total_staged      INTEGER := 0;
    v_rows_loaded       INTEGER := 0;
    v_rows_dup          INTEGER := 0;
    v_missing_countries TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- One successful upload per year: reject if a SUCCESS row already exists.
    IF EXISTS (
        SELECT 1 FROM rep_raw.upload_log
        WHERE year = p_year AND status = 'SUCCESS'
    ) THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, 0, 0, 0, 0, 'FAILED',
             format('Year %s already has a successful upload. Delete the existing data before uploading again.', p_year),
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  format('Year %s already has a successful upload. Delete the existing data before uploading again.', p_year)
        );
    END IF;

    SELECT COUNT(*) INTO v_row_count
    FROM rep_raw.all_kpis
    WHERE batch_id = p_batch_id
      AND year_of_kpis IS NOT NULL
      AND year_of_kpis::integer = p_year;

    -- Rebuild all_kpis staging from all raw rows
    PERFORM rep_warehouse.etl_stage_all_kpis();

    -- Geography pre-check: dim_geography must have a country-level row for every
    -- country present in this year's data. dim_geography is populated by the
    -- Salesforce ingest; KPI uploads must not create geography rows.
    SELECT STRING_AGG(DISTINCT s.country, ', ' ORDER BY s.country)
    INTO v_missing_countries
    FROM rep_staging.all_kpis s
    WHERE s.year = p_year
      AND LOWER(s.country) != 'total'
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = s.country AND g.province IS NULL AND g.district IS NULL
      );

    IF v_missing_countries IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis
    WHERE year = p_year;

    -- Load KPI definitions into dim_kpi before inserting facts.
    -- This ensures every fact row will have a non-null kpi_id.
    PERFORM rep_warehouse.etl_load_dim_kpi();

    -- Log duplicate fact-key combinations within this upload
    WITH deduped_rows AS (
        SELECT DISTINCT
            kpi_id, kpi_group, year,
            disaggregation_level_one, disaggregation_level_two,
            row_scope, row_id
        FROM rep_staging.all_kpis
        WHERE year = p_year
    )
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_id, kpi_group, year,
        disaggregation_level_one, disaggregation_level_two,
        row_scope,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM deduped_rows
    GROUP BY kpi_id, kpi_group, year,
             disaggregation_level_one, disaggregation_level_two, row_scope
    HAVING COUNT(*) > 1;

    -- Year-scoped replace: delete existing fact rows for this year then reinsert.
    -- INNER JOIN on dim_kpi and dim_geography guarantees kpi_id and geography_id
    -- are never null (the checks above ensure both dimensions are populated).
    DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope
        )
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM rep_staging.all_kpis s
        WHERE s.year = p_year
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        dg.id,
        s.year,
        dd.id,
        s.disaggregation_level_one,
        s.disaggregation_level_two,
        s.value_type,
        s.row_scope,
        s.value,
        NULLIF(s.updated_date, '')::date,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
    INNER JOIN rep_warehouse.dim_geography dg
           ON dg.country = s.country AND dg.province IS NULL AND dg.district IS NULL
    LEFT  JOIN rep_warehouse.dim_date dd
           ON dd.id = ((s.year::text || '0101')::integer);

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

    SELECT COALESCE(SUM(occurrences - 1), 0) INTO v_rows_dup
    FROM rep_raw.duplicate_rows
    WHERE batch_id = p_batch_id;

    INSERT INTO rep_raw.upload_log
        (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.upload_log
        (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, 0, 0, 0, 0, 'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;


-- ── 3. kpi_upload_level_one ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_level_one(
    p_batch_id    TEXT,
    p_source_file TEXT,
    p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path   = rep_warehouse, rep_staging, rep_raw, public
SET statement_timeout = 0
AS $$
DECLARE
    v_total_rows        INTEGER := 0;
    v_rows_updated      INTEGER := 0;
    v_rows_added        INTEGER := 0;
    v_missing_countries TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- Geography pre-check against the current batch only
    SELECT STRING_AGG(DISTINCT TRIM(s.country), ', ' ORDER BY TRIM(s.country))
    INTO v_missing_countries
    FROM rep_raw.level_one_kpis s
    WHERE s.batch_id  = p_batch_id
      AND s.country  IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = TRIM(s.country) AND g.province IS NULL AND g.district IS NULL
      );

    IF v_missing_countries IS NOT NULL THEN
        INSERT INTO rep_raw.level_one_upload_log
            (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, 0, 0, 0, 'FAILED',
             'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries
        );
    END IF;

    -- Rebuild level_one staging from all raw rows (needed for etl_load_dim_kpi)
    PERFORM rep_warehouse.etl_stage_level_one_kpis();

    -- Load KPI definitions into dim_kpi before inserting facts
    PERFORM rep_warehouse.etl_load_dim_kpi();

    -- Count distinct rows in this batch (dedup by upsert key)
    SELECT COUNT(*) INTO v_total_rows
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        ) s.row_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year    IS NOT NULL
          AND s.country IS NOT NULL
          AND s.kpi     IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    ) _t;

    -- Count rows that already exist in the warehouse (will be updated)
    SELECT COUNT(*) INTO v_rows_updated
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        )
            s.year::smallint                  AS year,
            dg.id                             AS geography_id,
            TRIM(s.school_level)              AS school_level,
            TRIM(s.annual_newly_supported)    AS annual_newly_supported,
            TRIM(s.type)                      AS fund_type,
            TRIM(s.gender)                    AS gender
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    ) deduped
    WHERE EXISTS (
        SELECT 1 FROM rep_warehouse.fact_level_one_kpis f
        WHERE f.year                                    = deduped.year
          AND COALESCE(f.geography_id,            -1)  = COALESCE(deduped.geography_id,            -1)
          AND COALESCE(f.school_level,            '')  = COALESCE(deduped.school_level,            '')
          AND COALESCE(f.annual_newly_supported,  '')  = COALESCE(deduped.annual_newly_supported,  '')
          AND COALESCE(f.fund_type,               '')  = COALESCE(deduped.fund_type,               '')
          AND COALESCE(f.gender,                  '')  = COALESCE(deduped.gender,                  '')
    );

    v_rows_added := v_total_rows - v_rows_updated;

    -- Upsert into fact table. INNER JOIN on dim_kpi guarantees kpi_id is never null
    -- (dim_kpi was loaded above from this batch's staging data).
    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        )
            s.row_id,
            s.year::smallint                  AS year,
            TRIM(s.kpi)                       AS kpi,
            TRIM(s.school_level)              AS school_level,
            TRIM(s.annual_newly_supported)    AS annual_newly_supported,
            TRIM(s.type)                      AS fund_type,
            TRIM(s.gender)                    AS gender,
            TRIM(s.disaggregation_gender)     AS disaggregation_gender,
            CASE
                WHEN REPLACE(s.value::TEXT, ',', '') ~ '^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$'
                THEN REPLACE(s.value::TEXT, ',', '')::NUMERIC
            END                               AS value,
            dg.id                             AS geography_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_level_one_kpis
        (kpi_id, geography_id, year_date_id, year,
         school_level, annual_newly_supported, fund_type, gender, disaggregation_gender,
         value,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        s.geography_id,
        dd.id,
        s.year,
        s.school_level, s.annual_newly_supported, s.fund_type, s.gender, s.disaggregation_gender,
        s.value,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi AND dk.scd_is_current = true
    LEFT  JOIN rep_warehouse.dim_date dd
           ON dd.id = ((s.year::text || '0101')::integer)
    ON CONFLICT (
        year,
        COALESCE(geography_id,            -1),
        COALESCE(school_level,            ''),
        COALESCE(annual_newly_supported,  ''),
        COALESCE(fund_type,               ''),
        COALESCE(gender,                  '')
    )
    DO UPDATE SET
        kpi_id                = EXCLUDED.kpi_id,
        disaggregation_gender = EXCLUDED.disaggregation_gender,
        value                 = EXCLUDED.value,
        lin_is_current        = true,
        lin_change_type       = 'UPDATE',
        lin_source_system     = EXCLUDED.lin_source_system,
        lin_source_file       = EXCLUDED.lin_source_file,
        lin_load_batch_id     = EXCLUDED.lin_load_batch_id,
        lin_source_row_number = EXCLUDED.lin_source_row_number;

    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, uploaded_by, source_file)
    VALUES
        (p_batch_id, v_rows_added, v_rows_updated, v_total_rows,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',       'SUCCESS',
        'batch_id',     p_batch_id,
        'rows_added',   v_rows_added,
        'rows_updated', v_rows_updated,
        'total_rows',   v_total_rows,
        'message',      format('Loaded %s rows: %s added, %s updated',
                               v_total_rows, v_rows_added, v_rows_updated)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, 0, 0, 0, 'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;


-- ===== 20250201000014_kpi_raw_reader.sql =====
-- Allow authenticated users to read raw All_KPIs rows for the year detail view.
-- Rows are scoped to the latest successful upload batch for the requested year.

CREATE OR REPLACE FUNCTION rep_warehouse.get_all_kpi_rows(
    p_year   INTEGER,
    p_limit  INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    row_id          INTEGER,
    kpi_no          TEXT,
    indicator_group TEXT,
    indicator       TEXT,
    disaggregation1 TEXT,
    disaggregation2 TEXT,
    value_type      TEXT,
    ghana           TEXT,
    malawi          TEXT,
    tanzania        TEXT,
    zambia          TEXT,
    zimbabwe        TEXT,
    total           TEXT,
    updated_date    TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, rep_warehouse, public
AS $$
    SELECT
        k.row_id::integer,
        k.kpi_no, k.indicator_group, k.indicator,
        k.disaggregation1, k.disaggregation2, k.value_type,
        k.ghana, k.malawi, k.tanzania, k.zambia, k.zimbabwe, k.total,
        k.updated_date
    FROM rep_raw.all_kpis k
    WHERE k.batch_id = (
        SELECT ul.batch_id FROM rep_raw.upload_log ul
        WHERE ul.year = p_year AND ul.status = 'SUCCESS'
        ORDER BY ul.inserted_at DESC LIMIT 1
    )
    ORDER BY k.row_id::integer
    LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.count_all_kpi_rows(p_year INTEGER)
RETURNS BIGINT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, rep_warehouse, public
AS $$
    SELECT COUNT(*)
    FROM rep_raw.all_kpis k
    WHERE k.batch_id = (
        SELECT ul.batch_id FROM rep_raw.upload_log ul
        WHERE ul.year = p_year AND ul.status = 'SUCCESS'
        ORDER BY ul.inserted_at DESC LIMIT 1
    );
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.get_all_kpi_rows(INTEGER, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_warehouse.count_all_kpi_rows(INTEGER)                 TO authenticated;


-- ===== 20250201000015_drop_kpi_bulk_etl.sql =====
-- Remove the unused bulk KPI ETL pipeline.
-- KPI data is loaded exclusively via the kpi-upload / kpi-level-one-upload edge functions
-- which call kpi_upload_all() and kpi_upload_level_one() directly.
-- The orchestrator-style wrappers (etl_run_kpis, etl_run_kpi_staging, etl_run_kpi_warehouse)
-- are never invoked and are dropped here.

DROP FUNCTION IF EXISTS rep_warehouse.etl_run_kpis(TEXT, TEXT);
DROP FUNCTION IF EXISTS rep_warehouse.etl_run_kpi_warehouse();
DROP FUNCTION IF EXISTS rep_warehouse.etl_run_kpi_staging();


-- ===== 20250201000016_whatsapp_bot_sessions.sql =====
-- =============================================================================
-- WhatsApp bot session state + consent persistence
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Ephemeral bot conversation sessions (one row per phone number)
-- ---------------------------------------------------------------------------
CREATE TABLE rep_portal.whatsapp_bot_sessions (
    id           BIGSERIAL    PRIMARY KEY,
    phone        TEXT         NOT NULL UNIQUE,
    step         TEXT         NOT NULL DEFAULT 'idle',
    context      JSONB        NOT NULL DEFAULT '{}',
    consented_at TIMESTAMPTZ,           -- set when user taps "I Agree"; cleared on session reset
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX wbs_phone_idx ON rep_portal.whatsapp_bot_sessions (phone);

CREATE TRIGGER whatsapp_bot_sessions_updated_at
  BEFORE UPDATE ON rep_portal.whatsapp_bot_sessions
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

-- RLS: service_role only (bot edge function uses service role key)
ALTER TABLE rep_portal.whatsapp_bot_sessions ENABLE ROW LEVEL SECURITY;

GRANT ALL ON rep_portal.whatsapp_bot_sessions TO service_role;
GRANT USAGE ON SEQUENCE rep_portal.whatsapp_bot_sessions_id_seq TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Persist consent onto the permanent user profile
-- ---------------------------------------------------------------------------
ALTER TABLE rep_portal.whatsapp_users
  ADD COLUMN consented_at TIMESTAMPTZ;
-- NULL = no consent recorded; non-NULL = timestamp when user agreed via WhatsApp bot


-- ===== 20250201000017_whatsapp_bot_grants.sql =====
-- Grant service_role read access to dim_geography so the WhatsApp bot
-- can populate country / province / district selection menus.
GRANT SELECT ON rep_warehouse.dim_geography TO service_role;


-- ===== 20250201000018_district_report_fns.sql =====
-- Three SQL functions called by the WhatsApp bot "View Reports" flow.
-- Each function returns aggregated data for a given district.
-- All are SECURITY DEFINER so the service_role JWT used by the Edge Function
-- can call them without needing direct grants on the underlying view tables.

-- ── 1. Children Supported ─────────────────────────────────────────────────────
-- Returns row count (girls), school count, and a formatted top-5 school list
-- for the latest year that has data for the given district.

CREATE OR REPLACE FUNCTION rep_warehouse.district_report_children(p_district TEXT)
RETURNS TABLE (
  report_year  INT,
  total_girls  BIGINT,
  school_count BIGINT,
  top_schools  TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_year INT;
BEGIN
  SELECT MAX(year) INTO v_year
  FROM rep_warehouse.view_children_supported
  WHERE district = p_district;

  IF v_year IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH per_school AS (
    SELECT school_name, COUNT(*) AS n
    FROM rep_warehouse.view_children_supported
    WHERE district = p_district AND year = v_year
    GROUP BY school_name
  ),
  agg AS (
    SELECT SUM(n)::BIGINT AS total_girls, COUNT(*)::BIGINT AS school_count
    FROM per_school
  ),
  top AS (
    SELECT string_agg('• ' || school_name || ': ' || n::TEXT, E'\n' ORDER BY n DESC) AS top_schools
    FROM (SELECT school_name, n FROM per_school ORDER BY n DESC LIMIT 5) t
  )
  SELECT v_year, agg.total_girls, agg.school_count, top.top_schools
  FROM agg, top;
END;
$$;

-- ── 2. People ─────────────────────────────────────────────────────────────────
-- Returns guide counts (active and total) and CAMA membership count.

CREATE OR REPLACE FUNCTION rep_warehouse.district_report_people(p_district TEXT)
RETURNS TABLE (
  active_guides BIGINT,
  total_guides  BIGINT,
  cama_members  BIGINT
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT
    COUNT(*) FILTER (WHERE guide_status = 'Active')::BIGINT,
    COUNT(*)::BIGINT,
    (SELECT COUNT(*)::BIGINT FROM rep_warehouse.view_cama_membership WHERE district = p_district)
  FROM rep_warehouse.view_guide_assignment
  WHERE district = p_district;
$$;

-- ── 3. Finance ────────────────────────────────────────────────────────────────
-- Returns grant and loan counts/totals for the latest year with data
-- in each category. Grant year and loan year may differ.

CREATE OR REPLACE FUNCTION rep_warehouse.district_report_finance(p_district TEXT)
RETURNS TABLE (
  grants_year  INT,
  grants_count BIGINT,
  grants_total NUMERIC,
  loans_year   INT,
  loans_count  BIGINT,
  loans_total  NUMERIC
) LANGUAGE plpgsql SECURITY DEFINER STABLE AS $$
DECLARE
  v_grant_year INT;
  v_loan_year  INT;
BEGIN
  SELECT MAX(grant_year)    INTO v_grant_year FROM rep_warehouse.view_grants WHERE district = p_district;
  SELECT MAX(disbursal_year) INTO v_loan_year  FROM rep_warehouse.view_loans  WHERE district = p_district;

  RETURN QUERY
  SELECT
    v_grant_year,
    (SELECT COUNT(*)::BIGINT     FROM rep_warehouse.view_grants WHERE district = p_district AND grant_year    = v_grant_year),
    (SELECT COALESCE(SUM(amount_given), 0) FROM rep_warehouse.view_grants WHERE district = p_district AND grant_year    = v_grant_year),
    v_loan_year,
    (SELECT COUNT(*)::BIGINT     FROM rep_warehouse.view_loans  WHERE district = p_district AND disbursal_year = v_loan_year),
    (SELECT COALESCE(SUM(loan_value), 0)   FROM rep_warehouse.view_loans  WHERE district = p_district AND disbursal_year = v_loan_year);
END;
$$;

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_children(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_people(TEXT)   TO service_role;
GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_finance(TEXT)  TO service_role;


-- ===== 20250201000019_fix_staging_splits.sql =====
-- Fix two staging ETL bugs:
--
-- 1. etl_stage_academic_record / etl_stage_post_school_clients filtered on
--    contact_record_type (ContactRecordType__c formula field) instead of
--    academic_record_type (RecordType.Name). The Post School split never fired.
--
-- 2. etl_stage_cama_members read from rep_raw.cama_members (intentionally empty).
--    Rewritten to derive CAMA members from rep_raw.contacts where
--    record_type_name = 'Cama', joined with rep_staging.schools for district /
--    partner_school.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        row_id,
        salesforce_id,
        person_id                              AS contact_id,
        school_institution_id                  AS school_id,
        district_id,
        district_name                          AS district,
        country_name                           AS country,
        contact_record_type,
        form,
        CASE WHEN year ~ '^\d{4}$' THEN year::smallint END AS year,
        (received_financial_support = 'true')  AS received_financial_support,
        (repeated = 'true')                    AS repeated,
        (attendance_issues = 'true')           AS attendance_issues,
        accommodation,
        donor_code_id,
        project_code_id,
        donor_activity_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND (academic_record_type IS NULL OR academic_record_type != 'Post School');
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_post_school_clients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.post_school_clients;
    CREATE TABLE rep_staging.post_school_clients AS
    SELECT
        row_id,
        salesforce_id,
        person_id                              AS contact_id,
        district_id,
        district_name                          AS district,
        country_name                           AS country,
        contact_record_type,
        form,
        CASE WHEN year ~ '^\d{4}$' THEN year::smallint END AS year,
        (received_financial_support = 'true')  AS received_financial_support,
        accommodation,
        donor_code_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND academic_record_type = 'Post School';
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_cama_members()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.cama_members;
    CREATE TABLE rep_staging.cama_members AS
    SELECT
        c.row_id,
        c.salesforce_id                              AS contact_id,
        c.school_id,
        sc.school_name,
        sc.district,
        c.country_name                               AS country,
        NULLIF(c.date_joined_cama, '')::TIMESTAMP    AS date_joined_cama,
        COALESCE(sc.active_partner_school, false)    AS partner_school
    FROM rep_raw.contacts c
    LEFT JOIN rep_staging.schools sc ON sc.school_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND c.record_type_name = 'Cama';
END;
$$;


-- ===== 20250201000020_map_views.sql =====
-- Map views for the CAMFED Data Map page.
-- Replaces the placeholder district_boundaries_geojson view with live warehouse data.
-- Creates school_points_geojson view from rep_warehouse.dim_school + fact tables.

-- ── District KPI view ─────────────────────────────────────────────────────────
-- app.js calls: .from('district_boundaries_geojson').select('id,country_slug,...,kpis')
-- Geometry is loaded from Supabase Storage — this view only supplies KPI values.

DROP VIEW IF EXISTS public.district_boundaries_geojson;

CREATE OR REPLACE VIEW public.district_boundaries_geojson AS
WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
    AND country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe')
),
all_districts AS (
  SELECT DISTINCT g.country, g.district
  FROM rep_warehouse.dim_geography g
  JOIN valid_countries vc ON vc.country = g.country
  WHERE g.district IS NOT NULL
    AND g.scd_is_current = true
),
children_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_children_supported f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
guides_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Learner%'    AND f.guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Transition%' AND f.guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Agri%'       AND f.guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Business%'   AND f.guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
cama_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
grants_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                      AS grant_count,
    ROUND(SUM(COALESCE(f.amount_given, 0)))::int  AS grant_value
  FROM rep_warehouse.fact_grants f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
loans_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                          AS loan_count,
    ROUND(SUM(COALESCE(f.loan_value, 0)))::int        AS loan_value
  FROM rep_warehouse.fact_loans f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
post_school_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_post_school_support f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
schools_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE s.active_partner_school = true) AS active_partner_schools
  FROM rep_warehouse.dim_school s
  JOIN rep_warehouse.dim_geography g ON g.id = s.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL AND s.scd_is_current = true
  GROUP BY g.country, g.district
)
SELECT
  lower(replace(d.country, ' ', '-')) || '::' || lower(d.district)  AS id,
  lower(replace(d.country, ' ', '-'))                                AS country_slug,
  d.country                                                          AS country_name,
  d.district                                                         AS district_name,
  COALESCE(cs.total, 0)                                              AS program_count,
  COALESCE(cs.total, 0)                                              AS beneficiary_count,
  0                                                                  AS risk_score,
  jsonb_build_object(
    'education_bursaries_children',                COALESCE(cs.total, 0),
    'clients_by_form',                             COALESCE(cs.total, 0),
    'active_learner_guides',                       COALESCE(ga.learner,      0),
    'active_guides_transition',                    COALESCE(ga.transition,   0),
    'active_guides_agriculture',                   COALESCE(ga.agriculture,  0),
    'active_guides_business',                      COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                                COALESCE(cam.total, 0),
    'grants_disbursed',                            COALESCE(gr.grant_value, 0),
    'grants_distributed_count',                    COALESCE(gr.grant_count, 0),
    'loans_disbursed',                             COALESCE(lo.loan_value, 0),
    'post_school_clients',                         COALESCE(ps.total, 0),
    'active_partner_schools',                      COALESCE(sc.active_partner_schools, 0)
  )                                                                  AS kpis
FROM all_districts d
LEFT JOIN children_by_district   cs  ON cs.country  = d.country AND cs.district  = d.district
LEFT JOIN guides_by_district     ga  ON ga.country  = d.country AND ga.district  = d.district
LEFT JOIN cama_by_district       cam ON cam.country = d.country AND cam.district = d.district
LEFT JOIN grants_by_district     gr  ON gr.country  = d.country AND gr.district  = d.district
LEFT JOIN loans_by_district      lo  ON lo.country  = d.country AND lo.district  = d.district
LEFT JOIN post_school_by_district ps ON ps.country  = d.country AND ps.district  = d.district
LEFT JOIN schools_by_district    sc  ON sc.country  = d.country AND sc.district  = d.district;

GRANT SELECT ON public.district_boundaries_geojson TO anon, authenticated;


-- ── School points view ────────────────────────────────────────────────────────
-- app.js calls: .from('school_points_geojson').select('school_id,school_name,...,kpis')
-- Only schools with valid lat/lng in the 5 priority countries are included.

DROP VIEW IF EXISTS public.school_points_geojson;

CREATE OR REPLACE VIEW public.school_points_geojson AS
WITH
cs_by_school AS (
  SELECT
    f.school_id,
    COUNT(*)                                          AS total,
    COUNT(*) FILTER (WHERE ct.gender = 'Female')      AS girls,
    COUNT(*) FILTER (WHERE ct.gender = 'Male')        AS boys
  FROM rep_warehouse.fact_children_supported f
  LEFT JOIN rep_warehouse.dim_contact ct ON ct.id = f.contact_id
  WHERE f.school_id IS NOT NULL
  GROUP BY f.school_id
),
guides_by_school AS (
  SELECT
    school_id,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Learner%'    AND guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Transition%' AND guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Agri%'       AND guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Business%'   AND guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
cama_by_school AS (
  SELECT school_id, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership
  WHERE school_id IS NOT NULL
  GROUP BY school_id
)
SELECT
  s.source_school_id::text                    AS school_id,
  s.school_name,
  lower(replace(g.country, ' ', '-'))         AS country_slug,
  g.country                                   AS country_name,
  g.district                                  AS district_name,
  g.province,
  'warehouse'                                 AS geo_source,
  s.latitude,
  s.longitude,
  jsonb_build_object(
    'education_bursaries_children',   COALESCE(cs.total, 0),
    'clients_by_form',                COALESCE(cs.total, 0),
    'clients_by_form_girls',          COALESCE(cs.girls, 0),
    'clients_by_form_boys',           COALESCE(cs.boys,  0),
    'active_learner_guides',          COALESCE(ga.learner,     0),
    'active_guides_transition',       COALESCE(ga.transition,  0),
    'active_guides_agriculture',      COALESCE(ga.agriculture, 0),
    'active_guides_business',         COALESCE(ga.business,    0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                   COALESCE(cam.total, 0),
    'active_partner_schools',         CASE WHEN s.active_partner_school THEN 1 ELSE 0 END
  ) AS kpis
FROM rep_warehouse.dim_school s
JOIN  rep_warehouse.dim_geography g
      ON  g.id = s.geography_id
      AND g.scd_is_current = true
LEFT JOIN cs_by_school    cs  ON cs.school_id  = s.id
LEFT JOIN guides_by_school ga  ON ga.school_id  = s.id
LEFT JOIN cama_by_school   cam ON cam.school_id = s.id
WHERE s.scd_is_current = true
  AND s.latitude  IS NOT NULL
  AND s.longitude IS NOT NULL
  AND g.country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe');

GRANT SELECT ON public.school_points_geojson TO anon, authenticated;


-- ===== 20250201000021_whatsapp_shared_phone.sql =====
-- Reset all live sessions to idle so users see the new main menu on their
-- next message. Sessions are ephemeral; no data is lost.
UPDATE rep_portal.whatsapp_bot_sessions
SET step = 'idle', context = '{}', consented_at = NULL;


-- ===== 20250201000022_map_rpcs.sql =====
-- Map RPC functions for the CAMFED Data Map page.
-- Replace the plain views (which fail for anon due to RLS on rep_warehouse) with
-- SECURITY DEFINER functions that run as postgres and bypass RLS, matching the
-- pattern already used by get_dashboard_data() and get_observed_kpi().

-- ── Clean up plain views from previous migration ─────────────────────────────
DROP VIEW IF EXISTS public.district_boundaries_geojson;
DROP VIEW IF EXISTS public.school_points_geojson;

-- ── District KPI data ─────────────────────────────────────────────────────────
-- Returns one row per district with aggregated KPI counts as JSONB.
-- Geometry comes from Supabase Storage GeoJSON; this supplies KPI values only.

CREATE OR REPLACE FUNCTION public.get_district_kpi_data()
RETURNS TABLE (
  id               TEXT,
  country_slug     TEXT,
  country_name     TEXT,
  district_name    TEXT,
  program_count    INT,
  beneficiary_count INT,
  risk_score       NUMERIC,
  kpis             JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
    AND country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe')
),
all_districts AS (
  SELECT DISTINCT g.country, g.district
  FROM rep_warehouse.dim_geography g
  JOIN valid_countries vc ON vc.country = g.country
  WHERE g.district IS NOT NULL
    AND g.scd_is_current = true
),
children_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_children_supported f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
guides_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Learner%'    AND f.guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Transition%' AND f.guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Agri%'       AND f.guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Business%'   AND f.guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
cama_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
grants_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                     AS grant_count,
    ROUND(SUM(COALESCE(f.amount_given, 0)))::int AS grant_value
  FROM rep_warehouse.fact_grants f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
loans_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                         AS loan_count,
    ROUND(SUM(COALESCE(f.loan_value, 0)))::int       AS loan_value
  FROM rep_warehouse.fact_loans f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
post_school_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_post_school_support f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
schools_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE s.active_partner_school = true) AS active_partner_schools
  FROM rep_warehouse.dim_school s
  JOIN rep_warehouse.dim_geography g ON g.id = s.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL AND s.scd_is_current = true
  GROUP BY g.country, g.district
)
SELECT
  lower(replace(d.country, ' ', '-')) || '::' || lower(d.district) AS id,
  lower(replace(d.country, ' ', '-'))                               AS country_slug,
  d.country                                                         AS country_name,
  d.district                                                        AS district_name,
  COALESCE(cs.total, 0)::int                                        AS program_count,
  COALESCE(cs.total, 0)::int                                        AS beneficiary_count,
  0::numeric                                                        AS risk_score,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'grants_disbursed',              COALESCE(gr.grant_value, 0),
    'grants_distributed_count',      COALESCE(gr.grant_count, 0),
    'loans_disbursed',               COALESCE(lo.loan_value, 0),
    'post_school_clients',           COALESCE(ps.total, 0),
    'active_partner_schools',        COALESCE(sc.active_partner_schools, 0)
  )                                                                 AS kpis
FROM all_districts d
LEFT JOIN children_by_district    cs  ON cs.country  = d.country AND cs.district  = d.district
LEFT JOIN guides_by_district      ga  ON ga.country  = d.country AND ga.district  = d.district
LEFT JOIN cama_by_district        cam ON cam.country = d.country AND cam.district = d.district
LEFT JOIN grants_by_district      gr  ON gr.country  = d.country AND gr.district  = d.district
LEFT JOIN loans_by_district       lo  ON lo.country  = d.country AND lo.district  = d.district
LEFT JOIN post_school_by_district ps  ON ps.country  = d.country AND ps.district  = d.district
LEFT JOIN schools_by_district     sc  ON sc.country  = d.country AND sc.district  = d.district;
$$;

GRANT EXECUTE ON FUNCTION public.get_district_kpi_data() TO anon, authenticated;


-- ── School point data ─────────────────────────────────────────────────────────
-- Returns one row per school with lat/lng and per-school KPI counts as JSONB.
-- Only schools with valid coordinates in the 5 priority countries are included.

CREATE OR REPLACE FUNCTION public.get_school_point_data()
RETURNS TABLE (
  school_id    TEXT,
  school_name  TEXT,
  country_slug TEXT,
  country_name TEXT,
  district_name TEXT,
  province     TEXT,
  geo_source   TEXT,
  latitude     NUMERIC,
  longitude    NUMERIC,
  kpis         JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
WITH
cs_by_school AS (
  SELECT
    f.school_id,
    COUNT(*)                                         AS total,
    COUNT(*) FILTER (WHERE ct.gender = 'Female')     AS girls,
    COUNT(*) FILTER (WHERE ct.gender = 'Male')       AS boys
  FROM rep_warehouse.fact_children_supported f
  LEFT JOIN rep_warehouse.dim_contact ct ON ct.id = f.contact_id
  WHERE f.school_id IS NOT NULL
  GROUP BY f.school_id
),
guides_by_school AS (
  SELECT
    school_id,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Learner%'    AND guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Transition%' AND guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Agri%'       AND guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Business%'   AND guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
cama_by_school AS (
  SELECT school_id, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership
  WHERE school_id IS NOT NULL
  GROUP BY school_id
)
SELECT
  s.source_school_id::text                    AS school_id,
  s.school_name,
  lower(replace(g.country, ' ', '-'))         AS country_slug,
  g.country                                   AS country_name,
  g.district                                  AS district_name,
  g.province,
  'warehouse'                                 AS geo_source,
  s.latitude,
  s.longitude,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'clients_by_form_girls',         COALESCE(cs.girls, 0),
    'clients_by_form_boys',          COALESCE(cs.boys,  0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'active_partner_schools',        CASE WHEN s.active_partner_school THEN 1 ELSE 0 END
  ) AS kpis
FROM rep_warehouse.dim_school s
JOIN  rep_warehouse.dim_geography g
      ON  g.id = s.geography_id
      AND g.scd_is_current = true
LEFT JOIN cs_by_school    cs  ON cs.school_id  = s.id
LEFT JOIN guides_by_school ga  ON ga.school_id  = s.id
LEFT JOIN cama_by_school   cam ON cam.school_id = s.id
WHERE s.scd_is_current = true
  AND s.latitude  IS NOT NULL
  AND s.longitude IS NOT NULL
  AND g.country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe');
$$;

GRANT EXECUTE ON FUNCTION public.get_school_point_data() TO anon, authenticated;


-- ===== 20250201000023_rpc_functions.sql =====
-- Public RPC functions for the frontend dashboard.
-- get_dashboard_data: pre-aggregated metrics from all fact tables.
-- get_observed_kpi:   per-KPI rows from the observed KPI view.
--
-- Country list is authoritative from view_observed_kpi only.
-- All non-KPI sections filter to that same country set.

-- ── public.schools ────────────────────────────────────────────────────────────
-- Pre-geocoded school table (4817 rows, imported from schools_import.csv).
-- Loaded outside migrations historically; CREATE TABLE IF NOT EXISTS makes
-- db reset self-contained. The remote DB already has this table.

CREATE TABLE IF NOT EXISTS public.schools (
  school_id     TEXT PRIMARY KEY,
  school_name   TEXT NOT NULL,
  country_slug  TEXT,
  country_name  TEXT,
  district_name TEXT,
  province      TEXT,
  geo_source    TEXT,
  latitude      NUMERIC,
  longitude     NUMERIC,
  kpis          JSONB,
  active_partner_school BOOLEAN
);

-- ── Materialized view ────────────────────────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS public.dashboard_data_agg;

CREATE MATERIALIZED VIEW public.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
)

-- 1a. Children Supported — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- 1b. Children Supported — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- 1c. Children Supported — Cumulative 2020-2030
SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- 1d. Children Supported — Cumulative all-time
SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- 2. Active Learner Guides
SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_type = 'Learner Guide' AND v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

-- 3. Number of Clients by Form (all supported children)
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- 3a. Girls Supported (direct gender count)
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- 3b. Boys Supported (direct gender count)
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- 4. Active Partner Schools
SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

-- 5. Women Supported in Tertiary Education
SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

-- 6. Active Guides by Type (all)
SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

-- 7. Number of Post School Clients
SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

-- 8. Grants Disbursed (total value)
SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

-- 9. Loans Disbursed (total value)
SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- 10. Girls supported by CAMA (newly supported)
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- 10b. Girls supported through community initiatives (newly supported)
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- 11. Active Guides — Transition
SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

-- 12. Active Guides — Agriculture
SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

-- 13. Active Guides — Business
SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.school_name

UNION ALL

-- 14. Grants Distributed — Count
SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

-- 15. Loans Disbursed — Agriculture (count)
SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- 16. Loans Disbursed — Business (count)
SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- 17. Loans Disbursed — Kiva (count)
SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- 18. Loans Disbursed — RIF (count)
SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

REFRESH MATERIALIZED VIEW public.dashboard_data_agg;

GRANT SELECT ON public.dashboard_data_agg TO anon, authenticated;

-- ── RPC: get_dashboard_data ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_dashboard_data()
RETURNS json LANGUAGE sql SECURITY DEFINER AS $$
  SELECT json_build_object('data', json_agg(r))
  FROM (SELECT * FROM public.dashboard_data_agg) r;
$$;

GRANT EXECUTE ON FUNCTION public.get_dashboard_data() TO anon, authenticated;

-- ── RPC: get_observed_kpi ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_observed_kpi(p_kpi_id TEXT)
RETURNS TABLE (
  country                  TEXT,
  kpi_id                   TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  year                     INTEGER,
  value                    TEXT
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    v.country,
    v.kpi_id,
    v.disaggregation_level_one,
    v.disaggregation_level_two,
    v.year,
    v.value
  FROM rep_warehouse.view_observed_kpi v
  WHERE v.kpi_id = p_kpi_id
    AND v.year IS NOT NULL
    AND v.country IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION public.get_observed_kpi(TEXT) TO anon, authenticated;


-- ===== 20250201000024_fix_school_points.sql =====
-- Fix get_school_point_data() to source coordinates from public.schools
-- (pre-geocoded, 4817 rows) rather than rep_warehouse.dim_school (no lat/lng).
-- KPI counts still come from live warehouse fact tables via dim_school.id join.

CREATE OR REPLACE FUNCTION public.get_school_point_data()
RETURNS TABLE (
  school_id     TEXT,
  school_name   TEXT,
  country_slug  TEXT,
  country_name  TEXT,
  district_name TEXT,
  province      TEXT,
  geo_source    TEXT,
  latitude      NUMERIC,
  longitude     NUMERIC,
  kpis          JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
WITH
-- Map public.schools.school_id -> dim_school.id (warehouse PK for fact joins)
school_dim AS (
  SELECT
    ps.school_id   AS source_id,
    ds.id          AS dim_id
  FROM public.schools ps
  JOIN rep_warehouse.dim_school ds
    ON  ds.source_school_id = ps.school_id
    AND ds.scd_is_current   = true
),
cs_by_school AS (
  SELECT
    f.school_id,
    COUNT(*)                                         AS total,
    COUNT(*) FILTER (WHERE ct.gender = 'Female')     AS girls,
    COUNT(*) FILTER (WHERE ct.gender = 'Male')       AS boys
  FROM rep_warehouse.fact_children_supported f
  LEFT JOIN rep_warehouse.dim_contact ct ON ct.id = f.contact_id
  WHERE f.school_id IS NOT NULL
  GROUP BY f.school_id
),
guides_by_school AS (
  SELECT
    school_id,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Learner%'    AND guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Transition%' AND guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Agri%'       AND guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Business%'   AND guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
cama_by_school AS (
  SELECT school_id, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
partner_by_school AS (
  SELECT source_school_id::text AS school_id,
         active_partner_school
  FROM rep_warehouse.dim_school
  WHERE scd_is_current = true
)
SELECT
  ps.school_id,
  ps.school_name,
  ps.country_slug,
  ps.country_name,
  ps.district_name,
  ps.province,
  COALESCE(ps.geo_source, 'geocoded')             AS geo_source,
  ps.latitude,
  ps.longitude,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'clients_by_form_girls',         COALESCE(cs.girls, 0),
    'clients_by_form_boys',          COALESCE(cs.boys,  0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'active_partner_schools',        CASE WHEN COALESCE(pb.active_partner_school, false) THEN 1 ELSE 0 END
  ) AS kpis
FROM public.schools ps
LEFT JOIN school_dim       sd  ON sd.source_id  = ps.school_id
LEFT JOIN cs_by_school     cs  ON cs.school_id  = sd.dim_id
LEFT JOIN guides_by_school ga  ON ga.school_id  = sd.dim_id
LEFT JOIN cama_by_school   cam ON cam.school_id = sd.dim_id
LEFT JOIN partner_by_school pb ON pb.school_id  = ps.school_id
WHERE ps.country_slug IN ('tanzania', 'ghana', 'malawi', 'zambia', 'zimbabwe');
$$;

GRANT EXECUTE ON FUNCTION public.get_school_point_data() TO anon, authenticated;


-- ===== 20250201000025_school_points_use_csv_kpis.sql =====
-- Simplify get_school_point_data() to return public.schools.kpis directly.
-- The pre-baked KPI values in public.schools (imported from schools_import.csv)
-- are correct. The warehouse fact tables do not have school_id populated for
-- most records so live joins return all zeros.

CREATE OR REPLACE FUNCTION public.get_school_point_data()
RETURNS TABLE (
  school_id     TEXT,
  school_name   TEXT,
  country_slug  TEXT,
  country_name  TEXT,
  district_name TEXT,
  province      TEXT,
  geo_source    TEXT,
  latitude      NUMERIC,
  longitude     NUMERIC,
  kpis          JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
SELECT
  school_id,
  school_name,
  country_slug,
  country_name,
  district_name,
  province,
  COALESCE(geo_source, 'geocoded') AS geo_source,
  latitude,
  longitude,
  kpis
FROM public.schools
WHERE country_slug IN ('tanzania', 'ghana', 'malawi', 'zambia', 'zimbabwe')
  AND latitude  IS NOT NULL
  AND longitude IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION public.get_school_point_data() TO anon, authenticated;


-- ===== 20250201000026_school_points_live_warehouse.sql =====
-- Fix get_school_point_data() to use live warehouse KPIs joined by school name + country.
-- public.schools has no Salesforce ID; the only link to dim_school is school_name.
-- fact_children_supported.school_id is dim_school.id (integer), not source_school_id.
-- DISTINCT ON school_id guards against the ~363 duplicate name matches across countries.

CREATE OR REPLACE FUNCTION public.get_school_point_data()
RETURNS TABLE (
  school_id     TEXT,
  school_name   TEXT,
  country_slug  TEXT,
  country_name  TEXT,
  district_name TEXT,
  province      TEXT,
  geo_source    TEXT,
  latitude      NUMERIC,
  longitude     NUMERIC,
  kpis          JSONB
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
WITH
-- Map public.schools -> dim_school.id via name + country match.
-- DISTINCT ON ensures one dim_school row per public.schools row.
school_dim AS (
  SELECT DISTINCT ON (ps.school_id)
    ps.school_id  AS source_id,
    ds.id         AS dim_id
  FROM public.schools ps
  JOIN rep_warehouse.dim_school ds
    ON  lower(trim(ds.school_name)) = lower(trim(ps.school_name))
    AND ds.scd_is_current = true
  JOIN rep_warehouse.dim_geography g
    ON  g.id = ds.geography_id
    AND g.scd_is_current = true
    AND lower(g.country) = lower(ps.country_name)
  ORDER BY ps.school_id, ds.id
),
cs_by_school AS (
  SELECT
    f.school_id,
    COUNT(*)                                         AS total,
    COUNT(*) FILTER (WHERE ct.gender = 'Female')     AS girls,
    COUNT(*) FILTER (WHERE ct.gender = 'Male')       AS boys
  FROM rep_warehouse.fact_children_supported f
  LEFT JOIN rep_warehouse.dim_contact ct ON ct.id = f.contact_id
  WHERE f.school_id IS NOT NULL
  GROUP BY f.school_id
),
guides_by_school AS (
  SELECT
    school_id,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Learner%'    AND guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Transition%' AND guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Agri%'       AND guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Business%'   AND guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
cama_by_school AS (
  SELECT school_id, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
partner_by_school AS (
  SELECT id AS dim_id, active_partner_school
  FROM rep_warehouse.dim_school
  WHERE scd_is_current = true
)
SELECT
  ps.school_id,
  ps.school_name,
  ps.country_slug,
  ps.country_name,
  ps.district_name,
  ps.province,
  COALESCE(ps.geo_source, 'geocoded')             AS geo_source,
  ps.latitude,
  ps.longitude,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'clients_by_form_girls',         COALESCE(cs.girls, 0),
    'clients_by_form_boys',          COALESCE(cs.boys,  0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'active_partner_schools',        CASE WHEN COALESCE(pb.active_partner_school, false) THEN 1 ELSE 0 END
  ) AS kpis
FROM public.schools ps
LEFT JOIN school_dim       sd  ON sd.source_id  = ps.school_id
LEFT JOIN cs_by_school     cs  ON cs.school_id  = sd.dim_id
LEFT JOIN guides_by_school ga  ON ga.school_id  = sd.dim_id
LEFT JOIN cama_by_school   cam ON cam.school_id = sd.dim_id
LEFT JOIN partner_by_school pb ON pb.dim_id     = sd.dim_id
WHERE ps.country_slug IN ('tanzania', 'ghana', 'malawi', 'zambia', 'zimbabwe')
  AND ps.latitude  IS NOT NULL
  AND ps.longitude IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION public.get_school_point_data() TO anon, authenticated;


-- ===== 20250201000027_kpi_delete_year.sql =====
-- Migration: kpi_delete_year RPC
-- Removes all raw and warehouse KPI data for a given year so that the year
-- can be cleanly re-uploaded. dim_kpi rows are intentionally preserved because
-- they are upserted on every upload and are shared across years.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_delete_year(p_year INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_raw, rep_warehouse, public
AS $$
DECLARE
  v_batch_ids TEXT[];
BEGIN
  -- Collect all batch IDs for the year (SUCCESS and FAILED alike) so that
  -- related raw/audit rows can be cleaned up atomically.
  SELECT array_agg(batch_id)
    INTO v_batch_ids
    FROM rep_raw.upload_log
   WHERE year = p_year;

  IF v_batch_ids IS NOT NULL THEN
    DELETE FROM rep_raw.unmatched_rows WHERE batch_id = ANY(v_batch_ids);
    DELETE FROM rep_raw.duplicate_rows  WHERE batch_id = ANY(v_batch_ids);
    DELETE FROM rep_raw.all_kpis        WHERE batch_id = ANY(v_batch_ids);
  END IF;

  -- Warehouse facts are keyed by year, not batch_id.
  DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

  -- Remove upload_log rows last so that referential lookups above still work.
  DELETE FROM rep_raw.upload_log WHERE year = p_year;

  RETURN jsonb_build_object('status', 'OK', 'year', p_year);
END;
$$;

-- Allow any authenticated user to call this function (admin-only UI gate is
-- enforced in the frontend; the RPC itself is safe to call as authenticated).
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_delete_year(INTEGER) TO authenticated;


-- ===== 20250201000028_whatsapp_events.sql =====
-- whatsapp_events: one row per conversation step transition.
-- Used for WhatsApp bot usage analytics shown in the admin panel.
-- phone_hash is SHA-256 of the phone number — PII never stored here.
-- user_id is whatsapp_users.id (bigint), null for unauthenticated events.

CREATE TABLE rep_portal.whatsapp_events (
  id          BIGSERIAL    PRIMARY KEY,
  phone_hash  TEXT         NOT NULL,
  user_id     BIGINT,
  flow        TEXT         NOT NULL,
  from_step   TEXT,
  to_step     TEXT         NOT NULL,
  outcome     TEXT,        -- 'completed' | 'abandoned' | 'error' | 'auth_failed' | NULL (in-progress)
  occurred_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX ON rep_portal.whatsapp_events (occurred_at DESC);
CREATE INDEX ON rep_portal.whatsapp_events (flow, occurred_at DESC);

ALTER TABLE rep_portal.whatsapp_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_select_wa_events"
  ON rep_portal.whatsapp_events
  FOR SELECT TO authenticated
  USING (rep_warehouse.is_admin());

GRANT INSERT ON rep_portal.whatsapp_events TO service_role;
GRANT USAGE  ON SEQUENCE rep_portal.whatsapp_events_id_seq TO service_role;

-- ── Analytics views ───────────────────────────────────────────────────────────

-- Daily event counts (last 60 days). Views run as caller — RLS on the
-- base table enforces admin-only access; grants here just allow execution.

CREATE VIEW rep_portal.view_wa_daily AS
SELECT
  (occurred_at AT TIME ZONE 'UTC')::date          AS day,
  COUNT(DISTINCT phone_hash)                       AS unique_users,
  COUNT(*)                                         AS total_events,
  COUNT(*) FILTER (WHERE outcome = 'completed')    AS completions,
  COUNT(*) FILTER (WHERE outcome = 'error')        AS errors
FROM rep_portal.whatsapp_events
WHERE occurred_at >= now() - INTERVAL '60 days'
GROUP BY 1
ORDER BY 1 DESC;

GRANT SELECT ON rep_portal.view_wa_daily TO authenticated;

-- Per-flow metrics (last 30 days).
CREATE VIEW rep_portal.view_wa_flow_summary AS
SELECT
  flow,
  COUNT(DISTINCT phone_hash)                          AS unique_users,
  COUNT(*) FILTER (WHERE from_step = 'idle')          AS started,
  COUNT(*) FILTER (WHERE outcome = 'completed')       AS completed,
  COUNT(*) FILTER (WHERE outcome = 'abandoned')       AS abandoned,
  COUNT(*) FILTER (WHERE outcome = 'error')           AS errors,
  ROUND(
    100.0
      * COUNT(*) FILTER (WHERE outcome = 'completed')
      / NULLIF(COUNT(*) FILTER (WHERE from_step = 'idle'), 0),
    1
  ) AS completion_pct
FROM rep_portal.whatsapp_events
WHERE occurred_at >= now() - INTERVAL '30 days'
GROUP BY flow
ORDER BY started DESC NULLS LAST;

GRANT SELECT ON rep_portal.view_wa_flow_summary TO authenticated;

-- Step-level funnel per flow (last 30 days).
CREATE VIEW rep_portal.view_wa_funnel AS
SELECT
  flow,
  to_step                     AS step,
  COUNT(*)                    AS entries,
  COUNT(DISTINCT phone_hash)  AS unique_users
FROM rep_portal.whatsapp_events
WHERE occurred_at >= now() - INTERVAL '30 days'
GROUP BY flow, to_step
ORDER BY flow, entries DESC;

GRANT SELECT ON rep_portal.view_wa_funnel TO authenticated;

-- Recent bot errors (last 100).
CREATE VIEW rep_portal.view_wa_errors AS
SELECT id, flow, from_step, to_step, occurred_at
FROM rep_portal.whatsapp_events
WHERE outcome = 'error'
ORDER BY occurred_at DESC
LIMIT 100;

GRANT SELECT ON rep_portal.view_wa_errors TO authenticated;

