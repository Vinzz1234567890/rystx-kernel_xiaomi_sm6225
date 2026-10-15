#!/bin/bash
#
# Compile script for vauxite Kernel
# Copyright (C) 2020-2021 Adithya R.

SECONDS=0 # builtin bash timer
ZIPNAME="rystX-fog-$(date '+%Y%m%d-%H%M').zip"
TC_DIR="$(pwd)/tc/clang-r450784e"
AK3_DIR="$(pwd)/android/AnyKernel3"
DEFCONFIG="stock_defconfig"
FRAGMENTS=""

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

export PATH="$TC_DIR/bin:$PATH"
export KBUILD_BUILD_USER=nobody
export KBUILD_BUILD_HOST=android-build

if ! [ -d "$TC_DIR" ]; then
	echo "AOSP clang not found! Cloning to $TC_DIR..."
	if ! git clone --depth=1 -b 14 https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone "$TC_DIR"; then
		echo "Cloning failed! Aborting..."
		exit 1
	fi
fi

if [[ $1 = "-r" || $1 = "--regen" ]]; then
	make O=out ARCH=arm64 $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

if [[ $1 = "-rf" || $1 = "--regen-full" ]]; then
	make O=out ARCH=arm64 $DEFCONFIG
	cp out/.config arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated full defconfig at $DEFCONFIG"
	exit
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
	rm -rf out
fi

mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG
printf 'CONFIG_LITTLE_CPU_MASK=15\nCONFIG_BIG_CPU_MASK=240\nCONFIG_ANDROID_VENDOR_HOOKS=y\n' > out/masks.config
./scripts/kconfig/merge_config.sh -m -O out out/.config $FRAGMENTS out/masks.config
make O=out ARCH=arm64 olddefconfig
yes "" | make O=out ARCH=arm64 syncconfig > /dev/null
grep -q '^CONFIG_TOUCHSCREEN_NT36xxx_HOSTDL_SPI=y' out/.config || { echo "FATAL: NT36xxx SPI driver not enabled"; exit 1; }
grep -q '^CONFIG_LITTLE_CPU_MASK=15' out/.config || { echo "FATAL: LITTLE_CPU_MASK missing"; exit 1; }
grep -q '^CONFIG_ANDROID_VENDOR_HOOKS=y' out/.config || { echo "FATAL: VENDOR_HOOKS missing"; exit 1; }

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 Image.gz 2> >(tee log.txt >&2) || exit $?

kernel="out/arch/arm64/boot/Image.gz"

if [ -f "$kernel" ]; then
	echo -e "\nKernel compiled succesfully! Zipping up...\n"
	if ! git clone -q https://github.com/CHRISL7/AnyKernel3 -b master AnyKernel3; then
		echo -e "\nAnyKernel3 repo not found locally and couldn't clone from GitHub! Aborting..."
		exit 1
	fi
	if [ -f "$AK3_DIR/anykernel.sh" ]; then
		cp "$AK3_DIR/anykernel.sh" AnyKernel3/anykernel.sh
	fi
	cp $kernel AnyKernel3
	cp out/.config AnyKernel3/kernel.config
	rm -rf out/arch/arm64/boot
	cd AnyKernel3
	zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo "Zip: $ZIPNAME"
else
	echo -e "\nCompilation failed!"
	exit 1
fi

