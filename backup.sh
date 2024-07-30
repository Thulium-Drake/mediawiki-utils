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

usage="Usage: $0

  Creates a backup of your MediaWiki Instance at the following location:

  $BACKUPBASEDIR/[current-date]

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
BACKUPDIR="$BACKUPBASEDIR/$(date +%F)"

# Ensure backup target directory
mkdir -p $BACKUPDIR

# Create DB backup
mysqldump --host=$DBHOST --user=$DBUSER --password=$DBPASSWD $DBNAME > $BACKUPDIR/$DBNAME.sql

# Backup settings
cp -L $BASEDIR/mediawiki-common/LocalSettings.php $BACKUPDIR

# Backup attachments
tar czf $BACKUPDIR/images.tgz --exclude lockdir --exclude archive --exclude thumb --exclude deleted -C $BASEDIR/mediawiki-common/images .

if test $(version $MINORVERSION) -ge $(version "1.40.0")
then
  # Export pages as XML for a rainy day
  php $BASEDIR/$TARGETDIR/maintenance/run.php dumpBackup.php --full -q -o gzip:$BACKUPDIR/wiki-pages.xml.gz
  # Save version
  php $BASEDIR/$TARGETDIR/maintenance/run.php Version.php > $BACKUPDIR/version.txt
else
  php $BASEDIR/mediawiki-$MINORVERSION/maintenance/update.php --quick
  # Export pages as XML for a rainy day
  php $BASEDIR/$TARGETDIR/maintenance/dumpBackup.php --full -q -o gzip:$BACKUPDIR/wiki-pages.xml.gz
  # Save version
  php $BASEDIR/$TARGETDIR/maintenance/Version.php > $BACKUPDIR/version.txt
fi

cat << EOF > $BACKUPDIR/README.txt
This directory contains the following files:

* $DBNAME.sql: Database dump (contains all pages and other information of the Wiki)
* LocalSettings.php: Main settings file at the time of the backup
* Logo.png: Logo at the time of the backup
* images.tgz: Contents of the 'images' folder, which contains all attachments to the Wiki
* version.txt: The version of the wiki at the time of the backup
* wiki-pages.xml: XML export of only wiki pages, can be used to rebuild the Wiki when the DB does not restore
EOF

say "Job's done! Backup is located at $BACKUPDIR"
