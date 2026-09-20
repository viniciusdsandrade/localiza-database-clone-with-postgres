-- ============================================================================
-- Rental Platform Case Study - MySQL DDL
-- Target: MySQL 8.x / InnoDB.
--
-- MySQL has no PostgreSQL-style schemas inside one database and no exclusion
-- constraints. Therefore domain names are table prefixes, and temporal overlap
-- is checked by triggers plus a transaction-level vehicle guard procedure.
-- Application code must generate UUID strings (CHAR(36)).
-- ============================================================================

CREATE DATABASE IF NOT EXISTS rental_platform_case
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
USE rental_platform_case;

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- --------------------------------------------------------------------------
-- Tables
-- --------------------------------------------------------------------------
CREATE TABLE org_legal_entity (
    id                                 char(36) NOT NULL,
    entity_code                        varchar(30) NOT NULL,
    legal_name                         varchar(200) NOT NULL,
    trade_name                         varchar(160),
    tax_identifier_ciphertext          text,
    tax_identifier_hmac                binary(32),
    country_code                       char(2) NOT NULL,
    currency_code                      char(3) NOT NULL,
    timezone                           varchar(64) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_org_legal_entity PRIMARY KEY (id),
    CONSTRAINT uq_org_legal_entity_entity_code_1 UNIQUE (entity_code),
    CONSTRAINT uq_org_legal_entity_country_code_tax_identifier_hmac_2  UNIQUE (country_code, tax_identifier_hmac),
    CONSTRAINT ck_org_legal_entity_1 CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED'))
) ENGINE=InnoDB;

