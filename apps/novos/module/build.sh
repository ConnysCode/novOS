#!/bin/sh
# Builds libnovos-video-backdrop.so into ./output. Runs entirely on this Mac.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
docker build --quiet --platform=linux/amd64 -t novos-module-toolchain "$HERE" >/dev/null
docker run --rm --platform=linux/amd64 -v "$HERE":/module -w /module novos-module-toolchain sh -c '
set -eu
mkdir -p output
QT=/sysroot/usr/include/arm-linux-gnueabi/qt5
/usr/lib/qt5/bin/moc -I$QT -I$QT/QtCore -I$QT/QtQml -I$QT/QtQuick -DQT_PLUGIN video-backdrop.cpp -o output/video-backdrop.moc
arm-linux-gnueabi-g++ -std=c++11 -shared -fPIC -O2 -Wall \
    -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp \
    -DQT_PLUGIN -DQT_NO_DEBUG -DQT_QML_LIB -DQT_QUICK_LIB -DQT_GUI_LIB -DQT_CORE_LIB \
    -Ioutput -I/sysroot/usr/include -I$QT -I$QT/QtCore -I$QT/QtGui -I$QT/QtQml -I$QT/QtQuick \
    video-backdrop.cpp -o output/libnovos-video-backdrop.so -ldl
arm-linux-gnueabi-readelf -h output/libnovos-video-backdrop.so | grep -E "Class|Flags"
arm-linux-gnueabi-readelf -d output/libnovos-video-backdrop.so | grep NEEDED
'
