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

# Use the system ANGLE package instead of building it via vcpkg, it is a huge
# Chromium-based build and the Arch package ships the same chromium/7258 version
make-aur-package --chaotic-aur angle

# If the application needs to be manually built that has to be done down here
echo "Building Ladybird..."
echo "---------------------------------------------------------------"
git clone https://github.com/LadybirdBrowser/ladybird ./ladybird
cd ./ladybird

VERSION=r$(git rev-list --count HEAD).$(git rev-parse --short HEAD)
echo "$VERSION" > ~/version

# vcpkg is used to build the third party dependencies, the checkout
# needs to match the builtin-baseline of the manifest
git clone https://github.com/microsoft/vcpkg.git ./vcpkg
git -C ./vcpkg checkout "$(awk -F'"' '/"builtin-baseline"/{print $4; exit}' vcpkg.json)"

# Drop angle from the vcpkg manifest so the system package is used instead
python3 - <<'EOF'
import json
with open('vcpkg.json') as f:
    data = json.load(f)
data['dependencies'] = [d for d in data['dependencies'] if not (isinstance(d, dict) and d.get('name') == 'angle')]
data['overrides'] = [d for d in data['overrides'] if d.get('name') != 'angle']
with open('vcpkg.json', 'w') as f:
    json.dump(data, f, indent=2)
EOF

export VCPKG_ROOT="$PWD/vcpkg"
export VCPKG_DISABLE_METRICS="true"
export RUSTUP_TOOLCHAIN=stable

# Apply required patches:
# From the AUR 'ladybird' package:
# - gcc-wno-restrict: GCC emits -Wrestrict warnings which break the build because of -Werror
# Needed for the AppImage:
# - sandbox-allow-time: allow the time() syscall in the seccomp sandbox
# - allow-readv-writev-in-seccomp-sandbox: curl/OpenSSL use readv() for TLS data (https://github.com/NixOS/nixpkgs/pull/539002)
# - ca-certificates: allow reading CA bundles in the sandbox and support SSL_CERT_FILE
for patch in ../patches/*.patch; do
	patch -N -p1 --forward -i "$patch"
done

# The Release preset builds shared libraries (lagom + vcpkg deps), which keeps the
# binaries small and avoids symbol collisions with the bundled Qt
cmake \
	--preset Release \
	-B ./Build/release \
	-S ./ \
	-DCMAKE_BUILD_TYPE=Release \
	-DENABLE_LTO_FOR_RELEASE=OFF \
	-DENABLE_INSTALL_HEADERS=OFF \
	-DCMAKE_INSTALL_PREFIX='/opt/ladybird/usr' \
	-DCMAKE_INSTALL_LIBEXECDIR='lib/ladybird' \
	-DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
	-DVCPKG_ROOT="$VCPKG_ROOT" \
	-Wno-dev

cmake --build ./Build/release
cmake --install ./Build/release
