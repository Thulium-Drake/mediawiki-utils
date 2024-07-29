#!/bin/bash
# Download latest version of MediaWiki from the site and unpack it
# Who? jeff@usn.nl

# Defaults
BASEURL="https://releases.wikimedia.org/mediawiki/"
BASEDIR="/opt"
TARGETDIR="mediawiki"
DBHOST=localhost
DBNAME=mediawiki
DBUSER=mediawiki
DBPASSWD=mediawiki
VERBOSE=false
CURLOPTS='-Ss'

# Override any defaults that are set by the user
test -f $HOME/.mediawiki.conf && . $HOME/.mediawiki.conf

usage="Usage: $0 [version]

  Installs/Updates MediaWiki with the version specified, or if unspecified, latest

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
      CURLOPTS=''
      ;;
  esac
done

shift $[$OPTIND -1]
VERSION=$1

# Collect latest version if not defined
if test -z "$VERSION"
then
  say "Version not defined, collecting latest"
  VERSION=$(curl $CURLOPTS $BASEURL | cut -d\" -f6 | grep -E "[0-9]\.[0-9][0-9]" | sort -V | tail -n1 | cut -d\/ -f1)
  say "Latest version is $VERSION"
fi

# Collect latest package for version
PACKAGE=$(curl $CURLOPTS $BASEURL/$VERSION/ | cut -d\" -f6 | grep mediawiki-$VERSION | grep -Ev "(sig|rc|zip)" | sort -V | tail -n1)
MINORVERSION=$(echo ${PACKAGE%%.tar.gz} | cut -d- -f2)
say "Latest minor version is $MINORVERSION"

# Download package
curl -Ss $BASEURL/$VERSION/$PACKAGE > /tmp/mediawiki.tgz
tar xzf /tmp/mediawiki.tgz -C $BASEDIR
chown -R root:root $BASEDIR/mediawiki-$MINORVERSION

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
mkdir -p $BASEDIR/mediawiki-common/images
chown $APACHE:$APACHE $BASEDIR/mediawiki-common/images

# If we're running with SELinux in Enforcing mode, set up upload directory
GETENFORCE=$(getenforce 2>/dev/null)
if test "$GETENFORCE" == 'Enforcing'
then
  semanage fcontext -a -t httpd_sys_content_rw_t "$BASEDIR/mediawiki-common/images(/.*)?"
  restorecon -r $BASEDIR/mediawiki-common
fi

# Create DB backup of current version before upgrading
mysqldump --host=$DBHOST --user=$DBUSER --password=$DBPASSWD $DBNAME > /root/wikibackup-$(date +%F)-pre-$MINORVERSION.sql

# Rework symlinks
OLDVERSION=$(readlink $BASEDIR/$TARGETDIR)
rm -rf $BASEDIR/$TARGETDIR
ln -s $BASEDIR/mediawiki-$MINORVERSION $BASEDIR/$TARGETDIR

# for settings
ln -s $BASEDIR/mediawiki-common/LocalSettings.php $BASEDIR/mediawiki-$MINORVERSION/
ln -s $BASEDIR/mediawiki-common/Logo.png $BASEDIR/mediawiki-$MINORVERSION/

# for attachments
rm -rf $BASEDIR/mediawiki-$MINORVERSION/images
ln -s $BASEDIR/mediawiki-common/images $BASEDIR/mediawiki-$MINORVERSION/

ln -s $BASEDIR/mediawiki-$MINORVERSION/images $BASEDIR/mediawiki-$MINORVERSION/upload

# Run maintenance jobs for update
if test $(version $MINORVERSION) -ge $(version "1.40.0")
then
  php $BASEDIR/mediawiki-$MINORVERSION/maintenance/run.php update.php --quick
else
  php $BASEDIR/mediawiki-$MINORVERSION/maintenance/update.php --quick
fi

# Clean up old version
if "$OLDVERSION" != "$BASEDIR/mediawiki-$MINORVERSION"
then
  rm -rf $OLDVERSION
fi

say "Job's done! Happy Wiki-ing on $MINORVERSION"
say "Please note that you might still need to update your extensions!"
