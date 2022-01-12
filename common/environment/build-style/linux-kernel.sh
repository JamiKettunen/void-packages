: ${_kernver:="${version}_${revision}"}

# -dbg package has to be generated manually anyway
nodebug=yes

nostrip=yes
noverifyrdeps=yes
noshlibprovides=yes

# the Linux kernel has no (real) test suite
make_check=no

# These files could be modified when an external module is built.
mutable_files="
	/usr/lib/modules/${_kernver}/modules.builtin.bin
	/usr/lib/modules/${_kernver}/modules.builtin.alias.bin
	/usr/lib/modules/${_kernver}/modules.softdep
	/usr/lib/modules/${_kernver}/modules.dep
	/usr/lib/modules/${_kernver}/modules.dep.bin
	/usr/lib/modules/${_kernver}/modules.symbols
	/usr/lib/modules/${_kernver}/modules.symbols.bin
	/usr/lib/modules/${_kernver}/modules.alias
	/usr/lib/modules/${_kernver}/modules.alias.bin
	/usr/lib/modules/${_kernver}/modules.devname
"

# reproducible build
# FIXME: usr/src/kernel-headers-5.15.12_1/include/generated/compile.h does't honor KBUILD_BUILD_TIMESTAMP!!!
export KBUILD_BUILD_TIMESTAMP=$(LC_ALL=C date -ud @${SOURCE_DATE_EPOCH:-0})
export KBUILD_BUILD_USER=voidlinux
export KBUILD_BUILD_HOST=voidlinux

_arch= _archdir= _subarch=
case "$XBPS_TARGET_MACHINE" in
	i686*) _arch=i386; _archdir=x86;;
	x86_64*) _arch=x86_64; _archdir=x86;;
	arm*) _arch=arm;;
	aarch64*) _arch=arm64;;
	ppc64le*) _arch=powerpc; _subarch=ppc64le;;
	ppc64*) _arch=powerpc; _subarch=ppc64;;
	ppc*) _arch=powerpc; _subarch=ppc;;
	mips*) _arch=mips;;
esac
if [ -z "$_archdir" ]; then
	_archdir=$_arch
fi
_cross=
if [ "$CROSS_BUILD" ]; then
	_cross="CROSS_COMPILE=${XBPS_CROSS_TRIPLET}-"
fi

# Setup Makefile.DocBook if kernel version in range 4.14 -> 5.10
xbps-uhelper cmpver $version 4.14; _r1=$?
xbps-uhelper cmpver $version 5.11; _r2=$?
if [[ $_r1 -lt 2 && $_r2 -eq 255 ]]; then
	_docbook_makefile=${XBPS_COMMONDIR}/environment/configure/linux-kernel/Makefile.DocBook
fi
unset _r1 _r2

: ${python_version:=3}
