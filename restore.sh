#!/bin/bash
# Backup your MediaWiki instance
# Who? jeff@usn.nl

# Defaults
BASEDIR="/opt"
TARGETDIR=mediawiki
BACKUPBASEDIR="/var/backups/mediawiki"
DBHOST=localhost
DBNAME=mediawiki
DBUSER=mediawiki
DBPASSWD=mediawiki
VERBOSE=false

# Override any defaults that are set by the user
test -f $HOME/.mediawiki.conf && . $HOME/.mediawiki.conf

usage="Usage: $0 [target-date]

  Restores a backup of your MediaWiki Instance from the following location:

  $BACKUPBASEDIR/[target-date]

  NOTE: THIS SCRIPT DOES NOT INSTALL THE CORRECT VERSION OF MEDIAWIKI, DO THAT FIRST!

  -v  Verbose
"

function version() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

function say() {
  if $VERBOSE
  then
    echo "$@"
  fi
}

while getopts "hv" opt; do
  case ${opt} in
    h)
      echo -e "$usage"
      exit 0
      ;;
    v)
      VERBOSE=true
      ;;
  esac
done

shift $[$OPTIND -1]
BACKUPDIR="$BACKUPBASEDIR/$1"

# Check if the target exists
if ! test -d $BACKUPDIR
then
  echo "ERROR: date $1 is not valid, no backup found!"
  exit 1
fi

# Restore DB backup
mysql --host=$DBHOST --user=$DBUSER --password=$DBPASSWD $DBNAME < $BACKUPDIR/$DBNAME.sql

# Restore settings
mkdir -p $BASEDIR/mediawiki-common/images
cp $BACKUPDIR/LocalSettings.php $BASEDIR/mediawiki-common/LocalSettings.php

# Restore attachments
mkdir /tmp/mediawiki-restore.$$
tar xzf $BACKUPDIR/images.tgz -C /tmp/mediawiki-restore.$$

if test $(version $MINORVERSION) -ge $(version "1.40.0")
then
  php $BASEDIR/$TARGETDIR/maintenance/run.php importImages.php --overwrite --search-recursively /tmp/mediawiki-restore.$$
  php $BASEDIR/$TARGETDIR/maintenance/run.php rebuildall.php
  php $BASEDIR/$TARGETDIR/maintenance/run.php refreshLinks.php
else
  php $BASEDIR/$TARGETDIR/maintenance/importImages.php --overwrite --search-recursively /tmp/mediawiki-restore.$$
  php $BASEDIR/$TARGETDIR/maintenance/rebuildall.php
  php $BASEDIR/$TARGETDIR/maintenance/refreshLinks.php
fi

# Check OS version and set Apache system user
. /etc/os-release
case $ID in
  debian)
    APACHE=www-data
    ;;
  rhel|fedora)
    APACHE=apache
    ;;
esac

# Ensure common directories in case of a new installation
chown -R $APACHE:$APACHE $BASEDIR/mediawiki-common/images
chown -R $APACHE:$APACHE $BASEDIR/mediawiki-common/LocalSettings.php

# If we're running with SELinux in Enforcing mode, set up upload directory
GETENFORCE=$(getenforce 2>/dev/null)
if test "$GETENFORCE" == 'Enforcing'
then
  semanage fcontext -a -t httpd_sys_content_rw_t "$BASEDIR/mediawiki-common/images(/.*)?"
  restorecon -r $BASEDIR/mediawiki-common
fi

# Clean up
rm -rf /tmp/mediawiki-restore.$$

say "Job's done! Backup has been restored!"
