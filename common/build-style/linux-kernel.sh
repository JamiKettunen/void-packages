#
# This helper is for all Linux kernel templates.
#

_kernel_ver_lt() {
	local ver=${version%.*}
	local ver_major=${ver%.*} cmp_major=${1%.*}
	if [ $ver_major -gt $cmp_major ]; then
		return 1
	elif [ $ver_major -eq $cmp_major ]; then
		local ver_minor=${ver#*.} cmp_minor=${1#*.}
		if [ $ver_minor -ge $cmp_minor ]; then
			return 1
		fi
	fi
}

_kernel_supports_modules() {
	grep -q '^CONFIG_MODULES=y$' .config
}

_kernel_update_make() {
	if [ -z "$_llvm" ] && [[ "$kernel_clang" || "$kernel_llvm" ]]; then
		if _kernel_ver_lt 5.15; then
			msg_warn "Unpatched <5.7 kernels don't have full support for Clang/LLVM; ensure your kernel is up-to-date & patched!\n"
			if [ "$kernel_llvm" ]; then
				_llvm="CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm STRIP=llvm-strip OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf HOSTCC=clang HOSTCXX=clang++ HOSTAR=llvm-ar HOSTLD=ld.lld AS=clang"
			fi
		else
			if [ "$kernel_llvm" ]; then
				_llvm="LLVM=1 LLVM_IAS=1"
			fi
		fi
		if [ -z "$kernel_llvm" ]; then
			_llvm="CC=clang"
		fi
	fi

	: ${make_cmd:=make}
	_make="$make_cmd ARCH=$_arch $_cross $_llvm"

	local func="${1:-${FUNCNAME[1]}}"
	if [ -z "$make_build_target" ] && [[ "$func" = *"_build" || "$func" = *"_install" ]]; then
		case "$_arch" in
			i386|x86_64) make_build_target="bzImage";;
			arm) make_build_target="zImage dtbs";;
			arm64) make_build_target="Image dtbs";;
			powerpc) make_build_target="zImage";;
			mips) make_build_target="uImage dtbs";;
		esac
		if _kernel_supports_modules; then
			make_build_target+=" modules"
		fi
	fi
}

