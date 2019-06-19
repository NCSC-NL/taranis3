---
--- This schema is loaded by the installation script install/640.db-load
--- when there is no database loaded yet.  Otherwise, upgrade scripts will
--- get run via install/641.db-upgrade
---

--- !!!! When you make changes to this schema, you much check the syntax
--- !!!! by running regression script t/054-db-load-schema.t

--- Global settings are sometimes wrong
--- Things will really break when these are set wrongly.  Changes in the
--- database settings are only affectuated after a new connection, so we
--- need to set them for the current session as well.

DO $$
BEGIN
EXECUTE 'ALTER DATABASE ' || current_database() || ' SET datestyle = ISO, YMD';
END; $$;
SET datestyle = 'ISO, YMD';

DO $$
BEGIN
EXECUTE 'ALTER DATABASE ' || current_database() ||' SET client_encoding = UTF8';
END; $$;
SET client_encoding = UTF8;

DO $$
BEGIN
EXECUTE 'ALTER DATABASE ' || current_database() ||' SET client_min_messages = warning';
END; $$;
SET client_min_messages = warning;


--- This table was added in 3.4 to maintain global settings, mainly: the
--- schema version of this database.

CREATE TABLE taranis (
    key   character varying(50) NOT NULL,
    value text
);

INSERT INTO taranis VALUES ('schema_version', 3600);


CREATE TABLE advisory_damage (
    advisory_id integer NOT NULL,
    damage_id integer NOT NULL
);


CREATE TABLE analysis (
    id character varying(8) NOT NULL,
    orgdate character varying(8),
    orgtime character varying(8),
    last_status_date character varying(8),
    last_status_time character varying(8),
    status character varying(15),
    title text,
    comments text,
    idstring text,
    rating integer,
    orgdatetime timestamp without time zone DEFAULT now(),
    last_status_change timestamp without time zone DEFAULT now(),
    joined_into_analysis character varying(8),
    opened_by text,
    owned_by text
);


CREATE TABLE analysis_publication (
    analysis_id character varying(8) NOT NULL,
    publication_id integer NOT NULL
);

CREATE SEQUENCE advisory_linked_items_id_seq
    START WITH 10000000
    CACHE 10;

CREATE TABLE advisory_linked_items (
    id integer DEFAULT nextval('advisory_linked_items_id_seq'::regclass) NOT NULL,
    created timestamp with time zone default now(),
    item_digest character varying(50) NOT NULL,
    publication_id integer NOT NULL,
    created_by text NOT NULL
);

ALTER SEQUENCE advisory_linked_items_id_seq
    OWNED BY advisory_linked_items.id;


CREATE SEQUENCE calling_list_id_seq
    START WITH 20000000
    CACHE 10;

CREATE TABLE calling_list (
    id integer DEFAULT nextval('calling_list_id_seq'::regclass) NOT NULL,
    publication_id integer NOT NULL,
    group_id integer NOT NULL,
    is_called boolean DEFAULT false,
    locked_by text,
    comments text
);

ALTER SEQUENCE calling_list_id_seq
    OWNED BY calling_list.id;


CREATE SEQUENCE category_id_seq
    START WITH 30000000
    CACHE 10;

CREATE TABLE category (
    id integer DEFAULT nextval('category_id_seq'::regclass) NOT NULL,
    name character varying(30) NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL
);

ALTER SEQUENCE category_id_seq
    OWNED BY category.id;


CREATE TABLE checkstatus (
    source character varying(50) NOT NULL,
    "timestamp" character varying(10),
    comments character varying(50)
);


CREATE SEQUENCE cluster_id_seq
    START WITH 40000000
    CACHE 10;

CREATE TABLE cluster (
    id integer DEFAULT nextval('cluster_id_seq'::regclass) NOT NULL,
    language character varying(2) NOT NULL,
    threshold numeric NOT NULL,
    timeframe_hours integer NOT NULL,
    is_enabled boolean DEFAULT true,
    category_id integer NOT NULL,
    recluster boolean DEFAULT true NOT NULL
);

ALTER SEQUENCE cluster_id_seq
    OWNED BY cluster.id;


CREATE SEQUENCE collector_id_seq
    START WITH 50000000
    CACHE 10;

CREATE TABLE collector (
   id integer DEFAULT nextval('collector_id_seq'::regclass) NOT NULL, 
   description text NOT NULL, 
   secret character varying(100)
);

ALTER SEQUENCE collector_id_seq
    OWNED BY collector.id;


CREATE SEQUENCE constituent_group_id_seq
    START WITH 60000000
    CACHE 10;

CREATE TABLE constituent_group (
    id integer DEFAULT nextval('constituent_group_id_seq'::regclass) NOT NULL,
    name text NOT NULL,
    use_sh boolean DEFAULT false NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    constituent_type integer NOT NULL,
    notes text,
    call_hh  boolean DEFAULT false,
    any_hh   boolean DEFAULT false,
    no_advisories boolean DEFAULT false NOT NULL,
    external_ref text
);

ALTER SEQUENCE constituent_group_id_seq
    OWNED BY constituent_group.id;


CREATE SEQUENCE constituent_individual_id_seq
    START WITH 70000000
    CACHE 10;

CREATE TABLE constituent_individual (
    id integer DEFAULT nextval('constituent_individual_id_seq'::regclass) NOT NULL,
    call247 boolean NOT NULL,
    emailaddress text,
    firstname text NOT NULL,
    lastname text NOT NULL,
    role integer NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    tel_mobile text,
    tel_regular text,
    call_hh boolean DEFAULT false,
    external_ref text,
    PRIMARY KEY (id)
);

ALTER SEQUENCE constituent_individual_id_seq
    OWNED BY constituent_individual.id;


CREATE SEQUENCE constituent_publication_id_seq
    START WITH 80000000
    CACHE 10;

CREATE TABLE constituent_publication (
    id integer DEFAULT nextval('constituent_publication_id_seq'::regclass) NOT NULL,
    type_id integer NOT NULL,
    constituent_id integer NOT NULL
);

ALTER SEQUENCE constituent_publication_id_seq
    OWNED BY constituent_publication.id;


CREATE SEQUENCE constituent_role_id_seq
    START WITH 90000000
    CACHE 10;

CREATE TABLE constituent_role (
    id integer DEFAULT nextval('constituent_role_id_seq'::regclass) NOT NULL,
    role_name character varying(50),
    PRIMARY KEY(id)
);

ALTER SEQUENCE constituent_role_id_seq
    OWNED BY constituent_role.id;


CREATE SEQUENCE constituent_type_id_seq
    START WITH 110000000
    CACHE 10;

CREATE TABLE constituent_type (
    id integer DEFAULT nextval('constituent_type_id_seq'::regclass) NOT NULL,
    type_description character varying(50) NOT NULL
);

ALTER SEQUENCE constituent_type_id_seq
    OWNED BY constituent_type.id;


CREATE TABLE cpe_cve (
    cve_id text NOT NULL,
    cpe_id text NOT NULL
);


CREATE TABLE cpe_files (
    filename text NOT NULL,
    last_change text NOT NULL
);


CREATE SEQUENCE damage_description_id_seq
    START WITH 120000000
    CACHE 10;

CREATE TABLE damage_description (
    id integer DEFAULT nextval('damage_description_id_seq'::regclass) NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    description text
);

ALTER SEQUENCE damage_description_id_seq
    OWNED BY damage_description.id;


CREATE TABLE dashboard (
    html text,
    json text,
    type integer NOT NULL
);

CREATE TABLE download_files (
    file_url text NOT NULL,
    last_change text,
    name text NOT NULL,
    filename text
);

--- email_item

CREATE SEQUENCE email_item_id_seq
    START WITH 130000000
    CACHE 10;

CREATE TABLE email_item (
    id integer DEFAULT nextval('email_item_id_seq'::regclass) NOT NULL,
    digest character varying(50) NOT NULL,
    body text
);

ALTER SEQUENCE email_item_id_seq
    OWNED BY email_item.id;

CREATE INDEX email_item_body_trgm_idx
    ON email_item USING GIN(body gin_trgm_ops);

--- email_item archive

CREATE TABLE email_item_archive (
    id integer NOT NULL,
    digest character varying(50) NOT NULL,
    body text
);

CREATE INDEX email_item_archive_body_trgm_idx
    ON email_item_archive USING GIN(body gin_trgm_ops);

---

CREATE SEQUENCE entitlement_id_seq
    START WITH 140000000
    CACHE 10;

CREATE TABLE entitlement (
    id integer DEFAULT nextval('entitlement_id_seq'::regclass) NOT NULL,
    name text,
    description text,
    particularization boolean DEFAULT false
);

ALTER SEQUENCE entitlement_id_seq
    OWNED BY entitlement.id;

COMMENT ON COLUMN entitlement.particularization IS 'This field indicates a particularization for role_right. if true the role_right (web)form should display a text field.';


CREATE SEQUENCE errors_id_seq
    START WITH 150000000
    CACHE 10;

CREATE TABLE errors (
    id integer DEFAULT nextval('errors_id_seq'::regclass) NOT NULL,
    error text,
    error_code character varying(4),
    time_of_error timestamp with time zone DEFAULT now(),
    digest character varying(50),
    logfile text,
    reference_id integer    
);

