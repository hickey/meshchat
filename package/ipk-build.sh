#!/bin/sh
# ipkg-build -- construct a .ipk from a directory
# Carl Worth <cworth@east.isi.edu>
# based on a script by Steve Redler IV, steve@sr-tech.com 5-21-2001
set -e

ipkg_extract_value() {
	sed -e "s/^[^:]*:[[:space:]]*//"
}

required_field() {
	field=$1

	value=`grep "^$field:" < $CONTROL/control | ipkg_extract_value`
	if [ -z "$value" ]; then
		echo "ipkg-build: Error: $CONTROL/control is missing field $field" ;
		PKG_ERROR=1
	fi
	echo $value
}

pkg_appears_sane() {
	local pkg_dir=$1

	local owd=`pwd`
	cd $pkg_dir

	PKG_ERROR=0
	if [ ! -f "$CONTROL/control" ]; then
		echo "ipkg-build: Error: Control file $pkg_dir/$CONTROL/control not found."
		cd $owd
		return 1
	fi

	pkg=`required_field Package`
	version=`required_field Version`
	arch=`required_field Architecture`
	required_field Maintainer >/dev/null
	required_field Description >/dev/null

	if echo $pkg | grep '[^a-z0-9.+-]'; then
		echo "ipkg-build: Error: Package name $name contains illegal characters, (other than [a-z0-9.+-])"
		PKG_ERROR=1;
	fi

    local bad_fields=`sed -ne 's/^\([^[:space:]][^:[:space:]]\+[[:space:]]\+\)[^:].*/\1/p' < $CONTROL/control | sed -e 's/\\n//'`
	if [ -n "$bad_fields" ]; then
		bad_fields=`echo $bad_fields`
		echo "ipkg-build: Error: The following fields in $CONTROL/control are missing a ':'"
		echo "	$bad_fields"
		echo "ipkg-build: This may be due to a missing initial space for a multi-line field value"
		PKG_ERROR=1
	fi

    for script in $CONTROL/preinst $CONTROL/postinst $CONTROL/prerm $CONTROL/postrm; do
		if [ -f $script -a ! -x $script ]; then
			echo "ipkg-build: Error: package script $script is not executable"
			PKG_ERROR=1
		fi
	done

	if [ -f $CONTROL/conffiles ]; then
		for cf in `cat $CONTROL/conffiles`; do
			if [ ! -f ./$cf ]; then
				echo "ipkg-build: Error: $CONTROL/conffiles mentions conffile $cf which does not exist"
				PKG_ERROR=1
			fi
		done
	fi

	cd $owd
	return $PKG_ERROR
}

###
# ipkg-build "main"
###

case $# in
1)
	dest_dir=.
	;;
2)
	dest_dir=$2
	;;
*)
	echo "Usage: ipkg-build <pkg_directory> [<destination_directory>]" ;
	exit 1
	;;
esac

pkg_dir=$1

if [ ! -d $pkg_dir ]; then
	echo "ipkg-build: Error: Directory $pkg_dir does not exist"
	exit 1
fi

# CONTROL is second so that it takes precedence
CONTROL=
[ -d $pkg_dir/DEBIAN ] && CONTROL=DEBIAN
[ -d $pkg_dir/CONTROL ] && CONTROL=CONTROL
if [ -z "$CONTROL" ]; then
	echo "ipkg-build: Error: Directory $pkg_dir has no CONTROL subdirectory."
	exit 1
fi

if ! pkg_appears_sane $pkg_dir; then
	echo "Please fix the above errors and try again."
	exit 1
fi

tmp_dir=$dest_dir/IPKG_BUILD.$$
mkdir $tmp_dir

tar -C $pkg_dir --exclude=$CONTROL -czf $tmp_dir/data.tar.gz .
tar -C $pkg_dir/$CONTROL -czf $tmp_dir/control.tar.gz .

echo "2.0" > $tmp_dir/debian-binary

pkg_file=$dest_dir/${pkg}_${version}_${arch}.ipk
tar -C $tmp_dir -czf $pkg_file debian-binary data.tar.gz control.tar.gz
rm $tmp_dir/debian-binary $tmp_dir/data.tar.gz $tmp_dir/control.tar.gz
rmdir $tmp_dir

echo "Packaged contents of $pkg_dir into $pkg_file"