do_configure() {
	_kernel_update_make

	# FIXME: check if this is still true on e.g. srcpkgs/rpi-kernel/template!!!
	# Remove .git directory, otherwise scripts/setkernelversion.sh
	# modifies KERNELRELEASE and appends '+' to it.
	#rm -rf .git

	# 5.8 misses Documentation/DocBook. We ship the directory from 4.12 here (kernels >=4.14 && <=5.10)
	if [ "$_docbook_makefile" ]; then
		install -Dm644 "$_docbook_makefile" Documentation/DocBook/Makefile
	fi

	# If there's a file called <arch>-dotconfig(-custom),
	# use it to configure the kernel; otherwise use kernel_defconfig or
	# arch defaults and all stuff as modules (allmodconfig).
	local dotconfig="$FILESDIR/${_subarch:-$_arch}-dotconfig"
	if [ -f ${dotconfig}-custom ]; then
		msg_normal "Detected a custom .config file for your arch, using it.\n"
		cp -f ${dotconfig}-custom .config
	elif [ "$kernel_defconfig" ]; then
		msg_normal "Generating .config from $kernel_defconfig...\n"
		${_make} ${make_build_args} ${kernel_defconfig}
	elif [ -f ${dotconfig} ]; then
		msg_normal "Detected a .config file for your arch, using it.\n"
		cp -f ${dotconfig} .config
	else
		msg_normal "Generating .config from allmodconfig...\n"
		${_make} ${make_build_args} allmodconfig
	fi
	${_make} ${make_build_args} oldconfig

	# Merge found .config fragments
	local config_fragments="$(find "${FILESDIR}"/*.config -maxdepth 0 -type f -exec basename {} \; 2>/dev/null | xargs)"
	if [ "$config_fragments" ]; then
		msg_normal "Merging config fragments $config_fragments...\n"
		cp -f ${FILESDIR}/*.config arch/$_archdir/configs/
		${_make} ${make_build_args} $config_fragments
	fi

	# Always use our revision to CONFIG_LOCALVERSION to match our pkg version.
	sed "s|^\(CONFIG_LOCALVERSION=\).*|\1\"_${revision}\"|" -i .config
}

do_build() {
	_kernel_update_make

	#export LDFLAGS=
	${_make} ${makejobs} ${make_build_args} prepare
	${_make} ${makejobs} ${make_build_args} ${make_build_target}
}

do_install() {
	local hdrdest _args mv_debug

	_kernel_update_make

	if [ -z "$make_install_target" ]; then
		if [[ " $make_build_target " = *" dtbs "* ]]; then
			make_install_target+=" dtbs_install"
		fi
		if _kernel_supports_modules; then
			make_install_target+=" modules_install"
		fi
	fi

	: ${make_install_args:=INSTALL_PATH=${DESTDIR}/boot INSTALL_MOD_PATH=${DESTDIR} INSTALL_DTBS_PATH=${DESTDIR}/boot/dtbs/dtbs-${_kernver}}

	# Run depmod after compressing modules - makes depmod.sh a noop
	sed -i '2iexit 0' scripts/depmod.sh

	# Install kernel, modules, DTBs etc.
	${_make} ${makejobs} ${make_install_args} ${make_install_target}

	vinstall .config 644 boot config-${_kernver}
	vinstall System.map 644 boot System.map-${_kernver}
	case "$_archdir" in
		x86) vinstall arch/x86/boot/bzImage 644 boot vmlinuz-${_kernver};;
		arm) vinstall arch/arm/boot/zImage 644 boot;;
		arm64) vinstall arch/arm64/boot/Image 644 boot vmlinux-${_kernver};;
		powerpc)
			# zImage on powerpc is useless as it won't load initramfs
			# raw vmlinux is huge, and this is nostrip, so do it manually
			vinstall vmlinux 644 boot vmlinux-${_kernver}
			/usr/bin/$STRIP ${DESTDIR}/boot/vmlinux-${_kernver}
			;;
		mips) vinstall arch/mips/boot/uImage.bin 644 boot uImage-${_kernver};;
	esac

	# Switch to /usr
	vmkdir usr
	mv ${DESTDIR}/lib ${DESTDIR}/usr

	# Remove firmware stuff provided by the "linux-firmware" pkg
	rm -rf ${DESTDIR}/usr/lib/firmware

	# DKMS prep
	cd ${DESTDIR}/usr/lib/modules/${_kernver}
	rm -f source build
	ln -s ../../../src/kernel-headers-${_kernver} build
	cd ${wrksrc}

	# Install required headers to build external modules
	hdrdest=${DESTDIR}/usr/src/kernel-headers-${_kernver}
	install -Dm644 Makefile ${hdrdest}/Makefile
	install -Dm644 kernel/Makefile ${hdrdest}/kernel/Makefile
	install -Dm644 .config ${hdrdest}/.config
	for file in $(find . -name Kconfig\*); do
		mkdir -p ${hdrdest}/$(dirname $file)
		install -Dm644 $file ${hdrdest}/${file}
	done
	for file in $(find arch/${_archdir} scripts -name module.lds -o -name Kbuild.platforms -o -name Platform); do
		mkdir -p ${hdrdest}/$(dirname $file)
		install -Dm644 $file ${hdrdest}/${file}
	done

	mkdir -p ${hdrdest}/include
	for i in acpi asm-generic clocksource config crypto drm generated linux vdso \
		math-emu media net pcmcia scsi sound trace uapi video xen dt-bindings; do
		if [ -d include/$i ]; then
			cp -a include/$i ${hdrdest}/include
		fi
	done

	mkdir -p ${hdrdest}/arch/${_archdir}
	cp -a arch/${_archdir}/include ${hdrdest}/arch/${_archdir}

	# Remove helper binaries built for host,
	# if generated files from the scripts/ directory need to be included,
	# they need to be copied to ${hdrdest} before this step
	if [ "$CROSS_BUILD" ]; then
		${_make} ${makejobs} ${make_build_args} _mrproper_scripts
		# remove host specific objects as well
		find scripts -name '*.o' -delete
	fi

	# Copy files necessary for later builds, like nvidia and vmware
	cp Module.symvers ${hdrdest}
	cp -a scripts ${hdrdest}
	mkdir -p ${hdrdest}/security/selinux
	cp -a security/selinux/include ${hdrdest}/security/selinux
	mkdir -p ${hdrdest}/tools/include
	cp -a tools/include/tools ${hdrdest}/tools/include

	mkdir -p ${hdrdest}/arch/${_archdir}/kernel
	cp arch/${_archdir}/Makefile ${hdrdest}/arch/${_archdir}
	if [ "$_arch" = "i386" ]; then
		cp arch/x86/Makefile_32.cpu ${hdrdest}/arch/x86
	fi
	if [ "$_archdir" = "x86" ]; then
		cp arch/x86/kernel/asm-offsets.s ${hdrdest}/arch/x86/kernel
	elif [ "$_archdir" = "arm64" ]; then
		cp -a arch/arm64/kernel/vdso ${hdrdest}/arch/arm64/kernel/
	fi

	# add headers for lirc package
	# pci
	for i in bt8xx cx88 saa7134; do
		mkdir -p ${hdrdest}/drivers/media/pci/${i}
		cp -a drivers/media/pci/${i}/*.h ${hdrdest}/drivers/media/pci/${i}
	done
	# usb
	for i in cpia2 em28xx pwc; do
		mkdir -p ${hdrdest}/drivers/media/usb/${i}
		cp -a drivers/media/usb/${i}/*.h ${hdrdest}/drivers/media/usb/${i}
	done
	# i2c
	mkdir -p ${hdrdest}/drivers/media/i2c
	cp drivers/media/i2c/*.h ${hdrdest}/drivers/media/i2c
	for i in cx25840; do
		mkdir -p ${hdrdest}/drivers/media/i2c/${i}
		cp -a drivers/media/i2c/${i}/*.h ${hdrdest}/drivers/media/i2c/${i}
	done

	# Add md headers
	mkdir -p ${hdrdest}/drivers/md
	cp drivers/md/*.h ${hdrdest}/drivers/md

	# Add inotify.h
	mkdir -p ${hdrdest}/include/linux
	cp include/linux/inotify.h ${hdrdest}/include/linux

	# Add wireless headers
	mkdir -p ${hdrdest}/net/mac80211/
	cp net/mac80211/*.h ${hdrdest}/net/mac80211

	# add dvb headers for http://mcentral.de/hg/~mrec/em28xx-new
	mkdir -p ${hdrdest}/drivers/media/dvb-frontends
	cp drivers/media/dvb-frontends/lgdt330x.h \
		${hdrdest}/drivers/media/dvb-frontends/
	cp drivers/media/i2c/msp3400-driver.h ${hdrdest}/drivers/media/i2c/

	# add dvb headers
	mkdir -p ${hdrdest}/drivers/media/usb/dvb-usb
	cp drivers/media/usb/dvb-usb/*.h ${hdrdest}/drivers/media/usb/dvb-usb/
	mkdir -p ${hdrdest}/drivers/media/dvb-frontends
	cp drivers/media/dvb-frontends/*.h ${hdrdest}/drivers/media/dvb-frontends/
	mkdir -p ${hdrdest}/drivers/media/tuners
	cp drivers/media/tuners/*.h ${hdrdest}/drivers/media/tuners/

	# Add xfs and shmem for aufs building
	mkdir -p ${hdrdest}/fs/xfs/libxfs
	mkdir -p ${hdrdest}/mm
	cp fs/xfs/libxfs/xfs_sb.h ${hdrdest}/fs/xfs/libxfs/xfs_sb.h

	# Add objtool binary, needed to build external modules with dkms
	if [ "$_arch" = "x86_64" ]; then
		mkdir -p ${hdrdest}/tools/objtool
		cp tools/objtool/objtool ${hdrdest}/tools/objtool
	fi

	# Remove unneeded architectures
	case "$_arch" in
		i386|x86_64) _args=("arm*" "m*" "p*");;
		arm|arm64) _args=("x86*" "m*" "p*");;
		powerpc) _args=("arm*" "m*" "x86*" "parisc");;
		mips) _args=("arm*" "microblaze" "x86*" "p*");;
	esac
	for arch in alpha arc avr32 blackfin cris frv h8300 \
		ia64 nios2 openrisc "s*" um v850 xtensa "${_args[@]}"; do
		rm -rf ${hdrdest}/arch/${arch} ${hdrdest}/scripts/dtc/include-prefixes/${arch}
	done
	# Keep arch/x86/ras/Kconfig as it is needed by drivers/ras/Kconfig
	mkdir -p ${hdrdest}/arch/x86/ras
	cp -a arch/x86/ras/Kconfig ${hdrdest}/arch/x86/ras/Kconfig

	# Extract debugging symbols and compress modules
	msg_normal "$pkgver: extracting debug info and compressing modules, please wait...\n"
	install -Dm644 vmlinux ${DESTDIR}/usr/lib/debug/boot/vmlinux-${_kernver}
	mv_debug="${XBPS_COMMONDIR}/environment/configure/linux-kernel/mv-debug"
	(
		cd ${DESTDIR}
		export DESTDIR
		find ./ -name '*.ko' -print0 | \
			xargs -0r -n1 -P ${XBPS_MAKEJOBS} ${mv_debug}
	)
	# ... and run depmod again.
	depmod -b ${DESTDIR}/usr -F System.map ${_kernver}
}