ALTER SEQUENCE errors_id_seq
    OWNED BY errors.id;


CREATE TABLE identifier (
    identifier character varying(50) NOT NULL,
    digest character varying(50) NOT NULL
);


CREATE TABLE identifier_archive (
    identifier character varying(50),
    digest character varying(50)
);


CREATE TABLE identifier_description (
    identifier character varying(50) NOT NULL,
    description text,
    type character varying(3),
    phase character varying(15),
    status character varying(15),
    phase_date date,
    published_date date,
    modified_date date,
    custom_description text
);


CREATE SEQUENCE import_issue_id_seq
    START WITH 160000000
    CACHE 10;

CREATE TABLE import_issue (
    id integer DEFAULT nextval('import_issue_id_seq'::regclass) NOT NULL,
    created_on timestamp with time zone DEFAULT now(),
    status integer NOT NULL,
    description text,
    comments text,
    type integer,
    soft_hard_id integer,
    resolved_by text,
    resolved_on timestamp with time zone,
    create_new_issue boolean,
    followup_on_issue_nr integer
);

ALTER SEQUENCE import_issue_id_seq
    OWNED BY import_issue.id;


CREATE SEQUENCE import_photo_id_seq
    START WITH 170000000
    CACHE 10;

CREATE TABLE import_photo (
    id integer DEFAULT nextval('import_photo_id_seq'::regclass) NOT NULL,
    group_id integer NOT NULL,
    created_on timestamp with time zone DEFAULT now(),
    imported_on timestamp with time zone,
    imported_by text
);

ALTER SEQUENCE import_photo_id_seq
    OWNED BY import_photo.id;


CREATE TABLE import_photo_software_hardware (
    photo_id integer NOT NULL,
    import_sh integer NOT NULL,
    ok_to_import boolean
);


CREATE SEQUENCE import_software_hardware_id_seq
    START WITH 180000000
    CACHE 10;

CREATE TABLE import_software_hardware (
    id integer DEFAULT nextval('import_software_hardware_id_seq'::regclass) NOT NULL,
    cpe_id text,
    producer text,
    name text,
    type text,
    issue_nr integer
);

ALTER SEQUENCE import_software_hardware_id_seq
    OWNED BY import_software_hardware.id;


CREATE SEQUENCE item_id_seq
    START WITH 190000000
    CACHE 10;

CREATE TABLE item (
    id integer DEFAULT nextval('item_id_seq'::regclass) NOT NULL,
    digest character varying(50) NOT NULL,
    date character varying(8),
    "time" character varying(8),
    source character varying(50),
    title character varying(250),
    link character varying(500),
    description character varying(500),
    status integer DEFAULT 0,
    created timestamp with time zone DEFAULT now() NOT NULL,
    is_mail boolean DEFAULT false,
    is_mailed boolean DEFAULT false NOT NULL,
    category integer,
    cluster_id character varying(22),
    cluster_score numeric,
    cluster_enabled boolean DEFAULT true,
    source_id integer,
    screenshot_object_id oid,
    screenshot_file_size integer,
    matching_keywords_json text
);

ALTER SEQUENCE item_id_seq
    OWNED BY item.id;

CREATE INDEX ON item(status);

CREATE TABLE item_analysis (
    item_id character varying(50) NOT NULL,
    analysis_id character varying(8) NOT NULL
);


CREATE TABLE item_archive (
    digest character varying(50) NOT NULL,
    id character varying(16),
    date character varying(8),
    "time" character varying(8),
    source character varying(50),
    title character varying(250),
    link character varying(500),
    description character varying(500),
    status integer,
    created timestamp without time zone,
    is_mail boolean,
    is_mailed boolean DEFAULT false NOT NULL,
    category integer,
    cluster_id character varying(22),
    cluster_score numeric,
    cluster_enabled boolean DEFAULT true,
    source_id integer,
    screenshot_object_id oid,
    screenshot_file_size integer,
    matching_keywords_json text
);


CREATE TABLE item_publication_type (
    item_digest character varying(50) NOT NULL,
    publication_type integer NOT NULL,
    publication_specifics text NOT NULL
);


CREATE SEQUENCE membership_id_seq
    START WITH 210000000
    CACHE 10;

CREATE TABLE membership (
    id integer DEFAULT nextval('membership_id_seq'::regclass) NOT NULL,
    constituent_id integer NOT NULL,
    group_id integer NOT NULL
);

ALTER SEQUENCE membership_id_seq
    OWNED BY membership.id;


CREATE TABLE parsers (
    parsername character varying(50) NOT NULL,
    link_prefix character varying(250),
    link_start character varying(250),
    link_stop character varying(250),
    desc_start character varying(250),
    desc_stop character varying(250),
    title_start character varying(250),
    title_stop character varying(250),
    strip0_start character varying(250),
    strip0_stop character varying(250),
    strip1_start character varying(250),
    strip1_stop character varying(250),
    strip2_start character varying(250),
    strip2_stop character varying(250),
    item_start character varying(250),
    item_stop character varying(250)
);


CREATE SEQUENCE phish_id_seq
    START WITH 220000000
    CACHE 10;

CREATE TABLE phish (
    id integer DEFAULT nextval('phish_id_seq'::regclass) NOT NULL,
    url character varying(250) NOT NULL,
    datetime_added character varying(14),
    datetime_down character varying(14),
    datetime_hash_change character varying(14),
    counter_down integer,
    counter_hash_change integer,
    hash character varying(50),
    reference text,
    campaign text
);

ALTER SEQUENCE phish_id_seq
    OWNED BY phish.id;


CREATE TABLE phish_image (
   phish_id integer, 
   object_id oid, 
   file_size integer, 
   "timestamp" timestamp with time zone DEFAULT NOW() 
);

CREATE TRIGGER t_phish
    BEFORE UPDATE OR DELETE ON phish_image
    FOR EACH ROW EXECUTE PROCEDURE lo_manage(object_id);

CREATE TABLE platform_in_publication (
    publication_id integer NOT NULL,
    softhard_id integer NOT NULL
);

CREATE TABLE product_in_publication (
    publication_id integer NOT NULL,
    softhard_id integer NOT NULL
);


CREATE SEQUENCE publication_id_seq
    START WITH 230000000
    CACHE 10;

CREATE TABLE publication (
    id integer DEFAULT nextval('publication_id_seq'::regclass) NOT NULL,
    contents text,
    approved_on timestamp with time zone,
    created_on timestamp with time zone DEFAULT now() NOT NULL,
    published_on timestamp with time zone,
    replacedby_id integer,
    status integer,
    title text,
    type integer,
    created_by text NOT NULL,
    approved_by text,
    published_by text,
    xml_contents text,
    opened_by text
);

ALTER SEQUENCE publication_id_seq
    OWNED BY publication.id;


CREATE SEQUENCE publication2constituent_id_seq
    START WITH 240000000
    CACHE 10;

