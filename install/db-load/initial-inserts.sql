INSERT INTO users (username, password, uriw, search, category, anasearch, anastatus, mailfrom_sender, mailfrom_email, lmh, statstype, hitsperpage, fullname, disabled, datestart, datestop) VALUES ('admin', '{SSHA512}0E6hEGJxt1Yv++dkbXIjbFHpEvGwEKNIdYzMFS0dZwLLI+nohXM8wN1Yf2Cb5jVn2UMkc4uv3uYNkDTLfjT4+khVXgo=', '1111', NULL, NULL, NULL, NULL, 'Taranis Admin', 'admin@localhost', '111', NULL, NULL, 'Taranis Admin', false, NULL, NULL);

INSERT INTO entitlement (id, name, description, particularization) VALUES (1, 'analysis', 'Rechten op een analyse. Via een particularization kunnen rechten op analyses met een bepaalde status worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (2, 'configuration_generic', 'Rechten op de generieke Taranis configuratie', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (3, 'configuration_parser', 'Rechten op Parser configuraties ', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (4, 'configuration_strips', 'Rechten op Strips configuraties', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (5, 'constituent_groups', 'Rechten op Constituent Groups', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (6, 'constituent_individuals', 'Rechten op Constituent Individuals. Via een particularization kunnen rechten op constituents van een bepaalde groep worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (7, 'damage_description', 'Rechten op de lijst van schadeomschrijvingen', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (8, 'entitlements', 'Rechten op Entitlement definities', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (9, 'item_analysis', 'Rechten op de koppeling tussen een item en een analyse. Via een particularization kunnen rechten op het koppelen van items van een bepaalde categorie worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (10, 'items', 'Rechten op verzamelde items. Via een particularization kunnen rechten op items van een bepaalde categorie worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (11, 'membership', 'Rechten op de groepslidmaatschappen van Constituent Individuals. Via een particularization kunnen rechten op lidmaatschappen voor een bepaalde Constituent Group worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (12, 'publication', 'Rechten op een publicatie. Via een particularization kunnen rechten op publicaties van een bepaald type worden gespecificeerd. De rechten op een publicatie bepalen ook de rechten op het koppelen van kwetsbare platformen, etc.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (13, 'publication_template', 'Rechten op publicatie templates. Via een particularization kunnen rechten op templates van een bepaald type worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (14, 'publication_type', 'Rechten op publicatie typen', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (15, 'software_hardware', 'Rechten op de lijst van hard- en software', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (16, 'soft_hard_usage', 'Rechten op het koppelen van hard- en software aan Constituent Groups (''onderhouden foto''). Via een  particularization kunnen rechten op het koppelen van een hard- en software aan een specifieke Constituent  Group worden gespecificeerd.', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (17, 'sources_errors', 'Rechten op foutmeldingen rondom bronnen.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (18, 'sources_items', 'Rechten op de bronnenlijst (items bronnen). Via een particularization kunnen rechten op bronnen van een bepaalde categorie worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (19, 'sources_stats', 'Rechten op de bronnenlijst (statistiek bronnen). Via een particularization kunnen rechten op bronnen van  een bepaalde categorie worden gespecificeerd.', true);
INSERT INTO entitlement (id, name, description, particularization) VALUES (20, 'role_right', 'Rechten op rechtentoekenningen aan rol', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (21, 'roles', 'Rechten op Role definities', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (22, 'user_role', 'Rechten op toegekende rollen aan een gebruiker', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (23, 'user_action', 'Rechten op uitgevoerde acties van gebruikers (kan alleen ''read'' rechten zijn, ''write'' rechten zijn voorbehouden aan Taranis zelf)', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (24, 'users', 'Rechten op gebruikersgegevens', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (25, 'generic', 'Generieke rechten (login/logout)', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (26, 'tools', 'Rechten op tools', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (27, 'admin_generic', 'Taranis Administrator Rechten', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (28, 'photo_import', 'Rechten op importeren van foto', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (29, 'dossier', 'Rechten op dossiers', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (30, 'rest_level1', 'Rechten voor REST level 1', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (31, 'rest_level2', 'Rechten voor REST level 2', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (32, 'rest_level3', 'Rechten voor REST level 3', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (33, 'rest_level4', 'Rechten voor REST level 4', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (34, 'report', 'Rechten op reports', false);
INSERT INTO entitlement (id, name, description, particularization) VALUES (35, 'cve', 'Rechten op CVE descriptions en templates', false);

INSERT INTO role (id, name, description) VALUES (1, 'Taranis Administrator', 'Admin');

INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (1, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (2, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (3, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (4, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (5, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (6, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (7, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (8, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (9, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (10, true, NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (11, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (12, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (13, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (14, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (15, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (16, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (17, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (18, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (19, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (20, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (21, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (22, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (23, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (24, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (25, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (26, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (27, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (28, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (29, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (30, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (31, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (32, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (33, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (34, true,  NULL, true, 1, true);
INSERT INTO role_right (entitlement_id, execute_right, particularization, read_right, role_id, write_right) VALUES (35, true,  NULL, true, 1, true);

INSERT INTO user_role (role_id, username) VALUES (1, 'admin');

INSERT INTO cpe_files( filename, last_change ) VALUES ( 'nvdcve-2.0-modified.xml.gz', 'firsttime' );
INSERT INTO cpe_files( filename, last_change ) VALUES ( 'nvdcve-2.0-recent.xml.gz' , 'firsttime' );

INSERT INTO soft_hard_type (description, base, sub_type) VALUES ('Application', 'a', NULL);
INSERT INTO soft_hard_type (description, base, sub_type) VALUES ('Operating System', 'o', NULL);
INSERT INTO soft_hard_type (description, base, sub_type) VALUES ('Hardware', 'h', NULL);

INSERT INTO parsers (parsername) VALUES ( 'xml' );
INSERT INTO parsers (parsername) VALUES ('twitter');
INSERT INTO parsers (parsername) VALUES ('custom');
INSERT INTO category (name) VALUES ( 'security-news' );
INSERT INTO category (name) VALUES ( 'ict-news' );
INSERT INTO category (name) VALUES ( 'security-vuln' );
INSERT INTO category (name) VALUES ( 'news' );

INSERT INTO download_files (file_url, name, filename) VALUES ('http://static.nvd.nist.gov/feeds/xml/cve/nvdcve-2.0-recent.xml.gz', 'cpe_download', 'nvdcve-2.0-recent.xml.gz');
INSERT INTO download_files (file_url, name, filename) VALUES ('http://static.nvd.nist.gov/feeds/xml/cve/nvdcve-2.0-modified.xml.gz', 'cpe_download', 'nvdcve-2.0-modified.xml.gz');
INSERT INTO download_files (file_url, name, filename) VALUES ('http://cve.mitre.org/data/downloads/allitems-cvrf-year-2016.xml','cve_description', 'allitems-cvrf-year-2016.xml');
INSERT INTO download_files (file_url, name, filename) VALUES ('http://cve.mitre.org/data/downloads/allitems-cvrf-year-2017.xml','cve_description', 'allitems-cvrf-year-2017.xml');
INSERT INTO download_files (file_url, name, filename) VALUES ('http://cve.mitre.org/data/downloads/allitems-cvrf-year-2018.xml','cve_description', 'allitems-cvrf-year-2018.xml');
INSERT INTO download_files (file_url, name, filename) VALUES ('http://cve.mitre.org/data/downloads/allitems-cvrf-year-2019.xml','cve_description', 'allitems-cvrf-year-2019.xml');

INSERT INTO dashboard(html, json, "type") VALUES ('', '', 1);
INSERT INTO dashboard(html, json, "type") VALUES ('', '', 2);

INSERT INTO constituent_type(type_description) VALUES ('default');
