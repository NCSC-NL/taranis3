# PostgreSQL

This page collects information about running Postgresql, which may be
useful for you.

## Upgrading PSQL RedHat

( When the psql installation on RedHat EL is too old, it will mention
  this README script as help. )

RedHat EL 6 comes with a Postgres version which does not support
trigram indexes. These indexes are required to speed-up various searches.

( XXX https://www.softwarecollections.org/en/scls/rhscl/rh-postgresql95/
  describes a slightly different process. )

Execute the following:

1. define the Red Hat Software Collections (RHSCL) repository
   Add these lines to ``/etc/yum.repos.d/local.repo``
   Change ``<your-repo>`` into the location of your own RHSCL server.
```
[rhscl]
name=Red Hat Enterprise Linux 6Server - $basearch - RHSCL
failovermethod=priority
baseurl=http://<your-repo>/rhel6s-$basearch/RPMS.rhscl-1
enabled=0
gpgcheck=0
```
2. upgrade to PostgreSQL 9.5 (or newer)
```
# install the software
yum --enablerepo=rhscl install rh-postgresql95

# initialize the database
service rh-postgresql95-postgresql initdb

# start the daemon at boot
chkconfig rh-postgresql95-postgresql on

# Enable SCL for root and postgresql user
for b in ~root ~postgres; do
	echo "source scl_source enable rh-postgresql95" >>$b/.bashrc
    done
```
3. log-off and -on again be able to use postgres.

4. the Taranis bootstrap script should be able to pick this up
     automatically, from the environment of the root user each time it
     runs.