CREATE TABLE publication2constituent (
    id integer DEFAULT nextval('publication2constituent_id_seq'::regclass) NOT NULL,
    channel integer,
    constituent_id integer NOT NULL,
    publication_id integer,
    result character varying(50),
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER SEQUENCE publication2constituent_id_seq
    OWNED BY publication2constituent.id;


CREATE SEQUENCE publication_advisory_id_seq
    START WITH 250000000
    CACHE 10;

CREATE TABLE publication_advisory (
    id integer DEFAULT nextval('publication_advisory_id_seq'::regclass) NOT NULL,
    consequences text,
    damage smallint,
    deleted boolean DEFAULT false,
    endofweek_id integer,
    govcertid character varying(100),
    hyperlinks text,
    ids TEXT NOT NULL DEFAULT '',
    probability smallint,
    publication_id integer,
    ques_dmg_infoleak smallint,
    sms_id integer,
    solution text,
    summary text,
    title text,
    update text,
    version character varying(5),
    description text,
    ques_dmg_privesc smallint,
    ques_dmg_remrights smallint,
    ques_dmg_codeexec smallint,
    ques_dmg_dos smallint,
    ques_pro_solution smallint,
    ques_pro_expect smallint,
    ques_pro_exploited smallint,
    ques_pro_userint smallint,
    ques_pro_complexity smallint,
    ques_pro_credent smallint,
    ques_pro_access smallint,
    ques_pro_details smallint,
    ques_pro_exploit smallint,
    ques_pro_standard smallint,
    ques_leg_known smallint,
    ques_leg_exploited smallint,
    ques_leg_simplicity smallint,
    ques_leg_default smallint,
    ques_leg_physic smallint,
    ques_leg_user smallint,
    ques_leg_data smallint,
    ques_leg_dos smallint,
    ques_leg_rights smallint,
    ques_pro_deviation text,
    ques_dmg_deviation text,
    platforms_text text,
    products_text text,
    versions_text text,
    notes text,
    tlpamber text,
    based_on text
);

ALTER SEQUENCE publication_advisory_id_seq
    OWNED BY publication_advisory.id;


CREATE SEQUENCE publication_advisory_forward_id_seq
    START WITH 260000000
    CACHE 10;

CREATE TABLE publication_advisory_forward (
  id integer DEFAULT nextval('publication_advisory_forward_id_seq'::regclass) NOT NULL,
  govcertid character varying(100),
  publication_id integer,
  damage smallint,
  probability smallint,
  deleted boolean DEFAULT false,
  hyperlinks text,
  ids character varying(2000),
  summary text,
  title character varying(255),
  update text,
  version character varying(5),
  platforms_text text,
  products_text text,
  versions_text text,
  notes text,
  tlpamber text,
  source text,
  ques_dmg_infoleak smallint,
  ques_dmg_privesc smallint,
  ques_dmg_remrights smallint,
  ques_dmg_codeexec smallint,
  ques_dmg_dos smallint,
  ques_dmg_deviation text,
  ques_pro_solution smallint,
  ques_pro_expect smallint,
  ques_pro_exploited smallint,
  ques_pro_userint smallint,
  ques_pro_complexity smallint,
  ques_pro_credent smallint,
  ques_pro_access smallint,
  ques_pro_details smallint,
  ques_pro_exploit smallint,
  ques_pro_standard smallint,
  ques_pro_deviation text
);

ALTER SEQUENCE publication_advisory_forward_id_seq
    OWNED BY publication_advisory_forward.id;


CREATE TABLE advisory_forward_damage (
  damage_id integer NOT NULL,
  advisory_forward_id integer NOT NULL
);


CREATE SEQUENCE publication_attachment_id_seq
    START WITH 260000000
    CACHE 10;

CREATE TABLE publication_attachment (
  id integer DEFAULT nextval('publication_attachment_id_seq'::regclass) NOT NULL,
  object_id oid,
  file_size integer,
  publication_id integer,
  mimetype text,
  filename text
);

ALTER SEQUENCE publication_attachment_id_seq
    OWNED BY publication_attachment.id;


CREATE TRIGGER t_publication_attachment
    BEFORE UPDATE OR DELETE ON publication_attachment
    FOR EACH ROW EXECUTE PROCEDURE lo_manage(object_id);


CREATE SEQUENCE publication_endofday_id_seq
    START WITH 270000000
    CACHE 10;

CREATE TABLE publication_endofday (
    id integer DEFAULT nextval('publication_endofday_id_seq'::regclass) NOT NULL,
    publication_id integer,
    handler text,
    first_co_handler text,
    second_co_handler text,
    timeframe_begin timestamp with time zone,
    timeframe_end timestamp with time zone,
    general_info text,
    vulnerabilities_threats text,
    published_advisories text,
    linked_items text,
    incident_info text,
    community_news text,
    media_exposure text,
    tlp_amber text
);

ALTER SEQUENCE publication_endofday_id_seq
    OWNED BY publication_endofday.id;


CREATE SEQUENCE publication_endofweek_id_seq
    START WITH 280000000
    CACHE 10;

CREATE TABLE publication_endofweek (
    id integer DEFAULT nextval('publication_endofweek_id_seq'::regclass) NOT NULL,
    closing text,
    introduction text,
    newondatabank text,
    publication_id integer,
    sent_advisories text,
    newsitem text
);

ALTER SEQUENCE publication_endofweek_id_seq
    OWNED BY publication_endofweek.id;


CREATE SEQUENCE publication_template_id_seq
    START WITH 290000000
    CACHE 10;

CREATE TABLE publication_template (
    id integer DEFAULT nextval('publication_template_id_seq'::regclass) NOT NULL,
    description character varying(100),
    template text NOT NULL,
    title character varying(50) NOT NULL,
    type integer NOT NULL
);

ALTER SEQUENCE publication_template_id_seq
    OWNED BY publication_template.id;


CREATE SEQUENCE publication_type_id_seq
    START WITH 310000000
    CACHE 10;

CREATE TABLE publication_type (
    id integer DEFAULT nextval('publication_type_id_seq'::regclass) NOT NULL,
    description text,
    title text
);

ALTER SEQUENCE publication_type_id_seq
    OWNED BY publication_type.id;


CREATE SEQUENCE role_id_seq
    START WITH 320000000
    CACHE 10;

CREATE TABLE role (
    id integer DEFAULT nextval('role_id_seq'::regclass) NOT NULL,
    name text,
    description text
);

ALTER SEQUENCE role_id_seq
    OWNED BY role.id;


CREATE SEQUENCE role_right_id_seq
    START WITH 330000000
    CACHE 10;

CREATE TABLE role_right (
    id integer DEFAULT nextval('role_right_id_seq'::regclass) NOT NULL,
    entitlement_id integer,
    execute_right boolean,
    particularization text,
    read_right boolean,
    role_id integer,
    write_right boolean
);

ALTER SEQUENCE role_right_id_seq
    OWNED BY role_right.id;


CREATE SEQUENCE search_id_seq
    START WITH 340000000
    CACHE 10;

CREATE TABLE search (
    id integer DEFAULT nextval('search_id_seq'::regclass) NOT NULL,
    description text NOT NULL,
    sortby text,
    keywords text,
    startdate timestamp with time zone,
    enddate timestamp with time zone,
    hitsperpage integer NOT NULL,
    uriw character varying(4),
    is_public boolean DEFAULT false NOT NULL,
    created_by text NOT NULL
);

ALTER SEQUENCE search_id_seq
    OWNED BY search.id;


CREATE TABLE search_category (
    search_id integer NOT NULL,
    category_id integer NOT NULL
);


CREATE TABLE search_source (
    search_id integer NOT NULL,
    sourcename text NOT NULL
);


CREATE TABLE soft_hard_type (
    description text,
    base character varying(2) NOT NULL,
    sub_type character varying(2)
);


CREATE SEQUENCE soft_hard_usage_id_seq
    START WITH 350000000
    CACHE 10;

CREATE TABLE soft_hard_usage (
    usage_id integer DEFAULT nextval('soft_hard_usage_id_seq'::regclass) NOT NULL,
    group_id integer NOT NULL,
    soft_hard_id integer
);

ALTER SEQUENCE soft_hard_usage_id_seq
    OWNED BY soft_hard_usage.usage_id;


CREATE SEQUENCE software_hardware_id_seq
    START WITH 360000000
    CACHE 10;

CREATE TABLE software_hardware (
    id integer DEFAULT nextval('software_hardware_id_seq'::regclass) NOT NULL,
    deleted boolean,
    monitored boolean,
    name text,
    producer text,
    version text,
    type character varying(2),
    cpe_id text
);

ALTER SEQUENCE software_hardware_id_seq
    OWNED BY software_hardware.id;


CREATE SEQUENCE software_hardware_cpe_import_id_seq
    START WITH 370000000
    CACHE 10;

CREATE TABLE software_hardware_cpe_import (
    id integer DEFAULT nextval('software_hardware_cpe_import_id_seq'::regclass) NOT NULL,
    name text,
    producer text,
    version text,
    type character varying(2),
    cpe_id text,
    ok_to_import boolean DEFAULT true
);

ALTER SEQUENCE software_hardware_cpe_import_id_seq
    OWNED BY software_hardware_cpe_import.id;


CREATE SEQUENCE sources_id_seq
    START WITH 380000000
    CACHE 10;

CREATE TABLE sources (
    id integer DEFAULT nextval('sources_id_seq'::regclass) NOT NULL,
    digest text,
    fullurl text,
    host text,
    mailbox text,
    mtbc integer,
    parser text,
    username text,
    password text,
    protocol text,
    port integer,
    sourcename text,
    status text,
    url text,
    checkid boolean,
    enabled boolean DEFAULT true,
    archive_mailbox text,
    delete_mail boolean DEFAULT false,
    category integer,
    language character varying(2),
    clustering_enabled boolean DEFAULT false NOT NULL,
    contains_advisory boolean DEFAULT false,
    advisory_handler text,
    create_advisory boolean,
    deleted boolean DEFAULT false,
    take_screenshot boolean DEFAULT FALSE,
    collector_id integer,
    use_starttls boolean DEFAULT false,
    use_keyword_matching boolean DEFAULT false,
    additional_config text,
    rating integer DEFAULT 50,
    mtbc_random_delay_max integer DEFAULT 0 NOT NULL
);

ALTER SEQUENCE sources_id_seq
    OWNED BY sources.id;


CREATE SEQUENCE statistics_analyze_id_seq
    START WITH 390000000
    CACHE 10;

CREATE TABLE statistics_analyze (
    id integer DEFAULT nextval('statistics_analyze_id_seq'::regclass) NOT NULL,
    pending_count integer,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL
);

ALTER SEQUENCE statistics_analyze_id_seq
    OWNED BY statistics_analyze.id;


CREATE SEQUENCE statistics_assess_id_seq
    START WITH 410000000
    CACHE 10;

CREATE TABLE statistics_assess (
    id integer DEFAULT nextval('statistics_assess_id_seq'::regclass) NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now(),
    tag_cloud text
);

ALTER SEQUENCE statistics_assess_id_seq
    OWNED BY statistics_assess.id;


CREATE SEQUENCE statistics_collector_id_seq
    START WITH 420000000
    CACHE 10;

CREATE TABLE statistics_collector (
    id integer DEFAULT nextval('statistics_collector_id_seq'::regclass) NOT NULL,
    started timestamp with time zone DEFAULT now() NOT NULL,
    finished timestamp with time zone,
    collector_id integer,
    status text
);

ALTER SEQUENCE statistics_collector_id_seq
    OWNED BY statistics_collector.id;


CREATE SEQUENCE statistics_database_id_seq
    START WITH 430000000
    CACHE 10;

CREATE TABLE statistics_database (
    id integer DEFAULT nextval('statistics_database_id_seq'::regclass) NOT NULL,
    items_count integer,
    "timestamp" timestamp with time zone DEFAULT now()
);

ALTER SEQUENCE statistics_database_id_seq
    OWNED BY statistics_database.id;


CREATE TABLE statsimages (
    digest text,
    description text,
    link text,
    source text,
    category text,
    object_id oid,
    file_size integer
);

CREATE TRIGGER t_statsimage
    BEFORE UPDATE OR DELETE ON statsimages
    FOR EACH ROW EXECUTE PROCEDURE lo_manage(object_id);


CREATE SEQUENCE tag_id_seq
    START WITH 440000000
    CACHE 10;

CREATE TABLE tag (
    id integer DEFAULT nextval('tag_id_seq'::regclass) NOT NULL,
    name text NOT NULL
);

ALTER SEQUENCE tag_id_seq
    OWNED BY tag.id;


CREATE TABLE tag_item (
    tag_id integer NOT NULL,
    item_id text NOT NULL,
    item_table_name text NOT NULL,
    dossier_id integer
);

CREATE TABLE type_publication_constituent (
    constituent_type_id integer NOT NULL,
    publication_type_id integer NOT NULL
);


CREATE SEQUENCE user_action_id_seq
    START WITH 450000000
    CACHE 10;

CREATE TABLE user_action (
    id integer DEFAULT nextval('user_action_id_seq'::regclass) NOT NULL,
    date timestamp without time zone DEFAULT now(),
    username text,
    entitlement text,
    action text,
    comment text,
    dossier_id integer
);

ALTER SEQUENCE user_action_id_seq
    OWNED BY user_action.id;


CREATE SEQUENCE user_role_id_seq
    START WITH 460000000
    CACHE 10;

CREATE TABLE user_role (
    id integer DEFAULT nextval('user_role_id_seq'::regclass) NOT NULL,
    role_id integer,
    username character varying(50)
);

ALTER SEQUENCE user_role_id_seq
    OWNED BY user_role.id;


CREATE TABLE users (
    username text NOT NULL,
    password text,
    uriw character varying(4),
    search text,
    anasearch text,
    anastatus text,
    mailfrom_sender text,
    mailfrom_email text,
    lmh character varying(4),
    statstype text,
    hitsperpage integer,
    fullname text,
    disabled boolean DEFAULT false,
    datestart date DEFAULT now(),
    datestop date DEFAULT now(),
    assess_orderby text,
    category integer,
    source text,
    assess_autorefresh boolean DEFAULT true NOT NULL
);

-- TODO: is view still in use?
CREATE VIEW versions AS
    SELECT ov.id, ov.replacedby_id, ov.approved_on, ov.created_on FROM publication uo, publication ov WHERE (uo.id = ov.replacedby_id);

CREATE SEQUENCE dossier_id_seq
    START WITH 470000000
    CACHE 10;
    
CREATE TABLE dossier (
   id integer DEFAULT nextval('dossier_id_seq'::regclass) NOT NULL,
   status integer NOT NULL DEFAULT 1, 
   description text NOT NULL, 
   reminder_interval interval DEFAULT '1 mon'::interval,
   reminder_account text
);

ALTER SEQUENCE dossier_id_seq
    OWNED BY dossier.id;


CREATE TABLE dossier_contributor (
   username text NOT NULL, 
   dossier_id integer NOT NULL, 
   role_description text, 
   is_owner boolean NOT NULL DEFAULT TRUE 
);

CREATE SEQUENCE dossier_note_id_seq
    START WITH 480000000
    CACHE 10;

CREATE TABLE dossier_note (
   id integer DEFAULT nextval('dossier_note_id_seq'::regclass) NOT NULL, 
   text text, 
   created timestamp with time zone DEFAULT now(),
   dossier_item_id integer,
   created_by text
);

ALTER SEQUENCE dossier_note_id_seq
    OWNED BY dossier_note.id;


CREATE SEQUENCE dossier_note_url_id_seq
    START WITH 490000000
    CACHE 10;

CREATE TABLE dossier_note_url (
   id integer DEFAULT nextval('dossier_note_url_id_seq'::regclass) NOT NULL, 
   url text NOT NULL, 
   description text, 
   note_id integer NOT NULL,
   created timestamp with time zone DEFAULT now()
);

ALTER SEQUENCE dossier_note_url_id_seq
    OWNED BY dossier_note_url.id;


CREATE SEQUENCE dossier_note_ticket_id_seq
    START WITH 510000000
    CACHE 10;

CREATE TABLE dossier_note_ticket (
   id integer DEFAULT nextval('dossier_note_ticket_id_seq'::regclass) NOT NULL,
   reference integer NOT NULL,
   note_id integer NOT NULL,
   created timestamp with time zone DEFAULT now()
);

ALTER SEQUENCE dossier_note_ticket_id_seq
    OWNED BY dossier_note_ticket.id;


CREATE SEQUENCE dossier_note_file_id_seq
    START WITH 520000000
    CACHE 10;

CREATE TABLE dossier_note_file (
   id integer DEFAULT nextval('dossier_note_file_id_seq'::regclass) NOT NULL,
   size integer NOT NULL,
   name text NOT NULL,
   object_id oid NOT NULL,
   note_id integer NOT NULL,
   created timestamp with time zone DEFAULT now(),
   mime text NOT NULL
);

ALTER SEQUENCE dossier_note_file_id_seq
    OWNED BY dossier_note_file.id;


CREATE TRIGGER t_dossier_file
    BEFORE UPDATE OR DELETE ON dossier_note_file
    FOR EACH ROW EXECUTE PROCEDURE lo_manage(object_id);

CREATE SEQUENCE dossier_item_id_seq
    START WITH 530000000
    CACHE 10;

CREATE TABLE dossier_item (
   id integer DEFAULT nextval('dossier_item_id_seq'::regclass) NOT NULL,
   event_timestamp timestamp with time zone DEFAULT now(),
   classification integer,
   status integer,
   assess_id text,
   analysis_id character varying(8),
   note_id integer,
   dossier_id integer NOT NULL,
   advisory_id integer,
   eos_id integer,
   eow_id integer,
   advisory_forward_id integer,
   eod_id integer
);

ALTER SEQUENCE dossier_item_id_seq
    OWNED BY dossier_item.id;


CREATE SEQUENCE wordlist_id_seq
    START WITH 540000000
    CACHE 10;

CREATE TABLE wordlist (
    id integer DEFAULT nextval('wordlist_id_seq'::regclass) NOT NULL,
    description text,
    words_json text
);

ALTER SEQUENCE wordlist_id_seq
    OWNED BY wordlist.id;


CREATE SEQUENCE source_wordlist_id_seq
    START WITH 550000000
    CACHE 10;

CREATE TABLE source_wordlist (
  id integer DEFAULT nextval('source_wordlist_id_seq'::regclass) NOT NULL,
  source_id integer,
  wordlist_id integer,
  and_wordlist_id integer
);

ALTER SEQUENCE source_wordlist_id_seq
    OWNED BY source_wordlist.id;


CREATE SEQUENCE feeddigest_id_seq
    START WITH 560000000
    CACHE 10;

CREATE TABLE feeddigest (
  id integer DEFAULT nextval('feeddigest_id_seq'::regclass) NOT NULL,
  url text NOT NULL,
  to_address text NOT NULL,
  sending_hour integer NOT NULL,
  template_header text,
  template_feed_item text,
  template_footer text,
  strip_html boolean DEFAULT true,
  last_sent_timestamp timestamp with time zone
);

ALTER SEQUENCE feeddigest_id_seq
    OWNED BY feeddigest.id;


CREATE SEQUENCE cve_template_id_seq
    START WITH 570000000
    CACHE 10;
    
CREATE TABLE cve_template (
   id integer DEFAULT nextval('cve_template_id_seq'::regclass) NOT NULL, 
   description text NOT NULL, 
   template text
);

ALTER SEQUENCE cve_template_id_seq
    OWNED BY cve_template.id;


CREATE SEQUENCE report_todo_id_seq
    START WITH 580000000
    CACHE 10;

CREATE TABLE report_todo (
  id integer DEFAULT nextval('report_todo_id_seq'::regclass) NOT NULL,
  due_date timestamp with time zone,
  description text,
  notes text,
  done_status integer DEFAULT 0
);

ALTER SEQUENCE report_todo_id_seq
    OWNED BY report_todo.id;


CREATE SEQUENCE report_special_interest_id_seq
    START WITH 590000000
    CACHE 10;

CREATE TABLE report_special_interest (
  id integer DEFAULT nextval('report_special_interest_id_seq'::regclass) NOT NULL,
  requestor text,
  topic text,
  action text,
  date_start timestamp with time zone,
  date_end timestamp with time zone,
  timestamp_reminder_sent timestamp with time zone
);

ALTER SEQUENCE report_special_interest_id_seq
    OWNED BY report_special_interest.id;


CREATE SEQUENCE report_contact_log_id_seq
    START WITH 610000000
    CACHE 10;

CREATE TABLE report_contact_log (
  id integer DEFAULT nextval('report_contact_log_id_seq'::regclass) NOT NULL,
  type integer,
  contact_details text,
  created timestamp with time zone DEFAULT now(),
  notes text
);

ALTER SEQUENCE report_contact_log_id_seq
    OWNED BY report_contact_log.id;


CREATE SEQUENCE report_incident_log_id_seq
    START WITH 620000000
    CACHE 10;

CREATE TABLE report_incident_log (
  id integer DEFAULT nextval('report_incident_log_id_seq'::regclass) NOT NULL,
  description text,
  owner text,
  ticket_number text,
  created timestamp with time zone DEFAULT now(),
  status integer,
  constituent text
);

ALTER SEQUENCE report_incident_log_id_seq
    OWNED BY report_incident_log.id;


CREATE SEQUENCE publication_endofshift_id_seq
    START WITH 630000000
    CACHE 10;

CREATE TABLE publication_endofshift (
  id integer DEFAULT nextval('publication_endofshift_id_seq'::regclass),
  notes text,
  publication_id integer,
  handler text,
  timeframe_begin timestamp with time zone,
  timeframe_end timestamp with time zone,
  todo text,
  contact_log text,
  incident_log text,
  special_interest text,
  done text
);

ALTER SEQUENCE publication_endofshift_id_seq
    OWNED BY publication_endofshift.id;


CREATE TABLE access_token (
   username text NOT NULL, 
   token text NOT NULL, 
   created timestamp with time zone DEFAULT NOW(), 
   last_access timestamp with time zone DEFAULT NOW(),
   expiry_time integer
);

CREATE SEQUENCE stream_id_seq
    START WITH 640000000
    CACHE 10;

CREATE TABLE stream (
   id integer DEFAULT nextval('stream_id_seq'::regclass) NOT NULL,
   description text,
   displays_json text,
   transition_time integer
);

ALTER SEQUENCE stream_id_seq
    OWNED BY stream.id;


CREATE TABLE stream_role (
   stream_id integer,
   role_id integer
);


CREATE SEQUENCE announcement_id_seq
    START WITH 650000000
    CACHE 10;

CREATE TABLE announcement (
   id integer DEFAULT nextval('announcement_id_seq'::regclass) NOT NULL, 
   title text, 
   is_enabled boolean DEFAULT TRUE, 
   type text NOT NULL, 
   content_json text,
   created timestamp with time zone DEFAULT now()
);

ALTER SEQUENCE announcement_id_seq
    OWNED BY announcement.id;

ALTER TABLE ONLY announcement ADD CONSTRAINT pk_announcement PRIMARY KEY (id);


CREATE TABLE individual_roles (
    individual_id      integer NOT NULL,
    individual_role_id integer NOT NULL,
    PRIMARY KEY (individual_id, individual_role_id),
    FOREIGN KEY (individual_id)      REFERENCES constituent_individual(id),
    FOREIGN KEY (individual_role_id) REFERENCES constituent_role(id)
);


ALTER TABLE ONLY stream_role ADD CONSTRAINT pk_stream_role PRIMARY KEY (stream_id, role_id);

ALTER TABLE ONLY stream ADD CONSTRAINT pk_stream_id PRIMARY KEY (id);

ALTER TABLE ONLY access_token ADD CONSTRAINT pk_access_token PRIMARY KEY (token);

ALTER TABLE ONLY publication_endofshift ADD CONSTRAINT pk_publication_endofshift PRIMARY KEY(id);

ALTER TABLE ONLY report_incident_log ADD CONSTRAINT pk_report_incident_log PRIMARY KEY(id);

ALTER TABLE ONLY report_contact_log ADD CONSTRAINT pk_report_contact_log PRIMARY KEY(id);

ALTER TABLE ONLY report_special_interest ADD CONSTRAINT pk_report_special_interest PRIMARY KEY(id);

ALTER TABLE ONLY report_todo ADD CONSTRAINT pk_report_todo PRIMARY KEY(id);

ALTER TABLE ONLY cve_template ADD CONSTRAINT pk_cve_template PRIMARY KEY(id);

ALTER TABLE ONLY feeddigest ADD CONSTRAINT pk_feed_digest PRIMARY KEY (id);

ALTER TABLE ONLY role_right ADD CONSTRAINT "Role_id_Entitlement_id" UNIQUE (entitlement_id, role_id);

ALTER TABLE ONLY collector ADD CONSTRAINT collector_pk PRIMARY KEY (id);

ALTER TABLE ONLY advisory_damage ADD CONSTRAINT advisory_damage_pkey PRIMARY KEY (advisory_id, damage_id);

ALTER TABLE ONLY analysis_publication ADD CONSTRAINT analysis_publication_pk PRIMARY KEY (analysis_id, publication_id);

ALTER TABLE ONLY constituent_group ADD CONSTRAINT constituent_group_pkey PRIMARY KEY (id);

ALTER TABLE ONLY constituent_publication ADD CONSTRAINT constituent_publication_pkey PRIMARY KEY (id);

ALTER TABLE ONLY constituent_type ADD CONSTRAINT constituent_type_pkey PRIMARY KEY (id);

ALTER TABLE ONLY software_hardware ADD CONSTRAINT cpe_unique UNIQUE (cpe_id);

ALTER TABLE ONLY damage_description ADD CONSTRAINT damage_description_pkey PRIMARY KEY (id);

ALTER TABLE ONLY download_files ADD CONSTRAINT download_files_pkey PRIMARY KEY (file_url);

ALTER TABLE ONLY email_item_archive ADD CONSTRAINT email_item_archive_pkey PRIMARY KEY (id);

ALTER TABLE ONLY email_item ADD CONSTRAINT email_item_pkey PRIMARY KEY (id);

ALTER TABLE ONLY entitlement ADD CONSTRAINT entitlement_pkey PRIMARY KEY (id);

ALTER TABLE ONLY analysis ADD CONSTRAINT id PRIMARY KEY (id);

ALTER TABLE ONLY identifier_description ADD CONSTRAINT identifier_description_pkey PRIMARY KEY (identifier);

ALTER TABLE ONLY item_analysis ADD CONSTRAINT item_analysis_pk PRIMARY KEY (item_id, analysis_id);

ALTER TABLE ONLY membership ADD CONSTRAINT membership_pkey PRIMARY KEY (id);

ALTER TABLE ONLY parsers ADD CONSTRAINT parsers_pkey PRIMARY KEY (parsername);

ALTER TABLE ONLY import_photo ADD CONSTRAINT ph_import_photo PRIMARY KEY (id);

ALTER TABLE ONLY import_photo_software_hardware ADD CONSTRAINT ph_import_photo_sh PRIMARY KEY (photo_id, import_sh);

ALTER TABLE phish ADD CONSTRAINT phish_id_pk PRIMARY KEY (id);

ALTER TABLE phish_image ADD CONSTRAINT phish_images_pk PRIMARY KEY (phish_id, object_id);

ALTER TABLE ONLY calling_list ADD CONSTRAINT pk_calling_list PRIMARY KEY (id);

ALTER TABLE ONLY category ADD CONSTRAINT pk_category PRIMARY KEY (id);

ALTER TABLE ONLY checkstatus ADD CONSTRAINT pk_checkstatus PRIMARY KEY (source);

ALTER TABLE ONLY cluster ADD CONSTRAINT pk_cluster PRIMARY KEY (id);

ALTER TABLE ONLY cpe_cve ADD CONSTRAINT pk_cpe_cve PRIMARY KEY (cve_id, cpe_id);

ALTER TABLE ONLY cpe_files ADD CONSTRAINT pk_cpe_files PRIMARY KEY (filename);

ALTER TABLE ONLY publication_endofweek ADD CONSTRAINT pk_endofweek PRIMARY KEY (id);

ALTER TABLE ONLY errors ADD CONSTRAINT pk_errors_id PRIMARY KEY (id);

ALTER TABLE ONLY identifier ADD CONSTRAINT pk_identifier_digest PRIMARY KEY (identifier, digest);

ALTER TABLE ONLY import_issue ADD CONSTRAINT pk_import_issue PRIMARY KEY (id);

ALTER TABLE ONLY import_software_hardware ADD CONSTRAINT pk_import_software_hardware PRIMARY KEY (id);

ALTER TABLE ONLY item_publication_type ADD CONSTRAINT pk_item_publication_type PRIMARY KEY (item_digest, publication_type, publication_specifics);

ALTER TABLE ONLY platform_in_publication ADD CONSTRAINT pk_platform_in_publication PRIMARY KEY (publication_id, softhard_id);

ALTER TABLE ONLY product_in_publication ADD CONSTRAINT pk_product_in_publication PRIMARY KEY (publication_id, softhard_id);

ALTER TABLE ONLY publication_endofday ADD CONSTRAINT pk_publication_endofday PRIMARY KEY (id);

ALTER TABLE ONLY search ADD CONSTRAINT pk_search PRIMARY KEY (id);

ALTER TABLE ONLY search_category ADD CONSTRAINT pk_search_category PRIMARY KEY (search_id, category_id);

ALTER TABLE ONLY search_source ADD CONSTRAINT pk_search_source PRIMARY KEY (search_id, sourcename);

ALTER TABLE ONLY tag_item ADD CONSTRAINT pk_tag_item PRIMARY KEY (tag_id, item_id, item_table_name);

ALTER TABLE ONLY publication2constituent ADD CONSTRAINT publication2constituent_pk PRIMARY KEY (id);

ALTER TABLE ONLY publication_advisory ADD CONSTRAINT publication_advisory_pkey PRIMARY KEY (id);

ALTER TABLE ONLY publication_advisory_forward ADD CONSTRAINT pk_publication_advisory_forward PRIMARY KEY (id);

ALTER TABLE ONLY publication ADD CONSTRAINT publication_pk PRIMARY KEY (id);

ALTER TABLE ONLY publication_template ADD CONSTRAINT publication_template_pkey PRIMARY KEY (id);

ALTER TABLE ONLY publication_type ADD CONSTRAINT publication_type_pkey PRIMARY KEY (id);

ALTER TABLE ONLY role ADD CONSTRAINT role_pkey PRIMARY KEY (id);

ALTER TABLE ONLY role_right ADD CONSTRAINT "role_right_ID" PRIMARY KEY (id);

ALTER TABLE ONLY item ADD CONSTRAINT rss_pkey PRIMARY KEY (digest);

ALTER TABLE ONLY soft_hard_type ADD CONSTRAINT soft_hard_type_pkey PRIMARY KEY (base);

ALTER TABLE ONLY soft_hard_usage ADD CONSTRAINT soft_hard_usage_pkey PRIMARY KEY (usage_id);

ALTER TABLE ONLY software_hardware_cpe_import ADD CONSTRAINT software_hardware_cpe_import_pkey PRIMARY KEY (id);

ALTER TABLE ONLY software_hardware ADD CONSTRAINT software_hardware_pkey PRIMARY KEY (id);

ALTER TABLE ONLY sources ADD CONSTRAINT sources_pkey PRIMARY KEY (id);

ALTER TABLE ONLY statistics_analyze ADD CONSTRAINT statistics_analyze_pk PRIMARY KEY (id);

ALTER TABLE ONLY statistics_assess ADD CONSTRAINT statistics_assess_pk PRIMARY KEY (id);

ALTER TABLE ONLY statistics_collector ADD CONSTRAINT statistics_collector_pk PRIMARY KEY (id);

ALTER TABLE ONLY statistics_database ADD CONSTRAINT statistics_database_pk PRIMARY KEY (id);

ALTER TABLE ONLY tag ADD CONSTRAINT tag_id PRIMARY KEY (id);

ALTER TABLE ONLY type_publication_constituent ADD CONSTRAINT type_publication_constituent_pk PRIMARY KEY (constituent_type_id, publication_type_id);

ALTER TABLE ONLY calling_list ADD CONSTRAINT un_publicationid_groupid UNIQUE (publication_id, group_id);

ALTER TABLE ONLY cluster ADD CONSTRAINT unique_cluster UNIQUE (language, category_id);

ALTER TABLE ONLY user_action ADD CONSTRAINT user_action_pkey PRIMARY KEY (id);

ALTER TABLE ONLY user_role ADD CONSTRAINT user_role_pkey PRIMARY KEY (id);

ALTER TABLE ONLY users ADD CONSTRAINT users_pkey PRIMARY KEY (username);

ALTER TABLE ONLY dossier ADD CONSTRAINT pk_dossier PRIMARY KEY (id);

ALTER TABLE ONLY dossier_contributor ADD CONSTRAINT pk_dossier_contributor PRIMARY KEY (username, dossier_id);

ALTER TABLE ONLY dossier_note ADD CONSTRAINT pk_dossier_note PRIMARY KEY (id);

ALTER TABLE ONLY dossier_note_url ADD CONSTRAINT pk_dossier_note_url PRIMARY KEY (id);

ALTER TABLE ONLY dossier_note_ticket ADD CONSTRAINT pk_dossier_note_ticket PRIMARY KEY (id);

ALTER TABLE ONLY dossier_note_file ADD CONSTRAINT pk_dossier_note_file PRIMARY KEY (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT pk_dossier_item PRIMARY KEY (id);

ALTER TABLE ONLY advisory_forward_damage ADD CONSTRAINT pk_advisory_forward_damage PRIMARY KEY (damage_id, advisory_forward_id);

ALTER TABLE ONLY wordlist ADD CONSTRAINT pk_wordslist PRIMARY KEY (id);

ALTER TABLE ONLY source_wordlist ADD CONSTRAINT pk_source_wordlist PRIMARY KEY (id);

CREATE INDEX base_subtype ON soft_hard_type USING btree (sub_type, base);

CREATE INDEX "cpeId" ON software_hardware USING btree (cpe_id);

CREATE INDEX ent ON user_action USING btree (entitlement);

CREATE UNIQUE INDEX entitlement_role_id ON role_right USING btree (entitlement_id, role_id);

CREATE INDEX fki_dossier_item_publication_advisory_forward ON dossier_item(advisory_forward_id);

CREATE INDEX fki_sources_parser ON sources USING btree (parser);

CREATE INDEX fki_advisory_handler ON sources USING btree (advisory_handler);

CREATE INDEX fki_analysis_id_fk ON item_analysis USING btree (analysis_id);

CREATE INDEX fki_category_item ON item USING btree (category);

CREATE INDEX fki_category_item_archive ON item_archive USING btree (category);

CREATE INDEX fki_category_sources ON sources USING btree (category);

CREATE INDEX fki_sources_collector_fk ON sources(collector_id);

CREATE INDEX fki_category_users ON users USING btree (category);

CREATE INDEX fki_constituent_type ON constituent_group USING btree (constituent_type);

CREATE INDEX fki_followup_issue_nr ON import_issue USING btree (followup_on_issue_nr);

CREATE INDEX fki_imported_by ON import_photo USING btree (imported_by);

CREATE INDEX fki_issue_nr ON import_software_hardware USING btree (issue_nr);

CREATE INDEX fki_joined_into_analysis ON analysis USING btree (joined_into_analysis);

CREATE INDEX fki_opened_by ON analysis USING btree (opened_by);

CREATE INDEX fki_opened_by_users ON publication USING btree (opened_by);

CREATE INDEX fki_owned_by ON analysis USING btree (owned_by);

CREATE INDEX fki_publication_id ON publication USING btree (replacedby_id);

CREATE INDEX fki_publication_id_advisory ON publication_advisory USING btree (publication_id);

CREATE INDEX fki_resolved_by ON import_issue USING btree (resolved_by);

CREATE INDEX fki_role_id ON user_role USING btree (role_id);

CREATE INDEX fki_search_user ON search USING btree (created_by);

CREATE INDEX fki_software_hardware_id_issue ON import_issue USING btree (soft_hard_id);

CREATE INDEX fki_source_id ON item USING btree (source_id);

CREATE INDEX fki_username ON user_role USING btree (username);

CREATE INDEX fki_users_publishedby ON publication USING btree (published_by);

CREATE INDEX fki_users_username ON publication USING btree (approved_by);

CREATE INDEX fki_statistics_collector_fk ON statistics_collector(collector_id);

CREATE INDEX fki_username_useraction ON user_action(username);

CREATE INDEX fki_user_action_dossier_id ON user_action(dossier_id);

CREATE UNIQUE INDEX identifier_index ON identifier_description USING btree (identifier);

CREATE INDEX idx_category ON item USING btree (category);

CREATE INDEX idx_created ON item_archive USING btree (created);

CREATE INDEX idx_cveid ON identifier USING btree (identifier);

CREATE INDEX idx_cveid2 ON identifier_archive USING btree (identifier);

CREATE INDEX idx_digest ON item USING btree (digest);

CREATE INDEX idx_digest2 ON identifier USING btree (digest);

CREATE INDEX idx_digest3 ON item_archive USING btree (digest);

CREATE INDEX idx_digest4 ON identifier_archive USING btree (digest);

CREATE INDEX item_digest_index ON item_publication_type USING btree (item_digest);

CREATE INDEX name_producer_type ON software_hardware USING btree (producer, name, type);

CREATE UNIQUE INDEX u_source_id_wordlist_id_and_null ON source_wordlist (source_id, wordlist_id) WHERE and_wordlist_id IS NULL;

CREATE INDEX errors_time_of_error_idx ON errors (time_of_error);

ALTER TABLE ONLY stream_role ADD CONSTRAINT fk_stream_role_stream_id FOREIGN KEY (stream_id) REFERENCES stream (id);

ALTER TABLE ONLY stream_role ADD CONSTRAINT fk_stream_role_role_id FOREIGN KEY (role_id) REFERENCES role (id);

ALTER TABLE ONLY access_token ADD CONSTRAINT fk_access_token_username FOREIGN KEY (username) REFERENCES users (username);

ALTER TABLE ONLY publication_endofshift ADD CONSTRAINT fk_publication_endofshift_publication FOREIGN KEY (publication_id) REFERENCES publication (id);

ALTER TABLE ONLY publication_endofshift ADD CONSTRAINT fk_publication_endofshift_users FOREIGN KEY (handler) REFERENCES users (username);

ALTER TABLE ONLY report_incident_log ADD CONSTRAINT fk_incident_log_users FOREIGN KEY (owner) REFERENCES users (username);

ALTER TABLE ONLY item ADD CONSTRAINT fk_source_id FOREIGN KEY (source_id) REFERENCES sources(id);

ALTER TABLE ONLY analysis_publication ADD CONSTRAINT analysis_id FOREIGN KEY (analysis_id) REFERENCES analysis(id);

ALTER TABLE ONLY item_analysis ADD CONSTRAINT analysis_id_fk FOREIGN KEY (analysis_id) REFERENCES analysis(id);

ALTER TABLE ONLY soft_hard_type ADD CONSTRAINT base FOREIGN KEY (sub_type) REFERENCES soft_hard_type(base);

ALTER TABLE ONLY publication2constituent ADD CONSTRAINT constituent_fk FOREIGN KEY (constituent_id) REFERENCES constituent_individual(id);

ALTER TABLE ONLY constituent_group ADD CONSTRAINT constituent_group_constituent_type_fkey FOREIGN KEY (constituent_type) REFERENCES constituent_type(id);

ALTER TABLE ONLY constituent_individual ADD CONSTRAINT constituent_individual_role_fkey FOREIGN KEY (role) REFERENCES constituent_role(id);

ALTER TABLE ONLY constituent_publication ADD CONSTRAINT constituent_publication_constituent_id_fkey FOREIGN KEY (constituent_id) REFERENCES constituent_individual(id);

ALTER TABLE ONLY constituent_publication ADD CONSTRAINT constituent_publication_type_id_fkey FOREIGN KEY (type_id) REFERENCES publication_type(id);

ALTER TABLE ONLY advisory_damage ADD CONSTRAINT damage_description_damage_id_fkey FOREIGN KEY (damage_id) REFERENCES damage_description(id);

ALTER TABLE ONLY role_right ADD CONSTRAINT entitlement FOREIGN KEY (entitlement_id) REFERENCES entitlement(id);

ALTER TABLE ONLY sources ADD CONSTRAINT fk_advisory_handler FOREIGN KEY (advisory_handler) REFERENCES users(username);

ALTER TABLE ONLY sources ADD CONSTRAINT sources_collector_fk FOREIGN KEY (collector_id) REFERENCES collector (id);

ALTER TABLE ONLY item ADD CONSTRAINT fk_category FOREIGN KEY (category) REFERENCES category(id);

ALTER TABLE ONLY item_archive ADD CONSTRAINT fk_category FOREIGN KEY (category) REFERENCES category(id);

ALTER TABLE ONLY sources ADD CONSTRAINT fk_category FOREIGN KEY (category) REFERENCES category(id);

ALTER TABLE ONLY users ADD CONSTRAINT fk_category FOREIGN KEY (category) REFERENCES category(id);

ALTER TABLE ONLY search_category ADD CONSTRAINT fk_category FOREIGN KEY (category_id) REFERENCES category(id);

ALTER TABLE ONLY cluster ADD CONSTRAINT fk_category FOREIGN KEY (category_id) REFERENCES category(id);

ALTER TABLE ONLY calling_list ADD CONSTRAINT fk_constituen_group FOREIGN KEY (group_id) REFERENCES constituent_group(id);

ALTER TABLE ONLY publication_endofday ADD CONSTRAINT fk_first_co_handler FOREIGN KEY (first_co_handler) REFERENCES users(username);

ALTER TABLE ONLY import_issue ADD CONSTRAINT fk_followup_issue_nr FOREIGN KEY (followup_on_issue_nr) REFERENCES import_issue(id);

ALTER TABLE ONLY publication_endofday ADD CONSTRAINT fk_handler FOREIGN KEY (handler) REFERENCES users(username);

ALTER TABLE ONLY import_photo ADD CONSTRAINT fk_import_group_id FOREIGN KEY (group_id) REFERENCES constituent_group(id);

ALTER TABLE ONLY import_photo_software_hardware ADD CONSTRAINT fk_import_photo FOREIGN KEY (photo_id) REFERENCES import_photo(id);

ALTER TABLE ONLY import_photo_software_hardware ADD CONSTRAINT fk_import_sh2 FOREIGN KEY (import_sh) REFERENCES import_software_hardware(id);

ALTER TABLE ONLY import_photo ADD CONSTRAINT fk_imported_by FOREIGN KEY (imported_by) REFERENCES users(username);

ALTER TABLE ONLY import_software_hardware ADD CONSTRAINT fk_issue_nr FOREIGN KEY (issue_nr) REFERENCES import_issue(id);

ALTER TABLE ONLY item_publication_type ADD CONSTRAINT fk_item_digest FOREIGN KEY (item_digest) REFERENCES item(digest);

ALTER TABLE ONLY analysis ADD CONSTRAINT fk_joined_into_analysis FOREIGN KEY (joined_into_analysis) REFERENCES analysis(id);

ALTER TABLE ONLY analysis ADD CONSTRAINT fk_opened_by FOREIGN KEY (opened_by) REFERENCES users(username);

ALTER TABLE ONLY publication ADD CONSTRAINT fk_opened_by_users FOREIGN KEY (opened_by) REFERENCES users(username);

ALTER TABLE ONLY analysis ADD CONSTRAINT fk_owned_by FOREIGN KEY (owned_by) REFERENCES users(username);

ALTER TABLE ONLY platform_in_publication ADD CONSTRAINT fk_platform_in_publication FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY platform_in_publication ADD CONSTRAINT fk_platform_in_publication_2 FOREIGN KEY (softhard_id) REFERENCES software_hardware(id);

ALTER TABLE ONLY calling_list ADD CONSTRAINT fk_publication FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY product_in_publication ADD CONSTRAINT fk_publication_id FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY publication_advisory ADD CONSTRAINT fk_publication_id FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY publication_endofweek ADD CONSTRAINT fk_publication_id FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY publication_endofday ADD CONSTRAINT fk_publication_id FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY item_publication_type ADD CONSTRAINT fk_publication_type FOREIGN KEY (publication_type) REFERENCES publication_type(id);

ALTER TABLE ONLY import_issue ADD CONSTRAINT fk_resolved_by FOREIGN KEY (resolved_by) REFERENCES users(username);

ALTER TABLE ONLY search_source ADD CONSTRAINT fk_search FOREIGN KEY (search_id) REFERENCES search(id);

ALTER TABLE ONLY search_category ADD CONSTRAINT fk_search FOREIGN KEY (search_id) REFERENCES search(id);

ALTER TABLE ONLY search ADD CONSTRAINT fk_search_user FOREIGN KEY (created_by) REFERENCES users(username);

ALTER TABLE ONLY publication_endofday ADD CONSTRAINT fk_second_co_handler FOREIGN KEY (second_co_handler) REFERENCES users(username);

ALTER TABLE ONLY product_in_publication ADD CONSTRAINT fk_software_hardware_id FOREIGN KEY (softhard_id) REFERENCES software_hardware(id);

ALTER TABLE ONLY import_issue ADD CONSTRAINT fk_software_hardware_id_issue FOREIGN KEY (soft_hard_id) REFERENCES software_hardware(id);

ALTER TABLE ONLY tag_item ADD CONSTRAINT fk_tag_item FOREIGN KEY (tag_id) REFERENCES tag(id);

ALTER TABLE ONLY calling_list ADD CONSTRAINT fk_users FOREIGN KEY (locked_by) REFERENCES users(username);

ALTER TABLE ONLY publication ADD CONSTRAINT fk_users_approvedby FOREIGN KEY (approved_by) REFERENCES users(username);

ALTER TABLE ONLY publication ADD CONSTRAINT fk_users_publishedby FOREIGN KEY (published_by) REFERENCES users(username);

ALTER TABLE ONLY item_analysis ADD CONSTRAINT item_id_fk FOREIGN KEY (item_id) REFERENCES item(digest);

ALTER TABLE ONLY membership ADD CONSTRAINT membership_constituent_id_fkey FOREIGN KEY (constituent_id) REFERENCES constituent_individual(id);

ALTER TABLE ONLY membership ADD CONSTRAINT membership_group_id_fkey FOREIGN KEY (group_id) REFERENCES constituent_group(id);

ALTER TABLE ONLY advisory_damage ADD CONSTRAINT publication_advisory_advisory_id_fkey FOREIGN KEY (advisory_id) REFERENCES publication_advisory(id);

ALTER TABLE ONLY publication2constituent ADD CONSTRAINT publication_fk FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY publication ADD CONSTRAINT publication_id FOREIGN KEY (replacedby_id) REFERENCES publication(id);

ALTER TABLE ONLY analysis_publication ADD CONSTRAINT publication_id FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE ONLY publication ADD CONSTRAINT publication_type_id FOREIGN KEY (type) REFERENCES publication_type(id);

ALTER TABLE ONLY user_role ADD CONSTRAINT role_id FOREIGN KEY (role_id) REFERENCES role(id);

ALTER TABLE ONLY role_right ADD CONSTRAINT role_id FOREIGN KEY (role_id) REFERENCES role(id);

ALTER TABLE ONLY soft_hard_usage ADD CONSTRAINT soft_hard_usage_group_id_fkey FOREIGN KEY (group_id) REFERENCES constituent_group(id);

ALTER TABLE ONLY soft_hard_usage ADD CONSTRAINT soft_hard_usage_soft_hard_id_fkey FOREIGN KEY (soft_hard_id) REFERENCES software_hardware(id);

ALTER TABLE ONLY sources ADD CONSTRAINT sources_parser_fkey FOREIGN KEY (parser) REFERENCES parsers(parsername);

ALTER TABLE ONLY publication_template ADD CONSTRAINT type FOREIGN KEY (type) REFERENCES publication_type(id);

ALTER TABLE ONLY software_hardware ADD CONSTRAINT type FOREIGN KEY (type) REFERENCES soft_hard_type(base);

ALTER TABLE ONLY user_role ADD CONSTRAINT username FOREIGN KEY (username) REFERENCES users(username);

ALTER TABLE ONLY publication ADD CONSTRAINT users_username FOREIGN KEY (created_by) REFERENCES users(username);

ALTER TABLE ONLY statistics_collector ADD CONSTRAINT statistics_collector_fk FOREIGN KEY (collector_id) REFERENCES collector (id);

ALTER TABLE ONLY user_action ADD CONSTRAINT fk_username_useraction FOREIGN KEY (username) REFERENCES users (username);

ALTER TABLE ONLY dossier ADD CONSTRAINT fk_dossier_reminder_account FOREIGN KEY (reminder_account) REFERENCES users (username);

ALTER TABLE ONLY user_action ADD CONSTRAINT fk_user_action_dossier_id FOREIGN KEY (dossier_id) REFERENCES dossier (id);

ALTER TABLE ONLY dossier_contributor ADD CONSTRAINT fk_dossier_contributor_user FOREIGN KEY (username) REFERENCES users (username);

ALTER TABLE ONLY dossier_contributor ADD CONSTRAINT fk_dossier_contributor_dossier FOREIGN KEY (dossier_id) REFERENCES dossier (id);

ALTER TABLE ONLY dossier_note ADD CONSTRAINT fk_dossier_note_createdby FOREIGN KEY (created_by) REFERENCES users (username);

ALTER TABLE ONLY dossier_note ADD CONSTRAINT fk_dossier_item_id FOREIGN KEY (dossier_item_id) REFERENCES dossier_item(id);

ALTER TABLE ONLY dossier_note_url ADD CONSTRAINT fk_dossier_note_url_note FOREIGN KEY (note_id) REFERENCES dossier_note (id);

ALTER TABLE ONLY dossier_note_ticket ADD CONSTRAINT fk_dossier_note_ticket_note FOREIGN KEY (note_id) REFERENCES dossier_note (id);

ALTER TABLE ONLY dossier_note_file ADD CONSTRAINT fk_dossier_note_file_note FOREIGN KEY (note_id) REFERENCES dossier_note (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_dossier FOREIGN KEY (dossier_id) REFERENCES dossier (id); 

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_assess FOREIGN KEY (assess_id) REFERENCES item (digest); 

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_analysis FOREIGN KEY (analysis_id) REFERENCES analysis (id); 

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_note FOREIGN KEY (note_id) REFERENCES dossier_note (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_advisory FOREIGN KEY (advisory_id) REFERENCES publication_advisory (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_eos FOREIGN KEY (eos_id) REFERENCES publication_endofshift (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_eod FOREIGN KEY (eod_id) REFERENCES publication_endofday (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_eow FOREIGN KEY (eow_id) REFERENCES publication_endofweek (id);

ALTER TABLE ONLY tag_item ADD CONSTRAINT fk_tag_item_dossier FOREIGN KEY (dossier_id) REFERENCES dossier (id);

ALTER TABLE ONLY publication_advisory_forward ADD CONSTRAINT fk_publication_publication_advisory_forward FOREIGN KEY (publication_id) REFERENCES publication (id);

ALTER TABLE ONLY advisory_forward_damage ADD CONSTRAINT fk_damage_description_advisory_forward_damage FOREIGN KEY (damage_id) REFERENCES damage_description (id); 

ALTER TABLE ONLY advisory_forward_damage ADD CONSTRAINT fk_publication_advisory_forward_advisory_damage FOREIGN KEY (advisory_forward_id) REFERENCES publication_advisory_forward (id);

ALTER TABLE ONLY publication_attachment ADD CONSTRAINT fk_publication_publication_attachment FOREIGN KEY (publication_id) REFERENCES publication (id);

ALTER TABLE ONLY dossier_item ADD CONSTRAINT fk_dossier_item_publication_advisory_forward FOREIGN KEY (advisory_forward_id) REFERENCES publication_advisory_forward (id);

ALTER TABLE ONLY source_wordlist ADD CONSTRAINT fk_source_wordlist_and_wordlist_id FOREIGN KEY (and_wordlist_id) REFERENCES wordlist (id);

ALTER TABLE ONLY source_wordlist ADD CONSTRAINT fk_source_wordlist_source_id FOREIGN KEY (source_id) REFERENCES sources (id);

ALTER TABLE ONLY source_wordlist ADD CONSTRAINT fk_source_wordlist_wordlist_id FOREIGN KEY (wordlist_id) REFERENCES wordlist (id);

ALTER TABLE ONLY source_wordlist ADD CONSTRAINT u_source_id_wordlist_id_and_wordlist_id UNIQUE (source_id, wordlist_id, and_wordlist_id);

ALTER TABLE ONLY item_archive ADD CONSTRAINT item_archive_id_unique UNIQUE (id);

ALTER TABLE advisory_linked_items
   ADD CONSTRAINT fk_advisory_linked_item_digest
      FOREIGN KEY (item_digest) REFERENCES item(digest);

ALTER TABLE advisory_linked_items
   ADD CONSTRAINT fk_advisory_linked_publication_id
      FOREIGN KEY (publication_id) REFERENCES publication(id);

ALTER TABLE advisory_linked_items
   ADD CONSTRAINT fk_advisory_linked_created_by
      FOREIGN KEY (created_by) REFERENCES users(username);

CREATE INDEX item_description_trgm_idx ON item using GIN(description gin_trgm_ops);
CREATE INDEX item_title_trgm_idx ON item using GIN(title gin_trgm_ops);

CREATE INDEX item_archive_description_trgm_idx ON item_archive using GIN(description gin_trgm_ops);
CREATE INDEX item_archive_title_trgm_idx ON item_archive using GIN(title gin_trgm_ops);

CREATE INDEX analysis_title_trgm_idx ON analysis using GIN(title gin_trgm_ops);
CREATE INDEX analysis_comments_trgm_idx ON analysis using GIN(comments gin_trgm_ops);
CREATE INDEX analysis_idstring_trgm_idx ON analysis using GIN(idstring gin_trgm_ops);
CREATE INDEX analysis_id_trgm_idx ON analysis using GIN(id gin_trgm_ops);

CREATE INDEX publication_contents_trgm_idx on publication using GIN(contents gin_trgm_ops);
CREATE INDEX publication_advisory_consequences_trgm_idx on publication_advisory using GIN(consequences gin_trgm_ops);
CREATE INDEX publication_advisory_description_trgm_idx on publication_advisory using GIN(description gin_trgm_ops);
CREATE INDEX publication_advisory_govcertid_trgm_idx on publication_advisory using GIN(govcertid gin_trgm_ops);
CREATE INDEX publication_advisory_hyperlinks_trgm_idx on publication_advisory using GIN(hyperlinks gin_trgm_ops);
CREATE INDEX publication_advisory_ids_trgm_idx on publication_advisory using GIN(ids gin_trgm_ops);
CREATE INDEX publication_advisory_solutions_trgm_idx on publication_advisory using GIN(solution gin_trgm_ops);
CREATE INDEX publication_advisory_summary_trgm_idx on publication_advisory using GIN(summary gin_trgm_ops);
CREATE INDEX publication_advisory_title_trgm_idx on publication_advisory using GIN(title gin_trgm_ops);
CREATE INDEX publication_advisory_update_trgm_idx on publication_advisory using GIN(update gin_trgm_ops);
CREATE INDEX publication_advisory_notes_trgm_idx on publication_advisory using GIN(notes gin_trgm_ops);
CREATE INDEX publication_advisory_tlpamber_trgm_idx on publication_advisory using GIN(tlpamber gin_trgm_ops);
CREATE INDEX software_hardware_name_trgm_idx on software_hardware using GIN(name gin_trgm_ops);
CREATE INDEX software_hardware_producer_trgm_idx on software_hardware using GIN(producer gin_trgm_ops);


REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;
