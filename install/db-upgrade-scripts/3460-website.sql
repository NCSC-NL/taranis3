CREATE SEQUENCE publication_advisory_website_id_seq
    START WITH 660000000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE publication_advisory_website (
    id integer DEFAULT nextval('publication_advisory_website_id_seq'::regclass) NOT NULL,
    publication_id integer,
    govcertid      text,
    title          text,
    advisory_id    integer,                -- either this one or next
    advisory_forward_id integer,           --    refers to emailed pub
    damage         smallint,
    probability    smallint,
    version        character varying(5),
    document_uuid  character varying(40),  -- not used anymore
    handle_uuid    text,                   -- unique external reference
    is_public      boolean
);

ALTER TABLE ONLY publication_advisory_website
    ADD CONSTRAINT publication_advisory_website_pk PRIMARY KEY (id);

CREATE INDEX fki_publication_advisory_website_advisory_id
	ON publication_advisory_website (advisory_id);

CREATE INDEX fki_publication_advisory_website_advisory_forward_id
	ON publication_advisory_website (advisory_forward_id);

ALTER TABLE publication_advisory_website
    ADD CONSTRAINT fk_advisory_id
    FOREIGN KEY (advisory_id) REFERENCES publication_advisory(id);