CREATE TABLE org_business_unit (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    parent_business_unit_id            char(36),
    unit_code                          varchar(30) NOT NULL,
    name                               varchar(160) NOT NULL,
    unit_type                          varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_org_business_unit PRIMARY KEY (id),
    CONSTRAINT uq_org_business_unit_legal_entity_id_unit_code_1  UNIQUE (legal_entity_id, unit_code),
    CONSTRAINT ck_org_business_unit_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE org_branch (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    business_unit_id                   char(36),
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
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_org_branch PRIMARY KEY (id),
    CONSTRAINT uq_org_branch_legal_entity_id_branch_code_1  UNIQUE (legal_entity_id, branch_code),
    CONSTRAINT ck_org_branch_1 CHECK (branch_type IN ('AIRPORT','URBAN','MALL','DEALERSHIP','MAINTENANCE_HUB','USED_CAR_STORE','VIRTUAL')),
    CONSTRAINT ck_org_branch_2 CHECK (operator_type IN ('OWNED','FRANCHISE','PARTNER')),
    CONSTRAINT ck_org_branch_3 CHECK (status IN ('PLANNED','ACTIVE','TEMPORARILY_CLOSED','CLOSED')),
    CONSTRAINT ck_org_branch_4 CHECK (closed_at IS NULL OR opened_at IS NULL OR closed_at >= opened_at)
) ENGINE=InnoDB;

CREATE TABLE org_branch_operator (
    id                                 char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    operator_party_id                  char(36) NOT NULL,
    operator_role                      varchar(30) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    agreement_reference                varchar(100),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_org_branch_operator PRIMARY KEY (id),
    CONSTRAINT ck_org_branch_operator_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE org_branch_hours (
    id                                 char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    day_of_week                        smallint NOT NULL,
    opens_at                           time,
    closes_at                          time,
    is_closed                          boolean NOT NULL DEFAULT FALSE,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_org_branch_hours PRIMARY KEY (id),
    CONSTRAINT uq_org_branch_hours_branch_id_day_of_week_1  UNIQUE (branch_id, day_of_week),
    CONSTRAINT ck_org_branch_hours_1 CHECK (day_of_week BETWEEN 1 AND 7),
    CONSTRAINT ck_org_branch_hours_2 CHECK (is_closed OR closes_at > opens_at)
) ENGINE=InnoDB;

CREATE TABLE org_branch_calendar_exception (
    id                                 char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    exception_date                     date NOT NULL,
    opens_at                           time,
    closes_at                          time,
    is_closed                          boolean NOT NULL DEFAULT TRUE,
    reason                             varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_org_branch_calendar_exception PRIMARY KEY (id),
    CONSTRAINT uq_org_branch_calendar_exception_branch_id_except_d9b41bc0  UNIQUE (branch_id, exception_date),
    CONSTRAINT ck_org_branch_calendar_exception_1 CHECK (is_closed OR closes_at > opens_at)
) ENGINE=InnoDB;

CREATE TABLE org_channel (
    id                                 char(36) NOT NULL,
    channel_code                       varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    channel_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_org_channel PRIMARY KEY (id),
    CONSTRAINT uq_org_channel_channel_code_1 UNIQUE (channel_code),
    CONSTRAINT ck_org_channel_1 CHECK (channel_type IN ('WEB','MOBILE_APP','BRANCH','CALL_CENTER','PARTNER','API','KIOSK')),
    CONSTRAINT ck_org_channel_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE party_party (
    id                                 char(36) NOT NULL,
    party_type                         varchar(20) NOT NULL,
    canonical_status                   varchar(20) NOT NULL DEFAULT 'ACTIVE',
    preferred_language                 varchar(10),
    home_country_code                  char(2),
    merged_into_party_id               char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_party PRIMARY KEY (id),
    CONSTRAINT ck_party_party_1 CHECK (party_type IN ('PERSON','ORGANIZATION')),
    CONSTRAINT ck_party_party_2 CHECK (canonical_status IN ('ACTIVE','BLOCKED','MERGED','ANONYMIZED','DECEASED','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE party_person (
    party_id                           char(36) NOT NULL,
    given_name                         varchar(100) NOT NULL,
    family_name                        varchar(140) NOT NULL,
    preferred_name                     varchar(100),
    birth_date                         date,
    nationality_country_code           char(2),
    gender_code                        varchar(20),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_person PRIMARY KEY (party_id)
) ENGINE=InnoDB;

CREATE TABLE party_organization (
    party_id                           char(36) NOT NULL,
    legal_name                         varchar(200) NOT NULL,
    trade_name                         varchar(180),
    organization_type                  varchar(30),
    incorporation_country_code         char(2),
    website_url                        varchar(500),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_organization PRIMARY KEY (party_id)
) ENGINE=InnoDB;

CREATE TABLE party_party_identifier (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    identifier_type                    varchar(40) NOT NULL,
    issuing_country_code               char(2) NOT NULL,
    identifier_ciphertext              text NOT NULL,
    identifier_hmac                    binary(32) NOT NULL,
    identifier_last4                   varchar(8),
    valid_from                         date,
    valid_to                           date,
    verified_at                        datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_party_identifier PRIMARY KEY (id),
    CONSTRAINT uq_party_party_identifier_identifier_type_issuing_2a125238  UNIQUE (identifier_type, issuing_country_code, identifier_hmac),
    CONSTRAINT ck_party_party_identifier_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_party_party_identifier_2 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','UNVERIFIED'))
) ENGINE=InnoDB;

CREATE TABLE party_contact_point (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    contact_type                       varchar(20) NOT NULL,
    usage_type                         varchar(20) NOT NULL,
    value_ciphertext                   text NOT NULL,
    value_hmac                         binary(32) NOT NULL,
    is_primary                         boolean NOT NULL DEFAULT FALSE,
    verified_at                        datetime(6),
    valid_from                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    valid_to                           datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_contact_point PRIMARY KEY (id),
    CONSTRAINT ck_party_contact_point_1 CHECK (contact_type IN ('EMAIL','PHONE','MOBILE','WHATSAPP')),
    CONSTRAINT ck_party_contact_point_2 CHECK (usage_type IN ('PERSONAL','WORK','BILLING','EMERGENCY')),
    CONSTRAINT ck_party_contact_point_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE party_postal_address (
    id                                 char(36) NOT NULL,
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
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_postal_address PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE party_party_address (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    address_id                         char(36) NOT NULL,
    usage_type                         varchar(20) NOT NULL,
    is_primary                         boolean NOT NULL DEFAULT FALSE,
    valid_from                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    valid_to                           datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_party_address PRIMARY KEY (id),
    CONSTRAINT uq_party_party_address_party_id_address_id_usage__32d5144f  UNIQUE (party_id, address_id, usage_type, valid_from),
    CONSTRAINT ck_party_party_address_1 CHECK (usage_type IN ('HOME','WORK','BILLING','MAILING','REGISTERED')),
    CONSTRAINT ck_party_party_address_2 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE party_customer_account (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    customer_number                    varchar(40) NOT NULL,
    segment                            varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    credit_limit                       decimal(19,4),
    currency_code                      char(3),
    opened_at                          datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    closed_at                          datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_customer_account PRIMARY KEY (id),
    CONSTRAINT uq_party_customer_account_legal_entity_id_custome_0bdb7276  UNIQUE (legal_entity_id, customer_number),
    CONSTRAINT uq_party_customer_account_legal_entity_id_party_id_2  UNIQUE (legal_entity_id, party_id),
    CONSTRAINT ck_party_customer_account_1 CHECK (segment IN ('RETAIL','CORPORATE','PARTNER','GOVERNMENT','INTERNAL')),
    CONSTRAINT ck_party_customer_account_2 CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_party_customer_account_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
) ENGINE=InnoDB;

CREATE TABLE party_organization_representative (
    id                                 char(36) NOT NULL,
    organization_party_id              char(36) NOT NULL,
    person_party_id                    char(36) NOT NULL,
    role_type                          varchar(40) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    authority_document_id              char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_organization_representative PRIMARY KEY (id),
    CONSTRAINT ck_party_organization_representative_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE party_driver_profile (
    id                                 char(36) NOT NULL,
    person_party_id                    char(36) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    first_approved_at                  datetime(6),
    last_reviewed_at                   datetime(6),
    young_driver_until                 date,
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_driver_profile PRIMARY KEY (id),
    CONSTRAINT uq_party_driver_profile_person_party_id_1 UNIQUE (person_party_id),
    CONSTRAINT ck_party_driver_profile_1 CHECK (status IN ('PENDING','APPROVED','RESTRICTED','SUSPENDED','REJECTED'))
) ENGINE=InnoDB;

CREATE TABLE party_driver_license (
    id                                 char(36) NOT NULL,
    driver_profile_id                  char(36) NOT NULL,
    issuing_country_code               char(2) NOT NULL,
    license_number_ciphertext          text NOT NULL,
    license_number_hmac                binary(32) NOT NULL,
    category                           varchar(20) NOT NULL,
    issued_at                          date,
    expires_at                         date NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'UNVERIFIED',
    verification_source                varchar(40),
    verified_at                        datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_driver_license PRIMARY KEY (id),
    CONSTRAINT uq_party_driver_license_issuing_country_code_lice_53885997  UNIQUE (issuing_country_code, license_number_hmac),
    CONSTRAINT ck_party_driver_license_1 CHECK (status IN ('UNVERIFIED','VALID','EXPIRED','SUSPENDED','REVOKED','REJECTED')),
    CONSTRAINT ck_party_driver_license_2 CHECK (issued_at IS NULL OR expires_at > issued_at)
) ENGINE=InnoDB;

CREATE TABLE party_identity_verification (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    verification_type                  varchar(40) NOT NULL,
    provider                           varchar(60),
    provider_reference                 varchar(160),
    result                             varchar(20) NOT NULL,
    score                              decimal(8,5),
    evidence_json                      json,
    verified_at                        datetime(6) NOT NULL,
    expires_at                         datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_identity_verification PRIMARY KEY (id),
    CONSTRAINT ck_party_identity_verification_1 CHECK (result IN ('APPROVED','REJECTED','REVIEW','EXPIRED')),
    CONSTRAINT ck_party_identity_verification_2 CHECK (expires_at IS NULL OR expires_at > verified_at)
) ENGINE=InnoDB;

CREATE TABLE party_risk_assessment (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    assessment_type                    varchar(40) NOT NULL,
    risk_level                         varchar(20) NOT NULL,
    score                              decimal(10,5),
    rule_version                       varchar(60),
    decision                           varchar(30) NOT NULL,
    reason_codes                       json,
    assessed_at                        datetime(6) NOT NULL,
    expires_at                         datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_party_risk_assessment PRIMARY KEY (id),
    CONSTRAINT ck_party_risk_assessment_1 CHECK (risk_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_party_risk_assessment_2 CHECK (decision IN ('APPROVE','REVIEW','REJECT','LIMIT')),
    CONSTRAINT ck_party_risk_assessment_3 CHECK (expires_at IS NULL OR expires_at > assessed_at)
) ENGINE=InnoDB;

CREATE TABLE party_customer_restriction (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    restriction_type                   varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    reason_code                        varchar(60),
    starts_at                          datetime(6) NOT NULL,
    ends_at                            datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_by                         char(36),
    released_by                        char(36),
    released_at                        datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_party_customer_restriction PRIMARY KEY (id),
    CONSTRAINT ck_party_customer_restriction_1 CHECK (severity IN ('INFO','WARNING','BLOCKING')),
    CONSTRAINT ck_party_customer_restriction_2 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED')),
    CONSTRAINT ck_party_customer_restriction_3 CHECK (ends_at IS NULL OR ends_at > starts_at)
) ENGINE=InnoDB;

CREATE TABLE catalog_unit_of_measure (
    id                                 char(36) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    name                               varchar(80) NOT NULL,
    dimension                          varchar(30) NOT NULL,
    decimal_scale                      smallint NOT NULL DEFAULT 0,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_unit_of_measure PRIMARY KEY (id),
    CONSTRAINT uq_catalog_unit_of_measure_unit_code_1 UNIQUE (unit_code),
    CONSTRAINT ck_catalog_unit_of_measure_1 CHECK (decimal_scale BETWEEN 0 AND 9)
) ENGINE=InnoDB;

CREATE TABLE catalog_tax_category (
    id                                 char(36) NOT NULL,
    tax_category_code                  varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    country_code                       char(2) NOT NULL,
    configuration_json                 json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_tax_category PRIMARY KEY (id),
    CONSTRAINT uq_catalog_tax_category_country_code_tax_category_code_1  UNIQUE (country_code, tax_category_code),
    CONSTRAINT ck_catalog_tax_category_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_vehicle_make (
    id                                 char(36) NOT NULL,
    make_code                          varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    country_code                       char(2),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_vehicle_make PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_make_make_code_1 UNIQUE (make_code),
    CONSTRAINT ck_catalog_vehicle_make_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_vehicle_model (
    id                                 char(36) NOT NULL,
    make_id                            char(36) NOT NULL,
    model_code                         varchar(40) NOT NULL,
    name                               varchar(120) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_vehicle_model PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_model_make_id_model_code_1  UNIQUE (make_id, model_code),
    CONSTRAINT ck_catalog_vehicle_model_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_vehicle_variant (
    id                                 char(36) NOT NULL,
    model_id                           char(36) NOT NULL,
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
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_vehicle_variant PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_variant_model_id_variant_code__69e5c55d  UNIQUE (model_id, variant_code, model_year),
    CONSTRAINT ck_catalog_vehicle_variant_1 CHECK (transmission_type IS NULL OR transmission_type IN ('MANUAL','AUTOMATIC','CVT','DUAL_CLUTCH','OTHER')),
    CONSTRAINT ck_catalog_vehicle_variant_2 CHECK (fuel_type IS NULL OR fuel_type IN ('GASOLINE','ETHANOL','FLEX','DIESEL','HYBRID','ELECTRIC','OTHER')),
    CONSTRAINT ck_catalog_vehicle_variant_3 CHECK (seat_count IS NULL OR seat_count > 0),
    CONSTRAINT ck_catalog_vehicle_variant_4 CHECK (door_count IS NULL OR door_count > 0),
    CONSTRAINT ck_catalog_vehicle_variant_5 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_feature (
    id                                 char(36) NOT NULL,
    feature_code                       varchar(40) NOT NULL,
    name                               varchar(100) NOT NULL,
    feature_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_feature PRIMARY KEY (id),
    CONSTRAINT uq_catalog_feature_feature_code_1 UNIQUE (feature_code),
    CONSTRAINT ck_catalog_feature_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_variant_feature (
    vehicle_variant_id                 char(36) NOT NULL,
    feature_id                         char(36) NOT NULL,
    feature_value                      varchar(120),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_variant_feature PRIMARY KEY (vehicle_variant_id, feature_id)
) ENGINE=InnoDB;

CREATE TABLE catalog_vehicle_group (
    id                                 char(36) NOT NULL,
    group_code                         varchar(30) NOT NULL,
    name                               varchar(120) NOT NULL,
    market_country_code                char(2) NOT NULL,
    description                        text,
    minimum_seats                      smallint,
    minimum_luggage                    smallint,
    sort_order                         int NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_vehicle_group PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_group_market_country_code_group_code_1  UNIQUE (market_country_code, group_code),
    CONSTRAINT ck_catalog_vehicle_group_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_vehicle_group_variant (
    id                                 char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    vehicle_variant_id                 char(36) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    priority                           smallint NOT NULL DEFAULT 100,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_vehicle_group_variant PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_group_variant_vehicle_group_id_b7063c95  UNIQUE (vehicle_group_id, vehicle_variant_id, valid_from),
    CONSTRAINT ck_catalog_vehicle_group_variant_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE catalog_vehicle_group_upgrade (
    id                                 char(36) NOT NULL,
    from_group_id                      char(36) NOT NULL,
    to_group_id                        char(36) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    requires_approval                  boolean NOT NULL DEFAULT FALSE,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_vehicle_group_upgrade PRIMARY KEY (id),
    CONSTRAINT uq_catalog_vehicle_group_upgrade_from_group_id_to_0a9e3cb2  UNIQUE (from_group_id, to_group_id, valid_from),
    CONSTRAINT ck_catalog_vehicle_group_upgrade_1 CHECK (from_group_id <> to_group_id),
    CONSTRAINT ck_catalog_vehicle_group_upgrade_2 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE catalog_commercial_product (
    id                                 char(36) NOT NULL,
    product_code                       varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    product_type                       varchar(30) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    tax_category_id                    char(36),
    configuration_json                 json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_commercial_product PRIMARY KEY (id),
    CONSTRAINT uq_catalog_commercial_product_product_code_1  UNIQUE (product_code),
    CONSTRAINT ck_catalog_commercial_product_1 CHECK (product_type IN ('RENTAL','ACCESSORY','SERVICE','PROTECTION','FEE','MILEAGE','DISCOUNT','TAX')),
    CONSTRAINT ck_catalog_commercial_product_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_coverage (
    id                                 char(36) NOT NULL,
    coverage_code                      varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    description                        text,
    coverage_type                      varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_coverage PRIMARY KEY (id),
    CONSTRAINT uq_catalog_coverage_coverage_code_1 UNIQUE (coverage_code),
    CONSTRAINT ck_catalog_coverage_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE catalog_protection_coverage (
    protection_product_id              char(36) NOT NULL,
    coverage_id                        char(36) NOT NULL,
    deductible_amount                  decimal(19,4),
    coverage_limit_amount              decimal(19,4),
    currency_code                      char(3),
    terms_json                         json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_protection_coverage PRIMARY KEY (protection_product_id, coverage_id),
    CONSTRAINT ck_catalog_protection_coverage_1 CHECK (deductible_amount IS NULL OR deductible_amount >= 0),
    CONSTRAINT ck_catalog_protection_coverage_2 CHECK (coverage_limit_amount IS NULL OR coverage_limit_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE catalog_charge_type (
    id                                 char(36) NOT NULL,
    charge_code                        varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    category                           varchar(30) NOT NULL,
    default_product_id                 char(36),
    is_reversible                      boolean NOT NULL DEFAULT TRUE,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_catalog_charge_type PRIMARY KEY (id),
    CONSTRAINT uq_catalog_charge_type_charge_code_1 UNIQUE (charge_code),
    CONSTRAINT ck_catalog_charge_type_1 CHECK (category IN ('RENTAL','USAGE','PROTECTION','FEE','DAMAGE','TRAFFIC','TOLL','TAX','DISCOUNT','OTHER')),
    CONSTRAINT ck_catalog_charge_type_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE corporate_partner (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    partner_code                       varchar(40) NOT NULL,
    partner_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_partner PRIMARY KEY (id),
    CONSTRAINT uq_corporate_partner_partner_code_1 UNIQUE (partner_code),
    CONSTRAINT uq_corporate_partner_party_id_2 UNIQUE (party_id),
    CONSTRAINT ck_corporate_partner_1 CHECK (partner_type IN ('OTA','TRAVEL_AGENCY','AIRLINE','BANK','INSURER','MARKETPLACE','OTHER')),
    CONSTRAINT ck_corporate_partner_2 CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE corporate_partner_agreement (
    id                                 char(36) NOT NULL,
    partner_id                         char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    agreement_number                   varchar(60) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    commission_model                   varchar(30),
    commission_value                   decimal(19,6),
    currency_code                      char(3),
    terms_json                         json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_partner_agreement PRIMARY KEY (id),
    CONSTRAINT uq_corporate_partner_agreement_legal_entity_id_ag_0279997d  UNIQUE (legal_entity_id, agreement_number),
    CONSTRAINT ck_corporate_partner_agreement_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_partner_agreement_2 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
) ENGINE=InnoDB;

CREATE TABLE corporate_corporate_agreement (
    id                                 char(36) NOT NULL,
    customer_account_id                char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    agreement_number                   varchar(60) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    billing_mode                       varchar(30) NOT NULL,
    currency_code                      char(3) NOT NULL,
    credit_limit                       decimal(19,4),
    terms_json                         json,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_corporate_agreement PRIMARY KEY (id),
    CONSTRAINT uq_corporate_corporate_agreement_legal_entity_id__50e67ddc  UNIQUE (legal_entity_id, agreement_number),
    CONSTRAINT ck_corporate_corporate_agreement_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_corporate_agreement_2 CHECK (billing_mode IN ('DIRECT','CONSOLIDATED','PREPAID','VOUCHER')),
    CONSTRAINT ck_corporate_corporate_agreement_3 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
) ENGINE=InnoDB;

CREATE TABLE corporate_corporate_cost_center (
    id                                 char(36) NOT NULL,
    corporate_agreement_id             char(36) NOT NULL,
    parent_cost_center_id              char(36),
    cost_center_code                   varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_corporate_corporate_cost_center PRIMARY KEY (id),
    CONSTRAINT uq_corporate_corporate_cost_center_corporate_agre_88789ddd  UNIQUE (corporate_agreement_id, cost_center_code),
    CONSTRAINT ck_corporate_corporate_cost_center_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE corporate_authorized_driver (
    id                                 char(36) NOT NULL,
    corporate_agreement_id             char(36) NOT NULL,
    driver_profile_id                  char(36) NOT NULL,
    cost_center_id                     char(36),
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    authorization_level                varchar(30),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_corporate_authorized_driver PRIMARY KEY (id),
    CONSTRAINT uq_corporate_authorized_driver_corporate_agreemen_cb7456fb  UNIQUE (corporate_agreement_id, driver_profile_id, valid_from),
    CONSTRAINT ck_corporate_authorized_driver_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_authorized_driver_2 CHECK (status IN ('ACTIVE','SUSPENDED','EXPIRED','REVOKED'))
) ENGINE=InnoDB;

CREATE TABLE corporate_corporate_billing_profile (
    id                                 char(36) NOT NULL,
    corporate_agreement_id             char(36) NOT NULL,
    billing_party_id                   char(36) NOT NULL,
    billing_address_id                 char(36),
    payment_terms_days                 int NOT NULL DEFAULT 0,
    invoice_frequency                  varchar(20) NOT NULL,
    purchase_order_required            boolean NOT NULL DEFAULT FALSE,
    tax_document_email_ciphertext      text,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_corporate_billing_profile PRIMARY KEY (id),
    CONSTRAINT uq_corporate_corporate_billing_profile_corporate__64893437  UNIQUE (corporate_agreement_id),
    CONSTRAINT ck_corporate_corporate_billing_profile_1 CHECK (payment_terms_days >= 0),
    CONSTRAINT ck_corporate_corporate_billing_profile_2 CHECK (invoice_frequency IN ('PER_CONTRACT','WEEKLY','BIWEEKLY','MONTHLY')),
    CONSTRAINT ck_corporate_corporate_billing_profile_3 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE fleet_acquisition_order (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    supplier_party_id                  char(36) NOT NULL,
    order_number                       varchar(60) NOT NULL,
    order_date                         date NOT NULL,
    expected_delivery_date             date,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    total_amount                       decimal(19,4) NOT NULL DEFAULT 0,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_acquisition_order PRIMARY KEY (id),
    CONSTRAINT uq_fleet_acquisition_order_legal_entity_id_order_number_1  UNIQUE (legal_entity_id, order_number),
    CONSTRAINT ck_fleet_acquisition_order_1 CHECK (status IN ('DRAFT','APPROVED','PLACED','PARTIALLY_RECEIVED','RECEIVED','CANCELLED')),
    CONSTRAINT ck_fleet_acquisition_order_2 CHECK (total_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE fleet_acquisition_order_line (
    id                                 char(36) NOT NULL,
    acquisition_order_id               char(36) NOT NULL,
    line_number                        int NOT NULL,
    vehicle_variant_id                 char(36) NOT NULL,
    quantity_ordered                   int NOT NULL,
    quantity_received                  int NOT NULL DEFAULT 0,
    unit_price                         decimal(19,4) NOT NULL,
    expected_delivery_date             date,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_acquisition_order_line PRIMARY KEY (id),
    CONSTRAINT uq_fleet_acquisition_order_line_acquisition_order_26372419  UNIQUE (acquisition_order_id, line_number),
    CONSTRAINT ck_fleet_acquisition_order_line_1 CHECK (quantity_ordered > 0),
    CONSTRAINT ck_fleet_acquisition_order_line_2 CHECK (quantity_received >= 0),
    CONSTRAINT ck_fleet_acquisition_order_line_3 CHECK (quantity_received <= quantity_ordered),
    CONSTRAINT ck_fleet_acquisition_order_line_4 CHECK (unit_price >= 0)
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle (
    id                                 char(36) NOT NULL,
    fleet_number                       varchar(40) NOT NULL,
    vin                                varchar(40) NOT NULL,
    vehicle_variant_id                 char(36) NOT NULL,
    owning_legal_entity_id             char(36) NOT NULL,
    acquisition_order_line_id          char(36),
    acquired_at                        date,
    in_service_at                      date,
    current_branch_id                  char(36),
    current_vehicle_group_id           char(36),
    current_operational_state          varchar(30) NOT NULL DEFAULT 'PICKUP_PREPARATION',
    current_lifecycle_state            varchar(30) NOT NULL DEFAULT 'RECEIVED',
    current_odometer_km                decimal(12,1) NOT NULL DEFAULT 0,
    current_fuel_level                 decimal(5,2),
    status_reason                      varchar(120),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_vehicle PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_fleet_number_1 UNIQUE (fleet_number),
    CONSTRAINT uq_fleet_vehicle_vin_2 UNIQUE (vin),
    CONSTRAINT ck_fleet_vehicle_1 CHECK (current_operational_state IN ('AVAILABLE','PICKUP_PREPARATION','RENTED','RETURN_PROCESSING','CLEANING','MAINTENANCE','IN_TRANSFER','QUARANTINED','BLOCKED','SALE_PREPARATION')),
    CONSTRAINT ck_fleet_vehicle_2 CHECK (current_lifecycle_state IN ('ORDERED','RECEIVED','IN_FLEET','DISPOSAL_CANDIDATE','SALE_PREPARATION','LISTED_FOR_SALE','SOLD','DEREGISTERED')),
    CONSTRAINT ck_fleet_vehicle_3 CHECK (current_odometer_km >= 0),
    CONSTRAINT ck_fleet_vehicle_4 CHECK (current_fuel_level IS NULL OR (current_fuel_level >= 0 AND current_fuel_level <= 100))
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_registration (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    country_code                       char(2) NOT NULL,
    registration_number                varchar(30) NOT NULL,
    registration_hmac                  binary(32),
    issuing_region                     varchar(80),
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    document_object_key                varchar(500),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_registration PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_registration_country_code_regist_344750a9  UNIQUE (country_code, registration_number, valid_from),
    CONSTRAINT ck_fleet_vehicle_registration_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_fleet_vehicle_registration_2 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','REPLACED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_group_assignment (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    assignment_reason                  varchar(60),
    assigned_by                        char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_group_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_group_assignment_vehicle_id_valid_from_1  UNIQUE (vehicle_id, valid_from),
    CONSTRAINT ck_fleet_vehicle_group_assignment_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_operational_state_history (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         char(36),
    changed_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_operational_state_history  PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_operational_state_history_1  CHECK (to_status IN ('AVAILABLE','PICKUP_PREPARATION','RENTED','RETURN_PROCESSING','CLEANING','MAINTENANCE','IN_TRANSFER',' QUARANTINED','BLOCKED','SALE_PREPARATION'))
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_lifecycle_history (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         char(36),
    changed_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_lifecycle_history PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_lifecycle_history_1 CHECK (to_status IN ('ORDERED','RECEIVED','IN_FLEET','DISPOSAL_CANDIDATE','SALE_PREPARATION','LISTED_FOR_SALE','SOLD','DEREGISTERED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_restriction (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    restriction_type                   varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    reason_code                        varchar(60),
    starts_at                          datetime(6) NOT NULL,
    ends_at                            datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_type                        varchar(40),
    source_id                          char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_vehicle_restriction PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_restriction_1 CHECK (severity IN ('INFO','WARNING','BLOCKING')),
    CONSTRAINT ck_fleet_vehicle_restriction_2 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED')),
    CONSTRAINT ck_fleet_vehicle_restriction_3 CHECK (ends_at IS NULL OR ends_at > starts_at)
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_location_history (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    branch_id                          char(36),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    location_type                      varchar(30) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          char(36),
    recorded_at                        datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_location_history PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_location_history_1 CHECK (location_type IN ('BRANCH','GPS','WORKSHOP','CUSTOMER','TRANSFER','OTHER'))
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_calendar_entry (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6) NOT NULL,
    entry_type                         varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          char(36),
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_vehicle_calendar_entry PRIMARY KEY (id),
    CONSTRAINT ck_fleet_vehicle_calendar_entry_1 CHECK (end_at > start_at),
    CONSTRAINT ck_fleet_vehicle_calendar_entry_2 CHECK (entry_type IN ('RENTAL','MAINTENANCE','TRANSFER','CLEANING','INSPECTION','SALE_PREPARATION','MANUAL_BLOCK')),
    CONSTRAINT ck_fleet_vehicle_calendar_entry_3 CHECK (status IN ('HELD','CONFIRMED','ACTIVE','CLOSED','CANCELLED','SUPERSEDED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_odometer_reading (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    reading_km                         decimal(12,1) NOT NULL,
    reading_at                         datetime(6) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          char(36),
    is_correction                      boolean NOT NULL DEFAULT FALSE,
    corrects_reading_id                char(36),
    recorded_by                        char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_odometer_reading PRIMARY KEY (id),
    CONSTRAINT ck_fleet_odometer_reading_1 CHECK (reading_km >= 0),
    CONSTRAINT ck_fleet_odometer_reading_2 CHECK (corrects_reading_id IS NULL OR corrects_reading_id <> id)
) ENGINE=InnoDB;

CREATE TABLE fleet_fuel_reading (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    fuel_level_percent                 decimal(5,2) NOT NULL,
    reading_at                         datetime(6) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          char(36),
    recorded_by                        char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_fuel_reading PRIMARY KEY (id),
    CONSTRAINT ck_fleet_fuel_reading_1 CHECK (fuel_level_percent >= 0 AND fuel_level_percent <= 100)
) ENGINE=InnoDB;

CREATE TABLE fleet_asset_document (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             binary(32),
    issued_at                          date,
    expires_at                         date,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_asset_document PRIMARY KEY (id),
    CONSTRAINT ck_fleet_asset_document_1 CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at),
    CONSTRAINT ck_fleet_asset_document_2 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','REPLACED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_accessory_asset (
    id                                 char(36) NOT NULL,
    asset_code                         varchar(50) NOT NULL,
    product_id                         char(36) NOT NULL,
    serial_number                      varchar(100),
    owning_legal_entity_id             char(36) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_accessory_asset PRIMARY KEY (id),
    CONSTRAINT uq_fleet_accessory_asset_asset_code_1 UNIQUE (asset_code),
    CONSTRAINT ck_fleet_accessory_asset_1 CHECK (status IN ('AVAILABLE','ASSIGNED','MAINTENANCE','LOST','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_accessory_assignment (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    accessory_asset_id                 char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    assignment_reason                  varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_accessory_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_accessory_assignment_accessory_a_3ae41b12  UNIQUE (accessory_asset_id, start_at),
    CONSTRAINT ck_fleet_vehicle_accessory_assignment_1 CHECK (end_at IS NULL OR end_at > start_at)
) ENGINE=InnoDB;

CREATE TABLE fleet_vehicle_cost_basis (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    purchase_amount                    decimal(19,4) NOT NULL,
    capitalized_cost_amount            decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    effective_date                     date NOT NULL,
    source_reference                   varchar(100),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_cost_basis PRIMARY KEY (id),
    CONSTRAINT uq_fleet_vehicle_cost_basis_vehicle_id_effective_date_1  UNIQUE (vehicle_id, effective_date),
    CONSTRAINT ck_fleet_vehicle_cost_basis_1 CHECK (purchase_amount >= 0),
    CONSTRAINT ck_fleet_vehicle_cost_basis_2 CHECK (capitalized_cost_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE fleet_depreciation_entry (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    period_start                       date NOT NULL,
    period_end                         date NOT NULL,
    depreciation_amount                decimal(19,4) NOT NULL,
    book_value_after                   decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    accounting_reference               varchar(100),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_depreciation_entry PRIMARY KEY (id),
    CONSTRAINT uq_fleet_depreciation_entry_vehicle_id_period_sta_7a43f62c  UNIQUE (vehicle_id, period_start, period_end),
    CONSTRAINT ck_fleet_depreciation_entry_1 CHECK (period_end >= period_start),
    CONSTRAINT ck_fleet_depreciation_entry_2 CHECK (depreciation_amount >= 0),
    CONSTRAINT ck_fleet_depreciation_entry_3 CHECK (book_value_after >= 0)
) ENGINE=InnoDB;

CREATE TABLE fleet_disposal_eligibility (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    evaluated_at                       datetime(6) NOT NULL,
    eligible                           boolean NOT NULL,
    reason_codes                       json,
    recommended_channel                varchar(40),
    estimated_residual_value           decimal(19,4),
    currency_code                      char(3),
    model_version                      varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_disposal_eligibility PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE pricing_rate_plan (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    plan_code                          varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    rental_mode                        varchar(30) NOT NULL,
    description                        text,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_rate_plan PRIMARY KEY (id),
    CONSTRAINT uq_pricing_rate_plan_legal_entity_id_plan_code_1  UNIQUE (legal_entity_id, plan_code),
    CONSTRAINT ck_pricing_rate_plan_1 CHECK (rental_mode IN ('HOURLY','DAILY','WEEKLY','MONTHLY','SUBSCRIPTION','CORPORATE')),
    CONSTRAINT ck_pricing_rate_plan_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE pricing_rate_plan_version (
    id                                 char(36) NOT NULL,
    rate_plan_id                       char(36) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    currency_code                      char(3) NOT NULL,
    calculation_version                varchar(60) NOT NULL,
    ruleset_hash                       varchar(64) NOT NULL,
    published_at                       datetime(6),
    published_by                       char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_rate_plan_version PRIMARY KEY (id),
    CONSTRAINT uq_pricing_rate_plan_version_rate_plan_id_version_number_1  UNIQUE (rate_plan_id, version_number),
    CONSTRAINT ck_pricing_rate_plan_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_pricing_rate_plan_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE pricing_rate_plan_applicability (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    origin_branch_id                   char(36),
    destination_branch_id              char(36),
    vehicle_group_id                   char(36),
    channel_id                         char(36),
    customer_segment                   varchar(30),
    corporate_agreement_id             char(36),
    partner_id                         char(36),
    priority                           smallint NOT NULL DEFAULT 100,
    condition_json                     json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_rate_plan_applicability PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE pricing_rental_length_band (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    band_code                          varchar(30) NOT NULL,
    minimum_minutes                    int NOT NULL,
    maximum_minutes                    int,
    billing_unit                       varchar(20) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_rental_length_band PRIMARY KEY (id),
    CONSTRAINT uq_pricing_rental_length_band_rate_plan_version_i_f4ae433d  UNIQUE (rate_plan_version_id, band_code),
    CONSTRAINT ck_pricing_rental_length_band_1 CHECK (minimum_minutes >= 0),
    CONSTRAINT ck_pricing_rental_length_band_2 CHECK (maximum_minutes IS NULL OR maximum_minutes > minimum_minutes),
    CONSTRAINT ck_pricing_rental_length_band_3 CHECK (billing_unit IN ('HOUR','DAY','WEEK','MONTH'))
) ENGINE=InnoDB;

CREATE TABLE pricing_season (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    season_code                        varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    start_date                         date NOT NULL,
    end_date                           date NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    recurrence_rule                    varchar(300),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_season PRIMARY KEY (id),
    CONSTRAINT uq_pricing_season_legal_entity_id_season_code_start_date_1  UNIQUE (legal_entity_id, season_code, start_date),
    CONSTRAINT ck_pricing_season_1 CHECK (end_date >= start_date)
) ENGINE=InnoDB;

CREATE TABLE pricing_base_rate (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    origin_branch_id                   char(36),
    rental_length_band_id              char(36),
    season_id                          char(36),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    minimum_charge_amount              decimal(19,4),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_base_rate PRIMARY KEY (id),
    CONSTRAINT ck_pricing_base_rate_1 CHECK (amount >= 0),
    CONSTRAINT ck_pricing_base_rate_2 CHECK (minimum_charge_amount IS NULL OR minimum_charge_amount >= 0),
    CONSTRAINT ck_pricing_base_rate_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE pricing_mileage_package (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    package_code                       varchar(40) NOT NULL,
    name                               varchar(120) NOT NULL,
    included_km                        decimal(12,2),
    included_km_per_unit               decimal(12,2),
    is_unlimited                       boolean NOT NULL DEFAULT FALSE,
    billing_mode                       varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_mileage_package PRIMARY KEY (id),
    CONSTRAINT uq_pricing_mileage_package_rate_plan_version_id_p_3dc9d824  UNIQUE (rate_plan_version_id, package_code),
    CONSTRAINT ck_pricing_mileage_package_1 CHECK (included_km IS NULL OR included_km >= 0),
    CONSTRAINT ck_pricing_mileage_package_2 CHECK (included_km_per_unit IS NULL OR included_km_per_unit >= 0),
    CONSTRAINT ck_pricing_mileage_package_3 CHECK (billing_mode IN ('FIXED','PER_RENTAL_UNIT','FLEXIBLE')),
    CONSTRAINT ck_pricing_mileage_package_4 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE pricing_mileage_rate (
    id                                 char(36) NOT NULL,
    mileage_package_id                 char(36) NOT NULL,
    vehicle_group_id                   char(36),
    excess_km_amount                   decimal(19,4) NOT NULL,
    flex_km_amount                     decimal(19,4),
    currency_code                      char(3) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_mileage_rate PRIMARY KEY (id),
    CONSTRAINT ck_pricing_mileage_rate_1 CHECK (excess_km_amount >= 0),
    CONSTRAINT ck_pricing_mileage_rate_2 CHECK (flex_km_amount IS NULL OR flex_km_amount >= 0),
    CONSTRAINT ck_pricing_mileage_rate_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE pricing_one_way_rule (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    origin_branch_id                   char(36),
    destination_branch_id              char(36),
    origin_region                      varchar(80),
    destination_region                 varchar(80),
    vehicle_group_id                   char(36),
    calculation_type                   varchar(30) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_one_way_rule PRIMARY KEY (id),
    CONSTRAINT ck_pricing_one_way_rule_1 CHECK (calculation_type IN ('FIXED','DISTANCE','PERCENTAGE','WAIVED','DENIED')),
    CONSTRAINT ck_pricing_one_way_rule_2 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE pricing_one_way_price (
    id                                 char(36) NOT NULL,
    one_way_rule_id                    char(36) NOT NULL,
    fixed_amount                       decimal(19,4),
    amount_per_km                      decimal(19,6),
    percentage_rate                    decimal(9,6),
    minimum_amount                     decimal(19,4),
    maximum_amount                     decimal(19,4),
    currency_code                      char(3),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_one_way_price PRIMARY KEY (id),
    CONSTRAINT uq_pricing_one_way_price_one_way_rule_id_1  UNIQUE (one_way_rule_id),
    CONSTRAINT ck_pricing_one_way_price_1 CHECK (fixed_amount IS NULL OR fixed_amount >= 0),
    CONSTRAINT ck_pricing_one_way_price_2 CHECK (amount_per_km IS NULL OR amount_per_km >= 0),
    CONSTRAINT ck_pricing_one_way_price_3 CHECK (percentage_rate IS NULL OR percentage_rate >= 0),
    CONSTRAINT ck_pricing_one_way_price_4 CHECK (minimum_amount IS NULL OR minimum_amount >= 0),
    CONSTRAINT ck_pricing_one_way_price_5 CHECK (maximum_amount IS NULL OR maximum_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE pricing_fuel_price (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    branch_id                          char(36),
    fuel_type                          varchar(30) NOT NULL,
    amount_per_liter                   decimal(19,6) NOT NULL,
    service_multiplier                 decimal(10,6) NOT NULL DEFAULT 1,
    currency_code                      char(3) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_fuel_price PRIMARY KEY (id),
    CONSTRAINT ck_pricing_fuel_price_1 CHECK (amount_per_liter >= 0),
    CONSTRAINT ck_pricing_fuel_price_2 CHECK (service_multiplier >= 0),
    CONSTRAINT ck_pricing_fuel_price_3 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE pricing_preauthorization_rule (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    vehicle_group_id                   char(36),
    customer_segment                   varchar(30),
    fixed_amount                       decimal(19,4),
    rental_multiplier                  decimal(10,6),
    minimum_amount                     decimal(19,4),
    maximum_amount                     decimal(19,4),
    currency_code                      char(3) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_preauthorization_rule PRIMARY KEY (id),
    CONSTRAINT ck_pricing_preauthorization_rule_1 CHECK (fixed_amount IS NULL OR fixed_amount >= 0),
    CONSTRAINT ck_pricing_preauthorization_rule_2 CHECK (rental_multiplier IS NULL OR rental_multiplier >= 0),
    CONSTRAINT ck_pricing_preauthorization_rule_3 CHECK (minimum_amount IS NULL OR minimum_amount >= 0),
    CONSTRAINT ck_pricing_preauthorization_rule_4 CHECK (maximum_amount IS NULL OR maximum_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE pricing_pricing_rule (
    id                                 char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    rule_type                          varchar(40) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    condition_json                     json NOT NULL,
    action_json                        json NOT NULL,
    valid_from                         datetime(6),
    valid_to                           datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_pricing_rule PRIMARY KEY (id),
    CONSTRAINT uq_pricing_pricing_rule_rate_plan_version_id_rule_code_1  UNIQUE (rate_plan_version_id, rule_code),
    CONSTRAINT ck_pricing_pricing_rule_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_pricing_pricing_rule_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE pricing_promotion (
    id                                 char(36) NOT NULL,
    promotion_code                     varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    stacking_policy                    varchar(30) NOT NULL,
    condition_json                     json,
    action_json                        json,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_promotion PRIMARY KEY (id),
    CONSTRAINT uq_pricing_promotion_promotion_code_1 UNIQUE (promotion_code),
    CONSTRAINT ck_pricing_promotion_1 CHECK (valid_to > valid_from),
    CONSTRAINT ck_pricing_promotion_2 CHECK (stacking_policy IN ('EXCLUSIVE','STACKABLE','BEST_ONLY')),
    CONSTRAINT ck_pricing_promotion_3 CHECK (status IN ('DRAFT','ACTIVE','PAUSED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE pricing_coupon (
    id                                 char(36) NOT NULL,
    promotion_id                       char(36) NOT NULL,
    coupon_code                        varchar(80) NOT NULL,
    maximum_redemptions                int,
    maximum_per_party                  int,
    valid_from                         datetime(6),
    valid_to                           datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_coupon PRIMARY KEY (id),
    CONSTRAINT uq_pricing_coupon_coupon_code_1 UNIQUE (coupon_code),
    CONSTRAINT ck_pricing_coupon_1 CHECK (maximum_redemptions IS NULL OR maximum_redemptions > 0),
    CONSTRAINT ck_pricing_coupon_2 CHECK (maximum_per_party IS NULL OR maximum_per_party > 0),
    CONSTRAINT ck_pricing_coupon_3 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_pricing_coupon_4 CHECK (status IN ('ACTIVE','PAUSED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE pricing_coupon_redemption (
    id                                 char(36) NOT NULL,
    coupon_id                          char(36) NOT NULL,
    party_id                           char(36),
    reservation_id                     char(36),
    quote_id                           char(36),
    redeemed_at                        datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_coupon_redemption PRIMARY KEY (id),
    CONSTRAINT uq_pricing_coupon_redemption_idempotency_key_1  UNIQUE (idempotency_key),
    CONSTRAINT ck_pricing_coupon_redemption_1 CHECK (status IN ('RESERVED','CONSUMED','RELEASED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE pricing_quote (
    id                                 char(36) NOT NULL,
    quote_number                       varchar(60) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    customer_account_id                char(36),
    rate_plan_version_id               char(36) NOT NULL,
    origin_branch_id                   char(36) NOT NULL,
    destination_branch_id              char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    channel_id                         char(36) NOT NULL,
    planned_pickup_at                  datetime(6) NOT NULL,
    planned_return_at                  datetime(6) NOT NULL,
    currency_code                      char(3) NOT NULL,
    subtotal_amount                    decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL,
    expires_at                         datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'VALID',
    context_json                       json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_pricing_quote PRIMARY KEY (id),
    CONSTRAINT uq_pricing_quote_legal_entity_id_quote_number_1  UNIQUE (legal_entity_id, quote_number),
    CONSTRAINT ck_pricing_quote_1 CHECK (planned_return_at > planned_pickup_at),
    CONSTRAINT ck_pricing_quote_2 CHECK (expires_at > created_at),
    CONSTRAINT ck_pricing_quote_3 CHECK (subtotal_amount >= 0),
    CONSTRAINT ck_pricing_quote_4 CHECK (discount_amount >= 0),
    CONSTRAINT ck_pricing_quote_5 CHECK (tax_amount >= 0),
    CONSTRAINT ck_pricing_quote_6 CHECK (total_amount >= 0),
    CONSTRAINT ck_pricing_quote_7 CHECK (status IN ('VALID','EXPIRED','CONVERTED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE pricing_quote_line (
    id                                 char(36) NOT NULL,
    quote_id                           char(36) NOT NULL,
    line_number                        int NOT NULL,
    product_id                         char(36),
    charge_type_id                     char(36),
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    service_start_at                   datetime(6),
    service_end_at                     datetime(6),
    rule_reference                     varchar(160),
    line_metadata                      json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_quote_line PRIMARY KEY (id),
    CONSTRAINT uq_pricing_quote_line_quote_id_line_number_1  UNIQUE (quote_id, line_number),
    CONSTRAINT ck_pricing_quote_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_pricing_quote_line_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_pricing_quote_line_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_pricing_quote_line_4 CHECK (gross_amount = base_amount - discount_amount + tax_amount),
    CONSTRAINT ck_pricing_quote_line_5 CHECK (service_end_at IS NULL OR service_start_at IS NULL OR service_end_at > service_start_at)
) ENGINE=InnoDB;

CREATE TABLE pricing_pricing_calculation (
    id                                 char(36) NOT NULL,
    quote_id                           char(36) NOT NULL,
    calculation_sequence               int NOT NULL,
    calculation_version                varchar(60) NOT NULL,
    input_hash                         varchar(64) NOT NULL,
    input_snapshot                     json NOT NULL,
    output_snapshot                    json NOT NULL,
    duration_ms                        int,
    calculated_at                      datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_pricing_calculation PRIMARY KEY (id),
    CONSTRAINT uq_pricing_pricing_calculation_quote_id_calculati_d1b53ccc  UNIQUE (quote_id, calculation_sequence),
    CONSTRAINT ck_pricing_pricing_calculation_1 CHECK (duration_ms IS NULL OR duration_ms >= 0)
) ENGINE=InnoDB;

CREATE TABLE pricing_quote_rule_trace (
    id                                 char(36) NOT NULL,
    pricing_calculation_id             char(36) NOT NULL,
    sequence_number                    int NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    matched                            boolean NOT NULL,
    condition_result                   json,
    action_result                      json,
    explanation                        text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_pricing_quote_rule_trace PRIMARY KEY (id),
    CONSTRAINT uq_pricing_quote_rule_trace_pricing_calculation_i_ea988f52  UNIQUE (pricing_calculation_id, sequence_number)
) ENGINE=InnoDB;

CREATE TABLE corporate_rate_entitlement (
    id                                 char(36) NOT NULL,
    corporate_agreement_id             char(36) NOT NULL,
    rate_plan_id                       char(36) NOT NULL,
    vehicle_group_id                   char(36),
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    priority                           smallint NOT NULL DEFAULT 100,
    constraints_json                   json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_corporate_rate_entitlement PRIMARY KEY (id),
    CONSTRAINT ck_corporate_rate_entitlement_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE corporate_purchase_order (
    id                                 char(36) NOT NULL,
    corporate_agreement_id             char(36) NOT NULL,
    purchase_order_number              varchar(80) NOT NULL,
    cost_center_id                     char(36),
    valid_from                         date,
    valid_to                           date,
    authorized_amount                  decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_purchase_order PRIMARY KEY (id),
    CONSTRAINT uq_corporate_purchase_order_corporate_agreement_i_393e33a8  UNIQUE (corporate_agreement_id, purchase_order_number),
    CONSTRAINT ck_corporate_purchase_order_1 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_corporate_purchase_order_2 CHECK (authorized_amount IS NULL OR authorized_amount >= 0),
    CONSTRAINT ck_corporate_purchase_order_3 CHECK (status IN ('ACTIVE','EXHAUSTED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE corporate_voucher (
    id                                 char(36) NOT NULL,
    corporate_agreement_id             char(36),
    partner_agreement_id               char(36),
    voucher_code                       varchar(100) NOT NULL,
    authorized_party_id                char(36),
    valid_from                         datetime(6),
    valid_to                           datetime(6),
    maximum_amount                     decimal(19,4),
    currency_code                      char(3),
    usage_limit                        int NOT NULL DEFAULT 1,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_corporate_voucher PRIMARY KEY (id),
    CONSTRAINT uq_corporate_voucher_voucher_code_1 UNIQUE (voucher_code),
    CONSTRAINT ck_corporate_voucher_1 CHECK (usage_limit > 0),
    CONSTRAINT ck_corporate_voucher_2 CHECK (maximum_amount IS NULL OR maximum_amount >= 0),
    CONSTRAINT ck_corporate_voucher_3 CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_corporate_voucher_4 CHECK (status IN ('ACTIVE','RESERVED','CONSUMED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE corporate_consolidated_billing_instruction (
    id                                 char(36) NOT NULL,
    corporate_billing_profile_id       char(36) NOT NULL,
    grouping_key                       varchar(40) NOT NULL,
    cutoff_day                         smallint,
    delivery_channel                   varchar(20) NOT NULL,
    recipient_contact_id               char(36),
    configuration_json                 json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_corporate_consolidated_billing_instruction  PRIMARY KEY (id),
    CONSTRAINT ck_corporate_consolidated_billing_instruction_1  CHECK (cutoff_day IS NULL OR cutoff_day BETWEEN 1 AND 31),
    CONSTRAINT ck_corporate_consolidated_billing_instruction_2  CHECK (delivery_channel IN ('EMAIL','SFTP','API','PORTAL')),
    CONSTRAINT ck_corporate_consolidated_billing_instruction_3  CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE availability_inventory_bucket (
    branch_id                          char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    bucket_start                       datetime(6) NOT NULL,
    local_business_date                date NOT NULL,
    projected_capacity_qty             int NOT NULL DEFAULT 0,
    blocked_qty                        int NOT NULL DEFAULT 0,
    safety_buffer_qty                  int NOT NULL DEFAULT 0,
    overbook_limit_qty                 int NOT NULL DEFAULT 0,
    held_qty                           int NOT NULL DEFAULT 0,
    committed_qty                      int NOT NULL DEFAULT 0,
    projection_version                 bigint NOT NULL DEFAULT 0,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_availability_inventory_bucket PRIMARY KEY (branch_id, vehicle_group_id, bucket_start),
    CONSTRAINT ck_availability_inventory_bucket_1 CHECK (projected_capacity_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_2 CHECK (blocked_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_3 CHECK (safety_buffer_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_4 CHECK (overbook_limit_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_5 CHECK (held_qty >= 0),
    CONSTRAINT ck_availability_inventory_bucket_6 CHECK (committed_qty >= 0)
) ENGINE=InnoDB;

CREATE TABLE availability_availability_hold (
    id                                 char(36) NOT NULL,
    hold_token                         varchar(120) NOT NULL,
    branch_id                          char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6) NOT NULL,
    quantity                           int NOT NULL DEFAULT 1,
    expires_at                         datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_type                        varchar(40),
    source_id                          char(36),
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_availability_hold PRIMARY KEY (id),
    CONSTRAINT uq_availability_availability_hold_hold_token_1  UNIQUE (hold_token),
    CONSTRAINT uq_availability_availability_hold_idempotency_key_2  UNIQUE (idempotency_key),
    CONSTRAINT ck_availability_availability_hold_1 CHECK (end_at > start_at),
    CONSTRAINT ck_availability_availability_hold_2 CHECK (quantity > 0),
    CONSTRAINT ck_availability_availability_hold_3 CHECK (expires_at > created_at),
    CONSTRAINT ck_availability_availability_hold_4 CHECK (status IN ('ACTIVE','CONVERTED','EXPIRED','RELEASED'))
) ENGINE=InnoDB;

CREATE TABLE availability_capacity_commitment (
    id                                 char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6) NOT NULL,
    quantity                           int NOT NULL DEFAULT 1,
    commitment_type                    varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    source_type                        varchar(40) NOT NULL,
    source_id                          char(36) NOT NULL,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_capacity_commitment PRIMARY KEY (id),
    CONSTRAINT uq_availability_capacity_commitment_idempotency_key_1  UNIQUE (idempotency_key),
    CONSTRAINT ck_availability_capacity_commitment_1 CHECK (end_at > start_at),
    CONSTRAINT ck_availability_capacity_commitment_2 CHECK (quantity > 0),
    CONSTRAINT ck_availability_capacity_commitment_3 CHECK (commitment_type IN ('RESERVATION','ALLOTMENT','MANUAL','BUFFER')),
    CONSTRAINT ck_availability_capacity_commitment_4 CHECK (status IN ('ACTIVE','CONSUMED','RELEASED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE availability_upgrade_path (
    id                                 char(36) NOT NULL,
    origin_branch_id                   char(36),
    from_group_id                      char(36) NOT NULL,
    to_group_id                        char(36) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    cost_policy                        varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_availability_upgrade_path PRIMARY KEY (id),
    CONSTRAINT uq_availability_upgrade_path_origin_branch_id_fro_bc702385  UNIQUE (origin_branch_id, from_group_id, to_group_id, valid_from),
    CONSTRAINT ck_availability_upgrade_path_1 CHECK (from_group_id <> to_group_id),
    CONSTRAINT ck_availability_upgrade_path_2 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_availability_upgrade_path_3 CHECK (cost_policy IN ('FREE','CUSTOMER_PAYS','MANAGER_APPROVAL')),
    CONSTRAINT ck_availability_upgrade_path_4 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE availability_fleet_allotment (
    id                                 char(36) NOT NULL,
    partner_agreement_id               char(36),
    corporate_agreement_id             char(36),
    branch_id                          char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6) NOT NULL,
    quantity                           int NOT NULL,
    release_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_availability_fleet_allotment PRIMARY KEY (id),
    CONSTRAINT ck_availability_fleet_allotment_1 CHECK (end_at > start_at),
    CONSTRAINT ck_availability_fleet_allotment_2 CHECK (quantity > 0),
    CONSTRAINT ck_availability_fleet_allotment_3 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE availability_relocation_order (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    order_number                       varchar(60) NOT NULL,
    origin_branch_id                   char(36) NOT NULL,
    destination_branch_id              char(36) NOT NULL,
    planned_departure_at               datetime(6) NOT NULL,
    planned_arrival_at                 datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    reason_code                        varchar(60),
    created_by                         char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_relocation_order PRIMARY KEY (id),
    CONSTRAINT uq_availability_relocation_order_legal_entity_id__2783fe4e  UNIQUE (legal_entity_id, order_number),
    CONSTRAINT ck_availability_relocation_order_1 CHECK (planned_arrival_at > planned_departure_at),
    CONSTRAINT ck_availability_relocation_order_2 CHECK (status IN ('PLANNED','DISPATCHED','IN_TRANSIT','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE availability_relocation_leg (
    id                                 char(36) NOT NULL,
    relocation_order_id                char(36) NOT NULL,
    sequence_number                    int NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    calendar_entry_id                  char(36),
    departed_at                        datetime(6),
    arrived_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_availability_relocation_leg PRIMARY KEY (id),
    CONSTRAINT uq_availability_relocation_leg_relocation_order_i_26aef275  UNIQUE (relocation_order_id, sequence_number),
    CONSTRAINT uq_availability_relocation_leg_relocation_order_i_53141511  UNIQUE (relocation_order_id, vehicle_id),
    CONSTRAINT ck_availability_relocation_leg_1 CHECK (arrived_at IS NULL OR departed_at IS NULL OR arrived_at >= departed_at),
    CONSTRAINT ck_availability_relocation_leg_2 CHECK (status IN ('PLANNED','IN_TRANSIT','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE availability_oversell_alert (
    id                                 char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    bucket_start                       datetime(6) NOT NULL,
    shortage_qty                       int NOT NULL,
    severity                           varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    detected_at                        datetime(6) NOT NULL,
    resolved_at                        datetime(6),
    resolution_note                    text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_availability_oversell_alert PRIMARY KEY (id),
    CONSTRAINT ck_availability_oversell_alert_1 CHECK (shortage_qty > 0),
    CONSTRAINT ck_availability_oversell_alert_2 CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_availability_oversell_alert_3 CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED','IGNORED'))
) ENGINE=InnoDB;

CREATE TABLE availability_forecast_snapshot (
    id                                 char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    bucket_start                       datetime(6) NOT NULL,
    forecast_version                   varchar(60) NOT NULL,
    expected_returns_qty               decimal(12,4) NOT NULL,
    expected_pickups_qty               decimal(12,4) NOT NULL,
    expected_no_show_qty               decimal(12,4) NOT NULL,
    confidence                         decimal(8,6),
    generated_at                       datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_availability_forecast_snapshot PRIMARY KEY (id),
    CONSTRAINT uq_availability_forecast_snapshot_branch_id_vehic_7bf6534b  UNIQUE (branch_id, vehicle_group_id, bucket_start, forecast_version),
    CONSTRAINT ck_availability_forecast_snapshot_1 CHECK (expected_returns_qty >= 0),
    CONSTRAINT ck_availability_forecast_snapshot_2 CHECK (expected_pickups_qty >= 0),
    CONSTRAINT ck_availability_forecast_snapshot_3 CHECK (expected_no_show_qty >= 0),
    CONSTRAINT ck_availability_forecast_snapshot_4 CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation (
    id                                 char(36) NOT NULL,
    reservation_number                 varchar(60) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    customer_account_id                char(36),
    booker_party_id                    char(36),
    requested_vehicle_group_id         char(36) NOT NULL,
    pickup_branch_id                   char(36) NOT NULL,
    planned_return_branch_id           char(36) NOT NULL,
    planned_pickup_at                  datetime(6) NOT NULL,
    planned_return_at                  datetime(6) NOT NULL,
    rental_mode                        varchar(30) NOT NULL,
    channel_id                         char(36) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    quote_id                           char(36),
    corporate_agreement_id             char(36),
    cost_center_id                     char(36),
    purchase_order_id                  char(36),
    voucher_id                         char(36),
    current_status                     varchar(20) NOT NULL DEFAULT 'DRAFT',
    guarantee_status                   varchar(20) NOT NULL DEFAULT 'NOT_REQUIRED',
    expires_at                         datetime(6),
    external_reference                 varchar(160),
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_reservation_reservation PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_legal_entity_id_reserv_ab7bda09  UNIQUE (legal_entity_id, reservation_number),
    CONSTRAINT ck_reservation_reservation_1 CHECK (planned_return_at > planned_pickup_at),
    CONSTRAINT ck_reservation_reservation_2 CHECK (rental_mode IN ('HOURLY','DAILY','WEEKLY','MONTHLY','CORPORATE')),
    CONSTRAINT ck_reservation_reservation_3 CHECK (current_status IN ('DRAFT','HELD','CONFIRMED','PICKUP_READY','CONVERTED','CANCELLED','EXPIRED','NO_SHOW')),
    CONSTRAINT ck_reservation_reservation_4 CHECK (guarantee_status IN ('NOT_REQUIRED','PENDING','AUTHORIZED','FAILED','EXPIRED','RELEASED'))
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_driver (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    driver_profile_id                  char(36) NOT NULL,
    driver_role                        varchar(20) NOT NULL,
    eligibility_status                 varchar(20) NOT NULL DEFAULT 'PENDING',
    eligibility_checked_at             datetime(6),
    young_driver_applies               boolean NOT NULL DEFAULT FALSE,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_driver PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_driver_reservation_id__5504cc73  UNIQUE (reservation_id, driver_profile_id),
    CONSTRAINT ck_reservation_reservation_driver_1 CHECK (driver_role IN ('PRIMARY','ADDITIONAL')),
    CONSTRAINT ck_reservation_reservation_driver_2 CHECK (eligibility_status IN ('PENDING','ELIGIBLE','INELIGIBLE','REVIEW'))
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_product (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    product_id                         char(36) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    configuration_json                 json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_product PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_product_reservation_id_937dcf71  UNIQUE (reservation_id, product_id),
    CONSTRAINT ck_reservation_reservation_product_1 CHECK (quantity > 0),
    CONSTRAINT ck_reservation_reservation_product_2 CHECK (status IN ('ACTIVE','REMOVED','UNAVAILABLE'))
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_price_line (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    line_number                        int NOT NULL,
    quote_line_id                      char(36),
    product_id                         char(36),
    charge_type_id                     char(36),
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    rule_reference                     varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_price_line PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_price_line_reservation_653da8d8  UNIQUE (reservation_id, line_number),
    CONSTRAINT ck_reservation_reservation_price_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_reservation_reservation_price_line_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_reservation_reservation_price_line_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_reservation_reservation_price_line_4 CHECK (gross_amount = base_amount - discount_amount + tax_amount)
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_status_history (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         char(36),
    changed_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_status_history PRIMARY KEY (id),
    CONSTRAINT ck_reservation_reservation_status_history_1  CHECK (to_status IN ('DRAFT','HELD','CONFIRMED','PICKUP_READY','CONVERTED','CANCELLED','EXPIRED','NO_SHOW'))
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_change (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    change_sequence                    int NOT NULL,
    change_type                        varchar(40) NOT NULL,
    requested_by_party_id              char(36),
    previous_snapshot                  json NOT NULL,
    new_snapshot                       json NOT NULL,
    price_delta_amount                 decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    changed_at                         datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_change PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_change_reservation_id__fa6280d3  UNIQUE (reservation_id, change_sequence)
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_cancellation (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    cancelled_at                       datetime(6) NOT NULL,
    cancelled_by_party_id              char(36),
    reason_code                        varchar(60) NOT NULL,
    reason_text                        text,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    policy_rule_reference              varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_cancellation PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_cancellation_reservation_id_1  UNIQUE (reservation_id),
    CONSTRAINT ck_reservation_reservation_cancellation_1 CHECK (fee_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE reservation_no_show_assessment (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    assessed_at                        datetime(6) NOT NULL,
    grace_period_minutes               int NOT NULL,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    rule_reference                     varchar(160),
    waived                             boolean NOT NULL DEFAULT FALSE,
    waiver_reason                      text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_no_show_assessment PRIMARY KEY (id),
    CONSTRAINT uq_reservation_no_show_assessment_reservation_id_1  UNIQUE (reservation_id),
    CONSTRAINT ck_reservation_no_show_assessment_1 CHECK (grace_period_minutes >= 0),
    CONSTRAINT ck_reservation_no_show_assessment_2 CHECK (fee_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_guarantee (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    guarantee_type                     varchar(30) NOT NULL,
    amount                             decimal(19,4),
    currency_code                      char(3),
    provider_reference                 varchar(160),
    status                             varchar(20) NOT NULL,
    authorized_at                      datetime(6),
    expires_at                         datetime(6),
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_reservation_reservation_guarantee PRIMARY KEY (id),
    CONSTRAINT uq_reservation_reservation_guarantee_idempotency_key_1  UNIQUE (idempotency_key),
    CONSTRAINT ck_reservation_reservation_guarantee_1 CHECK (amount IS NULL OR amount >= 0),
    CONSTRAINT ck_reservation_reservation_guarantee_2 CHECK (guarantee_type IN ('CARD_PREAUTH','VOUCHER','CORPORATE_CREDIT','PREPAYMENT','NONE')),
    CONSTRAINT ck_reservation_reservation_guarantee_3 CHECK (status IN ('PENDING','AUTHORIZED','FAILED','EXPIRED','RELEASED','CONSUMED'))
) ENGINE=InnoDB;

CREATE TABLE reservation_partner_booking (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    partner_id                         char(36) NOT NULL,
    partner_agreement_id               char(36),
    external_booking_reference         varchar(160) NOT NULL,
    external_status                    varchar(60),
    commission_amount                  decimal(19,4),
    currency_code                      char(3),
    raw_payload                        json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_partner_booking PRIMARY KEY (id),
    CONSTRAINT uq_reservation_partner_booking_partner_id_externa_083fe7a4  UNIQUE (partner_id, external_booking_reference),
    CONSTRAINT ck_reservation_partner_booking_1 CHECK (commission_amount IS NULL OR commission_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE reservation_digital_pickup_eligibility (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    eligible                           boolean NOT NULL,
    decision                           varchar(20) NOT NULL,
    reason_codes                       json,
    rule_version                       varchar(60),
    assessed_at                        datetime(6) NOT NULL,
    expires_at                         datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_digital_pickup_eligibility PRIMARY KEY (id),
    CONSTRAINT ck_reservation_digital_pickup_eligibility_1  CHECK (decision IN ('ELIGIBLE','INELIGIBLE','REVIEW')),
    CONSTRAINT ck_reservation_digital_pickup_eligibility_2  CHECK (expires_at IS NULL OR expires_at > assessed_at)
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_note (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    note_type                          varchar(30) NOT NULL,
    note_text                          text NOT NULL,
    visibility                         varchar(20) NOT NULL,
    created_by                         char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_note PRIMARY KEY (id),
    CONSTRAINT ck_reservation_reservation_note_1 CHECK (visibility IN ('INTERNAL','CUSTOMER_VISIBLE','PARTNER_VISIBLE'))
) ENGINE=InnoDB;

CREATE TABLE reservation_reservation_inventory_commitment (
    id                                 char(36) NOT NULL,
    reservation_id                     char(36) NOT NULL,
    availability_hold_id               char(36),
    capacity_commitment_id             char(36),
    relation_type                      varchar(20) NOT NULL,
    linked_at                          datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_reservation_reservation_inventory_commitment  PRIMARY KEY (id),
    CONSTRAINT ck_reservation_reservation_inventory_commitment_1  CHECK (relation_type IN ('HOLD','COMMITMENT')),
    CONSTRAINT ck_reservation_reservation_inventory_commitment_2  CHECK ((relation_type = 'HOLD' AND availability_hold_id IS NOT NULL AND capacity_commitment_id IS NULL) OR ( relation_type = 'COMMITMENT' AND capacity_commitment_id IS NOT NULL AND availability_hold_id IS NULL))
) ENGINE=InnoDB;

CREATE TABLE rental_rental_contract (
    id                                 char(36) NOT NULL,
    contract_number                    varchar(60) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    reservation_id                     char(36),
    customer_account_id                char(36) NOT NULL,
    origin_branch_id                   char(36) NOT NULL,
    planned_return_branch_id           char(36) NOT NULL,
    actual_return_branch_id            char(36),
    rental_mode                        varchar(30) NOT NULL,
    mileage_package_id                 char(36),
    opened_at                          datetime(6) NOT NULL,
    activated_at                       datetime(6),
    planned_return_at                  datetime(6) NOT NULL,
    actual_return_at                   datetime(6),
    current_revision_number            int NOT NULL DEFAULT 0,
    current_status                     varchar(20) NOT NULL DEFAULT 'OPENING',
    currency_code                      char(3) NOT NULL,
    created_channel_id                 char(36) NOT NULL,
    closed_reason                      varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_rental_contract PRIMARY KEY (id),
    CONSTRAINT uq_rental_rental_contract_legal_entity_id_contrac_e46b4872  UNIQUE (legal_entity_id, contract_number),
    CONSTRAINT uq_rental_rental_contract_reservation_id_2  UNIQUE (reservation_id),
    CONSTRAINT ck_rental_rental_contract_1 CHECK (planned_return_at > opened_at),
    CONSTRAINT ck_rental_rental_contract_2 CHECK (actual_return_at IS NULL OR actual_return_at >= opened_at),
    CONSTRAINT ck_rental_rental_contract_3 CHECK (activated_at IS NULL OR activated_at >= opened_at),
    CONSTRAINT ck_rental_rental_contract_4 CHECK (rental_mode IN ('HOURLY','DAILY','WEEKLY','MONTHLY','CORPORATE')),
    CONSTRAINT ck_rental_rental_contract_5 CHECK (current_status IN ('OPENING','ACTIVE','OVERDUE','RETURN_PENDING','CLOSED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE rental_contract_revision (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    revision_number                    int NOT NULL,
    previous_revision_id               char(36),
    reason_code                        varchar(60) NOT NULL,
    effective_at                       datetime(6) NOT NULL,
    document_hash                      varchar(64),
    pricing_snapshot_hash              varchar(64),
    snapshot_json                      json NOT NULL,
    created_by                         char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_contract_revision PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_revision_contract_id_revision_number_1  UNIQUE (contract_id, revision_number),
    CONSTRAINT ck_rental_contract_revision_1 CHECK (revision_number >= 0)
) ENGINE=InnoDB;

CREATE TABLE rental_contract_party_role (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    role_type                          varchar(30) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    source_type                        varchar(40),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_contract_party_role PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_party_role_contract_id_party_i_4a6cbbeb  UNIQUE (contract_id, party_id, role_type, valid_from),
    CONSTRAINT ck_rental_contract_party_role_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_rental_contract_party_role_2 CHECK (role_type IN ('CUSTOMER','BOOKER','CORPORATE_USER','REPRESENTATIVE','PRIMARY_DRIVER','ADDITIONAL_DRIVER','PAYER','BENEFICIARY'))
) ENGINE=InnoDB;

CREATE TABLE rental_contract_product (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    product_id                         char(36) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    locked_at_activation               boolean NOT NULL DEFAULT FALSE,
    configuration_json                 json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_contract_product PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_product_contract_id_product_id_1  UNIQUE (contract_id, product_id),
    CONSTRAINT ck_rental_contract_product_1 CHECK (quantity > 0),
    CONSTRAINT ck_rental_contract_product_2 CHECK (status IN ('ACTIVE','REMOVED','CONSUMED'))
) ENGINE=InnoDB;

CREATE TABLE rental_contract_price_snapshot_line (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    contract_revision_id               char(36) NOT NULL,
    line_number                        int NOT NULL,
    reservation_price_line_id          char(36),
    product_id                         char(36),
    charge_type_id                     char(36),
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    rate_plan_version_id               char(36) NOT NULL,
    rule_reference                     varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_contract_price_snapshot_line PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_price_snapshot_line_contract_r_0abd84bf  UNIQUE (contract_revision_id, line_number),
    CONSTRAINT ck_rental_contract_price_snapshot_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_rental_contract_price_snapshot_line_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_rental_contract_price_snapshot_line_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_rental_contract_price_snapshot_line_4 CHECK (gross_amount = base_amount - discount_amount + tax_amount)
) ENGINE=InnoDB;

CREATE TABLE rental_vehicle_assignment (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    calendar_entry_id                  char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    sequence_number                    smallint NOT NULL,
    pickup_branch_id                   char(36) NOT NULL,
    planned_return_branch_id           char(36) NOT NULL,
    actual_return_branch_id            char(36),
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    assignment_reason                  varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_vehicle_assignment PRIMARY KEY (id),
    CONSTRAINT uq_rental_vehicle_assignment_contract_id_sequence_number_1  UNIQUE (contract_id, sequence_number),
    CONSTRAINT uq_rental_vehicle_assignment_calendar_entry_id_2  UNIQUE (calendar_entry_id),
    CONSTRAINT ck_rental_vehicle_assignment_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_rental_vehicle_assignment_2 CHECK (assignment_reason IN ('INITIAL','REPLACEMENT')),
    CONSTRAINT ck_rental_vehicle_assignment_3 CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE rental_pickup_event (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    vehicle_assignment_id              char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    picked_up_at                       datetime(6) NOT NULL,
    odometer_reading_id                char(36) NOT NULL,
    fuel_reading_id                    char(36),
    inspection_id                      char(36),
    performed_by                       char(36),
    digital_pickup                     boolean NOT NULL DEFAULT FALSE,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_pickup_event PRIMARY KEY (id),
    CONSTRAINT uq_rental_pickup_event_vehicle_assignment_id_1  UNIQUE (vehicle_assignment_id)
) ENGINE=InnoDB;

CREATE TABLE rental_return_event (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    vehicle_assignment_id              char(36) NOT NULL,
    branch_id                          char(36) NOT NULL,
    returned_at                        datetime(6) NOT NULL,
    odometer_reading_id                char(36) NOT NULL,
    fuel_reading_id                    char(36),
    inspection_id                      char(36),
    performed_by                       char(36),
    after_hours                        boolean NOT NULL DEFAULT FALSE,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_return_event PRIMARY KEY (id),
    CONSTRAINT uq_rental_return_event_vehicle_assignment_id_1  UNIQUE (vehicle_assignment_id)
) ENGINE=InnoDB;

CREATE TABLE rental_extension (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    requested_at                       datetime(6) NOT NULL,
    requested_by_party_id              char(36),
    previous_planned_return_at         datetime(6) NOT NULL,
    new_planned_return_at              datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    availability_checked_at            datetime(6),
    payment_checked_at                 datetime(6),
    price_delta_amount                 decimal(19,4),
    currency_code                      char(3),
    decision_reason                    text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_extension PRIMARY KEY (id),
    CONSTRAINT ck_rental_extension_1 CHECK (new_planned_return_at > previous_planned_return_at),
    CONSTRAINT ck_rental_extension_2 CHECK (status IN ('REQUESTED','APPROVED','REJECTED','CANCELLED','APPLIED'))
) ENGINE=InnoDB;

CREATE TABLE rental_vehicle_replacement (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    previous_assignment_id             char(36) NOT NULL,
    new_assignment_id                  char(36) NOT NULL,
    reason_code                        varchar(60) NOT NULL,
    replaced_at                        datetime(6) NOT NULL,
    authorized_by                      char(36),
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_vehicle_replacement PRIMARY KEY (id),
    CONSTRAINT uq_rental_vehicle_replacement_previous_assignment_id_1  UNIQUE (previous_assignment_id),
    CONSTRAINT uq_rental_vehicle_replacement_new_assignment_id_2  UNIQUE (new_assignment_id),
    CONSTRAINT ck_rental_vehicle_replacement_1 CHECK (previous_assignment_id <> new_assignment_id)
) ENGINE=InnoDB;

CREATE TABLE rental_contract_status_history (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    from_status                        varchar(40),
    to_status                          varchar(40) NOT NULL,
    reason_code                        varchar(60),
    reason_text                        text,
    changed_by                         char(36),
    changed_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_contract_status_history PRIMARY KEY (id),
    CONSTRAINT ck_rental_contract_status_history_1 CHECK (to_status IN ('OPENING','ACTIVE','OVERDUE','RETURN_PENDING','CLOSED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE rental_contract_terms_acceptance (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    contract_revision_id               char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    terms_type                         varchar(40) NOT NULL,
    terms_version                      varchar(60) NOT NULL,
    accepted_at                        datetime(6) NOT NULL,
    channel_id                         char(36),
    evidence_hash                      varchar(64) NOT NULL,
    ip_address_token                   varchar(100),
    device_reference                   varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_contract_terms_acceptance PRIMARY KEY (id),
    CONSTRAINT uq_rental_contract_terms_acceptance_contract_revi_e69987ad  UNIQUE (contract_revision_id, party_id, terms_type, terms_version)
) ENGINE=InnoDB;

CREATE TABLE rental_contract_document (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    contract_revision_id               char(36),
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             binary(32),
    generated_at                       datetime(6) NOT NULL,
    signed_at                          datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_rental_contract_document PRIMARY KEY (id),
    CONSTRAINT ck_rental_contract_document_1 CHECK (status IN ('ACTIVE','SUPERSEDED','VOID'))
) ENGINE=InnoDB;

CREATE TABLE rental_digital_pickup_session (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    reservation_id                     char(36),
    party_id                           char(36) NOT NULL,
    session_token_hash                 binary(32) NOT NULL,
    started_at                         datetime(6) NOT NULL,
    expires_at                         datetime(6) NOT NULL,
    completed_at                       datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'STARTED',
    failure_reason                     varchar(120),
    device_reference                   varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_digital_pickup_session PRIMARY KEY (id),
    CONSTRAINT uq_rental_digital_pickup_session_session_token_hash_1  UNIQUE (session_token_hash),
    CONSTRAINT ck_rental_digital_pickup_session_1 CHECK (expires_at > started_at),
    CONSTRAINT ck_rental_digital_pickup_session_2 CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ck_rental_digital_pickup_session_3 CHECK (status IN ('STARTED','IDENTITY_VERIFIED','PAYMENT_VERIFIED','READY','COMPLETED','FAILED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE rental_vehicle_access_credential (
    id                                 char(36) NOT NULL,
    digital_pickup_session_id          char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    credential_type                    varchar(30) NOT NULL,
    credential_token_ciphertext        text NOT NULL,
    issued_at                          datetime(6) NOT NULL,
    expires_at                         datetime(6) NOT NULL,
    revoked_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_vehicle_access_credential PRIMARY KEY (id),
    CONSTRAINT ck_rental_vehicle_access_credential_1 CHECK (expires_at > issued_at),
    CONSTRAINT ck_rental_vehicle_access_credential_2 CHECK (revoked_at IS NULL OR revoked_at >= issued_at),
    CONSTRAINT ck_rental_vehicle_access_credential_3 CHECK (credential_type IN ('DIGITAL_KEY','PIN','BLUETOOTH_TOKEN','NFC_TOKEN')),
    CONSTRAINT ck_rental_vehicle_access_credential_4 CHECK (status IN ('ACTIVE','USED','EXPIRED','REVOKED'))
) ENGINE=InnoDB;

CREATE TABLE rental_vehicle_access_command (
    id                                 char(36) NOT NULL,
    contract_id                        char(36),
    vehicle_id                         char(36) NOT NULL,
    command_type                       varchar(30) NOT NULL,
    requested_by                       char(36),
    reason_code                        varchar(60),
    requested_at                       datetime(6) NOT NULL,
    expires_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    provider_reference                 varchar(160),
    result_code                        varchar(60),
    completed_at                       datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_vehicle_access_command PRIMARY KEY (id),
    CONSTRAINT ck_rental_vehicle_access_command_1 CHECK (command_type IN ('UNLOCK','LOCK','START_ENABLE','START_DISABLE','HORN','LIGHTS')),
    CONSTRAINT ck_rental_vehicle_access_command_2 CHECK (status IN ('REQUESTED','SENT','ACKNOWLEDGED','SUCCEEDED','FAILED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_rental_vehicle_access_command_3 CHECK (expires_at IS NULL OR expires_at > requested_at)
) ENGINE=InnoDB;

CREATE TABLE rental_overdue_case (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    opened_at                          datetime(6) NOT NULL,
    severity                           varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    last_contact_at                    datetime(6),
    next_action_at                     datetime(6),
    assigned_to                        char(36),
    resolution_code                    varchar(60),
    closed_at                          datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_overdue_case PRIMARY KEY (id),
    CONSTRAINT uq_rental_overdue_case_contract_id_1 UNIQUE (contract_id),
    CONSTRAINT ck_rental_overdue_case_1 CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_rental_overdue_case_2 CHECK (status IN ('OPEN','CONTACTING','ESCALATED','RECOVERY','CLOSED')),
    CONSTRAINT ck_rental_overdue_case_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
) ENGINE=InnoDB;

CREATE TABLE rental_contract_reprocessing (
    id                                 char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    requested_at                       datetime(6) NOT NULL,
    requested_by                       char(36),
    reason_code                        varchar(60) NOT NULL,
    previous_revision_number           int NOT NULL,
    new_revision_number                int,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    financial_delta_amount             decimal(19,4),
    currency_code                      char(3),
    result_json                        json,
    completed_at                       datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_rental_contract_reprocessing PRIMARY KEY (id),
    CONSTRAINT ck_rental_contract_reprocessing_1 CHECK (status IN ('REQUESTED','PROCESSING','COMPLETED','FAILED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE inspection_inspection_template (
    id                                 char(36) NOT NULL,
    template_code                      varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    inspection_type                    varchar(30) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_inspection_template PRIMARY KEY (id),
    CONSTRAINT uq_inspection_inspection_template_template_code_v_2484f4a5  UNIQUE (template_code, version_number),
    CONSTRAINT ck_inspection_inspection_template_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_inspection_inspection_template_2 CHECK (inspection_type IN ('PICKUP','RETURN','MAINTENANCE','TRANSFER','SALE','AD_HOC')),
    CONSTRAINT ck_inspection_inspection_template_3 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE inspection_inspection_template_item (
    id                                 char(36) NOT NULL,
    inspection_template_id             char(36) NOT NULL,
    item_code                          varchar(50) NOT NULL,
    label                              varchar(160) NOT NULL,
    item_type                          varchar(30) NOT NULL,
    required                           boolean NOT NULL DEFAULT TRUE,
    sort_order                         int NOT NULL DEFAULT 0,
    configuration_json                 json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_inspection_inspection_template_item PRIMARY KEY (id),
    CONSTRAINT uq_inspection_inspection_template_item_inspection_a33ef367  UNIQUE (inspection_template_id, item_code),
    CONSTRAINT ck_inspection_inspection_template_item_1 CHECK (item_type IN ('BOOLEAN','TEXT','NUMBER','CHOICE','PHOTO','ODOMETER','FUEL','DAMAGE_MAP','SIGNATURE'))
) ENGINE=InnoDB;

CREATE TABLE inspection_inspection (
    id                                 char(36) NOT NULL,
    inspection_template_id             char(36) NOT NULL,
    inspection_type                    varchar(30) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    contract_id                        char(36),
    vehicle_assignment_id              char(36),
    branch_id                          char(36),
    started_at                         datetime(6) NOT NULL,
    completed_at                       datetime(6),
    performed_by                       char(36),
    status                             varchar(20) NOT NULL DEFAULT 'IN_PROGRESS',
    device_reference                   varchar(160),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_inspection PRIMARY KEY (id),
    CONSTRAINT ck_inspection_inspection_1 CHECK (completed_at IS NULL OR completed_at >= started_at),
    CONSTRAINT ck_inspection_inspection_2 CHECK (inspection_type IN ('PICKUP','RETURN','MAINTENANCE','TRANSFER','SALE','AD_HOC')),
    CONSTRAINT ck_inspection_inspection_3 CHECK (status IN ('IN_PROGRESS','COMPLETED','CANCELLED','SUPERSEDED'))
) ENGINE=InnoDB;

CREATE TABLE inspection_inspection_item_result (
    id                                 char(36) NOT NULL,
    inspection_id                      char(36) NOT NULL,
    template_item_id                   char(36) NOT NULL,
    result_text                        text,
    result_number                      decimal(19,6),
    result_boolean                     boolean,
    result_json                        json,
    passed                             boolean,
    observed_at                        datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_inspection_inspection_item_result PRIMARY KEY (id),
    CONSTRAINT uq_inspection_inspection_item_result_inspection_i_72157564  UNIQUE (inspection_id, template_item_id)
) ENGINE=InnoDB;

CREATE TABLE inspection_inspection_media (
    id                                 char(36) NOT NULL,
    inspection_id                      char(36) NOT NULL,
    template_item_id                   char(36),
    media_type                         varchar(20) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             binary(32),
    captured_at                        datetime(6) NOT NULL,
    captured_by                        char(36),
    device_reference                   varchar(160),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_inspection_inspection_media PRIMARY KEY (id),
    CONSTRAINT ck_inspection_inspection_media_1 CHECK (media_type IN ('PHOTO','VIDEO','AUDIO','SIGNATURE','DOCUMENT'))
) ENGINE=InnoDB;

CREATE TABLE inspection_damage_record (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    body_part                          varchar(60) NOT NULL,
    damage_type                        varchar(40) NOT NULL,
    position_x                         decimal(8,5),
    position_y                         decimal(8,5),
    severity                           varchar(20) NOT NULL,
    first_observed_at                  datetime(6) NOT NULL,
    resolved_at                        datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_record PRIMARY KEY (id),
    CONSTRAINT ck_inspection_damage_record_1 CHECK (position_x IS NULL OR (position_x >= 0 AND position_x <= 1)),
    CONSTRAINT ck_inspection_damage_record_2 CHECK (position_y IS NULL OR (position_y >= 0 AND position_y <= 1)),
    CONSTRAINT ck_inspection_damage_record_3 CHECK (severity IN ('COSMETIC','MINOR','MODERATE','MAJOR','SAFETY')),
    CONSTRAINT ck_inspection_damage_record_4 CHECK (status IN ('OPEN','MONITORED','REPAIRED','WRITTEN_OFF')),
    CONSTRAINT ck_inspection_damage_record_5 CHECK (resolved_at IS NULL OR resolved_at >= first_observed_at)
) ENGINE=InnoDB;

CREATE TABLE inspection_damage_observation (
    id                                 char(36) NOT NULL,
    damage_record_id                   char(36) NOT NULL,
    inspection_id                      char(36) NOT NULL,
    observed_status                    varchar(20) NOT NULL,
    severity                           varchar(20) NOT NULL,
    media_id                           char(36),
    notes                              text,
    observed_at                        datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_inspection_damage_observation PRIMARY KEY (id),
    CONSTRAINT uq_inspection_damage_observation_damage_record_id_7eccb3ff  UNIQUE (damage_record_id, inspection_id),
    CONSTRAINT ck_inspection_damage_observation_1 CHECK (observed_status IN ('EXISTING','NEW','WORSENED','UNCHANGED','RESOLVED')),
    CONSTRAINT ck_inspection_damage_observation_2 CHECK (severity IN ('COSMETIC','MINOR','MODERATE','MAJOR','SAFETY'))
) ENGINE=InnoDB;

CREATE TABLE inspection_damage_attribution (
    id                                 char(36) NOT NULL,
    damage_record_id                   char(36) NOT NULL,
    contract_id                        char(36),
    incident_id                        char(36),
    attribution_status                 varchar(20) NOT NULL,
    decision_reason                    text,
    decided_at                         datetime(6),
    decided_by                         char(36),
    responsible_party_id               char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_attribution PRIMARY KEY (id),
    CONSTRAINT ck_inspection_damage_attribution_1 CHECK (attribution_status IN ('PENDING','CUSTOMER','COMPANY','THIRD_PARTY','PRE_EXISTING','UNDETERMINED','WAIVED'))
) ENGINE=InnoDB;

CREATE TABLE inspection_damage_assessment (
    id                                 char(36) NOT NULL,
    damage_record_id                   char(36) NOT NULL,
    contract_id                        char(36),
    assessment_version                 int NOT NULL,
    assessed_at                        datetime(6) NOT NULL,
    repair_estimate_amount             decimal(19,4),
    downtime_amount                    decimal(19,4),
    administrative_amount              decimal(19,4),
    customer_charge_amount             decimal(19,4),
    currency_code                      char(3),
    method                             varchar(30) NOT NULL,
    assessor_party_id                  char(36),
    price_table_version                varchar(60),
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_assessment PRIMARY KEY (id),
    CONSTRAINT uq_inspection_damage_assessment_damage_record_id__e1fad7c0  UNIQUE (damage_record_id, assessment_version),
    CONSTRAINT ck_inspection_damage_assessment_1 CHECK (repair_estimate_amount IS NULL OR repair_estimate_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_2 CHECK (downtime_amount IS NULL OR downtime_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_3 CHECK (administrative_amount IS NULL OR administrative_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_4 CHECK (customer_charge_amount IS NULL OR customer_charge_amount >= 0),
    CONSTRAINT ck_inspection_damage_assessment_5 CHECK (method IN ('PRICE_TABLE','MANUAL_ESTIMATE','WORKSHOP_QUOTE','INSURER')),
    CONSTRAINT ck_inspection_damage_assessment_6 CHECK (status IN ('DRAFT','APPROVED','REJECTED','SUPERSEDED'))
) ENGINE=InnoDB;

CREATE TABLE inspection_damage_price_table_version (
    id                                 char(36) NOT NULL,
    table_code                         varchar(50) NOT NULL,
    version_number                     int NOT NULL,
    country_code                       char(2) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    currency_code                      char(3) NOT NULL,
    price_data                         json NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_damage_price_table_version PRIMARY KEY (id),
    CONSTRAINT uq_inspection_damage_price_table_version_table_co_a76ef88e  UNIQUE (table_code, version_number),
    CONSTRAINT ck_inspection_damage_price_table_version_1  CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_inspection_damage_price_table_version_2  CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE inspection_fuel_assessment (
    id                                 char(36) NOT NULL,
    inspection_id                      char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    pickup_level_percent               decimal(5,2) NOT NULL,
    return_level_percent               decimal(5,2) NOT NULL,
    missing_liters                     decimal(10,3) NOT NULL DEFAULT 0,
    unit_price                         decimal(19,6) NOT NULL DEFAULT 0,
    service_fee_amount                 decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    fuel_price_id                      char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_inspection_fuel_assessment PRIMARY KEY (id),
    CONSTRAINT uq_inspection_fuel_assessment_inspection_id_1  UNIQUE (inspection_id),
    CONSTRAINT ck_inspection_fuel_assessment_1 CHECK (pickup_level_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_inspection_fuel_assessment_2 CHECK (return_level_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_inspection_fuel_assessment_3 CHECK (missing_liters >= 0),
    CONSTRAINT ck_inspection_fuel_assessment_4 CHECK (unit_price >= 0),
    CONSTRAINT ck_inspection_fuel_assessment_5 CHECK (service_fee_amount >= 0),
    CONSTRAINT ck_inspection_fuel_assessment_6 CHECK (total_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE inspection_cleaning_assessment (
    id                                 char(36) NOT NULL,
    inspection_id                      char(36) NOT NULL,
    contract_id                        char(36) NOT NULL,
    cleaning_level                     varchar(20) NOT NULL,
    chargeable                         boolean NOT NULL,
    amount                             decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    reason_codes                       json,
    approved_by                        char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_inspection_cleaning_assessment PRIMARY KEY (id),
    CONSTRAINT uq_inspection_cleaning_assessment_inspection_id_1  UNIQUE (inspection_id),
    CONSTRAINT ck_inspection_cleaning_assessment_1 CHECK (cleaning_level IN ('NORMAL','SPECIAL','BIOHAZARD','SMOKE','PET','EXTREME')),
    CONSTRAINT ck_inspection_cleaning_assessment_2 CHECK (amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE inspection_lost_found_item (
    id                                 char(36) NOT NULL,
    inspection_id                      char(36) NOT NULL,
    contract_id                        char(36),
    item_description                   varchar(240) NOT NULL,
    found_at                           datetime(6) NOT NULL,
    storage_location                   varchar(120),
    status                             varchar(20) NOT NULL DEFAULT 'STORED',
    released_to_party_id               char(36),
    released_at                        datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_inspection_lost_found_item PRIMARY KEY (id),
    CONSTRAINT ck_inspection_lost_found_item_1 CHECK (status IN ('STORED','CUSTOMER_NOTIFIED','RELEASED','DISPOSED','TRANSFERRED_TO_AUTHORITY'))
) ENGINE=InnoDB;

CREATE TABLE billing_payment_method_token (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    provider                           varchar(60) NOT NULL,
    provider_customer_reference        varchar(160),
    payment_token_ciphertext           text NOT NULL,
    fingerprint                        varchar(160),
    brand                              varchar(40),
    last4                              char(4),
    expiry_month                       smallint,
    expiry_year                        smallint,
    billing_address_id                 char(36),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_payment_method_token PRIMARY KEY (id),
    CONSTRAINT ck_billing_payment_method_token_1 CHECK (expiry_month IS NULL OR expiry_month BETWEEN 1 AND 12),
    CONSTRAINT ck_billing_payment_method_token_2 CHECK (expiry_year IS NULL OR expiry_year >= 2000),
    CONSTRAINT ck_billing_payment_method_token_3 CHECK (status IN ('ACTIVE','EXPIRED','REVOKED','FAILED'))
) ENGINE=InnoDB;

CREATE TABLE billing_charge (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    contract_id                        char(36),
    reservation_id                     char(36),
    charge_type_id                     char(36) NOT NULL,
    source_context                     varchar(40) NOT NULL,
    source_id                          char(36) NOT NULL,
    source_event_id                    varchar(160),
    service_start_at                   datetime(6),
    service_end_at                     datetime(6),
    quantity                           decimal(19,6) NOT NULL DEFAULT 1,
    unit_code                          varchar(20) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    base_amount                        decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    rate_plan_version_id               char(36),
    rule_reference                     varchar(160),
    posting_status                     varchar(20) NOT NULL DEFAULT 'DRAFT',
    reversal_of_charge_id              char(36),
    idempotency_key                    varchar(160) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    posted_at                          datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_charge PRIMARY KEY (id),
    CONSTRAINT uq_billing_charge_legal_entity_id_idempotency_key_1  UNIQUE (legal_entity_id, idempotency_key),
    CONSTRAINT ck_billing_charge_1 CHECK (service_end_at IS NULL OR service_start_at IS NULL OR service_end_at > service_start_at),
    CONSTRAINT ck_billing_charge_2 CHECK (quantity > 0),
    CONSTRAINT ck_billing_charge_3 CHECK (discount_amount >= 0),
    CONSTRAINT ck_billing_charge_4 CHECK (tax_amount >= 0),
    CONSTRAINT ck_billing_charge_5 CHECK (gross_amount = base_amount - discount_amount + tax_amount),
    CONSTRAINT ck_billing_charge_6 CHECK (posting_status IN ('DRAFT','POSTED','VOID')),
    CONSTRAINT ck_billing_charge_7 CHECK (reversal_of_charge_id IS NULL OR reversal_of_charge_id <> id)
) ENGINE=InnoDB;

CREATE TABLE billing_invoice (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    invoice_number                     varchar(60) NOT NULL,
    customer_account_id                char(36) NOT NULL,
    billing_party_id                   char(36) NOT NULL,
    contract_id                        char(36),
    corporate_agreement_id             char(36),
    issue_date                         date NOT NULL,
    due_date                           date NOT NULL,
    currency_code                      char(3) NOT NULL,
    subtotal_amount                    decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    supersedes_invoice_id              char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_invoice PRIMARY KEY (id),
    CONSTRAINT uq_billing_invoice_legal_entity_id_invoice_number_1  UNIQUE (legal_entity_id, invoice_number),
    CONSTRAINT ck_billing_invoice_1 CHECK (due_date >= issue_date),
    CONSTRAINT ck_billing_invoice_2 CHECK (subtotal_amount >= 0),
    CONSTRAINT ck_billing_invoice_3 CHECK (discount_amount >= 0),
    CONSTRAINT ck_billing_invoice_4 CHECK (tax_amount >= 0),
    CONSTRAINT ck_billing_invoice_5 CHECK (total_amount >= 0),
    CONSTRAINT ck_billing_invoice_6 CHECK (status IN ('DRAFT','ISSUED','PARTIALLY_PAID','PAID','OVERDUE','CANCELLED','WRITTEN_OFF'))
) ENGINE=InnoDB;

CREATE TABLE billing_invoice_line (
    id                                 char(36) NOT NULL,
    invoice_id                         char(36) NOT NULL,
    line_number                        int NOT NULL,
    charge_id                          char(36) NOT NULL,
    description                        varchar(240) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    net_amount                         decimal(19,4) NOT NULL,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    gross_amount                       decimal(19,4) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_billing_invoice_line PRIMARY KEY (id),
    CONSTRAINT uq_billing_invoice_line_invoice_id_line_number_1  UNIQUE (invoice_id, line_number),
    CONSTRAINT uq_billing_invoice_line_invoice_id_charge_id_2  UNIQUE (invoice_id, charge_id),
    CONSTRAINT ck_billing_invoice_line_1 CHECK (quantity > 0),
    CONSTRAINT ck_billing_invoice_line_2 CHECK (tax_amount >= 0),
    CONSTRAINT ck_billing_invoice_line_3 CHECK (gross_amount = net_amount + tax_amount)
) ENGINE=InnoDB;

CREATE TABLE billing_receivable (
    id                                 char(36) NOT NULL,
    invoice_id                         char(36) NOT NULL,
    receivable_number                  varchar(60) NOT NULL,
    original_amount                    decimal(19,4) NOT NULL,
    open_amount                        decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    due_date                           date NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_receivable PRIMARY KEY (id),
    CONSTRAINT uq_billing_receivable_receivable_number_1 UNIQUE (receivable_number),
    CONSTRAINT uq_billing_receivable_invoice_id_2 UNIQUE (invoice_id),
    CONSTRAINT ck_billing_receivable_1 CHECK (original_amount >= 0),
    CONSTRAINT ck_billing_receivable_2 CHECK (open_amount >= 0),
    CONSTRAINT ck_billing_receivable_3 CHECK (open_amount <= original_amount),
    CONSTRAINT ck_billing_receivable_4 CHECK (status IN ('OPEN','PARTIALLY_PAID','PAID','OVERDUE','DISPUTED','WRITTEN_OFF','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE billing_payment_intent (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    contract_id                        char(36),
    reservation_id                     char(36),
    receivable_id                      char(36),
    payment_method_token_id            char(36),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    capture_method                     varchar(20) NOT NULL,
    status                             varchar(30) NOT NULL DEFAULT 'CREATED',
    provider                           varchar(60) NOT NULL,
    provider_reference                 varchar(160),
    idempotency_key                    varchar(160) NOT NULL,
    expires_at                         datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_payment_intent PRIMARY KEY (id),
    CONSTRAINT uq_billing_payment_intent_legal_entity_id_idempot_5465443a  UNIQUE (legal_entity_id, idempotency_key),
    CONSTRAINT ck_billing_payment_intent_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_payment_intent_2 CHECK (capture_method IN ('AUTOMATIC','MANUAL')),
    CONSTRAINT ck_billing_payment_intent_3 CHECK (status IN ('CREATED','REQUIRES_ACTION','PROCESSING','AUTHORIZED','CAPTURED','FAILED','CANCELLED','EXPIRED'))
) ENGINE=InnoDB;

CREATE TABLE billing_payment_transaction (
    id                                 char(36) NOT NULL,
    payment_intent_id                  char(36),
    transaction_type                   varchar(30) NOT NULL,
    provider                           varchar(60) NOT NULL,
    provider_transaction_id            varchar(180) NOT NULL,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    settled_at                         datetime(6),
    failure_code                       varchar(80),
    raw_response                       json,
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_billing_payment_transaction PRIMARY KEY (id),
    CONSTRAINT uq_billing_payment_transaction_provider_provider__5cf6ecc2  UNIQUE (provider, provider_transaction_id),
    CONSTRAINT uq_billing_payment_transaction_idempotency_key_2  UNIQUE (idempotency_key),
    CONSTRAINT ck_billing_payment_transaction_1 CHECK (amount >= 0),
    CONSTRAINT ck_billing_payment_transaction_2 CHECK (transaction_type IN ('AUTHORIZE','CAPTURE','SALE','VOID','REFUND','CHARGEBACK','REVERSAL')),
    CONSTRAINT ck_billing_payment_transaction_3 CHECK (status IN ('PENDING','SUCCEEDED','FAILED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE billing_payment_allocation (
    id                                 char(36) NOT NULL,
    payment_transaction_id             char(36) NOT NULL,
    receivable_id                      char(36) NOT NULL,
    allocated_amount                   decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    allocated_at                       datetime(6) NOT NULL,
    reversal_of_allocation_id          char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_billing_payment_allocation PRIMARY KEY (id),
    CONSTRAINT ck_billing_payment_allocation_1 CHECK (allocated_amount > 0),
    CONSTRAINT ck_billing_payment_allocation_2 CHECK (reversal_of_allocation_id IS NULL OR reversal_of_allocation_id <> id)
) ENGINE=InnoDB;

CREATE TABLE billing_preauthorization (
    id                                 char(36) NOT NULL,
    payment_method_token_id            char(36) NOT NULL,
    reservation_id                     char(36),
    contract_id                        char(36),
    provider                           varchar(60) NOT NULL,
    provider_reference                 varchar(160) NOT NULL,
    authorized_amount                  decimal(19,4) NOT NULL,
    captured_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    released_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    authorized_at                      datetime(6) NOT NULL,
    expires_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'AUTHORIZED',
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_preauthorization PRIMARY KEY (id),
    CONSTRAINT uq_billing_preauthorization_provider_provider_reference_1  UNIQUE (provider, provider_reference),
    CONSTRAINT uq_billing_preauthorization_idempotency_key_2  UNIQUE (idempotency_key),
    CONSTRAINT ck_billing_preauthorization_1 CHECK (authorized_amount >= 0),
    CONSTRAINT ck_billing_preauthorization_2 CHECK (captured_amount >= 0),
    CONSTRAINT ck_billing_preauthorization_3 CHECK (released_amount >= 0),
    CONSTRAINT ck_billing_preauthorization_4 CHECK (captured_amount + released_amount <= authorized_amount),
    CONSTRAINT ck_billing_preauthorization_5 CHECK (status IN ('PENDING','AUTHORIZED','PARTIALLY_CAPTURED','CAPTURED','RELEASED','EXPIRED','FAILED'))
) ENGINE=InnoDB;

CREATE TABLE billing_refund (
    id                                 char(36) NOT NULL,
    payment_transaction_id             char(36) NOT NULL,
    refund_transaction_id              char(36),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    reason_code                        varchar(60) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    requested_at                       datetime(6) NOT NULL,
    completed_at                       datetime(6),
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_refund PRIMARY KEY (id),
    CONSTRAINT uq_billing_refund_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_billing_refund_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_refund_2 CHECK (status IN ('REQUESTED','PROCESSING','SUCCEEDED','FAILED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE billing_credit_note (
    id                                 char(36) NOT NULL,
    invoice_id                         char(36) NOT NULL,
    credit_note_number                 varchar(60) NOT NULL,
    issue_date                         date NOT NULL,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    reason_code                        varchar(60) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ISSUED',
    tax_document_id                    char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_credit_note PRIMARY KEY (id),
    CONSTRAINT uq_billing_credit_note_credit_note_number_1  UNIQUE (credit_note_number),
    CONSTRAINT ck_billing_credit_note_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_credit_note_2 CHECK (status IN ('DRAFT','ISSUED','APPLIED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE billing_chargeback (
    id                                 char(36) NOT NULL,
    payment_transaction_id             char(36) NOT NULL,
    provider_case_reference            varchar(160) NOT NULL,
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    reason_code                        varchar(80),
    opened_at                          datetime(6) NOT NULL,
    response_due_at                    datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    outcome                            varchar(20),
    closed_at                          datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_chargeback PRIMARY KEY (id),
    CONSTRAINT uq_billing_chargeback_provider_case_reference_1  UNIQUE (provider_case_reference),
    CONSTRAINT ck_billing_chargeback_1 CHECK (amount > 0),
    CONSTRAINT ck_billing_chargeback_2 CHECK (status IN ('OPEN','EVIDENCE_SUBMITTED','WON','LOST','CLOSED')),
    CONSTRAINT ck_billing_chargeback_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
) ENGINE=InnoDB;

CREATE TABLE billing_tax_document (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    invoice_id                         char(36),
    document_type                      varchar(30) NOT NULL,
    document_number                    varchar(80) NOT NULL,
    series                             varchar(30),
    access_key                         varchar(100),
    issued_at                          datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL,
    object_key                         varchar(500),
    provider_response                  json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_tax_document PRIMARY KEY (id),
    CONSTRAINT uq_billing_tax_document_legal_entity_id_document__76b2374c  UNIQUE (legal_entity_id, document_type, document_number, series),
    CONSTRAINT ck_billing_tax_document_1 CHECK (status IN ('REQUESTED','AUTHORIZED','REJECTED','CANCELLED','VOID'))
) ENGINE=InnoDB;

CREATE TABLE billing_dunning_case (
    id                                 char(36) NOT NULL,
    customer_account_id                char(36) NOT NULL,
    receivable_id                      char(36) NOT NULL,
    opened_at                          datetime(6) NOT NULL,
    stage                              varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    assigned_to                        char(36),
    next_action_at                     datetime(6),
    closed_at                          datetime(6),
    resolution_code                    varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_dunning_case PRIMARY KEY (id),
    CONSTRAINT uq_billing_dunning_case_receivable_id_1 UNIQUE (receivable_id),
    CONSTRAINT ck_billing_dunning_case_1 CHECK (stage IN ('REMINDER','NOTICE','COLLECTION','LEGAL')),
    CONSTRAINT ck_billing_dunning_case_2 CHECK (status IN ('OPEN','PAUSED','PROMISE_TO_PAY','CLOSED')),
    CONSTRAINT ck_billing_dunning_case_3 CHECK (closed_at IS NULL OR closed_at >= opened_at)
) ENGINE=InnoDB;

CREATE TABLE billing_collection_action (
    id                                 char(36) NOT NULL,
    dunning_case_id                    char(36) NOT NULL,
    action_type                        varchar(40) NOT NULL,
    scheduled_at                       datetime(6),
    executed_at                        datetime(6),
    channel                            varchar(20),
    result_code                        varchar(60),
    notes                              text,
    performed_by                       char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_billing_collection_action PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE billing_settlement_batch (
    id                                 char(36) NOT NULL,
    provider                           varchar(60) NOT NULL,
    batch_reference                    varchar(160) NOT NULL,
    settlement_date                    date NOT NULL,
    gross_amount                       decimal(19,4) NOT NULL,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    net_amount                         decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_settlement_batch PRIMARY KEY (id),
    CONSTRAINT uq_billing_settlement_batch_provider_batch_reference_1  UNIQUE (provider, batch_reference),
    CONSTRAINT ck_billing_settlement_batch_1 CHECK (gross_amount >= 0),
    CONSTRAINT ck_billing_settlement_batch_2 CHECK (fee_amount >= 0),
    CONSTRAINT ck_billing_settlement_batch_3 CHECK (status IN ('RECEIVED','RECONCILED','PARTIALLY_RECONCILED','REJECTED'))
) ENGINE=InnoDB;

CREATE TABLE billing_settlement_item (
    id                                 char(36) NOT NULL,
    settlement_batch_id                char(36) NOT NULL,
    payment_transaction_id             char(36),
    provider_transaction_id            varchar(180) NOT NULL,
    gross_amount                       decimal(19,4) NOT NULL,
    fee_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    net_amount                         decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'MATCHED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_billing_settlement_item PRIMARY KEY (id),
    CONSTRAINT uq_billing_settlement_item_settlement_batch_id_pr_c0f4489e  UNIQUE (settlement_batch_id, provider_transaction_id),
    CONSTRAINT ck_billing_settlement_item_1 CHECK (gross_amount >= 0),
    CONSTRAINT ck_billing_settlement_item_2 CHECK (fee_amount >= 0),
    CONSTRAINT ck_billing_settlement_item_3 CHECK (status IN ('MATCHED','UNMATCHED','DUPLICATE','MISMATCH'))
) ENGINE=InnoDB;

CREATE TABLE billing_reconciliation_issue (
    id                                 char(36) NOT NULL,
    settlement_item_id                 char(36),
    issue_type                         varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    description                        text,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    opened_at                          datetime(6) NOT NULL,
    resolved_at                        datetime(6),
    resolution_note                    text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_reconciliation_issue PRIMARY KEY (id),
    CONSTRAINT ck_billing_reconciliation_issue_1 CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_billing_reconciliation_issue_2 CHECK (status IN ('OPEN','INVESTIGATING','RESOLVED','IGNORED')),
    CONSTRAINT ck_billing_reconciliation_issue_3 CHECK (resolved_at IS NULL OR resolved_at >= opened_at)
) ENGINE=InnoDB;

CREATE TABLE billing_accounting_export (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    period_start                       date NOT NULL,
    period_end                         date NOT NULL,
    export_type                        varchar(30) NOT NULL,
    object_key                         varchar(500),
    record_count                       int NOT NULL DEFAULT 0,
    total_debit                        decimal(19,4) NOT NULL DEFAULT 0,
    total_credit                       decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'GENERATED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_billing_accounting_export PRIMARY KEY (id),
    CONSTRAINT ck_billing_accounting_export_1 CHECK (period_end >= period_start),
    CONSTRAINT ck_billing_accounting_export_2 CHECK (record_count >= 0),
    CONSTRAINT ck_billing_accounting_export_3 CHECK (status IN ('GENERATED','SENT','ACCEPTED','REJECTED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_provider_import_batch (
    id                                 char(36) NOT NULL,
    provider                           varchar(60) NOT NULL,
    batch_reference                    varchar(160) NOT NULL,
    received_at                        datetime(6) NOT NULL,
    record_count                       int NOT NULL DEFAULT 0,
    processed_count                    int NOT NULL DEFAULT 0,
    error_count                        int NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    object_key                         varchar(500),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_provider_import_batch PRIMARY KEY (id),
    CONSTRAINT uq_traffic_provider_import_batch_provider_batch_r_20ebf910  UNIQUE (provider, batch_reference),
    CONSTRAINT ck_traffic_provider_import_batch_1 CHECK (record_count >= 0),
    CONSTRAINT ck_traffic_provider_import_batch_2 CHECK (processed_count >= 0),
    CONSTRAINT ck_traffic_provider_import_batch_3 CHECK (error_count >= 0),
    CONSTRAINT ck_traffic_provider_import_batch_4 CHECK (status IN ('RECEIVED','PROCESSING','COMPLETED','PARTIAL','FAILED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_traffic_notice (
    id                                 char(36) NOT NULL,
    import_batch_id                    char(36),
    vehicle_id                         char(36) NOT NULL,
    authority_code                     varchar(60) NOT NULL,
    external_notice_number             varchar(120) NOT NULL,
    infraction_code                    varchar(60),
    infraction_at                      datetime(6) NOT NULL,
    location_text                      varchar(240),
    base_amount                        decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    due_date                           date,
    status                             varchar(30) NOT NULL DEFAULT 'RECEIVED',
    raw_payload                        json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_traffic_notice PRIMARY KEY (id),
    CONSTRAINT uq_traffic_traffic_notice_authority_code_external_4c8a0b01  UNIQUE (authority_code, external_notice_number),
    CONSTRAINT ck_traffic_traffic_notice_1 CHECK (base_amount >= 0),
    CONSTRAINT ck_traffic_traffic_notice_2 CHECK (status IN ('RECEIVED','ATTRIBUTED','NOMINATION_PENDING','APPEALED','CONFIRMED','PAID','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_traffic_attribution (
    id                                 char(36) NOT NULL,
    traffic_notice_id                  char(36) NOT NULL,
    contract_id                        char(36),
    vehicle_assignment_id              char(36),
    driver_profile_id                  char(36),
    attribution_status                 varchar(30) NOT NULL,
    confidence                         decimal(8,6),
    attributed_at                      datetime(6),
    decided_by                         char(36),
    reason_text                        text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_traffic_attribution PRIMARY KEY (id),
    CONSTRAINT uq_traffic_traffic_attribution_traffic_notice_id_1  UNIQUE (traffic_notice_id),
    CONSTRAINT ck_traffic_traffic_attribution_1 CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    CONSTRAINT ck_traffic_traffic_attribution_2 CHECK (attribution_status IN ('PENDING','MATCHED','MANUAL_REVIEW','UNATTRIBUTED','COMPANY_RESPONSIBLE'))
) ENGINE=InnoDB;

CREATE TABLE traffic_driver_nomination (
    id                                 char(36) NOT NULL,
    traffic_notice_id                  char(36) NOT NULL,
    driver_profile_id                  char(36) NOT NULL,
    submitted_at                       datetime(6),
    submission_deadline                date,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    authority_reference                varchar(160),
    document_object_key                varchar(500),
    rejection_reason                   text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_driver_nomination PRIMARY KEY (id),
    CONSTRAINT ck_traffic_driver_nomination_1 CHECK (status IN ('PENDING','SUBMITTED','ACCEPTED','REJECTED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_traffic_appeal (
    id                                 char(36) NOT NULL,
    traffic_notice_id                  char(36) NOT NULL,
    appeal_level                       smallint NOT NULL DEFAULT 1,
    submitted_at                       datetime(6),
    deadline                           date,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    grounds                            text,
    document_object_key                varchar(500),
    decision_at                        datetime(6),
    decision_text                      text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_traffic_appeal PRIMARY KEY (id),
    CONSTRAINT ck_traffic_traffic_appeal_1 CHECK (appeal_level > 0),
    CONSTRAINT ck_traffic_traffic_appeal_2 CHECK (status IN ('DRAFT','SUBMITTED','UPHELD','DENIED','WITHDRAWN','EXPIRED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_toll_tag (
    id                                 char(36) NOT NULL,
    provider                           varchar(60) NOT NULL,
    tag_number                         varchar(100) NOT NULL,
    owning_legal_entity_id             char(36) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_toll_tag PRIMARY KEY (id),
    CONSTRAINT uq_traffic_toll_tag_provider_tag_number_1 UNIQUE (provider, tag_number),
    CONSTRAINT ck_traffic_toll_tag_1 CHECK (status IN ('ACTIVE','SUSPENDED','LOST','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_toll_tag_assignment (
    id                                 char(36) NOT NULL,
    toll_tag_id                        char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_traffic_toll_tag_assignment PRIMARY KEY (id),
    CONSTRAINT uq_traffic_toll_tag_assignment_toll_tag_id_start_at_1  UNIQUE (toll_tag_id, start_at),
    CONSTRAINT ck_traffic_toll_tag_assignment_1 CHECK (end_at IS NULL OR end_at > start_at)
) ENGINE=InnoDB;

CREATE TABLE traffic_toll_transaction (
    id                                 char(36) NOT NULL,
    import_batch_id                    char(36),
    provider                           varchar(60) NOT NULL,
    external_transaction_id            varchar(160) NOT NULL,
    toll_tag_id                        char(36),
    vehicle_id                         char(36) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    plaza_name                         varchar(160),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    contract_id                        char(36),
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_toll_transaction PRIMARY KEY (id),
    CONSTRAINT uq_traffic_toll_transaction_provider_external_tra_55281db6  UNIQUE (provider, external_transaction_id),
    CONSTRAINT ck_traffic_toll_transaction_1 CHECK (amount >= 0),
    CONSTRAINT ck_traffic_toll_transaction_2 CHECK (status IN ('RECEIVED','ATTRIBUTED','CHARGED','DISPUTED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_parking_transaction (
    id                                 char(36) NOT NULL,
    provider                           varchar(60) NOT NULL,
    external_transaction_id            varchar(160) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    entered_at                         datetime(6),
    exited_at                          datetime(6),
    location_name                      varchar(160),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    contract_id                        char(36),
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_traffic_parking_transaction PRIMARY KEY (id),
    CONSTRAINT uq_traffic_parking_transaction_provider_external__c2aaba9a  UNIQUE (provider, external_transaction_id),
    CONSTRAINT ck_traffic_parking_transaction_1 CHECK (amount >= 0),
    CONSTRAINT ck_traffic_parking_transaction_2 CHECK (exited_at IS NULL OR entered_at IS NULL OR exited_at >= entered_at),
    CONSTRAINT ck_traffic_parking_transaction_3 CHECK (status IN ('RECEIVED','ATTRIBUTED','CHARGED','DISPUTED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE traffic_traffic_charge_link (
    id                                 char(36) NOT NULL,
    source_type                        varchar(20) NOT NULL,
    traffic_notice_id                  char(36),
    toll_transaction_id                char(36),
    parking_transaction_id             char(36),
    charge_id                          char(36) NOT NULL,
    linked_at                          datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_traffic_traffic_charge_link PRIMARY KEY (id),
    CONSTRAINT ck_traffic_traffic_charge_link_1 CHECK (source_type IN ('TRAFFIC_NOTICE','TOLL','PARKING')),
    CONSTRAINT ck_traffic_traffic_charge_link_2 CHECK ((source_type = 'TRAFFIC_NOTICE' AND traffic_notice_id IS NOT NULL AND toll_transaction_id IS NULL AND parking_transaction_id IS NULL) OR (source_type = 'TOLL' AND toll_transaction_id IS NOT NULL AND traffic_notice_id IS NULL AND parking_transaction_id IS NULL) OR (source_type = 'PARKING' AND parking_transaction_id IS NOT NULL AND traffic_notice_id IS NULL AND toll_transaction_id IS NULL))
) ENGINE=InnoDB;

CREATE TABLE claim_insurance_policy (
    id                                 char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    insurer_party_id                   char(36) NOT NULL,
    policy_number                      varchar(100) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6) NOT NULL,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    policy_document_key                varchar(500),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_insurance_policy PRIMARY KEY (id),
    CONSTRAINT uq_claim_insurance_policy_legal_entity_id_policy_number_1  UNIQUE (legal_entity_id, policy_number),
    CONSTRAINT ck_claim_insurance_policy_1 CHECK (valid_to > valid_from),
    CONSTRAINT ck_claim_insurance_policy_2 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE claim_policy_coverage (
    insurance_policy_id                char(36) NOT NULL,
    coverage_id                        char(36) NOT NULL,
    deductible_amount                  decimal(19,4),
    coverage_limit_amount              decimal(19,4),
    currency_code                      char(3) NOT NULL,
    terms_json                         json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_claim_policy_coverage PRIMARY KEY (insurance_policy_id, coverage_id),
    CONSTRAINT ck_claim_policy_coverage_1 CHECK (deductible_amount IS NULL OR deductible_amount >= 0),
    CONSTRAINT ck_claim_policy_coverage_2 CHECK (coverage_limit_amount IS NULL OR coverage_limit_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE claim_incident (
    id                                 char(36) NOT NULL,
    incident_number                    varchar(60) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    contract_id                        char(36),
    incident_type                      varchar(30) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    reported_at                        datetime(6) NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    location_text                      varchar(240),
    description                        text,
    police_report_number               varchar(100),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_incident PRIMARY KEY (id),
    CONSTRAINT uq_claim_incident_legal_entity_id_incident_number_1  UNIQUE (legal_entity_id, incident_number),
    CONSTRAINT ck_claim_incident_1 CHECK (reported_at >= occurred_at),
    CONSTRAINT ck_claim_incident_2 CHECK (incident_type IN ('ACCIDENT','THEFT','ROBBERY','VANDALISM','FIRE','FLOOD','MECHANICAL_FAILURE','OTHER')),
    CONSTRAINT ck_claim_incident_3 CHECK (status IN ('OPEN','UNDER_REVIEW','RESOLVED','CLOSED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE claim_incident_party (
    id                                 char(36) NOT NULL,
    incident_id                        char(36) NOT NULL,
    party_id                           char(36),
    role_type                          varchar(30) NOT NULL,
    name_snapshot                      varchar(180),
    contact_snapshot                   json,
    injury_severity                    varchar(20),
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_claim_incident_party PRIMARY KEY (id),
    CONSTRAINT ck_claim_incident_party_1 CHECK (role_type IN ('DRIVER','PASSENGER','THIRD_PARTY_DRIVER','THIRD_PARTY_OWNER','WITNESS','AUTHORITY','OTHER'))
) ENGINE=InnoDB;

CREATE TABLE claim_incident_vehicle (
    id                                 char(36) NOT NULL,
    incident_id                        char(36) NOT NULL,
    vehicle_id                         char(36),
    role_type                          varchar(30) NOT NULL,
    registration_snapshot              varchar(40),
    make_model_snapshot                varchar(180),
    drivable_after                     boolean,
    tow_required                       boolean,
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_claim_incident_vehicle PRIMARY KEY (id),
    CONSTRAINT ck_claim_incident_vehicle_1 CHECK (role_type IN ('RENTAL_VEHICLE','THIRD_PARTY_VEHICLE','OTHER'))
) ENGINE=InnoDB;

CREATE TABLE claim_incident_document (
    id                                 char(36) NOT NULL,
    incident_id                        char(36) NOT NULL,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             binary(32),
    captured_at                        datetime(6) NOT NULL,
    description                        varchar(240),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_claim_incident_document PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE claim_claim (
    id                                 char(36) NOT NULL,
    claim_number                       varchar(60) NOT NULL,
    incident_id                        char(36) NOT NULL,
    insurance_policy_id                char(36),
    contract_id                        char(36),
    claim_type                         varchar(30) NOT NULL,
    opened_at                          datetime(6) NOT NULL,
    reported_to_insurer_at             datetime(6),
    status                             varchar(30) NOT NULL DEFAULT 'OPEN',
    estimated_amount                   decimal(19,4),
    approved_amount                    decimal(19,4),
    currency_code                      char(3),
    insurer_reference                  varchar(160),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_claim PRIMARY KEY (id),
    CONSTRAINT uq_claim_claim_claim_number_1 UNIQUE (claim_number),
    CONSTRAINT ck_claim_claim_1 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_claim_claim_2 CHECK (approved_amount IS NULL OR approved_amount >= 0),
    CONSTRAINT ck_claim_claim_3 CHECK (claim_type IN ('OWN_DAMAGE','THIRD_PARTY','THEFT','TOTAL_LOSS','ASSISTANCE','OTHER')),
    CONSTRAINT ck_claim_claim_4 CHECK (status IN ('OPEN','SUBMITTED','UNDER_REVIEW','APPROVED','PARTIALLY_APPROVED','DENIED','PAID','CLOSED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE claim_claim_coverage_decision (
    id                                 char(36) NOT NULL,
    claim_id                           char(36) NOT NULL,
    coverage_id                        char(36) NOT NULL,
    decision                           varchar(30) NOT NULL,
    decided_at                         datetime(6),
    covered_amount                     decimal(19,4),
    deductible_amount                  decimal(19,4),
    currency_code                      char(3),
    reason_text                        text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_claim_coverage_decision PRIMARY KEY (id),
    CONSTRAINT uq_claim_claim_coverage_decision_claim_id_coverage_id_1  UNIQUE (claim_id, coverage_id),
    CONSTRAINT ck_claim_claim_coverage_decision_1 CHECK (covered_amount IS NULL OR covered_amount >= 0),
    CONSTRAINT ck_claim_claim_coverage_decision_2 CHECK (deductible_amount IS NULL OR deductible_amount >= 0),
    CONSTRAINT ck_claim_claim_coverage_decision_3 CHECK (decision IN ('PENDING','COVERED','PARTIALLY_COVERED','NOT_COVERED','EXCLUDED','WAIVED'))
) ENGINE=InnoDB;

CREATE TABLE claim_claim_cost (
    id                                 char(36) NOT NULL,
    claim_id                           char(36) NOT NULL,
    cost_type                          varchar(40) NOT NULL,
    supplier_party_id                  char(36),
    description                        varchar(240),
    amount                             decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    incurred_at                        date NOT NULL,
    invoice_reference                  varchar(100),
    recoverable                        boolean NOT NULL DEFAULT FALSE,
    status                             varchar(20) NOT NULL DEFAULT 'RECORDED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_claim_cost PRIMARY KEY (id),
    CONSTRAINT ck_claim_claim_cost_1 CHECK (amount >= 0),
    CONSTRAINT ck_claim_claim_cost_2 CHECK (status IN ('RECORDED','APPROVED','PAID','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE claim_third_party_claim (
    id                                 char(36) NOT NULL,
    claim_id                           char(36) NOT NULL,
    third_party_id                     char(36),
    claimant_name_snapshot             varchar(180),
    claimed_amount                     decimal(19,4),
    approved_amount                    decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    settlement_date                    date,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_third_party_claim PRIMARY KEY (id),
    CONSTRAINT ck_claim_third_party_claim_1 CHECK (claimed_amount IS NULL OR claimed_amount >= 0),
    CONSTRAINT ck_claim_third_party_claim_2 CHECK (approved_amount IS NULL OR approved_amount >= 0),
    CONSTRAINT ck_claim_third_party_claim_3 CHECK (status IN ('RECEIVED','UNDER_REVIEW','NEGOTIATION','SETTLED','DENIED','LITIGATION','CLOSED'))
) ENGINE=InnoDB;

CREATE TABLE claim_recovery_case (
    id                                 char(36) NOT NULL,
    claim_id                           char(36) NOT NULL,
    responsible_party_id               char(36),
    opened_at                          datetime(6) NOT NULL,
    target_amount                      decimal(19,4) NOT NULL,
    recovered_amount                   decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    closed_at                          datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_recovery_case PRIMARY KEY (id),
    CONSTRAINT ck_claim_recovery_case_1 CHECK (target_amount >= 0),
    CONSTRAINT ck_claim_recovery_case_2 CHECK (recovered_amount >= 0),
    CONSTRAINT ck_claim_recovery_case_3 CHECK (recovered_amount <= target_amount),
    CONSTRAINT ck_claim_recovery_case_4 CHECK (status IN ('OPEN','NEGOTIATION','COLLECTION','LITIGATION','RECOVERED','CLOSED','WRITTEN_OFF'))
) ENGINE=InnoDB;

CREATE TABLE claim_roadside_assistance_case (
    id                                 char(36) NOT NULL,
    case_number                        varchar(60) NOT NULL,
    incident_id                        char(36),
    contract_id                        char(36),
    vehicle_id                         char(36) NOT NULL,
    assistance_type                    varchar(40) NOT NULL,
    requested_at                       datetime(6) NOT NULL,
    dispatched_at                      datetime(6),
    completed_at                       datetime(6),
    provider_party_id                  char(36),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    cost_amount                        decimal(19,4),
    currency_code                      char(3),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_claim_roadside_assistance_case PRIMARY KEY (id),
    CONSTRAINT uq_claim_roadside_assistance_case_case_number_1  UNIQUE (case_number),
    CONSTRAINT ck_claim_roadside_assistance_case_1 CHECK (completed_at IS NULL OR completed_at >= requested_at),
    CONSTRAINT ck_claim_roadside_assistance_case_2 CHECK (cost_amount IS NULL OR cost_amount >= 0),
    CONSTRAINT ck_claim_roadside_assistance_case_3 CHECK (status IN ('REQUESTED','DISPATCHED','ARRIVED','COMPLETED','CANCELLED','FAILED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_maintenance_plan (
    id                                 char(36) NOT NULL,
    plan_code                          varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    vehicle_variant_id                 char(36),
    manufacturer                       boolean NOT NULL DEFAULT FALSE,
    valid_from                         date NOT NULL,
    valid_to                           date,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_maintenance_plan PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_maintenance_plan_plan_code_valid_from_1  UNIQUE (plan_code, valid_from),
    CONSTRAINT ck_maintenance_maintenance_plan_1 CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_maintenance_maintenance_plan_2 CHECK (status IN ('ACTIVE','INACTIVE','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_maintenance_rule (
    id                                 char(36) NOT NULL,
    maintenance_plan_id                char(36) NOT NULL,
    rule_code                          varchar(50) NOT NULL,
    service_type                       varchar(40) NOT NULL,
    every_km                           decimal(12,1),
    every_days                         int,
    whichever_first                    boolean NOT NULL DEFAULT TRUE,
    condition_json                     json,
    priority                           smallint NOT NULL DEFAULT 100,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_maintenance_maintenance_rule PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_maintenance_rule_maintenance_plan__6159e176  UNIQUE (maintenance_plan_id, rule_code),
    CONSTRAINT ck_maintenance_maintenance_rule_1 CHECK (every_km IS NULL OR every_km > 0),
    CONSTRAINT ck_maintenance_maintenance_rule_2 CHECK (every_days IS NULL OR every_days > 0),
    CONSTRAINT ck_maintenance_maintenance_rule_3 CHECK (every_km IS NOT NULL OR every_days IS NOT NULL OR condition_json IS NOT NULL),
    CONSTRAINT ck_maintenance_maintenance_rule_4 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_maintenance_due (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    maintenance_rule_id                char(36) NOT NULL,
    due_odometer_km                    decimal(12,1),
    due_date                           date,
    calculated_at                      datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DUE',
    service_order_id                   char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_maintenance_due PRIMARY KEY (id),
    CONSTRAINT ck_maintenance_maintenance_due_1 CHECK (due_odometer_km IS NULL OR due_odometer_km >= 0),
    CONSTRAINT ck_maintenance_maintenance_due_2 CHECK (status IN ('UPCOMING','DUE','OVERDUE','SCHEDULED','COMPLETED','WAIVED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_vendor (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    vendor_code                        varchar(40) NOT NULL,
    vendor_type                        varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_vendor PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_vendor_vendor_code_1 UNIQUE (vendor_code),
    CONSTRAINT uq_maintenance_vendor_party_id_2 UNIQUE (party_id),
    CONSTRAINT ck_maintenance_vendor_1 CHECK (vendor_type IN ('WORKSHOP','PARTS','TOWING','CLEANING','INSPECTION','OTHER')),
    CONSTRAINT ck_maintenance_vendor_2 CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_workshop (
    id                                 char(36) NOT NULL,
    vendor_id                          char(36) NOT NULL,
    branch_id                          char(36),
    name                               varchar(160) NOT NULL,
    address_id                         char(36),
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_workshop PRIMARY KEY (id),
    CONSTRAINT ck_maintenance_workshop_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_service_order (
    id                                 char(36) NOT NULL,
    service_order_number               varchar(60) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    workshop_id                        char(36),
    calendar_entry_id                  char(36),
    order_type                         varchar(30) NOT NULL,
    opened_at                          datetime(6) NOT NULL,
    scheduled_start_at                 datetime(6),
    started_at                         datetime(6),
    completed_at                       datetime(6),
    odometer_open_km                   decimal(12,1),
    odometer_close_km                  decimal(12,1),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    estimated_amount                   decimal(19,4),
    actual_amount                      decimal(19,4),
    currency_code                      char(3),
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_service_order PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_service_order_service_order_number_1  UNIQUE (service_order_number),
    CONSTRAINT ck_maintenance_service_order_1 CHECK (completed_at IS NULL OR completed_at >= opened_at),
    CONSTRAINT ck_maintenance_service_order_2 CHECK (odometer_open_km IS NULL OR odometer_open_km >= 0),
    CONSTRAINT ck_maintenance_service_order_3 CHECK (odometer_close_km IS NULL OR odometer_close_km >= 0),
    CONSTRAINT ck_maintenance_service_order_4 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_maintenance_service_order_5 CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT ck_maintenance_service_order_6 CHECK (order_type IN ('PREVENTIVE','CORRECTIVE','RECALL','TIRE','BODYWORK','CLEANING','INSPECTION')),
    CONSTRAINT ck_maintenance_service_order_7 CHECK (status IN ('OPEN','SCHEDULED','IN_PROGRESS','AWAITING_PARTS','QUALITY_CHECK','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_service_order_item (
    id                                 char(36) NOT NULL,
    service_order_id                   char(36) NOT NULL,
    line_number                        int NOT NULL,
    service_type                       varchar(60) NOT NULL,
    description                        varchar(240),
    quantity                           decimal(19,6) NOT NULL DEFAULT 1,
    unit_amount                        decimal(19,4) NOT NULL DEFAULT 0,
    labor_hours                        decimal(10,2),
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_service_order_item PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_service_order_item_service_order_i_6de424be  UNIQUE (service_order_id, line_number),
    CONSTRAINT ck_maintenance_service_order_item_1 CHECK (quantity > 0),
    CONSTRAINT ck_maintenance_service_order_item_2 CHECK (unit_amount >= 0),
    CONSTRAINT ck_maintenance_service_order_item_3 CHECK (labor_hours IS NULL OR labor_hours >= 0),
    CONSTRAINT ck_maintenance_service_order_item_4 CHECK (status IN ('PLANNED','APPROVED','IN_PROGRESS','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_part (
    id                                 char(36) NOT NULL,
    part_code                          varchar(60) NOT NULL,
    manufacturer_code                  varchar(80),
    name                               varchar(160) NOT NULL,
    unit_code                          varchar(20) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_maintenance_part PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_part_part_code_1 UNIQUE (part_code),
    CONSTRAINT ck_maintenance_part_1 CHECK (status IN ('ACTIVE','INACTIVE','DISCONTINUED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_service_order_part (
    id                                 char(36) NOT NULL,
    service_order_item_id              char(36) NOT NULL,
    part_id                            char(36) NOT NULL,
    quantity                           decimal(19,6) NOT NULL,
    unit_amount                        decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    serial_number                      varchar(100),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_maintenance_service_order_part PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_service_order_part_service_order_i_13b18f26  UNIQUE (service_order_item_id, part_id, serial_number),
    CONSTRAINT ck_maintenance_service_order_part_1 CHECK (quantity > 0),
    CONSTRAINT ck_maintenance_service_order_part_2 CHECK (unit_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE maintenance_recall_campaign (
    id                                 char(36) NOT NULL,
    manufacturer_code                  varchar(60) NOT NULL,
    campaign_code                      varchar(80) NOT NULL,
    name                               varchar(180) NOT NULL,
    announced_at                       date,
    severity                           varchar(20) NOT NULL,
    instructions                       text,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_recall_campaign PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_recall_campaign_manufacturer_code__cb32fd47  UNIQUE (manufacturer_code, campaign_code),
    CONSTRAINT ck_maintenance_recall_campaign_1 CHECK (severity IN ('ADVISORY','IMPORTANT','SAFETY_CRITICAL')),
    CONSTRAINT ck_maintenance_recall_campaign_2 CHECK (status IN ('ACTIVE','CLOSED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_vehicle_recall (
    id                                 char(36) NOT NULL,
    recall_campaign_id                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    identified_at                      datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    service_order_id                   char(36),
    completed_at                       datetime(6),
    completion_reference               varchar(120),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_vehicle_recall PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_vehicle_recall_recall_campaign_id__202e0ec3  UNIQUE (recall_campaign_id, vehicle_id),
    CONSTRAINT ck_maintenance_vehicle_recall_1 CHECK (status IN ('OPEN','SCHEDULED','COMPLETED','NOT_APPLICABLE','DECLINED'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_tire (
    id                                 char(36) NOT NULL,
    serial_number                      varchar(100) NOT NULL,
    brand                              varchar(80),
    model                              varchar(100),
    size_code                          varchar(40),
    purchased_at                       date,
    purchase_amount                    decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'IN_STOCK',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_tire PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_tire_serial_number_1 UNIQUE (serial_number),
    CONSTRAINT ck_maintenance_tire_1 CHECK (purchase_amount IS NULL OR purchase_amount >= 0),
    CONSTRAINT ck_maintenance_tire_2 CHECK (status IN ('IN_STOCK','INSTALLED','REPAIR','DISCARDED','LOST'))
) ENGINE=InnoDB;

CREATE TABLE maintenance_tire_assignment (
    id                                 char(36) NOT NULL,
    tire_id                            char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    position_code                      varchar(30) NOT NULL,
    installed_at                       datetime(6) NOT NULL,
    removed_at                         datetime(6),
    installed_odometer_km              decimal(12,1),
    removed_odometer_km                decimal(12,1),
    removal_reason                     varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_maintenance_tire_assignment PRIMARY KEY (id),
    CONSTRAINT uq_maintenance_tire_assignment_tire_id_installed_at_1  UNIQUE (tire_id, installed_at),
    CONSTRAINT ck_maintenance_tire_assignment_1 CHECK (removed_at IS NULL OR removed_at > installed_at),
    CONSTRAINT ck_maintenance_tire_assignment_2 CHECK (installed_odometer_km IS NULL OR installed_odometer_km >= 0),
    CONSTRAINT ck_maintenance_tire_assignment_3 CHECK (removed_odometer_km IS NULL OR removed_odometer_km >= 0)
) ENGINE=InnoDB;

CREATE TABLE maintenance_downtime (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    service_order_id                   char(36),
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    downtime_type                      varchar(30) NOT NULL,
    reason_code                        varchar(60),
    calendar_entry_id                  char(36),
    estimated_cost_amount              decimal(19,4),
    currency_code                      char(3),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_maintenance_downtime PRIMARY KEY (id),
    CONSTRAINT ck_maintenance_downtime_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_maintenance_downtime_2 CHECK (estimated_cost_amount IS NULL OR estimated_cost_amount >= 0),
    CONSTRAINT ck_maintenance_downtime_3 CHECK (downtime_type IN ('MAINTENANCE','RECALL','DAMAGE','DOCUMENTATION','CLEANING','OTHER'))
) ENGINE=InnoDB;

CREATE TABLE telematics_provider (
    id                                 char(36) NOT NULL,
    provider_code                      varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    configuration_json                 json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_provider PRIMARY KEY (id),
    CONSTRAINT uq_telematics_provider_provider_code_1 UNIQUE (provider_code),
    CONSTRAINT ck_telematics_provider_1 CHECK (status IN ('ACTIVE','SUSPENDED','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE telematics_device (
    id                                 char(36) NOT NULL,
    provider_id                        char(36) NOT NULL,
    device_serial                      varchar(120) NOT NULL,
    device_type                        varchar(30) NOT NULL,
    firmware_version                   varchar(60),
    activated_at                       datetime(6),
    last_seen_at                       datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_device PRIMARY KEY (id),
    CONSTRAINT uq_telematics_device_provider_id_device_serial_1  UNIQUE (provider_id, device_serial),
    CONSTRAINT ck_telematics_device_1 CHECK (device_type IN ('OEM','OBD','TRACKER','SMART_KEY','OTHER')),
    CONSTRAINT ck_telematics_device_2 CHECK (status IN ('ACTIVE','OFFLINE','SUSPENDED','RETIRED','LOST'))
) ENGINE=InnoDB;

CREATE TABLE telematics_vehicle_device_assignment (
    id                                 char(36) NOT NULL,
    device_id                          char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    assignment_type                    varchar(30) NOT NULL,
    installed_by                       char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_vehicle_device_assignment PRIMARY KEY (id),
    CONSTRAINT uq_telematics_vehicle_device_assignment_device_id_f95fcb22  UNIQUE (device_id, start_at),
    CONSTRAINT ck_telematics_vehicle_device_assignment_1 CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_telematics_vehicle_device_assignment_2 CHECK (assignment_type IN ('PRIMARY_TELEMATICS','DIGITAL_KEY','AUXILIARY'))
) ENGINE=InnoDB;

CREATE TABLE telematics_device_health_event (
    id                                 char(36) NOT NULL,
    device_id                          char(36) NOT NULL,
    event_type                         varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    details_json                       json,
    resolved_at                        datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_device_health_event PRIMARY KEY (id),
    CONSTRAINT ck_telematics_device_health_event_1 CHECK (severity IN ('INFO','WARNING','ERROR','CRITICAL')),
    CONSTRAINT ck_telematics_device_health_event_2 CHECK (resolved_at IS NULL OR resolved_at >= occurred_at)
) ENGINE=InnoDB;

CREATE TABLE telematics_telemetry_event_index (
    id                                 char(36) NOT NULL,
    device_id                          char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    provider_event_id                  varchar(180),
    sequence_number                    bigint,
    event_type                         varchar(40) NOT NULL,
    event_time                         datetime(6) NOT NULL,
    received_at                        datetime(6) NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    odometer_km                        decimal(12,1),
    fuel_level_percent                 decimal(5,2),
    speed_kph                          decimal(8,2),
    object_key                         varchar(500),
    payload_version                    int NOT NULL DEFAULT 1,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_telemetry_event_index PRIMARY KEY (id),
    CONSTRAINT uq_telematics_telemetry_event_index_device_id_pro_51faf317  UNIQUE (device_id, provider_event_id),
    CONSTRAINT uq_telematics_telemetry_event_index_device_id_seq_585ee7dd  UNIQUE (device_id, sequence_number),
    CONSTRAINT ck_telematics_telemetry_event_index_1 CHECK (sequence_number IS NULL OR sequence_number >= 0),
    CONSTRAINT ck_telematics_telemetry_event_index_2 CHECK (odometer_km IS NULL OR odometer_km >= 0),
    CONSTRAINT ck_telematics_telemetry_event_index_3 CHECK (fuel_level_percent IS NULL OR fuel_level_percent BETWEEN 0 AND 100),
    CONSTRAINT ck_telematics_telemetry_event_index_4 CHECK (speed_kph IS NULL OR speed_kph >= 0)
) ENGINE=InnoDB;

CREATE TABLE telematics_trip_summary (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    device_id                          char(36),
    contract_id                        char(36),
    trip_start_at                      datetime(6) NOT NULL,
    trip_end_at                        datetime(6) NOT NULL,
    start_latitude                     decimal(10,7),
    start_longitude                    decimal(10,7),
    end_latitude                       decimal(10,7),
    end_longitude                      decimal(10,7),
    distance_km                        decimal(12,3) NOT NULL,
    duration_seconds                   int NOT NULL,
    maximum_speed_kph                  decimal(8,2),
    harsh_event_count                  int NOT NULL DEFAULT 0,
    calculation_version                varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_trip_summary PRIMARY KEY (id),
    CONSTRAINT ck_telematics_trip_summary_1 CHECK (trip_end_at > trip_start_at),
    CONSTRAINT ck_telematics_trip_summary_2 CHECK (distance_km >= 0),
    CONSTRAINT ck_telematics_trip_summary_3 CHECK (duration_seconds >= 0),
    CONSTRAINT ck_telematics_trip_summary_4 CHECK (maximum_speed_kph IS NULL OR maximum_speed_kph >= 0),
    CONSTRAINT ck_telematics_trip_summary_5 CHECK (harsh_event_count >= 0)
) ENGINE=InnoDB;

CREATE TABLE telematics_driving_event (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    device_id                          char(36),
    contract_id                        char(36),
    trip_summary_id                    char(36),
    event_type                         varchar(40) NOT NULL,
    severity                           varchar(20) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    measured_value                     decimal(19,6),
    threshold_value                    decimal(19,6),
    rule_version                       varchar(60),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_driving_event PRIMARY KEY (id),
    CONSTRAINT ck_telematics_driving_event_1 CHECK (event_type IN ('HARSH_BRAKE','HARSH_ACCELERATION','HARSH_CORNER','SPEEDING','IMPACT','TOWING','GEOFENCE','IDLE','OTHER')),
    CONSTRAINT ck_telematics_driving_event_2 CHECK (severity IN ('INFO','LOW','MEDIUM','HIGH','CRITICAL'))
) ENGINE=InnoDB;

CREATE TABLE telematics_geofence (
    id                                 char(36) NOT NULL,
    geofence_code                      varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    geofence_type                      varchar(30) NOT NULL,
    geometry_json                      json NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_geofence PRIMARY KEY (id),
    CONSTRAINT uq_telematics_geofence_geofence_code_1 UNIQUE (geofence_code),
    CONSTRAINT ck_telematics_geofence_1 CHECK (geofence_type IN ('BRANCH','COUNTRY','RESTRICTED_AREA','SERVICE_AREA','CUSTOM')),
    CONSTRAINT ck_telematics_geofence_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE telematics_geofence_event (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    device_id                          char(36),
    geofence_id                        char(36) NOT NULL,
    contract_id                        char(36),
    event_type                         varchar(20) NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    latitude                           decimal(10,7),
    longitude                          decimal(10,7),
    provider_event_id                  varchar(180),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_geofence_event PRIMARY KEY (id),
    CONSTRAINT uq_telematics_geofence_event_device_id_provider_event_id_1  UNIQUE (device_id, provider_event_id),
    CONSTRAINT ck_telematics_geofence_event_1 CHECK (event_type IN ('ENTER','EXIT','DWELL'))
) ENGINE=InnoDB;

CREATE TABLE telematics_vehicle_command (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    device_id                          char(36),
    contract_id                        char(36),
    command_type                       varchar(30) NOT NULL,
    requested_by                       char(36),
    reason_code                        varchar(60),
    requested_at                       datetime(6) NOT NULL,
    expires_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_vehicle_command PRIMARY KEY (id),
    CONSTRAINT uq_telematics_vehicle_command_idempotency_key_1  UNIQUE (idempotency_key),
    CONSTRAINT ck_telematics_vehicle_command_1 CHECK (command_type IN ('LOCK','UNLOCK','IMMOBILIZE','MOBILIZE','HORN','LIGHTS','LOCATE')),
    CONSTRAINT ck_telematics_vehicle_command_2 CHECK (status IN ('REQUESTED','SENT','ACKNOWLEDGED','SUCCEEDED','FAILED','EXPIRED','CANCELLED')),
    CONSTRAINT ck_telematics_vehicle_command_3 CHECK (expires_at IS NULL OR expires_at > requested_at)
) ENGINE=InnoDB;

CREATE TABLE telematics_command_result (
    id                                 char(36) NOT NULL,
    vehicle_command_id                 char(36) NOT NULL,
    provider_reference                 varchar(160),
    acknowledged_at                    datetime(6),
    executed_at                        datetime(6),
    result_code                        varchar(60) NOT NULL,
    result_message                     text,
    raw_response                       json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_telematics_command_result PRIMARY KEY (id),
    CONSTRAINT uq_telematics_command_result_vehicle_command_id_1  UNIQUE (vehicle_command_id)
) ENGINE=InnoDB;

CREATE TABLE telematics_telemetry_rule_version (
    id                                 char(36) NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    rule_type                          varchar(40) NOT NULL,
    rule_json                          json NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_telematics_telemetry_rule_version PRIMARY KEY (id),
    CONSTRAINT uq_telematics_telemetry_rule_version_rule_code_ve_dfbc988d  UNIQUE (rule_code, version_number),
    CONSTRAINT ck_telematics_telemetry_rule_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_telematics_telemetry_rule_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_loyalty_account (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    account_number                     varchar(60) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    enrolled_at                        datetime(6) NOT NULL,
    current_tier_id                    char(36),
    balance_projection                 decimal(19,4) NOT NULL DEFAULT 0,
    balance_updated_at                 datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_loyalty_account PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_loyalty_account_party_id_1 UNIQUE (party_id),
    CONSTRAINT uq_loyalty_loyalty_account_account_number_2  UNIQUE (account_number),
    CONSTRAINT ck_loyalty_loyalty_account_1 CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_loyalty_tier (
    id                                 char(36) NOT NULL,
    tier_code                          varchar(30) NOT NULL,
    name                               varchar(100) NOT NULL,
    rank_order                         smallint NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    benefit_summary                    json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_loyalty_loyalty_tier PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_loyalty_tier_tier_code_1 UNIQUE (tier_code),
    CONSTRAINT uq_loyalty_loyalty_tier_rank_order_2 UNIQUE (rank_order),
    CONSTRAINT ck_loyalty_loyalty_tier_1 CHECK (rank_order > 0),
    CONSTRAINT ck_loyalty_loyalty_tier_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_tier_rule_version (
    id                                 char(36) NOT NULL,
    loyalty_tier_id                    char(36) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    qualification_rule_json            json NOT NULL,
    retention_rule_json                json,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_tier_rule_version PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_tier_rule_version_loyalty_tier_id_vers_e0d1732a  UNIQUE (loyalty_tier_id, version_number),
    CONSTRAINT ck_loyalty_tier_rule_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_loyalty_tier_rule_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_tier_history (
    id                                 char(36) NOT NULL,
    loyalty_account_id                 char(36) NOT NULL,
    loyalty_tier_id                    char(36) NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    reason_code                        varchar(60),
    rule_version_id                    char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_loyalty_tier_history PRIMARY KEY (id),
    CONSTRAINT ck_loyalty_tier_history_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE loyalty_earning_rule (
    id                                 char(36) NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    condition_json                     json NOT NULL,
    calculation_json                   json NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_earning_rule PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_earning_rule_rule_code_version_number_1  UNIQUE (rule_code, version_number),
    CONSTRAINT ck_loyalty_earning_rule_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_loyalty_earning_rule_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_redemption_rule (
    id                                 char(36) NOT NULL,
    rule_code                          varchar(60) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    condition_json                     json NOT NULL,
    conversion_json                    json NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_redemption_rule PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_redemption_rule_rule_code_version_number_1  UNIQUE (rule_code, version_number),
    CONSTRAINT ck_loyalty_redemption_rule_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_loyalty_redemption_rule_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_points_ledger (
    id                                 char(36) NOT NULL,
    loyalty_account_id                 char(36) NOT NULL,
    entry_type                         varchar(30) NOT NULL,
    points                             decimal(19,4) NOT NULL,
    source_type                        varchar(40) NOT NULL,
    source_id                          char(36) NOT NULL,
    source_correlation_id              varchar(160) NOT NULL,
    earning_rule_id                    char(36),
    redemption_rule_id                 char(36),
    available_at                       datetime(6) NOT NULL,
    expires_at                         datetime(6),
    reversal_of_entry_id               char(36),
    occurred_at                        datetime(6) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_loyalty_points_ledger PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_points_ledger_loyalty_account_id_sourc_1c8160a0  UNIQUE (loyalty_account_id, source_correlation_id),
    CONSTRAINT ck_loyalty_points_ledger_1 CHECK (points <> 0),
    CONSTRAINT ck_loyalty_points_ledger_2 CHECK (expires_at IS NULL OR expires_at > available_at),
    CONSTRAINT ck_loyalty_points_ledger_3 CHECK (reversal_of_entry_id IS NULL OR reversal_of_entry_id <> id),
    CONSTRAINT ck_loyalty_points_ledger_4 CHECK (entry_type IN ('EARN','REDEEM','EXPIRE','ADJUSTMENT','REVERSAL','TRANSFER_IN','TRANSFER_OUT'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_points_lot (
    id                                 char(36) NOT NULL,
    loyalty_account_id                 char(36) NOT NULL,
    origin_ledger_entry_id             char(36) NOT NULL,
    original_points                    decimal(19,4) NOT NULL,
    remaining_points                   decimal(19,4) NOT NULL,
    available_at                       datetime(6) NOT NULL,
    expires_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'AVAILABLE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_points_lot PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_points_lot_origin_ledger_entry_id_1  UNIQUE (origin_ledger_entry_id),
    CONSTRAINT ck_loyalty_points_lot_1 CHECK (original_points > 0),
    CONSTRAINT ck_loyalty_points_lot_2 CHECK (remaining_points >= 0),
    CONSTRAINT ck_loyalty_points_lot_3 CHECK (remaining_points <= original_points),
    CONSTRAINT ck_loyalty_points_lot_4 CHECK (expires_at IS NULL OR expires_at > available_at),
    CONSTRAINT ck_loyalty_points_lot_5 CHECK (status IN ('PENDING','AVAILABLE','CONSUMED','EXPIRED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_redemption (
    id                                 char(36) NOT NULL,
    loyalty_account_id                 char(36) NOT NULL,
    reservation_id                     char(36),
    contract_id                        char(36),
    points_requested                   decimal(19,4) NOT NULL,
    monetary_value                     decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    requested_at                       datetime(6) NOT NULL,
    completed_at                       datetime(6),
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_redemption PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_redemption_idempotency_key_1 UNIQUE (idempotency_key),
    CONSTRAINT ck_loyalty_redemption_1 CHECK (points_requested > 0),
    CONSTRAINT ck_loyalty_redemption_2 CHECK (monetary_value IS NULL OR monetary_value >= 0),
    CONSTRAINT ck_loyalty_redemption_3 CHECK (status IN ('REQUESTED','RESERVED','COMPLETED','FAILED','CANCELLED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_redemption_allocation (
    id                                 char(36) NOT NULL,
    redemption_id                      char(36) NOT NULL,
    points_lot_id                      char(36) NOT NULL,
    points_consumed                    decimal(19,4) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_loyalty_redemption_allocation PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_redemption_allocation_redemption_id_po_22aa0170  UNIQUE (redemption_id, points_lot_id),
    CONSTRAINT ck_loyalty_redemption_allocation_1 CHECK (points_consumed > 0)
) ENGINE=InnoDB;

CREATE TABLE loyalty_benefit (
    id                                 char(36) NOT NULL,
    benefit_code                       varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    benefit_type                       varchar(30) NOT NULL,
    configuration_json                 json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_loyalty_benefit PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_benefit_benefit_code_1 UNIQUE (benefit_code),
    CONSTRAINT ck_loyalty_benefit_1 CHECK (benefit_type IN ('DISCOUNT','UPGRADE','FREE_DAY','ADDITIONAL_DRIVER','PRIORITY','OTHER')),
    CONSTRAINT ck_loyalty_benefit_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_benefit_entitlement (
    id                                 char(36) NOT NULL,
    loyalty_account_id                 char(36) NOT NULL,
    benefit_id                         char(36) NOT NULL,
    granted_at                         datetime(6) NOT NULL,
    expires_at                         datetime(6),
    quantity_granted                   decimal(19,4) NOT NULL DEFAULT 1,
    quantity_remaining                 decimal(19,4) NOT NULL DEFAULT 1,
    source_type                        varchar(40),
    source_id                          char(36),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_benefit_entitlement PRIMARY KEY (id),
    CONSTRAINT ck_loyalty_benefit_entitlement_1 CHECK (quantity_granted > 0),
    CONSTRAINT ck_loyalty_benefit_entitlement_2 CHECK (quantity_remaining >= 0),
    CONSTRAINT ck_loyalty_benefit_entitlement_3 CHECK (quantity_remaining <= quantity_granted),
    CONSTRAINT ck_loyalty_benefit_entitlement_4 CHECK (expires_at IS NULL OR expires_at > granted_at),
    CONSTRAINT ck_loyalty_benefit_entitlement_5 CHECK (status IN ('ACTIVE','CONSUMED','EXPIRED','REVOKED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_benefit_usage (
    id                                 char(36) NOT NULL,
    benefit_entitlement_id             char(36) NOT NULL,
    reservation_id                     char(36),
    contract_id                        char(36),
    quantity_used                      decimal(19,4) NOT NULL,
    used_at                            datetime(6) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'APPLIED',
    reversal_of_usage_id               char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_loyalty_benefit_usage PRIMARY KEY (id),
    CONSTRAINT ck_loyalty_benefit_usage_1 CHECK (quantity_used > 0),
    CONSTRAINT ck_loyalty_benefit_usage_2 CHECK (reversal_of_usage_id IS NULL OR reversal_of_usage_id <> id),
    CONSTRAINT ck_loyalty_benefit_usage_3 CHECK (status IN ('APPLIED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE loyalty_points_transfer (
    id                                 char(36) NOT NULL,
    from_account_id                    char(36) NOT NULL,
    to_account_id                      char(36) NOT NULL,
    points                             decimal(19,4) NOT NULL,
    requested_at                       datetime(6) NOT NULL,
    completed_at                       datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    out_ledger_entry_id                char(36),
    in_ledger_entry_id                 char(36),
    idempotency_key                    varchar(160) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_loyalty_points_transfer PRIMARY KEY (id),
    CONSTRAINT uq_loyalty_points_transfer_idempotency_key_1  UNIQUE (idempotency_key),
    CONSTRAINT ck_loyalty_points_transfer_1 CHECK (from_account_id <> to_account_id),
    CONSTRAINT ck_loyalty_points_transfer_2 CHECK (points > 0),
    CONSTRAINT ck_loyalty_points_transfer_3 CHECK (status IN ('REQUESTED','COMPLETED','FAILED','CANCELLED','REVERSED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_fleet_service_contract (
    id                                 char(36) NOT NULL,
    contract_number                    varchar(60) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    customer_account_id                char(36) NOT NULL,
    corporate_agreement_id             char(36),
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    billing_mode                       varchar(30) NOT NULL,
    currency_code                      char(3) NOT NULL,
    service_scope_json                 json,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_fleet_service_contract PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_fleet_service_contract_legal_entity_94056b31  UNIQUE (legal_entity_id, contract_number),
    CONSTRAINT ck_fleet_mgmt_fleet_service_contract_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_fleet_mgmt_fleet_service_contract_2 CHECK (billing_mode IN ('FIXED_MONTHLY','PER_VEHICLE','PER_KM','HYBRID')),
    CONSTRAINT ck_fleet_mgmt_fleet_service_contract_3 CHECK (status IN ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','TERMINATED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_fleet_service_level (
    id                                 char(36) NOT NULL,
    fleet_service_contract_id          char(36) NOT NULL,
    service_code                       varchar(50) NOT NULL,
    target_value                       decimal(19,6),
    unit_code                          varchar(20),
    measurement_window                 varchar(30),
    penalty_rule_json                  json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_mgmt_fleet_service_level PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_fleet_service_level_fleet_service_c_c0079b34  UNIQUE (fleet_service_contract_id, service_code),
    CONSTRAINT ck_fleet_mgmt_fleet_service_level_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_managed_vehicle_assignment (
    id                                 char(36) NOT NULL,
    fleet_service_contract_id          char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    assigned_driver_profile_id         char(36),
    cost_center_id                     char(36),
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    assignment_status                  varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_managed_vehicle_assignment PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_managed_vehicle_assignment_fleet_se_39f0436d  UNIQUE (fleet_service_contract_id, vehicle_id, start_at),
    CONSTRAINT ck_fleet_mgmt_managed_vehicle_assignment_1  CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_fleet_mgmt_managed_vehicle_assignment_2  CHECK (assignment_status IN ('PLANNED','ACTIVE','SUSPENDED','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_mileage_commitment (
    id                                 char(36) NOT NULL,
    fleet_service_contract_id          char(36) NOT NULL,
    vehicle_id                         char(36),
    period_start                       date NOT NULL,
    period_end                         date NOT NULL,
    included_km                        decimal(12,2) NOT NULL,
    excess_km_amount                   decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    actual_km                          decimal(12,2),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_mileage_commitment PRIMARY KEY (id),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_1 CHECK (period_end >= period_start),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_2 CHECK (included_km >= 0),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_3 CHECK (excess_km_amount >= 0),
    CONSTRAINT ck_fleet_mgmt_mileage_commitment_4 CHECK (actual_km IS NULL OR actual_km >= 0)
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_telemetry_package (
    id                                 char(36) NOT NULL,
    fleet_service_contract_id          char(36) NOT NULL,
    package_code                       varchar(50) NOT NULL,
    features_json                      json NOT NULL,
    monthly_amount                     decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_mgmt_telemetry_package PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_telemetry_package_fleet_service_con_51e8a4d2  UNIQUE (fleet_service_contract_id, package_code),
    CONSTRAINT ck_fleet_mgmt_telemetry_package_1 CHECK (monthly_amount >= 0),
    CONSTRAINT ck_fleet_mgmt_telemetry_package_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_replacement_entitlement (
    id                                 char(36) NOT NULL,
    fleet_service_contract_id          char(36) NOT NULL,
    vehicle_group_id                   char(36),
    trigger_type                       varchar(40) NOT NULL,
    trigger_threshold                  decimal(19,6),
    maximum_days                       int,
    terms_json                         json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_mgmt_replacement_entitlement PRIMARY KEY (id),
    CONSTRAINT ck_fleet_mgmt_replacement_entitlement_1 CHECK (maximum_days IS NULL OR maximum_days > 0),
    CONSTRAINT ck_fleet_mgmt_replacement_entitlement_2 CHECK (trigger_type IN ('MAINTENANCE','ACCIDENT','DOWNTIME','MILEAGE','MANUAL')),
    CONSTRAINT ck_fleet_mgmt_replacement_entitlement_3 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_fleet_service_event (
    id                                 char(36) NOT NULL,
    fleet_service_contract_id          char(36) NOT NULL,
    vehicle_id                         char(36),
    event_type                         varchar(40) NOT NULL,
    source_type                        varchar(40),
    source_id                          char(36),
    occurred_at                        datetime(6) NOT NULL,
    details_json                       json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_mgmt_fleet_service_event PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_subscription_plan (
    id                                 char(36) NOT NULL,
    plan_code                          varchar(50) NOT NULL,
    name                               varchar(140) NOT NULL,
    vehicle_group_id                   char(36) NOT NULL,
    minimum_months                     int NOT NULL,
    included_km_per_month              decimal(12,2) NOT NULL,
    monthly_amount                     decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    terms_json                         json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_subscription_plan PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_subscription_plan_plan_code_1  UNIQUE (plan_code),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_1 CHECK (minimum_months > 0),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_2 CHECK (included_km_per_month >= 0),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_3 CHECK (monthly_amount >= 0),
    CONSTRAINT ck_fleet_mgmt_subscription_plan_4 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_subscription_contract (
    id                                 char(36) NOT NULL,
    contract_number                    varchar(60) NOT NULL,
    subscription_plan_id               char(36) NOT NULL,
    customer_account_id                char(36) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    start_at                           datetime(6) NOT NULL,
    minimum_end_at                     datetime(6) NOT NULL,
    end_at                             datetime(6),
    billing_day                        smallint NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    currency_code                      char(3) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_subscription_contract PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_subscription_contract_legal_entity__79a78c69  UNIQUE (legal_entity_id, contract_number),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_1 CHECK (minimum_end_at > start_at),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_2 CHECK (end_at IS NULL OR end_at >= minimum_end_at),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_3 CHECK (billing_day BETWEEN 1 AND 28),
    CONSTRAINT ck_fleet_mgmt_subscription_contract_4 CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','CANCELLED','COMPLETED','DEFAULTED'))
) ENGINE=InnoDB;

CREATE TABLE fleet_mgmt_subscription_vehicle_assignment (
    id                                 char(36) NOT NULL,
    subscription_contract_id           char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    calendar_entry_id                  char(36),
    start_at                           datetime(6) NOT NULL,
    end_at                             datetime(6),
    assignment_reason                  varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_fleet_mgmt_subscription_vehicle_assignment  PRIMARY KEY (id),
    CONSTRAINT uq_fleet_mgmt_subscription_vehicle_assignment_sub_5dde8dad  UNIQUE (subscription_contract_id, vehicle_id, start_at),
    CONSTRAINT ck_fleet_mgmt_subscription_vehicle_assignment_1  CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT ck_fleet_mgmt_subscription_vehicle_assignment_2  CHECK (assignment_reason IN ('INITIAL','REPLACEMENT','UPGRADE','DOWNGRADE')),
    CONSTRAINT ck_fleet_mgmt_subscription_vehicle_assignment_3  CHECK (status IN ('PLANNED','ACTIVE','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_disposal_candidate (
    id                                 char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    identified_at                      datetime(6) NOT NULL,
    reason_code                        varchar(40) NOT NULL,
    priority                           smallint NOT NULL DEFAULT 100,
    target_sale_date                   date,
    status                             varchar(30) NOT NULL DEFAULT 'IDENTIFIED',
    approved_at                        datetime(6),
    approved_by                        char(36),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_disposal_candidate PRIMARY KEY (id),
    CONSTRAINT uq_used_car_disposal_candidate_vehicle_id_1  UNIQUE (vehicle_id),
    CONSTRAINT ck_used_car_disposal_candidate_1 CHECK (reason_code IN ('AGE','MILEAGE','MAINTENANCE_COST','RESIDUAL_VALUE','FLEET_REBALANCING','ACCIDENT_HISTORY','MODEL_STRATEGY',' OTHER')),
    CONSTRAINT ck_used_car_disposal_candidate_2 CHECK (status IN ('IDENTIFIED','UNDER_REVIEW','APPROVED','REJECTED','PREPARING','LISTED','SOLD','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_vehicle_valuation (
    id                                 char(36) NOT NULL,
    disposal_candidate_id              char(36) NOT NULL,
    valuation_type                     varchar(30) NOT NULL,
    valued_at                          datetime(6) NOT NULL,
    market_value                       decimal(19,4) NOT NULL,
    minimum_sale_value                 decimal(19,4),
    expected_refurbishment_cost        decimal(19,4),
    currency_code                      char(3) NOT NULL,
    valuation_source                   varchar(60),
    model_version                      varchar(60),
    details_json                       json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_used_car_vehicle_valuation PRIMARY KEY (id),
    CONSTRAINT ck_used_car_vehicle_valuation_1 CHECK (market_value >= 0),
    CONSTRAINT ck_used_car_vehicle_valuation_2 CHECK (minimum_sale_value IS NULL OR minimum_sale_value >= 0),
    CONSTRAINT ck_used_car_vehicle_valuation_3 CHECK (expected_refurbishment_cost IS NULL OR expected_refurbishment_cost >= 0),
    CONSTRAINT ck_used_car_vehicle_valuation_4 CHECK (valuation_type IN ('MARKET','TRADE','AUCTION','INTERNAL','APPRAISAL'))
) ENGINE=InnoDB;

CREATE TABLE used_car_refurbishment_order (
    id                                 char(36) NOT NULL,
    disposal_candidate_id              char(36) NOT NULL,
    service_order_id                   char(36),
    opened_at                          datetime(6) NOT NULL,
    target_completion_at               datetime(6),
    completed_at                       datetime(6),
    estimated_amount                   decimal(19,4),
    actual_amount                      decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_refurbishment_order PRIMARY KEY (id),
    CONSTRAINT ck_used_car_refurbishment_order_1 CHECK (completed_at IS NULL OR completed_at >= opened_at),
    CONSTRAINT ck_used_car_refurbishment_order_2 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_order_3 CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_order_4 CHECK (status IN ('OPEN','APPROVED','IN_PROGRESS','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_refurbishment_item (
    id                                 char(36) NOT NULL,
    refurbishment_order_id             char(36) NOT NULL,
    line_number                        int NOT NULL,
    item_type                          varchar(40) NOT NULL,
    description                        varchar(240),
    estimated_amount                   decimal(19,4),
    actual_amount                      decimal(19,4),
    currency_code                      char(3),
    status                             varchar(20) NOT NULL DEFAULT 'PLANNED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_refurbishment_item PRIMARY KEY (id),
    CONSTRAINT uq_used_car_refurbishment_item_refurbishment_orde_45478fc0  UNIQUE (refurbishment_order_id, line_number),
    CONSTRAINT ck_used_car_refurbishment_item_1 CHECK (estimated_amount IS NULL OR estimated_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_item_2 CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT ck_used_car_refurbishment_item_3 CHECK (status IN ('PLANNED','APPROVED','COMPLETED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_sale_channel (
    id                                 char(36) NOT NULL,
    channel_code                       varchar(40) NOT NULL,
    name                               varchar(140) NOT NULL,
    channel_type                       varchar(30) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    configuration_json                 json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_used_car_sale_channel PRIMARY KEY (id),
    CONSTRAINT uq_used_car_sale_channel_channel_code_1 UNIQUE (channel_code),
    CONSTRAINT ck_used_car_sale_channel_1 CHECK (channel_type IN ('OWN_STORE','ONLINE','AUCTION','WHOLESALE','PARTNER')),
    CONSTRAINT ck_used_car_sale_channel_2 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE used_car_listing (
    id                                 char(36) NOT NULL,
    disposal_candidate_id              char(36) NOT NULL,
    sale_channel_id                    char(36) NOT NULL,
    listing_reference                  varchar(100) NOT NULL,
    listed_at                          datetime(6) NOT NULL,
    expires_at                         datetime(6),
    asking_price                       decimal(19,4) NOT NULL,
    currency_code                      char(3) NOT NULL,
    odometer_km                        decimal(12,1) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    description                        text,
    media_manifest                     json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_listing PRIMARY KEY (id),
    CONSTRAINT uq_used_car_listing_sale_channel_id_listing_reference_1  UNIQUE (sale_channel_id, listing_reference),
    CONSTRAINT ck_used_car_listing_1 CHECK (asking_price >= 0),
    CONSTRAINT ck_used_car_listing_2 CHECK (odometer_km >= 0),
    CONSTRAINT ck_used_car_listing_3 CHECK (expires_at IS NULL OR expires_at > listed_at),
    CONSTRAINT ck_used_car_listing_4 CHECK (status IN ('DRAFT','ACTIVE','RESERVED','SOLD','EXPIRED','WITHDRAWN'))
) ENGINE=InnoDB;

CREATE TABLE used_car_lead (
    id                                 char(36) NOT NULL,
    listing_id                         char(36),
    party_id                           char(36),
    source_channel                     varchar(40),
    created_at_source                  datetime(6),
    contact_snapshot                   json,
    status                             varchar(20) NOT NULL DEFAULT 'NEW',
    assigned_to                        char(36),
    next_action_at                     datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_lead PRIMARY KEY (id),
    CONSTRAINT ck_used_car_lead_1 CHECK (status IN ('NEW','CONTACTED','QUALIFIED','TEST_DRIVE','NEGOTIATION','WON','LOST','DUPLICATE'))
) ENGINE=InnoDB;

CREATE TABLE used_car_test_drive (
    id                                 char(36) NOT NULL,
    lead_id                            char(36),
    listing_id                         char(36) NOT NULL,
    driver_profile_id                  char(36) NOT NULL,
    scheduled_start_at                 datetime(6) NOT NULL,
    scheduled_end_at                   datetime(6) NOT NULL,
    actual_start_at                    datetime(6),
    actual_end_at                      datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_test_drive PRIMARY KEY (id),
    CONSTRAINT ck_used_car_test_drive_1 CHECK (scheduled_end_at > scheduled_start_at),
    CONSTRAINT ck_used_car_test_drive_2 CHECK (actual_end_at IS NULL OR actual_start_at IS NULL OR actual_end_at >= actual_start_at),
    CONSTRAINT ck_used_car_test_drive_3 CHECK (status IN ('SCHEDULED','CHECKED_IN','COMPLETED','NO_SHOW','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_sale_order (
    id                                 char(36) NOT NULL,
    sale_order_number                  varchar(60) NOT NULL,
    legal_entity_id                    char(36) NOT NULL,
    buyer_party_id                     char(36) NOT NULL,
    sale_channel_id                    char(36) NOT NULL,
    order_date                         date NOT NULL,
    currency_code                      char(3) NOT NULL,
    subtotal_amount                    decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    total_amount                       decimal(19,4) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_sale_order PRIMARY KEY (id),
    CONSTRAINT uq_used_car_sale_order_legal_entity_id_sale_order_number_1  UNIQUE (legal_entity_id, sale_order_number),
    CONSTRAINT ck_used_car_sale_order_1 CHECK (subtotal_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_3 CHECK (tax_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_4 CHECK (total_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_5 CHECK (status IN ('DRAFT','RESERVED','SIGNED','PAID','DELIVERED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_sale_order_vehicle (
    id                                 char(36) NOT NULL,
    sale_order_id                      char(36) NOT NULL,
    disposal_candidate_id              char(36) NOT NULL,
    vehicle_id                         char(36) NOT NULL,
    listing_id                         char(36),
    sale_price                         decimal(19,4) NOT NULL,
    discount_amount                    decimal(19,4) NOT NULL DEFAULT 0,
    tax_amount                         decimal(19,4) NOT NULL DEFAULT 0,
    currency_code                      char(3) NOT NULL,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_used_car_sale_order_vehicle PRIMARY KEY (id),
    CONSTRAINT uq_used_car_sale_order_vehicle_sale_order_id_vehicle_id_1  UNIQUE (sale_order_id, vehicle_id),
    CONSTRAINT uq_used_car_sale_order_vehicle_vehicle_id_2  UNIQUE (vehicle_id),
    CONSTRAINT ck_used_car_sale_order_vehicle_1 CHECK (sale_price >= 0),
    CONSTRAINT ck_used_car_sale_order_vehicle_2 CHECK (discount_amount >= 0),
    CONSTRAINT ck_used_car_sale_order_vehicle_3 CHECK (tax_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE used_car_vehicle_transfer (
    id                                 char(36) NOT NULL,
    sale_order_vehicle_id              char(36) NOT NULL,
    seller_party_id                    char(36) NOT NULL,
    buyer_party_id                     char(36) NOT NULL,
    requested_at                       datetime(6) NOT NULL,
    completed_at                       datetime(6),
    authority_reference                varchar(160),
    document_object_key                varchar(500),
    status                             varchar(20) NOT NULL DEFAULT 'REQUESTED',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_vehicle_transfer PRIMARY KEY (id),
    CONSTRAINT uq_used_car_vehicle_transfer_sale_order_vehicle_id_1  UNIQUE (sale_order_vehicle_id),
    CONSTRAINT ck_used_car_vehicle_transfer_1 CHECK (status IN ('REQUESTED','DOCUMENTATION_PENDING','SUBMITTED','COMPLETED','REJECTED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_used_vehicle_warranty (
    id                                 char(36) NOT NULL,
    sale_order_vehicle_id              char(36) NOT NULL,
    warranty_code                      varchar(50) NOT NULL,
    starts_at                          date NOT NULL,
    ends_at                            date NOT NULL,
    coverage_json                      json NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_used_car_used_vehicle_warranty PRIMARY KEY (id),
    CONSTRAINT uq_used_car_used_vehicle_warranty_sale_order_vehi_f93774c5  UNIQUE (sale_order_vehicle_id, warranty_code),
    CONSTRAINT ck_used_car_used_vehicle_warranty_1 CHECK (ends_at >= starts_at),
    CONSTRAINT ck_used_car_used_vehicle_warranty_2 CHECK (status IN ('ACTIVE','EXPIRED','CANCELLED','CLAIMED'))
) ENGINE=InnoDB;

CREATE TABLE used_car_sale_document (
    id                                 char(36) NOT NULL,
    sale_order_id                      char(36) NOT NULL,
    document_type                      varchar(40) NOT NULL,
    object_key                         varchar(500) NOT NULL,
    content_type                       varchar(100),
    sha256                             binary(32),
    generated_at                       datetime(6) NOT NULL,
    signed_at                          datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_used_car_sale_document PRIMARY KEY (id),
    CONSTRAINT ck_used_car_sale_document_1 CHECK (status IN ('ACTIVE','SUPERSEDED','VOID'))
) ENGINE=InnoDB;

CREATE TABLE privacy_privacy_notice (
    id                                 char(36) NOT NULL,
    notice_code                        varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    country_code                       char(2) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_privacy_privacy_notice PRIMARY KEY (id),
    CONSTRAINT uq_privacy_privacy_notice_country_code_notice_code_1  UNIQUE (country_code, notice_code),
    CONSTRAINT ck_privacy_privacy_notice_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE privacy_privacy_notice_version (
    id                                 char(36) NOT NULL,
    privacy_notice_id                  char(36) NOT NULL,
    version_number                     int NOT NULL,
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    language_code                      varchar(10) NOT NULL,
    content_object_key                 varchar(500) NOT NULL,
    content_hash                       varchar(64) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'DRAFT',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_privacy_notice_version PRIMARY KEY (id),
    CONSTRAINT uq_privacy_privacy_notice_version_privacy_notice__a2c98a00  UNIQUE (privacy_notice_id, version_number, language_code),
    CONSTRAINT ck_privacy_privacy_notice_version_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_privacy_privacy_notice_version_2 CHECK (status IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB;

CREATE TABLE privacy_processing_purpose (
    id                                 char(36) NOT NULL,
    purpose_code                       varchar(50) NOT NULL,
    name                               varchar(160) NOT NULL,
    description                        text,
    data_categories_json               json,
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_privacy_processing_purpose PRIMARY KEY (id),
    CONSTRAINT uq_privacy_processing_purpose_purpose_code_1  UNIQUE (purpose_code),
    CONSTRAINT ck_privacy_processing_purpose_1 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE privacy_legal_basis (
    id                                 char(36) NOT NULL,
    purpose_id                         char(36) NOT NULL,
    country_code                       char(2) NOT NULL,
    basis_type                         varchar(40) NOT NULL,
    legal_reference                    varchar(240),
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_privacy_legal_basis PRIMARY KEY (id),
    CONSTRAINT ck_privacy_legal_basis_1 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_privacy_legal_basis_2 CHECK (basis_type IN ('CONSENT','CONTRACT','LEGAL_OBLIGATION','LEGITIMATE_INTEREST','VITAL_INTEREST','PUBLIC_TASK','FRAUD_PREVENTION',' CREDIT_PROTECTION','OTHER')),
    CONSTRAINT ck_privacy_legal_basis_3 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE privacy_consent_receipt (
    id                                 char(36) NOT NULL,
    party_id                           char(36) NOT NULL,
    privacy_notice_version_id          char(36) NOT NULL,
    purpose_id                         char(36) NOT NULL,
    decision                           varchar(20) NOT NULL,
    captured_at                        datetime(6) NOT NULL,
    channel_id                         char(36),
    evidence_hash                      varchar(64) NOT NULL,
    ip_address_token                   varchar(100),
    device_reference                   varchar(160),
    withdrawn_at                       datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_privacy_consent_receipt PRIMARY KEY (id),
    CONSTRAINT ck_privacy_consent_receipt_1 CHECK (decision IN ('GRANTED','DENIED','WITHDRAWN')),
    CONSTRAINT ck_privacy_consent_receipt_2 CHECK (withdrawn_at IS NULL OR withdrawn_at >= captured_at)
) ENGINE=InnoDB;

CREATE TABLE privacy_data_subject_request (
    id                                 char(36) NOT NULL,
    party_id                           char(36),
    request_type                       varchar(30) NOT NULL,
    received_at                        datetime(6) NOT NULL,
    due_at                             datetime(6),
    channel_id                         char(36),
    identity_verification_id           char(36),
    status                             varchar(30) NOT NULL DEFAULT 'RECEIVED',
    assigned_to                        char(36),
    completed_at                       datetime(6),
    resolution_summary                 text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_data_subject_request PRIMARY KEY (id),
    CONSTRAINT ck_privacy_data_subject_request_1 CHECK (request_type IN ('ACCESS','CORRECTION','PORTABILITY','DELETION','ANONYMIZATION','INFORMATION','OBJECTION','RESTRICTION')),
    CONSTRAINT ck_privacy_data_subject_request_2 CHECK (status IN ('RECEIVED','IDENTITY_PENDING','IN_PROGRESS','PARTIALLY_COMPLETED','COMPLETED','DENIED','CANCELLED')),
    CONSTRAINT ck_privacy_data_subject_request_3 CHECK (due_at IS NULL OR due_at >= received_at),
    CONSTRAINT ck_privacy_data_subject_request_4 CHECK (completed_at IS NULL OR completed_at >= received_at)
) ENGINE=InnoDB;

CREATE TABLE privacy_retention_policy (
    id                                 char(36) NOT NULL,
    policy_code                        varchar(60) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    country_code                       char(2),
    retention_days                     int NOT NULL,
    trigger_event                      varchar(60) NOT NULL,
    disposition_action                 varchar(30) NOT NULL,
    legal_reference                    varchar(240),
    valid_from                         datetime(6) NOT NULL,
    valid_to                           datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_retention_policy PRIMARY KEY (id),
    CONSTRAINT uq_privacy_retention_policy_policy_code_valid_from_1  UNIQUE (policy_code, valid_from),
    CONSTRAINT ck_privacy_retention_policy_1 CHECK (retention_days >= 0),
    CONSTRAINT ck_privacy_retention_policy_2 CHECK (valid_to IS NULL OR valid_to > valid_from),
    CONSTRAINT ck_privacy_retention_policy_3 CHECK (disposition_action IN ('DELETE','ANONYMIZE','ARCHIVE','REVIEW')),
    CONSTRAINT ck_privacy_retention_policy_4 CHECK (status IN ('ACTIVE','INACTIVE'))
) ENGINE=InnoDB;

CREATE TABLE privacy_legal_hold (
    id                                 char(36) NOT NULL,
    hold_reference                     varchar(100) NOT NULL,
    party_id                           char(36),
    resource_type                      varchar(80),
    resource_id                        char(36),
    reason_code                        varchar(60) NOT NULL,
    starts_at                          datetime(6) NOT NULL,
    ends_at                            datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    authorized_by                      char(36),
    notes                              text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_legal_hold PRIMARY KEY (id),
    CONSTRAINT uq_privacy_legal_hold_hold_reference_1 UNIQUE (hold_reference),
    CONSTRAINT ck_privacy_legal_hold_1 CHECK (ends_at IS NULL OR ends_at > starts_at),
    CONSTRAINT ck_privacy_legal_hold_2 CHECK (status IN ('ACTIVE','RELEASED','EXPIRED'))
) ENGINE=InnoDB;

CREATE TABLE privacy_erasure_job (
    id                                 char(36) NOT NULL,
    data_subject_request_id            char(36),
    party_id                           char(36),
    resource_type                      varchar(80) NOT NULL,
    resource_id                        char(36),
    action_type                        varchar(30) NOT NULL,
    scheduled_at                       datetime(6) NOT NULL,
    executed_at                        datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'SCHEDULED',
    blocked_by_legal_hold_id           char(36),
    result_json                        json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_erasure_job PRIMARY KEY (id),
    CONSTRAINT ck_privacy_erasure_job_1 CHECK (action_type IN ('DELETE','ANONYMIZE','TOKENIZE','ARCHIVE')),
    CONSTRAINT ck_privacy_erasure_job_2 CHECK (status IN ('SCHEDULED','RUNNING','COMPLETED','FAILED','BLOCKED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE privacy_data_access_audit (
    id                                 char(36) NOT NULL,
    actor_id                           char(36),
    actor_type                         varchar(30) NOT NULL,
    party_id                           char(36),
    resource_type                      varchar(80) NOT NULL,
    resource_id                        char(36),
    action                             varchar(30) NOT NULL,
    purpose_code                       varchar(50),
    occurred_at                        datetime(6) NOT NULL,
    request_id                         varchar(100),
    source_ip_token                    varchar(100),
    metadata_json                      json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_privacy_data_access_audit PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE privacy_data_sharing_record (
    id                                 char(36) NOT NULL,
    party_id                           char(36),
    recipient_party_id                 char(36),
    recipient_name                     varchar(180),
    purpose_id                         char(36) NOT NULL,
    legal_basis_id                     char(36),
    data_categories_json               json NOT NULL,
    shared_at                          datetime(6) NOT NULL,
    transfer_country_code              char(2),
    agreement_reference                varchar(120),
    request_reference                  varchar(120),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_privacy_data_sharing_record PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE privacy_token_map (
    id                                 char(36) NOT NULL,
    token_type                         varchar(40) NOT NULL,
    token_value                        varchar(180) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    resource_id_ciphertext             text NOT NULL,
    created_at_source                  datetime(6) NOT NULL,
    expires_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_privacy_token_map PRIMARY KEY (id),
    CONSTRAINT uq_privacy_token_map_token_type_token_value_1  UNIQUE (token_type, token_value),
    CONSTRAINT ck_privacy_token_map_1 CHECK (status IN ('ACTIVE','REVOKED','EXPIRED'))
) ENGINE=InnoDB;

CREATE TABLE integration_outbox_event (
    id                                 char(36) NOT NULL,
    aggregate_type                     varchar(80) NOT NULL,
    aggregate_id                       char(36) NOT NULL,
    aggregate_version                  bigint NOT NULL,
    event_index                        smallint NOT NULL DEFAULT 0,
    event_type                         varchar(120) NOT NULL,
    payload_version                    int NOT NULL DEFAULT 1,
    payload                            json NOT NULL,
    occurred_at                        datetime(6) NOT NULL,
    published_at                       datetime(6),
    publish_attempts                   int NOT NULL DEFAULT 0,
    last_error                         text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_outbox_event PRIMARY KEY (id),
    CONSTRAINT uq_integration_outbox_event_aggregate_type_aggreg_7e983bc6  UNIQUE (aggregate_type, aggregate_id, aggregate_version, event_index),
    CONSTRAINT ck_integration_outbox_event_1 CHECK (aggregate_version >= 0),
    CONSTRAINT ck_integration_outbox_event_2 CHECK (event_index >= 0),
    CONSTRAINT ck_integration_outbox_event_3 CHECK (payload_version > 0),
    CONSTRAINT ck_integration_outbox_event_4 CHECK (publish_attempts >= 0)
) ENGINE=InnoDB;

CREATE TABLE integration_inbox_message (
    id                                 char(36) NOT NULL,
    consumer_name                      varchar(100) NOT NULL,
    message_id                         varchar(180) NOT NULL,
    event_type                         varchar(120),
    received_at                        datetime(6) NOT NULL,
    processed_at                       datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    result_json                        json,
    last_error                         text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_inbox_message PRIMARY KEY (id),
    CONSTRAINT uq_integration_inbox_message_consumer_name_message_id_1  UNIQUE (consumer_name, message_id),
    CONSTRAINT ck_integration_inbox_message_1 CHECK (status IN ('RECEIVED','PROCESSING','PROCESSED','FAILED','IGNORED'))
) ENGINE=InnoDB;

CREATE TABLE integration_idempotency_key (
    id                                 char(36) NOT NULL,
    scope                              varchar(100) NOT NULL,
    idempotency_key                    varchar(180) NOT NULL,
    request_hash                       varchar(64) NOT NULL,
    resource_type                      varchar(80),
    resource_id                        char(36),
    response_code                      int,
    response_snapshot                  json,
    expires_at                         datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'PROCESSING',
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_idempotency_key PRIMARY KEY (id),
    CONSTRAINT uq_integration_idempotency_key_scope_idempotency_key_1  UNIQUE (scope, idempotency_key),
    CONSTRAINT ck_integration_idempotency_key_1 CHECK (status IN ('PROCESSING','COMPLETED','FAILED','EXPIRED'))
) ENGINE=InnoDB;

CREATE TABLE integration_external_reference (
    id                                 char(36) NOT NULL,
    system_code                        varchar(60) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    resource_id                        char(36) NOT NULL,
    external_resource_type             varchar(80),
    external_id                        varchar(180) NOT NULL,
    valid_from                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    valid_to                           datetime(6),
    metadata_json                      json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_integration_external_reference PRIMARY KEY (id),
    CONSTRAINT uq_integration_external_reference_system_code_ext_9c5d3d28  UNIQUE (system_code, external_id, valid_from),
    CONSTRAINT ck_integration_external_reference_1 CHECK (valid_to IS NULL OR valid_to > valid_from)
) ENGINE=InnoDB;

CREATE TABLE integration_saga_instance (
    id                                 char(36) NOT NULL,
    saga_type                          varchar(100) NOT NULL,
    business_key                       varchar(180) NOT NULL,
    current_step                       varchar(100),
    status                             varchar(20) NOT NULL DEFAULT 'STARTED',
    state_json                         json,
    started_at                         datetime(6) NOT NULL,
    completed_at                       datetime(6),
    last_error                         text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_saga_instance PRIMARY KEY (id),
    CONSTRAINT uq_integration_saga_instance_saga_type_business_key_1  UNIQUE (saga_type, business_key),
    CONSTRAINT ck_integration_saga_instance_1 CHECK (status IN ('STARTED','RUNNING','COMPENSATING','COMPLETED','FAILED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE integration_saga_step (
    id                                 char(36) NOT NULL,
    saga_instance_id                   char(36) NOT NULL,
    step_number                        int NOT NULL,
    step_name                          varchar(100) NOT NULL,
    status                             varchar(20) NOT NULL DEFAULT 'PENDING',
    attempts                           int NOT NULL DEFAULT 0,
    started_at                         datetime(6),
    completed_at                       datetime(6),
    request_json                       json,
    result_json                        json,
    last_error                         text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_saga_step PRIMARY KEY (id),
    CONSTRAINT uq_integration_saga_step_saga_instance_id_step_number_1  UNIQUE (saga_instance_id, step_number),
    CONSTRAINT ck_integration_saga_step_1 CHECK (step_number >= 0),
    CONSTRAINT ck_integration_saga_step_2 CHECK (attempts >= 0),
    CONSTRAINT ck_integration_saga_step_3 CHECK (status IN ('PENDING','RUNNING','COMPLETED','FAILED','COMPENSATED','SKIPPED'))
) ENGINE=InnoDB;

CREATE TABLE integration_dead_letter (
    id                                 char(36) NOT NULL,
    source_system                      varchar(80) NOT NULL,
    message_id                         varchar(180) NOT NULL,
    event_type                         varchar(120),
    payload                            json,
    error_class                        varchar(160),
    error_message                      text,
    failed_at                          datetime(6) NOT NULL,
    retry_count                        int NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'OPEN',
    reprocessed_at                     datetime(6),
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_dead_letter PRIMARY KEY (id),
    CONSTRAINT uq_integration_dead_letter_source_system_message_id_1  UNIQUE (source_system, message_id),
    CONSTRAINT ck_integration_dead_letter_1 CHECK (retry_count >= 0),
    CONSTRAINT ck_integration_dead_letter_2 CHECK (status IN ('OPEN','RETRYING','REPROCESSED','IGNORED','RESOLVED'))
) ENGINE=InnoDB;

CREATE TABLE integration_audit_event (
    id                                 char(36) NOT NULL,
    actor_type                         varchar(30) NOT NULL,
    actor_id                           char(36),
    action                             varchar(80) NOT NULL,
    resource_type                      varchar(80) NOT NULL,
    resource_id                        char(36),
    legal_entity_id                    char(36),
    branch_id                          char(36),
    occurred_at                        datetime(6) NOT NULL,
    request_id                         varchar(100),
    correlation_id                     varchar(100),
    source_ip_token                    varchar(100),
    before_hash                        varchar(64),
    after_hash                         varchar(64),
    metadata_json                      json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_integration_audit_event PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE integration_job_run (
    id                                 char(36) NOT NULL,
    job_name                           varchar(120) NOT NULL,
    run_key                            varchar(180) NOT NULL,
    started_at                         datetime(6) NOT NULL,
    completed_at                       datetime(6),
    status                             varchar(20) NOT NULL DEFAULT 'RUNNING',
    records_read                       bigint NOT NULL DEFAULT 0,
    records_written                    bigint NOT NULL DEFAULT 0,
    records_failed                     bigint NOT NULL DEFAULT 0,
    checkpoint_json                    json,
    last_error                         text,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_job_run PRIMARY KEY (id),
    CONSTRAINT uq_integration_job_run_job_name_run_key_1 UNIQUE (job_name, run_key),
    CONSTRAINT ck_integration_job_run_1 CHECK (records_read >= 0),
    CONSTRAINT ck_integration_job_run_2 CHECK (records_written >= 0),
    CONSTRAINT ck_integration_job_run_3 CHECK (records_failed >= 0),
    CONSTRAINT ck_integration_job_run_4 CHECK (status IN ('RUNNING','COMPLETED','PARTIAL','FAILED','CANCELLED'))
) ENGINE=InnoDB;

CREATE TABLE integration_import_batch (
    id                                 char(36) NOT NULL,
    import_type                        varchar(80) NOT NULL,
    source_system                      varchar(80) NOT NULL,
    external_batch_id                  varchar(180),
    object_key                         varchar(500),
    received_at                        datetime(6) NOT NULL,
    processed_at                       datetime(6),
    record_count                       int NOT NULL DEFAULT 0,
    success_count                      int NOT NULL DEFAULT 0,
    failure_count                      int NOT NULL DEFAULT 0,
    status                             varchar(20) NOT NULL DEFAULT 'RECEIVED',
    result_json                        json,
    created_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at                         datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    row_version                        bigint NOT NULL DEFAULT 0,
    CONSTRAINT pk_integration_import_batch PRIMARY KEY (id),
    CONSTRAINT uq_integration_import_batch_source_system_externa_958d6d40  UNIQUE (source_system, external_batch_id),
    CONSTRAINT ck_integration_import_batch_1 CHECK (record_count >= 0),
    CONSTRAINT ck_integration_import_batch_2 CHECK (success_count >= 0),
    CONSTRAINT ck_integration_import_batch_3 CHECK (failure_count >= 0),
    CONSTRAINT ck_integration_import_batch_4 CHECK (status IN ('RECEIVED','VALIDATING','PROCESSING','COMPLETED','PARTIAL','FAILED','REJECTED'))
) ENGINE=InnoDB;


CREATE TABLE fleet_vehicle_calendar_guard (
    vehicle_id                           char(36) NOT NULL,
    lock_version                         bigint NOT NULL DEFAULT 0,
    updated_at                           datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    CONSTRAINT pk_fleet_vehicle_calendar_guard PRIMARY KEY (vehicle_id)
) ENGINE=InnoDB;

-- --------------------------------------------------------------------------
-- Foreign keys
-- --------------------------------------------------------------------------
ALTER TABLE org_business_unit ADD CONSTRAINT fk_org_business_unit_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE org_business_unit ADD CONSTRAINT fk_org_business_unit_parent_business_unit_id_org__913017ce  FOREIGN KEY (parent_business_unit_id) REFERENCES org_business_unit (id);
ALTER TABLE org_branch ADD CONSTRAINT fk_org_branch_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE org_branch ADD CONSTRAINT fk_org_branch_business_unit_id_org_business_unit_2  FOREIGN KEY (business_unit_id) REFERENCES org_business_unit (id);
ALTER TABLE org_branch_operator ADD CONSTRAINT fk_org_branch_operator_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id) ON DELETE CASCADE;
ALTER TABLE org_branch_operator ADD CONSTRAINT fk_org_branch_operator_operator_party_id_party_party_2  FOREIGN KEY (operator_party_id) REFERENCES party_party (id);
ALTER TABLE org_branch_hours ADD CONSTRAINT fk_org_branch_hours_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id) ON DELETE CASCADE;
ALTER TABLE org_branch_calendar_exception ADD CONSTRAINT fk_org_branch_calendar_exception_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id) ON DELETE CASCADE;
ALTER TABLE party_party ADD CONSTRAINT fk_party_party_merged_into_party_id_party_party_1  FOREIGN KEY (merged_into_party_id) REFERENCES party_party (id);
ALTER TABLE party_person ADD CONSTRAINT fk_party_person_party_id_party_party_1 FOREIGN KEY (party_id) REFERENCES party_party (id) ON DELETE CASCADE;
ALTER TABLE party_organization ADD CONSTRAINT fk_party_organization_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id) ON DELETE CASCADE;
ALTER TABLE party_party_identifier ADD CONSTRAINT fk_party_party_identifier_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id) ON DELETE CASCADE;
ALTER TABLE party_contact_point ADD CONSTRAINT fk_party_contact_point_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id) ON DELETE CASCADE;
ALTER TABLE party_party_address ADD CONSTRAINT fk_party_party_address_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id) ON DELETE CASCADE;
ALTER TABLE party_party_address ADD CONSTRAINT fk_party_party_address_address_id_party_postal_address_2  FOREIGN KEY (address_id) REFERENCES party_postal_address (id);
ALTER TABLE party_customer_account ADD CONSTRAINT fk_party_customer_account_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE party_customer_account ADD CONSTRAINT fk_party_customer_account_legal_entity_id_org_leg_69f18cc9  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE party_organization_representative ADD CONSTRAINT fk_party_organization_representative_organization_991f314f  FOREIGN KEY (organization_party_id) REFERENCES party_organization (party_id);
ALTER TABLE party_organization_representative ADD CONSTRAINT fk_party_organization_representative_person_party_06bc49af  FOREIGN KEY (person_party_id) REFERENCES party_person (party_id);
ALTER TABLE party_driver_profile ADD CONSTRAINT fk_party_driver_profile_person_party_id_party_person_1  FOREIGN KEY (person_party_id) REFERENCES party_person (party_id);
ALTER TABLE party_driver_license ADD CONSTRAINT fk_party_driver_license_driver_profile_id_party_d_1256538a  FOREIGN KEY (driver_profile_id) REFERENCES party_driver_profile (id)  ON DELETE CASCADE;
ALTER TABLE party_identity_verification ADD CONSTRAINT fk_party_identity_verification_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE party_risk_assessment ADD CONSTRAINT fk_party_risk_assessment_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE party_customer_restriction ADD CONSTRAINT fk_party_customer_restriction_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE catalog_vehicle_model ADD CONSTRAINT fk_catalog_vehicle_model_make_id_catalog_vehicle_make_1  FOREIGN KEY (make_id) REFERENCES catalog_vehicle_make (id);
ALTER TABLE catalog_vehicle_variant ADD CONSTRAINT fk_catalog_vehicle_variant_model_id_catalog_vehic_cc9f481e  FOREIGN KEY (model_id) REFERENCES catalog_vehicle_model (id);
ALTER TABLE catalog_variant_feature ADD CONSTRAINT fk_catalog_variant_feature_vehicle_variant_id_cat_b18cefb4  FOREIGN KEY (vehicle_variant_id) REFERENCES catalog_vehicle_variant (id) ON DELETE CASCADE;
ALTER TABLE catalog_variant_feature ADD CONSTRAINT fk_catalog_variant_feature_feature_id_catalog_feature_2  FOREIGN KEY (feature_id) REFERENCES catalog_feature (id) ON DELETE CASCADE;
ALTER TABLE catalog_vehicle_group_variant ADD CONSTRAINT fk_catalog_vehicle_group_variant_vehicle_group_id_3433c773  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id) ON DELETE CASCADE;
ALTER TABLE catalog_vehicle_group_variant ADD CONSTRAINT fk_catalog_vehicle_group_variant_vehicle_variant__9cb5d80b  FOREIGN KEY (vehicle_variant_id) REFERENCES catalog_vehicle_variant (id);
ALTER TABLE catalog_vehicle_group_upgrade ADD CONSTRAINT fk_catalog_vehicle_group_upgrade_from_group_id_ca_3d9eb99b  FOREIGN KEY (from_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE catalog_vehicle_group_upgrade ADD CONSTRAINT fk_catalog_vehicle_group_upgrade_to_group_id_cata_b75e5b64  FOREIGN KEY (to_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE catalog_commercial_product ADD CONSTRAINT fk_catalog_commercial_product_unit_code_catalog_u_bb2e364a  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure (unit_code);
ALTER TABLE catalog_commercial_product ADD CONSTRAINT fk_catalog_commercial_product_tax_category_id_cat_a17528a4  FOREIGN KEY (tax_category_id) REFERENCES catalog_tax_category (id);
ALTER TABLE catalog_protection_coverage ADD CONSTRAINT fk_catalog_protection_coverage_protection_product_ee8a7131  FOREIGN KEY (protection_product_id) REFERENCES catalog_commercial_product (id) ON DELETE CASCADE;
ALTER TABLE catalog_protection_coverage ADD CONSTRAINT fk_catalog_protection_coverage_coverage_id_catalo_fa7da6c0  FOREIGN KEY (coverage_id) REFERENCES catalog_coverage (id);
ALTER TABLE catalog_charge_type ADD CONSTRAINT fk_catalog_charge_type_default_product_id_catalog_0ab13201  FOREIGN KEY (default_product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE corporate_partner ADD CONSTRAINT fk_corporate_partner_party_id_party_organization_1  FOREIGN KEY (party_id) REFERENCES party_organization (party_id);
ALTER TABLE corporate_partner_agreement ADD CONSTRAINT fk_corporate_partner_agreement_partner_id_corpora_bdc6085c  FOREIGN KEY (partner_id) REFERENCES corporate_partner (id);
ALTER TABLE corporate_partner_agreement ADD CONSTRAINT fk_corporate_partner_agreement_legal_entity_id_or_9769ba82  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE corporate_corporate_agreement ADD CONSTRAINT fk_corporate_corporate_agreement_customer_account_fabc5706  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE corporate_corporate_agreement ADD CONSTRAINT fk_corporate_corporate_agreement_legal_entity_id__b542cbcb  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE corporate_corporate_cost_center ADD CONSTRAINT fk_corporate_corporate_cost_center_corporate_agre_0e663e39  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate_corporate_cost_center ADD CONSTRAINT fk_corporate_corporate_cost_center_parent_cost_ce_d1c0422c  FOREIGN KEY (parent_cost_center_id) REFERENCES corporate_corporate_cost_center (id);
ALTER TABLE corporate_authorized_driver ADD CONSTRAINT fk_corporate_authorized_driver_corporate_agreemen_dfd5ceff  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate_authorized_driver ADD CONSTRAINT fk_corporate_authorized_driver_driver_profile_id__c24f2666  FOREIGN KEY (driver_profile_id) REFERENCES party_driver_profile (id);
ALTER TABLE corporate_authorized_driver ADD CONSTRAINT fk_corporate_authorized_driver_cost_center_id_cor_0ddc326b  FOREIGN KEY (cost_center_id) REFERENCES corporate_corporate_cost_center (id);
ALTER TABLE corporate_corporate_billing_profile ADD CONSTRAINT fk_corporate_corporate_billing_profile_corporate__547efdde  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate_corporate_billing_profile ADD CONSTRAINT fk_corporate_corporate_billing_profile_billing_pa_78869652  FOREIGN KEY (billing_party_id) REFERENCES party_party (id);
ALTER TABLE corporate_corporate_billing_profile ADD CONSTRAINT fk_corporate_corporate_billing_profile_billing_ad_1942df6c  FOREIGN KEY (billing_address_id) REFERENCES party_postal_address (id);
ALTER TABLE fleet_acquisition_order ADD CONSTRAINT fk_fleet_acquisition_order_legal_entity_id_org_le_b74bdace  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE fleet_acquisition_order ADD CONSTRAINT fk_fleet_acquisition_order_supplier_party_id_part_b47c48d6  FOREIGN KEY (supplier_party_id) REFERENCES party_organization (party_id);
ALTER TABLE fleet_acquisition_order_line ADD CONSTRAINT fk_fleet_acquisition_order_line_acquisition_order_5b6faa62  FOREIGN KEY (acquisition_order_id) REFERENCES fleet_acquisition_order (id) ON DELETE CASCADE;
ALTER TABLE fleet_acquisition_order_line ADD CONSTRAINT fk_fleet_acquisition_order_line_vehicle_variant_i_8ee7863e  FOREIGN KEY (vehicle_variant_id) REFERENCES catalog_vehicle_variant ( id);
ALTER TABLE fleet_vehicle ADD CONSTRAINT fk_fleet_vehicle_vehicle_variant_id_catalog_vehic_566b420b  FOREIGN KEY (vehicle_variant_id) REFERENCES catalog_vehicle_variant (id);
ALTER TABLE fleet_vehicle ADD CONSTRAINT fk_fleet_vehicle_owning_legal_entity_id_org_legal_entity_2  FOREIGN KEY (owning_legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE fleet_vehicle ADD CONSTRAINT fk_fleet_vehicle_acquisition_order_line_id_fleet__674c3c12  FOREIGN KEY (acquisition_order_line_id) REFERENCES fleet_acquisition_order_line (id);
ALTER TABLE fleet_vehicle ADD CONSTRAINT fk_fleet_vehicle_current_branch_id_org_branch_4  FOREIGN KEY (current_branch_id) REFERENCES org_branch (id);
ALTER TABLE fleet_vehicle ADD CONSTRAINT fk_fleet_vehicle_current_vehicle_group_id_catalog_535204f6  FOREIGN KEY (current_vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE fleet_vehicle_registration ADD CONSTRAINT fk_fleet_vehicle_registration_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet_vehicle_group_assignment ADD CONSTRAINT fk_fleet_vehicle_group_assignment_vehicle_id_flee_842255ce  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet_vehicle_group_assignment ADD CONSTRAINT fk_fleet_vehicle_group_assignment_vehicle_group_i_14bed1dd  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE fleet_vehicle_operational_state_history ADD CONSTRAINT fk_fleet_vehicle_operational_state_history_vehicl_98f31720  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet_vehicle_lifecycle_history ADD CONSTRAINT fk_fleet_vehicle_lifecycle_history_vehicle_id_fle_94edbc4a  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id) ON DELETE CASCADE;
ALTER TABLE fleet_vehicle_restriction ADD CONSTRAINT fk_fleet_vehicle_restriction_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_vehicle_location_history ADD CONSTRAINT fk_fleet_vehicle_location_history_vehicle_id_flee_7dfbd856  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_vehicle_location_history ADD CONSTRAINT fk_fleet_vehicle_location_history_branch_id_org_branch_2  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE fleet_vehicle_calendar_entry ADD CONSTRAINT fk_fleet_vehicle_calendar_entry_legal_entity_id_o_6e894812  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE fleet_vehicle_calendar_entry ADD CONSTRAINT fk_fleet_vehicle_calendar_entry_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_odometer_reading ADD CONSTRAINT fk_fleet_odometer_reading_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_odometer_reading ADD CONSTRAINT fk_fleet_odometer_reading_corrects_reading_id_fle_7abc031f  FOREIGN KEY (corrects_reading_id) REFERENCES fleet_odometer_reading (id);
ALTER TABLE fleet_fuel_reading ADD CONSTRAINT fk_fleet_fuel_reading_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_asset_document ADD CONSTRAINT fk_fleet_asset_document_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_accessory_asset ADD CONSTRAINT fk_fleet_accessory_asset_product_id_catalog_comme_2de1c88f  FOREIGN KEY (product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE fleet_accessory_asset ADD CONSTRAINT fk_fleet_accessory_asset_owning_legal_entity_id_o_3c33def1  FOREIGN KEY (owning_legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE fleet_vehicle_accessory_assignment ADD CONSTRAINT fk_fleet_vehicle_accessory_assignment_vehicle_id__9d76ef64  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_vehicle_accessory_assignment ADD CONSTRAINT fk_fleet_vehicle_accessory_assignment_accessory_a_d6bac007  FOREIGN KEY (accessory_asset_id) REFERENCES fleet_accessory_asset (id);
ALTER TABLE fleet_vehicle_cost_basis ADD CONSTRAINT fk_fleet_vehicle_cost_basis_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_depreciation_entry ADD CONSTRAINT fk_fleet_depreciation_entry_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_disposal_eligibility ADD CONSTRAINT fk_fleet_disposal_eligibility_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE pricing_rate_plan ADD CONSTRAINT fk_pricing_rate_plan_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE pricing_rate_plan_version ADD CONSTRAINT fk_pricing_rate_plan_version_rate_plan_id_pricing_733eaaf5  FOREIGN KEY (rate_plan_id) REFERENCES pricing_rate_plan (id)  ON DELETE CASCADE;
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_rate_plan_vers_3a8fc222  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_origin_branch__66ca57bc  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_destination_br_38984212  FOREIGN KEY (destination_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_vehicle_group__7ae718b9  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group ( id);
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_channel_id_org_1ba087d8  FOREIGN KEY (channel_id) REFERENCES org_channel (id);
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_corporate_agre_6e701357  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id);
ALTER TABLE pricing_rate_plan_applicability ADD CONSTRAINT fk_pricing_rate_plan_applicability_partner_id_cor_e060e1ed  FOREIGN KEY (partner_id) REFERENCES corporate_partner (id);
ALTER TABLE pricing_rental_length_band ADD CONSTRAINT fk_pricing_rental_length_band_rate_plan_version_i_9c376409  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing_season ADD CONSTRAINT fk_pricing_season_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE pricing_base_rate ADD CONSTRAINT fk_pricing_base_rate_rate_plan_version_id_pricing_2316b89f  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id)  ON DELETE CASCADE;
ALTER TABLE pricing_base_rate ADD CONSTRAINT fk_pricing_base_rate_vehicle_group_id_catalog_veh_78dc57b3  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE pricing_base_rate ADD CONSTRAINT fk_pricing_base_rate_origin_branch_id_org_branch_3  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_base_rate ADD CONSTRAINT fk_pricing_base_rate_rental_length_band_id_pricin_6d056e4d  FOREIGN KEY (rental_length_band_id) REFERENCES pricing_rental_length_band (id);
ALTER TABLE pricing_base_rate ADD CONSTRAINT fk_pricing_base_rate_season_id_pricing_season_5  FOREIGN KEY (season_id) REFERENCES pricing_season (id);
ALTER TABLE pricing_mileage_package ADD CONSTRAINT fk_pricing_mileage_package_rate_plan_version_id_p_270ffd4f  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version ( id) ON DELETE CASCADE;
ALTER TABLE pricing_mileage_rate ADD CONSTRAINT fk_pricing_mileage_rate_mileage_package_id_pricin_090b9e6d  FOREIGN KEY (mileage_package_id) REFERENCES pricing_mileage_package (id)  ON DELETE CASCADE;
ALTER TABLE pricing_mileage_rate ADD CONSTRAINT fk_pricing_mileage_rate_vehicle_group_id_catalog__91640bf7  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE pricing_one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_rate_plan_version_id_pric_bf479ef8  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing_one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_origin_branch_id_org_branch_2  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_destination_branch_id_org_branch_3  FOREIGN KEY (destination_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_one_way_rule ADD CONSTRAINT fk_pricing_one_way_rule_vehicle_group_id_catalog__cf12e5c7  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE pricing_one_way_price ADD CONSTRAINT fk_pricing_one_way_price_one_way_rule_id_pricing__e419f17b  FOREIGN KEY (one_way_rule_id) REFERENCES pricing_one_way_rule (id)  ON DELETE CASCADE;
ALTER TABLE pricing_fuel_price ADD CONSTRAINT fk_pricing_fuel_price_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE pricing_fuel_price ADD CONSTRAINT fk_pricing_fuel_price_branch_id_org_branch_2  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_preauthorization_rule ADD CONSTRAINT fk_pricing_preauthorization_rule_rate_plan_versio_f22e10b2  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing_preauthorization_rule ADD CONSTRAINT fk_pricing_preauthorization_rule_vehicle_group_id_d327ec19  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE pricing_pricing_rule ADD CONSTRAINT fk_pricing_pricing_rule_rate_plan_version_id_pric_5df31375  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id) ON DELETE CASCADE;
ALTER TABLE pricing_coupon ADD CONSTRAINT fk_pricing_coupon_promotion_id_pricing_promotion_1  FOREIGN KEY (promotion_id) REFERENCES pricing_promotion (id)  ON DELETE CASCADE;
ALTER TABLE pricing_coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_coupon_id_pricing_coupon_1  FOREIGN KEY (coupon_id) REFERENCES pricing_coupon (id);
ALTER TABLE pricing_coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_party_id_party_party_2  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE pricing_coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_reservation_id_reser_20f2c00e  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE pricing_coupon_redemption ADD CONSTRAINT fk_pricing_coupon_redemption_quote_id_pricing_quote_4  FOREIGN KEY (quote_id) REFERENCES pricing_quote (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_customer_account_id_party_custom_f3509bd8  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_rate_plan_version_id_pricing_rat_1e59fe59  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_origin_branch_id_org_branch_4  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_destination_branch_id_org_branch_5  FOREIGN KEY (destination_branch_id) REFERENCES org_branch (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_vehicle_group_id_catalog_vehicle_group_6  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE pricing_quote ADD CONSTRAINT fk_pricing_quote_channel_id_org_channel_7 FOREIGN KEY (channel_id) REFERENCES org_channel (id);
ALTER TABLE pricing_quote_line ADD CONSTRAINT fk_pricing_quote_line_quote_id_pricing_quote_1  FOREIGN KEY (quote_id) REFERENCES pricing_quote (id) ON DELETE CASCADE;
ALTER TABLE pricing_quote_line ADD CONSTRAINT fk_pricing_quote_line_product_id_catalog_commerci_ee18710e  FOREIGN KEY (product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE pricing_quote_line ADD CONSTRAINT fk_pricing_quote_line_charge_type_id_catalog_charge_type_3  FOREIGN KEY (charge_type_id) REFERENCES catalog_charge_type (id);
ALTER TABLE pricing_quote_line ADD CONSTRAINT fk_pricing_quote_line_unit_code_catalog_unit_of_measure_4  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure (unit_code);
ALTER TABLE pricing_pricing_calculation ADD CONSTRAINT fk_pricing_pricing_calculation_quote_id_pricing_quote_1  FOREIGN KEY (quote_id) REFERENCES pricing_quote (id) ON DELETE CASCADE;
ALTER TABLE pricing_quote_rule_trace ADD CONSTRAINT fk_pricing_quote_rule_trace_pricing_calculation_i_664709e5  FOREIGN KEY (pricing_calculation_id) REFERENCES pricing_pricing_calculation (id) ON DELETE CASCADE;
ALTER TABLE corporate_rate_entitlement ADD CONSTRAINT fk_corporate_rate_entitlement_corporate_agreement_1b6fe465  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate_rate_entitlement ADD CONSTRAINT fk_corporate_rate_entitlement_rate_plan_id_pricin_443b648f  FOREIGN KEY (rate_plan_id) REFERENCES pricing_rate_plan (id);
ALTER TABLE corporate_rate_entitlement ADD CONSTRAINT fk_corporate_rate_entitlement_vehicle_group_id_ca_9961c6e2  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE corporate_purchase_order ADD CONSTRAINT fk_corporate_purchase_order_corporate_agreement_i_49590724  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id) ON DELETE CASCADE;
ALTER TABLE corporate_purchase_order ADD CONSTRAINT fk_corporate_purchase_order_cost_center_id_corpor_8869e641  FOREIGN KEY (cost_center_id) REFERENCES corporate_corporate_cost_center ( id);
ALTER TABLE corporate_voucher ADD CONSTRAINT fk_corporate_voucher_corporate_agreement_id_corpo_ee99af88  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement ( id);
ALTER TABLE corporate_voucher ADD CONSTRAINT fk_corporate_voucher_partner_agreement_id_corpora_d0bdacf7  FOREIGN KEY (partner_agreement_id) REFERENCES corporate_partner_agreement (id);
ALTER TABLE corporate_voucher ADD CONSTRAINT fk_corporate_voucher_authorized_party_id_party_party_3  FOREIGN KEY (authorized_party_id) REFERENCES party_party (id);
ALTER TABLE corporate_consolidated_billing_instruction  ADD CONSTRAINT fk_corporate_consolidated_billing_instruction_cor_d19eee78  FOREIGN KEY (corporate_billing_profile_id) REFERENCES corporate_corporate_billing_profile (id) ON DELETE CASCADE;
ALTER TABLE corporate_consolidated_billing_instruction  ADD CONSTRAINT fk_corporate_consolidated_billing_instruction_rec_fb4bcb7d  FOREIGN KEY (recipient_contact_id) REFERENCES party_contact_point (id);
ALTER TABLE availability_inventory_bucket ADD CONSTRAINT fk_availability_inventory_bucket_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_inventory_bucket ADD CONSTRAINT fk_availability_inventory_bucket_vehicle_group_id_7ef5caad  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE availability_availability_hold ADD CONSTRAINT fk_availability_availability_hold_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_availability_hold ADD CONSTRAINT fk_availability_availability_hold_vehicle_group_i_246a9284  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE availability_capacity_commitment ADD CONSTRAINT fk_availability_capacity_commitment_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_capacity_commitment ADD CONSTRAINT fk_availability_capacity_commitment_vehicle_group_ee08c37d  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group ( id);
ALTER TABLE availability_upgrade_path ADD CONSTRAINT fk_availability_upgrade_path_origin_branch_id_org_branch_1  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_upgrade_path ADD CONSTRAINT fk_availability_upgrade_path_from_group_id_catalo_7470f48f  FOREIGN KEY (from_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE availability_upgrade_path ADD CONSTRAINT fk_availability_upgrade_path_to_group_id_catalog__0b7eff92  FOREIGN KEY (to_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE availability_fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_partner_agreement_bfa6ad8b  FOREIGN KEY (partner_agreement_id) REFERENCES corporate_partner_agreement (id);
ALTER TABLE availability_fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_corporate_agreeme_6ceac69d  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id);
ALTER TABLE availability_fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_branch_id_org_branch_3  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_fleet_allotment ADD CONSTRAINT fk_availability_fleet_allotment_vehicle_group_id__cc05a8e4  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE availability_relocation_order ADD CONSTRAINT fk_availability_relocation_order_legal_entity_id__f05e7324  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE availability_relocation_order ADD CONSTRAINT fk_availability_relocation_order_origin_branch_id_e8b29d25  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_relocation_order ADD CONSTRAINT fk_availability_relocation_order_destination_bran_0b2fa5fe  FOREIGN KEY (destination_branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_relocation_leg ADD CONSTRAINT fk_availability_relocation_leg_relocation_order_i_001aa7c2  FOREIGN KEY (relocation_order_id) REFERENCES availability_relocation_order (id) ON DELETE CASCADE;
ALTER TABLE availability_relocation_leg ADD CONSTRAINT fk_availability_relocation_leg_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE availability_relocation_leg ADD CONSTRAINT fk_availability_relocation_leg_calendar_entry_id__c7a15dd3  FOREIGN KEY (calendar_entry_id) REFERENCES fleet_vehicle_calendar_entry (id);
ALTER TABLE availability_oversell_alert ADD CONSTRAINT fk_availability_oversell_alert_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_oversell_alert ADD CONSTRAINT fk_availability_oversell_alert_vehicle_group_id_c_8aa75740  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE availability_forecast_snapshot ADD CONSTRAINT fk_availability_forecast_snapshot_branch_id_org_branch_1  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE availability_forecast_snapshot ADD CONSTRAINT fk_availability_forecast_snapshot_vehicle_group_i_d8873a07  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_legal_entity_id_org_le_80967ca0  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_customer_account_id_pa_85377a7b  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_booker_party_id_party_party_3  FOREIGN KEY (booker_party_id) REFERENCES party_party (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_requested_vehicle_grou_7f83f461  FOREIGN KEY (requested_vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_pickup_branch_id_org_branch_5  FOREIGN KEY (pickup_branch_id) REFERENCES org_branch (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_planned_return_branch__7465987c  FOREIGN KEY (planned_return_branch_id) REFERENCES org_branch (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_channel_id_org_channel_7  FOREIGN KEY (channel_id) REFERENCES org_channel (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_rate_plan_version_id_p_83281045  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version ( id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_quote_id_pricing_quote_9  FOREIGN KEY (quote_id) REFERENCES pricing_quote (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_corporate_agreement_id_f244d17d  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_cost_center_id_corpora_b229e667  FOREIGN KEY (cost_center_id) REFERENCES corporate_corporate_cost_center ( id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_purchase_order_id_corp_bafb6cf8  FOREIGN KEY (purchase_order_id) REFERENCES corporate_purchase_order (id);
ALTER TABLE reservation_reservation ADD CONSTRAINT fk_reservation_reservation_voucher_id_corporate_voucher_13  FOREIGN KEY (voucher_id) REFERENCES corporate_voucher (id);
ALTER TABLE reservation_reservation_driver ADD CONSTRAINT fk_reservation_reservation_driver_reservation_id__9d862a68  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_reservation_driver ADD CONSTRAINT fk_reservation_reservation_driver_driver_profile__aa9ab200  FOREIGN KEY (driver_profile_id) REFERENCES party_driver_profile (id);
ALTER TABLE reservation_reservation_product ADD CONSTRAINT fk_reservation_reservation_product_reservation_id_ff90d098  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation ( id) ON DELETE CASCADE;
ALTER TABLE reservation_reservation_product ADD CONSTRAINT fk_reservation_reservation_product_product_id_cat_ed1f54e4  FOREIGN KEY (product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE reservation_reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_reservation_479bc52e  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_quote_line__9bf598d0  FOREIGN KEY (quote_line_id) REFERENCES pricing_quote_line (id);
ALTER TABLE reservation_reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_product_id__b3c5f731  FOREIGN KEY (product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE reservation_reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_charge_type_a99c8203  FOREIGN KEY (charge_type_id) REFERENCES catalog_charge_type (id);
ALTER TABLE reservation_reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_unit_code_c_80863c1a  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure ( unit_code);
ALTER TABLE reservation_reservation_price_line ADD CONSTRAINT fk_reservation_reservation_price_line_rate_plan_v_51b707de  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id);
ALTER TABLE reservation_reservation_status_history ADD CONSTRAINT fk_reservation_reservation_status_history_reserva_c9f5f2e5  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_reservation_change ADD CONSTRAINT fk_reservation_reservation_change_reservation_id__fa8da71c  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE reservation_reservation_change ADD CONSTRAINT fk_reservation_reservation_change_requested_by_pa_f41ad951  FOREIGN KEY (requested_by_party_id) REFERENCES party_party (id);
ALTER TABLE reservation_reservation_cancellation ADD CONSTRAINT fk_reservation_reservation_cancellation_reservati_7bd79379  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE reservation_reservation_cancellation ADD CONSTRAINT fk_reservation_reservation_cancellation_cancelled_b1cb1a2b  FOREIGN KEY (cancelled_by_party_id) REFERENCES party_party ( id);
ALTER TABLE reservation_no_show_assessment ADD CONSTRAINT fk_reservation_no_show_assessment_reservation_id__c6406c62  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE reservation_reservation_guarantee ADD CONSTRAINT fk_reservation_reservation_guarantee_reservation__83e20f6e  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_partner_booking ADD CONSTRAINT fk_reservation_partner_booking_reservation_id_res_0c525701  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_partner_booking ADD CONSTRAINT fk_reservation_partner_booking_partner_id_corpora_a50d252f  FOREIGN KEY (partner_id) REFERENCES corporate_partner (id);
ALTER TABLE reservation_partner_booking ADD CONSTRAINT fk_reservation_partner_booking_partner_agreement__7ffdcc6c  FOREIGN KEY (partner_agreement_id) REFERENCES corporate_partner_agreement (id);
ALTER TABLE reservation_digital_pickup_eligibility ADD CONSTRAINT fk_reservation_digital_pickup_eligibility_reserva_df67048b  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE reservation_reservation_note ADD CONSTRAINT fk_reservation_reservation_note_reservation_id_re_b501e158  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_reservation_inventory_commitment  ADD CONSTRAINT fk_reservation_reservation_inventory_commitment_r_c0963fa6  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id) ON DELETE CASCADE;
ALTER TABLE reservation_reservation_inventory_commitment  ADD CONSTRAINT fk_reservation_reservation_inventory_commitment_a_95efb863  FOREIGN KEY (availability_hold_id) REFERENCES availability_availability_hold (id);
ALTER TABLE reservation_reservation_inventory_commitment  ADD CONSTRAINT fk_reservation_reservation_inventory_commitment_c_1062bc76  FOREIGN KEY (capacity_commitment_id) REFERENCES availability_capacity_commitment (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_legal_entity_id_org_leg_4f830ed5  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_reservation_id_reservat_46ce6596  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_customer_account_id_par_1cd51e5d  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_origin_branch_id_org_branch_4  FOREIGN KEY (origin_branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_planned_return_branch_i_9a1d9ec0  FOREIGN KEY (planned_return_branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_actual_return_branch_id_5dfc8e3f  FOREIGN KEY (actual_return_branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_mileage_package_id_pric_698e03a6  FOREIGN KEY (mileage_package_id) REFERENCES pricing_mileage_package (id);
ALTER TABLE rental_rental_contract ADD CONSTRAINT fk_rental_rental_contract_created_channel_id_org_channel_8  FOREIGN KEY (created_channel_id) REFERENCES org_channel (id);
ALTER TABLE rental_contract_revision ADD CONSTRAINT fk_rental_contract_revision_contract_id_rental_re_e6aed74c  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id)  ON DELETE CASCADE;
ALTER TABLE rental_contract_revision ADD CONSTRAINT fk_rental_contract_revision_previous_revision_id__62ea74ca  FOREIGN KEY (previous_revision_id) REFERENCES rental_contract_revision ( id);
ALTER TABLE rental_contract_party_role ADD CONSTRAINT fk_rental_contract_party_role_contract_id_rental__2b7f26e9  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id)  ON DELETE CASCADE;
ALTER TABLE rental_contract_party_role ADD CONSTRAINT fk_rental_contract_party_role_party_id_party_party_2  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE rental_contract_product ADD CONSTRAINT fk_rental_contract_product_contract_id_rental_ren_a060c4cb  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id)  ON DELETE CASCADE;
ALTER TABLE rental_contract_product ADD CONSTRAINT fk_rental_contract_product_product_id_catalog_com_2ffbcdc7  FOREIGN KEY (product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_contract_i_433b5c59  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract ( id) ON DELETE CASCADE;
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_contract_r_6924bde9  FOREIGN KEY (contract_revision_id) REFERENCES rental_contract_revision (id) ON DELETE CASCADE;
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_reservatio_b09118f3  FOREIGN KEY (reservation_price_line_id) REFERENCES reservation_reservation_price_line (id);
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_product_id_e5d449c8  FOREIGN KEY (product_id) REFERENCES catalog_commercial_product (id);
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_charge_typ_513bc08a  FOREIGN KEY (charge_type_id) REFERENCES catalog_charge_type ( id);
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_unit_code__a675b815  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure ( unit_code);
ALTER TABLE rental_contract_price_snapshot_line ADD CONSTRAINT fk_rental_contract_price_snapshot_line_rate_plan__aa809a02  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id);
ALTER TABLE rental_vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_contract_id_rental_r_d95c1f9c  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id)  ON DELETE CASCADE;
ALTER TABLE rental_vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_calendar_entry_id_fl_76a81150  FOREIGN KEY (calendar_entry_id) REFERENCES fleet_vehicle_calendar_entry (id);
ALTER TABLE rental_vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_vehicle_id_fleet_vehicle_3  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE rental_vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_pickup_branch_id_org_branch_4  FOREIGN KEY (pickup_branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_planned_return_branc_8b855ab2  FOREIGN KEY (planned_return_branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_vehicle_assignment ADD CONSTRAINT fk_rental_vehicle_assignment_actual_return_branch_73d5a70a  FOREIGN KEY (actual_return_branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_pickup_event ADD CONSTRAINT fk_rental_pickup_event_contract_id_rental_rental__195a99ee  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_pickup_event ADD CONSTRAINT fk_rental_pickup_event_vehicle_assignment_id_rent_a7ee97f9  FOREIGN KEY (vehicle_assignment_id) REFERENCES rental_vehicle_assignment (id);
ALTER TABLE rental_pickup_event ADD CONSTRAINT fk_rental_pickup_event_branch_id_org_branch_3  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_pickup_event ADD CONSTRAINT fk_rental_pickup_event_odometer_reading_id_fleet__88210f28  FOREIGN KEY (odometer_reading_id) REFERENCES fleet_odometer_reading (id);
ALTER TABLE rental_pickup_event ADD CONSTRAINT fk_rental_pickup_event_fuel_reading_id_fleet_fuel_f5e98d7f  FOREIGN KEY (fuel_reading_id) REFERENCES fleet_fuel_reading (id);
ALTER TABLE rental_pickup_event ADD CONSTRAINT fk_rental_pickup_event_inspection_id_inspection_i_69d49857  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id);
ALTER TABLE rental_return_event ADD CONSTRAINT fk_rental_return_event_contract_id_rental_rental__f6920ef5  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_return_event ADD CONSTRAINT fk_rental_return_event_vehicle_assignment_id_rent_aa34499a  FOREIGN KEY (vehicle_assignment_id) REFERENCES rental_vehicle_assignment (id);
ALTER TABLE rental_return_event ADD CONSTRAINT fk_rental_return_event_branch_id_org_branch_3  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE rental_return_event ADD CONSTRAINT fk_rental_return_event_odometer_reading_id_fleet__eea06bd9  FOREIGN KEY (odometer_reading_id) REFERENCES fleet_odometer_reading (id);
ALTER TABLE rental_return_event ADD CONSTRAINT fk_rental_return_event_fuel_reading_id_fleet_fuel_8845a500  FOREIGN KEY (fuel_reading_id) REFERENCES fleet_fuel_reading (id);
ALTER TABLE rental_return_event ADD CONSTRAINT fk_rental_return_event_inspection_id_inspection_i_8a62d08c  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id);
ALTER TABLE rental_extension ADD CONSTRAINT fk_rental_extension_contract_id_rental_rental_contract_1  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_extension ADD CONSTRAINT fk_rental_extension_requested_by_party_id_party_party_2  FOREIGN KEY (requested_by_party_id) REFERENCES party_party (id);
ALTER TABLE rental_vehicle_replacement ADD CONSTRAINT fk_rental_vehicle_replacement_contract_id_rental__d46cc399  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_vehicle_replacement ADD CONSTRAINT fk_rental_vehicle_replacement_previous_assignment_4212fc10  FOREIGN KEY (previous_assignment_id) REFERENCES rental_vehicle_assignment (id);
ALTER TABLE rental_vehicle_replacement ADD CONSTRAINT fk_rental_vehicle_replacement_new_assignment_id_r_cc143ecc  FOREIGN KEY (new_assignment_id) REFERENCES rental_vehicle_assignment ( id);
ALTER TABLE rental_contract_status_history ADD CONSTRAINT fk_rental_contract_status_history_contract_id_ren_b7d30ae2  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id)  ON DELETE CASCADE;
ALTER TABLE rental_contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_contract_id_r_e1bd3927  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_contract_revi_38c909b2  FOREIGN KEY (contract_revision_id) REFERENCES rental_contract_revision (id);
ALTER TABLE rental_contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_party_id_party_party_3  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE rental_contract_terms_acceptance ADD CONSTRAINT fk_rental_contract_terms_acceptance_channel_id_or_c4886e88  FOREIGN KEY (channel_id) REFERENCES org_channel (id);
ALTER TABLE rental_contract_document ADD CONSTRAINT fk_rental_contract_document_contract_id_rental_re_43cb1a1a  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_contract_document ADD CONSTRAINT fk_rental_contract_document_contract_revision_id__028a9a2f  FOREIGN KEY (contract_revision_id) REFERENCES rental_contract_revision ( id);
ALTER TABLE rental_digital_pickup_session ADD CONSTRAINT fk_rental_digital_pickup_session_contract_id_rent_6042c3a6  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_digital_pickup_session ADD CONSTRAINT fk_rental_digital_pickup_session_reservation_id_r_62d0440f  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE rental_digital_pickup_session ADD CONSTRAINT fk_rental_digital_pickup_session_party_id_party_party_3  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE rental_vehicle_access_credential ADD CONSTRAINT fk_rental_vehicle_access_credential_digital_picku_46f920a7  FOREIGN KEY (digital_pickup_session_id) REFERENCES rental_digital_pickup_session (id) ON DELETE CASCADE;
ALTER TABLE rental_vehicle_access_credential ADD CONSTRAINT fk_rental_vehicle_access_credential_vehicle_id_fl_99bba7ba  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE rental_vehicle_access_command ADD CONSTRAINT fk_rental_vehicle_access_command_contract_id_rent_c6361125  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_vehicle_access_command ADD CONSTRAINT fk_rental_vehicle_access_command_vehicle_id_fleet_d6fb9a73  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE rental_overdue_case ADD CONSTRAINT fk_rental_overdue_case_contract_id_rental_rental__ae4039d0  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE rental_contract_reprocessing ADD CONSTRAINT fk_rental_contract_reprocessing_contract_id_renta_9b6f3d24  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_inspection_template_item ADD CONSTRAINT fk_inspection_inspection_template_item_inspection_4789f1b9  FOREIGN KEY (inspection_template_id) REFERENCES inspection_inspection_template (id) ON DELETE CASCADE;
ALTER TABLE inspection_inspection ADD CONSTRAINT fk_inspection_inspection_inspection_template_id_i_172a4ce8  FOREIGN KEY (inspection_template_id) REFERENCES inspection_inspection_template (id);
ALTER TABLE inspection_inspection ADD CONSTRAINT fk_inspection_inspection_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE inspection_inspection ADD CONSTRAINT fk_inspection_inspection_contract_id_rental_renta_0b054e85  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_inspection ADD CONSTRAINT fk_inspection_inspection_vehicle_assignment_id_re_7bace524  FOREIGN KEY (vehicle_assignment_id) REFERENCES rental_vehicle_assignment (id);
ALTER TABLE inspection_inspection ADD CONSTRAINT fk_inspection_inspection_branch_id_org_branch_5  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE inspection_inspection_item_result ADD CONSTRAINT fk_inspection_inspection_item_result_inspection_i_df07a250  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id) ON DELETE CASCADE;
ALTER TABLE inspection_inspection_item_result ADD CONSTRAINT fk_inspection_inspection_item_result_template_ite_30e0aa67  FOREIGN KEY (template_item_id) REFERENCES inspection_inspection_template_item (id);
ALTER TABLE inspection_inspection_media ADD CONSTRAINT fk_inspection_inspection_media_inspection_id_insp_4f1df40c  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id)  ON DELETE CASCADE;
ALTER TABLE inspection_inspection_media ADD CONSTRAINT fk_inspection_inspection_media_template_item_id_i_383e7e81  FOREIGN KEY (template_item_id) REFERENCES inspection_inspection_template_item (id);
ALTER TABLE inspection_damage_record ADD CONSTRAINT fk_inspection_damage_record_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE inspection_damage_observation ADD CONSTRAINT fk_inspection_damage_observation_damage_record_id_35f8b591  FOREIGN KEY (damage_record_id) REFERENCES inspection_damage_record ( id);
ALTER TABLE inspection_damage_observation ADD CONSTRAINT fk_inspection_damage_observation_inspection_id_in_b73d6c3e  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id);
ALTER TABLE inspection_damage_observation ADD CONSTRAINT fk_inspection_damage_observation_media_id_inspect_1467b661  FOREIGN KEY (media_id) REFERENCES inspection_inspection_media (id);
ALTER TABLE inspection_damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_damage_record_id_d0058bd5  FOREIGN KEY (damage_record_id) REFERENCES inspection_damage_record ( id);
ALTER TABLE inspection_damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_contract_id_rent_1385d531  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_incident_id_clai_51e7cae7  FOREIGN KEY (incident_id) REFERENCES claim_incident (id);
ALTER TABLE inspection_damage_attribution ADD CONSTRAINT fk_inspection_damage_attribution_responsible_part_e94686dd  FOREIGN KEY (responsible_party_id) REFERENCES party_party (id);
ALTER TABLE inspection_damage_assessment ADD CONSTRAINT fk_inspection_damage_assessment_damage_record_id__74e2d0dd  FOREIGN KEY (damage_record_id) REFERENCES inspection_damage_record ( id);
ALTER TABLE inspection_damage_assessment ADD CONSTRAINT fk_inspection_damage_assessment_contract_id_renta_b985876a  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_damage_assessment ADD CONSTRAINT fk_inspection_damage_assessment_assessor_party_id_12b10a8c  FOREIGN KEY (assessor_party_id) REFERENCES party_party (id);
ALTER TABLE inspection_fuel_assessment ADD CONSTRAINT fk_inspection_fuel_assessment_inspection_id_inspe_07b8dc0b  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id);
ALTER TABLE inspection_fuel_assessment ADD CONSTRAINT fk_inspection_fuel_assessment_contract_id_rental__c914b49c  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_fuel_assessment ADD CONSTRAINT fk_inspection_fuel_assessment_fuel_price_id_prici_004ccc7b  FOREIGN KEY (fuel_price_id) REFERENCES pricing_fuel_price (id);
ALTER TABLE inspection_cleaning_assessment ADD CONSTRAINT fk_inspection_cleaning_assessment_inspection_id_i_e93b9ede  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id);
ALTER TABLE inspection_cleaning_assessment ADD CONSTRAINT fk_inspection_cleaning_assessment_contract_id_ren_fa85d3a9  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_lost_found_item ADD CONSTRAINT fk_inspection_lost_found_item_inspection_id_inspe_b4209e8c  FOREIGN KEY (inspection_id) REFERENCES inspection_inspection (id);
ALTER TABLE inspection_lost_found_item ADD CONSTRAINT fk_inspection_lost_found_item_contract_id_rental__80aee175  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE inspection_lost_found_item ADD CONSTRAINT fk_inspection_lost_found_item_released_to_party_i_c84510ac  FOREIGN KEY (released_to_party_id) REFERENCES party_party (id);
ALTER TABLE billing_payment_method_token ADD CONSTRAINT fk_billing_payment_method_token_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE billing_payment_method_token ADD CONSTRAINT fk_billing_payment_method_token_billing_address_i_fce0e31e  FOREIGN KEY (billing_address_id) REFERENCES party_postal_address (id);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_contract_id_rental_rental_contract_2  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_reservation_id_reservation_reservation_3  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_charge_type_id_catalog_charge_type_4  FOREIGN KEY (charge_type_id) REFERENCES catalog_charge_type (id);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_unit_code_catalog_unit_of_measure_5  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure (unit_code);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_rate_plan_version_id_pricing_ra_9152308f  FOREIGN KEY (rate_plan_version_id) REFERENCES pricing_rate_plan_version (id);
ALTER TABLE billing_charge ADD CONSTRAINT fk_billing_charge_reversal_of_charge_id_billing_charge_7  FOREIGN KEY (reversal_of_charge_id) REFERENCES billing_charge (id);
ALTER TABLE billing_invoice ADD CONSTRAINT fk_billing_invoice_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE billing_invoice ADD CONSTRAINT fk_billing_invoice_customer_account_id_party_cust_c255ffac  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE billing_invoice ADD CONSTRAINT fk_billing_invoice_billing_party_id_party_party_3  FOREIGN KEY (billing_party_id) REFERENCES party_party (id);
ALTER TABLE billing_invoice ADD CONSTRAINT fk_billing_invoice_contract_id_rental_rental_contract_4  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE billing_invoice ADD CONSTRAINT fk_billing_invoice_corporate_agreement_id_corpora_51f3c93f  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id);
ALTER TABLE billing_invoice ADD CONSTRAINT fk_billing_invoice_supersedes_invoice_id_billing_invoice_6  FOREIGN KEY (supersedes_invoice_id) REFERENCES billing_invoice (id);
ALTER TABLE billing_invoice_line ADD CONSTRAINT fk_billing_invoice_line_invoice_id_billing_invoice_1  FOREIGN KEY (invoice_id) REFERENCES billing_invoice (id) ON DELETE CASCADE;
ALTER TABLE billing_invoice_line ADD CONSTRAINT fk_billing_invoice_line_charge_id_billing_charge_2  FOREIGN KEY (charge_id) REFERENCES billing_charge (id);
ALTER TABLE billing_receivable ADD CONSTRAINT fk_billing_receivable_invoice_id_billing_invoice_1  FOREIGN KEY (invoice_id) REFERENCES billing_invoice (id);
ALTER TABLE billing_payment_intent ADD CONSTRAINT fk_billing_payment_intent_legal_entity_id_org_leg_84e570ef  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE billing_payment_intent ADD CONSTRAINT fk_billing_payment_intent_party_id_party_party_2  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE billing_payment_intent ADD CONSTRAINT fk_billing_payment_intent_contract_id_rental_rent_94de4098  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE billing_payment_intent ADD CONSTRAINT fk_billing_payment_intent_reservation_id_reservat_ed029fdc  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE billing_payment_intent ADD CONSTRAINT fk_billing_payment_intent_receivable_id_billing_r_96e121cd  FOREIGN KEY (receivable_id) REFERENCES billing_receivable (id);
ALTER TABLE billing_payment_intent ADD CONSTRAINT fk_billing_payment_intent_payment_method_token_id_49b5bb17  FOREIGN KEY (payment_method_token_id) REFERENCES billing_payment_method_token (id);
ALTER TABLE billing_payment_transaction ADD CONSTRAINT fk_billing_payment_transaction_payment_intent_id__549db615  FOREIGN KEY (payment_intent_id) REFERENCES billing_payment_intent (id);
ALTER TABLE billing_payment_allocation ADD CONSTRAINT fk_billing_payment_allocation_payment_transaction_e966b684  FOREIGN KEY (payment_transaction_id) REFERENCES billing_payment_transaction (id);
ALTER TABLE billing_payment_allocation ADD CONSTRAINT fk_billing_payment_allocation_receivable_id_billi_424b9336  FOREIGN KEY (receivable_id) REFERENCES billing_receivable (id);
ALTER TABLE billing_payment_allocation ADD CONSTRAINT fk_billing_payment_allocation_reversal_of_allocat_ccb7ea16  FOREIGN KEY (reversal_of_allocation_id) REFERENCES billing_payment_allocation (id);
ALTER TABLE billing_preauthorization ADD CONSTRAINT fk_billing_preauthorization_payment_method_token__f4b79f0d  FOREIGN KEY (payment_method_token_id) REFERENCES billing_payment_method_token (id);
ALTER TABLE billing_preauthorization ADD CONSTRAINT fk_billing_preauthorization_reservation_id_reserv_dfa5eef9  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE billing_preauthorization ADD CONSTRAINT fk_billing_preauthorization_contract_id_rental_re_b9dbdc6b  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE billing_refund ADD CONSTRAINT fk_billing_refund_payment_transaction_id_billing__ab3a86a0  FOREIGN KEY (payment_transaction_id) REFERENCES billing_payment_transaction (id);
ALTER TABLE billing_refund ADD CONSTRAINT fk_billing_refund_refund_transaction_id_billing_p_fed5ce2f  FOREIGN KEY (refund_transaction_id) REFERENCES billing_payment_transaction (id);
ALTER TABLE billing_credit_note ADD CONSTRAINT fk_billing_credit_note_invoice_id_billing_invoice_1  FOREIGN KEY (invoice_id) REFERENCES billing_invoice (id);
ALTER TABLE billing_credit_note ADD CONSTRAINT fk_billing_credit_note_tax_document_id_billing_ta_e623e1ff  FOREIGN KEY (tax_document_id) REFERENCES billing_tax_document (id);
ALTER TABLE billing_chargeback ADD CONSTRAINT fk_billing_chargeback_payment_transaction_id_bill_617288cb  FOREIGN KEY (payment_transaction_id) REFERENCES billing_payment_transaction (id);
ALTER TABLE billing_tax_document ADD CONSTRAINT fk_billing_tax_document_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE billing_tax_document ADD CONSTRAINT fk_billing_tax_document_invoice_id_billing_invoice_2  FOREIGN KEY (invoice_id) REFERENCES billing_invoice (id);
ALTER TABLE billing_dunning_case ADD CONSTRAINT fk_billing_dunning_case_customer_account_id_party_1ee48f6c  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE billing_dunning_case ADD CONSTRAINT fk_billing_dunning_case_receivable_id_billing_receivable_2  FOREIGN KEY (receivable_id) REFERENCES billing_receivable (id);
ALTER TABLE billing_collection_action ADD CONSTRAINT fk_billing_collection_action_dunning_case_id_bill_29a97fd7  FOREIGN KEY (dunning_case_id) REFERENCES billing_dunning_case (id)  ON DELETE CASCADE;
ALTER TABLE billing_settlement_item ADD CONSTRAINT fk_billing_settlement_item_settlement_batch_id_bi_8acdd183  FOREIGN KEY (settlement_batch_id) REFERENCES billing_settlement_batch (id) ON DELETE CASCADE;
ALTER TABLE billing_settlement_item ADD CONSTRAINT fk_billing_settlement_item_payment_transaction_id_179e8096  FOREIGN KEY (payment_transaction_id) REFERENCES billing_payment_transaction (id);
ALTER TABLE billing_reconciliation_issue ADD CONSTRAINT fk_billing_reconciliation_issue_settlement_item_i_89e1c65e  FOREIGN KEY (settlement_item_id) REFERENCES billing_settlement_item ( id);
ALTER TABLE billing_accounting_export ADD CONSTRAINT fk_billing_accounting_export_legal_entity_id_org__8aef407b  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE traffic_traffic_notice ADD CONSTRAINT fk_traffic_traffic_notice_import_batch_id_traffic_a726f841  FOREIGN KEY (import_batch_id) REFERENCES traffic_provider_import_batch (id);
ALTER TABLE traffic_traffic_notice ADD CONSTRAINT fk_traffic_traffic_notice_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE traffic_traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_traffic_notice_id__782e6e40  FOREIGN KEY (traffic_notice_id) REFERENCES traffic_traffic_notice (id);
ALTER TABLE traffic_traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_contract_id_rental_bebc0978  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE traffic_traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_vehicle_assignment_8896b457  FOREIGN KEY (vehicle_assignment_id) REFERENCES rental_vehicle_assignment (id);
ALTER TABLE traffic_traffic_attribution ADD CONSTRAINT fk_traffic_traffic_attribution_driver_profile_id__9fd23c6a  FOREIGN KEY (driver_profile_id) REFERENCES party_driver_profile (id);
ALTER TABLE traffic_driver_nomination ADD CONSTRAINT fk_traffic_driver_nomination_traffic_notice_id_tr_c246b814  FOREIGN KEY (traffic_notice_id) REFERENCES traffic_traffic_notice (id);
ALTER TABLE traffic_driver_nomination ADD CONSTRAINT fk_traffic_driver_nomination_driver_profile_id_pa_8c032902  FOREIGN KEY (driver_profile_id) REFERENCES party_driver_profile (id);
ALTER TABLE traffic_traffic_appeal ADD CONSTRAINT fk_traffic_traffic_appeal_traffic_notice_id_traff_95bfe0ab  FOREIGN KEY (traffic_notice_id) REFERENCES traffic_traffic_notice (id);
ALTER TABLE traffic_toll_tag ADD CONSTRAINT fk_traffic_toll_tag_owning_legal_entity_id_org_le_3e9b62ec  FOREIGN KEY (owning_legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE traffic_toll_tag_assignment ADD CONSTRAINT fk_traffic_toll_tag_assignment_toll_tag_id_traffi_a47fea74  FOREIGN KEY (toll_tag_id) REFERENCES traffic_toll_tag (id);
ALTER TABLE traffic_toll_tag_assignment ADD CONSTRAINT fk_traffic_toll_tag_assignment_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE traffic_toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_import_batch_id_traff_a8f71b6b  FOREIGN KEY (import_batch_id) REFERENCES traffic_provider_import_batch ( id);
ALTER TABLE traffic_toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_toll_tag_id_traffic_toll_tag_2  FOREIGN KEY (toll_tag_id) REFERENCES traffic_toll_tag (id);
ALTER TABLE traffic_toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_vehicle_id_fleet_vehicle_3  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE traffic_toll_transaction ADD CONSTRAINT fk_traffic_toll_transaction_contract_id_rental_re_3e506932  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE traffic_parking_transaction ADD CONSTRAINT fk_traffic_parking_transaction_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE traffic_parking_transaction ADD CONSTRAINT fk_traffic_parking_transaction_contract_id_rental_394386e9  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE traffic_traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_traffic_notice_id__fe7dacda  FOREIGN KEY (traffic_notice_id) REFERENCES traffic_traffic_notice (id);
ALTER TABLE traffic_traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_toll_transaction_i_fa1b5a73  FOREIGN KEY (toll_transaction_id) REFERENCES traffic_toll_transaction (id);
ALTER TABLE traffic_traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_parking_transactio_53fd31f9  FOREIGN KEY (parking_transaction_id) REFERENCES traffic_parking_transaction (id);
ALTER TABLE traffic_traffic_charge_link ADD CONSTRAINT fk_traffic_traffic_charge_link_charge_id_billing_charge_4  FOREIGN KEY (charge_id) REFERENCES billing_charge (id);
ALTER TABLE claim_insurance_policy ADD CONSTRAINT fk_claim_insurance_policy_legal_entity_id_org_leg_b729ad96  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE claim_insurance_policy ADD CONSTRAINT fk_claim_insurance_policy_insurer_party_id_party__e07c11cb  FOREIGN KEY (insurer_party_id) REFERENCES party_organization (party_id);
ALTER TABLE claim_policy_coverage ADD CONSTRAINT fk_claim_policy_coverage_insurance_policy_id_clai_f2a0e554  FOREIGN KEY (insurance_policy_id) REFERENCES claim_insurance_policy (id)  ON DELETE CASCADE;
ALTER TABLE claim_policy_coverage ADD CONSTRAINT fk_claim_policy_coverage_coverage_id_catalog_coverage_2  FOREIGN KEY (coverage_id) REFERENCES catalog_coverage (id);
ALTER TABLE claim_incident ADD CONSTRAINT fk_claim_incident_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE claim_incident ADD CONSTRAINT fk_claim_incident_contract_id_rental_rental_contract_2  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE claim_incident_party ADD CONSTRAINT fk_claim_incident_party_incident_id_claim_incident_1  FOREIGN KEY (incident_id) REFERENCES claim_incident (id) ON DELETE CASCADE;
ALTER TABLE claim_incident_party ADD CONSTRAINT fk_claim_incident_party_party_id_party_party_2  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE claim_incident_vehicle ADD CONSTRAINT fk_claim_incident_vehicle_incident_id_claim_incident_1  FOREIGN KEY (incident_id) REFERENCES claim_incident (id) ON DELETE CASCADE;
ALTER TABLE claim_incident_vehicle ADD CONSTRAINT fk_claim_incident_vehicle_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE claim_incident_document ADD CONSTRAINT fk_claim_incident_document_incident_id_claim_incident_1  FOREIGN KEY (incident_id) REFERENCES claim_incident (id) ON DELETE CASCADE;
ALTER TABLE claim_claim ADD CONSTRAINT fk_claim_claim_incident_id_claim_incident_1  FOREIGN KEY (incident_id) REFERENCES claim_incident (id);
ALTER TABLE claim_claim ADD CONSTRAINT fk_claim_claim_insurance_policy_id_claim_insuranc_4c9269f4  FOREIGN KEY (insurance_policy_id) REFERENCES claim_insurance_policy (id);
ALTER TABLE claim_claim ADD CONSTRAINT fk_claim_claim_contract_id_rental_rental_contract_3  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE claim_claim_coverage_decision ADD CONSTRAINT fk_claim_claim_coverage_decision_claim_id_claim_claim_1  FOREIGN KEY (claim_id) REFERENCES claim_claim (id) ON DELETE CASCADE;
ALTER TABLE claim_claim_coverage_decision ADD CONSTRAINT fk_claim_claim_coverage_decision_coverage_id_cata_70121be9  FOREIGN KEY (coverage_id) REFERENCES catalog_coverage (id);
ALTER TABLE claim_claim_cost ADD CONSTRAINT fk_claim_claim_cost_claim_id_claim_claim_1  FOREIGN KEY (claim_id) REFERENCES claim_claim (id) ON DELETE CASCADE;
ALTER TABLE claim_claim_cost ADD CONSTRAINT fk_claim_claim_cost_supplier_party_id_party_organization_2  FOREIGN KEY (supplier_party_id) REFERENCES party_organization (party_id);
ALTER TABLE claim_third_party_claim ADD CONSTRAINT fk_claim_third_party_claim_claim_id_claim_claim_1  FOREIGN KEY (claim_id) REFERENCES claim_claim (id);
ALTER TABLE claim_third_party_claim ADD CONSTRAINT fk_claim_third_party_claim_third_party_id_party_party_2  FOREIGN KEY (third_party_id) REFERENCES party_party (id);
ALTER TABLE claim_recovery_case ADD CONSTRAINT fk_claim_recovery_case_claim_id_claim_claim_1  FOREIGN KEY (claim_id) REFERENCES claim_claim (id);
ALTER TABLE claim_recovery_case ADD CONSTRAINT fk_claim_recovery_case_responsible_party_id_party_party_2  FOREIGN KEY (responsible_party_id) REFERENCES party_party (id);
ALTER TABLE claim_roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_incident_id_cla_b8bf19f7  FOREIGN KEY (incident_id) REFERENCES claim_incident (id);
ALTER TABLE claim_roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_contract_id_ren_391d5ed1  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE claim_roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_vehicle_id_flee_cce0f0dd  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE claim_roadside_assistance_case ADD CONSTRAINT fk_claim_roadside_assistance_case_provider_party__8ec2f39c  FOREIGN KEY (provider_party_id) REFERENCES party_organization ( party_id);
ALTER TABLE maintenance_maintenance_plan ADD CONSTRAINT fk_maintenance_maintenance_plan_vehicle_variant_i_47d12681  FOREIGN KEY (vehicle_variant_id) REFERENCES catalog_vehicle_variant ( id);
ALTER TABLE maintenance_maintenance_rule ADD CONSTRAINT fk_maintenance_maintenance_rule_maintenance_plan__24974bfd  FOREIGN KEY (maintenance_plan_id) REFERENCES maintenance_maintenance_plan (id) ON DELETE CASCADE;
ALTER TABLE maintenance_maintenance_due ADD CONSTRAINT fk_maintenance_maintenance_due_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE maintenance_maintenance_due ADD CONSTRAINT fk_maintenance_maintenance_due_maintenance_rule_i_b6eb59c7  FOREIGN KEY (maintenance_rule_id) REFERENCES maintenance_maintenance_rule (id);
ALTER TABLE maintenance_maintenance_due ADD CONSTRAINT fk_maintenance_maintenance_due_service_order_id_m_e2bdd15e  FOREIGN KEY (service_order_id) REFERENCES maintenance_service_order ( id);
ALTER TABLE maintenance_vendor ADD CONSTRAINT fk_maintenance_vendor_party_id_party_organization_1  FOREIGN KEY (party_id) REFERENCES party_organization (party_id);
ALTER TABLE maintenance_workshop ADD CONSTRAINT fk_maintenance_workshop_vendor_id_maintenance_vendor_1  FOREIGN KEY (vendor_id) REFERENCES maintenance_vendor (id);
ALTER TABLE maintenance_workshop ADD CONSTRAINT fk_maintenance_workshop_branch_id_org_branch_2  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE maintenance_workshop ADD CONSTRAINT fk_maintenance_workshop_address_id_party_postal_address_3  FOREIGN KEY (address_id) REFERENCES party_postal_address (id);
ALTER TABLE maintenance_service_order ADD CONSTRAINT fk_maintenance_service_order_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE maintenance_service_order ADD CONSTRAINT fk_maintenance_service_order_workshop_id_maintena_9e44837d  FOREIGN KEY (workshop_id) REFERENCES maintenance_workshop (id);
ALTER TABLE maintenance_service_order ADD CONSTRAINT fk_maintenance_service_order_calendar_entry_id_fl_636430da  FOREIGN KEY (calendar_entry_id) REFERENCES fleet_vehicle_calendar_entry (id);
ALTER TABLE maintenance_service_order_item ADD CONSTRAINT fk_maintenance_service_order_item_service_order_i_e353e5ea  FOREIGN KEY (service_order_id) REFERENCES maintenance_service_order (id) ON DELETE CASCADE;
ALTER TABLE maintenance_part ADD CONSTRAINT fk_maintenance_part_unit_code_catalog_unit_of_measure_1  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure (unit_code);
ALTER TABLE maintenance_service_order_part ADD CONSTRAINT fk_maintenance_service_order_part_service_order_i_f2949983  FOREIGN KEY (service_order_item_id) REFERENCES maintenance_service_order_item (id) ON DELETE CASCADE;
ALTER TABLE maintenance_service_order_part ADD CONSTRAINT fk_maintenance_service_order_part_part_id_mainten_d32bf07d  FOREIGN KEY (part_id) REFERENCES maintenance_part (id);
ALTER TABLE maintenance_vehicle_recall ADD CONSTRAINT fk_maintenance_vehicle_recall_recall_campaign_id__add3886a  FOREIGN KEY (recall_campaign_id) REFERENCES maintenance_recall_campaign (id);
ALTER TABLE maintenance_vehicle_recall ADD CONSTRAINT fk_maintenance_vehicle_recall_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE maintenance_vehicle_recall ADD CONSTRAINT fk_maintenance_vehicle_recall_service_order_id_ma_61066ba2  FOREIGN KEY (service_order_id) REFERENCES maintenance_service_order (id);
ALTER TABLE maintenance_tire_assignment ADD CONSTRAINT fk_maintenance_tire_assignment_tire_id_maintenance_tire_1  FOREIGN KEY (tire_id) REFERENCES maintenance_tire (id);
ALTER TABLE maintenance_tire_assignment ADD CONSTRAINT fk_maintenance_tire_assignment_vehicle_id_fleet_vehicle_2  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE maintenance_downtime ADD CONSTRAINT fk_maintenance_downtime_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE maintenance_downtime ADD CONSTRAINT fk_maintenance_downtime_service_order_id_maintena_89dc7a01  FOREIGN KEY (service_order_id) REFERENCES maintenance_service_order (id);
ALTER TABLE maintenance_downtime ADD CONSTRAINT fk_maintenance_downtime_calendar_entry_id_fleet_v_dd9edc03  FOREIGN KEY (calendar_entry_id) REFERENCES fleet_vehicle_calendar_entry (id);
ALTER TABLE telematics_device ADD CONSTRAINT fk_telematics_device_provider_id_telematics_provider_1  FOREIGN KEY (provider_id) REFERENCES telematics_provider (id);
ALTER TABLE telematics_vehicle_device_assignment ADD CONSTRAINT fk_telematics_vehicle_device_assignment_device_id_ce15a595  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_vehicle_device_assignment ADD CONSTRAINT fk_telematics_vehicle_device_assignment_vehicle_i_306d67ea  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE telematics_device_health_event ADD CONSTRAINT fk_telematics_device_health_event_device_id_telem_8e6cc4aa  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_telemetry_event_index ADD CONSTRAINT fk_telematics_telemetry_event_index_device_id_tel_3df1e8c3  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_telemetry_event_index ADD CONSTRAINT fk_telematics_telemetry_event_index_vehicle_id_fl_e10ed6b1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE telematics_trip_summary ADD CONSTRAINT fk_telematics_trip_summary_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE telematics_trip_summary ADD CONSTRAINT fk_telematics_trip_summary_device_id_telematics_device_2  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_trip_summary ADD CONSTRAINT fk_telematics_trip_summary_contract_id_rental_ren_55c02804  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE telematics_driving_event ADD CONSTRAINT fk_telematics_driving_event_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE telematics_driving_event ADD CONSTRAINT fk_telematics_driving_event_device_id_telematics_device_2  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_driving_event ADD CONSTRAINT fk_telematics_driving_event_contract_id_rental_re_352e0bc4  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE telematics_driving_event ADD CONSTRAINT fk_telematics_driving_event_trip_summary_id_telem_edc7cc20  FOREIGN KEY (trip_summary_id) REFERENCES telematics_trip_summary (id);
ALTER TABLE telematics_geofence_event ADD CONSTRAINT fk_telematics_geofence_event_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE telematics_geofence_event ADD CONSTRAINT fk_telematics_geofence_event_device_id_telematics_device_2  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_geofence_event ADD CONSTRAINT fk_telematics_geofence_event_geofence_id_telemati_09f4a4a4  FOREIGN KEY (geofence_id) REFERENCES telematics_geofence (id);
ALTER TABLE telematics_geofence_event ADD CONSTRAINT fk_telematics_geofence_event_contract_id_rental_r_831b6d1a  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE telematics_vehicle_command ADD CONSTRAINT fk_telematics_vehicle_command_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE telematics_vehicle_command ADD CONSTRAINT fk_telematics_vehicle_command_device_id_telematic_553167d6  FOREIGN KEY (device_id) REFERENCES telematics_device (id);
ALTER TABLE telematics_vehicle_command ADD CONSTRAINT fk_telematics_vehicle_command_contract_id_rental__9d1e4164  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE telematics_command_result ADD CONSTRAINT fk_telematics_command_result_vehicle_command_id_t_12fde95b  FOREIGN KEY (vehicle_command_id) REFERENCES telematics_vehicle_command ( id) ON DELETE CASCADE;
ALTER TABLE loyalty_loyalty_account ADD CONSTRAINT fk_loyalty_loyalty_account_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE loyalty_loyalty_account ADD CONSTRAINT fk_loyalty_loyalty_account_current_tier_id_loyalt_fc0c485d  FOREIGN KEY (current_tier_id) REFERENCES loyalty_loyalty_tier (id);
ALTER TABLE loyalty_tier_rule_version ADD CONSTRAINT fk_loyalty_tier_rule_version_loyalty_tier_id_loya_6e5f4229  FOREIGN KEY (loyalty_tier_id) REFERENCES loyalty_loyalty_tier (id)  ON DELETE CASCADE;
ALTER TABLE loyalty_tier_history ADD CONSTRAINT fk_loyalty_tier_history_loyalty_account_id_loyalt_31dc7dd5  FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_loyalty_account (id)  ON DELETE CASCADE;
ALTER TABLE loyalty_tier_history ADD CONSTRAINT fk_loyalty_tier_history_loyalty_tier_id_loyalty_l_ac4642b9  FOREIGN KEY (loyalty_tier_id) REFERENCES loyalty_loyalty_tier (id);
ALTER TABLE loyalty_tier_history ADD CONSTRAINT fk_loyalty_tier_history_rule_version_id_loyalty_t_92fb18ca  FOREIGN KEY (rule_version_id) REFERENCES loyalty_tier_rule_version (id);
ALTER TABLE loyalty_points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_loyalty_account_id_loyal_75638ffa  FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_loyalty_account (id);
ALTER TABLE loyalty_points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_earning_rule_id_loyalty__0e0ef5fe  FOREIGN KEY (earning_rule_id) REFERENCES loyalty_earning_rule (id);
ALTER TABLE loyalty_points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_redemption_rule_id_loyal_430eb7e4  FOREIGN KEY (redemption_rule_id) REFERENCES loyalty_redemption_rule (id);
ALTER TABLE loyalty_points_ledger ADD CONSTRAINT fk_loyalty_points_ledger_reversal_of_entry_id_loy_0187f35d  FOREIGN KEY (reversal_of_entry_id) REFERENCES loyalty_points_ledger (id);
ALTER TABLE loyalty_points_lot ADD CONSTRAINT fk_loyalty_points_lot_loyalty_account_id_loyalty__2a81d62d  FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_loyalty_account (id);
ALTER TABLE loyalty_points_lot ADD CONSTRAINT fk_loyalty_points_lot_origin_ledger_entry_id_loya_b3419dde  FOREIGN KEY (origin_ledger_entry_id) REFERENCES loyalty_points_ledger (id);
ALTER TABLE loyalty_redemption ADD CONSTRAINT fk_loyalty_redemption_loyalty_account_id_loyalty__12ce29ca  FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_loyalty_account (id);
ALTER TABLE loyalty_redemption ADD CONSTRAINT fk_loyalty_redemption_reservation_id_reservation__1a2b8fbe  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE loyalty_redemption ADD CONSTRAINT fk_loyalty_redemption_contract_id_rental_rental_contract_3  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE loyalty_redemption_allocation ADD CONSTRAINT fk_loyalty_redemption_allocation_redemption_id_lo_b939e147  FOREIGN KEY (redemption_id) REFERENCES loyalty_redemption (id)  ON DELETE CASCADE;
ALTER TABLE loyalty_redemption_allocation ADD CONSTRAINT fk_loyalty_redemption_allocation_points_lot_id_lo_ca77ab36  FOREIGN KEY (points_lot_id) REFERENCES loyalty_points_lot (id);
ALTER TABLE loyalty_benefit_entitlement ADD CONSTRAINT fk_loyalty_benefit_entitlement_loyalty_account_id_19c9ed67  FOREIGN KEY (loyalty_account_id) REFERENCES loyalty_loyalty_account ( id);
ALTER TABLE loyalty_benefit_entitlement ADD CONSTRAINT fk_loyalty_benefit_entitlement_benefit_id_loyalty_63e3163a  FOREIGN KEY (benefit_id) REFERENCES loyalty_benefit (id);
ALTER TABLE loyalty_benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_benefit_entitlement_id_l_473b2eb8  FOREIGN KEY (benefit_entitlement_id) REFERENCES loyalty_benefit_entitlement (id);
ALTER TABLE loyalty_benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_reservation_id_reservati_ea12cae2  FOREIGN KEY (reservation_id) REFERENCES reservation_reservation (id);
ALTER TABLE loyalty_benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_contract_id_rental_renta_c45f74fd  FOREIGN KEY (contract_id) REFERENCES rental_rental_contract (id);
ALTER TABLE loyalty_benefit_usage ADD CONSTRAINT fk_loyalty_benefit_usage_reversal_of_usage_id_loy_161c2c87  FOREIGN KEY (reversal_of_usage_id) REFERENCES loyalty_benefit_usage (id);
ALTER TABLE loyalty_points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_from_account_id_loyalt_36d9a91a  FOREIGN KEY (from_account_id) REFERENCES loyalty_loyalty_account (id);
ALTER TABLE loyalty_points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_to_account_id_loyalty__08fd9e1c  FOREIGN KEY (to_account_id) REFERENCES loyalty_loyalty_account (id);
ALTER TABLE loyalty_points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_out_ledger_entry_id_lo_6f1855ad  FOREIGN KEY (out_ledger_entry_id) REFERENCES loyalty_points_ledger (id);
ALTER TABLE loyalty_points_transfer ADD CONSTRAINT fk_loyalty_points_transfer_in_ledger_entry_id_loy_f12f28fa  FOREIGN KEY (in_ledger_entry_id) REFERENCES loyalty_points_ledger (id);
ALTER TABLE fleet_mgmt_fleet_service_contract ADD CONSTRAINT fk_fleet_mgmt_fleet_service_contract_legal_entity_0449c228  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE fleet_mgmt_fleet_service_contract ADD CONSTRAINT fk_fleet_mgmt_fleet_service_contract_customer_acc_6cd72fad  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE fleet_mgmt_fleet_service_contract ADD CONSTRAINT fk_fleet_mgmt_fleet_service_contract_corporate_ag_62ad139e  FOREIGN KEY (corporate_agreement_id) REFERENCES corporate_corporate_agreement (id);
ALTER TABLE fleet_mgmt_fleet_service_level ADD CONSTRAINT fk_fleet_mgmt_fleet_service_level_fleet_service_c_0b1cf43a  FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt_fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt_fleet_service_level ADD CONSTRAINT fk_fleet_mgmt_fleet_service_level_unit_code_catal_ecc953d1  FOREIGN KEY (unit_code) REFERENCES catalog_unit_of_measure ( unit_code);
ALTER TABLE fleet_mgmt_managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_fleet_se_78391358  FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt_fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt_managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_vehicle__ca7d7e43  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_mgmt_managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_assigned_4783c88b  FOREIGN KEY (assigned_driver_profile_id) REFERENCES party_driver_profile (id);
ALTER TABLE fleet_mgmt_managed_vehicle_assignment ADD CONSTRAINT fk_fleet_mgmt_managed_vehicle_assignment_cost_cen_e312d0a4  FOREIGN KEY (cost_center_id) REFERENCES corporate_corporate_cost_center (id);
ALTER TABLE fleet_mgmt_mileage_commitment ADD CONSTRAINT fk_fleet_mgmt_mileage_commitment_fleet_service_co_68e442e1  FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt_fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt_mileage_commitment ADD CONSTRAINT fk_fleet_mgmt_mileage_commitment_vehicle_id_fleet_66ce1962  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_mgmt_telemetry_package ADD CONSTRAINT fk_fleet_mgmt_telemetry_package_fleet_service_con_f3f1712e  FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt_fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt_replacement_entitlement ADD CONSTRAINT fk_fleet_mgmt_replacement_entitlement_fleet_servi_8f99ffc4  FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt_fleet_service_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt_replacement_entitlement ADD CONSTRAINT fk_fleet_mgmt_replacement_entitlement_vehicle_gro_bcba57c9  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE fleet_mgmt_fleet_service_event ADD CONSTRAINT fk_fleet_mgmt_fleet_service_event_fleet_service_c_3b809512  FOREIGN KEY (fleet_service_contract_id) REFERENCES fleet_mgmt_fleet_service_contract (id);
ALTER TABLE fleet_mgmt_fleet_service_event ADD CONSTRAINT fk_fleet_mgmt_fleet_service_event_vehicle_id_flee_72acf7be  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_mgmt_subscription_plan ADD CONSTRAINT fk_fleet_mgmt_subscription_plan_vehicle_group_id__7c4c492d  FOREIGN KEY (vehicle_group_id) REFERENCES catalog_vehicle_group (id);
ALTER TABLE fleet_mgmt_subscription_contract ADD CONSTRAINT fk_fleet_mgmt_subscription_contract_subscription__8a13a360  FOREIGN KEY (subscription_plan_id) REFERENCES fleet_mgmt_subscription_plan (id);
ALTER TABLE fleet_mgmt_subscription_contract ADD CONSTRAINT fk_fleet_mgmt_subscription_contract_customer_acco_ad7cb737  FOREIGN KEY (customer_account_id) REFERENCES party_customer_account (id);
ALTER TABLE fleet_mgmt_subscription_contract ADD CONSTRAINT fk_fleet_mgmt_subscription_contract_legal_entity__27036bbf  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE fleet_mgmt_subscription_vehicle_assignment  ADD CONSTRAINT fk_fleet_mgmt_subscription_vehicle_assignment_sub_de7ead13  FOREIGN KEY (subscription_contract_id) REFERENCES fleet_mgmt_subscription_contract (id) ON DELETE CASCADE;
ALTER TABLE fleet_mgmt_subscription_vehicle_assignment  ADD CONSTRAINT fk_fleet_mgmt_subscription_vehicle_assignment_veh_f9be83d1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE fleet_mgmt_subscription_vehicle_assignment  ADD CONSTRAINT fk_fleet_mgmt_subscription_vehicle_assignment_cal_a88faa6f  FOREIGN KEY (calendar_entry_id) REFERENCES fleet_vehicle_calendar_entry (id);
ALTER TABLE used_car_disposal_candidate ADD CONSTRAINT fk_used_car_disposal_candidate_vehicle_id_fleet_vehicle_1  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE used_car_vehicle_valuation ADD CONSTRAINT fk_used_car_vehicle_valuation_disposal_candidate__16ac4ac3  FOREIGN KEY (disposal_candidate_id) REFERENCES used_car_disposal_candidate (id) ON DELETE CASCADE;
ALTER TABLE used_car_refurbishment_order ADD CONSTRAINT fk_used_car_refurbishment_order_disposal_candidat_a898cea0  FOREIGN KEY (disposal_candidate_id) REFERENCES used_car_disposal_candidate (id);
ALTER TABLE used_car_refurbishment_order ADD CONSTRAINT fk_used_car_refurbishment_order_service_order_id__5174b827  FOREIGN KEY (service_order_id) REFERENCES maintenance_service_order ( id);
ALTER TABLE used_car_refurbishment_item ADD CONSTRAINT fk_used_car_refurbishment_item_refurbishment_orde_47a9659e  FOREIGN KEY (refurbishment_order_id) REFERENCES used_car_refurbishment_order (id) ON DELETE CASCADE;
ALTER TABLE used_car_listing ADD CONSTRAINT fk_used_car_listing_disposal_candidate_id_used_ca_ff83f2ed  FOREIGN KEY (disposal_candidate_id) REFERENCES used_car_disposal_candidate (id);
ALTER TABLE used_car_listing ADD CONSTRAINT fk_used_car_listing_sale_channel_id_used_car_sale_5ba1c5f2  FOREIGN KEY (sale_channel_id) REFERENCES used_car_sale_channel (id);
ALTER TABLE used_car_lead ADD CONSTRAINT fk_used_car_lead_listing_id_used_car_listing_1  FOREIGN KEY (listing_id) REFERENCES used_car_listing (id);
ALTER TABLE used_car_lead ADD CONSTRAINT fk_used_car_lead_party_id_party_party_2 FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE used_car_test_drive ADD CONSTRAINT fk_used_car_test_drive_lead_id_used_car_lead_1  FOREIGN KEY (lead_id) REFERENCES used_car_lead (id);
ALTER TABLE used_car_test_drive ADD CONSTRAINT fk_used_car_test_drive_listing_id_used_car_listing_2  FOREIGN KEY (listing_id) REFERENCES used_car_listing (id);
ALTER TABLE used_car_test_drive ADD CONSTRAINT fk_used_car_test_drive_driver_profile_id_party_dr_cfd433ad  FOREIGN KEY (driver_profile_id) REFERENCES party_driver_profile (id);
ALTER TABLE used_car_sale_order ADD CONSTRAINT fk_used_car_sale_order_legal_entity_id_org_legal_entity_1  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE used_car_sale_order ADD CONSTRAINT fk_used_car_sale_order_buyer_party_id_party_party_2  FOREIGN KEY (buyer_party_id) REFERENCES party_party (id);
ALTER TABLE used_car_sale_order ADD CONSTRAINT fk_used_car_sale_order_sale_channel_id_used_car_s_74c03d06  FOREIGN KEY (sale_channel_id) REFERENCES used_car_sale_channel (id);
ALTER TABLE used_car_sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_sale_order_id_used_def3eb45  FOREIGN KEY (sale_order_id) REFERENCES used_car_sale_order (id)  ON DELETE CASCADE;
ALTER TABLE used_car_sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_disposal_candidate_3e572391  FOREIGN KEY (disposal_candidate_id) REFERENCES used_car_disposal_candidate (id);
ALTER TABLE used_car_sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_vehicle_id_fleet_vehicle_3  FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id);
ALTER TABLE used_car_sale_order_vehicle ADD CONSTRAINT fk_used_car_sale_order_vehicle_listing_id_used_ca_0ecc8323  FOREIGN KEY (listing_id) REFERENCES used_car_listing (id);
ALTER TABLE used_car_vehicle_transfer ADD CONSTRAINT fk_used_car_vehicle_transfer_sale_order_vehicle_i_13b3f076  FOREIGN KEY (sale_order_vehicle_id) REFERENCES used_car_sale_order_vehicle (id);
ALTER TABLE used_car_vehicle_transfer ADD CONSTRAINT fk_used_car_vehicle_transfer_seller_party_id_party_party_2  FOREIGN KEY (seller_party_id) REFERENCES party_party (id);
ALTER TABLE used_car_vehicle_transfer ADD CONSTRAINT fk_used_car_vehicle_transfer_buyer_party_id_party_party_3  FOREIGN KEY (buyer_party_id) REFERENCES party_party (id);
ALTER TABLE used_car_used_vehicle_warranty ADD CONSTRAINT fk_used_car_used_vehicle_warranty_sale_order_vehi_a729f4c1  FOREIGN KEY (sale_order_vehicle_id) REFERENCES used_car_sale_order_vehicle (id) ON DELETE CASCADE;
ALTER TABLE used_car_sale_document ADD CONSTRAINT fk_used_car_sale_document_sale_order_id_used_car__2ea0cf60  FOREIGN KEY (sale_order_id) REFERENCES used_car_sale_order (id)  ON DELETE CASCADE;
ALTER TABLE privacy_privacy_notice_version ADD CONSTRAINT fk_privacy_privacy_notice_version_privacy_notice__ac0b556a  FOREIGN KEY (privacy_notice_id) REFERENCES privacy_privacy_notice ( id) ON DELETE CASCADE;
ALTER TABLE privacy_legal_basis ADD CONSTRAINT fk_privacy_legal_basis_purpose_id_privacy_process_a07a3266  FOREIGN KEY (purpose_id) REFERENCES privacy_processing_purpose (id);
ALTER TABLE privacy_consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE privacy_consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_privacy_notice_version_a9f735eb  FOREIGN KEY (privacy_notice_version_id) REFERENCES privacy_privacy_notice_version (id);
ALTER TABLE privacy_consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_purpose_id_privacy_pro_cd939f31  FOREIGN KEY (purpose_id) REFERENCES privacy_processing_purpose (id);
ALTER TABLE privacy_consent_receipt ADD CONSTRAINT fk_privacy_consent_receipt_channel_id_org_channel_4  FOREIGN KEY (channel_id) REFERENCES org_channel (id);
ALTER TABLE privacy_data_subject_request ADD CONSTRAINT fk_privacy_data_subject_request_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE privacy_data_subject_request ADD CONSTRAINT fk_privacy_data_subject_request_channel_id_org_channel_2  FOREIGN KEY (channel_id) REFERENCES org_channel (id);
ALTER TABLE privacy_data_subject_request ADD CONSTRAINT fk_privacy_data_subject_request_identity_verifica_9067215d  FOREIGN KEY (identity_verification_id) REFERENCES party_identity_verification (id);
ALTER TABLE privacy_legal_hold ADD CONSTRAINT fk_privacy_legal_hold_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE privacy_erasure_job ADD CONSTRAINT fk_privacy_erasure_job_data_subject_request_id_pr_35b86c5d  FOREIGN KEY (data_subject_request_id) REFERENCES privacy_data_subject_request (id);
ALTER TABLE privacy_erasure_job ADD CONSTRAINT fk_privacy_erasure_job_party_id_party_party_2  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE privacy_erasure_job ADD CONSTRAINT fk_privacy_erasure_job_blocked_by_legal_hold_id_p_fe8237f5  FOREIGN KEY (blocked_by_legal_hold_id) REFERENCES privacy_legal_hold (id);
ALTER TABLE privacy_data_access_audit ADD CONSTRAINT fk_privacy_data_access_audit_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE privacy_data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_party_id_party_party_1  FOREIGN KEY (party_id) REFERENCES party_party (id);
ALTER TABLE privacy_data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_recipient_party_id_fe3eb89a  FOREIGN KEY (recipient_party_id) REFERENCES party_party (id);
ALTER TABLE privacy_data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_purpose_id_privacy_303fc290  FOREIGN KEY (purpose_id) REFERENCES privacy_processing_purpose (id);
ALTER TABLE privacy_data_sharing_record ADD CONSTRAINT fk_privacy_data_sharing_record_legal_basis_id_pri_46a287ce  FOREIGN KEY (legal_basis_id) REFERENCES privacy_legal_basis (id);
ALTER TABLE integration_saga_step ADD CONSTRAINT fk_integration_saga_step_saga_instance_id_integra_4d884140  FOREIGN KEY (saga_instance_id) REFERENCES integration_saga_instance (id)  ON DELETE CASCADE;
ALTER TABLE integration_audit_event ADD CONSTRAINT fk_integration_audit_event_legal_entity_id_org_le_989ccbe0  FOREIGN KEY (legal_entity_id) REFERENCES org_legal_entity (id);
ALTER TABLE integration_audit_event ADD CONSTRAINT fk_integration_audit_event_branch_id_org_branch_2  FOREIGN KEY (branch_id) REFERENCES org_branch (id);
ALTER TABLE fleet_vehicle_calendar_guard ADD CONSTRAINT fk_calendar_guard_vehicle FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicle (id) ON DELETE CASCADE;

-- --------------------------------------------------------------------------
-- Secondary indexes
-- --------------------------------------------------------------------------
CREATE INDEX ix_org_business_unit_parent_business_unit_id_1  ON org_business_unit (parent_business_unit_id);
CREATE INDEX ix_org_branch_country_code_status_1 ON org_branch (country_code, status);
CREATE INDEX ix_org_branch_airport_code_2 ON org_branch (airport_code);
CREATE INDEX ix_org_branch_operator_branch_id_valid_from_1  ON org_branch_operator (branch_id, valid_from);
CREATE INDEX ix_party_party_canonical_status_1 ON party_party (canonical_status);
CREATE INDEX ix_party_party_identifier_party_id_identifier_type_1  ON party_party_identifier (party_id, identifier_type);
CREATE INDEX ix_party_contact_point_party_id_contact_type_1  ON party_contact_point (party_id, contact_type);
CREATE INDEX ix_party_contact_point_value_hmac_2 ON party_contact_point (value_hmac);
CREATE INDEX ix_party_party_address_party_id_usage_type_1  ON party_party_address (party_id, usage_type);
CREATE INDEX ix_party_customer_account_party_id_1 ON party_customer_account (party_id);
CREATE INDEX ix_party_customer_account_status_2 ON party_customer_account (status);
CREATE INDEX ix_party_organization_representative_organization_673bbd10  ON party_organization_representative (organization_party_id);
CREATE INDEX ix_party_organization_representative_person_party_id_2  ON party_organization_representative (person_party_id);
CREATE INDEX ix_party_driver_license_driver_profile_id_expires_at_1  ON party_driver_license (driver_profile_id, expires_at);
CREATE INDEX ix_party_identity_verification_party_id_verified_at_1  ON party_identity_verification (party_id, verified_at);
CREATE INDEX ix_party_risk_assessment_party_id_assessed_at_1  ON party_risk_assessment (party_id, assessed_at);
CREATE INDEX ix_party_customer_restriction_party_id_status_1  ON party_customer_restriction (party_id, status);
CREATE INDEX ix_catalog_vehicle_variant_model_year_1 ON catalog_vehicle_variant (model_year);
CREATE INDEX ix_catalog_vehicle_group_market_country_code_status_1  ON catalog_vehicle_group (market_country_code, status);
CREATE INDEX ix_catalog_vehicle_group_variant_vehicle_variant__503416be  ON catalog_vehicle_group_variant (vehicle_variant_id, valid_from);
CREATE INDEX ix_catalog_vehicle_group_upgrade_from_group_id_priority_1  ON catalog_vehicle_group_upgrade (from_group_id, priority);
CREATE INDEX ix_catalog_commercial_product_product_type_status_1  ON catalog_commercial_product (product_type, status);
CREATE INDEX ix_corporate_corporate_agreement_customer_account_f75ea870  ON corporate_corporate_agreement (customer_account_id, status);
CREATE INDEX ix_fleet_vehicle_current_branch_id_current_vehicl_b582c392  ON fleet_vehicle (current_branch_id, current_vehicle_group_id, current_operational_state);
CREATE INDEX ix_fleet_vehicle_current_lifecycle_state_2  ON fleet_vehicle (current_lifecycle_state);
CREATE INDEX ix_fleet_vehicle_registration_vehicle_id_valid_from_1  ON fleet_vehicle_registration (vehicle_id, valid_from);
CREATE INDEX ix_fleet_vehicle_registration_registration_number_2  ON fleet_vehicle_registration (registration_number);
CREATE INDEX ix_fleet_vehicle_group_assignment_vehicle_group_i_094e1ae6  ON fleet_vehicle_group_assignment (vehicle_group_id, valid_from);
CREATE INDEX ix_fleet_vehicle_operational_state_history_vehicl_5c9e6ef5  ON fleet_vehicle_operational_state_history (vehicle_id, changed_at);
CREATE INDEX ix_fleet_vehicle_lifecycle_history_vehicle_id_changed_at_1  ON fleet_vehicle_lifecycle_history (vehicle_id, changed_at);
CREATE INDEX ix_fleet_vehicle_restriction_vehicle_id_status_1  ON fleet_vehicle_restriction (vehicle_id, status);
CREATE INDEX ix_fleet_vehicle_location_history_vehicle_id_recorded_at_1  ON fleet_vehicle_location_history (vehicle_id, recorded_at);
CREATE INDEX ix_fleet_vehicle_calendar_entry_vehicle_id_start__25052cfa  ON fleet_vehicle_calendar_entry (vehicle_id, start_at, end_at);
CREATE INDEX ix_fleet_vehicle_calendar_entry_source_type_source_id_2  ON fleet_vehicle_calendar_entry (source_type, source_id);
CREATE INDEX ix_fleet_odometer_reading_vehicle_id_reading_at_1  ON fleet_odometer_reading (vehicle_id, reading_at);
CREATE INDEX ix_fleet_fuel_reading_vehicle_id_reading_at_1  ON fleet_fuel_reading (vehicle_id, reading_at);
CREATE INDEX ix_fleet_asset_document_vehicle_id_document_type_1  ON fleet_asset_document (vehicle_id, document_type);
CREATE INDEX ix_fleet_vehicle_accessory_assignment_vehicle_id__cb56e5d9  ON fleet_vehicle_accessory_assignment (vehicle_id, start_at);
CREATE INDEX ix_fleet_disposal_eligibility_vehicle_id_evaluated_at_1  ON fleet_disposal_eligibility (vehicle_id, evaluated_at);
CREATE INDEX ix_pricing_rate_plan_version_rate_plan_id_valid_f_cfe91f9e  ON pricing_rate_plan_version (rate_plan_id, valid_from, valid_to);
CREATE INDEX ix_pricing_rate_plan_applicability_origin_branch__cea49215  ON pricing_rate_plan_applicability (origin_branch_id, vehicle_group_id, priority);
CREATE INDEX ix_pricing_base_rate_rate_plan_version_id_vehicle_00ee8c12  ON pricing_base_rate (rate_plan_version_id, vehicle_group_id, origin_branch_id, valid_from);
CREATE INDEX ix_pricing_one_way_rule_origin_branch_id_destinat_c15b9004  ON pricing_one_way_rule (origin_branch_id, destination_branch_id, vehicle_group_id, priority);
CREATE INDEX ix_pricing_fuel_price_branch_id_fuel_type_valid_from_1  ON pricing_fuel_price (branch_id, fuel_type, valid_from);
CREATE INDEX ix_pricing_coupon_redemption_coupon_id_party_id_1  ON pricing_coupon_redemption (coupon_id, party_id);
CREATE INDEX ix_pricing_quote_origin_branch_id_vehicle_group_i_76eea0f3  ON pricing_quote (origin_branch_id, vehicle_group_id, planned_pickup_at);
CREATE INDEX ix_pricing_quote_customer_account_id_created_at_2  ON pricing_quote (customer_account_id, created_at);
CREATE INDEX ix_availability_inventory_bucket_local_business_d_b4feeb3c  ON availability_inventory_bucket (local_business_date, branch_id);
CREATE INDEX ix_availability_availability_hold_branch_id_vehic_54be950e  ON availability_availability_hold (branch_id, vehicle_group_id, start_at, end_at);
CREATE INDEX ix_availability_availability_hold_expires_at_status_2  ON availability_availability_hold (expires_at, status);
CREATE INDEX ix_availability_capacity_commitment_branch_id_veh_3615b9b9  ON availability_capacity_commitment (branch_id, vehicle_group_id, start_at, end_at);
CREATE INDEX ix_availability_capacity_commitment_source_type_s_d14b4be6  ON availability_capacity_commitment (source_type, source_id);
CREATE INDEX ix_availability_upgrade_path_from_group_id_priority_1  ON availability_upgrade_path (from_group_id, priority);
CREATE INDEX ix_availability_fleet_allotment_branch_id_vehicle_6521bb23  ON availability_fleet_allotment (branch_id, vehicle_group_id, start_at);
CREATE INDEX ix_availability_oversell_alert_status_detected_at_1  ON availability_oversell_alert (status, detected_at);
CREATE INDEX ix_reservation_reservation_pickup_branch_id_plann_7fcc49a3  ON reservation_reservation (pickup_branch_id, planned_pickup_at, requested_vehicle_group_id);
CREATE INDEX ix_reservation_reservation_customer_account_id_cr_7d260e6d  ON reservation_reservation (customer_account_id, created_at);
CREATE INDEX ix_reservation_reservation_current_status_planned_301ad661  ON reservation_reservation (current_status, planned_pickup_at);
CREATE INDEX ix_reservation_reservation_status_history_reserva_541b9721  ON reservation_reservation_status_history (reservation_id, changed_at);
CREATE INDEX ix_reservation_digital_pickup_eligibility_reserva_d4a372f0  ON reservation_digital_pickup_eligibility (reservation_id, assessed_at);
CREATE INDEX ix_reservation_reservation_inventory_commitment_r_857487d3  ON reservation_reservation_inventory_commitment (reservation_id);
CREATE INDEX ix_reservation_reservation_inventory_commitment_c_789ea5ea  ON reservation_reservation_inventory_commitment (capacity_commitment_id);
CREATE INDEX ix_rental_rental_contract_customer_account_id_opened_at_1  ON rental_rental_contract (customer_account_id, opened_at);
CREATE INDEX ix_rental_rental_contract_current_status_planned__5a9f25e5  ON rental_rental_contract (current_status, planned_return_at);
CREATE INDEX ix_rental_rental_contract_origin_branch_id_opened_at_3  ON rental_rental_contract (origin_branch_id, opened_at);
CREATE INDEX ix_rental_contract_party_role_contract_id_role_type_1  ON rental_contract_party_role (contract_id, role_type);
CREATE INDEX ix_rental_vehicle_assignment_vehicle_id_start_at_end_at_1  ON rental_vehicle_assignment (vehicle_id, start_at, end_at);
CREATE INDEX ix_rental_vehicle_assignment_contract_id_status_2  ON rental_vehicle_assignment (contract_id, status);
CREATE INDEX ix_rental_extension_contract_id_requested_at_1  ON rental_extension (contract_id, requested_at);
CREATE INDEX ix_rental_contract_status_history_contract_id_changed_at_1  ON rental_contract_status_history (contract_id, changed_at);
CREATE INDEX ix_rental_contract_document_contract_id_document_type_1  ON rental_contract_document (contract_id, document_type);
CREATE INDEX ix_rental_vehicle_access_command_vehicle_id_requested_at_1  ON rental_vehicle_access_command (vehicle_id, requested_at);
CREATE INDEX ix_inspection_inspection_vehicle_id_started_at_1  ON inspection_inspection (vehicle_id, started_at);
CREATE INDEX ix_inspection_inspection_contract_id_inspection_type_2  ON inspection_inspection (contract_id, inspection_type);
CREATE INDEX ix_inspection_inspection_media_inspection_id_captured_at_1  ON inspection_inspection_media (inspection_id, captured_at);
CREATE INDEX ix_inspection_damage_record_vehicle_id_status_1  ON inspection_damage_record (vehicle_id, status);
CREATE INDEX ix_billing_payment_method_token_party_id_status_1  ON billing_payment_method_token (party_id, status);
CREATE INDEX ix_billing_payment_method_token_provider_fingerprint_2  ON billing_payment_method_token (provider, fingerprint);
CREATE INDEX ix_billing_charge_contract_id_occurred_at_1  ON billing_charge (contract_id, occurred_at);
CREATE INDEX ix_billing_charge_source_context_source_id_2  ON billing_charge (source_context, source_id);
CREATE INDEX ix_billing_charge_posting_status_occurred_at_3  ON billing_charge (posting_status, occurred_at);
CREATE INDEX ix_billing_invoice_customer_account_id_issue_date_1  ON billing_invoice (customer_account_id, issue_date);
CREATE INDEX ix_billing_invoice_status_due_date_2 ON billing_invoice (status, due_date);
CREATE INDEX ix_billing_receivable_status_due_date_1 ON billing_receivable (status, due_date);
CREATE INDEX ix_billing_payment_intent_provider_provider_reference_1  ON billing_payment_intent (provider, provider_reference);
CREATE INDEX ix_billing_payment_transaction_payment_intent_id__b463a099  ON billing_payment_transaction (payment_intent_id, occurred_at);
CREATE INDEX ix_billing_payment_allocation_receivable_id_allocated_at_1  ON billing_payment_allocation (receivable_id, allocated_at);
CREATE INDEX ix_billing_collection_action_dunning_case_id_executed_at_1  ON billing_collection_action (dunning_case_id, executed_at);
CREATE INDEX ix_traffic_traffic_notice_vehicle_id_infraction_at_1  ON traffic_traffic_notice (vehicle_id, infraction_at);
CREATE INDEX ix_traffic_traffic_notice_status_due_date_2  ON traffic_traffic_notice (status, due_date);
CREATE INDEX ix_traffic_toll_tag_assignment_vehicle_id_start_at_1  ON traffic_toll_tag_assignment (vehicle_id, start_at);
CREATE INDEX ix_traffic_toll_transaction_vehicle_id_occurred_at_1  ON traffic_toll_transaction (vehicle_id, occurred_at);
CREATE INDEX ix_traffic_parking_transaction_vehicle_id_entered_at_1  ON traffic_parking_transaction (vehicle_id, entered_at);
CREATE INDEX ix_claim_incident_contract_id_occurred_at_1  ON claim_incident (contract_id, occurred_at);
CREATE INDEX ix_claim_incident_status_reported_at_2 ON claim_incident (status, reported_at);
CREATE INDEX ix_claim_claim_cost_claim_id_incurred_at_1  ON claim_claim_cost (claim_id, incurred_at);
CREATE INDEX ix_maintenance_maintenance_due_status_due_date_1  ON maintenance_maintenance_due (status, due_date);
CREATE INDEX ix_maintenance_maintenance_due_vehicle_id_status_2  ON maintenance_maintenance_due (vehicle_id, status);
CREATE INDEX ix_maintenance_service_order_vehicle_id_opened_at_1  ON maintenance_service_order (vehicle_id, opened_at);
CREATE INDEX ix_maintenance_service_order_status_scheduled_start_at_2  ON maintenance_service_order (status, scheduled_start_at);
CREATE INDEX ix_maintenance_tire_assignment_vehicle_id_positio_a894da3f  ON maintenance_tire_assignment (vehicle_id, position_code, installed_at);
CREATE INDEX ix_maintenance_downtime_vehicle_id_start_at_1  ON maintenance_downtime (vehicle_id, start_at);
CREATE INDEX ix_telematics_device_status_last_seen_at_1  ON telematics_device (status, last_seen_at);
CREATE INDEX ix_telematics_vehicle_device_assignment_vehicle_i_a60b1872  ON telematics_vehicle_device_assignment (vehicle_id, start_at);
CREATE INDEX ix_telematics_device_health_event_device_id_occurred_at_1  ON telematics_device_health_event (device_id, occurred_at);
CREATE INDEX ix_telematics_telemetry_event_index_vehicle_id_ev_06487c2b  ON telematics_telemetry_event_index (vehicle_id, event_time);
CREATE INDEX ix_telematics_telemetry_event_index_event_type_ev_0472e44c  ON telematics_telemetry_event_index (event_type, event_time);
CREATE INDEX ix_telematics_trip_summary_vehicle_id_trip_start_at_1  ON telematics_trip_summary (vehicle_id, trip_start_at);
CREATE INDEX ix_telematics_trip_summary_contract_id_trip_start_at_2  ON telematics_trip_summary (contract_id, trip_start_at);
CREATE INDEX ix_telematics_driving_event_vehicle_id_occurred_at_1  ON telematics_driving_event (vehicle_id, occurred_at);
CREATE INDEX ix_telematics_driving_event_contract_id_event_type_2  ON telematics_driving_event (contract_id, event_type);
CREATE INDEX ix_telematics_geofence_event_vehicle_id_occurred_at_1  ON telematics_geofence_event (vehicle_id, occurred_at);
CREATE INDEX ix_loyalty_tier_history_loyalty_account_id_valid_from_1  ON loyalty_tier_history (loyalty_account_id, valid_from);
CREATE INDEX ix_loyalty_points_ledger_loyalty_account_id_available_at_1  ON loyalty_points_ledger (loyalty_account_id, available_at);
CREATE INDEX ix_loyalty_points_ledger_source_type_source_id_2  ON loyalty_points_ledger (source_type, source_id);
CREATE INDEX ix_fleet_mgmt_managed_vehicle_assignment_vehicle__0facac8e  ON fleet_mgmt_managed_vehicle_assignment (vehicle_id, start_at);
CREATE INDEX ix_fleet_mgmt_mileage_commitment_fleet_service_co_9f1fc2d1  ON fleet_mgmt_mileage_commitment (fleet_service_contract_id, period_start);
CREATE INDEX ix_fleet_mgmt_fleet_service_event_fleet_service_c_96458ea4  ON fleet_mgmt_fleet_service_event (fleet_service_contract_id, occurred_at);
CREATE INDEX ix_fleet_mgmt_subscription_vehicle_assignment_veh_be4692a6  ON fleet_mgmt_subscription_vehicle_assignment (vehicle_id, start_at);
CREATE INDEX ix_used_car_vehicle_valuation_disposal_candidate__d6cb4637  ON used_car_vehicle_valuation (disposal_candidate_id, valued_at);
CREATE INDEX ix_used_car_listing_status_listed_at_1 ON used_car_listing (status, listed_at);
CREATE INDEX ix_used_car_lead_status_next_action_at_1 ON used_car_lead (status, next_action_at);
CREATE INDEX ix_privacy_consent_receipt_party_id_purpose_id_ca_56424124  ON privacy_consent_receipt (party_id, purpose_id, captured_at);
CREATE INDEX ix_privacy_data_subject_request_status_due_at_1  ON privacy_data_subject_request (status, due_at);
CREATE INDEX ix_privacy_legal_hold_resource_type_resource_id_1  ON privacy_legal_hold (resource_type, resource_id);
CREATE INDEX ix_privacy_legal_hold_party_id_status_2 ON privacy_legal_hold (party_id, status);
CREATE INDEX ix_privacy_erasure_job_status_scheduled_at_1  ON privacy_erasure_job (status, scheduled_at);
CREATE INDEX ix_privacy_data_access_audit_party_id_occurred_at_1  ON privacy_data_access_audit (party_id, occurred_at);
CREATE INDEX ix_privacy_data_access_audit_actor_id_occurred_at_2  ON privacy_data_access_audit (actor_id, occurred_at);
CREATE INDEX ix_privacy_data_sharing_record_party_id_shared_at_1  ON privacy_data_sharing_record (party_id, shared_at);
CREATE INDEX ix_integration_outbox_event_published_at_created_at_1  ON integration_outbox_event (published_at, created_at);
CREATE INDEX ix_integration_outbox_event_aggregate_type_aggregate_id_2  ON integration_outbox_event (aggregate_type, aggregate_id);
CREATE INDEX ix_integration_inbox_message_status_received_at_1  ON integration_inbox_message (status, received_at);
CREATE INDEX ix_integration_idempotency_key_expires_at_status_1  ON integration_idempotency_key (expires_at, status);
CREATE INDEX ix_integration_external_reference_resource_type_r_59e6ad58  ON integration_external_reference (resource_type, resource_id);
CREATE INDEX ix_integration_external_reference_system_code_ext_200eeeec  ON integration_external_reference (system_code, external_id);
CREATE INDEX ix_integration_audit_event_resource_type_resource_1720f547  ON integration_audit_event (resource_type, resource_id, occurred_at);
CREATE INDEX ix_integration_audit_event_actor_id_occurred_at_2  ON integration_audit_event (actor_id, occurred_at);

-- MySQL does not support partial indexes. These broader indexes support the
-- same operational queries; status predicates are applied by the query.
CREATE INDEX ix_reservation_active_pickup
    ON reservation_reservation (pickup_branch_id, planned_pickup_at, requested_vehicle_group_id, current_status);
CREATE INDEX ix_vehicle_available_by_branch_group
    ON fleet_vehicle (current_branch_id, current_vehicle_group_id, current_operational_state, current_lifecycle_state);
CREATE INDEX ix_contract_open_due
    ON rental_rental_contract (current_status, planned_return_at);
CREATE INDEX ix_outbox_unpublished
    ON integration_outbox_event (published_at, created_at);

DELIMITER $$

-- Fast, non-concurrent overlap protection. Under concurrency, callers must also
-- invoke sp_lock_vehicle_calendar_slot inside the same transaction before INSERT.
CREATE TRIGGER trg_calendar_no_overlap_bi
BEFORE INSERT ON fleet_vehicle_calendar_entry
FOR EACH ROW
BEGIN
    IF NEW.status IN ('HELD','CONFIRMED','ACTIVE','CLOSED') AND EXISTS (
        SELECT 1
          FROM fleet_vehicle_calendar_entry e
         WHERE e.vehicle_id = NEW.vehicle_id
           AND e.status IN ('HELD','CONFIRMED','ACTIVE','CLOSED')
           AND NEW.start_at < e.end_at
           AND NEW.end_at > e.start_at
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle calendar interval overlaps an existing entry';
    END IF;
END$$

CREATE TRIGGER trg_calendar_no_overlap_bu
BEFORE UPDATE ON fleet_vehicle_calendar_entry
FOR EACH ROW
BEGIN
    IF NEW.status IN ('HELD','CONFIRMED','ACTIVE','CLOSED') AND EXISTS (
        SELECT 1
          FROM fleet_vehicle_calendar_entry e
         WHERE e.vehicle_id = NEW.vehicle_id
           AND e.id <> NEW.id
           AND e.status IN ('HELD','CONFIRMED','ACTIVE','CLOSED')
           AND NEW.start_at < e.end_at
           AND NEW.end_at > e.start_at
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle calendar interval overlaps an existing entry';
    END IF;
END$$

-- Safe protocol:
-- START TRANSACTION;
-- CALL sp_lock_vehicle_calendar_slot(:vehicle_id, :start_at, :end_at, :entry_id_or_null);
-- INSERT/UPDATE fleet_vehicle_calendar_entry ...;
-- COMMIT;
CREATE PROCEDURE sp_lock_vehicle_calendar_slot(
    IN p_vehicle_id char(36),
    IN p_start_at datetime(6),
    IN p_end_at datetime(6),
    IN p_excluded_entry_id char(36)
)
BEGIN
    DECLARE v_lock_version bigint;

    IF p_end_at <= p_start_at THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'calendar end must be greater than start';
    END IF;

    INSERT INTO fleet_vehicle_calendar_guard (vehicle_id, lock_version)
    VALUES (p_vehicle_id, 0)
    ON DUPLICATE KEY UPDATE lock_version = lock_version;

    SELECT lock_version
      INTO v_lock_version
      FROM fleet_vehicle_calendar_guard
     WHERE vehicle_id = p_vehicle_id
     FOR UPDATE;

    IF EXISTS (
        SELECT 1
          FROM fleet_vehicle_calendar_entry e
         WHERE e.vehicle_id = p_vehicle_id
           AND (p_excluded_entry_id IS NULL OR e.id <> p_excluded_entry_id)
           AND e.status IN ('HELD','CONFIRMED','ACTIVE','CLOSED')
           AND p_start_at < e.end_at
           AND p_end_at > e.start_at
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'vehicle calendar interval overlaps an existing entry';
    END IF;
END$$

CREATE TRIGGER trg_rate_plan_period_bi
BEFORE INSERT ON pricing_rate_plan_version
FOR EACH ROW
BEGIN
    IF NEW.status = 'PUBLISHED' AND EXISTS (
        SELECT 1
          FROM pricing_rate_plan_version v
         WHERE v.rate_plan_id = NEW.rate_plan_id
           AND v.status = 'PUBLISHED'
           AND NEW.valid_from < COALESCE(v.valid_to, '9999-12-31 23:59:59.999999')
           AND COALESCE(NEW.valid_to, '9999-12-31 23:59:59.999999') > v.valid_from
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'published rate plan versions overlap';
    END IF;
END$$

CREATE TRIGGER trg_rate_plan_period_bu
BEFORE UPDATE ON pricing_rate_plan_version
FOR EACH ROW
BEGIN
    IF NEW.status = 'PUBLISHED' AND EXISTS (
        SELECT 1
          FROM pricing_rate_plan_version v
         WHERE v.rate_plan_id = NEW.rate_plan_id
           AND v.id <> NEW.id
           AND v.status = 'PUBLISHED'
           AND NEW.valid_from < COALESCE(v.valid_to, '9999-12-31 23:59:59.999999')
           AND COALESCE(NEW.valid_to, '9999-12-31 23:59:59.999999') > v.valid_from
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'published rate plan versions overlap';
    END IF;
END$$

CREATE TRIGGER trg_charge_protect_posted_bu
BEFORE UPDATE ON billing_charge
FOR EACH ROW
BEGIN
    IF OLD.posting_status = 'POSTED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'posted charges must be reversed, not updated';
    END IF;
END$$

CREATE TRIGGER trg_charge_protect_posted_bd
BEFORE DELETE ON billing_charge
FOR EACH ROW
BEGIN
    IF OLD.posting_status = 'POSTED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'posted charges are immutable';
    END IF;
END$$

CREATE TRIGGER trg_inspection_protect_completed_bu
BEFORE UPDATE ON inspection_inspection
FOR EACH ROW
BEGIN
    IF OLD.status = 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'completed inspections must be superseded, not updated';
    END IF;
END$$

CREATE TRIGGER trg_inspection_protect_completed_bd
BEFORE DELETE ON inspection_inspection
FOR EACH ROW
BEGIN
    IF OLD.status = 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'completed inspections are immutable';
    END IF;
END$$

CREATE TRIGGER trg_points_ledger_immutable_bu BEFORE UPDATE ON loyalty_points_ledger
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'points ledger is immutable'; END$$
CREATE TRIGGER trg_points_ledger_immutable_bd BEFORE DELETE ON loyalty_points_ledger
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'points ledger is immutable'; END$$

CREATE TRIGGER trg_payment_transaction_immutable_bu BEFORE  UPDATE ON billing_payment_transaction
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'payment transactions are immutable'; END$$
CREATE TRIGGER trg_payment_transaction_immutable_bd BEFORE  DELETE ON billing_payment_transaction
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'payment transactions are immutable'; END$$

CREATE TRIGGER trg_terms_acceptance_immutable_bu BEFORE UPDATE ON rental_contract_terms_acceptance
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'terms acceptance is immutable'; END$$
CREATE TRIGGER trg_terms_acceptance_immutable_bd BEFORE DELETE ON rental_contract_terms_acceptance
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'terms acceptance is immutable'; END$$

CREATE TRIGGER trg_audit_event_immutable_bu BEFORE UPDATE ON integration_audit_event
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'audit event is immutable'; END$$
CREATE TRIGGER trg_audit_event_immutable_bd BEFORE DELETE ON integration_audit_event
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'audit event is immutable'; END$$

CREATE TRIGGER trg_privacy_access_audit_immutable_bu BEFORE  UPDATE ON privacy_data_access_audit
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'privacy access audit is immutable'; END$$
CREATE TRIGGER trg_privacy_access_audit_immutable_bd BEFORE  DELETE ON privacy_data_access_audit
FOR EACH ROW BEGIN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'privacy access audit is immutable'; END$$

DELIMITER ;
