# taranis_install_scripts: unpack Taranis and run installation scripts.

class taranis_install_scripts ($os) {
	group { 'taranis':
		ensure => present,
	}
	user { 'taranis':
		ensure => present,
		gid => 'taranis',
		home => '/opt/taranis',
		shell => '/bin/bash',
	}


	package { 'git':
		ensure => present,
	}

	# Create a clean install (from working directory's HEAD commit) using the
	# packaging script.
	exec { 'create package':
		command => '/vagrant/devel/package-public-excluding-docs.pl HEAD > /opt/taranis-HEAD.tgz',
		creates => '/opt/taranis-HEAD.tgz',
	}
	exec { 'untar package':
		cwd => '/opt',
		command => '/bin/tar zxf /opt/taranis-HEAD.tgz',
		creates => '/opt/taranis-HEAD',
	}

	file { '/opt/taranis':
		ensure => link,
		target => '/opt/taranis-HEAD',
	}

	if $os == 'centos' {
		exec { 'epel_install':
			command => "/opt/taranis/install_scripts/${os}/epel_install.sh",
			require => File['/opt/taranis'],
			before => Exec['os_packages'],
		}
	}

	exec { 'os_packages':
		command => $os ? {
			'ubuntu' => "/opt/taranis/install_scripts/ubuntu/debian_packages.sh",
			'centos' => "/opt/taranis/install_scripts/centos/rpm_packages.sh",
		},
		timeout => 0,
	}

	exec { 'cpan_modules':
		command => "/opt/taranis/install_scripts/${os}/cpan_modules.sh",
		timeout => 0,
	}

	exec { 'permissions':
		command => "/opt/taranis/install_scripts/${os}/taranis_permissions.sh",
	}

	Package['git']
		-> Exec['create package'] -> Exec['untar package'] -> File['/opt/taranis']
		-> Exec['os_packages'] -> Exec['cpan_modules'] -> Exec['permissions']

	Group['taranis'] -> User['taranis'] -> Exec['permissions']
}
