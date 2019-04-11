#!/usr/bin/perl
# This file is part of Taranis, Copyright NCSC-NL. See http://taranis.ncsc.nl
# Licensed under EUPL v1.2 or newer, https://spdx.org/licenses/EUPL-1.2.html

use 5.010;
use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Test::PostgreSQL;
use Test::Most;
use SQL::Abstract::More;
use Tie::IxHash;

use Taranis::Database qw(withRollback withTransaction);
use Taranis::TestUtil qw(cmp_deeply_or_diff withEphemeralDatabase withDistConfig tableIds lastTableId);
use Taranis::FunctionalWrapper qw(Database Sql);


local $| = 1;


withDistConfig {
	subtest 'checkIfExists' => sub {
		withEphemeralDatabase {
			ok !Database->checkIfExists({}, 'collector', 0),
				"empty table";

			# Insert some arbitrary data.
			Database->simple->insert('collector', {
				description => 'testcollector',
				ip => '::1',
				secret => 'testcollector secret',
			});

			ok Database->checkIfExists({}, 'collector', 0),
				"empty where";

			ok Database->checkIfExists({ip => '::1'}, 'collector'),
				"basic match";
			ok !Database->checkIfExists({ip => '::2'}, 'collector'),
				"basic non-match";

			ok Database->checkIfExists({ip => '::1', description => 'testcollector'}, 'collector'),
				"multiple fields";
			ok !Database->checkIfExists({ip => '::1', description => 'THERE IS NO COLLECTOR, ONLY ZUUL'}, 'collector'),
				"multiple fields, some match";

			ok Database->checkIfExists({description => 'TeStCoLlEcToR'}, 'collector', 1),
				"case insensitive";
			ok !Database->checkIfExists({description => 'TeStCoLlEcToR'}, 'collector', 0),
				"case sensitive";
			ok !Database->checkIfExists({description => 'TeStCoLlEcToR'}, 'collector'),
				"case sensitive by default";

			ok Database->checkIfExists({id => lastTableId('collector')}, 'collector', 1),
				"case insensitive integer match";
			ok !Database->checkIfExists({id => lastTableId('collector') + 1}, 'collector', 1),
				"case insensitive integer nonmatch";
		};
	};


	subtest 'getResultCount' => sub {
		withEphemeralDatabase {
			my $db = Database->simple;
			$db->insert('collector', {
				description => "testcollector $_",
				ip => '::1',
				secret => 'testcollector secret',
			}) for 1 .. 5;

			$db->insert('collector', {
				description => "testcollector $_",
				ip => '::2',
				secret => 'testcollector secret',
			}) for 6 .. 10;

			$db->insert('sources', {
				id => $_,
				category => 1,
				digest => "testsource digest $_",
				fullurl => "https://www.ncsc.nl/test/$_",
				host => 'www.ncsc.nl',
				mtbc => 999,
				parser => 'xml',
				protocol => 'https://',
				port => 443,
				sourcename => "testsource $_",
				url => '/test',
				checkid => 1,
				language => 'en',
				collector_id => lastTableId 'collector',
				rating => 50,
			}) for 1 .. 2;

			is Database->getResultCount(Sql->select('collector', '*', {ip => '::1'})),
				5, 'simple select';

			is Database->getResultCount(Sql->select('collector', '*')),
				10, 'no where clause';

			is Database->getResultCount(Sql->select('collector', '*', {ip => '::3'})),
				0, '0 matches';

			is Database->getResultCount(Sql->select('collector', ['id', 'secret'], {ip => '::1'})),
				5, 'two columns';

			is Database->getResultCount(Sql->select('collector', '*', {ip => '::1'}, ['id'])),
				5, 'order by';

			is Database->getResultCount(Sql->select('collector', '*', {ip => ['::1', '::2']})),
				10, 'or';

			is Database->
				getResultCount(Sql->select('collector', '*', {ip => ['::1', '::2'], description => 'testcollector 3'})),
				1, 'and-or';

			is Database->getResultCount(Sql->select('collector', '*', {description => {-ilike => => '%LLECTOR 1%'}})),
				2, 'ilike';  # Matches collectors 1 and 10.

			tie my %join, "Tie::IxHash";

			my ($stmnt, @bind) = Sql->select('sources s', '*', {secret => 'testcollector secret'});
			%join = ('JOIN collector AS c' => { 's.collector_id' => 'c.id' });
			$stmnt = Database->sqlJoin(\%join, $stmnt);
			is Database->getResultCount($stmnt, @bind),
				2, 'join';
		};
	};


	subtest 'withRollback' => sub {
		withEphemeralDatabase {
			cmp_deeply_or_diff &tagNames, [];

			# Try a few levels of transaction nesting.
			withRollback {
				my $db = Database->simple;
				$db->insert('tag', {name => 'a'});
				cmp_deeply_or_diff &tagNames, [qw/a/];

				withRollback {
					$db->insert('tag', {name => 'b'});
					cmp_deeply_or_diff &tagNames, [qw/a b/];

					# Transaction should still get rolled back when an exception happens.
					eval {
						withRollback {
							$db->insert('tag', {name => 'c'});
							cmp_deeply_or_diff &tagNames, [qw/a b c/];
							die "uh oh!";
						};
					};

					cmp_deeply_or_diff &tagNames, [qw/a b/];
				};
				cmp_deeply_or_diff &tagNames, [qw/a/];
			};
			cmp_deeply_or_diff &tagNames, [];
		};
	};


	subtest 'withTransaction' => sub {
		withEphemeralDatabase {
			my $db = Database->simple;
			cmp_deeply_or_diff &tagNames, [];

			# Try a few levels of transaction nesting.
			withTransaction {
				$db->insert('tag', {name => 'a'});
				cmp_deeply_or_diff &tagNames, [qw/a/];

				withTransaction {
					$db->insert('tag', {name => 'b'});
					cmp_deeply_or_diff &tagNames, [qw/a b/];

					withTransaction {
						$db->insert('tag', {name => 'c'});
						cmp_deeply_or_diff &tagNames, [qw/a b c/];
					};

					cmp_deeply_or_diff &tagNames, [qw/a b c/];
				};
				cmp_deeply_or_diff &tagNames, [qw/a b c/];
			};
			cmp_deeply_or_diff &tagNames, [qw/a b c/];
		};
	};


	subtest 'withTransaction: rollback on exception' => sub {
		withEphemeralDatabase {
			cmp_deeply_or_diff &tagNames, [];

			# Let the exception travel through a few levels of transaction nesting.
			eval {
				withTransaction {
					my $db = Database->simple;
					$db->insert('tag', {name => 'a'});

					withTransaction {
						$db->insert('tag', {name => 'b'});

						withTransaction {
							$db->insert('tag', {name => 'c'});
							cmp_deeply_or_diff &tagNames, [qw/a b c/];
							die "uh oh!";
						};
					};
				};
			};
			cmp_deeply_or_diff &tagNames, [];
		};
	};


	subtest 'withTransaction + withRollback' => sub {
		withEphemeralDatabase {
			cmp_deeply_or_diff &tagNames, [];

			# Try a few levels of transaction nesting.
			withTransaction {
				my $db = Database->simple;

				$db->insert('tag', {name => 'a'});
				cmp_deeply_or_diff &tagNames, [qw/a/];

				withRollback {
					$db->insert('tag', {name => 'b'});
					cmp_deeply_or_diff &tagNames, [qw/a b/];

					withTransaction {
						$db->insert('tag', {name => 'c'});
						cmp_deeply_or_diff &tagNames, [qw/a b c/];
					};

					cmp_deeply_or_diff &tagNames, [qw/a b c/];
				};
				cmp_deeply_or_diff &tagNames, [qw/a/];
			};
			cmp_deeply_or_diff &tagNames, [qw/a/];
		};
	};
};


done_testing;


sub tagNames {
	return [ Database->simple->select('tag', 'name', {}, 'name')->flat ];
}
