export HOSTNAME=`hostname -f`

export CODENAME=trixie
export OUT_BASE=~/publish
export TRACE=/srv/cdbuilder.debian.org/src/ftp/debian/project/trace/$(hostname).debian.org
export ARCH_DI_DIR=/srv/cdbuilder.debian.org/src/deb-cd/d-i
export PUBDIR=/srv/cdbuilder.debian.org/dst/deb-cd
export MIRROR=/srv/cdbuilder.debian.org/src/ftp/debian
export BASEDIR=~/build.${CODENAME}/debian-cd
export MKISOFS=~/build.${CODENAME}/mkisofs/usr/bin/mkisofs
export EXTRACTED_SOURCES=${OUT_BASE}/cd-sources/
export LIVE_OUT=${OUT_BASE}/.live

if [ "$DATE"x = ""x ] ; then
    export DATE=`date -u +%Y%m%d`
fi

if [ "$ARCHES"x = ""x ] ; then
    ARCHES="amd64 arm64 armhf source ppc64el riscv64 s390x"
fi
