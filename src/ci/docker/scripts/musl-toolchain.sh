#!/bin/sh
# This script runs `musl-cross-make` to prepare C toolchain (Binutils, GCC, musl itself)
# and builds static libunwind that we distribute for static target.
#
# Versions of the toolchain components are configurable in `musl-cross-make/Makefile` and
# musl unlike GLIBC is forward compatible so upgrading it shouldn't break old distributions.
# Right now we have: Binutils 2.31.1, GCC 9.2.0, musl 1.1.24.

# ignore-tidy-linelength

set -ex

hide_output() {
  set +x
  on_err="
echo ERROR: An error was encountered with the build.
cat /tmp/build.log
exit 1
"
  trap "$on_err" ERR
  bash -c "while true; do sleep 30; echo \$(date) - building ...; done" &
  PING_LOOP_PID=$!
  "$@" &> /tmp/build.log
  trap - ERR
  kill $PING_LOOP_PID
  rm /tmp/build.log
  set -x
}

ARCH=$1
TARGET=$ARCH-linux-musl

# Don't depend on the mirrors of sabotage linux that musl-cross-make uses.
LINUX_HEADERS_SITE=https://ci-mirrors.rust-lang.org/rustc/sabotage-linux-tarballs

OUTPUT=/usr/local
shift

# Ancient binutils versions don't understand debug symbols produced by more recent tools.
# Apparently applying `-fPIC` everywhere allows them to link successfully.
# Enable debug info. If we don't do so, users can't debug into musl code,
# debuggers can't walk the stack, etc. Fixes #90103.
export CFLAGS="-fPIC -g1 $CFLAGS"

git clone https://github.com/richfelker/musl-cross-make # -b v0.9.9
cd musl-cross-make
# First version that supports musl 1.2.3:
git checkout d06727c1c4574173ed9349996c63d50f68b8e6c5

hide_output make -j$(nproc) TARGET=$TARGET MUSL_VER=1.2.3 LINUX_HEADERS_SITE=$LINUX_HEADERS_SITE
hide_output make install TARGET=$TARGET MUSL_VER=1.2.3 LINUX_HEADERS_SITE=$LINUX_HEADERS_SITE OUTPUT=$OUTPUT

cd -

# Install musl library to make binaries executable
ln -s $OUTPUT/$TARGET/lib/libc.so /lib/ld-musl-$ARCH.so.1
echo $OUTPUT/$TARGET/lib >> /etc/ld-musl-$ARCH.path

# Now when musl bootstraps itself create proper toolchain symlinks to make build and tests easier
if [ "$REPLACE_CC" = "1" ]; then
    for exec in cc gcc; do
        ln -s $TARGET-gcc /usr/local/bin/$exec
    done
    for exec in cpp c++ g++; do
        ln -s $TARGET-g++ /usr/local/bin/$exec
    done
fi
