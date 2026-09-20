-- ============================================================================
-- Rental Platform Case Study - PostgreSQL DDL
-- Target: PostgreSQL with pgcrypto and btree_gist available.
-- Run with psql, because this bootstrap uses \gexec and \connect.
--
-- No production secret, real customer data, proprietary table name or Localiza
-- internal implementation is represented here. This is an evidence-informed
-- reference architecture for study and interview preparation.
-- ============================================================================
\set ON_ERROR_STOP on

SELECT 'CREATE DATABASE rental_platform_case ENCODING ''UTF8'''
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'rental_platform_case'
)\gexec

\connect rental_platform_case

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE SCHEMA IF NOT EXISTS availability;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS claim;
CREATE SCHEMA IF NOT EXISTS corporate;
CREATE SCHEMA IF NOT EXISTS fleet;
CREATE SCHEMA IF NOT EXISTS fleet_mgmt;
CREATE SCHEMA IF NOT EXISTS inspection;
CREATE SCHEMA IF NOT EXISTS integration;
CREATE SCHEMA IF NOT EXISTS loyalty;
CREATE SCHEMA IF NOT EXISTS maintenance;
CREATE SCHEMA IF NOT EXISTS org;
CREATE SCHEMA IF NOT EXISTS party;
CREATE SCHEMA IF NOT EXISTS pricing;
CREATE SCHEMA IF NOT EXISTS privacy;
CREATE SCHEMA IF NOT EXISTS rental;
CREATE SCHEMA IF NOT EXISTS reservation;
CREATE SCHEMA IF NOT EXISTS telematics;
CREATE SCHEMA IF NOT EXISTS traffic;
CREATE SCHEMA IF NOT EXISTS used_car;

CREATE OR REPLACE FUNCTION integration.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := clock_timestamp();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integration.reject_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'immutable row in %.%', TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '55000';
END;
$$;

CREATE OR REPLACE FUNCTION integration.protect_posted_charge()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.posting_status = 'POSTED' THEN
        RAISE EXCEPTION 'posted charges are immutable' USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.posting_status = 'POSTED' THEN
        RAISE EXCEPTION 'posted charges must be reversed, not updated' USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION integration.protect_completed_inspection()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND OLD.status = 'COMPLETED' THEN
        RAISE EXCEPTION 'completed inspections are immutable' USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'COMPLETED' THEN
        RAISE EXCEPTION 'completed inspections must be superseded, not updated' USING ERRCODE = '55000';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- --------------------------------------------------------------------------
-- Tables
-- --------------------------------------------------------------------------
CREATE TABLE org.legal_entity (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    entity_code                        varchar(30) NOT NULL,
    legal_name                         varchar(200) NOT NULL,
    trade_name                         varchar(160),
    tax_identifier_ciphertext          text,
    tax_identifier_hmac                bytea,
    country_code                       char(2) NOT NULL,
    currency_code                      char(3) NOT NULL,
    timezone                           varchar(64) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_org_legal_entity PRIMARY KEY (id),
    CONSTRAINT uq_org_legal_entity_entity_code_1 UNIQUE (entity_code),
    CONSTRAINT uq_org_legal_entity_country_code_tax_identifier_hmac_2 UNIQUE (country_code, tax_identifier_hmac),
    CONSTRAINT ck_org_legal_entity_1 CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED'))
);

