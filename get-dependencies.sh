#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
	autoconf-archive \
	cmake            \
	nasm             \
	ninja            \
	python           \
	qt6-positioning  \
	rust             \
	tar              \
	zip

if [ "$ARCH" = 'x86_64' ]; then
	pacman -Syu --noconfirm libva-intel-driver
fi

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano intel-media-driver-mini ffmpeg-mini

# If the application needs to be manually built that has to be done down here
echo "Building Ladybird..."
echo "---------------------------------------------------------------"
git clone https://github.com/LadybirdBrowser/ladybird ./ladybird
cd ./ladybird

VERSION=r$(git rev-list --count HEAD).$(git rev-parse --short HEAD)
echo "$VERSION" > ~/version

# vcpkg is used to build all the third party dependencies statically,
# the checkout needs to match the builtin-baseline of the manifest
git clone https://github.com/microsoft/vcpkg.git ./vcpkg
git -C ./vcpkg checkout "$(awk -F'"' '/"builtin-baseline"/{print $4; exit}' vcpkg.json)"

export VCPKG_ROOT="$PWD/vcpkg"
export VCPKG_DISABLE_METRICS="true"
export RUSTUP_TOOLCHAIN=stable

# Apply required patches:
# From the AUR 'ladybird' package:
# - link-static-harfbuzz-fontconfig: static vcpkg build needs these symbols force-included
# - gcc-wno-restrict: GCC emits -Wrestrict warnings which break the build because of -Werror
# Needed for the AppImage:
# - sandbox-allow-time: allow the time() syscall in the seccomp sandbox
# - allow-readv-writev-in-seccomp-sandbox: curl/OpenSSL use readv() for TLS data (https://github.com/NixOS/nixpkgs/pull/539002)
# - ca-certificates: allow reading CA bundles in the sandbox and support SSL_CERT_FILE
for patch in ../patches/*.patch; do
	patch -N -p1 --forward -i "$patch"
done

cmake \
	--preset Distribution \
	-B ./Build/distribution \
	-S ./ \
	-DENABLE_INSTALL_HEADERS=OFF \
	-DCMAKE_INSTALL_PREFIX='/opt/ladybird/usr' \
	-DCMAKE_INSTALL_LIBEXECDIR='lib/ladybird' \
	-DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
	-DVCPKG_ROOT="$VCPKG_ROOT" \
	-Wno-dev

cmake --build ./Build/distribution
cmake --install ./Build/distribution
