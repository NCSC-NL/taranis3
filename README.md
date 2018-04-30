# Taranis

Taranis is a tool developed by NCSC-NL to facilitate the process of monitoring 
and analysing news items and writing security advisories. Downloads, 
documentation and a more indepth introduction can be found at 
https://taranis.ncsc.nl/.
Taranis is published under the EUPL. See LICENCE for more information.

## Quick installation guide

This is a quick overview for a new Taranis installation. To migrate an existing
installation or for more indepth documentation on the installation, refer to
the documentation at https://taranis.ncsc.nl/.

The installation of Taranis is almost completly automated for the supported 
platforms:
- CentOS 7
- Ubuntu 16.04 LTS
- RedHat 7 EL

To install Taranis obtain the latest release from https://taranis.ncsc.nl/ and 
make sure perl is installed.

CentOS:
```
yum install perl 
```

Ubuntu:
```
apt-get install perl-modules
```

Extract the bootstrap script and run it:

```
tar xzf taranis-3.4.1.tar.gz taranis-3.4.1/taranis-bootstrap
mv taranis-3.4.1/taranis-bootstrap .
./taranis-bootstrap taranis-3.4.1.tar.gz
```

The bootstrap script will start with creating a username (if the name doesn’t
exist already). It will unpack the sources (if they are not unpacked already)
into ``~taranis/sources/taranis-3.4.1/ ``.
Then, it starts the install scripts which are contained in the package.

If you run into a problem, you can modify the responible script in
``~taranis/sources/taranis-3.4.1/install/`` and run the installation again
(as user taranis):
```
taranis install
```
If the ``taranis`` script is not yet in your $PATH, you can run:
```
~/sources/taranis-3.4.1/bin/taranis install
```

If you find a bug please report it to taranis@ncsc.nl. Note that NCSC-NL fixes
bugs on a best effort basis.