CREATE TABLE org.business_unit (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    parent_business_unit_id            uuid,
    unit_code                          varchar(30) NOT NULL,
    name                               varchar(160) NOT NULL,
    unit_type                          varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_org_business_unit PRIMARY KEY (id),
    CONSTRAINT uq_org_business_unit_legal_entity_id_unit_code_1 UNIQUE (legal_entity_id, unit_code),
    CONSTRAINT ck_org_business_unit_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE org.branch (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    business_unit_id                   uuid,
    branch_code                        varchar(30) NOT NULL,
    name                               varchar(180) NOT NULL,
    branch_type                        varchar(30) NOT NULL,
    operator_type                      varchar(20) NOT NULL,
    country_code                       char(2) NOT NULL,
    timezone                           varchar(64) NOT NULL,
    airport_code                       varchar(8),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    opened_at                          date,
    closed_at                          date,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_org_branch PRIMARY KEY (id),
    CONSTRAINT uq_org_branch_legal_entity_id_branch_code_1 UNIQUE (legal_entity_id, branch_code),
    CONSTRAINT ck_org_branch_1 CHECK (branch_type IN ('AIRPORT','URBAN','MALL','DEALERSHIP','MAINTENANCE_HUB','USED_CAR_STORE','VIRTUAL')),
    CONSTRAINT ck_org_branch_2 CHECK (operator_type IN ('OWNED','FRANCHISE','PARTNER')),
    CONSTRAINT ck_org_branch_3 CHECK (status IN ('PLANNED','ACTIVE','TEMPORARILY_CLOSED','CLOSED')),
    CONSTRAINT ck_org_branch_4 CHECK (closed_at IS NULL OR opened_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE org.branch_operator (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    branch_id                          uuid NOT NULL,
    operator_party_id                  uuid NOT NULL,
    operator_role                      varchar(30) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    agreement_reference                varchar(100),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_org_branch_operator PRIMARY KEY (id),
    CONSTRAINT ck_org_branch_operator_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE org.branch_hours (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    branch_id                          uuid NOT NULL,
    day_of_week                        smallint NOT NULL,
    opens_at                           time,
    closes_at                          time,
    is_closed                          boolean NOT NULL DEFAULT FALSE,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_org_branch_hours PRIMARY KEY (id),
    CONSTRAINT uq_org_branch_hours_branch_id_day_of_week_1 UNIQUE (branch_id, day_of_week),
    CONSTRAINT ck_org_branch_hours_1 CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT ck_org_branch_hours_2 CHECK (is_closed OR closes_at > opens_at)
);

CREATE TABLE org.branch_calendar_exception (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    branch_id                          uuid NOT NULL,
    exception_date                     date NOT NULL,
    opens_at                           time,
    closes_at                          time,
    is_closed                          boolean NOT NULL DEFAULT TRUE,
    reason                             varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_org_branch_calendar_exception PRIMARY KEY (id),
    CONSTRAINT uq_org_branch_calendar_exception_branch_id_except_d9b41bc0 UNIQUE (branch_id, exception_date),
    CONSTRAINT ck_org_branch_calendar_exception_1 CHECK (is_closed OR closes_at > opens_at)
);

CREATE TABLE org.channel (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    channel_code                       varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    channel_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_org_channel PRIMARY KEY (id),
    CONSTRAINT uq_org_channel_channel_code_1 UNIQUE (channel_code),
    CONSTRAINT ck_org_channel_1 CHECK (channel_type IN ('WEB','MOBILE_APP','BRANCH','CALL_CENTER','PARTNER','API','KIOSK')),
    CONSTRAINT ck_org_channel_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE party.party (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_type                         varchar(20) NOT NULL,
    canonical_status                   varchar(20) NOT NULL DEFAULT 'ACTIVE',
    preferred_language                 varchar(10),
    home_country_code                  char(2),
    merged_into_party_id               uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_party PRIMARY KEY (id),
    CONSTRAINT ck_party_party_1 CHECK (party_type IN ('PERSON','ORGANIZATION')),
    CONSTRAINT ck_party_party_2 CHECK (canonical_status IN ('ACTIVE','BLOCKED','MERGED','ANONYMIZED','DECEASED','INACTIVE'))
);

CREATE TABLE party.person (
    party_id                           uuid NOT NULL,
    given_name                         varchar(100) NOT NULL,
    family_name                        varchar(140) NOT NULL,
    preferred_name                     varchar(100),
    birth_date                         date,
    nationality_country_code           char(2),
    gender_code                        varchar(20),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_person PRIMARY KEY (party_id)
);

CREATE TABLE party.organization (
    party_id                           uuid NOT NULL,
    legal_name                         varchar(200) NOT NULL,
    trade_name                         varchar(180),
    organization_type                  varchar(30),
    incorporation_country_code         char(2),
    website_url                        varchar(500),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_organization PRIMARY KEY (party_id)
);

CREATE TABLE party.party_identifier (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    identifier_type                    varchar(40) NOT NULL,
    issuing_country_code               char(2) NOT NULL,
    identifier_ciphertext              text NOT NULL,
    identifier_hmac                    bytea NOT NULL,
    identifier_last4                   varchar(8),
    valid_from                         date,
    valid_to                           date,
    verified_at                        timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_party_identifier PRIMARY KEY (id),
    CONSTRAINT uq_party_party_identifier_identifier_type_issuing_2a125238 UNIQUE (identifier_type, issuing_country_code, identifier_hmac),
    CONSTRAINT ck_party_party_identifier_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_party_party_identifier_2 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','UNVERIFIED'))
);

CREATE TABLE party.contact_point (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    contact_type                       varchar(20) NOT NULL,
    usage_type                         varchar(20) NOT NULL,
    value_ciphertext                   text NOT NULL,
    value_hmac                         bytea NOT NULL,
    is_primary                         boolean NOT NULL DEFAULT FALSE,
    verified_at                        timestamptz,
    valid_from                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to                           timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_contact_point PRIMARY KEY (id),
    CONSTRAINT ck_party_contact_point_1 CHECK (contact_type IN ('EMAIL','PHONE','MOBILE','WHATSAPP')),
    CONSTRAINT ck_party_contact_point_2 CHECK (usage_type IN ('PERSONAL','WORK','BILLING','EMERGENCY')),
    CONSTRAINT ck_party_contact_point_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE party.postal_address (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    country_code                       char(2) NOT NULL,
    postal_code                        varchar(20),
    state_region                       varchar(100),
    city                               varchar(120) NOT NULL,
    district                           varchar(120),
    street                             varchar(180),
    street_number                      varchar(30),
    complement                         varchar(140),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_postal_address PRIMARY KEY (id)
);

CREATE TABLE party.party_address (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    address_id                         uuid NOT NULL,
    usage_type                         varchar(20) NOT NULL,
    is_primary                         boolean NOT NULL DEFAULT FALSE,
    valid_from                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to                           timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_party_address PRIMARY KEY (id),
    CONSTRAINT uq_party_party_address_party_id_address_id_usage__32d5144f UNIQUE (party_id, address_id, usage_type, valid_from),
    CONSTRAINT ck_party_party_address_1 CHECK (usage_type IN ('HOME','WORK','BILLING','MAILING','REGISTERED')),
    CONSTRAINT ck_party_party_address_2 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE party.customer_account (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    customer_number                    varchar(40) NOT NULL,
    segment                            varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    credit_limit                       decimal(19,4),
    currency_code                      char(3),
    opened_at                          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at                          timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_customer_account PRIMARY KEY (id),
    CONSTRAINT uq_party_customer_account_legal_entity_id_custome_0bdb7276 UNIQUE (legal_entity_id, customer_number),
    CONSTRAINT uq_party_customer_account_legal_entity_id_party_id_2 UNIQUE (legal_entity_id, party_id),
    CONSTRAINT ck_party_customer_account_1 CHECK (segment IN ('RETAIL','CORPORATE','PARTNER','GOVERNMENT','INTERNAL')),
    CONSTRAINT ck_party_customer_account_2 CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_party_customer_account_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE party.organization_representative (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    organization_party_id              uuid NOT NULL,
    person_party_id                    uuid NOT NULL,
    role_type                          varchar(40) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    authority_document_id              uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_organization_representative PRIMARY KEY (id),
    CONSTRAINT ck_party_organization_representative_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE party.driver_profile (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    person_party_id                    uuid NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    first_approved_at                  timestamptz,
    last_reviewed_at                   timestamptz,
    young_driver_until                 date,
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_driver_profile PRIMARY KEY (id),
    CONSTRAINT uq_party_driver_profile_person_party_id_1 UNIQUE (person_party_id),
    CONSTRAINT ck_party_driver_profile_1 CHECK (status IN ('PENDING','APPROVED','RESTRICTED','SUSPENDED','REJECTED'))
);

CREATE TABLE party.driver_license (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    driver_profile_id                  uuid NOT NULL,
    issuing_country_code               char(2) NOT NULL,
    license_number_ciphertext          text NOT NULL,
    license_number_hmac                bytea NOT NULL,
    category                           varchar(20) NOT NULL,
    issued_at                          date,
    expires_at                         date NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'UNVERIFIED',
    verification_source                varchar(40),
    verified_at                        timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_driver_license PRIMARY KEY (id),
    CONSTRAINT uq_party_driver_license_issuing_country_code_lice_53885997 UNIQUE (issuing_country_code, license_number_hmac),
    CONSTRAINT ck_party_driver_license_1 CHECK (status IN ('UNVERIFIED','VALID','EXPIRED','SUSPENDED','REVOKED','REJECTED')),
    CONSTRAINT ck_party_driver_license_2 CHECK (issued_at IS NULL OR expires_at > issued_at)
);

CREATE TABLE party.identity_verification (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    verification_type                  varchar(40) NOT NULL,
    provider                           varchar(60),
    provider_reference                 varchar(160),
    result                             varchar(20) NOT NULL,
    score                              decimal(8,5),
    evidence_json                      jsonb,
    verified_at                        timestamptz NOT NULL,
    expires_at                         timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_identity_verification PRIMARY KEY (id),
    CONSTRAINT ck_party_identity_verification_1 CHECK (result IN ('APPROVED','REJECTED','REVIEW','EXPIRED')),
    CONSTRAINT ck_party_identity_verification_2 CHECK (expires_at IS NULL OR expires_at > verified_at)
);

CREATE TABLE party.risk_assessment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    assessment_type                    varchar(40) NOT NULL,
    risk_level                         varchar(20) NOT NULL,
    score                              decimal(10,5),
    rule_version                       varchar(60),
    decision                           varchar(30) NOT NULL,
    reason_codes                       jsonb,
    assessed_at                        timestamptz NOT NULL,
    expires_at                         timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_party_risk_assessment PRIMARY KEY (id),
    CONSTRAINT ck_party_risk_assessment_1 CHECK (risk_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_party_risk_assessment_2 CHECK (decision IN ('APPROVE','REVIEW','REJECT','LIMIT')),
    CONSTRAINT ck_party_risk_assessment_3 CHECK (expires_at IS NULL OR expires_at > assessed_at)
);

CREATE TABLE party.customer_restriction (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    restriction_type                   varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    reason_code                        varchar(60),
    starts_at                          timestamptz NOT NULL,
    ends_at                            timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_by                         uuid,
    released_by                        uuid,
    released_at                        timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_customer_restriction PRIMARY KEY (id),
    CONSTRAINT ck_party_customer_restriction_1 CHECK (severity IN ('INFO','WARNING','BLOCKING')),
    CONSTRAINT ck_party_customer_restriction_2 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED')),
    CONSTRAINT ck_party_customer_restriction_3 CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE TABLE catalog.unit_of_measure (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    unit_code                          varchar(20) NOT NULL,
    name                               varchar(80) NOT NULL,
    dimension                          varchar(30) NOT NULL,
    decimal_scale                      smallint NOT NULL DEFAULT 0,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_unit_of_measure PRIMARY KEY (id),
    CONSTRAINT uq_catalog_unit_of_measure_unit_code_1 UNIQUE (unit_code),
    CONSTRAINT ck_catalog_unit_of_measure_1 CHECK (decimal_scale BETWEEN 0 AND 9)
);

CREATE TABLE catalog.tax_category (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    tax_category_code                  varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    country_code                       char(2) NOT NULL,
    configuration_json                 jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_tax_category PRIMARY KEY (id),
    CONSTRAINT uq_catalog_tax_category_country_code_tax_category_code_1 UNIQUE (country_code, tax_category_code),
    CONSTRAINT ck_catalog_tax_category_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.vehicle_make (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    make_code                          varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    country_code                       char(2),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_vehicle_make PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_make_make_code_1 UNIQUE (make_code),
    CONSTRAINT ck_catalog_vehicle_make_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.vehicle_model (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    make_id                            uuid NOT NULL,
    model_code                         varchar(40) NOT NULL,
    name                               varchar(120) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_vehicle_model PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_model_make_id_model_code_1 UNIQUE (make_id, model_code),
    CONSTRAINT ck_catalog_vehicle_model_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.vehicle_variant (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    model_id                           uuid NOT NULL,
    variant_code                       varchar(50) NOT NULL,
    trim_name                          varchar(120),
    manufacture_year                   smallint,
    model_year                         smallint,
    engine_description                 varchar(120),
    transmission_type                  varchar(30),
    fuel_type                          varchar(30),
    seat_count                         smallint,
    door_count                         smallint,
    luggage_capacity                   smallint,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_vehicle_variant PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_variant_model_id_variant_code__69e5c55d UNIQUE (model_id, variant_code, model_year),
    CONSTRAINT ck_catalog_vehicle_variant_1 CHECK (transmission_type IS NULL OR transmission_type IN ('MANUAL','AUTOMATIC','CVT','DUAL_CLUTCH','OTHER')),
    CONSTRAINT ck_catalog_vehicle_variant_2 CHECK (fuel_type IS NULL OR fuel_type IN ('GASOLINE','ETHANOL','FLEX','DIESEL','HYBRID','ELECTRIC','OTHER')),
    CONSTRAINT ck_catalog_vehicle_variant_3 CHECK (seat_count IS NULL OR seat_count > 0),
    CONSTRAINT ck_catalog_vehicle_variant_4 CHECK (door_count IS NULL OR door_count > 0),
    CONSTRAINT ck_catalog_vehicle_variant_5 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.feature (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    feature_code                       varchar(40) NOT NULL,
    name                               varchar(100) NOT NULL,
    feature_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_feature PRIMARY KEY (id),
    CONSTRAINT uq_catalog_feature_feature_code_1 UNIQUE (feature_code),
    CONSTRAINT ck_catalog_feature_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.variant_feature (
    vehicle_variant_id                 uuid NOT NULL,
    feature_id                         uuid NOT NULL,
    feature_value                      varchar(120),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_variant_feature PRIMARY KEY (vehicle_variant_id, feature_id)
);

CREATE TABLE catalog.vehicle_group (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    group_code                         varchar(30) NOT NULL,
    name                               varchar(120) NOT NULL,
    market_country_code                char(2) NOT NULL,
    description                        text,
    minimum_seats                      smallint,
    minimum_luggage                    smallint,
    sort_order                         integer NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_vehicle_group PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_group_market_country_code_group_code_1 UNIQUE (market_country_code, group_code),
    CONSTRAINT ck_catalog_vehicle_group_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.vehicle_group_variant (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_group_id                   uuid NOT NULL,
    vehicle_variant_id                 uuid NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    priority                           smallint NOT NULL DEFAULT 100,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_vehicle_group_variant PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_group_variant_vehicle_group_id_b7063c95 UNIQUE (vehicle_group_id, vehicle_variant_id, valid_from),
    CONSTRAINT ck_catalog_vehicle_group_variant_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE catalog.vehicle_group_upgrade (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    from_group_id                      uuid NOT NULL,
    to_group_id                        uuid NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    requires_approval                  boolean NOT NULL DEFAULT FALSE,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_vehicle_group_upgrade PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_group_upgrade_from_group_id_to_0a9e3cb2 UNIQUE (from_group_id, to_group_id, valid_from),
    CONSTRAINT ck_catalog_vehicle_group_upgrade_1 CHECK (from_group_id <> to_group_id),
    CONSTRAINT ck_catalog_vehicle_group_upgrade_2 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE catalog.commercial_product (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    product_code                       varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    product_type                       varchar(30) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    tax_category_id                    uuid,
    configuration_json                 jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_commercial_product PRIMARY KEY (id),
    CONSTRAINT uq_catalog_commercial_product_product_code_1 UNIQUE (product_code),
    CONSTRAINT ck_catalog_commercial_product_1 CHECK (product_type IN ('RENTAL','ACCESSORY','SERVICE','PROTECTION','FEE','MILEAGE','DISCOUNT','TAX')),
    CONSTRAINT ck_catalog_commercial_product_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.coverage (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    coverage_code                      varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    description                        text,
    coverage_type                      varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_coverage PRIMARY KEY (id),
    CONSTRAINT uq_catalog_coverage_coverage_code_1 UNIQUE (coverage_code),
    CONSTRAINT ck_catalog_coverage_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE catalog.protection_coverage (
    protection_product_id              uuid NOT NULL,
    coverage_id                        uuid NOT NULL,
    deductible_amount                  decimal(19,4),
    coverage_limit_amount              decimal(19,4),
    currency_code                      char(3),
    terms_json                         jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_protection_coverage PRIMARY KEY (protection_product_id, coverage_id),
    CONSTRAINT ck_catalog_protection_coverage_1 CHECK (deductible_amount IS NULL OR deductible_amount >= 0),
    CONSTRAINT ck_catalog_protection_coverage_2 CHECK (coverage_limit_amount IS NULL OR coverage_limit_amount >= 0)
);

CREATE TABLE catalog.charge_type (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    charge_code                        varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    category                           varchar(30) NOT NULL,
    default_product_id                 uuid,
    is_reversible                      boolean NOT NULL DEFAULT TRUE,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_catalog_charge_type PRIMARY KEY (id),
    CONSTRAINT uq_catalog_charge_type_charge_code_1 UNIQUE (charge_code),
    CONSTRAINT ck_catalog_charge_type_1 CHECK (category IN ('RENTAL','USAGE','PROTECTION','FEE','DAMAGE','TRAFFIC','TOLL','TAX','DISCOUNT','OTHER')),
    CONSTRAINT ck_catalog_charge_type_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE corporate.partner (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    partner_code                       varchar(40) NOT NULL,
    partner_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_partner PRIMARY KEY (id),
    CONSTRAINT uq_corporate_partner_partner_code_1 UNIQUE (partner_code),
    CONSTRAINT uq_corporate_partner_party_id_2 UNIQUE (party_id),
    CONSTRAINT ck_corporate_partner_1 CHECK (partner_type IN ('OTA','TRAVEL_AGENCY','AIRLINE','BANK','INSURER','MARKETPLACE','OTHER')),
    CONSTRAINT ck_corporate_partner_2 CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE'))
);

CREATE TABLE corporate.partner_agreement (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    partner_id                         uuid NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    agreement_number                   varchar(60) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    commission_model                   varchar(30),
    commission_value                   decimal(19,6),
    currency_code                      char(3),
    terms_json                         jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_partner_agreement PRIMARY KEY (id),
    CONSTRAINT uq_corporate_partner_agreement_legal_entity_id_ag_0279997d UNIQUE (legal_entity_id, agreement_number),
    CONSTRAINT ck_corporate_partner_agreement_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_partner_agreement_2 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
);

CREATE TABLE corporate.corporate_agreement (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    customer_account_id                uuid NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    agreement_number                   varchar(60) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    billing_mode                       varchar(30) NOT NULL,
    currency_code                      char(3) NOT NULL,
    credit_limit                       decimal(19,4),
    terms_json                         jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_corporate_agreement PRIMARY KEY (id),
    CONSTRAINT uq_corporate_corporate_agreement_legal_entity_id__50e67ddc UNIQUE (legal_entity_id, agreement_number),
    CONSTRAINT ck_corporate_corporate_agreement_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_corporate_agreement_2 CHECK (billing_mode IN ('DIRECT','CONSOLIDATED','PREPAID','VOUCHER')),
    CONSTRAINT ck_corporate_corporate_agreement_3 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
);

CREATE TABLE corporate.corporate_cost_center (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_agreement_id             uuid NOT NULL,
    parent_cost_center_id              uuid,
    cost_center_code                   varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_corporate_corporate_cost_center PRIMARY KEY (id),
    CONSTRAINT uq_corporate_corporate_cost_center_corporate_agre_88789ddd UNIQUE (corporate_agreement_id, cost_center_code),
    CONSTRAINT ck_corporate_corporate_cost_center_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE corporate.authorized_driver (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_agreement_id             uuid NOT NULL,
    driver_profile_id                  uuid NOT NULL,
    cost_center_id                     uuid,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    authorization_level                varchar(30),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_corporate_authorized_driver PRIMARY KEY (id),
    CONSTRAINT uq_corporate_authorized_driver_corporate_agreemen_cb7456fb UNIQUE (corporate_agreement_id, driver_profile_id, valid_from),
    CONSTRAINT ck_corporate_authorized_driver_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_authorized_driver_2 CHECK (status IN ('ACTIVE','SUSPENDED','EXPIRED','REVOKED'))
);

CREATE TABLE corporate.corporate_billing_profile (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_agreement_id             uuid NOT NULL,
    billing_party_id                   uuid NOT NULL,
    billing_address_id                 uuid,
    payment_terms_days                 integer NOT NULL DEFAULT 0,
    invoice_frequency                  varchar(20) NOT NULL,
    purchase_order_required            boolean NOT NULL DEFAULT FALSE,
    tax_document_email_ciphertext      text,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_corporate_billing_profile PRIMARY KEY (id),
    CONSTRAINT uq_corporate_corporate_billing_profile_corporate__64893437 UNIQUE (corporate_agreement_id),
    CONSTRAINT ck_corporate_corporate_billing_profile_1 CHECK (payment_terms_days >= 0),
    CONSTRAINT ck_corporate_corporate_billing_profile_2 CHECK (invoice_frequency IN ('PER_CONTRACT','WEEKLY','BIWEEKLY','MONTHLY')),
    CONSTRAINT ck_corporate_corporate_billing_profile_3 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE fleet.acquisition_order (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    supplier_party_id                  uuid NOT NULL,
    order_number                       varchar(60) NOT NULL,
    order_date                         date NOT NULL,
    expected_delivery_date             date,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    total_amount                       decimal(19,4) NOT NULL DEFAULT 0,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_acquisition_order PRIMARY KEY (id),
    CONSTRAINT uq_fleet_acquisition_order_legal_entity_id_order_number_1 UNIQUE (legal_entity_id, order_number),
    CONSTRAINT ck_fleet_acquisition_order_1 CHECK (status IN ('DRAFT','APPROVED','PLACED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
    CONSTRAINT ck_fleet_acquisition_order_2 CHECK (total_amount >= 0)
);

CREATE TABLE fleet.acquisition_order_line (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    acquisition_order_id               uuid NOT NULL,
    line_number                        integer NOT NULL,
    vehicle_variant_id                 uuid NOT NULL,
    quantity_ordered                   integer NOT NULL,
    quantity_received                  integer NOT NULL DEFAULT 0,
    unit_price                         decimal(19,4) NOT NULL,
    expected_delivery_date             date,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_acquisition_order_line PRIMARY KEY (id),
    CONSTRAINT uq_fleet_acquisition_order_line_acquisition_order_26372419 UNIQUE (acquisition_order_id, line_number),
    CONSTRAINT ck_fleet_acquisition_order_line_1 CHECK (quantity_ordered > 0),
    CONSTRAINT ck_fleet_acquisition_order_line_2 CHECK (quantity_received >= 0),
    CONSTRAINT ck_fleet_acquisition_order_line_3 CHECK (quantity_received <= quantity_ordered),
    CONSTRAINT ck_fleet_acquisition_order_line_4 CHECK (unit_price >= 0)
);

CREATE TABLE fleet.vehicle (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_number                       varchar(40) NOT NULL,
    vin                                varchar(40) NOT NULL,
    vehicle_variant_id                 uuid NOT NULL,
    owning_legal_entity_id             uuid NOT NULL,
    acquisition_order_line_id          uuid,
    acquired_at                        date,
    in_service_at                      date,
    current_branch_id                  uuid,
    current_vehicle_group_id           uuid,
    current_operational_state          varchar(30) NOT NULL DEFAULT 'PICKUP_PREPARATION',
    current_lifecycle_state            varchar(30) NOT NULL DEFAULT 'RECEIVED',
    current_odometer_km                decimal(12,1) NOT NULL DEFAULT 0,
    current_fuel_level                 decimal(5,2),
    status_reason                      varchar(120),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_vehicle PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_fleet_number_1 UNIQUE (fleet_number),
    CONSTRAINT uq_fleet_vehicle_vin_2 UNIQUE (vin),
    CONSTRAINT ck_fleet_vehicle_1 CHECK (current_operational_state IN ('AVAILABLE','PICKUP_PREPARATION','RENTED','RETURN_PROCESSING','CLEANING','MAINTENANCE','IN_TRANSFER','QUARANTINED','BLOCKED','SALE_PREPARATION')),
    CONSTRAINT ck_fleet_vehicle_2 CHECK (current_lifecycle_state IN ('ORDERED','RECEIVED','IN_FLEET','DISPOSAL_CANDIDATE','SALE_PREPARATION','LISTED_FOR_SALE','SOLD','DEREGISTERED')),
    CONSTRAINT ck_fleet_vehicle_3 CHECK (current_odometer_km >= 0),
    CONSTRAINT ck_fleet_vehicle_4 CHECK (current_fuel_level IS NULL OR (current_fuel_level >= 0 AND current_fuel_level <= 100))
);

CREATE TABLE fleet.vehicle_registration (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    country_code                       char(2) NOT NULL,
    registration_number                varchar(30) NOT NULL,
    registration_hmac                  bytea,
    issuing_region                     varchar(80),
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    document_object_key                varchar(500),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_registration PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_registration_country_code_regist_344750a9 UNIQUE (country_code, registration_number, valid_from),
    CONSTRAINT ck_fleet_vehicle_registration_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_fleet_vehicle_registration_2 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','REPLACED'))
);

CREATE TABLE fleet.vehicle_group_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    assignment_reason                  varchar(60),
    assigned_by                        uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_group_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_group_assignment_vehicle_id_valid_from_1 UNIQUE (vehicle_id, valid_from),
    CONSTRAINT ck_fleet_vehicle_group_assignment_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE fleet.vehicle_operational_state_history (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         uuid,
    changed_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_operational_state_history PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_operational_state_history_1 CHECK (to_status IN ('AVAILABLE','PICKUP_PREPARATION','RENTED','RETURN_PROCESSING','CLEANING','MAINTENANCE','IN_TRANSFER','QUARANTINED','BLOCKED','SALE_PREPARATION'))
);

CREATE TABLE fleet.vehicle_lifecycle_history (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         uuid,
    changed_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_lifecycle_history PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_lifecycle_history_1 CHECK (to_status IN ('ORDERED','RECEIVED','IN_FLEET','DISPOSAL_CANDIDATE','SALE_PREPARATION','LISTED_FOR_SALE','SOLD','DEREGISTERED'))
);

CREATE TABLE fleet.vehicle_restriction (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    restriction_type                   varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    reason_code                        varchar(60),
    starts_at                          timestamptz NOT NULL,
    ends_at                            timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_type                        varchar(40),
    source_id                          uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_vehicle_restriction PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_restriction_1 CHECK (severity IN ('INFO','WARNING','BLOCKING')),
    CONSTRAINT ck_fleet_vehicle_restriction_2 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED')),
    CONSTRAINT ck_fleet_vehicle_restriction_3 CHECK (ends_at IS NULL OR ends_at > starts_at)
);

CREATE TABLE fleet.vehicle_location_history (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    branch_id                          uuid,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    location_type                      varchar(30) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          uuid,
    recorded_at                        timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_location_history PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_location_history_1 CHECK (location_type IN ('BRANCH','GPS','WORKSHOP','CUSTOMER','TRANSFER','OTHER'))
);

CREATE TABLE fleet.vehicle_calendar_entry (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz NOT NULL,
    entry_type                         varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          uuid,
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_vehicle_calendar_entry PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_calendar_entry_1 CHECK (end_at > start_at),
    CONSTRAINT ck_fleet_vehicle_calendar_entry_2 CHECK (entry_type IN ('RENTAL','MAINTENANCE','TRANSFER','CLEANING','INSPECTION','SALE_PREPARATION','MANUAL_BLOCK')),
    CONSTRAINT ck_fleet_vehicle_calendar_entry_3 CHECK (status IN ('HELD','CONFIRMED','ACTIVE','CLOSED','CANCELLED','SUPERSEDED'))
);

CREATE TABLE fleet.odometer_reading (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    reading_km                         decimal(12,1) NOT NULL,
    reading_at                         timestamptz NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          uuid,
    is_correction                      boolean NOT NULL DEFAULT FALSE,
    corrects_reading_id                uuid,
    recorded_by                        uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_odometer_reading PRIMARY KEY (id),
    CONSTRAINT ck_fleet_odometer_reading_1 CHECK (reading_km >= 0),
    CONSTRAINT ck_fleet_odometer_reading_2 CHECK (corrects_reading_id IS NULL OR corrects_reading_id <> id)
);

CREATE TABLE fleet.fuel_reading (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    fuel_level_percent                 decimal(5,2) NOT NULL,
    reading_at                         timestamptz NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          uuid,
    recorded_by                        uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_fuel_reading PRIMARY KEY (id),
    CONSTRAINT ck_fleet_fuel_reading_1 CHECK (fuel_level_percent >= 0 AND fuel_level_percent <= 100)
);

CREATE TABLE fleet.asset_document (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             bytea,
    issued_at                          date,
    expires_at                         date,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_asset_document PRIMARY KEY (id),
    CONSTRAINT ck_fleet_asset_document_1 CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT ck_fleet_asset_document_2 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','REPLACED'))
);

CREATE TABLE fleet.accessory_asset (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    asset_code                         varchar(50) NOT NULL,
    product_id                         uuid NOT NULL,
    serial_number                      varchar(100),
    owning_legal_entity_id             uuid NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_accessory_asset PRIMARY KEY (id),
    CONSTRAINT uq_fleet_accessory_asset_asset_code_1 UNIQUE (asset_code),
    CONSTRAINT ck_fleet_accessory_asset_1 CHECK (status IN ('AVAILABLE','ASSIGNED','MAINTENANCE','LOST','RETIRED'))
);

CREATE TABLE fleet.vehicle_accessory_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    accessory_asset_id                 uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    assignment_reason                  varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_accessory_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_accessory_assignment_accessory_a_3ae41b12 UNIQUE (accessory_asset_id, start_at),
    CONSTRAINT ck_fleet_vehicle_accessory_assignment_1 CHECK (end_at IS NULL OR end_at > start_at)
);

CREATE TABLE fleet.vehicle_cost_basis (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    purchase_amount                    decimal(19,4) NOT NULL,
    capitalized_cost_amount            decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    effective_date                     date NOT NULL,
    source_reference                   varchar(100),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_vehicle_cost_basis PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_cost_basis_vehicle_id_effective_date_1 UNIQUE (vehicle_id, effective_date),
    CONSTRAINT ck_fleet_vehicle_cost_basis_1 CHECK (purchase_amount >= 0),
    CONSTRAINT ck_fleet_vehicle_cost_basis_2 CHECK (capitalized_cost_amount >= 0)
);

CREATE TABLE fleet.depreciation_entry (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    period_start                       date NOT NULL,
    period_end                         date NOT NULL,
    depreciation_amount                decimal(19,4) NOT NULL,
    book_value_after                   decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    accounting_reference               varchar(100),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_depreciation_entry PRIMARY KEY (id),
    CONSTRAINT uq_fleet_depreciation_entry_vehicle_id_period_sta_7a43f62c UNIQUE (vehicle_id, period_start, period_end),
    CONSTRAINT ck_fleet_depreciation_entry_1 CHECK (period_end >= period_start),
    CONSTRAINT ck_fleet_depreciation_entry_2 CHECK (depreciation_amount >= 0),
    CONSTRAINT ck_fleet_depreciation_entry_3 CHECK (book_value_after >= 0)
);

CREATE TABLE fleet.disposal_eligibility (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    evaluated_at                       timestamptz NOT NULL,
    eligible                           boolean NOT NULL,
    reason_codes                       jsonb,
    recommended_channel                varchar(40),
    estimated_residual_value           decimal(19,4),
    currency_code                      char(3),
    model_version                      varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_disposal_eligibility PRIMARY KEY (id)
);

CREATE TABLE pricing.rate_plan (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    plan_code                          varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    rental_mode                        varchar(30) NOT NULL,
    description                        text,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_rate_plan PRIMARY KEY (id),
    CONSTRAINT uq_pricing_rate_plan_legal_entity_id_plan_code_1 UNIQUE (legal_entity_id, plan_code),
    CONSTRAINT ck_pricing_rate_plan_1 CHECK (rental_mode IN ('HOURLY','DAILY','WEEKLY','MONTHLY','SUBSCRIPTION','CORPORATE')),
    CONSTRAINT ck_pricing_rate_plan_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE pricing.rate_plan_version (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_id                       uuid NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    currency_code                      char(3) NOT NULL,
    calculation_version                varchar(60) NOT NULL,
    ruleset_hash                       varchar(64) NOT NULL,
    published_at                       timestamptz,
    published_by                       uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_rate_plan_version PRIMARY KEY (id),
    CONSTRAINT uq_pricing_rate_plan_version_rate_plan_id_version_number_1 UNIQUE (rate_plan_id, version_number),
    CONSTRAINT ck_pricing_rate_plan_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_pricing_rate_plan_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE pricing.rate_plan_applicability (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    origin_branch_id                   uuid,
    destination_branch_id              uuid,
    vehicle_group_id                   uuid,
    channel_id                         uuid,
    customer_segment                   varchar(30),
    corporate_agreement_id             uuid,
    partner_id                         uuid,
    priority                           smallint NOT NULL DEFAULT 100,
    condition_json                     jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_rate_plan_applicability PRIMARY KEY (id)
);

CREATE TABLE pricing.rental_length_band (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    band_code                          varchar(30) NOT NULL,
    minimum_minutes                    integer NOT NULL,
    maximum_minutes                    integer,
    billing_unit                       varchar(20) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_rental_length_band PRIMARY KEY (id),
    CONSTRAINT uq_pricing_rental_length_band_rate_plan_version_i_f4ae433d UNIQUE (rate_plan_version_id, band_code),
    CONSTRAINT ck_pricing_rental_length_band_1 CHECK (minimum_minutes >= 0),
    CONSTRAINT ck_pricing_rental_length_band_2 CHECK (maximum_minutes IS NULL OR maximum_minutes > minimum_minutes),
    CONSTRAINT ck_pricing_rental_length_band_3 CHECK (billing_unit IN ('HOUR','DAY','WEEK','MONTH'))
);

CREATE TABLE pricing.season (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    season_code                        varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    start_date                         date NOT NULL,
    end_date                           date NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    recurrence_rule                    varchar(300),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_season PRIMARY KEY (id),
    CONSTRAINT uq_pricing_season_legal_entity_id_season_code_start_date_1 UNIQUE (legal_entity_id, season_code, start_date),
    CONSTRAINT ck_pricing_season_1 CHECK (end_date >= start_date)
);

CREATE TABLE pricing.base_rate (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    origin_branch_id                   uuid,
    rental_length_band_id              uuid,
    season_id                          uuid,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    minimum_charge_amount              decimal(19,4),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_base_rate PRIMARY KEY (id),
    CONSTRAINT ck_pricing_base_rate_1 CHECK (amount >= 0),
    CONSTRAINT ck_pricing_base_rate_2 CHECK (minimum_charge_amount IS NULL OR minimum_charge_amount >= 0),
    CONSTRAINT ck_pricing_base_rate_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE pricing.mileage_package (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    package_code                       varchar(40) NOT NULL,
    name                               varchar(120) NOT NULL,
    included_km                        decimal(12,2),
    included_km_per_unit               decimal(12,2),
    is_unlimited                       boolean NOT NULL DEFAULT FALSE,
    billing_mode                       varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_mileage_package PRIMARY KEY (id),
    CONSTRAINT uq_pricing_mileage_package_rate_plan_version_id_p_3dc9d824 UNIQUE (rate_plan_version_id, package_code),
    CONSTRAINT ck_pricing_mileage_package_1 CHECK (included_km IS NULL OR included_km >= 0),
    CONSTRAINT ck_pricing_mileage_package_2 CHECK (included_km_per_unit IS NULL OR included_km_per_unit >= 0),
    CONSTRAINT ck_pricing_mileage_package_3 CHECK (billing_mode IN ('FIXED','PER_RENTAL_UNIT','FLEXIBLE')),
    CONSTRAINT ck_pricing_mileage_package_4 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE pricing.mileage_rate (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    mileage_package_id                 uuid NOT NULL,
    vehicle_group_id                   uuid,
    excess_km_amount                   decimal(19,4) NOT NULL,
    flex_km_amount                     decimal(19,4),
    currency_code                      char(3) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_mileage_rate PRIMARY KEY (id),
    CONSTRAINT ck_pricing_mileage_rate_1 CHECK (excess_km_amount >= 0),
    CONSTRAINT ck_pricing_mileage_rate_2 CHECK (flex_km_amount IS NULL OR flex_km_amount >= 0),
    CONSTRAINT ck_pricing_mileage_rate_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE pricing.one_way_rule (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    origin_branch_id                   uuid,
    destination_branch_id              uuid,
    origin_region                      varchar(80),
    destination_region                 varchar(80),
    vehicle_group_id                   uuid,
    calculation_type                   varchar(30) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_one_way_rule PRIMARY KEY (id),
    CONSTRAINT ck_pricing_one_way_rule_1 CHECK (calculation_type IN ('FIXED','DISTANCE','PERCENTAGE','WAIVED','DENIED')),
    CONSTRAINT ck_pricing_one_way_rule_2 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE pricing.one_way_price (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    one_way_rule_id                    uuid NOT NULL,
    fixed_amount                       decimal(19,4),
    amount_per_km                      decimal(19,6),
    percentage_rate                    decimal(9,6),
    minimum_amount                     decimal(19,4),
    maximum_amount                     decimal(19,4),
    currency_code                      char(3),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_one_way_price PRIMARY KEY (id),
    CONSTRAINT uq_pricing_one_way_price_one_way_rule_id_1 UNIQUE (one_way_rule_id),
    CONSTRAINT ck_pricing_one_way_price_1 CHECK (fixed_amount IS NULL OR fixed_amount >= 0),
    CONSTRAINT ck_pricing_one_way_price_2 CHECK (amount_per_km IS NULL OR amount_per_km >= 0),
    CONSTRAINT ck_pricing_one_way_price_3 CHECK (percentage_rate IS NULL OR percentage_rate >= 0),
    CONSTRAINT ck_pricing_one_way_price_4 CHECK (minimum_amount IS NULL OR minimum_amount >= 0),
    CONSTRAINT ck_pricing_one_way_price_5 CHECK (maximum_amount IS NULL OR maximum_amount >= 0)
);

CREATE TABLE pricing.fuel_price (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    branch_id                          uuid,
    fuel_type                          varchar(30) NOT NULL,
    amount_per_liter                   decimal(19,6) NOT NULL,
    service_multiplier                 decimal(10,6) NOT NULL DEFAULT 1,
    currency_code                      char(3) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_fuel_price PRIMARY KEY (id),
    CONSTRAINT ck_pricing_fuel_price_1 CHECK (amount_per_liter >= 0),
    CONSTRAINT ck_pricing_fuel_price_2 CHECK (service_multiplier >= 0),
    CONSTRAINT ck_pricing_fuel_price_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE pricing.preauthorization_rule (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    vehicle_group_id                   uuid,
    customer_segment                   varchar(30),
    fixed_amount                       decimal(19,4),
    rental_multiplier                  decimal(10,6),
    minimum_amount                     decimal(19,4),
    maximum_amount                     decimal(19,4),
    currency_code                      char(3) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_preauthorization_rule PRIMARY KEY (id),
    CONSTRAINT ck_pricing_preauthorization_rule_1 CHECK (fixed_amount IS NULL OR fixed_amount >= 0),
    CONSTRAINT ck_pricing_preauthorization_rule_2 CHECK (rental_multiplier IS NULL OR rental_multiplier >= 0),
    CONSTRAINT ck_pricing_preauthorization_rule_3 CHECK (minimum_amount IS NULL OR minimum_amount >= 0),
    CONSTRAINT ck_pricing_preauthorization_rule_4 CHECK (maximum_amount IS NULL OR maximum_amount >= 0)
);

CREATE TABLE pricing.pricing_rule (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rate_plan_version_id               uuid NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    rule_type                          varchar(40) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    condition_json                     jsonb NOT NULL,
    action_json                        jsonb NOT NULL,
    valid_from                         timestamptz,
    valid_to                           timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_pricing_rule PRIMARY KEY (id),
    CONSTRAINT uq_pricing_pricing_rule_rate_plan_version_id_rule_code_1 UNIQUE (rate_plan_version_id, rule_code),
    CONSTRAINT ck_pricing_pricing_rule_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_pricing_pricing_rule_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE pricing.promotion (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    promotion_code                     varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    stacking_policy                    varchar(30) NOT NULL,
    condition_json                     jsonb,
    action_json                        jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_promotion PRIMARY KEY (id),
    CONSTRAINT uq_pricing_promotion_promotion_code_1 UNIQUE (promotion_code),
    CONSTRAINT ck_pricing_promotion_1 CHECK (valid_to > valid_from),
    CONSTRAINT ck_pricing_promotion_2 CHECK (stacking_policy IN ('EXCLUSIVE','STACKABLE','BEST_ONLY')),
    CONSTRAINT ck_pricing_promotion_3 CHECK (status IN ('DRAFT','ACTIVE','PAUSED','EXPIRED','CANCELLED'))
);

CREATE TABLE pricing.coupon (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    promotion_id                       uuid NOT NULL,
    coupon_code                        varchar(80) NOT NULL,
    maximum_redemptions                integer,
    maximum_per_party                  integer,
    valid_from                         timestamptz,
    valid_to                           timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_coupon PRIMARY KEY (id),
    CONSTRAINT uq_pricing_coupon_coupon_code_1 UNIQUE (coupon_code),
    CONSTRAINT ck_pricing_coupon_1 CHECK (maximum_redemptions IS NULL OR maximum_redemptions > 0),
    CONSTRAINT ck_pricing_coupon_2 CHECK (maximum_per_party IS NULL OR maximum_per_party > 0),
    CONSTRAINT ck_pricing_coupon_3 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_pricing_coupon_4 CHECK (status IN ('ACTIVE','PAUSED','EXPIRED','CANCELLED'))
);

CREATE TABLE pricing.coupon_redemption (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    coupon_id                          uuid NOT NULL,
    party_id                           uuid,
    reservation_id                     uuid,
    quote_id                           uuid,
    redeemed_at                        timestamptz NOT NULL,
    status                             varchar(20) NOT NULL,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_coupon_redemption PRIMARY KEY (id),
    CONSTRAINT uq_pricing_coupon_redemption_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_pricing_coupon_redemption_1 CHECK (status IN ('RESERVED','CONSUMED','RELEASED','REVERSED'))
);

CREATE TABLE pricing.quote (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    quote_number                       varchar(60) NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    customer_account_id                uuid,
    rate_plan_version_id               uuid NOT NULL,
    origin_branch_id                   uuid NOT NULL,
    destination_branch_id              uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    channel_id                         uuid NOT NULL,
    planned_pickup_at                  timestamptz NOT NULL,
    planned_return_at                  timestamptz NOT NULL,
    currency_code                      char(3) NOT NULL,
    subtotal_amount                    decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL,
    expires_at                         timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'VALID',
    context_json                       jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_quote PRIMARY KEY (id),
    CONSTRAINT uq_pricing_quote_legal_entity_id_quote_number_1 UNIQUE (legal_entity_id, quote_number),
    CONSTRAINT ck_pricing_quote_1 CHECK (planned_return_at > planned_pickup_at),
    CONSTRAINT ck_pricing_quote_2 CHECK (expires_at > created_at),
    CONSTRAINT ck_pricing_quote_3 CHECK (subtotal_amount >= 0),
    CONSTRAINT ck_pricing_quote_4 CHECK (discount_amount >= 0),
    CONSTRAINT ck_pricing_quote_5 CHECK (tax_amount >= 0),
    CONSTRAINT ck_pricing_quote_6 CHECK (total_amount >= 0),
    CONSTRAINT ck_pricing_quote_7 CHECK (status IN ('VALID','EXPIRED','CONVERTED','CANCELLED'))
);

CREATE TABLE pricing.quote_line (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    quote_id                           uuid NOT NULL,
    line_number                        integer NOT NULL,
    product_id                         uuid,
    charge_type_id                     uuid,
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    service_start_at                   timestamptz,
    service_end_at                     timestamptz,
    rule_reference                     varchar(160),
    line_metadata                      jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_quote_line PRIMARY KEY (id),
    CONSTRAINT uq_pricing_quote_line_quote_id_line_number_1 UNIQUE (quote_id, line_number),
    CONSTRAINT ck_pricing_quote_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_pricing_quote_line_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_pricing_quote_line_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_pricing_quote_line_4 CHECK (gross_amount = base_amount - discount_amount + tax_amount),
    CONSTRAINT ck_pricing_quote_line_5 CHECK (service_end_at IS NULL OR service_start_at IS NULL OR service_end_at > service_start_at)
);

CREATE TABLE pricing.pricing_calculation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    quote_id                           uuid NOT NULL,
    calculation_sequence               integer NOT NULL,
    calculation_version                varchar(60) NOT NULL,
    input_hash                         varchar(64) NOT NULL,
    input_snapshot                     jsonb NOT NULL,
    output_snapshot                    jsonb NOT NULL,
    duration_ms                        integer,
    calculated_at                      timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_pricing_calculation PRIMARY KEY (id),
    CONSTRAINT uq_pricing_pricing_calculation_quote_id_calculati_d1b53ccc UNIQUE (quote_id, calculation_sequence),
    CONSTRAINT ck_pricing_pricing_calculation_1 CHECK (duration_ms IS NULL OR duration_ms >= 0)
);

CREATE TABLE pricing.quote_rule_trace (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    pricing_calculation_id             uuid NOT NULL,
    sequence_number                    integer NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    matched                            boolean NOT NULL,
    condition_result                   jsonb,
    action_result                      jsonb,
    explanation                        text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_pricing_quote_rule_trace PRIMARY KEY (id),
    CONSTRAINT uq_pricing_quote_rule_trace_pricing_calculation_i_ea988f52 UNIQUE (pricing_calculation_id, sequence_number)
);

CREATE TABLE corporate.rate_entitlement (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_agreement_id             uuid NOT NULL,
    rate_plan_id                       uuid NOT NULL,
    vehicle_group_id                   uuid,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    priority                           smallint NOT NULL DEFAULT 100,
    constraints_json                   jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_corporate_rate_entitlement PRIMARY KEY (id),
    CONSTRAINT ck_corporate_rate_entitlement_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE corporate.purchase_order (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_agreement_id             uuid NOT NULL,
    purchase_order_number              varchar(80) NOT NULL,
    cost_center_id                     uuid,
    valid_from                         date,
    valid_to                           date,
    authorized_amount                  decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_purchase_order PRIMARY KEY (id),
    CONSTRAINT uq_corporate_purchase_order_corporate_agreement_i_393e33a8 UNIQUE (corporate_agreement_id, purchase_order_number),
    CONSTRAINT ck_corporate_purchase_order_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_corporate_purchase_order_2 CHECK (authorized_amount IS NULL OR authorized_amount >= 0),
    CONSTRAINT ck_corporate_purchase_order_3 CHECK (status IN ('ACTIVE','EXHAUSTED','EXPIRED','CANCELLED'))
);

CREATE TABLE corporate.voucher (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_agreement_id             uuid,
    partner_agreement_id               uuid,
    voucher_code                       varchar(100) NOT NULL,
    authorized_party_id                uuid,
    valid_from                         timestamptz,
    valid_to                           timestamptz,
    maximum_amount                     decimal(19,4),
    currency_code                      char(3),
    usage_limit                        integer NOT NULL DEFAULT 1,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_voucher PRIMARY KEY (id),
    CONSTRAINT uq_corporate_voucher_voucher_code_1 UNIQUE (voucher_code),
    CONSTRAINT ck_corporate_voucher_1 CHECK (usage_limit > 0),
    CONSTRAINT ck_corporate_voucher_2 CHECK (maximum_amount IS NULL OR maximum_amount >= 0),
    CONSTRAINT ck_corporate_voucher_3 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_voucher_4 CHECK (status IN ('ACTIVE','RESERVED','CONSUMED','EXPIRED','CANCELLED'))
);

CREATE TABLE corporate.consolidated_billing_instruction (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    corporate_billing_profile_id       uuid NOT NULL,
    grouping_key                       varchar(40) NOT NULL,
    cutoff_day                         smallint,
    delivery_channel                   varchar(20) NOT NULL,
    recipient_contact_id               uuid,
    configuration_json                 jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_corporate_consolidated_billing_instruction PRIMARY KEY (id),
    CONSTRAINT ck_corporate_consolidated_billing_instruction_1 CHECK (cutoff_day IS NULL OR cutoff_day BETWEEN 1 AND 31),
    CONSTRAINT ck_corporate_consolidated_billing_instruction_2 CHECK (delivery_channel IN ('EMAIL','SFTP','API','PORTAL')),
    CONSTRAINT ck_corporate_consolidated_billing_instruction_3 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE availability.inventory_bucket (
    branch_id                          uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    bucket_start                       timestamptz NOT NULL,
    local_business_date                date NOT NULL,
    projected_capacity_qty             integer NOT NULL DEFAULT 0,
    blocked_qty                        integer NOT NULL DEFAULT 0,
    safety_buffer_qty                  integer NOT NULL DEFAULT 0,
    overbook_limit_qty                 integer NOT NULL DEFAULT 0,
    held_qty                           integer NOT NULL DEFAULT 0,
    committed_qty                      integer NOT NULL DEFAULT 0,
    projection_version                 bigint NOT NULL DEFAULT 0,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_availability_inventory_bucket PRIMARY KEY (branch_id, vehicle_group_id, bucket_start),
    CONSTRAINT ck_availability_inventory_bucket_1 CHECK (projected_capacity_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_2 CHECK (blocked_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_3 CHECK (safety_buffer_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_4 CHECK (overbook_limit_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_5 CHECK (held_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_6 CHECK (committed_qty >= 0)
);

CREATE TABLE availability.availability_hold (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    hold_token                         varchar(120) NOT NULL,
    branch_id                          uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz NOT NULL,
    quantity                           integer NOT NULL DEFAULT 1,
    expires_at                         timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_type                        varchar(40),
    source_id                          uuid,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_availability_hold PRIMARY KEY (id),
    CONSTRAINT uq_availability_availability_hold_hold_token_1 UNIQUE (hold_token),
    CONSTRAINT uq_availability_availability_hold_idempotency_key_2 UNIQUE (idempotency_key),
    CONSTRAINT ck_availability_availability_hold_1 CHECK (end_at > start_at),
    CONSTRAINT ck_availability_availability_hold_2 CHECK (quantity > 0),
    CONSTRAINT ck_availability_availability_hold_3 CHECK (expires_at > created_at),
    CONSTRAINT ck_availability_availability_hold_4 CHECK (status IN ('ACTIVE','CONVERTED','EXPIRED','RELEASED'))
);

CREATE TABLE availability.capacity_commitment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    branch_id                          uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz NOT NULL,
    quantity                           integer NOT NULL DEFAULT 1,
    commitment_type                    varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_type                        varchar(40) NOT NULL,
    source_id                          uuid NOT NULL,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_capacity_commitment PRIMARY KEY (id),
    CONSTRAINT uq_availability_capacity_commitment_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_availability_capacity_commitment_1 CHECK (end_at > start_at),
    CONSTRAINT ck_availability_capacity_commitment_2 CHECK (quantity > 0),
    CONSTRAINT ck_availability_capacity_commitment_3 CHECK (commitment_type IN ('RESERVATION','ALLOTMENT','MANUAL','BUFFER')),
    CONSTRAINT ck_availability_capacity_commitment_4 CHECK (status IN ('ACTIVE','CONSUMED','RELEASED','CANCELLED'))
);

CREATE TABLE availability.upgrade_path (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    origin_branch_id                   uuid,
    from_group_id                      uuid NOT NULL,
    to_group_id                        uuid NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    cost_policy                        varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_availability_upgrade_path PRIMARY KEY (id),
    CONSTRAINT uq_availability_upgrade_path_origin_branch_id_fro_bc702385 UNIQUE (origin_branch_id, from_group_id, to_group_id, valid_from),
    CONSTRAINT ck_availability_upgrade_path_1 CHECK (from_group_id <> to_group_id),
    CONSTRAINT ck_availability_upgrade_path_2 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_availability_upgrade_path_3 CHECK (cost_policy IN ('FREE','CUSTOMER_PAYS','MANAGER_APPROVAL')),
    CONSTRAINT ck_availability_upgrade_path_4 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE availability.fleet_allotment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    partner_agreement_id               uuid,
    corporate_agreement_id             uuid,
    branch_id                          uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz NOT NULL,
    quantity                           integer NOT NULL,
    release_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_availability_fleet_allotment PRIMARY KEY (id),
    CONSTRAINT ck_availability_fleet_allotment_1 CHECK (end_at > start_at),
    CONSTRAINT ck_availability_fleet_allotment_2 CHECK (quantity > 0),
    CONSTRAINT ck_availability_fleet_allotment_3 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED','CANCELLED'))
);

CREATE TABLE availability.relocation_order (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    order_number                       varchar(60) NOT NULL,
    origin_branch_id                   uuid NOT NULL,
    destination_branch_id              uuid NOT NULL,
    planned_departure_at               timestamptz NOT NULL,
    planned_arrival_at                 timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    reason_code                        varchar(60),
    created_by                         uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_relocation_order PRIMARY KEY (id),
    CONSTRAINT uq_availability_relocation_order_legal_entity_id__2783fe4e UNIQUE (legal_entity_id, order_number),
    CONSTRAINT ck_availability_relocation_order_1 CHECK (planned_arrival_at > planned_departure_at),
    CONSTRAINT ck_availability_relocation_order_2 CHECK (status IN ('PLANNED','DISPATCHED','IN_TRANSIT','COMPLETED','CANCELLED'))
);

CREATE TABLE availability.relocation_leg (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    relocation_order_id                uuid NOT NULL,
    sequence_number                    integer NOT NULL,
    vehicle_id                         uuid NOT NULL,
    calendar_entry_id                  uuid,
    departed_at                        timestamptz,
    arrived_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_availability_relocation_leg PRIMARY KEY (id),
    CONSTRAINT uq_availability_relocation_leg_relocation_order_i_26aef275 UNIQUE (relocation_order_id, sequence_number),
    CONSTRAINT uq_availability_relocation_leg_relocation_order_i_53141511 UNIQUE (relocation_order_id, vehicle_id),
    CONSTRAINT ck_availability_relocation_leg_1 CHECK (arrived_at IS NULL OR departed_at IS NULL OR arrived_at >= departed_at),
    CONSTRAINT ck_availability_relocation_leg_2 CHECK (status IN ('PLANNED','IN_TRANSIT','COMPLETED','CANCELLED'))
);

CREATE TABLE availability.oversell_alert (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    branch_id                          uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    bucket_start                       timestamptz NOT NULL,
    shortage_qty                       integer NOT NULL,
    severity                           varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    detected_at                        timestamptz NOT NULL,
    resolved_at                        timestamptz,
    resolution_note                    text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_oversell_alert PRIMARY KEY (id),
    CONSTRAINT ck_availability_oversell_alert_1 CHECK (shortage_qty > 0),
    CONSTRAINT ck_availability_oversell_alert_2 CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_availability_oversell_alert_3 CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED','IGNORED'))
);

CREATE TABLE availability.forecast_snapshot (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    branch_id                          uuid NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    bucket_start                       timestamptz NOT NULL,
    forecast_version                   varchar(60) NOT NULL,
    expected_returns_qty               decimal(12,4) NOT NULL,
    expected_pickups_qty               decimal(12,4) NOT NULL,
    expected_no_show_qty               decimal(12,4) NOT NULL,
    confidence                         decimal(8,6),
    generated_at                       timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_availability_forecast_snapshot PRIMARY KEY (id),
    CONSTRAINT uq_availability_forecast_snapshot_branch_id_vehic_7bf6534b UNIQUE (branch_id, vehicle_group_id, bucket_start, forecast_version),
    CONSTRAINT ck_availability_forecast_snapshot_1 CHECK (expected_returns_qty >= 0),
    CONSTRAINT ck_availability_forecast_snapshot_2 CHECK (expected_pickups_qty >= 0),
    CONSTRAINT ck_availability_forecast_snapshot_3 CHECK (expected_no_show_qty >= 0),
    CONSTRAINT ck_availability_forecast_snapshot_4 CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
);

CREATE TABLE reservation.reservation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_number                 varchar(60) NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    customer_account_id                uuid,
    booker_party_id                    uuid,
    requested_vehicle_group_id         uuid NOT NULL,
    pickup_branch_id                   uuid NOT NULL,
    planned_return_branch_id           uuid NOT NULL,
    planned_pickup_at                  timestamptz NOT NULL,
    planned_return_at                  timestamptz NOT NULL,
    rental_mode                        varchar(30) NOT NULL,
    channel_id                         uuid NOT NULL,
    rate_plan_version_id               uuid NOT NULL,
    quote_id                           uuid,
    corporate_agreement_id             uuid,
    cost_center_id                     uuid,
    purchase_order_id                  uuid,
    voucher_id                         uuid,
    current_status                     varchar(20) NOT NULL DEFAULT 'DRAFT',
    guarantee_status                   varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    expires_at                         timestamptz,
    external_reference                 varchar(160),
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_reservation_reservation PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_legal_entity_id_reserv_ab7bda09 UNIQUE (legal_entity_id, reservation_number),
    CONSTRAINT ck_reservation_reservation_1 CHECK (planned_return_at > planned_pickup_at),
    CONSTRAINT ck_reservation_reservation_2 CHECK (rental_mode IN ('HOURLY','DAILY','WEEKLY','MONTHLY','CORPORATE')),
    CONSTRAINT ck_reservation_reservation_3 CHECK (current_status IN ('DRAFT','HELD','CONFIRMED','PICKUP_READY','CONVERTED','CANCELLED','EXPIRED','NO_SHOW')),
    CONSTRAINT ck_reservation_reservation_4 CHECK (guarantee_status IN ('NOT_REQUIRED','PENDING','AUTHORIZED','FAILED','EXPIRED','RELEASED'))
);

CREATE TABLE reservation.reservation_driver (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    driver_profile_id                  uuid NOT NULL,
    driver_role                        varchar(20) NOT NULL,
    eligibility_status                 varchar(20) NOT NULL DEFAULT 'PENDING',
    eligibility_checked_at             timestamptz,
    young_driver_applies               boolean NOT NULL DEFAULT FALSE,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_driver PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_driver_reservation_id__5504cc73 UNIQUE (reservation_id, driver_profile_id),
    CONSTRAINT ck_reservation_reservation_driver_1 CHECK (driver_role IN ('PRIMARY','ADDITIONAL')),
    CONSTRAINT ck_reservation_reservation_driver_2 CHECK (eligibility_status IN ('PENDING','ELIGIBLE','INELIGIBLE','REVIEW'))
);

CREATE TABLE reservation.reservation_product (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    product_id                         uuid NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    configuration_json                 jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_product PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_product_reservation_id_937dcf71 UNIQUE (reservation_id, product_id),
    CONSTRAINT ck_reservation_reservation_product_1 CHECK (quantity > 0),
    CONSTRAINT ck_reservation_reservation_product_2 CHECK (status IN ('ACTIVE','REMOVED','UNAVAILABLE'))
);

CREATE TABLE reservation.reservation_price_line (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    line_number                        integer NOT NULL,
    quote_line_id                      uuid,
    product_id                         uuid,
    charge_type_id                     uuid,
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    rate_plan_version_id               uuid NOT NULL,
    rule_reference                     varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_price_line PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_price_line_reservation_653da8d8 UNIQUE (reservation_id, line_number),
    CONSTRAINT ck_reservation_reservation_price_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_reservation_reservation_price_line_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_reservation_reservation_price_line_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_reservation_reservation_price_line_4 CHECK (gross_amount = base_amount - discount_amount + tax_amount)
);

CREATE TABLE reservation.reservation_status_history (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         uuid,
    changed_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_status_history PRIMARY KEY (id),
    CONSTRAINT ck_reservation_reservation_status_history_1 CHECK (to_status IN ('DRAFT','HELD','CONFIRMED','PICKUP_READY','CONVERTED','CANCELLED','EXPIRED','NO_SHOW'))
);

CREATE TABLE reservation.reservation_change (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    change_sequence                    integer NOT NULL,
    change_type                        varchar(40) NOT NULL,
    requested_by_party_id              uuid,
    previous_snapshot                  jsonb NOT NULL,
    new_snapshot                       jsonb NOT NULL,
    price_delta_amount                 decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    changed_at                         timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_change PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_change_reservation_id__fa6280d3 UNIQUE (reservation_id, change_sequence)
);

CREATE TABLE reservation.reservation_cancellation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    cancelled_at                       timestamptz NOT NULL,
    cancelled_by_party_id              uuid,
    reason_code                        varchar(60) NOT NULL,
    reason_text                        text,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    policy_rule_reference              varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_cancellation PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_cancellation_reservation_id_1 UNIQUE (reservation_id),
    CONSTRAINT ck_reservation_reservation_cancellation_1 CHECK (fee_amount >= 0)
);

CREATE TABLE reservation.no_show_assessment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    assessed_at                        timestamptz NOT NULL,
    grace_period_minutes               integer NOT NULL,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    rule_reference                     varchar(160),
    waived                             boolean NOT NULL DEFAULT FALSE,
    waiver_reason                      text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_no_show_assessment PRIMARY KEY (id),
    CONSTRAINT uq_reservation_no_show_assessment_reservation_id_1 UNIQUE (reservation_id),
    CONSTRAINT ck_reservation_no_show_assessment_1 CHECK (grace_period_minutes >= 0),
    CONSTRAINT ck_reservation_no_show_assessment_2 CHECK (fee_amount >= 0)
);

CREATE TABLE reservation.reservation_guarantee (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    guarantee_type                     varchar(30) NOT NULL,
    amount                             decimal(19,4),
    currency_code                      char(3),
    provider_reference                 varchar(160),
    status                             varchar(20) NOT NULL,
    authorized_at                      timestamptz,
    expires_at                         timestamptz,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_reservation_reservation_guarantee PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_guarantee_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_reservation_reservation_guarantee_1 CHECK (amount IS NULL OR amount >= 0),
    CONSTRAINT ck_reservation_reservation_guarantee_2 CHECK (guarantee_type IN ('CARD_PREAUTH','VOUCHER','CORPORATE_CREDIT','PREPAYMENT','NONE')),
    CONSTRAINT ck_reservation_reservation_guarantee_3 CHECK (status IN ('PENDING','AUTHORIZED','FAILED','EXPIRED','RELEASED','CONSUMED'))
);

CREATE TABLE reservation.partner_booking (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    partner_id                         uuid NOT NULL,
    partner_agreement_id               uuid,
    external_booking_reference         varchar(160) NOT NULL,
    external_status                    varchar(60),
    commission_amount                  decimal(19,4),
    currency_code                      char(3),
    raw_payload                        jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_partner_booking PRIMARY KEY (id),
    CONSTRAINT uq_reservation_partner_booking_partner_id_externa_083fe7a4 UNIQUE (partner_id, external_booking_reference),
    CONSTRAINT ck_reservation_partner_booking_1 CHECK (commission_amount IS NULL OR commission_amount >= 0)
);

CREATE TABLE reservation.digital_pickup_eligibility (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    eligible                           boolean NOT NULL,
    decision                           varchar(20) NOT NULL,
    reason_codes                       jsonb,
    rule_version                       varchar(60),
    assessed_at                        timestamptz NOT NULL,
    expires_at                         timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_digital_pickup_eligibility PRIMARY KEY (id),
    CONSTRAINT ck_reservation_digital_pickup_eligibility_1 CHECK (decision IN ('ELIGIBLE','INELIGIBLE','REVIEW')),
    CONSTRAINT ck_reservation_digital_pickup_eligibility_2 CHECK (expires_at IS NULL OR expires_at > assessed_at)
);

CREATE TABLE reservation.reservation_note (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    note_type                          varchar(30) NOT NULL,
    note_text                          text NOT NULL,
    visibility                         varchar(20) NOT NULL,
    created_by                         uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_note PRIMARY KEY (id),
    CONSTRAINT ck_reservation_reservation_note_1 CHECK (visibility IN ('INTERNAL','CUSTOMER_VISIBLE','PARTNER_VISIBLE'))
);

CREATE TABLE reservation.reservation_inventory_commitment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    reservation_id                     uuid NOT NULL,
    availability_hold_id               uuid,
    capacity_commitment_id             uuid,
    relation_type                      varchar(20) NOT NULL,
    linked_at                          timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reservation_reservation_inventory_commitment PRIMARY KEY (id),
    CONSTRAINT ck_reservation_reservation_inventory_commitment_1 CHECK (relation_type IN ('HOLD','COMMITMENT')),
    CONSTRAINT ck_reservation_reservation_inventory_commitment_2 CHECK ((relation_type = 'HOLD' AND availability_hold_id IS NOT NULL AND capacity_commitment_id IS NULL) OR (relation_type = 'COMMITMENT' AND capacity_commitment_id IS NOT NULL AND availability_hold_id IS NULL))
);

CREATE TABLE rental.rental_contract (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_number                    varchar(60) NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    reservation_id                     uuid,
    customer_account_id                uuid NOT NULL,
    origin_branch_id                   uuid NOT NULL,
    planned_return_branch_id           uuid NOT NULL,
    actual_return_branch_id            uuid,
    rental_mode                        varchar(30) NOT NULL,
    mileage_package_id                 uuid,
    opened_at                          timestamptz NOT NULL,
    activated_at                       timestamptz,
    planned_return_at                  timestamptz NOT NULL,
    actual_return_at                   timestamptz,
    current_revision_number            integer NOT NULL DEFAULT 0,
    current_status                     varchar(20) NOT NULL DEFAULT 'OPENING',
    currency_code                      char(3) NOT NULL,
    created_channel_id                 uuid NOT NULL,
    closed_reason                      varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_rental_contract PRIMARY KEY (id),
    CONSTRAINT uq_rental_rental_contract_legal_entity_id_contrac_e46b4872 UNIQUE (legal_entity_id, contract_number),
    CONSTRAINT uq_rental_rental_contract_reservation_id_2 UNIQUE (reservation_id),
    CONSTRAINT ck_rental_rental_contract_1 CHECK (planned_return_at > opened_at),
    CONSTRAINT ck_rental_rental_contract_2 CHECK (actual_return_at IS NULL OR actual_return_at >= opened_at),
    CONSTRAINT ck_rental_rental_contract_3 CHECK (activated_at IS NULL OR activated_at >= opened_at),
    CONSTRAINT ck_rental_rental_contract_4 CHECK (rental_mode IN ('HOURLY','DAILY','WEEKLY','MONTHLY','CORPORATE')),
    CONSTRAINT ck_rental_rental_contract_5 CHECK (current_status IN ('OPENING','ACTIVE','OVERDUE','RETURN_PENDING','CLOSED','CANCELLED'))
);

CREATE TABLE rental.contract_revision (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    revision_number                    integer NOT NULL,
    previous_revision_id               uuid,
    reason_code                        varchar(60) NOT NULL,
    effective_at                       timestamptz NOT NULL,
    document_hash                      varchar(64),
    pricing_snapshot_hash              varchar(64),
    snapshot_json                      jsonb NOT NULL,
    created_by                         uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_contract_revision PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_revision_contract_id_revision_number_1 UNIQUE (contract_id, revision_number),
    CONSTRAINT ck_rental_contract_revision_1 CHECK (revision_number >= 0)
);

CREATE TABLE rental.contract_party_role (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    party_id                           uuid NOT NULL,
    role_type                          varchar(30) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    source_type                        varchar(40),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_contract_party_role PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_party_role_contract_id_party_i_4a6cbbeb UNIQUE (contract_id, party_id, role_type, valid_from),
    CONSTRAINT ck_rental_contract_party_role_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_rental_contract_party_role_2 CHECK (role_type IN ('CUSTOMER','BOOKER','CORPORATE_USER','REPRESENTATIVE','PRIMARY_DRIVER','ADDITIONAL_DRIVER','PAYER','BENEFICIARY'))
);

CREATE TABLE rental.contract_product (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    product_id                         uuid NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    locked_at_activation               boolean NOT NULL DEFAULT FALSE,
    configuration_json                 jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_contract_product PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_product_contract_id_product_id_1 UNIQUE (contract_id, product_id),
    CONSTRAINT ck_rental_contract_product_1 CHECK (quantity > 0),
    CONSTRAINT ck_rental_contract_product_2 CHECK (status IN ('ACTIVE','REMOVED','CONSUMED'))
);

CREATE TABLE rental.contract_price_snapshot_line (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    contract_revision_id               uuid NOT NULL,
    line_number                        integer NOT NULL,
    reservation_price_line_id          uuid,
    product_id                         uuid,
    charge_type_id                     uuid,
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    rate_plan_version_id               uuid NOT NULL,
    rule_reference                     varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_contract_price_snapshot_line PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_price_snapshot_line_contract_r_0abd84bf UNIQUE (contract_revision_id, line_number),
    CONSTRAINT ck_rental_contract_price_snapshot_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_rental_contract_price_snapshot_line_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_rental_contract_price_snapshot_line_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_rental_contract_price_snapshot_line_4 CHECK (gross_amount = base_amount - discount_amount + tax_amount)
);

CREATE TABLE rental.vehicle_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    calendar_entry_id                  uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    sequence_number                    smallint NOT NULL,
    pickup_branch_id                   uuid NOT NULL,
    planned_return_branch_id           uuid NOT NULL,
    actual_return_branch_id            uuid,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    assignment_reason                  varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_vehicle_assignment PRIMARY KEY (id),
    CONSTRAINT uq_rental_vehicle_assignment_contract_id_sequence_number_1 UNIQUE (contract_id, sequence_number),
    CONSTRAINT uq_rental_vehicle_assignment_calendar_entry_id_2 UNIQUE (calendar_entry_id),
    CONSTRAINT ck_rental_vehicle_assignment_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_rental_vehicle_assignment_2 CHECK (assignment_reason IN ('INITIAL','REPLACEMENT')),
    CONSTRAINT ck_rental_vehicle_assignment_3 CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','CANCELLED'))
);

CREATE TABLE rental.pickup_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    vehicle_assignment_id              uuid NOT NULL,
    branch_id                          uuid NOT NULL,
    picked_up_at                       timestamptz NOT NULL,
    odometer_reading_id                uuid NOT NULL,
    fuel_reading_id                    uuid,
    inspection_id                      uuid,
    performed_by                       uuid,
    digital_pickup                     boolean NOT NULL DEFAULT FALSE,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_pickup_event PRIMARY KEY (id),
    CONSTRAINT uq_rental_pickup_event_vehicle_assignment_id_1 UNIQUE (vehicle_assignment_id)
);

CREATE TABLE rental.return_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    vehicle_assignment_id              uuid NOT NULL,
    branch_id                          uuid NOT NULL,
    returned_at                        timestamptz NOT NULL,
    odometer_reading_id                uuid NOT NULL,
    fuel_reading_id                    uuid,
    inspection_id                      uuid,
    performed_by                       uuid,
    after_hours                        boolean NOT NULL DEFAULT FALSE,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_return_event PRIMARY KEY (id),
    CONSTRAINT uq_rental_return_event_vehicle_assignment_id_1 UNIQUE (vehicle_assignment_id)
);

CREATE TABLE rental.extension (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    requested_at                       timestamptz NOT NULL,
    requested_by_party_id              uuid,
    previous_planned_return_at         timestamptz NOT NULL,
    new_planned_return_at              timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    availability_checked_at            timestamptz,
    payment_checked_at                 timestamptz,
    price_delta_amount                 decimal(19,4),
    currency_code                      char(3),
    decision_reason                    text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_extension PRIMARY KEY (id),
    CONSTRAINT ck_rental_extension_1 CHECK (new_planned_return_at > previous_planned_return_at),
    CONSTRAINT ck_rental_extension_2 CHECK (status IN ('REQUESTED','APPROVED','REJECTED','CANCELLED','APPLIED'))
);

CREATE TABLE rental.vehicle_replacement (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    previous_assignment_id             uuid NOT NULL,
    new_assignment_id                  uuid NOT NULL,
    reason_code                        varchar(60) NOT NULL,
    replaced_at                        timestamptz NOT NULL,
    authorized_by                      uuid,
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_vehicle_replacement PRIMARY KEY (id),
    CONSTRAINT uq_rental_vehicle_replacement_previous_assignment_id_1 UNIQUE (previous_assignment_id),
    CONSTRAINT uq_rental_vehicle_replacement_new_assignment_id_2 UNIQUE (new_assignment_id),
    CONSTRAINT ck_rental_vehicle_replacement_1 CHECK (previous_assignment_id <> new_assignment_id)
);

CREATE TABLE rental.contract_status_history (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         uuid,
    changed_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_contract_status_history PRIMARY KEY (id),
    CONSTRAINT ck_rental_contract_status_history_1 CHECK (to_status IN ('OPENING','ACTIVE','OVERDUE','RETURN_PENDING','CLOSED','CANCELLED'))
);

CREATE TABLE rental.contract_terms_acceptance (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    contract_revision_id               uuid NOT NULL,
    party_id                           uuid NOT NULL,
    terms_type                         varchar(40) NOT NULL,
    terms_version                      varchar(60) NOT NULL,
    accepted_at                        timestamptz NOT NULL,
    channel_id                         uuid,
    evidence_hash                      varchar(64) NOT NULL,
    ip_address_token                   varchar(100),
    device_reference                   varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_contract_terms_acceptance PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_terms_acceptance_contract_revi_e69987ad UNIQUE (contract_revision_id, party_id, terms_type, terms_version)
);

CREATE TABLE rental.contract_document (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    contract_revision_id               uuid,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             bytea,
    generated_at                       timestamptz NOT NULL,
    signed_at                          timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rental_contract_document PRIMARY KEY (id),
    CONSTRAINT ck_rental_contract_document_1 CHECK (status IN ('ACTIVE','SUPERSEDED','VOID'))
);

CREATE TABLE rental.digital_pickup_session (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    reservation_id                     uuid,
    party_id                           uuid NOT NULL,
    session_token_hash                 bytea NOT NULL,
    started_at                         timestamptz NOT NULL,
    expires_at                         timestamptz NOT NULL,
    completed_at                       timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'STARTED',
    failure_reason                     varchar(120),
    device_reference                   varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_digital_pickup_session PRIMARY KEY (id),
    CONSTRAINT uq_rental_digital_pickup_session_session_token_hash_1 UNIQUE (session_token_hash),
    CONSTRAINT ck_rental_digital_pickup_session_1 CHECK (expires_at > started_at),
    CONSTRAINT ck_rental_digital_pickup_session_2 CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ck_rental_digital_pickup_session_3 CHECK (status IN ('STARTED','IDENTITY_VERIFIED','PAYMENT_VERIFIED','READY','COMPLETED','FAILED','EXPIRED','CANCELLED'))
);

CREATE TABLE rental.vehicle_access_credential (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    digital_pickup_session_id          uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    credential_type                    varchar(30) NOT NULL,
    credential_token_ciphertext        text NOT NULL,
    issued_at                          timestamptz NOT NULL,
    expires_at                         timestamptz NOT NULL,
    revoked_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_vehicle_access_credential PRIMARY KEY (id),
    CONSTRAINT ck_rental_vehicle_access_credential_1 CHECK (expires_at > issued_at),
    CONSTRAINT ck_rental_vehicle_access_credential_2 CHECK (revoked_at IS NULL OR revoked_at >= issued_at),
    CONSTRAINT ck_rental_vehicle_access_credential_3 CHECK (credential_type IN ('DIGITAL_KEY','PIN','BLUETOOTH_TOKEN','NFC_TOKEN')),
    CONSTRAINT ck_rental_vehicle_access_credential_4 CHECK (status IN ('ACTIVE','USED','EXPIRED','REVOKED'))
);

CREATE TABLE rental.vehicle_access_command (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid,
    vehicle_id                         uuid NOT NULL,
    command_type                       varchar(30) NOT NULL,
    requested_by                       uuid,
    reason_code                        varchar(60),
    requested_at                       timestamptz NOT NULL,
    expires_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    provider_reference                 varchar(160),
    result_code                        varchar(60),
    completed_at                       timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_vehicle_access_command PRIMARY KEY (id),
    CONSTRAINT ck_rental_vehicle_access_command_1 CHECK (command_type IN ('UNLOCK','LOCK','START_ENABLE','START_DISABLE','HORN','LIGHTS')),
    CONSTRAINT ck_rental_vehicle_access_command_2 CHECK (status IN ('REQUESTED','SENT','ACKNOWLEDGED','SUCCEEDED','FAILED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_rental_vehicle_access_command_3 CHECK (expires_at IS NULL OR expires_at > requested_at)
);

CREATE TABLE rental.overdue_case (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    opened_at                          timestamptz NOT NULL,
    severity                           varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    last_contact_at                    timestamptz,
    next_action_at                     timestamptz,
    assigned_to                        uuid,
    resolution_code                    varchar(60),
    closed_at                          timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_overdue_case PRIMARY KEY (id),
    CONSTRAINT uq_rental_overdue_case_contract_id_1 UNIQUE (contract_id),
    CONSTRAINT ck_rental_overdue_case_1 CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_rental_overdue_case_2 CHECK (status IN ('OPEN','CONTACTING','ESCALATED','RECOVERY','CLOSED')),
    CONSTRAINT ck_rental_overdue_case_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE rental.contract_reprocessing (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_id                        uuid NOT NULL,
    requested_at                       timestamptz NOT NULL,
    requested_by                       uuid,
    reason_code                        varchar(60) NOT NULL,
    previous_revision_number           integer NOT NULL,
    new_revision_number                integer,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    financial_delta_amount             decimal(19,4),
    currency_code                      char(3),
    result_json                        jsonb,
    completed_at                       timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_contract_reprocessing PRIMARY KEY (id),
    CONSTRAINT ck_rental_contract_reprocessing_1 CHECK (status IN ('REQUESTED','PROCESSING','COMPLETED','FAILED','CANCELLED'))
);

CREATE TABLE inspection.inspection_template (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    template_code                      varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    inspection_type                    varchar(30) NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_inspection_template PRIMARY KEY (id),
    CONSTRAINT uq_inspection_inspection_template_template_code_v_2484f4a5 UNIQUE (template_code, version_number),
    CONSTRAINT ck_inspection_inspection_template_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_inspection_inspection_template_2 CHECK (inspection_type IN ('PICKUP','RETURN','MAINTENANCE','TRANSFER','SALE','AD_HOC')),
    CONSTRAINT ck_inspection_inspection_template_3 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE inspection.inspection_template_item (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_template_id             uuid NOT NULL,
    item_code                          varchar(50) NOT NULL,
    label                              varchar(160) NOT NULL,
    item_type                          varchar(30) NOT NULL,
    required                           boolean NOT NULL DEFAULT TRUE,
    sort_order                         integer NOT NULL DEFAULT 0,
    configuration_json                 jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inspection_inspection_template_item PRIMARY KEY (id),
    CONSTRAINT uq_inspection_inspection_template_item_inspection_a33ef367 UNIQUE (inspection_template_id, item_code),
    CONSTRAINT ck_inspection_inspection_template_item_1 CHECK (item_type IN ('BOOLEAN','TEXT','NUMBER','CHOICE','PHOTO','ODOMETER','FUEL','DAMAGE_MAP','SIGNATURE'))
);

CREATE TABLE inspection.inspection (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_template_id             uuid NOT NULL,
    inspection_type                    varchar(30) NOT NULL,
    vehicle_id                         uuid NOT NULL,
    contract_id                        uuid,
    vehicle_assignment_id              uuid,
    branch_id                          uuid,
    started_at                         timestamptz NOT NULL,
    completed_at                       timestamptz,
    performed_by                       uuid,
    status                             varchar(20) NOT NULL DEFAULT 'IN_PROGRESS',
    device_reference                   varchar(160),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_inspection PRIMARY KEY (id),
    CONSTRAINT ck_inspection_inspection_1 CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ck_inspection_inspection_2 CHECK (inspection_type IN ('PICKUP','RETURN','MAINTENANCE','TRANSFER','SALE','AD_HOC')),
    CONSTRAINT ck_inspection_inspection_3 CHECK (status IN ('IN_PROGRESS','COMPLETED','CANCELLED','SUPERSEDED'))
);

CREATE TABLE inspection.inspection_item_result (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_id                      uuid NOT NULL,
    template_item_id                   uuid NOT NULL,
    result_text                        text,
    result_number                      decimal(19,6),
    result_boolean                     boolean,
    result_json                        jsonb,
    passed                             boolean,
    observed_at                        timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inspection_inspection_item_result PRIMARY KEY (id),
    CONSTRAINT uq_inspection_inspection_item_result_inspection_i_72157564 UNIQUE (inspection_id, template_item_id)
);

CREATE TABLE inspection.inspection_media (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_id                      uuid NOT NULL,
    template_item_id                   uuid,
    media_type                         varchar(20) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             bytea,
    captured_at                        timestamptz NOT NULL,
    captured_by                        uuid,
    device_reference                   varchar(160),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inspection_inspection_media PRIMARY KEY (id),
    CONSTRAINT ck_inspection_inspection_media_1 CHECK (media_type IN ('PHOTO','VIDEO','AUDIO','SIGNATURE','DOCUMENT'))
);

CREATE TABLE inspection.damage_record (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    body_part                          varchar(60) NOT NULL,
    damage_type                        varchar(40) NOT NULL,
    position_x                         decimal(8,5),
    position_y                         decimal(8,5),
    severity                           varchar(20) NOT NULL,
    first_observed_at                  timestamptz NOT NULL,
    resolved_at                        timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_record PRIMARY KEY (id),
    CONSTRAINT ck_inspection_damage_record_1 CHECK (position_x IS NULL OR (position_x >= 0 AND position_x <= 1)),
    CONSTRAINT ck_inspection_damage_record_2 CHECK (position_y IS NULL OR (position_y >= 0 AND position_y <= 1)),
    CONSTRAINT ck_inspection_damage_record_3 CHECK (severity IN ('COSMETIC','MINOR','MODERATE','MAJOR','SAFETY')),
    CONSTRAINT ck_inspection_damage_record_4 CHECK (status IN ('OPEN','MONITORED','REPAIRED','WRITTEN_OFF')),
    CONSTRAINT ck_inspection_damage_record_5 CHECK (resolved_at IS NULL OR resolved_at >= first_observed_at)
);

CREATE TABLE inspection.damage_observation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    damage_record_id                   uuid NOT NULL,
    inspection_id                      uuid NOT NULL,
    observed_status                    varchar(20) NOT NULL,
    severity                           varchar(20) NOT NULL,
    media_id                           uuid,
    notes                              text,
    observed_at                        timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inspection_damage_observation PRIMARY KEY (id),
    CONSTRAINT uq_inspection_damage_observation_damage_record_id_7eccb3ff UNIQUE (damage_record_id, inspection_id),
    CONSTRAINT ck_inspection_damage_observation_1 CHECK (observed_status IN ('EXISTING','NEW','WORSENED','UNCHANGED','RESOLVED')),
    CONSTRAINT ck_inspection_damage_observation_2 CHECK (severity IN ('COSMETIC','MINOR','MODERATE','MAJOR','SAFETY'))
);

CREATE TABLE inspection.damage_attribution (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    damage_record_id                   uuid NOT NULL,
    contract_id                        uuid,
    incident_id                        uuid,
    attribution_status                 varchar(20) NOT NULL,
    decision_reason                    text,
    decided_at                         timestamptz,
    decided_by                         uuid,
    responsible_party_id               uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_attribution PRIMARY KEY (id),
    CONSTRAINT ck_inspection_damage_attribution_1 CHECK (attribution_status IN ('PENDING','CUSTOMER','COMPANY','THIRD_PARTY','PRE_EXISTING','UNDETERMINED','WAIVED'))
);

CREATE TABLE inspection.damage_assessment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    damage_record_id                   uuid NOT NULL,
    contract_id                        uuid,
    assessment_version                 integer NOT NULL,
    assessed_at                        timestamptz NOT NULL,
    repair_estimate_amount             decimal(19,4),
    downtime_amount                    decimal(19,4),
    administrative_amount              decimal(19,4),
    customer_charge_amount             decimal(19,4),
    currency_code                      char(3),
    method                             varchar(30) NOT NULL,
    assessor_party_id                  uuid,
    price_table_version                varchar(60),
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_assessment PRIMARY KEY (id),
    CONSTRAINT uq_inspection_damage_assessment_damage_record_id__e1fad7c0 UNIQUE (damage_record_id, assessment_version),
    CONSTRAINT ck_inspection_damage_assessment_1 CHECK (repair_estimate_amount IS NULL OR repair_estimate_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_2 CHECK (downtime_amount IS NULL OR downtime_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_3 CHECK (administrative_amount IS NULL OR administrative_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_4 CHECK (customer_charge_amount IS NULL OR customer_charge_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_5 CHECK (method IN ('PRICE_TABLE','MANUAL_ESTIMATE','WORKSHOP_QUOTE','INSURER')),
    CONSTRAINT ck_inspection_damage_assessment_6 CHECK (status IN ('DRAFT','APPROVED','REJECTED','SUPERSEDED'))
);

CREATE TABLE inspection.damage_price_table_version (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    table_code                         varchar(50) NOT NULL,
    version_number                     integer NOT NULL,
    country_code                       char(2) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    currency_code                      char(3) NOT NULL,
    price_data                         jsonb NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_price_table_version PRIMARY KEY (id),
    CONSTRAINT uq_inspection_damage_price_table_version_table_co_a76ef88e UNIQUE (table_code, version_number),
    CONSTRAINT ck_inspection_damage_price_table_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_inspection_damage_price_table_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE inspection.fuel_assessment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_id                      uuid NOT NULL,
    contract_id                        uuid NOT NULL,
    pickup_level_percent               decimal(5,2) NOT NULL,
    return_level_percent               decimal(5,2) NOT NULL,
    missing_liters                     decimal(10,3) NOT NULL DEFAULT 0,
    unit_price                         decimal(19,6) NOT NULL DEFAULT 0,
    service_fee_amount                 decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    fuel_price_id                      uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inspection_fuel_assessment PRIMARY KEY (id),
    CONSTRAINT uq_inspection_fuel_assessment_inspection_id_1 UNIQUE (inspection_id),
    CONSTRAINT ck_inspection_fuel_assessment_1 CHECK (pickup_level_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_inspection_fuel_assessment_2 CHECK (return_level_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_inspection_fuel_assessment_3 CHECK (missing_liters >= 0),
    CONSTRAINT ck_inspection_fuel_assessment_4 CHECK (unit_price >= 0),
    CONSTRAINT ck_inspection_fuel_assessment_5 CHECK (service_fee_amount >= 0),
    CONSTRAINT ck_inspection_fuel_assessment_6 CHECK (total_amount >= 0)
);

CREATE TABLE inspection.cleaning_assessment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_id                      uuid NOT NULL,
    contract_id                        uuid NOT NULL,
    cleaning_level                     varchar(20) NOT NULL,
    chargeable                         boolean NOT NULL,
    amount                             decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    reason_codes                       jsonb,
    approved_by                        uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inspection_cleaning_assessment PRIMARY KEY (id),
    CONSTRAINT uq_inspection_cleaning_assessment_inspection_id_1 UNIQUE (inspection_id),
    CONSTRAINT ck_inspection_cleaning_assessment_1 CHECK (cleaning_level IN ('NORMAL','SPECIAL','BIOHAZARD','SMOKE','PET','EXTREME')),
    CONSTRAINT ck_inspection_cleaning_assessment_2 CHECK (amount >= 0)
);

CREATE TABLE inspection.lost_found_item (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    inspection_id                      uuid NOT NULL,
    contract_id                        uuid,
    item_description                   varchar(240) NOT NULL,
    found_at                           timestamptz NOT NULL,
    storage_location                   varchar(120),
    status                             varchar(20) NOT NULL DEFAULT 'STORED',
    released_to_party_id               uuid,
    released_at                        timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_lost_found_item PRIMARY KEY (id),
    CONSTRAINT ck_inspection_lost_found_item_1 CHECK (status IN ('STORED','CUSTOMER_NOTIFIED','RELEASED','DISPOSED','TRANSFERRED_TO_AUTHORITY'))
);

CREATE TABLE billing.payment_method_token (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    provider                           varchar(60) NOT NULL,
    provider_customer_reference        varchar(160),
    payment_token_ciphertext           text NOT NULL,
    fingerprint                        varchar(160),
    brand                              varchar(40),
    last4                              char(4),
    expiry_month                       smallint,
    expiry_year                        smallint,
    billing_address_id                 uuid,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_payment_method_token PRIMARY KEY (id),
    CONSTRAINT ck_billing_payment_method_token_1 CHECK (expiry_month IS NULL OR expiry_month BETWEEN 1 AND 12),
    CONSTRAINT ck_billing_payment_method_token_2 CHECK (expiry_year IS NULL OR expiry_year >= 2000),
    CONSTRAINT ck_billing_payment_method_token_3 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','FAILED'))
);

CREATE TABLE billing.charge (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    contract_id                        uuid,
    reservation_id                     uuid,
    charge_type_id                     uuid NOT NULL,
    source_context                     varchar(40) NOT NULL,
    source_id                          uuid NOT NULL,
    source_event_id                    varchar(160),
    service_start_at                   timestamptz,
    service_end_at                     timestamptz,
    quantity                           decimal(19,6) NOT NULL DEFAULT 1,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    rate_plan_version_id               uuid,
    rule_reference                     varchar(160),
    posting_status                     varchar(20) NOT NULL DEFAULT 'DRAFT',
    reversal_of_charge_id              uuid,
    idempotency_key                    varchar(160) NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    posted_at                          timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_charge PRIMARY KEY (id),
    CONSTRAINT uq_billing_charge_legal_entity_id_idempotency_key_1 UNIQUE (legal_entity_id, idempotency_key),
    CONSTRAINT ck_billing_charge_1 CHECK (service_end_at IS NULL OR service_start_at IS NULL OR service_end_at > service_start_at),
    CONSTRAINT ck_billing_charge_2 CHECK (quantity > 0),
    CONSTRAINT ck_billing_charge_3 CHECK (discount_amount >= 0),
    CONSTRAINT ck_billing_charge_4 CHECK (tax_amount >= 0),
    CONSTRAINT ck_billing_charge_5 CHECK (gross_amount = base_amount - discount_amount + tax_amount),
    CONSTRAINT ck_billing_charge_6 CHECK (posting_status IN ('DRAFT','POSTED','VOID')),
    CONSTRAINT ck_billing_charge_7 CHECK (reversal_of_charge_id IS NULL OR reversal_of_charge_id <> id)
);

CREATE TABLE billing.invoice (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    invoice_number                     varchar(60) NOT NULL,
    customer_account_id                uuid NOT NULL,
    billing_party_id                   uuid NOT NULL,
    contract_id                        uuid,
    corporate_agreement_id             uuid,
    issue_date                         date NOT NULL,
    due_date                           date NOT NULL,
    currency_code                      char(3) NOT NULL,
    subtotal_amount                    decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    supersedes_invoice_id              uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_invoice PRIMARY KEY (id),
    CONSTRAINT uq_billing_invoice_legal_entity_id_invoice_number_1 UNIQUE (legal_entity_id, invoice_number),
    CONSTRAINT ck_billing_invoice_1 CHECK (due_date >= issue_date),
    CONSTRAINT ck_billing_invoice_2 CHECK (subtotal_amount >= 0),
    CONSTRAINT ck_billing_invoice_3 CHECK (discount_amount >= 0),
    CONSTRAINT ck_billing_invoice_4 CHECK (tax_amount >= 0),
    CONSTRAINT ck_billing_invoice_5 CHECK (total_amount >= 0),
    CONSTRAINT ck_billing_invoice_6 CHECK (status IN ('DRAFT','ISSUED','PARTIALLY_PAID','PAID','OVERDUE','CANCELLED','WRITTEN_OFF'))
);

CREATE TABLE billing.invoice_line (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    invoice_id                         uuid NOT NULL,
    line_number                        integer NOT NULL,
    charge_id                          uuid NOT NULL,
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    net_amount                         decimal(19,4) NOT NULL,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_billing_invoice_line PRIMARY KEY (id),
    CONSTRAINT uq_billing_invoice_line_invoice_id_line_number_1 UNIQUE (invoice_id, line_number),
    CONSTRAINT uq_billing_invoice_line_invoice_id_charge_id_2 UNIQUE (invoice_id, charge_id),
    CONSTRAINT ck_billing_invoice_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_billing_invoice_line_2 CHECK (tax_amount >= 0),
    CONSTRAINT ck_billing_invoice_line_3 CHECK (gross_amount = net_amount + tax_amount)
);

CREATE TABLE billing.receivable (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    invoice_id                         uuid NOT NULL,
    receivable_number                  varchar(60) NOT NULL,
    original_amount                    decimal(19,4) NOT NULL,
    open_amount                        decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    due_date                           date NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_receivable PRIMARY KEY (id),
    CONSTRAINT uq_billing_receivable_receivable_number_1 UNIQUE (receivable_number),
    CONSTRAINT uq_billing_receivable_invoice_id_2 UNIQUE (invoice_id),
    CONSTRAINT ck_billing_receivable_1 CHECK (original_amount >= 0),
    CONSTRAINT ck_billing_receivable_2 CHECK (open_amount >= 0),
    CONSTRAINT ck_billing_receivable_3 CHECK (open_amount <= original_amount),
    CONSTRAINT ck_billing_receivable_4 CHECK (status IN ('OPEN','PARTIALLY_PAID','PAID','OVERDUE','DISPUTED','WRITTEN_OFF','CANCELLED'))
);

CREATE TABLE billing.payment_intent (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    party_id                           uuid NOT NULL,
    contract_id                        uuid,
    reservation_id                     uuid,
    receivable_id                      uuid,
    payment_method_token_id            uuid,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    capture_method                     varchar(20) NOT NULL,
    status                             varchar(30) NOT NULL DEFAULT 'CREATED',
    provider                           varchar(60) NOT NULL,
    provider_reference                 varchar(160),
    idempotency_key                    varchar(160) NOT NULL,
    expires_at                         timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_payment_intent PRIMARY KEY (id),
    CONSTRAINT uq_billing_payment_intent_legal_entity_id_idempot_5465443a UNIQUE (legal_entity_id, idempotency_key),
    CONSTRAINT ck_billing_payment_intent_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_payment_intent_2 CHECK (capture_method IN ('AUTOMATIC','MANUAL')),
    CONSTRAINT ck_billing_payment_intent_3 CHECK (status IN ('CREATED','REQUIRES_ACTION','PROCESSING','AUTHORIZED','CAPTURED','FAILED','CANCELLED','EXPIRED'))
);

CREATE TABLE billing.payment_transaction (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    payment_intent_id                  uuid,
    transaction_type                   varchar(30) NOT NULL,
    provider                           varchar(60) NOT NULL,
    provider_transaction_id            varchar(180) NOT NULL,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    settled_at                         timestamptz,
    failure_code                       varchar(80),
    raw_response                       jsonb,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_billing_payment_transaction PRIMARY KEY (id),
    CONSTRAINT uq_billing_payment_transaction_provider_provider__5cf6ecc2 UNIQUE (provider, provider_transaction_id),
    CONSTRAINT uq_billing_payment_transaction_idempotency_key_2 UNIQUE (idempotency_key),
    CONSTRAINT ck_billing_payment_transaction_1 CHECK (amount >= 0),
    CONSTRAINT ck_billing_payment_transaction_2 CHECK (transaction_type IN ('AUTHORIZE','CAPTURE','SALE','VOID','REFUND','CHARGEBACK','REVERSAL')),
    CONSTRAINT ck_billing_payment_transaction_3 CHECK (status IN ('PENDING','SUCCEEDED','FAILED','REVERSED'))
);

CREATE TABLE billing.payment_allocation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    payment_transaction_id             uuid NOT NULL,
    receivable_id                      uuid NOT NULL,
    allocated_amount                   decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    allocated_at                       timestamptz NOT NULL,
    reversal_of_allocation_id          uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_billing_payment_allocation PRIMARY KEY (id),
    CONSTRAINT ck_billing_payment_allocation_1 CHECK (allocated_amount > 0),
    CONSTRAINT ck_billing_payment_allocation_2 CHECK (reversal_of_allocation_id IS NULL OR reversal_of_allocation_id <> id)
);

CREATE TABLE billing.preauthorization (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    payment_method_token_id            uuid NOT NULL,
    reservation_id                     uuid,
    contract_id                        uuid,
    provider                           varchar(60) NOT NULL,
    provider_reference                 varchar(160) NOT NULL,
    authorized_amount                  decimal(19,4) NOT NULL,
    captured_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    released_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    authorized_at                      timestamptz NOT NULL,
    expires_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'AUTHORIZED',
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_preauthorization PRIMARY KEY (id),
    CONSTRAINT uq_billing_preauthorization_provider_provider_reference_1 UNIQUE (provider, provider_reference),
    CONSTRAINT uq_billing_preauthorization_idempotency_key_2 UNIQUE (idempotency_key),
    CONSTRAINT ck_billing_preauthorization_1 CHECK (authorized_amount >= 0),
    CONSTRAINT ck_billing_preauthorization_2 CHECK (captured_amount >= 0),
    CONSTRAINT ck_billing_preauthorization_3 CHECK (released_amount >= 0),
    CONSTRAINT ck_billing_preauthorization_4 CHECK (captured_amount + released_amount <= authorized_amount),
    CONSTRAINT ck_billing_preauthorization_5 CHECK (status IN ('PENDING','AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','RELEASED','EXPIRED','FAILED'))
);

CREATE TABLE billing.refund (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    payment_transaction_id             uuid NOT NULL,
    refund_transaction_id              uuid,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    reason_code                        varchar(60) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    requested_at                       timestamptz NOT NULL,
    completed_at                       timestamptz,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_refund PRIMARY KEY (id),
    CONSTRAINT uq_billing_refund_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_billing_refund_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_refund_2 CHECK (status IN ('REQUESTED','PROCESSING','SUCCEEDED','FAILED','CANCELLED'))
);

CREATE TABLE billing.credit_note (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    invoice_id                         uuid NOT NULL,
    credit_note_number                 varchar(60) NOT NULL,
    issue_date                         date NOT NULL,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    reason_code                        varchar(60) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ISSUED',
    tax_document_id                    uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_credit_note PRIMARY KEY (id),
    CONSTRAINT uq_billing_credit_note_credit_note_number_1 UNIQUE (credit_note_number),
    CONSTRAINT ck_billing_credit_note_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_credit_note_2 CHECK (status IN ('DRAFT','ISSUED','APPLIED','CANCELLED'))
);

CREATE TABLE billing.chargeback (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    payment_transaction_id             uuid NOT NULL,
    provider_case_reference            varchar(160) NOT NULL,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    reason_code                        varchar(80),
    opened_at                          timestamptz NOT NULL,
    response_due_at                    timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    outcome                            varchar(20),
    closed_at                          timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_chargeback PRIMARY KEY (id),
    CONSTRAINT uq_billing_chargeback_provider_case_reference_1 UNIQUE (provider_case_reference),
    CONSTRAINT ck_billing_chargeback_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_chargeback_2 CHECK (status IN ('OPEN','EVIDENCE_SUBMITTED','WON','LOST','CLOSED')),
    CONSTRAINT ck_billing_chargeback_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE billing.tax_document (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    invoice_id                         uuid,
    document_type                      varchar(30) NOT NULL,
    document_number                    varchar(80) NOT NULL,
    series                             varchar(30),
    access_key                         varchar(100),
    issued_at                          timestamptz NOT NULL,
    status                             varchar(20) NOT NULL,
    object_key                         varchar(500),
    provider_response                  jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_tax_document PRIMARY KEY (id),
    CONSTRAINT uq_billing_tax_document_legal_entity_id_document__76b2374c UNIQUE (legal_entity_id, document_type, document_number, series),
    CONSTRAINT ck_billing_tax_document_1 CHECK (status IN ('REQUESTED','AUTHORIZED','REJECTED','CANCELLED','VOID'))
);

CREATE TABLE billing.dunning_case (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    customer_account_id                uuid NOT NULL,
    receivable_id                      uuid NOT NULL,
    opened_at                          timestamptz NOT NULL,
    stage                              varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_to                        uuid,
    next_action_at                     timestamptz,
    closed_at                          timestamptz,
    resolution_code                    varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_dunning_case PRIMARY KEY (id),
    CONSTRAINT uq_billing_dunning_case_receivable_id_1 UNIQUE (receivable_id),
    CONSTRAINT ck_billing_dunning_case_1 CHECK (stage IN ('REMINDER','NOTICE','COLLECTION','LEGAL')),
    CONSTRAINT ck_billing_dunning_case_2 CHECK (status IN ('OPEN','PAUSED','PROMISE_TO_PAY','CLOSED')),
    CONSTRAINT ck_billing_dunning_case_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE billing.collection_action (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    dunning_case_id                    uuid NOT NULL,
    action_type                        varchar(40) NOT NULL,
    scheduled_at                       timestamptz,
    executed_at                        timestamptz,
    channel                            varchar(20),
    result_code                        varchar(60),
    notes                              text,
    performed_by                       uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_billing_collection_action PRIMARY KEY (id)
);

CREATE TABLE billing.settlement_batch (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    provider                           varchar(60) NOT NULL,
    batch_reference                    varchar(160) NOT NULL,
    settlement_date                    date NOT NULL,
    gross_amount                       decimal(19,4) NOT NULL,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    net_amount                         decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_settlement_batch PRIMARY KEY (id),
    CONSTRAINT uq_billing_settlement_batch_provider_batch_reference_1 UNIQUE (provider, batch_reference),
    CONSTRAINT ck_billing_settlement_batch_1 CHECK (gross_amount >= 0),
    CONSTRAINT ck_billing_settlement_batch_2 CHECK (fee_amount >= 0),
    CONSTRAINT ck_billing_settlement_batch_3 CHECK (status IN ('RECEIVED','RECONCILED','PARTIALLY_RECONCILED','REJECTED'))
);

CREATE TABLE billing.settlement_item (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    settlement_batch_id                uuid NOT NULL,
    payment_transaction_id             uuid,
    provider_transaction_id            varchar(180) NOT NULL,
    gross_amount                       decimal(19,4) NOT NULL,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    net_amount                         decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'MATCHED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_billing_settlement_item PRIMARY KEY (id),
    CONSTRAINT uq_billing_settlement_item_settlement_batch_id_pr_c0f4489e UNIQUE (settlement_batch_id, provider_transaction_id),
    CONSTRAINT ck_billing_settlement_item_1 CHECK (gross_amount >= 0),
    CONSTRAINT ck_billing_settlement_item_2 CHECK (fee_amount >= 0),
    CONSTRAINT ck_billing_settlement_item_3 CHECK (status IN ('MATCHED','UNMATCHED','DUPLICATE','MISMATCH'))
);

CREATE TABLE billing.reconciliation_issue (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    settlement_item_id                 uuid,
    issue_type                         varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    description                        text,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    opened_at                          timestamptz NOT NULL,
    resolved_at                        timestamptz,
    resolution_note                    text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_reconciliation_issue PRIMARY KEY (id),
    CONSTRAINT ck_billing_reconciliation_issue_1 CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_billing_reconciliation_issue_2 CHECK (status IN ('OPEN','INVESTIGATING','RESOLVED','IGNORED')),
    CONSTRAINT ck_billing_reconciliation_issue_3 CHECK (resolved_at IS NULL OR resolved_at >= opened_at)
);

CREATE TABLE billing.accounting_export (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    period_start                       date NOT NULL,
    period_end                         date NOT NULL,
    export_type                        varchar(30) NOT NULL,
    object_key                         varchar(500),
    record_count                       integer NOT NULL DEFAULT 0,
    total_debit                        decimal(19,4) NOT NULL DEFAULT 0,
    total_credit                       decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'GENERATED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_accounting_export PRIMARY KEY (id),
    CONSTRAINT ck_billing_accounting_export_1 CHECK (period_end >= period_start),
    CONSTRAINT ck_billing_accounting_export_2 CHECK (record_count >= 0),
    CONSTRAINT ck_billing_accounting_export_3 CHECK (status IN ('GENERATED','SENT','ACCEPTED','REJECTED'))
);

CREATE TABLE traffic.provider_import_batch (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    provider                           varchar(60) NOT NULL,
    batch_reference                    varchar(160) NOT NULL,
    received_at                        timestamptz NOT NULL,
    record_count                       integer NOT NULL DEFAULT 0,
    processed_count                    integer NOT NULL DEFAULT 0,
    error_count                        integer NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    object_key                         varchar(500),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_provider_import_batch PRIMARY KEY (id),
    CONSTRAINT uq_traffic_provider_import_batch_provider_batch_r_20ebf910 UNIQUE (provider, batch_reference),
    CONSTRAINT ck_traffic_provider_import_batch_1 CHECK (record_count >= 0),
    CONSTRAINT ck_traffic_provider_import_batch_2 CHECK (processed_count >= 0),
    CONSTRAINT ck_traffic_provider_import_batch_3 CHECK (error_count >= 0),
    CONSTRAINT ck_traffic_provider_import_batch_4 CHECK (status IN ('RECEIVED','PROCESSING','COMPLETED','PARTIAL','FAILED'))
);

CREATE TABLE traffic.traffic_notice (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    import_batch_id                    uuid,
    vehicle_id                         uuid NOT NULL,
    authority_code                     varchar(60) NOT NULL,
    external_notice_number             varchar(120) NOT NULL,
    infraction_code                    varchar(60),
    infraction_at                      timestamptz NOT NULL,
    location_text                      varchar(240),
    base_amount                        decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    due_date                           date,
    status                             varchar(30) NOT NULL DEFAULT 'RECEIVED',
    raw_payload                        jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_traffic_notice PRIMARY KEY (id),
    CONSTRAINT uq_traffic_traffic_notice_authority_code_external_4c8a0b01 UNIQUE (authority_code, external_notice_number),
    CONSTRAINT ck_traffic_traffic_notice_1 CHECK (base_amount >= 0),
    CONSTRAINT ck_traffic_traffic_notice_2 CHECK (status IN ('RECEIVED','ATTRIBUTED','NOMINATION_PENDING','APPEALED','CONFIRMED','PAID','CANCELLED'))
);

CREATE TABLE traffic.traffic_attribution (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    traffic_notice_id                  uuid NOT NULL,
    contract_id                        uuid,
    vehicle_assignment_id              uuid,
    driver_profile_id                  uuid,
    attribution_status                 varchar(30) NOT NULL,
    confidence                         decimal(8,6),
    attributed_at                      timestamptz,
    decided_by                         uuid,
    reason_text                        text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_traffic_attribution PRIMARY KEY (id),
    CONSTRAINT uq_traffic_traffic_attribution_traffic_notice_id_1 UNIQUE (traffic_notice_id),
    CONSTRAINT ck_traffic_traffic_attribution_1 CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    CONSTRAINT ck_traffic_traffic_attribution_2 CHECK (attribution_status IN ('PENDING','MATCHED','MANUAL_REVIEW','UNATTRIBUTED','COMPANY_RESPONSIBLE'))
);

CREATE TABLE traffic.driver_nomination (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    traffic_notice_id                  uuid NOT NULL,
    driver_profile_id                  uuid NOT NULL,
    submitted_at                       timestamptz,
    submission_deadline                date,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    authority_reference                varchar(160),
    document_object_key                varchar(500),
    rejection_reason                   text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_driver_nomination PRIMARY KEY (id),
    CONSTRAINT ck_traffic_driver_nomination_1 CHECK (status IN ('PENDING','SUBMITTED','ACCEPTED','REJECTED','EXPIRED','CANCELLED'))
);

CREATE TABLE traffic.traffic_appeal (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    traffic_notice_id                  uuid NOT NULL,
    appeal_level                       smallint NOT NULL DEFAULT 1,
    submitted_at                       timestamptz,
    deadline                           date,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    grounds                            text,
    document_object_key                varchar(500),
    decision_at                        timestamptz,
    decision_text                      text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_traffic_appeal PRIMARY KEY (id),
    CONSTRAINT ck_traffic_traffic_appeal_1 CHECK (appeal_level > 0),
    CONSTRAINT ck_traffic_traffic_appeal_2 CHECK (status IN ('DRAFT','SUBMITTED','UPHELD','DENIED','WITHDRAWN','EXPIRED'))
);

CREATE TABLE traffic.toll_tag (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    provider                           varchar(60) NOT NULL,
    tag_number                         varchar(100) NOT NULL,
    owning_legal_entity_id             uuid NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_toll_tag PRIMARY KEY (id),
    CONSTRAINT uq_traffic_toll_tag_provider_tag_number_1 UNIQUE (provider, tag_number),
    CONSTRAINT ck_traffic_toll_tag_1 CHECK (status IN ('ACTIVE','SUSPENDED','LOST','RETIRED'))
);

CREATE TABLE traffic.toll_tag_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    toll_tag_id                        uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_traffic_toll_tag_assignment PRIMARY KEY (id),
    CONSTRAINT uq_traffic_toll_tag_assignment_toll_tag_id_start_at_1 UNIQUE (toll_tag_id, start_at),
    CONSTRAINT ck_traffic_toll_tag_assignment_1 CHECK (end_at IS NULL OR end_at > start_at)
);

CREATE TABLE traffic.toll_transaction (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    import_batch_id                    uuid,
    provider                           varchar(60) NOT NULL,
    external_transaction_id            varchar(160) NOT NULL,
    toll_tag_id                        uuid,
    vehicle_id                         uuid NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    plaza_name                         varchar(160),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    contract_id                        uuid,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_toll_transaction PRIMARY KEY (id),
    CONSTRAINT uq_traffic_toll_transaction_provider_external_tra_55281db6 UNIQUE (provider, external_transaction_id),
    CONSTRAINT ck_traffic_toll_transaction_1 CHECK (amount >= 0),
    CONSTRAINT ck_traffic_toll_transaction_2 CHECK (status IN ('RECEIVED','ATTRIBUTED','CHARGED','DISPUTED','REVERSED'))
);

CREATE TABLE traffic.parking_transaction (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    provider                           varchar(60) NOT NULL,
    external_transaction_id            varchar(160) NOT NULL,
    vehicle_id                         uuid NOT NULL,
    entered_at                         timestamptz,
    exited_at                          timestamptz,
    location_name                      varchar(160),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    contract_id                        uuid,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_parking_transaction PRIMARY KEY (id),
    CONSTRAINT uq_traffic_parking_transaction_provider_external__c2aaba9a UNIQUE (provider, external_transaction_id),
    CONSTRAINT ck_traffic_parking_transaction_1 CHECK (amount >= 0),
    CONSTRAINT ck_traffic_parking_transaction_2 CHECK (exited_at IS NULL OR entered_at IS NULL OR exited_at >= entered_at),
    CONSTRAINT ck_traffic_parking_transaction_3 CHECK (status IN ('RECEIVED','ATTRIBUTED','CHARGED','DISPUTED','REVERSED'))
);

CREATE TABLE traffic.traffic_charge_link (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    source_type                        varchar(20) NOT NULL,
    traffic_notice_id                  uuid,
    toll_transaction_id                uuid,
    parking_transaction_id             uuid,
    charge_id                          uuid NOT NULL,
    linked_at                          timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_traffic_traffic_charge_link PRIMARY KEY (id),
    CONSTRAINT ck_traffic_traffic_charge_link_1 CHECK (source_type IN ('TRAFFIC_NOTICE','TOLL','PARKING')),
    CONSTRAINT ck_traffic_traffic_charge_link_2 CHECK ((source_type = 'TRAFFIC_NOTICE' AND traffic_notice_id IS NOT NULL AND toll_transaction_id IS NULL AND parking_transaction_id IS NULL) OR (source_type = 'TOLL' AND toll_transaction_id IS NOT NULL AND traffic_notice_id IS NULL AND parking_transaction_id IS NULL) OR (source_type = 'PARKING' AND parking_transaction_id IS NOT NULL AND traffic_notice_id IS NULL AND toll_transaction_id IS NULL))
);

CREATE TABLE claim.insurance_policy (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    legal_entity_id                    uuid NOT NULL,
    insurer_party_id                   uuid NOT NULL,
    policy_number                      varchar(100) NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    policy_document_key                varchar(500),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_insurance_policy PRIMARY KEY (id),
    CONSTRAINT uq_claim_insurance_policy_legal_entity_id_policy_number_1 UNIQUE (legal_entity_id, policy_number),
    CONSTRAINT ck_claim_insurance_policy_1 CHECK (valid_to > valid_from),
    CONSTRAINT ck_claim_insurance_policy_2 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','CANCELLED'))
);

CREATE TABLE claim.policy_coverage (
    insurance_policy_id                uuid NOT NULL,
    coverage_id                        uuid NOT NULL,
    deductible_amount                  decimal(19,4),
    coverage_limit_amount              decimal(19,4),
    currency_code                      char(3) NOT NULL,
    terms_json                         jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_claim_policy_coverage PRIMARY KEY (insurance_policy_id, coverage_id),
    CONSTRAINT ck_claim_policy_coverage_1 CHECK (deductible_amount IS NULL OR deductible_amount >= 0),
    CONSTRAINT ck_claim_policy_coverage_2 CHECK (coverage_limit_amount IS NULL OR coverage_limit_amount >= 0)
);

CREATE TABLE claim.incident (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    incident_number                    varchar(60) NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    contract_id                        uuid,
    incident_type                      varchar(30) NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    reported_at                        timestamptz NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    location_text                      varchar(240),
    description                        text,
    police_report_number               varchar(100),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_incident PRIMARY KEY (id),
    CONSTRAINT uq_claim_incident_legal_entity_id_incident_number_1 UNIQUE (legal_entity_id, incident_number),
    CONSTRAINT ck_claim_incident_1 CHECK (reported_at >= occurred_at),
    CONSTRAINT ck_claim_incident_2 CHECK (incident_type IN ('ACCIDENT','THEFT','ROBBERY','VANDALISM','FIRE','FLOOD','MECHANICAL_FAILURE','OTHER')),
    CONSTRAINT ck_claim_incident_3 CHECK (status IN ('OPEN','UNDER_REVIEW','RESOLVED','CLOSED','CANCELLED'))
);

CREATE TABLE claim.incident_party (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    incident_id                        uuid NOT NULL,
    party_id                           uuid,
    role_type                          varchar(30) NOT NULL,
    name_snapshot                      varchar(180),
    contact_snapshot                   jsonb,
    injury_severity                    varchar(20),
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_claim_incident_party PRIMARY KEY (id),
    CONSTRAINT ck_claim_incident_party_1 CHECK (role_type IN ('DRIVER','PASSENGER','THIRD_PARTY_DRIVER','THIRD_PARTY_OWNER','WITNESS','AUTHORITY','OTHER'))
);

CREATE TABLE claim.incident_vehicle (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    incident_id                        uuid NOT NULL,
    vehicle_id                         uuid,
    role_type                          varchar(30) NOT NULL,
    registration_snapshot              varchar(40),
    make_model_snapshot                varchar(180),
    drivable_after                     boolean,
    tow_required                       boolean,
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_claim_incident_vehicle PRIMARY KEY (id),
    CONSTRAINT ck_claim_incident_vehicle_1 CHECK (role_type IN ('RENTAL_VEHICLE','THIRD_PARTY_VEHICLE','OTHER'))
);

CREATE TABLE claim.incident_document (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    incident_id                        uuid NOT NULL,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             bytea,
    captured_at                        timestamptz NOT NULL,
    description                        varchar(240),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_claim_incident_document PRIMARY KEY (id)
);

CREATE TABLE claim.claim (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    claim_number                       varchar(60) NOT NULL,
    incident_id                        uuid NOT NULL,
    insurance_policy_id                uuid,
    contract_id                        uuid,
    claim_type                         varchar(30) NOT NULL,
    opened_at                          timestamptz NOT NULL,
    reported_to_insurer_at             timestamptz,
    status                             varchar(30) NOT NULL DEFAULT 'OPEN',
    estimated_amount                   decimal(19,4),
    approved_amount                    decimal(19,4),
    currency_code                      char(3),
    insurer_reference                  varchar(160),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_claim PRIMARY KEY (id),
    CONSTRAINT uq_claim_claim_claim_number_1 UNIQUE (claim_number),
    CONSTRAINT ck_claim_claim_1 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_claim_claim_2 CHECK (approved_amount IS NULL OR approved_amount >= 0),
    CONSTRAINT ck_claim_claim_3 CHECK (claim_type IN ('OWN_DAMAGE','THIRD_PARTY','THEFT','TOTAL_LOSS','ASSISTANCE','OTHER')),
    CONSTRAINT ck_claim_claim_4 CHECK (status IN ('OPEN','SUBMITTED','UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','DENIED','PAID','CLOSED','CANCELLED'))
);

CREATE TABLE claim.claim_coverage_decision (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    claim_id                           uuid NOT NULL,
    coverage_id                        uuid NOT NULL,
    decision                           varchar(30) NOT NULL,
    decided_at                         timestamptz,
    covered_amount                     decimal(19,4),
    deductible_amount                  decimal(19,4),
    currency_code                      char(3),
    reason_text                        text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_claim_coverage_decision PRIMARY KEY (id),
    CONSTRAINT uq_claim_claim_coverage_decision_claim_id_coverage_id_1 UNIQUE (claim_id, coverage_id),
    CONSTRAINT ck_claim_claim_coverage_decision_1 CHECK (covered_amount IS NULL OR covered_amount >= 0),
    CONSTRAINT ck_claim_claim_coverage_decision_2 CHECK (deductible_amount IS NULL OR deductible_amount >= 0),
    CONSTRAINT ck_claim_claim_coverage_decision_3 CHECK (decision IN ('PENDING','COVERED','PARTIALLY_COVERED','NOT_COVERED','EXCLUDED','WAIVED'))
);

CREATE TABLE claim.claim_cost (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    claim_id                           uuid NOT NULL,
    cost_type                          varchar(40) NOT NULL,
    supplier_party_id                  uuid,
    description                        varchar(240),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    incurred_at                        date NOT NULL,
    invoice_reference                  varchar(100),
    recoverable                        boolean NOT NULL DEFAULT FALSE,
    status                             varchar(20) NOT NULL DEFAULT 'RECORDED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_claim_cost PRIMARY KEY (id),
    CONSTRAINT ck_claim_claim_cost_1 CHECK (amount >= 0),
    CONSTRAINT ck_claim_claim_cost_2 CHECK (status IN ('RECORDED','APPROVED','PAID','REVERSED'))
);

CREATE TABLE claim.third_party_claim (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    claim_id                           uuid NOT NULL,
    third_party_id                     uuid,
    claimant_name_snapshot             varchar(180),
    claimed_amount                     decimal(19,4),
    approved_amount                    decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    settlement_date                    date,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_third_party_claim PRIMARY KEY (id),
    CONSTRAINT ck_claim_third_party_claim_1 CHECK (claimed_amount IS NULL OR claimed_amount >= 0),
    CONSTRAINT ck_claim_third_party_claim_2 CHECK (approved_amount IS NULL OR approved_amount >= 0),
    CONSTRAINT ck_claim_third_party_claim_3 CHECK (status IN ('RECEIVED','UNDER_REVIEW','NEGOTIATION','SETTLED','DENIED','LITIGATION','CLOSED'))
);

CREATE TABLE claim.recovery_case (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    claim_id                           uuid NOT NULL,
    responsible_party_id               uuid,
    opened_at                          timestamptz NOT NULL,
    target_amount                      decimal(19,4) NOT NULL,
    recovered_amount                   decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    closed_at                          timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_recovery_case PRIMARY KEY (id),
    CONSTRAINT ck_claim_recovery_case_1 CHECK (target_amount >= 0),
    CONSTRAINT ck_claim_recovery_case_2 CHECK (recovered_amount >= 0),
    CONSTRAINT ck_claim_recovery_case_3 CHECK (recovered_amount <= target_amount),
    CONSTRAINT ck_claim_recovery_case_4 CHECK (status IN ('OPEN','NEGOTIATION','COLLECTION','LITIGATION','RECOVERED','CLOSED','WRITTEN_OFF'))
);

CREATE TABLE claim.roadside_assistance_case (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    case_number                        varchar(60) NOT NULL,
    incident_id                        uuid,
    contract_id                        uuid,
    vehicle_id                         uuid NOT NULL,
    assistance_type                    varchar(40) NOT NULL,
    requested_at                       timestamptz NOT NULL,
    dispatched_at                      timestamptz,
    completed_at                       timestamptz,
    provider_party_id                  uuid,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    cost_amount                        decimal(19,4),
    currency_code                      char(3),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_roadside_assistance_case PRIMARY KEY (id),
    CONSTRAINT uq_claim_roadside_assistance_case_case_number_1 UNIQUE (case_number),
    CONSTRAINT ck_claim_roadside_assistance_case_1 CHECK (completed_at IS NULL OR completed_at >= requested_at),
    CONSTRAINT ck_claim_roadside_assistance_case_2 CHECK (cost_amount IS NULL OR cost_amount >= 0),
    CONSTRAINT ck_claim_roadside_assistance_case_3 CHECK (status IN ('REQUESTED','DISPATCHED','ARRIVED','COMPLETED','CANCELLED','FAILED'))
);

CREATE TABLE maintenance.maintenance_plan (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    plan_code                          varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    vehicle_variant_id                 uuid,
    manufacturer                       boolean NOT NULL DEFAULT FALSE,
    valid_from                         date NOT NULL,
    valid_to                           date,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_maintenance_plan PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_maintenance_plan_plan_code_valid_from_1 UNIQUE (plan_code, valid_from),
    CONSTRAINT ck_maintenance_maintenance_plan_1 CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_maintenance_maintenance_plan_2 CHECK (status IN ('ACTIVE','INACTIVE','RETIRED'))
);

CREATE TABLE maintenance.maintenance_rule (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    maintenance_plan_id                uuid NOT NULL,
    rule_code                          varchar(50) NOT NULL,
    service_type                       varchar(40) NOT NULL,
    every_km                           decimal(12,1),
    every_days                         integer,
    whichever_first                    boolean NOT NULL DEFAULT TRUE,
    condition_json                     jsonb,
    priority                           smallint NOT NULL DEFAULT 100,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_maintenance_maintenance_rule PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_maintenance_rule_maintenance_plan__6159e176 UNIQUE (maintenance_plan_id, rule_code),
    CONSTRAINT ck_maintenance_maintenance_rule_1 CHECK (every_km IS NULL OR every_km > 0),
    CONSTRAINT ck_maintenance_maintenance_rule_2 CHECK (every_days IS NULL OR every_days > 0),
    CONSTRAINT ck_maintenance_maintenance_rule_3 CHECK (every_km IS NOT NULL OR every_days IS NOT NULL OR condition_json IS NOT NULL),
    CONSTRAINT ck_maintenance_maintenance_rule_4 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE maintenance.maintenance_due (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    maintenance_rule_id                uuid NOT NULL,
    due_odometer_km                    decimal(12,1),
    due_date                           date,
    calculated_at                      timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DUE',
    service_order_id                   uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_maintenance_due PRIMARY KEY (id),
    CONSTRAINT ck_maintenance_maintenance_due_1 CHECK (due_odometer_km IS NULL OR due_odometer_km >= 0),
    CONSTRAINT ck_maintenance_maintenance_due_2 CHECK (status IN ('UPCOMING','DUE','OVERDUE','SCHEDULED','COMPLETED','WAIVED'))
);

CREATE TABLE maintenance.vendor (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    vendor_code                        varchar(40) NOT NULL,
    vendor_type                        varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_vendor PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_vendor_vendor_code_1 UNIQUE (vendor_code),
    CONSTRAINT uq_maintenance_vendor_party_id_2 UNIQUE (party_id),
    CONSTRAINT ck_maintenance_vendor_1 CHECK (vendor_type IN ('WORKSHOP','PARTS','TOWING','CLEANING','INSPECTION','OTHER')),
    CONSTRAINT ck_maintenance_vendor_2 CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE'))
);

CREATE TABLE maintenance.workshop (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vendor_id                          uuid NOT NULL,
    branch_id                          uuid,
    name                               varchar(160) NOT NULL,
    address_id                         uuid,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_workshop PRIMARY KEY (id),
    CONSTRAINT ck_maintenance_workshop_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE maintenance.service_order (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    service_order_number               varchar(60) NOT NULL,
    vehicle_id                         uuid NOT NULL,
    workshop_id                        uuid,
    calendar_entry_id                  uuid,
    order_type                         varchar(30) NOT NULL,
    opened_at                          timestamptz NOT NULL,
    scheduled_start_at                 timestamptz,
    started_at                         timestamptz,
    completed_at                       timestamptz,
    odometer_open_km                   decimal(12,1),
    odometer_close_km                  decimal(12,1),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    estimated_amount                   decimal(19,4),
    actual_amount                      decimal(19,4),
    currency_code                      char(3),
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_service_order PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_service_order_service_order_number_1 UNIQUE (service_order_number),
    CONSTRAINT ck_maintenance_service_order_1 CHECK (completed_at IS NULL OR completed_at >= opened_at),
    CONSTRAINT ck_maintenance_service_order_2 CHECK (odometer_open_km IS NULL OR odometer_open_km >= 0),
    CONSTRAINT ck_maintenance_service_order_3 CHECK (odometer_close_km IS NULL OR odometer_close_km >= 0),
    CONSTRAINT ck_maintenance_service_order_4 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_maintenance_service_order_5 CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT ck_maintenance_service_order_6 CHECK (order_type IN ('PREVENTIVE','CORRECTIVE','RECALL','TIRE','BODYWORK','CLEANING','INSPECTION')),
    CONSTRAINT ck_maintenance_service_order_7 CHECK (status IN ('OPEN','SCHEDULED','IN_PROGRESS','AWAITING_PARTS','QUALITY_CHECK','COMPLETED','CANCELLED'))
);

CREATE TABLE maintenance.service_order_item (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    service_order_id                   uuid NOT NULL,
    line_number                        integer NOT NULL,
    service_type                       varchar(60) NOT NULL,
    description                        varchar(240),
    quantity                           decimal(19,6) NOT NULL DEFAULT 1,
    unit_amount                        decimal(19,4) NOT NULL DEFAULT 0,
    labor_hours                        decimal(10,2),
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_service_order_item PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_service_order_item_service_order_i_6de424be UNIQUE (service_order_id, line_number),
    CONSTRAINT ck_maintenance_service_order_item_1 CHECK (quantity > 0),
    CONSTRAINT ck_maintenance_service_order_item_2 CHECK (unit_amount >= 0),
    CONSTRAINT ck_maintenance_service_order_item_3 CHECK (labor_hours IS NULL OR labor_hours >= 0),
    CONSTRAINT ck_maintenance_service_order_item_4 CHECK (status IN ('PLANNED','APPROVED','IN_PROGRESS','COMPLETED','CANCELLED'))
);

CREATE TABLE maintenance.part (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    part_code                          varchar(60) NOT NULL,
    manufacturer_code                  varchar(80),
    name                               varchar(160) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_maintenance_part PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_part_part_code_1 UNIQUE (part_code),
    CONSTRAINT ck_maintenance_part_1 CHECK (status IN ('ACTIVE','INACTIVE','DISCONTINUED'))
);

CREATE TABLE maintenance.service_order_part (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    service_order_item_id              uuid NOT NULL,
    part_id                            uuid NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    serial_number                      varchar(100),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_maintenance_service_order_part PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_service_order_part_service_order_i_13b18f26 UNIQUE (service_order_item_id, part_id, serial_number),
    CONSTRAINT ck_maintenance_service_order_part_1 CHECK (quantity > 0),
    CONSTRAINT ck_maintenance_service_order_part_2 CHECK (unit_amount >= 0)
);

CREATE TABLE maintenance.recall_campaign (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    manufacturer_code                  varchar(60) NOT NULL,
    campaign_code                      varchar(80) NOT NULL,
    name                               varchar(180) NOT NULL,
    announced_at                       date,
    severity                           varchar(20) NOT NULL,
    instructions                       text,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_recall_campaign PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_recall_campaign_manufacturer_code__cb32fd47 UNIQUE (manufacturer_code, campaign_code),
    CONSTRAINT ck_maintenance_recall_campaign_1 CHECK (severity IN ('ADVISORY','IMPORTANT','SAFETY_CRITICAL')),
    CONSTRAINT ck_maintenance_recall_campaign_2 CHECK (status IN ('ACTIVE','CLOSED','CANCELLED'))
);

CREATE TABLE maintenance.vehicle_recall (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    recall_campaign_id                 uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    identified_at                      timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    service_order_id                   uuid,
    completed_at                       timestamptz,
    completion_reference               varchar(120),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_vehicle_recall PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_vehicle_recall_recall_campaign_id__202e0ec3 UNIQUE (recall_campaign_id, vehicle_id),
    CONSTRAINT ck_maintenance_vehicle_recall_1 CHECK (status IN ('OPEN','SCHEDULED','COMPLETED','NOT_APPLICABLE','DECLINED'))
);

CREATE TABLE maintenance.tire (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    serial_number                      varchar(100) NOT NULL,
    brand                              varchar(80),
    model                              varchar(100),
    size_code                          varchar(40),
    purchased_at                       date,
    purchase_amount                    decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'IN_STOCK',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_tire PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_tire_serial_number_1 UNIQUE (serial_number),
    CONSTRAINT ck_maintenance_tire_1 CHECK (purchase_amount IS NULL OR purchase_amount >= 0),
    CONSTRAINT ck_maintenance_tire_2 CHECK (status IN ('IN_STOCK','INSTALLED','REPAIR','DISCARDED','LOST'))
);

CREATE TABLE maintenance.tire_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    tire_id                            uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    position_code                      varchar(30) NOT NULL,
    installed_at                       timestamptz NOT NULL,
    removed_at                         timestamptz,
    installed_odometer_km              decimal(12,1),
    removed_odometer_km                decimal(12,1),
    removal_reason                     varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_maintenance_tire_assignment PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_tire_assignment_tire_id_installed_at_1 UNIQUE (tire_id, installed_at),
    CONSTRAINT ck_maintenance_tire_assignment_1 CHECK (removed_at IS NULL OR removed_at > installed_at),
    CONSTRAINT ck_maintenance_tire_assignment_2 CHECK (installed_odometer_km IS NULL OR installed_odometer_km >= 0),
    CONSTRAINT ck_maintenance_tire_assignment_3 CHECK (removed_odometer_km IS NULL OR removed_odometer_km >= 0)
);

CREATE TABLE maintenance.downtime (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    service_order_id                   uuid,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    downtime_type                      varchar(30) NOT NULL,
    reason_code                        varchar(60),
    calendar_entry_id                  uuid,
    estimated_cost_amount              decimal(19,4),
    currency_code                      char(3),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_downtime PRIMARY KEY (id),
    CONSTRAINT ck_maintenance_downtime_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_maintenance_downtime_2 CHECK (estimated_cost_amount IS NULL OR estimated_cost_amount >= 0),
    CONSTRAINT ck_maintenance_downtime_3 CHECK (downtime_type IN ('MAINTENANCE','RECALL','DAMAGE','DOCUMENTATION','CLEANING','OTHER'))
);

CREATE TABLE telematics.provider (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    provider_code                      varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    configuration_json                 jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_provider PRIMARY KEY (id),
    CONSTRAINT uq_telematics_provider_provider_code_1 UNIQUE (provider_code),
    CONSTRAINT ck_telematics_provider_1 CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE'))
);

CREATE TABLE telematics.device (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    provider_id                        uuid NOT NULL,
    device_serial                      varchar(120) NOT NULL,
    device_type                        varchar(30) NOT NULL,
    firmware_version                   varchar(60),
    activated_at                       timestamptz,
    last_seen_at                       timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_device PRIMARY KEY (id),
    CONSTRAINT uq_telematics_device_provider_id_device_serial_1 UNIQUE (provider_id, device_serial),
    CONSTRAINT ck_telematics_device_1 CHECK (device_type IN ('OEM','OBD','TRACKER','SMART_KEY','OTHER')),
    CONSTRAINT ck_telematics_device_2 CHECK (status IN ('ACTIVE','OFFLINE','SUSPENDED','RETIRED','LOST'))
);

CREATE TABLE telematics.vehicle_device_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    device_id                          uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    assignment_type                    varchar(30) NOT NULL,
    installed_by                       uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_vehicle_device_assignment PRIMARY KEY (id),
    CONSTRAINT uq_telematics_vehicle_device_assignment_device_id_f95fcb22 UNIQUE (device_id, start_at),
    CONSTRAINT ck_telematics_vehicle_device_assignment_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_telematics_vehicle_device_assignment_2 CHECK (assignment_type IN ('PRIMARY_TELEMATICS','DIGITAL_KEY','AUXILIARY'))
);

CREATE TABLE telematics.device_health_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    device_id                          uuid NOT NULL,
    event_type                         varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    details_json                       jsonb,
    resolved_at                        timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_device_health_event PRIMARY KEY (id),
    CONSTRAINT ck_telematics_device_health_event_1 CHECK (severity IN ('INFO','WARNING','ERROR','CRITICAL')),
    CONSTRAINT ck_telematics_device_health_event_2 CHECK (resolved_at IS NULL OR resolved_at >= occurred_at)
);

CREATE TABLE telematics.telemetry_event_index (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    device_id                          uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    provider_event_id                  varchar(180),
    sequence_number                    bigint,
    event_type                         varchar(40) NOT NULL,
    event_time                         timestamptz NOT NULL,
    received_at                        timestamptz NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    odometer_km                        decimal(12,1),
    fuel_level_percent                 decimal(5,2),
    speed_kph                          decimal(8,2),
    object_key                         varchar(500),
    payload_version                    integer NOT NULL DEFAULT 1,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_telemetry_event_index PRIMARY KEY (id),
    CONSTRAINT uq_telematics_telemetry_event_index_device_id_pro_51faf317 UNIQUE (device_id, provider_event_id),
    CONSTRAINT uq_telematics_telemetry_event_index_device_id_seq_585ee7dd UNIQUE (device_id, sequence_number),
    CONSTRAINT ck_telematics_telemetry_event_index_1 CHECK (sequence_number IS NULL OR sequence_number >= 0),
    CONSTRAINT ck_telematics_telemetry_event_index_2 CHECK (odometer_km IS NULL OR odometer_km >= 0),
    CONSTRAINT ck_telematics_telemetry_event_index_3 CHECK (fuel_level_percent IS NULL OR fuel_level_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_telematics_telemetry_event_index_4 CHECK (speed_kph IS NULL OR speed_kph >= 0)
);

CREATE TABLE telematics.trip_summary (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    device_id                          uuid,
    contract_id                        uuid,
    trip_start_at                      timestamptz NOT NULL,
    trip_end_at                        timestamptz NOT NULL,
    start_latitude                     decimal(10,7),
    start_longitude                    decimal(10,7),
    end_latitude                       decimal(10,7),
    end_longitude                      decimal(10,7),
    distance_km                        decimal(12,3) NOT NULL,
    duration_seconds                   integer NOT NULL,
    maximum_speed_kph                  decimal(8,2),
    harsh_event_count                  integer NOT NULL DEFAULT 0,
    calculation_version                varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_trip_summary PRIMARY KEY (id),
    CONSTRAINT ck_telematics_trip_summary_1 CHECK (trip_end_at > trip_start_at),
    CONSTRAINT ck_telematics_trip_summary_2 CHECK (distance_km >= 0),
    CONSTRAINT ck_telematics_trip_summary_3 CHECK (duration_seconds >= 0),
    CONSTRAINT ck_telematics_trip_summary_4 CHECK (maximum_speed_kph IS NULL OR maximum_speed_kph >= 0),
    CONSTRAINT ck_telematics_trip_summary_5 CHECK (harsh_event_count >= 0)
);

CREATE TABLE telematics.driving_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    device_id                          uuid,
    contract_id                        uuid,
    trip_summary_id                    uuid,
    event_type                         varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    measured_value                     decimal(19,6),
    threshold_value                    decimal(19,6),
    rule_version                       varchar(60),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_driving_event PRIMARY KEY (id),
    CONSTRAINT ck_telematics_driving_event_1 CHECK (event_type IN ('HARSH_BRAKE','HARSH_ACCELERATION','HARSH_CORNER','SPEEDING','IMPACT','TOWING','GEOFENCE','IDLE','OTHER')),
    CONSTRAINT ck_telematics_driving_event_2 CHECK (severity IN ('INFO','LOW','MEDIUM','HIGH','CRITICAL'))
);

CREATE TABLE telematics.geofence (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    geofence_code                      varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    geofence_type                      varchar(30) NOT NULL,
    geometry_json                      jsonb NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_geofence PRIMARY KEY (id),
    CONSTRAINT uq_telematics_geofence_geofence_code_1 UNIQUE (geofence_code),
    CONSTRAINT ck_telematics_geofence_1 CHECK (geofence_type IN ('BRANCH','COUNTRY','RESTRICTED_AREA','SERVICE_AREA','CUSTOM')),
    CONSTRAINT ck_telematics_geofence_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE telematics.geofence_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    device_id                          uuid,
    geofence_id                        uuid NOT NULL,
    contract_id                        uuid,
    event_type                         varchar(20) NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    provider_event_id                  varchar(180),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_geofence_event PRIMARY KEY (id),
    CONSTRAINT uq_telematics_geofence_event_device_id_provider_event_id_1 UNIQUE (device_id, provider_event_id),
    CONSTRAINT ck_telematics_geofence_event_1 CHECK (event_type IN ('ENTER','EXIT','DWELL'))
);

CREATE TABLE telematics.vehicle_command (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    device_id                          uuid,
    contract_id                        uuid,
    command_type                       varchar(30) NOT NULL,
    requested_by                       uuid,
    reason_code                        varchar(60),
    requested_at                       timestamptz NOT NULL,
    expires_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_vehicle_command PRIMARY KEY (id),
    CONSTRAINT uq_telematics_vehicle_command_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_telematics_vehicle_command_1 CHECK (command_type IN ('LOCK','UNLOCK','IMMOBILIZE','MOBILIZE','HORN','LIGHTS','LOCATE')),
    CONSTRAINT ck_telematics_vehicle_command_2 CHECK (status IN ('REQUESTED','SENT','ACKNOWLEDGED','SUCCEEDED','FAILED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_telematics_vehicle_command_3 CHECK (expires_at IS NULL OR expires_at > requested_at)
);

CREATE TABLE telematics.command_result (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_command_id                 uuid NOT NULL,
    provider_reference                 varchar(160),
    acknowledged_at                    timestamptz,
    executed_at                        timestamptz,
    result_code                        varchar(60) NOT NULL,
    result_message                     text,
    raw_response                       jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_telematics_command_result PRIMARY KEY (id),
    CONSTRAINT uq_telematics_command_result_vehicle_command_id_1 UNIQUE (vehicle_command_id)
);

CREATE TABLE telematics.telemetry_rule_version (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rule_code                          varchar(60) NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    rule_type                          varchar(40) NOT NULL,
    rule_json                          jsonb NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_telemetry_rule_version PRIMARY KEY (id),
    CONSTRAINT uq_telematics_telemetry_rule_version_rule_code_ve_dfbc988d UNIQUE (rule_code, version_number),
    CONSTRAINT ck_telematics_telemetry_rule_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_telematics_telemetry_rule_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE loyalty.loyalty_account (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    account_number                     varchar(60) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    enrolled_at                        timestamptz NOT NULL,
    current_tier_id                    uuid,
    balance_projection                 decimal(19,4) NOT NULL DEFAULT 0,
    balance_updated_at                 timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_loyalty_account PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_loyalty_account_party_id_1 UNIQUE (party_id),
    CONSTRAINT uq_loyalty_loyalty_account_account_number_2 UNIQUE (account_number),
    CONSTRAINT ck_loyalty_loyalty_account_1 CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED'))
);

CREATE TABLE loyalty.loyalty_tier (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    tier_code                          varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    rank_order                         smallint NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    benefit_summary                    jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_loyalty_loyalty_tier PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_loyalty_tier_tier_code_1 UNIQUE (tier_code),
    CONSTRAINT uq_loyalty_loyalty_tier_rank_order_2 UNIQUE (rank_order),
    CONSTRAINT ck_loyalty_loyalty_tier_1 CHECK (rank_order > 0),
    CONSTRAINT ck_loyalty_loyalty_tier_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE loyalty.tier_rule_version (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    loyalty_tier_id                    uuid NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    qualification_rule_json            jsonb NOT NULL,
    retention_rule_json                jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_tier_rule_version PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_tier_rule_version_loyalty_tier_id_vers_e0d1732a UNIQUE (loyalty_tier_id, version_number),
    CONSTRAINT ck_loyalty_tier_rule_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_loyalty_tier_rule_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE loyalty.tier_history (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    loyalty_account_id                 uuid NOT NULL,
    loyalty_tier_id                    uuid NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    reason_code                        varchar(60),
    rule_version_id                    uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_loyalty_tier_history PRIMARY KEY (id),
    CONSTRAINT ck_loyalty_tier_history_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE loyalty.earning_rule (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rule_code                          varchar(60) NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    condition_json                     jsonb NOT NULL,
    calculation_json                   jsonb NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_earning_rule PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_earning_rule_rule_code_version_number_1 UNIQUE (rule_code, version_number),
    CONSTRAINT ck_loyalty_earning_rule_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_loyalty_earning_rule_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE loyalty.redemption_rule (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    rule_code                          varchar(60) NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    condition_json                     jsonb NOT NULL,
    conversion_json                    jsonb NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_redemption_rule PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_redemption_rule_rule_code_version_number_1 UNIQUE (rule_code, version_number),
    CONSTRAINT ck_loyalty_redemption_rule_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_loyalty_redemption_rule_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE loyalty.points_ledger (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    loyalty_account_id                 uuid NOT NULL,
    entry_type                         varchar(30) NOT NULL,
    points                             decimal(19,4) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          uuid NOT NULL,
    source_correlation_id              varchar(160) NOT NULL,
    earning_rule_id                    uuid,
    redemption_rule_id                 uuid,
    available_at                       timestamptz NOT NULL,
    expires_at                         timestamptz,
    reversal_of_entry_id               uuid,
    occurred_at                        timestamptz NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_loyalty_points_ledger PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_points_ledger_loyalty_account_id_sourc_1c8160a0 UNIQUE (loyalty_account_id, source_correlation_id),
    CONSTRAINT ck_loyalty_points_ledger_1 CHECK (points <> 0),
    CONSTRAINT ck_loyalty_points_ledger_2 CHECK (expires_at IS NULL OR expires_at > available_at),
    CONSTRAINT ck_loyalty_points_ledger_3 CHECK (reversal_of_entry_id IS NULL OR reversal_of_entry_id <> id),
    CONSTRAINT ck_loyalty_points_ledger_4 CHECK (entry_type IN ('EARN','REDEEM','EXPIRE','ADJUSTMENT','REVERSAL','TRANSFER_IN','TRANSFER_OUT'))
);

CREATE TABLE loyalty.points_lot (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    loyalty_account_id                 uuid NOT NULL,
    origin_ledger_entry_id             uuid NOT NULL,
    original_points                    decimal(19,4) NOT NULL,
    remaining_points                   decimal(19,4) NOT NULL,
    available_at                       timestamptz NOT NULL,
    expires_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_points_lot PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_points_lot_origin_ledger_entry_id_1 UNIQUE (origin_ledger_entry_id),
    CONSTRAINT ck_loyalty_points_lot_1 CHECK (original_points > 0),
    CONSTRAINT ck_loyalty_points_lot_2 CHECK (remaining_points >= 0),
    CONSTRAINT ck_loyalty_points_lot_3 CHECK (remaining_points <= original_points),
    CONSTRAINT ck_loyalty_points_lot_4 CHECK (expires_at IS NULL OR expires_at > available_at),
    CONSTRAINT ck_loyalty_points_lot_5 CHECK (status IN ('PENDING','AVAILABLE','CONSUMED','EXPIRED','REVERSED'))
);

CREATE TABLE loyalty.redemption (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    loyalty_account_id                 uuid NOT NULL,
    reservation_id                     uuid,
    contract_id                        uuid,
    points_requested                   decimal(19,4) NOT NULL,
    monetary_value                     decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    requested_at                       timestamptz NOT NULL,
    completed_at                       timestamptz,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_redemption PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_redemption_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_loyalty_redemption_1 CHECK (points_requested > 0),
    CONSTRAINT ck_loyalty_redemption_2 CHECK (monetary_value IS NULL OR monetary_value >= 0),
    CONSTRAINT ck_loyalty_redemption_3 CHECK (status IN ('REQUESTED','RESERVED','COMPLETED','FAILED','CANCELLED','REVERSED'))
);

CREATE TABLE loyalty.redemption_allocation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    redemption_id                      uuid NOT NULL,
    points_lot_id                      uuid NOT NULL,
    points_consumed                    decimal(19,4) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_loyalty_redemption_allocation PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_redemption_allocation_redemption_id_po_22aa0170 UNIQUE (redemption_id, points_lot_id),
    CONSTRAINT ck_loyalty_redemption_allocation_1 CHECK (points_consumed > 0)
);

CREATE TABLE loyalty.benefit (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    benefit_code                       varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    benefit_type                       varchar(30) NOT NULL,
    configuration_json                 jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_loyalty_benefit PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_benefit_benefit_code_1 UNIQUE (benefit_code),
    CONSTRAINT ck_loyalty_benefit_1 CHECK (benefit_type IN ('DISCOUNT','UPGRADE','FREE_DAY','ADDITIONAL_DRIVER','PRIORITY','OTHER')),
    CONSTRAINT ck_loyalty_benefit_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE loyalty.benefit_entitlement (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    loyalty_account_id                 uuid NOT NULL,
    benefit_id                         uuid NOT NULL,
    granted_at                         timestamptz NOT NULL,
    expires_at                         timestamptz,
    quantity_granted                   decimal(19,4) NOT NULL DEFAULT 1,
    quantity_remaining                 decimal(19,4) NOT NULL DEFAULT 1,
    source_type                        varchar(40),
    source_id                          uuid,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_benefit_entitlement PRIMARY KEY (id),
    CONSTRAINT ck_loyalty_benefit_entitlement_1 CHECK (quantity_granted > 0),
    CONSTRAINT ck_loyalty_benefit_entitlement_2 CHECK (quantity_remaining >= 0),
    CONSTRAINT ck_loyalty_benefit_entitlement_3 CHECK (quantity_remaining <= quantity_granted),
    CONSTRAINT ck_loyalty_benefit_entitlement_4 CHECK (expires_at IS NULL OR expires_at > granted_at),
    CONSTRAINT ck_loyalty_benefit_entitlement_5 CHECK (status IN ('ACTIVE','CONSUMED','EXPIRED','REVOKED'))
);

CREATE TABLE loyalty.benefit_usage (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    benefit_entitlement_id             uuid NOT NULL,
    reservation_id                     uuid,
    contract_id                        uuid,
    quantity_used                      decimal(19,4) NOT NULL,
    used_at                            timestamptz NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'APPLIED',
    reversal_of_usage_id               uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_loyalty_benefit_usage PRIMARY KEY (id),
    CONSTRAINT ck_loyalty_benefit_usage_1 CHECK (quantity_used > 0),
    CONSTRAINT ck_loyalty_benefit_usage_2 CHECK (reversal_of_usage_id IS NULL OR reversal_of_usage_id <> id),
    CONSTRAINT ck_loyalty_benefit_usage_3 CHECK (status IN ('APPLIED','REVERSED'))
);

CREATE TABLE loyalty.points_transfer (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    from_account_id                    uuid NOT NULL,
    to_account_id                      uuid NOT NULL,
    points                             decimal(19,4) NOT NULL,
    requested_at                       timestamptz NOT NULL,
    completed_at                       timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    out_ledger_entry_id                uuid,
    in_ledger_entry_id                 uuid,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_points_transfer PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_points_transfer_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_loyalty_points_transfer_1 CHECK (from_account_id <> to_account_id),
    CONSTRAINT ck_loyalty_points_transfer_2 CHECK (points > 0),
    CONSTRAINT ck_loyalty_points_transfer_3 CHECK (status IN ('REQUESTED','COMPLETED','FAILED','CANCELLED','REVERSED'))
);

CREATE TABLE fleet_mgmt.fleet_service_contract (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_number                    varchar(60) NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    customer_account_id                uuid NOT NULL,
    corporate_agreement_id             uuid,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    billing_mode                       varchar(30) NOT NULL,
    currency_code                      char(3) NOT NULL,
    service_scope_json                 jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_fleet_service_contract PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_fleet_service_contract_legal_entity_94056b31 UNIQUE (legal_entity_id, contract_number),
    CONSTRAINT ck_fleet_mgmt_fleet_service_contract_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_fleet_mgmt_fleet_service_contract_2 CHECK (billing_mode IN ('FIXED_MONTHLY','PER_VEHICLE','PER_KM','HYBRID')),
    CONSTRAINT ck_fleet_mgmt_fleet_service_contract_3 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
);

CREATE TABLE fleet_mgmt.fleet_service_level (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_service_contract_id          uuid NOT NULL,
    service_code                       varchar(50) NOT NULL,
    target_value                       decimal(19,6),
    unit_code                          varchar(20),
    measurement_window                 varchar(30),
    penalty_rule_json                  jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_mgmt_fleet_service_level PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_fleet_service_level_fleet_service_c_c0079b34 UNIQUE (fleet_service_contract_id, service_code),
    CONSTRAINT ck_fleet_mgmt_fleet_service_level_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE fleet_mgmt.managed_vehicle_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_service_contract_id          uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    assigned_driver_profile_id         uuid,
    cost_center_id                     uuid,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    assignment_status                  varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_managed_vehicle_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_managed_vehicle_assignment_fleet_se_39f0436d UNIQUE (fleet_service_contract_id, vehicle_id, start_at),
    CONSTRAINT ck_fleet_mgmt_managed_vehicle_assignment_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_fleet_mgmt_managed_vehicle_assignment_2 CHECK (assignment_status IN ('PLANNED','ACTIVE','SUSPENDED','COMPLETED','CANCELLED'))
);

CREATE TABLE fleet_mgmt.mileage_commitment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_service_contract_id          uuid NOT NULL,
    vehicle_id                         uuid,
    period_start                       date NOT NULL,
    period_end                         date NOT NULL,
    included_km                        decimal(12,2) NOT NULL,
    excess_km_amount                   decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    actual_km                          decimal(12,2),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_mileage_commitment PRIMARY KEY (id),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_1 CHECK (period_end >= period_start),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_2 CHECK (included_km >= 0),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_3 CHECK (excess_km_amount >= 0),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_4 CHECK (actual_km IS NULL OR actual_km >= 0)
);

CREATE TABLE fleet_mgmt.telemetry_package (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_service_contract_id          uuid NOT NULL,
    package_code                       varchar(50) NOT NULL,
    features_json                      jsonb NOT NULL,
    monthly_amount                     decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_mgmt_telemetry_package PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_telemetry_package_fleet_service_con_51e8a4d2 UNIQUE (fleet_service_contract_id, package_code),
    CONSTRAINT ck_fleet_mgmt_telemetry_package_1 CHECK (monthly_amount >= 0),
    CONSTRAINT ck_fleet_mgmt_telemetry_package_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE fleet_mgmt.replacement_entitlement (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_service_contract_id          uuid NOT NULL,
    vehicle_group_id                   uuid,
    trigger_type                       varchar(40) NOT NULL,
    trigger_threshold                  decimal(19,6),
    maximum_days                       integer,
    terms_json                         jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_mgmt_replacement_entitlement PRIMARY KEY (id),
    CONSTRAINT ck_fleet_mgmt_replacement_entitlement_1 CHECK (maximum_days IS NULL OR maximum_days > 0),
    CONSTRAINT ck_fleet_mgmt_replacement_entitlement_2 CHECK (trigger_type IN ('MAINTENANCE','ACCIDENT','DOWNTIME','MILEAGE','MANUAL')),
    CONSTRAINT ck_fleet_mgmt_replacement_entitlement_3 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE fleet_mgmt.fleet_service_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    fleet_service_contract_id          uuid NOT NULL,
    vehicle_id                         uuid,
    event_type                         varchar(40) NOT NULL,
    source_type                        varchar(40),
    source_id                          uuid,
    occurred_at                        timestamptz NOT NULL,
    details_json                       jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fleet_mgmt_fleet_service_event PRIMARY KEY (id)
);

CREATE TABLE fleet_mgmt.subscription_plan (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    plan_code                          varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    vehicle_group_id                   uuid NOT NULL,
    minimum_months                     integer NOT NULL,
    included_km_per_month              decimal(12,2) NOT NULL,
    monthly_amount                     decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    terms_json                         jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_subscription_plan PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_subscription_plan_plan_code_1 UNIQUE (plan_code),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_1 CHECK (minimum_months > 0),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_2 CHECK (included_km_per_month >= 0),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_3 CHECK (monthly_amount >= 0),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_4 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE fleet_mgmt.subscription_contract (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    contract_number                    varchar(60) NOT NULL,
    subscription_plan_id               uuid NOT NULL,
    customer_account_id                uuid NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    start_at                           timestamptz NOT NULL,
    minimum_end_at                     timestamptz NOT NULL,
    end_at                             timestamptz,
    billing_day                        smallint NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    currency_code                      char(3) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_subscription_contract PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_subscription_contract_legal_entity__79a78c69 UNIQUE (legal_entity_id, contract_number),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_1 CHECK (minimum_end_at > start_at),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_2 CHECK (end_at IS NULL OR end_at >= minimum_end_at),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_3 CHECK (billing_day BETWEEN 1 AND 28),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_4 CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CANCELLED','COMPLETED','DEFAULTED'))
);

CREATE TABLE fleet_mgmt.subscription_vehicle_assignment (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    subscription_contract_id           uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    calendar_entry_id                  uuid,
    start_at                           timestamptz NOT NULL,
    end_at                             timestamptz,
    assignment_reason                  varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_subscription_vehicle_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_subscription_vehicle_assignment_sub_5dde8dad UNIQUE (subscription_contract_id, vehicle_id, start_at),
    CONSTRAINT ck_fleet_mgmt_subscription_vehicle_assignment_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_fleet_mgmt_subscription_vehicle_assignment_2 CHECK (assignment_reason IN ('INITIAL','REPLACEMENT','UPGRADE','DOWNGRADE')),
    CONSTRAINT ck_fleet_mgmt_subscription_vehicle_assignment_3 CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','CANCELLED'))
);

CREATE TABLE used_car.disposal_candidate (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    vehicle_id                         uuid NOT NULL,
    identified_at                      timestamptz NOT NULL,
    reason_code                        varchar(40) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    target_sale_date                   date,
    status                             varchar(30) NOT NULL DEFAULT 'IDENTIFIED',
    approved_at                        timestamptz,
    approved_by                        uuid,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_disposal_candidate PRIMARY KEY (id),
    CONSTRAINT uq_used_car_disposal_candidate_vehicle_id_1 UNIQUE (vehicle_id),
    CONSTRAINT ck_used_car_disposal_candidate_1 CHECK (reason_code IN ('AGE','MILEAGE','MAINTENANCE_COST','RESIDUAL_VALUE','FLEET_REBALANCING','ACCIDENT_HISTORY','MODEL_STRATEGY','OTHER')),
    CONSTRAINT ck_used_car_disposal_candidate_2 CHECK (status IN ('IDENTIFIED','UNDER_REVIEW','APPROVED','REJECTED','PREPARING','LISTED','SOLD','CANCELLED'))
);

CREATE TABLE used_car.vehicle_valuation (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    disposal_candidate_id              uuid NOT NULL,
    valuation_type                     varchar(30) NOT NULL,
    valued_at                          timestamptz NOT NULL,
    market_value                       decimal(19,4) NOT NULL,
    minimum_sale_value                 decimal(19,4),
    expected_refurbishment_cost        decimal(19,4),
    currency_code                      char(3) NOT NULL,
    valuation_source                   varchar(60),
    model_version                      varchar(60),
    details_json                       jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_used_car_vehicle_valuation PRIMARY KEY (id),
    CONSTRAINT ck_used_car_vehicle_valuation_1 CHECK (market_value >= 0),
    CONSTRAINT ck_used_car_vehicle_valuation_2 CHECK (minimum_sale_value IS NULL OR minimum_sale_value >= 0),
    CONSTRAINT ck_used_car_vehicle_valuation_3 CHECK (expected_refurbishment_cost IS NULL OR expected_refurbishment_cost >= 0),
    CONSTRAINT ck_used_car_vehicle_valuation_4 CHECK (valuation_type IN ('MARKET','TRADE','AUCTION','INTERNAL','APPRAISAL'))
);

CREATE TABLE used_car.refurbishment_order (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    disposal_candidate_id              uuid NOT NULL,
    service_order_id                   uuid,
    opened_at                          timestamptz NOT NULL,
    target_completion_at               timestamptz,
    completed_at                       timestamptz,
    estimated_amount                   decimal(19,4),
    actual_amount                      decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_refurbishment_order PRIMARY KEY (id),
    CONSTRAINT ck_used_car_refurbishment_order_1 CHECK (completed_at IS NULL OR completed_at >= opened_at),
    CONSTRAINT ck_used_car_refurbishment_order_2 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_order_3 CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_order_4 CHECK (status IN ('OPEN','APPROVED','IN_PROGRESS','COMPLETED','CANCELLED'))
);

CREATE TABLE used_car.refurbishment_item (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    refurbishment_order_id             uuid NOT NULL,
    line_number                        integer NOT NULL,
    item_type                          varchar(40) NOT NULL,
    description                        varchar(240),
    estimated_amount                   decimal(19,4),
    actual_amount                      decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_refurbishment_item PRIMARY KEY (id),
    CONSTRAINT uq_used_car_refurbishment_item_refurbishment_orde_45478fc0 UNIQUE (refurbishment_order_id, line_number),
    CONSTRAINT ck_used_car_refurbishment_item_1 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_item_2 CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_item_3 CHECK (status IN ('PLANNED','APPROVED','COMPLETED','CANCELLED'))
);

CREATE TABLE used_car.sale_channel (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    channel_code                       varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    channel_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    configuration_json                 jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_used_car_sale_channel PRIMARY KEY (id),
    CONSTRAINT uq_used_car_sale_channel_channel_code_1 UNIQUE (channel_code),
    CONSTRAINT ck_used_car_sale_channel_1 CHECK (channel_type IN ('OWN_STORE','ONLINE','AUCTION','WHOLESALE','PARTNER')),
    CONSTRAINT ck_used_car_sale_channel_2 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE used_car.listing (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    disposal_candidate_id              uuid NOT NULL,
    sale_channel_id                    uuid NOT NULL,
    listing_reference                  varchar(100) NOT NULL,
    listed_at                          timestamptz NOT NULL,
    expires_at                         timestamptz,
    asking_price                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    odometer_km                        decimal(12,1) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    description                        text,
    media_manifest                     jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_listing PRIMARY KEY (id),
    CONSTRAINT uq_used_car_listing_sale_channel_id_listing_reference_1 UNIQUE (sale_channel_id, listing_reference),
    CONSTRAINT ck_used_car_listing_1 CHECK (asking_price >= 0),
    CONSTRAINT ck_used_car_listing_2 CHECK (odometer_km >= 0),
    CONSTRAINT ck_used_car_listing_3 CHECK (expires_at IS NULL OR expires_at > listed_at),
    CONSTRAINT ck_used_car_listing_4 CHECK (status IN ('DRAFT','ACTIVE','RESERVED','SOLD','EXPIRED','WITHDRAWN'))
);

CREATE TABLE used_car.lead (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    listing_id                         uuid,
    party_id                           uuid,
    source_channel                     varchar(40),
    created_at_source                  timestamptz,
    contact_snapshot                   jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'NEW',
    assigned_to                        uuid,
    next_action_at                     timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_lead PRIMARY KEY (id),
    CONSTRAINT ck_used_car_lead_1 CHECK (status IN ('NEW','CONTACTED','QUALIFIED','TEST_DRIVE','NEGOTIATION','WON','LOST','DUPLICATE'))
);

CREATE TABLE used_car.test_drive (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    lead_id                            uuid,
    listing_id                         uuid NOT NULL,
    driver_profile_id                  uuid NOT NULL,
    scheduled_start_at                 timestamptz NOT NULL,
    scheduled_end_at                   timestamptz NOT NULL,
    actual_start_at                    timestamptz,
    actual_end_at                      timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_test_drive PRIMARY KEY (id),
    CONSTRAINT ck_used_car_test_drive_1 CHECK (scheduled_end_at > scheduled_start_at),
    CONSTRAINT ck_used_car_test_drive_2 CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at),
    CONSTRAINT ck_used_car_test_drive_3 CHECK (status IN ('SCHEDULED','CHECKED_IN','COMPLETED','NO_SHOW','CANCELLED'))
);

CREATE TABLE used_car.sale_order (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    sale_order_number                  varchar(60) NOT NULL,
    legal_entity_id                    uuid NOT NULL,
    buyer_party_id                     uuid NOT NULL,
    sale_channel_id                    uuid NOT NULL,
    order_date                         date NOT NULL,
    currency_code                      char(3) NOT NULL,
    subtotal_amount                    decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_sale_order PRIMARY KEY (id),
    CONSTRAINT uq_used_car_sale_order_legal_entity_id_sale_order_number_1 UNIQUE (legal_entity_id, sale_order_number),
    CONSTRAINT ck_used_car_sale_order_1 CHECK (subtotal_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_4 CHECK (total_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_5 CHECK (status IN ('DRAFT','RESERVED','SIGNED','PAID','DELIVERED','CANCELLED'))
);

CREATE TABLE used_car.sale_order_vehicle (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    sale_order_id                      uuid NOT NULL,
    disposal_candidate_id              uuid NOT NULL,
    vehicle_id                         uuid NOT NULL,
    listing_id                         uuid,
    sale_price                         decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_used_car_sale_order_vehicle PRIMARY KEY (id),
    CONSTRAINT uq_used_car_sale_order_vehicle_sale_order_id_vehicle_id_1 UNIQUE (sale_order_id, vehicle_id),
    CONSTRAINT uq_used_car_sale_order_vehicle_vehicle_id_2 UNIQUE (vehicle_id),
    CONSTRAINT ck_used_car_sale_order_vehicle_1 CHECK (sale_price >= 0),
    CONSTRAINT ck_used_car_sale_order_vehicle_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_vehicle_3 CHECK (tax_amount >= 0)
);

CREATE TABLE used_car.vehicle_transfer (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    sale_order_vehicle_id              uuid NOT NULL,
    seller_party_id                    uuid NOT NULL,
    buyer_party_id                     uuid NOT NULL,
    requested_at                       timestamptz NOT NULL,
    completed_at                       timestamptz,
    authority_reference                varchar(160),
    document_object_key                varchar(500),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_vehicle_transfer PRIMARY KEY (id),
    CONSTRAINT uq_used_car_vehicle_transfer_sale_order_vehicle_id_1 UNIQUE (sale_order_vehicle_id),
    CONSTRAINT ck_used_car_vehicle_transfer_1 CHECK (status IN ('REQUESTED','DOCUMENTATION_PENDING','SUBMITTED','COMPLETED','REJECTED','CANCELLED'))
);

CREATE TABLE used_car.used_vehicle_warranty (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    sale_order_vehicle_id              uuid NOT NULL,
    warranty_code                      varchar(50) NOT NULL,
    starts_at                          date NOT NULL,
    ends_at                            date NOT NULL,
    coverage_json                      jsonb NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_used_vehicle_warranty PRIMARY KEY (id),
    CONSTRAINT uq_used_car_used_vehicle_warranty_sale_order_vehi_f93774c5 UNIQUE (sale_order_vehicle_id, warranty_code),
    CONSTRAINT ck_used_car_used_vehicle_warranty_1 CHECK (ends_at >= starts_at),
    CONSTRAINT ck_used_car_used_vehicle_warranty_2 CHECK (status IN ('ACTIVE','EXPIRED','CANCELLED','CLAIMED'))
);

CREATE TABLE used_car.sale_document (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    sale_order_id                      uuid NOT NULL,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             bytea,
    generated_at                       timestamptz NOT NULL,
    signed_at                          timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_used_car_sale_document PRIMARY KEY (id),
    CONSTRAINT ck_used_car_sale_document_1 CHECK (status IN ('ACTIVE','SUPERSEDED','VOID'))
);

CREATE TABLE privacy.privacy_notice (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    notice_code                        varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    country_code                       char(2) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_privacy_privacy_notice PRIMARY KEY (id),
    CONSTRAINT uq_privacy_privacy_notice_country_code_notice_code_1 UNIQUE (country_code, notice_code),
    CONSTRAINT ck_privacy_privacy_notice_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE privacy.privacy_notice_version (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    privacy_notice_id                  uuid NOT NULL,
    version_number                     integer NOT NULL,
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    language_code                      varchar(10) NOT NULL,
    content_object_key                 varchar(500) NOT NULL,
    content_hash                       varchar(64) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_privacy_notice_version PRIMARY KEY (id),
    CONSTRAINT uq_privacy_privacy_notice_version_privacy_notice__a2c98a00 UNIQUE (privacy_notice_id, version_number, language_code),
    CONSTRAINT ck_privacy_privacy_notice_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_privacy_privacy_notice_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
);

CREATE TABLE privacy.processing_purpose (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    purpose_code                       varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    description                        text,
    data_categories_json               jsonb,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_privacy_processing_purpose PRIMARY KEY (id),
    CONSTRAINT uq_privacy_processing_purpose_purpose_code_1 UNIQUE (purpose_code),
    CONSTRAINT ck_privacy_processing_purpose_1 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE privacy.legal_basis (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    purpose_id                         uuid NOT NULL,
    country_code                       char(2) NOT NULL,
    basis_type                         varchar(40) NOT NULL,
    legal_reference                    varchar(240),
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_privacy_legal_basis PRIMARY KEY (id),
    CONSTRAINT ck_privacy_legal_basis_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_privacy_legal_basis_2 CHECK (basis_type IN ('CONSENT','CONTRACT','LEGAL_OBLIGATION','LEGITIMATE_INTEREST','VITAL_INTEREST','PUBLIC_TASK','FRAUD_PREVENTION','CREDIT_PROTECTION','OTHER')),
    CONSTRAINT ck_privacy_legal_basis_3 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE privacy.consent_receipt (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid NOT NULL,
    privacy_notice_version_id          uuid NOT NULL,
    purpose_id                         uuid NOT NULL,
    decision                           varchar(20) NOT NULL,
    captured_at                        timestamptz NOT NULL,
    channel_id                         uuid,
    evidence_hash                      varchar(64) NOT NULL,
    ip_address_token                   varchar(100),
    device_reference                   varchar(160),
    withdrawn_at                       timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_privacy_consent_receipt PRIMARY KEY (id),
    CONSTRAINT ck_privacy_consent_receipt_1 CHECK (decision IN ('GRANTED','DENIED','WITHDRAWN')),
    CONSTRAINT ck_privacy_consent_receipt_2 CHECK (withdrawn_at IS NULL OR withdrawn_at >= captured_at)
);

CREATE TABLE privacy.data_subject_request (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid,
    request_type                       varchar(30) NOT NULL,
    received_at                        timestamptz NOT NULL,
    due_at                             timestamptz,
    channel_id                         uuid,
    identity_verification_id           uuid,
    status                             varchar(30) NOT NULL DEFAULT 'RECEIVED',
    assigned_to                        uuid,
    completed_at                       timestamptz,
    resolution_summary                 text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_data_subject_request PRIMARY KEY (id),
    CONSTRAINT ck_privacy_data_subject_request_1 CHECK (request_type IN ('ACCESS','CORRECTION','PORTABILITY','DELETION','ANONYMIZATION','INFORMATION','OBJECTION','RESTRICTION')),
    CONSTRAINT ck_privacy_data_subject_request_2 CHECK (status IN ('RECEIVED','IDENTITY_PENDING','IN_PROGRESS','PARTIALLY_COMPLETED','COMPLETED','DENIED','CANCELLED')),
    CONSTRAINT ck_privacy_data_subject_request_3 CHECK (due_at IS NULL OR due_at >= received_at),
    CONSTRAINT ck_privacy_data_subject_request_4 CHECK (completed_at IS NULL OR completed_at >= received_at)
);

CREATE TABLE privacy.retention_policy (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    policy_code                        varchar(60) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    country_code                       char(2),
    retention_days                     integer NOT NULL,
    trigger_event                      varchar(60) NOT NULL,
    disposition_action                 varchar(30) NOT NULL,
    legal_reference                    varchar(240),
    valid_from                         timestamptz NOT NULL,
    valid_to                           timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_retention_policy PRIMARY KEY (id),
    CONSTRAINT uq_privacy_retention_policy_policy_code_valid_from_1 UNIQUE (policy_code, valid_from),
    CONSTRAINT ck_privacy_retention_policy_1 CHECK (retention_days >= 0),
    CONSTRAINT ck_privacy_retention_policy_2 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_privacy_retention_policy_3 CHECK (disposition_action IN ('DELETE','ANONYMIZE','ARCHIVE','REVIEW')),
    CONSTRAINT ck_privacy_retention_policy_4 CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE privacy.legal_hold (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    hold_reference                     varchar(100) NOT NULL,
    party_id                           uuid,
    resource_type                      varchar(80),
    resource_id                        uuid,
    reason_code                        varchar(60) NOT NULL,
    starts_at                          timestamptz NOT NULL,
    ends_at                            timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    authorized_by                      uuid,
    notes                              text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_legal_hold PRIMARY KEY (id),
    CONSTRAINT uq_privacy_legal_hold_hold_reference_1 UNIQUE (hold_reference),
    CONSTRAINT ck_privacy_legal_hold_1 CHECK (ends_at IS NULL OR ends_at > starts_at),
    CONSTRAINT ck_privacy_legal_hold_2 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED'))
);

CREATE TABLE privacy.erasure_job (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    data_subject_request_id            uuid,
    party_id                           uuid,
    resource_type                      varchar(80) NOT NULL,
    resource_id                        uuid,
    action_type                        varchar(30) NOT NULL,
    scheduled_at                       timestamptz NOT NULL,
    executed_at                        timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    blocked_by_legal_hold_id           uuid,
    result_json                        jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_erasure_job PRIMARY KEY (id),
    CONSTRAINT ck_privacy_erasure_job_1 CHECK (action_type IN ('DELETE','ANONYMIZE','TOKENIZE','ARCHIVE')),
    CONSTRAINT ck_privacy_erasure_job_2 CHECK (status IN ('SCHEDULED','RUNNING','COMPLETED','FAILED','BLOCKED','CANCELLED'))
);

CREATE TABLE privacy.data_access_audit (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    actor_id                           uuid,
    actor_type                         varchar(30) NOT NULL,
    party_id                           uuid,
    resource_type                      varchar(80) NOT NULL,
    resource_id                        uuid,
    action                             varchar(30) NOT NULL,
    purpose_code                       varchar(50),
    occurred_at                        timestamptz NOT NULL,
    request_id                         varchar(100),
    source_ip_token                    varchar(100),
    metadata_json                      jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_privacy_data_access_audit PRIMARY KEY (id)
);

CREATE TABLE privacy.data_sharing_record (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    party_id                           uuid,
    recipient_party_id                 uuid,
    recipient_name                     varchar(180),
    purpose_id                         uuid NOT NULL,
    legal_basis_id                     uuid,
    data_categories_json               jsonb NOT NULL,
    shared_at                          timestamptz NOT NULL,
    transfer_country_code              char(2),
    agreement_reference                varchar(120),
    request_reference                  varchar(120),
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_privacy_data_sharing_record PRIMARY KEY (id)
);

CREATE TABLE privacy.token_map (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    token_type                         varchar(40) NOT NULL,
    token_value                        varchar(180) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    resource_id_ciphertext             text NOT NULL,
    created_at_source                  timestamptz NOT NULL,
    expires_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_token_map PRIMARY KEY (id),
    CONSTRAINT uq_privacy_token_map_token_type_token_value_1 UNIQUE (token_type, token_value),
    CONSTRAINT ck_privacy_token_map_1 CHECK (status IN ('ACTIVE','REVOKED','EXPIRED'))
);

CREATE TABLE integration.outbox_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    aggregate_type                     varchar(80) NOT NULL,
    aggregate_id                       uuid NOT NULL,
    aggregate_version                  bigint NOT NULL,
    event_index                        smallint NOT NULL DEFAULT 0,
    event_type                         varchar(120) NOT NULL,
    payload_version                    integer NOT NULL DEFAULT 1,
    payload                            jsonb NOT NULL,
    occurred_at                        timestamptz NOT NULL,
    published_at                       timestamptz,
    publish_attempts                   integer NOT NULL DEFAULT 0,
    last_error                         text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_outbox_event PRIMARY KEY (id),
    CONSTRAINT uq_integration_outbox_event_aggregate_type_aggreg_7e983bc6 UNIQUE (aggregate_type, aggregate_id, aggregate_version, event_index),
    CONSTRAINT ck_integration_outbox_event_1 CHECK (aggregate_version >= 0),
    CONSTRAINT ck_integration_outbox_event_2 CHECK (event_index >= 0),
    CONSTRAINT ck_integration_outbox_event_3 CHECK (payload_version > 0),
    CONSTRAINT ck_integration_outbox_event_4 CHECK (publish_attempts >= 0)
);

CREATE TABLE integration.inbox_message (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    consumer_name                      varchar(100) NOT NULL,
    message_id                         varchar(180) NOT NULL,
    event_type                         varchar(120),
    received_at                        timestamptz NOT NULL,
    processed_at                       timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    result_json                        jsonb,
    last_error                         text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_inbox_message PRIMARY KEY (id),
    CONSTRAINT uq_integration_inbox_message_consumer_name_message_id_1 UNIQUE (consumer_name, message_id),
    CONSTRAINT ck_integration_inbox_message_1 CHECK (status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED'))
);

CREATE TABLE integration.idempotency_key (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    scope                              varchar(100) NOT NULL,
    idempotency_key                    varchar(180) NOT NULL,
    request_hash                       varchar(64) NOT NULL,
    resource_type                      varchar(80),
    resource_id                        uuid,
    response_code                      integer,
    response_snapshot                  jsonb,
    expires_at                         timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'PROCESSING',
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_idempotency_key PRIMARY KEY (id),
    CONSTRAINT uq_integration_idempotency_key_scope_idempotency_key_1 UNIQUE (scope, idempotency_key),
    CONSTRAINT ck_integration_idempotency_key_1 CHECK (status IN ('PROCESSING','COMPLETED','FAILED','EXPIRED'))
);

CREATE TABLE integration.external_reference (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    system_code                        varchar(60) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    resource_id                        uuid NOT NULL,
    external_resource_type             varchar(80),
    external_id                        varchar(180) NOT NULL,
    valid_from                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to                           timestamptz,
    metadata_json                      jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_integration_external_reference PRIMARY KEY (id),
    CONSTRAINT uq_integration_external_reference_system_code_ext_9c5d3d28 UNIQUE (system_code, external_id, valid_from),
    CONSTRAINT ck_integration_external_reference_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE TABLE integration.saga_instance (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    saga_type                          varchar(100) NOT NULL,
    business_key                       varchar(180) NOT NULL,
    current_step                       varchar(100),
    status                             varchar(20) NOT NULL DEFAULT 'STARTED',
    state_json                         jsonb,
    started_at                         timestamptz NOT NULL,
    completed_at                       timestamptz,
    last_error                         text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_saga_instance PRIMARY KEY (id),
    CONSTRAINT uq_integration_saga_instance_saga_type_business_key_1 UNIQUE (saga_type, business_key),
    CONSTRAINT ck_integration_saga_instance_1 CHECK (status IN ('STARTED','RUNNING','COMPENSATING','COMPLETED','FAILED','CANCELLED'))
);

CREATE TABLE integration.saga_step (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    saga_instance_id                   uuid NOT NULL,
    step_number                        integer NOT NULL,
    step_name                          varchar(100) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    attempts                           integer NOT NULL DEFAULT 0,
    started_at                         timestamptz,
    completed_at                       timestamptz,
    request_json                       jsonb,
    result_json                        jsonb,
    last_error                         text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_saga_step PRIMARY KEY (id),
    CONSTRAINT uq_integration_saga_step_saga_instance_id_step_number_1 UNIQUE (saga_instance_id, step_number),
    CONSTRAINT ck_integration_saga_step_1 CHECK (step_number >= 0),
    CONSTRAINT ck_integration_saga_step_2 CHECK (attempts >= 0),
    CONSTRAINT ck_integration_saga_step_3 CHECK (status IN ('PENDING','RUNNING','COMPLETED','FAILED','COMPENSATED','SKIPPED'))
);

CREATE TABLE integration.dead_letter (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    source_system                      varchar(80) NOT NULL,
    message_id                         varchar(180) NOT NULL,
    event_type                         varchar(120),
    payload                            jsonb,
    error_class                        varchar(160),
    error_message                      text,
    failed_at                          timestamptz NOT NULL,
    retry_count                        integer NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    reprocessed_at                     timestamptz,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_dead_letter PRIMARY KEY (id),
    CONSTRAINT uq_integration_dead_letter_source_system_message_id_1 UNIQUE (source_system, message_id),
    CONSTRAINT ck_integration_dead_letter_1 CHECK (retry_count >= 0),
    CONSTRAINT ck_integration_dead_letter_2 CHECK (status IN ('OPEN','RETRYING','REPROCESSED','IGNORED','RESOLVED'))
);

CREATE TABLE integration.audit_event (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    actor_type                         varchar(30) NOT NULL,
    actor_id                           uuid,
    action                             varchar(80) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    resource_id                        uuid,
    legal_entity_id                    uuid,
    branch_id                          uuid,
    occurred_at                        timestamptz NOT NULL,
    request_id                         varchar(100),
    correlation_id                     varchar(100),
    source_ip_token                    varchar(100),
    before_hash                        varchar(64),
    after_hash                         varchar(64),
    metadata_json                      jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_integration_audit_event PRIMARY KEY (id)
);

CREATE TABLE integration.job_run (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    job_name                           varchar(120) NOT NULL,
    run_key                            varchar(180) NOT NULL,
    started_at                         timestamptz NOT NULL,
    completed_at                       timestamptz,
    status                             varchar(20) NOT NULL DEFAULT 'RUNNING',
    records_read                       bigint NOT NULL DEFAULT 0,
    records_written                    bigint NOT NULL DEFAULT 0,
    records_failed                     bigint NOT NULL DEFAULT 0,
    checkpoint_json                    jsonb,
    last_error                         text,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_job_run PRIMARY KEY (id),
    CONSTRAINT uq_integration_job_run_job_name_run_key_1 UNIQUE (job_name, run_key),
    CONSTRAINT ck_integration_job_run_1 CHECK (records_read >= 0),
    CONSTRAINT ck_integration_job_run_2 CHECK (records_written >= 0),
    CONSTRAINT ck_integration_job_run_3 CHECK (records_failed >= 0),
    CONSTRAINT ck_integration_job_run_4 CHECK (status IN ('RUNNING','COMPLETED','PARTIAL','FAILED','CANCELLED'))
);

CREATE TABLE integration.import_batch (
    id                                 uuid NOT NULL DEFAULT gen_random_uuid(),
    import_type                        varchar(80) NOT NULL,
    source_system                      varchar(80) NOT NULL,
    external_batch_id                  varchar(180),
    object_key                         varchar(500),
    received_at                        timestamptz NOT NULL,
    processed_at                       timestamptz,
    record_count                       integer NOT NULL DEFAULT 0,
    success_count                      integer NOT NULL DEFAULT 0,
    failure_count                      integer NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    result_json                        jsonb,
    created_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                         timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_import_batch PRIMARY KEY (id),
    CONSTRAINT uq_integration_import_batch_source_system_externa_958d6d40 UNIQUE (source_system, external_batch_id),
    CONSTRAINT ck_integration_import_batch_1 CHECK (record_count >= 0),
    CONSTRAINT ck_integration_import_batch_2 CHECK (success_count >= 0),
    CONSTRAINT ck_integration_import_batch_3 CHECK (failure_count >= 0),
    CONSTRAINT ck_integration_import_batch_4 CHECK (status IN ('RECEIVED','VALIDATING','PROCESSING','COMPLETED','PARTIAL','FAILED','REJECTED'))
);

-- --------------------------------------------------------------------------
-- Foreign keys
-- --------------------------------------------------------------------------
ALTER TABLE org.business_unit ADD CONSTRAINT fk_org_business_unit_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE org.business_unit ADD CONSTRAINT fk_org_business_unit_parent_business_unit_id_org__913017ce FOREIGN KEY (parent_business_unit_id) REFERENCES org.business_unit (id);
ALTER TABLE org.branch ADD CONSTRAINT fk_org_branch_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE org.branch ADD CONSTRAINT fk_org_branch_business_unit_id_org_business_unit_2 FOREIGN KEY (business_unit_id) REFERENCES org.business_unit (id);
ALTER TABLE org.branch_operator ADD CONSTRAINT fk_org_branch_operator_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id) ON DELETE CASCADE;
ALTER TABLE org.branch_operator ADD CONSTRAINT fk_org_branch_operator_operator_party_id_party_party_2 FOREIGN KEY (operator_party_id) REFERENCES party.party (id);
ALTER TABLE org.branch_hours ADD CONSTRAINT fk_org_branch_hours_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id) ON DELETE CASCADE;
ALTER TABLE org.branch_calendar_exception ADD CONSTRAINT fk_org_branch_calendar_exception_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id) ON DELETE CASCADE;
ALTER TABLE party.party ADD CONSTRAINT fk_party_party_merged_into_party_id_party_party_1 FOREIGN KEY (merged_into_party_id) REFERENCES party.party (id);
ALTER TABLE party.person ADD CONSTRAINT fk_party_person_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id) ON DELETE CASCADE;
ALTER TABLE party.organization ADD CONSTRAINT fk_party_organization_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id) ON DELETE CASCADE;
ALTER TABLE party.party_identifier ADD CONSTRAINT fk_party_party_identifier_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id) ON DELETE CASCADE;
ALTER TABLE party.contact_point ADD CONSTRAINT fk_party_contact_point_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id) ON DELETE CASCADE;
ALTER TABLE party.party_address ADD CONSTRAINT fk_party_party_address_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id) ON DELETE CASCADE;
ALTER TABLE party.party_address ADD CONSTRAINT fk_party_party_address_address_id_party_postal_address_2 FOREIGN KEY (address_id) REFERENCES party.postal_address (id);
ALTER TABLE party.customer_account ADD CONSTRAINT fk_party_customer_account_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE party.customer_account ADD CONSTRAINT fk_party_customer_account_legal_entity_id_org_leg_69f18cc9 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE party.organization_representative ADD CONSTRAINT fk_party_organization_representative_organization_991f314f FOREIGN KEY (organization_party_id) REFERENCES party.organization (party_id);
ALTER TABLE party.organization_representative ADD CONSTRAINT fk_party_organization_representative_person_party_06bc49af FOREIGN KEY (person_party_id) REFERENCES party.person (party_id);
ALTER TABLE party.driver_profile ADD CONSTRAINT fk_party_driver_profile_person_party_id_party_person_1 FOREIGN KEY (person_party_id) REFERENCES party.person (party_id);
ALTER TABLE party.driver_license ADD CONSTRAINT fk_party_driver_license_driver_profile_id_party_d_1256538a FOREIGN KEY (driver_profile_id) REFERENCES party.driver_profile (id) ON DELETE CASCADE;
ALTER TABLE party.identity_verification ADD CONSTRAINT fk_party_identity_verification_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE party.risk_assessment ADD CONSTRAINT fk_party_risk_assessment_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE party.customer_restriction ADD CONSTRAINT fk_party_customer_restriction_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE catalog.vehicle_model ADD CONSTRAINT fk_catalog_vehicle_model_make_id_catalog_vehicle_make_1 FOREIGN KEY (make_id) REFERENCES catalog.vehicle_make (id);
ALTER TABLE catalog.vehicle_variant ADD CONSTRAINT fk_catalog_vehicle_variant_model_id_catalog_vehic_cc9f481e FOREIGN KEY (model_id) REFERENCES catalog.vehicle_model (id);
ALTER TABLE catalog.variant_feature ADD CONSTRAINT fk_catalog_variant_feature_vehicle_variant_id_cat_b18cefb4 FOREIGN KEY (vehicle_variant_id) REFERENCES catalog.vehicle_variant (id) ON DELETE CASCADE;
ALTER TABLE catalog.variant_feature ADD CONSTRAINT fk_catalog_variant_feature_feature_id_catalog_feature_2 FOREIGN KEY (feature_id) REFERENCES catalog.feature (id) ON DELETE CASCADE;
ALTER TABLE catalog.vehicle_group_variant ADD CONSTRAINT fk_catalog_vehicle_group_variant_vehicle_group_id_3433c773 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id) ON DELETE CASCADE;
ALTER TABLE catalog.vehicle_group_variant ADD CONSTRAINT fk_catalog_vehicle_group_variant_vehicle_variant__9cb5d80b FOREIGN KEY (vehicle_variant_id) REFERENCES catalog.vehicle_variant (id);
ALTER TABLE catalog.vehicle_group_upgrade ADD CONSTRAINT fk_catalog_vehicle_group_upgrade_from_group_id_ca_3d9eb99b FOREIGN KEY (from_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE catalog.vehicle_group_upgrade ADD CONSTRAINT fk_catalog_vehicle_group_upgrade_to_group_id_cata_b75e5b64 FOREIGN KEY (to_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE catalog.commercial_product ADD CONSTRAINT fk_catalog_commercial_product_unit_code_catalog_u_bb2e364a FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE catalog.commercial_product ADD CONSTRAINT fk_catalog_commercial_product_tax_category_id_cat_a17528a4 FOREIGN KEY (tax_category_id) REFERENCES catalog.tax_category (id);
ALTER TABLE catalog.protection_coverage ADD CONSTRAINT fk_catalog_protection_coverage_protection_product_ee8a7131 FOREIGN KEY (protection_product_id) REFERENCES catalog.commercial_product (id) ON DELETE CASCADE;
ALTER TABLE catalog.protection_coverage ADD CONSTRAINT fk_catalog_protection_coverage_coverage_id_catalo_fa7da6c0 FOREIGN KEY (coverage_id) REFERENCES catalog.coverage (id);
ALTER TABLE catalog.charge_type ADD CONSTRAINT fk_catalog_charge_type_default_product_id_catalog_0ab13201 FOREIGN KEY (default_product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE corporate.partner ADD CONSTRAINT fk_corporate_partner_party_id_party_organization_1 FOREIGN KEY (party_id) REFERENCES party.organization (party_id);
ALTER TABLE corporate.partner_agreement ADD CONSTRAINT fk_corporate_partner_agreement_partner_id_corpora_bdc6085c FOREIGN KEY (partner_id) REFERENCES corporate.partner (id);
ALTER TABLE corporate.partner_agreement ADD CONSTRAINT fk_corporate_partner_agreement_legal_entity_id_or_9769ba82 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE corporate.corporate_agreement ADD CONSTRAINT fk_corporate_corporate_agreement_customer_account_fabc5706 FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE corporate.corporate_agreement ADD CONSTRAINT fk_corporate_corporate_agreement_legal_entity_id__b542cbcb FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE corporate.corporate_cost_center ADD CONSTRAINT fk_corporate_corporate_cost_center_corporate_agre_0e663e39 FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate.corporate_cost_center ADD CONSTRAINT fk_corporate_corporate_cost_center_parent_cost_ce_d1c0422c FOREIGN KEY (parent_cost_center_id) REFERENCES corporate.corporate_cost_center (id);
ALTER TABLE corporate.authorized_driver ADD CONSTRAINT fk_corporate_authorized_driver_corporate_agreemen_dfd5ceff FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate.authorized_driver ADD CONSTRAINT fk_corporate_authorized_driver_driver_profile_id__c24f2666 FOREIGN KEY (driver_profile_id) REFERENCES party.driver_profile (id);
ALTER TABLE corporate.authorized_driver ADD CONSTRAINT fk_corporate_authorized_driver_cost_center_id_cor_0ddc326b FOREIGN KEY (cost_center_id) REFERENCES corporate.corporate_cost_center (id);
ALTER TABLE corporate.corporate_billing_profile ADD CONSTRAINT fk_corporate_corporate_billing_profile_corporate__547efdde FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate.corporate_billing_profile ADD CONSTRAINT fk_corporate_corporate_billing_profile_billing_pa_78869652 FOREIGN KEY (billing_party_id) REFERENCES party.party (id);
ALTER TABLE corporate.corporate_billing_profile ADD CONSTRAINT fk_corporate_corporate_billing_profile_billing_ad_1942df6c FOREIGN KEY (billing_address_id) REFERENCES party.postal_address (id);
ALTER TABLE fleet.acquisition_order ADD CONSTRAINT fk_fleet_acquisition_order_legal_entity_id_org_le_b74bdace FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE fleet.acquisition_order ADD CONSTRAINT fk_fleet_acquisition_order_supplier_party_id_part_b47c48d6 FOREIGN KEY (supplier_party_id) REFERENCES party.organization (party_id);
ALTER TABLE fleet.acquisition_order_line ADD CONSTRAINT fk_fleet_acquisition_order_line_acquisition_order_5b6faa62 FOREIGN KEY (acquisition_order_id) REFERENCES fleet.acquisition_order (id) ON DELETE CASCADE;
ALTER TABLE fleet.acquisition_order_line ADD CONSTRAINT fk_fleet_acquisition_order_line_vehicle_variant_i_8ee7863e FOREIGN KEY (vehicle_variant_id) REFERENCES catalog.vehicle_variant (id);
ALTER TABLE fleet.vehicle ADD CONSTRAINT fk_fleet_vehicle_vehicle_variant_id_catalog_vehic_566b420b FOREIGN KEY (vehicle_variant_id) REFERENCES catalog.vehicle_variant (id);
ALTER TABLE fleet.vehicle ADD CONSTRAINT fk_fleet_vehicle_owning_legal_entity_id_org_legal_entity_2 FOREIGN KEY (owning_legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE fleet.vehicle ADD CONSTRAINT fk_fleet_vehicle_acquisition_order_line_id_fleet__674c3c12 FOREIGN KEY (acquisition_order_line_id) REFERENCES fleet.acquisition_order_line (id);
ALTER TABLE fleet.vehicle ADD CONSTRAINT fk_fleet_vehicle_current_branch_id_org_branch_4 FOREIGN KEY (current_branch_id) REFERENCES org.branch (id);
ALTER TABLE fleet.vehicle ADD CONSTRAINT fk_fleet_vehicle_current_vehicle_group_id_catalog_535204f6 FOREIGN KEY (current_vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE fleet.vehicle_registration ADD CONSTRAINT fk_fleet_vehicle_registration_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet.vehicle_group_assignment ADD CONSTRAINT fk_fleet_vehicle_group_assignment_vehicle_id_flee_842255ce FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet.vehicle_group_assignment ADD CONSTRAINT fk_fleet_vehicle_group_assignment_vehicle_group_i_14bed1dd FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE fleet.vehicle_operational_state_history ADD CONSTRAINT fk_fleet_vehicle_operational_state_history_vehicl_98f31720 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet.vehicle_lifecycle_history ADD CONSTRAINT fk_fleet_vehicle_lifecycle_history_vehicle_id_fle_94edbc4a FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet.vehicle_restriction ADD CONSTRAINT fk_fleet_vehicle_restriction_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.vehicle_location_history ADD CONSTRAINT fk_fleet_vehicle_location_history_vehicle_id_flee_7dfbd856 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.vehicle_location_history ADD CONSTRAINT fk_fleet_vehicle_location_history_branch_id_org_branch_2 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE fleet.vehicle_calendar_entry ADD CONSTRAINT fk_fleet_vehicle_calendar_entry_legal_entity_id_o_6e894812 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE fleet.vehicle_calendar_entry ADD CONSTRAINT fk_fleet_vehicle_calendar_entry_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.odometer_reading ADD CONSTRAINT fk_fleet_odometer_reading_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.odometer_reading ADD CONSTRAINT fk_fleet_odometer_reading_corrects_reading_id_fle_7abc031f FOREIGN KEY (corrects_reading_id) REFERENCES fleet.odometer_reading (id);
ALTER TABLE fleet.fuel_reading ADD CONSTRAINT fk_fleet_fuel_reading_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.asset_document ADD CONSTRAINT fk_fleet_asset_document_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.accessory_asset ADD CONSTRAINT fk_fleet_accessory_asset_product_id_catalog_comme_2de1c88f FOREIGN KEY (product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE fleet.accessory_asset ADD CONSTRAINT fk_fleet_accessory_asset_owning_legal_entity_id_o_3c33def1 FOREIGN KEY (owning_legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE fleet.vehicle_accessory_assignment ADD CONSTRAINT fk_fleet_vehicle_accessory_assignment_vehicle_id__9d76ef64 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.vehicle_accessory_assignment ADD CONSTRAINT fk_fleet_vehicle_accessory_assignment_accessory_a_d6bac007 FOREIGN KEY (accessory_asset_id) REFERENCES fleet.accessory_asset (id);
ALTER TABLE fleet.vehicle_cost_basis ADD CONSTRAINT fk_fleet_vehicle_cost_basis_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.depreciation_entry ADD CONSTRAINT fk_fleet_depreciation_entry_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet.disposal_eligibility ADD CONSTRAINT fk_fleet_disposal_eligibility_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE pricing.rate_plan ADD CONSTRAINT fk_pricing_rate_plan_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE pricing.rate_plan_version ADD CONSTRAINT fk_pricing_rate_plan_version_rate_plan_id_pricing_733eaaf5 FOREIGN KEY (rate_plan_id) REFERENCES pricing.rate_plan (id) ON DELETE CASCADE;
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_rate_plan_vers_3a8fc222 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_origin_branch__66ca57bc FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_destination_br_38984212 FOREIGN KEY (destination_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_vehicle_group__7ae718b9 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_channel_id_org_1ba087d8 FOREIGN KEY (channel_id) REFERENCES org.channel (id);
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_corporate_agre_6e701357 FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id);
ALTER TABLE pricing.rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_partner_id_cor_e060e1ed FOREIGN KEY (partner_id) REFERENCES corporate.partner (id);
ALTER TABLE pricing.rental_length_band ADD CONSTRAINT fk_pricing_rental_length_band_rate_plan_version_i_9c376409 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.season ADD CONSTRAINT fk_pricing_season_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE pricing.base_rate ADD CONSTRAINT fk_pricing_base_rate_rate_plan_version_id_pricing_2316b89f FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.base_rate ADD CONSTRAINT fk_pricing_base_rate_vehicle_group_id_catalog_veh_78dc57b3 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE pricing.base_rate ADD CONSTRAINT fk_pricing_base_rate_origin_branch_id_org_branch_3 FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.base_rate ADD CONSTRAINT fk_pricing_base_rate_rental_length_band_id_pricin_6d056e4d FOREIGN KEY (rental_length_band_id) REFERENCES pricing.rental_length_band (id);
ALTER TABLE pricing.base_rate ADD CONSTRAINT fk_pricing_base_rate_season_id_pricing_season_5 FOREIGN KEY (season_id) REFERENCES pricing.season (id);
ALTER TABLE pricing.mileage_package ADD CONSTRAINT fk_pricing_mileage_package_rate_plan_version_id_p_270ffd4f FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.mileage_rate ADD CONSTRAINT fk_pricing_mileage_rate_mileage_package_id_pricin_090b9e6d FOREIGN KEY (mileage_package_id) REFERENCES pricing.mileage_package (id) ON DELETE CASCADE;
ALTER TABLE pricing.mileage_rate ADD CONSTRAINT fk_pricing_mileage_rate_vehicle_group_id_catalog__91640bf7 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE pricing.one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_rate_plan_version_id_pric_bf479ef8 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_origin_branch_id_org_branch_2 FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_destination_branch_id_org_branch_3 FOREIGN KEY (destination_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_vehicle_group_id_catalog__cf12e5c7 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE pricing.one_way_price ADD CONSTRAINT fk_pricing_one_way_price_one_way_rule_id_pricing__e419f17b FOREIGN KEY (one_way_rule_id) REFERENCES pricing.one_way_rule (id) ON DELETE CASCADE;
ALTER TABLE pricing.fuel_price ADD CONSTRAINT fk_pricing_fuel_price_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE pricing.fuel_price ADD CONSTRAINT fk_pricing_fuel_price_branch_id_org_branch_2 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.preauthorization_rule ADD CONSTRAINT fk_pricing_preauthorization_rule_rate_plan_versio_f22e10b2 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.preauthorization_rule ADD CONSTRAINT fk_pricing_preauthorization_rule_vehicle_group_id_d327ec19 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE pricing.pricing_rule ADD CONSTRAINT fk_pricing_pricing_rule_rate_plan_version_id_pric_5df31375 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing.coupon ADD CONSTRAINT fk_pricing_coupon_promotion_id_pricing_promotion_1 FOREIGN KEY (promotion_id) REFERENCES pricing.promotion (id) ON DELETE CASCADE;
ALTER TABLE pricing.coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_coupon_id_pricing_coupon_1 FOREIGN KEY (coupon_id) REFERENCES pricing.coupon (id);
ALTER TABLE pricing.coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE pricing.coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_reservation_id_reser_20f2c00e FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE pricing.coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_quote_id_pricing_quote_4 FOREIGN KEY (quote_id) REFERENCES pricing.quote (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_customer_account_id_party_custom_f3509bd8 FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_rate_plan_version_id_pricing_rat_1e59fe59 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_origin_branch_id_org_branch_4 FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_destination_branch_id_org_branch_5 FOREIGN KEY (destination_branch_id) REFERENCES org.branch (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_vehicle_group_id_catalog_vehicle_group_6 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE pricing.quote ADD CONSTRAINT fk_pricing_quote_channel_id_org_channel_7 FOREIGN KEY (channel_id) REFERENCES org.channel (id);
ALTER TABLE pricing.quote_line ADD CONSTRAINT fk_pricing_quote_line_quote_id_pricing_quote_1 FOREIGN KEY (quote_id) REFERENCES pricing.quote (id) ON DELETE CASCADE;
ALTER TABLE pricing.quote_line ADD CONSTRAINT fk_pricing_quote_line_product_id_catalog_commerci_ee18710e FOREIGN KEY (product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE pricing.quote_line ADD CONSTRAINT fk_pricing_quote_line_charge_type_id_catalog_charge_type_3 FOREIGN KEY (charge_type_id) REFERENCES catalog.charge_type (id);
ALTER TABLE pricing.quote_line ADD CONSTRAINT fk_pricing_quote_line_unit_code_catalog_unit_of_measure_4 FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE pricing.pricing_calculation ADD CONSTRAINT fk_pricing_pricing_calculation_quote_id_pricing_quote_1 FOREIGN KEY (quote_id) REFERENCES pricing.quote (id) ON DELETE CASCADE;
ALTER TABLE pricing.quote_rule_trace ADD CONSTRAINT fk_pricing_quote_rule_trace_pricing_calculation_i_664709e5 FOREIGN KEY (pricing_calculation_id) REFERENCES pricing.pricing_calculation (id) ON DELETE CASCADE;
ALTER TABLE corporate.rate_entitlement ADD CONSTRAINT fk_corporate_rate_entitlement_corporate_agreement_1b6fe465 FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate.rate_entitlement ADD CONSTRAINT fk_corporate_rate_entitlement_rate_plan_id_pricin_443b648f FOREIGN KEY (rate_plan_id) REFERENCES pricing.rate_plan (id);
ALTER TABLE corporate.rate_entitlement ADD CONSTRAINT fk_corporate_rate_entitlement_vehicle_group_id_ca_9961c6e2 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE corporate.purchase_order ADD CONSTRAINT fk_corporate_purchase_order_corporate_agreement_i_49590724 FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate.purchase_order ADD CONSTRAINT fk_corporate_purchase_order_cost_center_id_corpor_8869e641 FOREIGN KEY (cost_center_id) REFERENCES corporate.corporate_cost_center (id);
ALTER TABLE corporate.voucher ADD CONSTRAINT fk_corporate_voucher_corporate_agreement_id_corpo_ee99af88 FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id);
ALTER TABLE corporate.voucher ADD CONSTRAINT fk_corporate_voucher_partner_agreement_id_corpora_d0bdacf7 FOREIGN KEY (partner_agreement_id) REFERENCES corporate.partner_agreement (id);
ALTER TABLE corporate.voucher ADD CONSTRAINT fk_corporate_voucher_authorized_party_id_party_party_3 FOREIGN KEY (authorized_party_id) REFERENCES party.party (id);
ALTER TABLE corporate.consolidated_billing_instruction ADD CONSTRAINT fk_corporate_consolidated_billing_instruction_cor_d19eee78 FOREIGN KEY (corporate_billing_profile_id) REFERENCES corporate.corporate_billing_profile (id) ON DELETE CASCADE;
ALTER TABLE corporate.consolidated_billing_instruction ADD CONSTRAINT fk_corporate_consolidated_billing_instruction_rec_fb4bcb7d FOREIGN KEY (recipient_contact_id) REFERENCES party.contact_point (id);
ALTER TABLE availability.inventory_bucket ADD CONSTRAINT fk_availability_inventory_bucket_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.inventory_bucket ADD CONSTRAINT fk_availability_inventory_bucket_vehicle_group_id_7ef5caad FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.availability_hold ADD CONSTRAINT fk_availability_availability_hold_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.availability_hold ADD CONSTRAINT fk_availability_availability_hold_vehicle_group_i_246a9284 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.capacity_commitment ADD CONSTRAINT fk_availability_capacity_commitment_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.capacity_commitment ADD CONSTRAINT fk_availability_capacity_commitment_vehicle_group_ee08c37d FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.upgrade_path ADD CONSTRAINT fk_availability_upgrade_path_origin_branch_id_org_branch_1 FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.upgrade_path ADD CONSTRAINT fk_availability_upgrade_path_from_group_id_catalo_7470f48f FOREIGN KEY (from_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.upgrade_path ADD CONSTRAINT fk_availability_upgrade_path_to_group_id_catalog__0b7eff92 FOREIGN KEY (to_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_partner_agreement_bfa6ad8b FOREIGN KEY (partner_agreement_id) REFERENCES corporate.partner_agreement (id);
ALTER TABLE availability.fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_corporate_agreeme_6ceac69d FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id);
ALTER TABLE availability.fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_branch_id_org_branch_3 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_vehicle_group_id__cc05a8e4 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.relocation_order ADD CONSTRAINT fk_availability_relocation_order_legal_entity_id__f05e7324 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE availability.relocation_order ADD CONSTRAINT fk_availability_relocation_order_origin_branch_id_e8b29d25 FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.relocation_order ADD CONSTRAINT fk_availability_relocation_order_destination_bran_0b2fa5fe FOREIGN KEY (destination_branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.relocation_leg ADD CONSTRAINT fk_availability_relocation_leg_relocation_order_i_001aa7c2 FOREIGN KEY (relocation_order_id) REFERENCES availability.relocation_order (id) ON DELETE CASCADE;
ALTER TABLE availability.relocation_leg ADD CONSTRAINT fk_availability_relocation_leg_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE availability.relocation_leg ADD CONSTRAINT fk_availability_relocation_leg_calendar_entry_id__c7a15dd3 FOREIGN KEY (calendar_entry_id) REFERENCES fleet.vehicle_calendar_entry (id);
ALTER TABLE availability.oversell_alert ADD CONSTRAINT fk_availability_oversell_alert_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.oversell_alert ADD CONSTRAINT fk_availability_oversell_alert_vehicle_group_id_c_8aa75740 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE availability.forecast_snapshot ADD CONSTRAINT fk_availability_forecast_snapshot_branch_id_org_branch_1 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE availability.forecast_snapshot ADD CONSTRAINT fk_availability_forecast_snapshot_vehicle_group_i_d8873a07 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_legal_entity_id_org_le_80967ca0 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_customer_account_id_pa_85377a7b FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_booker_party_id_party_party_3 FOREIGN KEY (booker_party_id) REFERENCES party.party (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_requested_vehicle_grou_7f83f461 FOREIGN KEY (requested_vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_pickup_branch_id_org_branch_5 FOREIGN KEY (pickup_branch_id) REFERENCES org.branch (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_planned_return_branch__7465987c FOREIGN KEY (planned_return_branch_id) REFERENCES org.branch (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_channel_id_org_channel_7 FOREIGN KEY (channel_id) REFERENCES org.channel (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_rate_plan_version_id_p_83281045 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_quote_id_pricing_quote_9 FOREIGN KEY (quote_id) REFERENCES pricing.quote (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_corporate_agreement_id_f244d17d FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_cost_center_id_corpora_b229e667 FOREIGN KEY (cost_center_id) REFERENCES corporate.corporate_cost_center (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_purchase_order_id_corp_bafb6cf8 FOREIGN KEY (purchase_order_id) REFERENCES corporate.purchase_order (id);
ALTER TABLE reservation.reservation ADD CONSTRAINT fk_reservation_reservation_voucher_id_corporate_voucher_13 FOREIGN KEY (voucher_id) REFERENCES corporate.voucher (id);
ALTER TABLE reservation.reservation_driver ADD CONSTRAINT fk_reservation_reservation_driver_reservation_id__9d862a68 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.reservation_driver ADD CONSTRAINT fk_reservation_reservation_driver_driver_profile__aa9ab200 FOREIGN KEY (driver_profile_id) REFERENCES party.driver_profile (id);
ALTER TABLE reservation.reservation_product ADD CONSTRAINT fk_reservation_reservation_product_reservation_id_ff90d098 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.reservation_product ADD CONSTRAINT fk_reservation_reservation_product_product_id_cat_ed1f54e4 FOREIGN KEY (product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE reservation.reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_reservation_479bc52e FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_quote_line__9bf598d0 FOREIGN KEY (quote_line_id) REFERENCES pricing.quote_line (id);
ALTER TABLE reservation.reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_product_id__b3c5f731 FOREIGN KEY (product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE reservation.reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_charge_type_a99c8203 FOREIGN KEY (charge_type_id) REFERENCES catalog.charge_type (id);
ALTER TABLE reservation.reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_unit_code_c_80863c1a FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE reservation.reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_rate_plan_v_51b707de FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id);
ALTER TABLE reservation.reservation_status_history ADD CONSTRAINT fk_reservation_reservation_status_history_reserva_c9f5f2e5 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.reservation_change ADD CONSTRAINT fk_reservation_reservation_change_reservation_id__fa8da71c FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE reservation.reservation_change ADD CONSTRAINT fk_reservation_reservation_change_requested_by_pa_f41ad951 FOREIGN KEY (requested_by_party_id) REFERENCES party.party (id);
ALTER TABLE reservation.reservation_cancellation ADD CONSTRAINT fk_reservation_reservation_cancellation_reservati_7bd79379 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE reservation.reservation_cancellation ADD CONSTRAINT fk_reservation_reservation_cancellation_cancelled_b1cb1a2b FOREIGN KEY (cancelled_by_party_id) REFERENCES party.party (id);
ALTER TABLE reservation.no_show_assessment ADD CONSTRAINT fk_reservation_no_show_assessment_reservation_id__c6406c62 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE reservation.reservation_guarantee ADD CONSTRAINT fk_reservation_reservation_guarantee_reservation__83e20f6e FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.partner_booking ADD CONSTRAINT fk_reservation_partner_booking_reservation_id_res_0c525701 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.partner_booking ADD CONSTRAINT fk_reservation_partner_booking_partner_id_corpora_a50d252f FOREIGN KEY (partner_id) REFERENCES corporate.partner (id);
ALTER TABLE reservation.partner_booking ADD CONSTRAINT fk_reservation_partner_booking_partner_agreement__7ffdcc6c FOREIGN KEY (partner_agreement_id) REFERENCES corporate.partner_agreement (id);
ALTER TABLE reservation.digital_pickup_eligibility ADD CONSTRAINT fk_reservation_digital_pickup_eligibility_reserva_df67048b FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE reservation.reservation_note ADD CONSTRAINT fk_reservation_reservation_note_reservation_id_re_b501e158 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.reservation_inventory_commitment ADD CONSTRAINT fk_reservation_reservation_inventory_commitment_r_c0963fa6 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation.reservation_inventory_commitment ADD CONSTRAINT fk_reservation_reservation_inventory_commitment_a_95efb863 FOREIGN KEY (availability_hold_id) REFERENCES availability.availability_hold (id);
ALTER TABLE reservation.reservation_inventory_commitment ADD CONSTRAINT fk_reservation_reservation_inventory_commitment_c_1062bc76 FOREIGN KEY (capacity_commitment_id) REFERENCES availability.capacity_commitment (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_legal_entity_id_org_leg_4f830ed5 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_reservation_id_reservat_46ce6596 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_customer_account_id_par_1cd51e5d FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_origin_branch_id_org_branch_4 FOREIGN KEY (origin_branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_planned_return_branch_i_9a1d9ec0 FOREIGN KEY (planned_return_branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_actual_return_branch_id_5dfc8e3f FOREIGN KEY (actual_return_branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_mileage_package_id_pric_698e03a6 FOREIGN KEY (mileage_package_id) REFERENCES pricing.mileage_package (id);
ALTER TABLE rental.rental_contract ADD CONSTRAINT fk_rental_rental_contract_created_channel_id_org_channel_8 FOREIGN KEY (created_channel_id) REFERENCES org.channel (id);
ALTER TABLE rental.contract_revision ADD CONSTRAINT fk_rental_contract_revision_contract_id_rental_re_e6aed74c FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id) ON DELETE CASCADE;
ALTER TABLE rental.contract_revision ADD CONSTRAINT fk_rental_contract_revision_previous_revision_id__62ea74ca FOREIGN KEY (previous_revision_id) REFERENCES rental.contract_revision (id);
ALTER TABLE rental.contract_party_role ADD CONSTRAINT fk_rental_contract_party_role_contract_id_rental__2b7f26e9 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id) ON DELETE CASCADE;
ALTER TABLE rental.contract_party_role ADD CONSTRAINT fk_rental_contract_party_role_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE rental.contract_product ADD CONSTRAINT fk_rental_contract_product_contract_id_rental_ren_a060c4cb FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id) ON DELETE CASCADE;
ALTER TABLE rental.contract_product ADD CONSTRAINT fk_rental_contract_product_product_id_catalog_com_2ffbcdc7 FOREIGN KEY (product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_contract_i_433b5c59 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id) ON DELETE CASCADE;
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_contract_r_6924bde9 FOREIGN KEY (contract_revision_id) REFERENCES rental.contract_revision (id) ON DELETE CASCADE;
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_reservatio_b09118f3 FOREIGN KEY (reservation_price_line_id) REFERENCES reservation.reservation_price_line (id);
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_product_id_e5d449c8 FOREIGN KEY (product_id) REFERENCES catalog.commercial_product (id);
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_charge_typ_513bc08a FOREIGN KEY (charge_type_id) REFERENCES catalog.charge_type (id);
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_unit_code__a675b815 FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE rental.contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_rate_plan__aa809a02 FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id);
ALTER TABLE rental.vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_contract_id_rental_r_d95c1f9c FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id) ON DELETE CASCADE;
ALTER TABLE rental.vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_calendar_entry_id_fl_76a81150 FOREIGN KEY (calendar_entry_id) REFERENCES fleet.vehicle_calendar_entry (id);
ALTER TABLE rental.vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_vehicle_id_fleet_vehicle_3 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE rental.vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_pickup_branch_id_org_branch_4 FOREIGN KEY (pickup_branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_planned_return_branc_8b855ab2 FOREIGN KEY (planned_return_branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_actual_return_branch_73d5a70a FOREIGN KEY (actual_return_branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.pickup_event ADD CONSTRAINT fk_rental_pickup_event_contract_id_rental_rental__195a99ee FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.pickup_event ADD CONSTRAINT fk_rental_pickup_event_vehicle_assignment_id_rent_a7ee97f9 FOREIGN KEY (vehicle_assignment_id) REFERENCES rental.vehicle_assignment (id);
ALTER TABLE rental.pickup_event ADD CONSTRAINT fk_rental_pickup_event_branch_id_org_branch_3 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.pickup_event ADD CONSTRAINT fk_rental_pickup_event_odometer_reading_id_fleet__88210f28 FOREIGN KEY (odometer_reading_id) REFERENCES fleet.odometer_reading (id);
ALTER TABLE rental.pickup_event ADD CONSTRAINT fk_rental_pickup_event_fuel_reading_id_fleet_fuel_f5e98d7f FOREIGN KEY (fuel_reading_id) REFERENCES fleet.fuel_reading (id);
ALTER TABLE rental.pickup_event ADD CONSTRAINT fk_rental_pickup_event_inspection_id_inspection_i_69d49857 FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id);
ALTER TABLE rental.return_event ADD CONSTRAINT fk_rental_return_event_contract_id_rental_rental__f6920ef5 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.return_event ADD CONSTRAINT fk_rental_return_event_vehicle_assignment_id_rent_aa34499a FOREIGN KEY (vehicle_assignment_id) REFERENCES rental.vehicle_assignment (id);
ALTER TABLE rental.return_event ADD CONSTRAINT fk_rental_return_event_branch_id_org_branch_3 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE rental.return_event ADD CONSTRAINT fk_rental_return_event_odometer_reading_id_fleet__eea06bd9 FOREIGN KEY (odometer_reading_id) REFERENCES fleet.odometer_reading (id);
ALTER TABLE rental.return_event ADD CONSTRAINT fk_rental_return_event_fuel_reading_id_fleet_fuel_8845a500 FOREIGN KEY (fuel_reading_id) REFERENCES fleet.fuel_reading (id);
ALTER TABLE rental.return_event ADD CONSTRAINT fk_rental_return_event_inspection_id_inspection_i_8a62d08c FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id);
ALTER TABLE rental.extension ADD CONSTRAINT fk_rental_extension_contract_id_rental_rental_contract_1 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.extension ADD CONSTRAINT fk_rental_extension_requested_by_party_id_party_party_2 FOREIGN KEY (requested_by_party_id) REFERENCES party.party (id);
ALTER TABLE rental.vehicle_replacement ADD CONSTRAINT fk_rental_vehicle_replacement_contract_id_rental__d46cc399 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.vehicle_replacement ADD CONSTRAINT fk_rental_vehicle_replacement_previous_assignment_4212fc10 FOREIGN KEY (previous_assignment_id) REFERENCES rental.vehicle_assignment (id);
ALTER TABLE rental.vehicle_replacement ADD CONSTRAINT fk_rental_vehicle_replacement_new_assignment_id_r_cc143ecc FOREIGN KEY (new_assignment_id) REFERENCES rental.vehicle_assignment (id);
ALTER TABLE rental.contract_status_history ADD CONSTRAINT fk_rental_contract_status_history_contract_id_ren_b7d30ae2 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id) ON DELETE CASCADE;
ALTER TABLE rental.contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_contract_id_r_e1bd3927 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_contract_revi_38c909b2 FOREIGN KEY (contract_revision_id) REFERENCES rental.contract_revision (id);
ALTER TABLE rental.contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_party_id_party_party_3 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE rental.contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_channel_id_or_c4886e88 FOREIGN KEY (channel_id) REFERENCES org.channel (id);
ALTER TABLE rental.contract_document ADD CONSTRAINT fk_rental_contract_document_contract_id_rental_re_43cb1a1a FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.contract_document ADD CONSTRAINT fk_rental_contract_document_contract_revision_id__028a9a2f FOREIGN KEY (contract_revision_id) REFERENCES rental.contract_revision (id);
ALTER TABLE rental.digital_pickup_session ADD CONSTRAINT fk_rental_digital_pickup_session_contract_id_rent_6042c3a6 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.digital_pickup_session ADD CONSTRAINT fk_rental_digital_pickup_session_reservation_id_r_62d0440f FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE rental.digital_pickup_session ADD CONSTRAINT fk_rental_digital_pickup_session_party_id_party_party_3 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE rental.vehicle_access_credential ADD CONSTRAINT fk_rental_vehicle_access_credential_digital_picku_46f920a7 FOREIGN KEY (digital_pickup_session_id) REFERENCES rental.digital_pickup_session (id) ON DELETE CASCADE;
ALTER TABLE rental.vehicle_access_credential ADD CONSTRAINT fk_rental_vehicle_access_credential_vehicle_id_fl_99bba7ba FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE rental.vehicle_access_command ADD CONSTRAINT fk_rental_vehicle_access_command_contract_id_rent_c6361125 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.vehicle_access_command ADD CONSTRAINT fk_rental_vehicle_access_command_vehicle_id_fleet_d6fb9a73 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE rental.overdue_case ADD CONSTRAINT fk_rental_overdue_case_contract_id_rental_rental__ae4039d0 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE rental.contract_reprocessing ADD CONSTRAINT fk_rental_contract_reprocessing_contract_id_renta_9b6f3d24 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.inspection_template_item ADD CONSTRAINT fk_inspection_inspection_template_item_inspection_4789f1b9 FOREIGN KEY (inspection_template_id) REFERENCES inspection.inspection_template (id) ON DELETE CASCADE;
ALTER TABLE inspection.inspection ADD CONSTRAINT fk_inspection_inspection_inspection_template_id_i_172a4ce8 FOREIGN KEY (inspection_template_id) REFERENCES inspection.inspection_template (id);
ALTER TABLE inspection.inspection ADD CONSTRAINT fk_inspection_inspection_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE inspection.inspection ADD CONSTRAINT fk_inspection_inspection_contract_id_rental_renta_0b054e85 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.inspection ADD CONSTRAINT fk_inspection_inspection_vehicle_assignment_id_re_7bace524 FOREIGN KEY (vehicle_assignment_id) REFERENCES rental.vehicle_assignment (id);
ALTER TABLE inspection.inspection ADD CONSTRAINT fk_inspection_inspection_branch_id_org_branch_5 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE inspection.inspection_item_result ADD CONSTRAINT fk_inspection_inspection_item_result_inspection_i_df07a250 FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id) ON DELETE CASCADE;
ALTER TABLE inspection.inspection_item_result ADD CONSTRAINT fk_inspection_inspection_item_result_template_ite_30e0aa67 FOREIGN KEY (template_item_id) REFERENCES inspection.inspection_template_item (id);
ALTER TABLE inspection.inspection_media ADD CONSTRAINT fk_inspection_inspection_media_inspection_id_insp_4f1df40c FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id) ON DELETE CASCADE;
ALTER TABLE inspection.inspection_media ADD CONSTRAINT fk_inspection_inspection_media_template_item_id_i_383e7e81 FOREIGN KEY (template_item_id) REFERENCES inspection.inspection_template_item (id);
ALTER TABLE inspection.damage_record ADD CONSTRAINT fk_inspection_damage_record_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE inspection.damage_observation ADD CONSTRAINT fk_inspection_damage_observation_damage_record_id_35f8b591 FOREIGN KEY (damage_record_id) REFERENCES inspection.damage_record (id);
ALTER TABLE inspection.damage_observation ADD CONSTRAINT fk_inspection_damage_observation_inspection_id_in_b73d6c3e FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id);
ALTER TABLE inspection.damage_observation ADD CONSTRAINT fk_inspection_damage_observation_media_id_inspect_1467b661 FOREIGN KEY (media_id) REFERENCES inspection.inspection_media (id);
ALTER TABLE inspection.damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_damage_record_id_d0058bd5 FOREIGN KEY (damage_record_id) REFERENCES inspection.damage_record (id);
ALTER TABLE inspection.damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_contract_id_rent_1385d531 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_incident_id_clai_51e7cae7 FOREIGN KEY (incident_id) REFERENCES claim.incident (id);
ALTER TABLE inspection.damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_responsible_part_e94686dd FOREIGN KEY (responsible_party_id) REFERENCES party.party (id);
ALTER TABLE inspection.damage_assessment ADD CONSTRAINT fk_inspection_damage_assessment_damage_record_id__74e2d0dd FOREIGN KEY (damage_record_id) REFERENCES inspection.damage_record (id);
ALTER TABLE inspection.damage_assessment ADD CONSTRAINT fk_inspection_damage_assessment_contract_id_renta_b985876a FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.damage_assessment ADD CONSTRAINT fk_inspection_damage_assessment_assessor_party_id_12b10a8c FOREIGN KEY (assessor_party_id) REFERENCES party.party (id);
ALTER TABLE inspection.fuel_assessment ADD CONSTRAINT fk_inspection_fuel_assessment_inspection_id_inspe_07b8dc0b FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id);
ALTER TABLE inspection.fuel_assessment ADD CONSTRAINT fk_inspection_fuel_assessment_contract_id_rental__c914b49c FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.fuel_assessment ADD CONSTRAINT fk_inspection_fuel_assessment_fuel_price_id_prici_004ccc7b FOREIGN KEY (fuel_price_id) REFERENCES pricing.fuel_price (id);
ALTER TABLE inspection.cleaning_assessment ADD CONSTRAINT fk_inspection_cleaning_assessment_inspection_id_i_e93b9ede FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id);
ALTER TABLE inspection.cleaning_assessment ADD CONSTRAINT fk_inspection_cleaning_assessment_contract_id_ren_fa85d3a9 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.lost_found_item ADD CONSTRAINT fk_inspection_lost_found_item_inspection_id_inspe_b4209e8c FOREIGN KEY (inspection_id) REFERENCES inspection.inspection (id);
ALTER TABLE inspection.lost_found_item ADD CONSTRAINT fk_inspection_lost_found_item_contract_id_rental__80aee175 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE inspection.lost_found_item ADD CONSTRAINT fk_inspection_lost_found_item_released_to_party_i_c84510ac FOREIGN KEY (released_to_party_id) REFERENCES party.party (id);
ALTER TABLE billing.payment_method_token ADD CONSTRAINT fk_billing_payment_method_token_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE billing.payment_method_token ADD CONSTRAINT fk_billing_payment_method_token_billing_address_i_fce0e31e FOREIGN KEY (billing_address_id) REFERENCES party.postal_address (id);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_contract_id_rental_rental_contract_2 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_reservation_id_reservation_reservation_3 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_charge_type_id_catalog_charge_type_4 FOREIGN KEY (charge_type_id) REFERENCES catalog.charge_type (id);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_unit_code_catalog_unit_of_measure_5 FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_rate_plan_version_id_pricing_ra_9152308f FOREIGN KEY (rate_plan_version_id) REFERENCES pricing.rate_plan_version (id);
ALTER TABLE billing.charge ADD CONSTRAINT fk_billing_charge_reversal_of_charge_id_billing_charge_7 FOREIGN KEY (reversal_of_charge_id) REFERENCES billing.charge (id);
ALTER TABLE billing.invoice ADD CONSTRAINT fk_billing_invoice_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE billing.invoice ADD CONSTRAINT fk_billing_invoice_customer_account_id_party_cust_c255ffac FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE billing.invoice ADD CONSTRAINT fk_billing_invoice_billing_party_id_party_party_3 FOREIGN KEY (billing_party_id) REFERENCES party.party (id);
ALTER TABLE billing.invoice ADD CONSTRAINT fk_billing_invoice_contract_id_rental_rental_contract_4 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE billing.invoice ADD CONSTRAINT fk_billing_invoice_corporate_agreement_id_corpora_51f3c93f FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id);
ALTER TABLE billing.invoice ADD CONSTRAINT fk_billing_invoice_supersedes_invoice_id_billing_invoice_6 FOREIGN KEY (supersedes_invoice_id) REFERENCES billing.invoice (id);
ALTER TABLE billing.invoice_line ADD CONSTRAINT fk_billing_invoice_line_invoice_id_billing_invoice_1 FOREIGN KEY (invoice_id) REFERENCES billing.invoice (id) ON DELETE CASCADE;
ALTER TABLE billing.invoice_line ADD CONSTRAINT fk_billing_invoice_line_charge_id_billing_charge_2 FOREIGN KEY (charge_id) REFERENCES billing.charge (id);
ALTER TABLE billing.receivable ADD CONSTRAINT fk_billing_receivable_invoice_id_billing_invoice_1 FOREIGN KEY (invoice_id) REFERENCES billing.invoice (id);
ALTER TABLE billing.payment_intent ADD CONSTRAINT fk_billing_payment_intent_legal_entity_id_org_leg_84e570ef FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE billing.payment_intent ADD CONSTRAINT fk_billing_payment_intent_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE billing.payment_intent ADD CONSTRAINT fk_billing_payment_intent_contract_id_rental_rent_94de4098 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE billing.payment_intent ADD CONSTRAINT fk_billing_payment_intent_reservation_id_reservat_ed029fdc FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE billing.payment_intent ADD CONSTRAINT fk_billing_payment_intent_receivable_id_billing_r_96e121cd FOREIGN KEY (receivable_id) REFERENCES billing.receivable (id);
ALTER TABLE billing.payment_intent ADD CONSTRAINT fk_billing_payment_intent_payment_method_token_id_49b5bb17 FOREIGN KEY (payment_method_token_id) REFERENCES billing.payment_method_token (id);
ALTER TABLE billing.payment_transaction ADD CONSTRAINT fk_billing_payment_transaction_payment_intent_id__549db615 FOREIGN KEY (payment_intent_id) REFERENCES billing.payment_intent (id);
ALTER TABLE billing.payment_allocation ADD CONSTRAINT fk_billing_payment_allocation_payment_transaction_e966b684 FOREIGN KEY (payment_transaction_id) REFERENCES billing.payment_transaction (id);
ALTER TABLE billing.payment_allocation ADD CONSTRAINT fk_billing_payment_allocation_receivable_id_billi_424b9336 FOREIGN KEY (receivable_id) REFERENCES billing.receivable (id);
ALTER TABLE billing.payment_allocation ADD CONSTRAINT fk_billing_payment_allocation_reversal_of_allocat_ccb7ea16 FOREIGN KEY (reversal_of_allocation_id) REFERENCES billing.payment_allocation (id);
ALTER TABLE billing.preauthorization ADD CONSTRAINT fk_billing_preauthorization_payment_method_token__f4b79f0d FOREIGN KEY (payment_method_token_id) REFERENCES billing.payment_method_token (id);
ALTER TABLE billing.preauthorization ADD CONSTRAINT fk_billing_preauthorization_reservation_id_reserv_dfa5eef9 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE billing.preauthorization ADD CONSTRAINT fk_billing_preauthorization_contract_id_rental_re_b9dbdc6b FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE billing.refund ADD CONSTRAINT fk_billing_refund_payment_transaction_id_billing__ab3a86a0 FOREIGN KEY (payment_transaction_id) REFERENCES billing.payment_transaction (id);
ALTER TABLE billing.refund ADD CONSTRAINT fk_billing_refund_refund_transaction_id_billing_p_fed5ce2f FOREIGN KEY (refund_transaction_id) REFERENCES billing.payment_transaction (id);
ALTER TABLE billing.credit_note ADD CONSTRAINT fk_billing_credit_note_invoice_id_billing_invoice_1 FOREIGN KEY (invoice_id) REFERENCES billing.invoice (id);
ALTER TABLE billing.credit_note ADD CONSTRAINT fk_billing_credit_note_tax_document_id_billing_ta_e623e1ff FOREIGN KEY (tax_document_id) REFERENCES billing.tax_document (id);
ALTER TABLE billing.chargeback ADD CONSTRAINT fk_billing_chargeback_payment_transaction_id_bill_617288cb FOREIGN KEY (payment_transaction_id) REFERENCES billing.payment_transaction (id);
ALTER TABLE billing.tax_document ADD CONSTRAINT fk_billing_tax_document_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE billing.tax_document ADD CONSTRAINT fk_billing_tax_document_invoice_id_billing_invoice_2 FOREIGN KEY (invoice_id) REFERENCES billing.invoice (id);
ALTER TABLE billing.dunning_case ADD CONSTRAINT fk_billing_dunning_case_customer_account_id_party_1ee48f6c FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE billing.dunning_case ADD CONSTRAINT fk_billing_dunning_case_receivable_id_billing_receivable_2 FOREIGN KEY (receivable_id) REFERENCES billing.receivable (id);
ALTER TABLE billing.collection_action ADD CONSTRAINT fk_billing_collection_action_dunning_case_id_bill_29a97fd7 FOREIGN KEY (dunning_case_id) REFERENCES billing.dunning_case (id) ON DELETE CASCADE;
ALTER TABLE billing.settlement_item ADD CONSTRAINT fk_billing_settlement_item_settlement_batch_id_bi_8acdd183 FOREIGN KEY (settlement_batch_id) REFERENCES billing.settlement_batch (id) ON DELETE CASCADE;
ALTER TABLE billing.settlement_item ADD CONSTRAINT fk_billing_settlement_item_payment_transaction_id_179e8096 FOREIGN KEY (payment_transaction_id) REFERENCES billing.payment_transaction (id);
ALTER TABLE billing.reconciliation_issue ADD CONSTRAINT fk_billing_reconciliation_issue_settlement_item_i_89e1c65e FOREIGN KEY (settlement_item_id) REFERENCES billing.settlement_item (id);
ALTER TABLE billing.accounting_export ADD CONSTRAINT fk_billing_accounting_export_legal_entity_id_org__8aef407b FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE traffic.traffic_notice ADD CONSTRAINT fk_traffic_traffic_notice_import_batch_id_traffic_a726f841 FOREIGN KEY (import_batch_id) REFERENCES traffic.provider_import_batch (id);
ALTER TABLE traffic.traffic_notice ADD CONSTRAINT fk_traffic_traffic_notice_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE traffic.traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_traffic_notice_id__782e6e40 FOREIGN KEY (traffic_notice_id) REFERENCES traffic.traffic_notice (id);
ALTER TABLE traffic.traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_contract_id_rental_bebc0978 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE traffic.traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_vehicle_assignment_8896b457 FOREIGN KEY (vehicle_assignment_id) REFERENCES rental.vehicle_assignment (id);
ALTER TABLE traffic.traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_driver_profile_id__9fd23c6a FOREIGN KEY (driver_profile_id) REFERENCES party.driver_profile (id);
ALTER TABLE traffic.driver_nomination ADD CONSTRAINT fk_traffic_driver_nomination_traffic_notice_id_tr_c246b814 FOREIGN KEY (traffic_notice_id) REFERENCES traffic.traffic_notice (id);
ALTER TABLE traffic.driver_nomination ADD CONSTRAINT fk_traffic_driver_nomination_driver_profile_id_pa_8c032902 FOREIGN KEY (driver_profile_id) REFERENCES party.driver_profile (id);
ALTER TABLE traffic.traffic_appeal ADD CONSTRAINT fk_traffic_traffic_appeal_traffic_notice_id_traff_95bfe0ab FOREIGN KEY (traffic_notice_id) REFERENCES traffic.traffic_notice (id);
ALTER TABLE traffic.toll_tag ADD CONSTRAINT fk_traffic_toll_tag_owning_legal_entity_id_org_le_3e9b62ec FOREIGN KEY (owning_legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE traffic.toll_tag_assignment ADD CONSTRAINT fk_traffic_toll_tag_assignment_toll_tag_id_traffi_a47fea74 FOREIGN KEY (toll_tag_id) REFERENCES traffic.toll_tag (id);
ALTER TABLE traffic.toll_tag_assignment ADD CONSTRAINT fk_traffic_toll_tag_assignment_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE traffic.toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_import_batch_id_traff_a8f71b6b FOREIGN KEY (import_batch_id) REFERENCES traffic.provider_import_batch (id);
ALTER TABLE traffic.toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_toll_tag_id_traffic_toll_tag_2 FOREIGN KEY (toll_tag_id) REFERENCES traffic.toll_tag (id);
ALTER TABLE traffic.toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_vehicle_id_fleet_vehicle_3 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE traffic.toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_contract_id_rental_re_3e506932 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE traffic.parking_transaction ADD CONSTRAINT fk_traffic_parking_transaction_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE traffic.parking_transaction ADD CONSTRAINT fk_traffic_parking_transaction_contract_id_rental_394386e9 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE traffic.traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_traffic_notice_id__fe7dacda FOREIGN KEY (traffic_notice_id) REFERENCES traffic.traffic_notice (id);
ALTER TABLE traffic.traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_toll_transaction_i_fa1b5a73 FOREIGN KEY (toll_transaction_id) REFERENCES traffic.toll_transaction (id);
ALTER TABLE traffic.traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_parking_transactio_53fd31f9 FOREIGN KEY (parking_transaction_id) REFERENCES traffic.parking_transaction (id);
ALTER TABLE traffic.traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_charge_id_billing_charge_4 FOREIGN KEY (charge_id) REFERENCES billing.charge (id);
ALTER TABLE claim.insurance_policy ADD CONSTRAINT fk_claim_insurance_policy_legal_entity_id_org_leg_b729ad96 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE claim.insurance_policy ADD CONSTRAINT fk_claim_insurance_policy_insurer_party_id_party__e07c11cb FOREIGN KEY (insurer_party_id) REFERENCES party.organization (party_id);
ALTER TABLE claim.policy_coverage ADD CONSTRAINT fk_claim_policy_coverage_insurance_policy_id_clai_f2a0e554 FOREIGN KEY (insurance_policy_id) REFERENCES claim.insurance_policy (id) ON DELETE CASCADE;
ALTER TABLE claim.policy_coverage ADD CONSTRAINT fk_claim_policy_coverage_coverage_id_catalog_coverage_2 FOREIGN KEY (coverage_id) REFERENCES catalog.coverage (id);
ALTER TABLE claim.incident ADD CONSTRAINT fk_claim_incident_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE claim.incident ADD CONSTRAINT fk_claim_incident_contract_id_rental_rental_contract_2 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE claim.incident_party ADD CONSTRAINT fk_claim_incident_party_incident_id_claim_incident_1 FOREIGN KEY (incident_id) REFERENCES claim.incident (id) ON DELETE CASCADE;
ALTER TABLE claim.incident_party ADD CONSTRAINT fk_claim_incident_party_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE claim.incident_vehicle ADD CONSTRAINT fk_claim_incident_vehicle_incident_id_claim_incident_1 FOREIGN KEY (incident_id) REFERENCES claim.incident (id) ON DELETE CASCADE;
ALTER TABLE claim.incident_vehicle ADD CONSTRAINT fk_claim_incident_vehicle_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE claim.incident_document ADD CONSTRAINT fk_claim_incident_document_incident_id_claim_incident_1 FOREIGN KEY (incident_id) REFERENCES claim.incident (id) ON DELETE CASCADE;
ALTER TABLE claim.claim ADD CONSTRAINT fk_claim_claim_incident_id_claim_incident_1 FOREIGN KEY (incident_id) REFERENCES claim.incident (id);
ALTER TABLE claim.claim ADD CONSTRAINT fk_claim_claim_insurance_policy_id_claim_insuranc_4c9269f4 FOREIGN KEY (insurance_policy_id) REFERENCES claim.insurance_policy (id);
ALTER TABLE claim.claim ADD CONSTRAINT fk_claim_claim_contract_id_rental_rental_contract_3 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE claim.claim_coverage_decision ADD CONSTRAINT fk_claim_claim_coverage_decision_claim_id_claim_claim_1 FOREIGN KEY (claim_id) REFERENCES claim.claim (id) ON DELETE CASCADE;
ALTER TABLE claim.claim_coverage_decision ADD CONSTRAINT fk_claim_claim_coverage_decision_coverage_id_cata_70121be9 FOREIGN KEY (coverage_id) REFERENCES catalog.coverage (id);
ALTER TABLE claim.claim_cost ADD CONSTRAINT fk_claim_claim_cost_claim_id_claim_claim_1 FOREIGN KEY (claim_id) REFERENCES claim.claim (id) ON DELETE CASCADE;
ALTER TABLE claim.claim_cost ADD CONSTRAINT fk_claim_claim_cost_supplier_party_id_party_organization_2 FOREIGN KEY (supplier_party_id) REFERENCES party.organization (party_id);
ALTER TABLE claim.third_party_claim ADD CONSTRAINT fk_claim_third_party_claim_claim_id_claim_claim_1 FOREIGN KEY (claim_id) REFERENCES claim.claim (id);
ALTER TABLE claim.third_party_claim ADD CONSTRAINT fk_claim_third_party_claim_third_party_id_party_party_2 FOREIGN KEY (third_party_id) REFERENCES party.party (id);
ALTER TABLE claim.recovery_case ADD CONSTRAINT fk_claim_recovery_case_claim_id_claim_claim_1 FOREIGN KEY (claim_id) REFERENCES claim.claim (id);
ALTER TABLE claim.recovery_case ADD CONSTRAINT fk_claim_recovery_case_responsible_party_id_party_party_2 FOREIGN KEY (responsible_party_id) REFERENCES party.party (id);
ALTER TABLE claim.roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_incident_id_cla_b8bf19f7 FOREIGN KEY (incident_id) REFERENCES claim.incident (id);
ALTER TABLE claim.roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_contract_id_ren_391d5ed1 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE claim.roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_vehicle_id_flee_cce0f0dd FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE claim.roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_provider_party__8ec2f39c FOREIGN KEY (provider_party_id) REFERENCES party.organization (party_id);
ALTER TABLE maintenance.maintenance_plan ADD CONSTRAINT fk_maintenance_maintenance_plan_vehicle_variant_i_47d12681 FOREIGN KEY (vehicle_variant_id) REFERENCES catalog.vehicle_variant (id);
ALTER TABLE maintenance.maintenance_rule ADD CONSTRAINT fk_maintenance_maintenance_rule_maintenance_plan__24974bfd FOREIGN KEY (maintenance_plan_id) REFERENCES maintenance.maintenance_plan (id) ON DELETE CASCADE;
ALTER TABLE maintenance.maintenance_due ADD CONSTRAINT fk_maintenance_maintenance_due_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE maintenance.maintenance_due ADD CONSTRAINT fk_maintenance_maintenance_due_maintenance_rule_i_b6eb59c7 FOREIGN KEY (maintenance_rule_id) REFERENCES maintenance.maintenance_rule (id);
ALTER TABLE maintenance.maintenance_due ADD CONSTRAINT fk_maintenance_maintenance_due_service_order_id_m_e2bdd15e FOREIGN KEY (service_order_id) REFERENCES maintenance.service_order (id);
ALTER TABLE maintenance.vendor ADD CONSTRAINT fk_maintenance_vendor_party_id_party_organization_1 FOREIGN KEY (party_id) REFERENCES party.organization (party_id);
ALTER TABLE maintenance.workshop ADD CONSTRAINT fk_maintenance_workshop_vendor_id_maintenance_vendor_1 FOREIGN KEY (vendor_id) REFERENCES maintenance.vendor (id);
ALTER TABLE maintenance.workshop ADD CONSTRAINT fk_maintenance_workshop_branch_id_org_branch_2 FOREIGN KEY (branch_id) REFERENCES org.branch (id);
ALTER TABLE maintenance.workshop ADD CONSTRAINT fk_maintenance_workshop_address_id_party_postal_address_3 FOREIGN KEY (address_id) REFERENCES party.postal_address (id);
ALTER TABLE maintenance.service_order ADD CONSTRAINT fk_maintenance_service_order_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE maintenance.service_order ADD CONSTRAINT fk_maintenance_service_order_workshop_id_maintena_9e44837d FOREIGN KEY (workshop_id) REFERENCES maintenance.workshop (id);
ALTER TABLE maintenance.service_order ADD CONSTRAINT fk_maintenance_service_order_calendar_entry_id_fl_636430da FOREIGN KEY (calendar_entry_id) REFERENCES fleet.vehicle_calendar_entry (id);
ALTER TABLE maintenance.service_order_item ADD CONSTRAINT fk_maintenance_service_order_item_service_order_i_e353e5ea FOREIGN KEY (service_order_id) REFERENCES maintenance.service_order (id) ON DELETE CASCADE;
ALTER TABLE maintenance.part ADD CONSTRAINT fk_maintenance_part_unit_code_catalog_unit_of_measure_1 FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE maintenance.service_order_part ADD CONSTRAINT fk_maintenance_service_order_part_service_order_i_f2949983 FOREIGN KEY (service_order_item_id) REFERENCES maintenance.service_order_item (id) ON DELETE CASCADE;
ALTER TABLE maintenance.service_order_part ADD CONSTRAINT fk_maintenance_service_order_part_part_id_mainten_d32bf07d FOREIGN KEY (part_id) REFERENCES maintenance.part (id);
ALTER TABLE maintenance.vehicle_recall ADD CONSTRAINT fk_maintenance_vehicle_recall_recall_campaign_id__add3886a FOREIGN KEY (recall_campaign_id) REFERENCES maintenance.recall_campaign (id);
ALTER TABLE maintenance.vehicle_recall ADD CONSTRAINT fk_maintenance_vehicle_recall_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE maintenance.vehicle_recall ADD CONSTRAINT fk_maintenance_vehicle_recall_service_order_id_ma_61066ba2 FOREIGN KEY (service_order_id) REFERENCES maintenance.service_order (id);
ALTER TABLE maintenance.tire_assignment ADD CONSTRAINT fk_maintenance_tire_assignment_tire_id_maintenance_tire_1 FOREIGN KEY (tire_id) REFERENCES maintenance.tire (id);
ALTER TABLE maintenance.tire_assignment ADD CONSTRAINT fk_maintenance_tire_assignment_vehicle_id_fleet_vehicle_2 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE maintenance.downtime ADD CONSTRAINT fk_maintenance_downtime_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE maintenance.downtime ADD CONSTRAINT fk_maintenance_downtime_service_order_id_maintena_89dc7a01 FOREIGN KEY (service_order_id) REFERENCES maintenance.service_order (id);
ALTER TABLE maintenance.downtime ADD CONSTRAINT fk_maintenance_downtime_calendar_entry_id_fleet_v_dd9edc03 FOREIGN KEY (calendar_entry_id) REFERENCES fleet.vehicle_calendar_entry (id);
ALTER TABLE telematics.device ADD CONSTRAINT fk_telematics_device_provider_id_telematics_provider_1 FOREIGN KEY (provider_id) REFERENCES telematics.provider (id);
ALTER TABLE telematics.vehicle_device_assignment ADD CONSTRAINT fk_telematics_vehicle_device_assignment_device_id_ce15a595 FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.vehicle_device_assignment ADD CONSTRAINT fk_telematics_vehicle_device_assignment_vehicle_i_306d67ea FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE telematics.device_health_event ADD CONSTRAINT fk_telematics_device_health_event_device_id_telem_8e6cc4aa FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.telemetry_event_index ADD CONSTRAINT fk_telematics_telemetry_event_index_device_id_tel_3df1e8c3 FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.telemetry_event_index ADD CONSTRAINT fk_telematics_telemetry_event_index_vehicle_id_fl_e10ed6b1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE telematics.trip_summary ADD CONSTRAINT fk_telematics_trip_summary_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE telematics.trip_summary ADD CONSTRAINT fk_telematics_trip_summary_device_id_telematics_device_2 FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.trip_summary ADD CONSTRAINT fk_telematics_trip_summary_contract_id_rental_ren_55c02804 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE telematics.driving_event ADD CONSTRAINT fk_telematics_driving_event_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE telematics.driving_event ADD CONSTRAINT fk_telematics_driving_event_device_id_telematics_device_2 FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.driving_event ADD CONSTRAINT fk_telematics_driving_event_contract_id_rental_re_352e0bc4 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE telematics.driving_event ADD CONSTRAINT fk_telematics_driving_event_trip_summary_id_telem_edc7cc20 FOREIGN KEY (trip_summary_id) REFERENCES telematics.trip_summary (id);
ALTER TABLE telematics.geofence_event ADD CONSTRAINT fk_telematics_geofence_event_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE telematics.geofence_event ADD CONSTRAINT fk_telematics_geofence_event_device_id_telematics_device_2 FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.geofence_event ADD CONSTRAINT fk_telematics_geofence_event_geofence_id_telemati_09f4a4a4 FOREIGN KEY (geofence_id) REFERENCES telematics.geofence (id);
ALTER TABLE telematics.geofence_event ADD CONSTRAINT fk_telematics_geofence_event_contract_id_rental_r_831b6d1a FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE telematics.vehicle_command ADD CONSTRAINT fk_telematics_vehicle_command_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE telematics.vehicle_command ADD CONSTRAINT fk_telematics_vehicle_command_device_id_telematic_553167d6 FOREIGN KEY (device_id) REFERENCES telematics.device (id);
ALTER TABLE telematics.vehicle_command ADD CONSTRAINT fk_telematics_vehicle_command_contract_id_rental__9d1e4164 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE telematics.command_result ADD CONSTRAINT fk_telematics_command_result_vehicle_command_id_t_12fde95b FOREIGN KEY (vehicle_command_id) REFERENCES telematics.vehicle_command (id) ON DELETE CASCADE;
ALTER TABLE loyalty.loyalty_account ADD CONSTRAINT fk_loyalty_loyalty_account_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE loyalty.loyalty_account ADD CONSTRAINT fk_loyalty_loyalty_account_current_tier_id_loyalt_fc0c485d FOREIGN KEY (current_tier_id) REFERENCES loyalty.loyalty_tier (id);
ALTER TABLE loyalty.tier_rule_version ADD CONSTRAINT fk_loyalty_tier_rule_version_loyalty_tier_id_loya_6e5f4229 FOREIGN KEY (loyalty_tier_id) REFERENCES loyalty.loyalty_tier (id) ON DELETE CASCADE;
ALTER TABLE loyalty.tier_history ADD CONSTRAINT fk_loyalty_tier_history_loyalty_account_id_loyalt_31dc7dd5 FOREIGN KEY (loyalty_account_id) REFERENCES loyalty.loyalty_account (id) ON DELETE CASCADE;
ALTER TABLE loyalty.tier_history ADD CONSTRAINT fk_loyalty_tier_history_loyalty_tier_id_loyalty_l_ac4642b9 FOREIGN KEY (loyalty_tier_id) REFERENCES loyalty.loyalty_tier (id);
ALTER TABLE loyalty.tier_history ADD CONSTRAINT fk_loyalty_tier_history_rule_version_id_loyalty_t_92fb18ca FOREIGN KEY (rule_version_id) REFERENCES loyalty.tier_rule_version (id);
ALTER TABLE loyalty.points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_loyalty_account_id_loyal_75638ffa FOREIGN KEY (loyalty_account_id) REFERENCES loyalty.loyalty_account (id);
ALTER TABLE loyalty.points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_earning_rule_id_loyalty__0e0ef5fe FOREIGN KEY (earning_rule_id) REFERENCES loyalty.earning_rule (id);
ALTER TABLE loyalty.points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_redemption_rule_id_loyal_430eb7e4 FOREIGN KEY (redemption_rule_id) REFERENCES loyalty.redemption_rule (id);
ALTER TABLE loyalty.points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_reversal_of_entry_id_loy_0187f35d FOREIGN KEY (reversal_of_entry_id) REFERENCES loyalty.points_ledger (id);
ALTER TABLE loyalty.points_lot ADD CONSTRAINT fk_loyalty_points_lot_loyalty_account_id_loyalty__2a81d62d FOREIGN KEY (loyalty_account_id) REFERENCES loyalty.loyalty_account (id);
ALTER TABLE loyalty.points_lot ADD CONSTRAINT fk_loyalty_points_lot_origin_ledger_entry_id_loya_b3419dde FOREIGN KEY (origin_ledger_entry_id) REFERENCES loyalty.points_ledger (id);
ALTER TABLE loyalty.redemption ADD CONSTRAINT fk_loyalty_redemption_loyalty_account_id_loyalty__12ce29ca FOREIGN KEY (loyalty_account_id) REFERENCES loyalty.loyalty_account (id);
ALTER TABLE loyalty.redemption ADD CONSTRAINT fk_loyalty_redemption_reservation_id_reservation__1a2b8fbe FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE loyalty.redemption ADD CONSTRAINT fk_loyalty_redemption_contract_id_rental_rental_contract_3 FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE loyalty.redemption_allocation ADD CONSTRAINT fk_loyalty_redemption_allocation_redemption_id_lo_b939e147 FOREIGN KEY (redemption_id) REFERENCES loyalty.redemption (id) ON DELETE CASCADE;
ALTER TABLE loyalty.redemption_allocation ADD CONSTRAINT fk_loyalty_redemption_allocation_points_lot_id_lo_ca77ab36 FOREIGN KEY (points_lot_id) REFERENCES loyalty.points_lot (id);
ALTER TABLE loyalty.benefit_entitlement ADD CONSTRAINT fk_loyalty_benefit_entitlement_loyalty_account_id_19c9ed67 FOREIGN KEY (loyalty_account_id) REFERENCES loyalty.loyalty_account (id);
ALTER TABLE loyalty.benefit_entitlement ADD CONSTRAINT fk_loyalty_benefit_entitlement_benefit_id_loyalty_63e3163a FOREIGN KEY (benefit_id) REFERENCES loyalty.benefit (id);
ALTER TABLE loyalty.benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_benefit_entitlement_id_l_473b2eb8 FOREIGN KEY (benefit_entitlement_id) REFERENCES loyalty.benefit_entitlement (id);
ALTER TABLE loyalty.benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_reservation_id_reservati_ea12cae2 FOREIGN KEY (reservation_id) REFERENCES reservation.reservation (id);
ALTER TABLE loyalty.benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_contract_id_rental_renta_c45f74fd FOREIGN KEY (contract_id) REFERENCES rental.rental_contract (id);
ALTER TABLE loyalty.benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_reversal_of_usage_id_loy_161c2c87 FOREIGN KEY (reversal_of_usage_id) REFERENCES loyalty.benefit_usage (id);
ALTER TABLE loyalty.points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_from_account_id_loyalt_36d9a91a FOREIGN KEY (from_account_id) REFERENCES loyalty.loyalty_account (id);
ALTER TABLE loyalty.points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_to_account_id_loyalty__08fd9e1c FOREIGN KEY (to_account_id) REFERENCES loyalty.loyalty_account (id);
ALTER TABLE loyalty.points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_out_ledger_entry_id_lo_6f1855ad FOREIGN KEY (out_ledger_entry_id) REFERENCES loyalty.points_ledger (id);
ALTER TABLE loyalty.points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_in_ledger_entry_id_loy_f12f28fa FOREIGN KEY (in_ledger_entry_id) REFERENCES loyalty.points_ledger (id);
ALTER TABLE fleet_mgmt.fleet_service_contract ADD CONSTRAINT fk_fleet_mgmt_fleet_service_contract_legal_entity_0449c228 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE fleet_mgmt.fleet_service_contract ADD CONSTRAINT fk_fleet_mgmt_fleet_service_contract_customer_acc_6cd72fad FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE fleet_mgmt.fleet_service_contract ADD CONSTRAINT fk_fleet_mgmt_fleet_service_contract_corporate_ag_62ad139e FOREIGN KEY (corporate_agreement_id) REFERENCES corporate.corporate_agreement (id);
ALTER TABLE fleet_mgmt.fleet_service_level ADD CONSTRAINT fk_fleet_mgmt_fleet_service_level_fleet_service_c_0b1cf43a FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt.fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt.fleet_service_level ADD CONSTRAINT fk_fleet_mgmt_fleet_service_level_unit_code_catal_ecc953d1 FOREIGN KEY (unit_code) REFERENCES catalog.unit_of_measure (unit_code);
ALTER TABLE fleet_mgmt.managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_fleet_se_78391358 FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt.fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt.managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_vehicle__ca7d7e43 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet_mgmt.managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_assigned_4783c88b FOREIGN KEY (assigned_driver_profile_id) REFERENCES party.driver_profile (id);
ALTER TABLE fleet_mgmt.managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_cost_cen_e312d0a4 FOREIGN KEY (cost_center_id) REFERENCES corporate.corporate_cost_center (id);
ALTER TABLE fleet_mgmt.mileage_commitment ADD CONSTRAINT fk_fleet_mgmt_mileage_commitment_fleet_service_co_68e442e1 FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt.fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt.mileage_commitment ADD CONSTRAINT fk_fleet_mgmt_mileage_commitment_vehicle_id_fleet_66ce1962 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet_mgmt.telemetry_package ADD CONSTRAINT fk_fleet_mgmt_telemetry_package_fleet_service_con_f3f1712e FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt.fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt.replacement_entitlement ADD CONSTRAINT fk_fleet_mgmt_replacement_entitlement_fleet_servi_8f99ffc4 FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt.fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt.replacement_entitlement ADD CONSTRAINT fk_fleet_mgmt_replacement_entitlement_vehicle_gro_bcba57c9 FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE fleet_mgmt.fleet_service_event ADD CONSTRAINT fk_fleet_mgmt_fleet_service_event_fleet_service_c_3b809512 FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt.fleet_service_contract (id);
ALTER TABLE fleet_mgmt.fleet_service_event ADD CONSTRAINT fk_fleet_mgmt_fleet_service_event_vehicle_id_flee_72acf7be FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet_mgmt.subscription_plan ADD CONSTRAINT fk_fleet_mgmt_subscription_plan_vehicle_group_id__7c4c492d FOREIGN KEY (vehicle_group_id) REFERENCES catalog.vehicle_group (id);
ALTER TABLE fleet_mgmt.subscription_contract ADD CONSTRAINT fk_fleet_mgmt_subscription_contract_subscription__8a13a360 FOREIGN KEY (subscription_plan_id) REFERENCES fleet_mgmt.subscription_plan (id);
ALTER TABLE fleet_mgmt.subscription_contract ADD CONSTRAINT fk_fleet_mgmt_subscription_contract_customer_acco_ad7cb737 FOREIGN KEY (customer_account_id) REFERENCES party.customer_account (id);
ALTER TABLE fleet_mgmt.subscription_contract ADD CONSTRAINT fk_fleet_mgmt_subscription_contract_legal_entity__27036bbf FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE fleet_mgmt.subscription_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_subscription_vehicle_assignment_sub_de7ead13 FOREIGN KEY (subscription_contract_id) REFERENCES fleet_mgmt.subscription_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt.subscription_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_subscription_vehicle_assignment_veh_f9be83d1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE fleet_mgmt.subscription_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_subscription_vehicle_assignment_cal_a88faa6f FOREIGN KEY (calendar_entry_id) REFERENCES fleet.vehicle_calendar_entry (id);
ALTER TABLE used_car.disposal_candidate ADD CONSTRAINT fk_used_car_disposal_candidate_vehicle_id_fleet_vehicle_1 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE used_car.vehicle_valuation ADD CONSTRAINT fk_used_car_vehicle_valuation_disposal_candidate__16ac4ac3 FOREIGN KEY (disposal_candidate_id) REFERENCES used_car.disposal_candidate (id) ON DELETE CASCADE;
ALTER TABLE used_car.refurbishment_order ADD CONSTRAINT fk_used_car_refurbishment_order_disposal_candidat_a898cea0 FOREIGN KEY (disposal_candidate_id) REFERENCES used_car.disposal_candidate (id);
ALTER TABLE used_car.refurbishment_order ADD CONSTRAINT fk_used_car_refurbishment_order_service_order_id__5174b827 FOREIGN KEY (service_order_id) REFERENCES maintenance.service_order (id);
ALTER TABLE used_car.refurbishment_item ADD CONSTRAINT fk_used_car_refurbishment_item_refurbishment_orde_47a9659e FOREIGN KEY (refurbishment_order_id) REFERENCES used_car.refurbishment_order (id) ON DELETE CASCADE;
ALTER TABLE used_car.listing ADD CONSTRAINT fk_used_car_listing_disposal_candidate_id_used_ca_ff83f2ed FOREIGN KEY (disposal_candidate_id) REFERENCES used_car.disposal_candidate (id);
ALTER TABLE used_car.listing ADD CONSTRAINT fk_used_car_listing_sale_channel_id_used_car_sale_5ba1c5f2 FOREIGN KEY (sale_channel_id) REFERENCES used_car.sale_channel (id);
ALTER TABLE used_car.lead ADD CONSTRAINT fk_used_car_lead_listing_id_used_car_listing_1 FOREIGN KEY (listing_id) REFERENCES used_car.listing (id);
ALTER TABLE used_car.lead ADD CONSTRAINT fk_used_car_lead_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE used_car.test_drive ADD CONSTRAINT fk_used_car_test_drive_lead_id_used_car_lead_1 FOREIGN KEY (lead_id) REFERENCES used_car.lead (id);
ALTER TABLE used_car.test_drive ADD CONSTRAINT fk_used_car_test_drive_listing_id_used_car_listing_2 FOREIGN KEY (listing_id) REFERENCES used_car.listing (id);
ALTER TABLE used_car.test_drive ADD CONSTRAINT fk_used_car_test_drive_driver_profile_id_party_dr_cfd433ad FOREIGN KEY (driver_profile_id) REFERENCES party.driver_profile (id);
ALTER TABLE used_car.sale_order ADD CONSTRAINT fk_used_car_sale_order_legal_entity_id_org_legal_entity_1 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE used_car.sale_order ADD CONSTRAINT fk_used_car_sale_order_buyer_party_id_party_party_2 FOREIGN KEY (buyer_party_id) REFERENCES party.party (id);
ALTER TABLE used_car.sale_order ADD CONSTRAINT fk_used_car_sale_order_sale_channel_id_used_car_s_74c03d06 FOREIGN KEY (sale_channel_id) REFERENCES used_car.sale_channel (id);
ALTER TABLE used_car.sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_sale_order_id_used_def3eb45 FOREIGN KEY (sale_order_id) REFERENCES used_car.sale_order (id) ON DELETE CASCADE;
ALTER TABLE used_car.sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_disposal_candidate_3e572391 FOREIGN KEY (disposal_candidate_id) REFERENCES used_car.disposal_candidate (id);
ALTER TABLE used_car.sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_vehicle_id_fleet_vehicle_3 FOREIGN KEY (vehicle_id) REFERENCES fleet.vehicle (id);
ALTER TABLE used_car.sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_listing_id_used_ca_0ecc8323 FOREIGN KEY (listing_id) REFERENCES used_car.listing (id);
ALTER TABLE used_car.vehicle_transfer ADD CONSTRAINT fk_used_car_vehicle_transfer_sale_order_vehicle_i_13b3f076 FOREIGN KEY (sale_order_vehicle_id) REFERENCES used_car.sale_order_vehicle (id);
ALTER TABLE used_car.vehicle_transfer ADD CONSTRAINT fk_used_car_vehicle_transfer_seller_party_id_party_party_2 FOREIGN KEY (seller_party_id) REFERENCES party.party (id);
ALTER TABLE used_car.vehicle_transfer ADD CONSTRAINT fk_used_car_vehicle_transfer_buyer_party_id_party_party_3 FOREIGN KEY (buyer_party_id) REFERENCES party.party (id);
ALTER TABLE used_car.used_vehicle_warranty ADD CONSTRAINT fk_used_car_used_vehicle_warranty_sale_order_vehi_a729f4c1 FOREIGN KEY (sale_order_vehicle_id) REFERENCES used_car.sale_order_vehicle (id) ON DELETE CASCADE;
ALTER TABLE used_car.sale_document ADD CONSTRAINT fk_used_car_sale_document_sale_order_id_used_car__2ea0cf60 FOREIGN KEY (sale_order_id) REFERENCES used_car.sale_order (id) ON DELETE CASCADE;
ALTER TABLE privacy.privacy_notice_version ADD CONSTRAINT fk_privacy_privacy_notice_version_privacy_notice__ac0b556a FOREIGN KEY (privacy_notice_id) REFERENCES privacy.privacy_notice (id) ON DELETE CASCADE;
ALTER TABLE privacy.legal_basis ADD CONSTRAINT fk_privacy_legal_basis_purpose_id_privacy_process_a07a3266 FOREIGN KEY (purpose_id) REFERENCES privacy.processing_purpose (id);
ALTER TABLE privacy.consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE privacy.consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_privacy_notice_version_a9f735eb FOREIGN KEY (privacy_notice_version_id) REFERENCES privacy.privacy_notice_version (id);
ALTER TABLE privacy.consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_purpose_id_privacy_pro_cd939f31 FOREIGN KEY (purpose_id) REFERENCES privacy.processing_purpose (id);
ALTER TABLE privacy.consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_channel_id_org_channel_4 FOREIGN KEY (channel_id) REFERENCES org.channel (id);
ALTER TABLE privacy.data_subject_request ADD CONSTRAINT fk_privacy_data_subject_request_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE privacy.data_subject_request ADD CONSTRAINT fk_privacy_data_subject_request_channel_id_org_channel_2 FOREIGN KEY (channel_id) REFERENCES org.channel (id);
ALTER TABLE privacy.data_subject_request ADD CONSTRAINT fk_privacy_data_subject_request_identity_verifica_9067215d FOREIGN KEY (identity_verification_id) REFERENCES party.identity_verification (id);
ALTER TABLE privacy.legal_hold ADD CONSTRAINT fk_privacy_legal_hold_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE privacy.erasure_job ADD CONSTRAINT fk_privacy_erasure_job_data_subject_request_id_pr_35b86c5d FOREIGN KEY (data_subject_request_id) REFERENCES privacy.data_subject_request (id);
ALTER TABLE privacy.erasure_job ADD CONSTRAINT fk_privacy_erasure_job_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE privacy.erasure_job ADD CONSTRAINT fk_privacy_erasure_job_blocked_by_legal_hold_id_p_fe8237f5 FOREIGN KEY (blocked_by_legal_hold_id) REFERENCES privacy.legal_hold (id);
ALTER TABLE privacy.data_access_audit ADD CONSTRAINT fk_privacy_data_access_audit_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE privacy.data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party.party (id);
ALTER TABLE privacy.data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_recipient_party_id_fe3eb89a FOREIGN KEY (recipient_party_id) REFERENCES party.party (id);
ALTER TABLE privacy.data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_purpose_id_privacy_303fc290 FOREIGN KEY (purpose_id) REFERENCES privacy.processing_purpose (id);
ALTER TABLE privacy.data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_legal_basis_id_pri_46a287ce FOREIGN KEY (legal_basis_id) REFERENCES privacy.legal_basis (id);
ALTER TABLE integration.saga_step ADD CONSTRAINT fk_integration_saga_step_saga_instance_id_integra_4d884140 FOREIGN KEY (saga_instance_id) REFERENCES integration.saga_instance (id) ON DELETE CASCADE;
ALTER TABLE integration.audit_event ADD CONSTRAINT fk_integration_audit_event_legal_entity_id_org_le_989ccbe0 FOREIGN KEY (legal_entity_id) REFERENCES org.legal_entity (id);
ALTER TABLE integration.audit_event ADD CONSTRAINT fk_integration_audit_event_branch_id_org_branch_2 FOREIGN KEY (branch_id) REFERENCES org.branch (id);

-- --------------------------------------------------------------------------
-- Secondary indexes
-- --------------------------------------------------------------------------
CREATE INDEX ix_org_business_unit_parent_business_unit_id_1 ON org.business_unit (parent_business_unit_id);
CREATE INDEX ix_org_branch_country_code_status_1 ON org.branch (country_code, status);
CREATE INDEX ix_org_branch_airport_code_2 ON org.branch (airport_code);
CREATE INDEX ix_org_branch_operator_branch_id_valid_from_1 ON org.branch_operator (branch_id, valid_from);
CREATE INDEX ix_party_party_canonical_status_1 ON party.party (canonical_status);
CREATE INDEX ix_party_party_identifier_party_id_identifier_type_1 ON party.party_identifier (party_id, identifier_type);
CREATE INDEX ix_party_contact_point_party_id_contact_type_1 ON party.contact_point (party_id, contact_type);
CREATE INDEX ix_party_contact_point_value_hmac_2 ON party.contact_point (value_hmac);
CREATE INDEX ix_party_party_address_party_id_usage_type_1 ON party.party_address (party_id, usage_type);
CREATE INDEX ix_party_customer_account_party_id_1 ON party.customer_account (party_id);
CREATE INDEX ix_party_customer_account_status_2 ON party.customer_account (status);
CREATE INDEX ix_party_organization_representative_organization_673bbd10 ON party.organization_representative (organization_party_id);
CREATE INDEX ix_party_organization_representative_person_party_id_2 ON party.organization_representative (person_party_id);
CREATE INDEX ix_party_driver_license_driver_profile_id_expires_at_1 ON party.driver_license (driver_profile_id, expires_at);
CREATE INDEX ix_party_identity_verification_party_id_verified_at_1 ON party.identity_verification (party_id, verified_at);
CREATE INDEX ix_party_risk_assessment_party_id_assessed_at_1 ON party.risk_assessment (party_id, assessed_at);
CREATE INDEX ix_party_customer_restriction_party_id_status_1 ON party.customer_restriction (party_id, status);
CREATE INDEX ix_catalog_vehicle_variant_model_year_1 ON catalog.vehicle_variant (model_year);
CREATE INDEX ix_catalog_vehicle_group_market_country_code_status_1 ON catalog.vehicle_group (market_country_code, status);
CREATE INDEX ix_catalog_vehicle_group_variant_vehicle_variant__503416be ON catalog.vehicle_group_variant (vehicle_variant_id, valid_from);
CREATE INDEX ix_catalog_vehicle_group_upgrade_from_group_id_priority_1 ON catalog.vehicle_group_upgrade (from_group_id, priority);
CREATE INDEX ix_catalog_commercial_product_product_type_status_1 ON catalog.commercial_product (product_type, status);
CREATE INDEX ix_corporate_corporate_agreement_customer_account_f75ea870 ON corporate.corporate_agreement (customer_account_id, status);
CREATE INDEX ix_fleet_vehicle_current_branch_id_current_vehicl_b582c392 ON fleet.vehicle (current_branch_id, current_vehicle_group_id, current_operational_state);
CREATE INDEX ix_fleet_vehicle_current_lifecycle_state_2 ON fleet.vehicle (current_lifecycle_state);
CREATE INDEX ix_fleet_vehicle_registration_vehicle_id_valid_from_1 ON fleet.vehicle_registration (vehicle_id, valid_from);
CREATE INDEX ix_fleet_vehicle_registration_registration_number_2 ON fleet.vehicle_registration (registration_number);
CREATE INDEX ix_fleet_vehicle_group_assignment_vehicle_group_i_094e1ae6 ON fleet.vehicle_group_assignment (vehicle_group_id, valid_from);
CREATE INDEX ix_fleet_vehicle_operational_state_history_vehicl_5c9e6ef5 ON fleet.vehicle_operational_state_history (vehicle_id, changed_at);
CREATE INDEX ix_fleet_vehicle_lifecycle_history_vehicle_id_changed_at_1 ON fleet.vehicle_lifecycle_history (vehicle_id, changed_at);
CREATE INDEX ix_fleet_vehicle_restriction_vehicle_id_status_1 ON fleet.vehicle_restriction (vehicle_id, status);
CREATE INDEX ix_fleet_vehicle_location_history_vehicle_id_recorded_at_1 ON fleet.vehicle_location_history (vehicle_id, recorded_at);
CREATE INDEX ix_fleet_vehicle_calendar_entry_vehicle_id_start__25052cfa ON fleet.vehicle_calendar_entry (vehicle_id, start_at, end_at);
CREATE INDEX ix_fleet_vehicle_calendar_entry_source_type_source_id_2 ON fleet.vehicle_calendar_entry (source_type, source_id);
CREATE INDEX ix_fleet_odometer_reading_vehicle_id_reading_at_1 ON fleet.odometer_reading (vehicle_id, reading_at);
CREATE INDEX ix_fleet_fuel_reading_vehicle_id_reading_at_1 ON fleet.fuel_reading (vehicle_id, reading_at);
CREATE INDEX ix_fleet_asset_document_vehicle_id_document_type_1 ON fleet.asset_document (vehicle_id, document_type);
CREATE INDEX ix_fleet_vehicle_accessory_assignment_vehicle_id__cb56e5d9 ON fleet.vehicle_accessory_assignment (vehicle_id, start_at);
CREATE INDEX ix_fleet_disposal_eligibility_vehicle_id_evaluated_at_1 ON fleet.disposal_eligibility (vehicle_id, evaluated_at);
CREATE INDEX ix_pricing_rate_plan_version_rate_plan_id_valid_f_cfe91f9e ON pricing.rate_plan_version (rate_plan_id, valid_from, valid_to);
CREATE INDEX ix_pricing_rate_plan_applicability_origin_branch__cea49215 ON pricing.rate_plan_applicability (origin_branch_id, vehicle_group_id, priority);
CREATE INDEX ix_pricing_base_rate_rate_plan_version_id_vehicle_00ee8c12 ON pricing.base_rate (rate_plan_version_id, vehicle_group_id, origin_branch_id, valid_from);
CREATE INDEX ix_pricing_one_way_rule_origin_branch_id_destinat_c15b9004 ON pricing.one_way_rule (origin_branch_id, destination_branch_id, vehicle_group_id, priority);
CREATE INDEX ix_pricing_fuel_price_branch_id_fuel_type_valid_from_1 ON pricing.fuel_price (branch_id, fuel_type, valid_from);
CREATE INDEX ix_pricing_coupon_redemption_coupon_id_party_id_1 ON pricing.coupon_redemption (coupon_id, party_id);
CREATE INDEX ix_pricing_quote_origin_branch_id_vehicle_group_i_76eea0f3 ON pricing.quote (origin_branch_id, vehicle_group_id, planned_pickup_at);
CREATE INDEX ix_pricing_quote_customer_account_id_created_at_2 ON pricing.quote (customer_account_id, created_at);
CREATE INDEX ix_availability_inventory_bucket_local_business_d_b4feeb3c ON availability.inventory_bucket (local_business_date, branch_id);
CREATE INDEX ix_availability_availability_hold_branch_id_vehic_54be950e ON availability.availability_hold (branch_id, vehicle_group_id, start_at, end_at);
CREATE INDEX ix_availability_availability_hold_expires_at_status_2 ON availability.availability_hold (expires_at, status);
CREATE INDEX ix_availability_capacity_commitment_branch_id_veh_3615b9b9 ON availability.capacity_commitment (branch_id, vehicle_group_id, start_at, end_at);
CREATE INDEX ix_availability_capacity_commitment_source_type_s_d14b4be6 ON availability.capacity_commitment (source_type, source_id);
CREATE INDEX ix_availability_upgrade_path_from_group_id_priority_1 ON availability.upgrade_path (from_group_id, priority);
CREATE INDEX ix_availability_fleet_allotment_branch_id_vehicle_6521bb23 ON availability.fleet_allotment (branch_id, vehicle_group_id, start_at);
CREATE INDEX ix_availability_oversell_alert_status_detected_at_1 ON availability.oversell_alert (status, detected_at);
CREATE INDEX ix_reservation_reservation_pickup_branch_id_plann_7fcc49a3 ON reservation.reservation (pickup_branch_id, planned_pickup_at, requested_vehicle_group_id);
CREATE INDEX ix_reservation_reservation_customer_account_id_cr_7d260e6d ON reservation.reservation (customer_account_id, created_at);
CREATE INDEX ix_reservation_reservation_current_status_planned_301ad661 ON reservation.reservation (current_status, planned_pickup_at);
CREATE INDEX ix_reservation_reservation_status_history_reserva_541b9721 ON reservation.reservation_status_history (reservation_id, changed_at);
CREATE INDEX ix_reservation_digital_pickup_eligibility_reserva_d4a372f0 ON reservation.digital_pickup_eligibility (reservation_id, assessed_at);
CREATE INDEX ix_reservation_reservation_inventory_commitment_r_857487d3 ON reservation.reservation_inventory_commitment (reservation_id);
CREATE INDEX ix_reservation_reservation_inventory_commitment_c_789ea5ea ON reservation.reservation_inventory_commitment (capacity_commitment_id);
CREATE INDEX ix_rental_rental_contract_customer_account_id_opened_at_1 ON rental.rental_contract (customer_account_id, opened_at);
CREATE INDEX ix_rental_rental_contract_current_status_planned__5a9f25e5 ON rental.rental_contract (current_status, planned_return_at);
CREATE INDEX ix_rental_rental_contract_origin_branch_id_opened_at_3 ON rental.rental_contract (origin_branch_id, opened_at);
CREATE INDEX ix_rental_contract_party_role_contract_id_role_type_1 ON rental.contract_party_role (contract_id, role_type);
CREATE INDEX ix_rental_vehicle_assignment_vehicle_id_start_at_end_at_1 ON rental.vehicle_assignment (vehicle_id, start_at, end_at);
CREATE INDEX ix_rental_vehicle_assignment_contract_id_status_2 ON rental.vehicle_assignment (contract_id, status);
CREATE INDEX ix_rental_extension_contract_id_requested_at_1 ON rental.extension (contract_id, requested_at);
CREATE INDEX ix_rental_contract_status_history_contract_id_changed_at_1 ON rental.contract_status_history (contract_id, changed_at);
CREATE INDEX ix_rental_contract_document_contract_id_document_type_1 ON rental.contract_document (contract_id, document_type);
CREATE INDEX ix_rental_vehicle_access_command_vehicle_id_requested_at_1 ON rental.vehicle_access_command (vehicle_id, requested_at);
CREATE INDEX ix_inspection_inspection_vehicle_id_started_at_1 ON inspection.inspection (vehicle_id, started_at);
CREATE INDEX ix_inspection_inspection_contract_id_inspection_type_2 ON inspection.inspection (contract_id, inspection_type);
CREATE INDEX ix_inspection_inspection_media_inspection_id_captured_at_1 ON inspection.inspection_media (inspection_id, captured_at);
CREATE INDEX ix_inspection_damage_record_vehicle_id_status_1 ON inspection.damage_record (vehicle_id, status);
CREATE INDEX ix_billing_payment_method_token_party_id_status_1 ON billing.payment_method_token (party_id, status);
CREATE INDEX ix_billing_payment_method_token_provider_fingerprint_2 ON billing.payment_method_token (provider, fingerprint);
CREATE INDEX ix_billing_charge_contract_id_occurred_at_1 ON billing.charge (contract_id, occurred_at);
CREATE INDEX ix_billing_charge_source_context_source_id_2 ON billing.charge (source_context, source_id);
CREATE INDEX ix_billing_charge_posting_status_occurred_at_3 ON billing.charge (posting_status, occurred_at);
CREATE INDEX ix_billing_invoice_customer_account_id_issue_date_1 ON billing.invoice (customer_account_id, issue_date);
CREATE INDEX ix_billing_invoice_status_due_date_2 ON billing.invoice (status, due_date);
CREATE INDEX ix_billing_receivable_status_due_date_1 ON billing.receivable (status, due_date);
CREATE INDEX ix_billing_payment_intent_provider_provider_reference_1 ON billing.payment_intent (provider, provider_reference);
CREATE INDEX ix_billing_payment_transaction_payment_intent_id__b463a099 ON billing.payment_transaction (payment_intent_id, occurred_at);
CREATE INDEX ix_billing_payment_allocation_receivable_id_allocated_at_1 ON billing.payment_allocation (receivable_id, allocated_at);
CREATE INDEX ix_billing_collection_action_dunning_case_id_executed_at_1 ON billing.collection_action (dunning_case_id, executed_at);
CREATE INDEX ix_traffic_traffic_notice_vehicle_id_infraction_at_1 ON traffic.traffic_notice (vehicle_id, infraction_at);
CREATE INDEX ix_traffic_traffic_notice_status_due_date_2 ON traffic.traffic_notice (status, due_date);
CREATE INDEX ix_traffic_toll_tag_assignment_vehicle_id_start_at_1 ON traffic.toll_tag_assignment (vehicle_id, start_at);
CREATE INDEX ix_traffic_toll_transaction_vehicle_id_occurred_at_1 ON traffic.toll_transaction (vehicle_id, occurred_at);
CREATE INDEX ix_traffic_parking_transaction_vehicle_id_entered_at_1 ON traffic.parking_transaction (vehicle_id, entered_at);
CREATE INDEX ix_claim_incident_contract_id_occurred_at_1 ON claim.incident (contract_id, occurred_at);
CREATE INDEX ix_claim_incident_status_reported_at_2 ON claim.incident (status, reported_at);
CREATE INDEX ix_claim_claim_cost_claim_id_incurred_at_1 ON claim.claim_cost (claim_id, incurred_at);
CREATE INDEX ix_maintenance_maintenance_due_status_due_date_1 ON maintenance.maintenance_due (status, due_date);
CREATE INDEX ix_maintenance_maintenance_due_vehicle_id_status_2 ON maintenance.maintenance_due (vehicle_id, status);
CREATE INDEX ix_maintenance_service_order_vehicle_id_opened_at_1 ON maintenance.service_order (vehicle_id, opened_at);
CREATE INDEX ix_maintenance_service_order_status_scheduled_start_at_2 ON maintenance.service_order (status, scheduled_start_at);
CREATE INDEX ix_maintenance_tire_assignment_vehicle_id_positio_a894da3f ON maintenance.tire_assignment (vehicle_id, position_code, installed_at);
CREATE INDEX ix_maintenance_downtime_vehicle_id_start_at_1 ON maintenance.downtime (vehicle_id, start_at);
CREATE INDEX ix_telematics_device_status_last_seen_at_1 ON telematics.device (status, last_seen_at);
CREATE INDEX ix_telematics_vehicle_device_assignment_vehicle_i_a60b1872 ON telematics.vehicle_device_assignment (vehicle_id, start_at);
CREATE INDEX ix_telematics_device_health_event_device_id_occurred_at_1 ON telematics.device_health_event (device_id, occurred_at);
CREATE INDEX ix_telematics_telemetry_event_index_vehicle_id_ev_06487c2b ON telematics.telemetry_event_index (vehicle_id, event_time);
CREATE INDEX ix_telematics_telemetry_event_index_event_type_ev_0472e44c ON telematics.telemetry_event_index (event_type, event_time);
CREATE INDEX ix_telematics_trip_summary_vehicle_id_trip_start_at_1 ON telematics.trip_summary (vehicle_id, trip_start_at);
CREATE INDEX ix_telematics_trip_summary_contract_id_trip_start_at_2 ON telematics.trip_summary (contract_id, trip_start_at);
CREATE INDEX ix_telematics_driving_event_vehicle_id_occurred_at_1 ON telematics.driving_event (vehicle_id, occurred_at);
CREATE INDEX ix_telematics_driving_event_contract_id_event_type_2 ON telematics.driving_event (contract_id, event_type);
CREATE INDEX ix_telematics_geofence_event_vehicle_id_occurred_at_1 ON telematics.geofence_event (vehicle_id, occurred_at);
CREATE INDEX ix_loyalty_tier_history_loyalty_account_id_valid_from_1 ON loyalty.tier_history (loyalty_account_id, valid_from);
CREATE INDEX ix_loyalty_points_ledger_loyalty_account_id_available_at_1 ON loyalty.points_ledger (loyalty_account_id, available_at);
CREATE INDEX ix_loyalty_points_ledger_source_type_source_id_2 ON loyalty.points_ledger (source_type, source_id);
CREATE INDEX ix_fleet_mgmt_managed_vehicle_assignment_vehicle__0facac8e ON fleet_mgmt.managed_vehicle_assignment (vehicle_id, start_at);
CREATE INDEX ix_fleet_mgmt_mileage_commitment_fleet_service_co_9f1fc2d1 ON fleet_mgmt.mileage_commitment (fleet_service_contract_id, period_start);
CREATE INDEX ix_fleet_mgmt_fleet_service_event_fleet_service_c_96458ea4 ON fleet_mgmt.fleet_service_event (fleet_service_contract_id, occurred_at);
CREATE INDEX ix_fleet_mgmt_subscription_vehicle_assignment_veh_be4692a6 ON fleet_mgmt.subscription_vehicle_assignment (vehicle_id, start_at);
CREATE INDEX ix_used_car_vehicle_valuation_disposal_candidate__d6cb4637 ON used_car.vehicle_valuation (disposal_candidate_id, valued_at);
CREATE INDEX ix_used_car_listing_status_listed_at_1 ON used_car.listing (status, listed_at);
CREATE INDEX ix_used_car_lead_status_next_action_at_1 ON used_car.lead (status, next_action_at);
CREATE INDEX ix_privacy_consent_receipt_party_id_purpose_id_ca_56424124 ON privacy.consent_receipt (party_id, purpose_id, captured_at);
CREATE INDEX ix_privacy_data_subject_request_status_due_at_1 ON privacy.data_subject_request (status, due_at);
CREATE INDEX ix_privacy_legal_hold_resource_type_resource_id_1 ON privacy.legal_hold (resource_type, resource_id);
CREATE INDEX ix_privacy_legal_hold_party_id_status_2 ON privacy.legal_hold (party_id, status);
CREATE INDEX ix_privacy_erasure_job_status_scheduled_at_1 ON privacy.erasure_job (status, scheduled_at);
CREATE INDEX ix_privacy_data_access_audit_party_id_occurred_at_1 ON privacy.data_access_audit (party_id, occurred_at);
CREATE INDEX ix_privacy_data_access_audit_actor_id_occurred_at_2 ON privacy.data_access_audit (actor_id, occurred_at);
CREATE INDEX ix_privacy_data_sharing_record_party_id_shared_at_1 ON privacy.data_sharing_record (party_id, shared_at);
CREATE INDEX ix_integration_outbox_event_published_at_created_at_1 ON integration.outbox_event (published_at, created_at);
CREATE INDEX ix_integration_outbox_event_aggregate_type_aggregate_id_2 ON integration.outbox_event (aggregate_type, aggregate_id);
CREATE INDEX ix_integration_inbox_message_status_received_at_1 ON integration.inbox_message (status, received_at);
CREATE INDEX ix_integration_idempotency_key_expires_at_status_1 ON integration.idempotency_key (expires_at, status);
CREATE INDEX ix_integration_external_reference_resource_type_r_59e6ad58 ON integration.external_reference (resource_type, resource_id);
CREATE INDEX ix_integration_external_reference_system_code_ext_200eeeec ON integration.external_reference (system_code, external_id);
CREATE INDEX ix_integration_audit_event_resource_type_resource_1720f547 ON integration.audit_event (resource_type, resource_id, occurred_at);
CREATE INDEX ix_integration_audit_event_actor_id_occurred_at_2 ON integration.audit_event (actor_id, occurred_at);

-- High-value partial indexes.
CREATE INDEX ix_reservation_active_pickup
    ON reservation.reservation (pickup_branch_id, planned_pickup_at, requested_vehicle_group_id)
    WHERE current_status IN ('HELD','CONFIRMED','PICKUP_READY');

CREATE INDEX ix_vehicle_available_by_branch_group
    ON fleet.vehicle (current_branch_id, current_vehicle_group_id)
    WHERE current_operational_state = 'AVAILABLE'
      AND current_lifecycle_state = 'IN_FLEET';

CREATE INDEX ix_contract_open_due
    ON rental.rental_contract (planned_return_at)
    WHERE current_status IN ('ACTIVE','OVERDUE');

CREATE INDEX ix_outbox_unpublished
    ON integration.outbox_event (created_at)
    WHERE published_at IS NULL;

-- Native temporal non-overlap guarantees.
ALTER TABLE fleet.vehicle_calendar_entry
    ADD CONSTRAINT ex_vehicle_calendar_no_overlap
    EXCLUDE USING gist (
        vehicle_id WITH =,
        tstzrange(start_at, end_at, '[)') WITH &&
    )
    WHERE (status IN ('HELD','CONFIRMED','ACTIVE','CLOSED'));

ALTER TABLE pricing.rate_plan_version
    ADD CONSTRAINT ex_published_rate_plan_period
    EXCLUDE USING gist (
        rate_plan_id WITH =,
        tstzrange(valid_from, COALESCE(valid_to, 'infinity'::timestamptz), '[)') WITH &&
    )
    WHERE (status = 'PUBLISHED');

ALTER TABLE fleet.vehicle_registration
    ADD CONSTRAINT ex_vehicle_registration_period
    EXCLUDE USING gist (
        vehicle_id WITH =,
        tstzrange(valid_from, COALESCE(valid_to, 'infinity'::timestamptz), '[)') WITH &&
    )
    WHERE (status = 'ACTIVE');

ALTER TABLE fleet.vehicle_group_assignment
    ADD CONSTRAINT ex_vehicle_group_assignment_period
    EXCLUDE USING gist (
        vehicle_id WITH =,
        tstzrange(valid_from, COALESCE(valid_to, 'infinity'::timestamptz), '[)') WITH &&
    );

ALTER TABLE telematics.vehicle_device_assignment
    ADD CONSTRAINT ex_device_assignment_period
    EXCLUDE USING gist (
        device_id WITH =,
        tstzrange(start_at, COALESCE(end_at, 'infinity'::timestamptz), '[)') WITH &&
    );

ALTER TABLE traffic.toll_tag_assignment
    ADD CONSTRAINT ex_toll_tag_assignment_period
    EXCLUDE USING gist (
        toll_tag_id WITH =,
        tstzrange(start_at, COALESCE(end_at, 'infinity'::timestamptz), '[)') WITH &&
    );

-- Critical immutability rules.
CREATE TRIGGER trg_charge_protect_posted
BEFORE UPDATE OR DELETE ON billing.charge
FOR EACH ROW EXECUTE FUNCTION integration.protect_posted_charge();

CREATE TRIGGER trg_inspection_protect_completed
BEFORE UPDATE OR DELETE ON inspection.inspection
FOR EACH ROW EXECUTE FUNCTION integration.protect_completed_inspection();

CREATE TRIGGER trg_points_ledger_immutable
BEFORE UPDATE OR DELETE ON loyalty.points_ledger
FOR EACH ROW EXECUTE FUNCTION integration.reject_mutation();

CREATE TRIGGER trg_payment_transaction_immutable
BEFORE UPDATE OR DELETE ON billing.payment_transaction
FOR EACH ROW EXECUTE FUNCTION integration.reject_mutation();

CREATE TRIGGER trg_terms_acceptance_immutable
BEFORE UPDATE OR DELETE ON rental.contract_terms_acceptance
FOR EACH ROW EXECUTE FUNCTION integration.reject_mutation();

CREATE TRIGGER trg_audit_event_immutable
BEFORE UPDATE OR DELETE ON integration.audit_event
FOR EACH ROW EXECUTE FUNCTION integration.reject_mutation();

CREATE TRIGGER trg_privacy_access_audit_immutable
BEFORE UPDATE OR DELETE ON privacy.data_access_audit
FOR EACH ROW EXECUTE FUNCTION integration.reject_mutation();

CREATE TRIGGER trg_org_legal_entity_touch BEFORE UPDATE ON org.legal_entity FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_org_business_unit_touch BEFORE UPDATE ON org.business_unit FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_org_branch_touch BEFORE UPDATE ON org.branch FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_org_branch_hours_touch BEFORE UPDATE ON org.branch_hours FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_org_branch_calendar_exception_touch BEFORE UPDATE ON org.branch_calendar_exception FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_org_channel_touch BEFORE UPDATE ON org.channel FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_party_touch BEFORE UPDATE ON party.party FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_person_touch BEFORE UPDATE ON party.person FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_organization_touch BEFORE UPDATE ON party.organization FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_party_identifier_touch BEFORE UPDATE ON party.party_identifier FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_contact_point_touch BEFORE UPDATE ON party.contact_point FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_postal_address_touch BEFORE UPDATE ON party.postal_address FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_party_address_touch BEFORE UPDATE ON party.party_address FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_customer_account_touch BEFORE UPDATE ON party.customer_account FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_organization_representative_touch BEFORE UPDATE ON party.organization_representative FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_driver_profile_touch BEFORE UPDATE ON party.driver_profile FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_driver_license_touch BEFORE UPDATE ON party.driver_license FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_party_customer_restriction_touch BEFORE UPDATE ON party.customer_restriction FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_unit_of_measure_touch BEFORE UPDATE ON catalog.unit_of_measure FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_tax_category_touch BEFORE UPDATE ON catalog.tax_category FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_vehicle_make_touch BEFORE UPDATE ON catalog.vehicle_make FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_vehicle_model_touch BEFORE UPDATE ON catalog.vehicle_model FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_vehicle_variant_touch BEFORE UPDATE ON catalog.vehicle_variant FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_feature_touch BEFORE UPDATE ON catalog.feature FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_variant_feature_touch BEFORE UPDATE ON catalog.variant_feature FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_vehicle_group_touch BEFORE UPDATE ON catalog.vehicle_group FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_vehicle_group_variant_touch BEFORE UPDATE ON catalog.vehicle_group_variant FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_vehicle_group_upgrade_touch BEFORE UPDATE ON catalog.vehicle_group_upgrade FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_commercial_product_touch BEFORE UPDATE ON catalog.commercial_product FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_coverage_touch BEFORE UPDATE ON catalog.coverage FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_protection_coverage_touch BEFORE UPDATE ON catalog.protection_coverage FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_catalog_charge_type_touch BEFORE UPDATE ON catalog.charge_type FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_partner_touch BEFORE UPDATE ON corporate.partner FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_partner_agreement_touch BEFORE UPDATE ON corporate.partner_agreement FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_corporate_agreement_touch BEFORE UPDATE ON corporate.corporate_agreement FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_corporate_cost_center_touch BEFORE UPDATE ON corporate.corporate_cost_center FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_authorized_driver_touch BEFORE UPDATE ON corporate.authorized_driver FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_corporate_billing_profile_touch BEFORE UPDATE ON corporate.corporate_billing_profile FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_acquisition_order_touch BEFORE UPDATE ON fleet.acquisition_order FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_acquisition_order_line_touch BEFORE UPDATE ON fleet.acquisition_order_line FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_vehicle_touch BEFORE UPDATE ON fleet.vehicle FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_vehicle_registration_touch BEFORE UPDATE ON fleet.vehicle_registration FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_vehicle_group_assignment_touch BEFORE UPDATE ON fleet.vehicle_group_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_vehicle_restriction_touch BEFORE UPDATE ON fleet.vehicle_restriction FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_vehicle_calendar_entry_touch BEFORE UPDATE ON fleet.vehicle_calendar_entry FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_asset_document_touch BEFORE UPDATE ON fleet.asset_document FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_accessory_asset_touch BEFORE UPDATE ON fleet.accessory_asset FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_vehicle_accessory_assignment_touch BEFORE UPDATE ON fleet.vehicle_accessory_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_rate_plan_touch BEFORE UPDATE ON pricing.rate_plan FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_rate_plan_version_touch BEFORE UPDATE ON pricing.rate_plan_version FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_rate_plan_applicability_touch BEFORE UPDATE ON pricing.rate_plan_applicability FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_rental_length_band_touch BEFORE UPDATE ON pricing.rental_length_band FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_season_touch BEFORE UPDATE ON pricing.season FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_base_rate_touch BEFORE UPDATE ON pricing.base_rate FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_mileage_package_touch BEFORE UPDATE ON pricing.mileage_package FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_mileage_rate_touch BEFORE UPDATE ON pricing.mileage_rate FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_one_way_rule_touch BEFORE UPDATE ON pricing.one_way_rule FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_one_way_price_touch BEFORE UPDATE ON pricing.one_way_price FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_fuel_price_touch BEFORE UPDATE ON pricing.fuel_price FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_preauthorization_rule_touch BEFORE UPDATE ON pricing.preauthorization_rule FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_pricing_rule_touch BEFORE UPDATE ON pricing.pricing_rule FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_promotion_touch BEFORE UPDATE ON pricing.promotion FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_coupon_touch BEFORE UPDATE ON pricing.coupon FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_quote_touch BEFORE UPDATE ON pricing.quote FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_pricing_quote_line_touch BEFORE UPDATE ON pricing.quote_line FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_rate_entitlement_touch BEFORE UPDATE ON corporate.rate_entitlement FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_purchase_order_touch BEFORE UPDATE ON corporate.purchase_order FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_voucher_touch BEFORE UPDATE ON corporate.voucher FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_corporate_consolidated_billing_instruction_touch BEFORE UPDATE ON corporate.consolidated_billing_instruction FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_inventory_bucket_touch BEFORE UPDATE ON availability.inventory_bucket FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_availability_hold_touch BEFORE UPDATE ON availability.availability_hold FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_capacity_commitment_touch BEFORE UPDATE ON availability.capacity_commitment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_upgrade_path_touch BEFORE UPDATE ON availability.upgrade_path FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_fleet_allotment_touch BEFORE UPDATE ON availability.fleet_allotment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_relocation_order_touch BEFORE UPDATE ON availability.relocation_order FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_relocation_leg_touch BEFORE UPDATE ON availability.relocation_leg FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_availability_oversell_alert_touch BEFORE UPDATE ON availability.oversell_alert FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_reservation_touch BEFORE UPDATE ON reservation.reservation FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_reservation_driver_touch BEFORE UPDATE ON reservation.reservation_driver FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_reservation_product_touch BEFORE UPDATE ON reservation.reservation_product FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_reservation_guarantee_touch BEFORE UPDATE ON reservation.reservation_guarantee FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_partner_booking_touch BEFORE UPDATE ON reservation.partner_booking FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_reservation_note_touch BEFORE UPDATE ON reservation.reservation_note FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_reservation_reservation_inventory_commitment_touch BEFORE UPDATE ON reservation.reservation_inventory_commitment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_rental_contract_touch BEFORE UPDATE ON rental.rental_contract FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_contract_party_role_touch BEFORE UPDATE ON rental.contract_party_role FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_contract_product_touch BEFORE UPDATE ON rental.contract_product FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_vehicle_assignment_touch BEFORE UPDATE ON rental.vehicle_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_extension_touch BEFORE UPDATE ON rental.extension FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_contract_document_touch BEFORE UPDATE ON rental.contract_document FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_digital_pickup_session_touch BEFORE UPDATE ON rental.digital_pickup_session FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_vehicle_access_credential_touch BEFORE UPDATE ON rental.vehicle_access_credential FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_vehicle_access_command_touch BEFORE UPDATE ON rental.vehicle_access_command FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_overdue_case_touch BEFORE UPDATE ON rental.overdue_case FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_rental_contract_reprocessing_touch BEFORE UPDATE ON rental.contract_reprocessing FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_inspection_template_touch BEFORE UPDATE ON inspection.inspection_template FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_inspection_template_item_touch BEFORE UPDATE ON inspection.inspection_template_item FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_inspection_touch BEFORE UPDATE ON inspection.inspection FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_damage_record_touch BEFORE UPDATE ON inspection.damage_record FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_damage_attribution_touch BEFORE UPDATE ON inspection.damage_attribution FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_damage_assessment_touch BEFORE UPDATE ON inspection.damage_assessment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_damage_price_table_version_touch BEFORE UPDATE ON inspection.damage_price_table_version FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_inspection_lost_found_item_touch BEFORE UPDATE ON inspection.lost_found_item FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_payment_method_token_touch BEFORE UPDATE ON billing.payment_method_token FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_charge_touch BEFORE UPDATE ON billing.charge FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_invoice_touch BEFORE UPDATE ON billing.invoice FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_receivable_touch BEFORE UPDATE ON billing.receivable FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_payment_intent_touch BEFORE UPDATE ON billing.payment_intent FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_preauthorization_touch BEFORE UPDATE ON billing.preauthorization FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_refund_touch BEFORE UPDATE ON billing.refund FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_credit_note_touch BEFORE UPDATE ON billing.credit_note FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_chargeback_touch BEFORE UPDATE ON billing.chargeback FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_tax_document_touch BEFORE UPDATE ON billing.tax_document FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_dunning_case_touch BEFORE UPDATE ON billing.dunning_case FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_settlement_batch_touch BEFORE UPDATE ON billing.settlement_batch FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_settlement_item_touch BEFORE UPDATE ON billing.settlement_item FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_reconciliation_issue_touch BEFORE UPDATE ON billing.reconciliation_issue FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_billing_accounting_export_touch BEFORE UPDATE ON billing.accounting_export FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_provider_import_batch_touch BEFORE UPDATE ON traffic.provider_import_batch FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_traffic_notice_touch BEFORE UPDATE ON traffic.traffic_notice FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_traffic_attribution_touch BEFORE UPDATE ON traffic.traffic_attribution FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_driver_nomination_touch BEFORE UPDATE ON traffic.driver_nomination FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_traffic_appeal_touch BEFORE UPDATE ON traffic.traffic_appeal FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_toll_tag_touch BEFORE UPDATE ON traffic.toll_tag FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_toll_tag_assignment_touch BEFORE UPDATE ON traffic.toll_tag_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_toll_transaction_touch BEFORE UPDATE ON traffic.toll_transaction FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_traffic_parking_transaction_touch BEFORE UPDATE ON traffic.parking_transaction FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_insurance_policy_touch BEFORE UPDATE ON claim.insurance_policy FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_policy_coverage_touch BEFORE UPDATE ON claim.policy_coverage FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_incident_touch BEFORE UPDATE ON claim.incident FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_incident_party_touch BEFORE UPDATE ON claim.incident_party FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_incident_vehicle_touch BEFORE UPDATE ON claim.incident_vehicle FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_claim_touch BEFORE UPDATE ON claim.claim FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_claim_coverage_decision_touch BEFORE UPDATE ON claim.claim_coverage_decision FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_claim_cost_touch BEFORE UPDATE ON claim.claim_cost FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_third_party_claim_touch BEFORE UPDATE ON claim.third_party_claim FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_recovery_case_touch BEFORE UPDATE ON claim.recovery_case FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_claim_roadside_assistance_case_touch BEFORE UPDATE ON claim.roadside_assistance_case FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_maintenance_plan_touch BEFORE UPDATE ON maintenance.maintenance_plan FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_maintenance_rule_touch BEFORE UPDATE ON maintenance.maintenance_rule FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_maintenance_due_touch BEFORE UPDATE ON maintenance.maintenance_due FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_vendor_touch BEFORE UPDATE ON maintenance.vendor FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_workshop_touch BEFORE UPDATE ON maintenance.workshop FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_service_order_touch BEFORE UPDATE ON maintenance.service_order FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_service_order_item_touch BEFORE UPDATE ON maintenance.service_order_item FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_part_touch BEFORE UPDATE ON maintenance.part FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_service_order_part_touch BEFORE UPDATE ON maintenance.service_order_part FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_recall_campaign_touch BEFORE UPDATE ON maintenance.recall_campaign FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_vehicle_recall_touch BEFORE UPDATE ON maintenance.vehicle_recall FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_tire_touch BEFORE UPDATE ON maintenance.tire FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_tire_assignment_touch BEFORE UPDATE ON maintenance.tire_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_maintenance_downtime_touch BEFORE UPDATE ON maintenance.downtime FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_telematics_provider_touch BEFORE UPDATE ON telematics.provider FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_telematics_device_touch BEFORE UPDATE ON telematics.device FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_telematics_vehicle_device_assignment_touch BEFORE UPDATE ON telematics.vehicle_device_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_telematics_geofence_touch BEFORE UPDATE ON telematics.geofence FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_telematics_vehicle_command_touch BEFORE UPDATE ON telematics.vehicle_command FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_telematics_telemetry_rule_version_touch BEFORE UPDATE ON telematics.telemetry_rule_version FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_loyalty_account_touch BEFORE UPDATE ON loyalty.loyalty_account FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_loyalty_tier_touch BEFORE UPDATE ON loyalty.loyalty_tier FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_tier_rule_version_touch BEFORE UPDATE ON loyalty.tier_rule_version FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_tier_history_touch BEFORE UPDATE ON loyalty.tier_history FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_earning_rule_touch BEFORE UPDATE ON loyalty.earning_rule FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_redemption_rule_touch BEFORE UPDATE ON loyalty.redemption_rule FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_points_lot_touch BEFORE UPDATE ON loyalty.points_lot FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_redemption_touch BEFORE UPDATE ON loyalty.redemption FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_benefit_touch BEFORE UPDATE ON loyalty.benefit FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_benefit_entitlement_touch BEFORE UPDATE ON loyalty.benefit_entitlement FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_loyalty_points_transfer_touch BEFORE UPDATE ON loyalty.points_transfer FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_fleet_service_contract_touch BEFORE UPDATE ON fleet_mgmt.fleet_service_contract FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_fleet_service_level_touch BEFORE UPDATE ON fleet_mgmt.fleet_service_level FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_managed_vehicle_assignment_touch BEFORE UPDATE ON fleet_mgmt.managed_vehicle_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_mileage_commitment_touch BEFORE UPDATE ON fleet_mgmt.mileage_commitment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_telemetry_package_touch BEFORE UPDATE ON fleet_mgmt.telemetry_package FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_replacement_entitlement_touch BEFORE UPDATE ON fleet_mgmt.replacement_entitlement FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_subscription_plan_touch BEFORE UPDATE ON fleet_mgmt.subscription_plan FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_subscription_contract_touch BEFORE UPDATE ON fleet_mgmt.subscription_contract FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_fleet_mgmt_subscription_vehicle_assignment_touch BEFORE UPDATE ON fleet_mgmt.subscription_vehicle_assignment FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_disposal_candidate_touch BEFORE UPDATE ON used_car.disposal_candidate FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_refurbishment_order_touch BEFORE UPDATE ON used_car.refurbishment_order FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_refurbishment_item_touch BEFORE UPDATE ON used_car.refurbishment_item FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_sale_channel_touch BEFORE UPDATE ON used_car.sale_channel FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_listing_touch BEFORE UPDATE ON used_car.listing FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_lead_touch BEFORE UPDATE ON used_car.lead FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_test_drive_touch BEFORE UPDATE ON used_car.test_drive FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_sale_order_touch BEFORE UPDATE ON used_car.sale_order FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_sale_order_vehicle_touch BEFORE UPDATE ON used_car.sale_order_vehicle FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_vehicle_transfer_touch BEFORE UPDATE ON used_car.vehicle_transfer FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_used_car_used_vehicle_warranty_touch BEFORE UPDATE ON used_car.used_vehicle_warranty FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_privacy_notice_touch BEFORE UPDATE ON privacy.privacy_notice FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_privacy_notice_version_touch BEFORE UPDATE ON privacy.privacy_notice_version FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_processing_purpose_touch BEFORE UPDATE ON privacy.processing_purpose FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_legal_basis_touch BEFORE UPDATE ON privacy.legal_basis FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_data_subject_request_touch BEFORE UPDATE ON privacy.data_subject_request FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_retention_policy_touch BEFORE UPDATE ON privacy.retention_policy FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_legal_hold_touch BEFORE UPDATE ON privacy.legal_hold FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_erasure_job_touch BEFORE UPDATE ON privacy.erasure_job FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_privacy_token_map_touch BEFORE UPDATE ON privacy.token_map FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_outbox_event_touch BEFORE UPDATE ON integration.outbox_event FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_inbox_message_touch BEFORE UPDATE ON integration.inbox_message FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_idempotency_key_touch BEFORE UPDATE ON integration.idempotency_key FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_external_reference_touch BEFORE UPDATE ON integration.external_reference FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_saga_instance_touch BEFORE UPDATE ON integration.saga_instance FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_saga_step_touch BEFORE UPDATE ON integration.saga_step FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_dead_letter_touch BEFORE UPDATE ON integration.dead_letter FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_job_run_touch BEFORE UPDATE ON integration.job_run FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();
CREATE TRIGGER trg_integration_import_batch_touch BEFORE UPDATE ON integration.import_batch FOR EACH ROW EXECUTE FUNCTION integration.touch_updated_at();

COMMIT;
