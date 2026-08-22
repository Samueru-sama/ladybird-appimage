#!/bin/sh

set -eu

ARCH=$(uname -m)
VERSION=$(pacman -Q ladybird | awk '{print $2; exit}') # example command to get version of application here
export ARCH VERSION
export OUTPATH=./dist
export ADD_HOOKS="self-updater.bg.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=https://raw.githubusercontent.com/LadybirdBrowser/ladybird/refs/heads/master/Base/res/icons/128x128/app-browser.png
export DESKTOP=https://raw.githubusercontent.com/LadybirdBrowser/ladybird/refs/heads/master/Meta/CMake/freedesktop/org.ladybird.Ladybird.desktop
export ANYLINUX_LIB=1

# Deploy dependencies
quick-sharun \
	/opt/ladybird/usr/bin/*          \
	/opt/ladybird/usr/lib/*          \
	/opt/ladybird/usr/lib/ladybird/* \
	/opt/angle/usr/lib/*             \
	/opt/ladybird/usr/share/*

mv -v ./AppDir/lib/angle/usr/lib/* ./AppDir/lib

# time() is blocked by the default sandbox rules
# but clock_gettime() and gettimeofday() are allowed
cat <<-'EOF' > ./AppDir/.timeshim.c
#define _GNU_SOURCE
#include <time.h>
#include <sys/time.h>

time_t time(time_t *t) {
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        ts.tv_sec = tv.tv_sec;
    }
    if (t)
        *t = ts.tv_sec;
    return ts.tv_sec;
}
EOF

cc -shared -fPIC -O2 -o ./AppDir/lib/timeshim.so ./AppDir/.timeshim.c
echo 'timeshim.so' >> ./AppDir/.preload

# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds, if the test fails due to the app
# having issues running in the CI use --simple-test instead
pacman -S --noconfirm vulkan-swrast # app now needs a vulkan device to launch
quick-sharun --simple-test ./dist/*.AppImage --disable-sandbox
