#!/bin/bash

# Simple script for automatic daily testing of gcc+avrlibc ToT.

BINUTILS_URL=git://sourceware.org/git/binutils-gdb.git
GCC_URL=https://github.com/mirrors/gcc
AVRLIBC_URL=https://github.com/dinuxbg/avr-libc
WINAVR_URL=https://gitlab.com/dinuxbg/winavr-code
BB_ARCH=avr

true ${GCC_BRANCH:=master}

# Who to send a short regression report to
REGRESSION_RECIPIENTS="dinuxbg@gmail.com"

# Default full report recipient. Caller can set this
# environment variable to override the default.
true ${SUMMARY_RECIPIENTS:=dinuxbg@gmail.com}


bb_daily_target_test()
{
  local PREV_BUILD_TAG=${1}
  local BUILD_TAG=${2}

  bb_clean

  bb_update_source binutils ${BINUTILS_URL}
  bb_update_source gcc ${GCC_URL} ${GCC_BRANCH}
  bb_update_source avrlibc ${AVRLIBC_URL}
  bb_update_source winavr ${WINAVR_URL}

  # Prepare tree for release, and write proper versioning info.
  pushd ${WORKSPACE}/gcc || error "failed to enter gcc"
  ./contrib/gcc_update origin ${GCC_BRANCH}
  popd

  local GCC_TOT=`cd gcc && git rev-parse HEAD`
  local BINUTILS_TOT=`cd binutils && git rev-parse HEAD`
  local AVRLIBC_TOT=`cd avrlibc && git rev-parse HEAD`
  local WINAVR_URL=`cd winavr && git rev-parse HEAD`

  echo "gcc ${GCC_TOT}" >> ${LOGDIR}/${BUILD_TAG}/versions.txt
  echo "binutils ${BINUTILS_TOT}" >> ${LOGDIR}/${BUILD_TAG}/versions.txt
  echo "avr-libc ${AVRLIBC_TOT}" >> ${LOGDIR}/${BUILD_TAG}/versions.txt
  echo "winavr ${WINAVR_URL}" >> ${LOGDIR}/${BUILD_TAG}/versions.txt

  # Setup avrtest, per:
  #    https://sourceforge.net/p/winavr/code/HEAD/tree/trunk/avrtest/
  #    https://lists.gnu.org/archive/html/avr-gcc-list/2009-09/msg00016.html
  export DEJAGNU=${PREFIX}/dejagnurc
  mkdir -p `dirname ${DEJAGNU}`
  echo "# WARNING - automatically generated!" > ${DEJAGNU}
  echo "set avrtest_dir \"${WORKSPACE}/winavr/avrtest\"" >> ${DEJAGNU}
  echo "set avrlibc_include_dir \"${PREFIX}/avr/include\"" >> ${DEJAGNU}
  echo 'set boards_dir {}' >> ${DEJAGNU}
  echo 'lappend boards_dir "${avrtest_dir}/dejagnuboards"' >> ${DEJAGNU}

  # Build binutils
  bb_config binutils "--disable-gdb --target=avr"
  bb_make binutils "-j`nproc`"
  bb_make binutils "install"

  export PATH=${PREFIX}/bin:${PATH}

  bb_config gcc "--target=avr --enable-languages=c,c++ --disable-nls --disable-libssp --with-dwarf2"
  bb_make gcc "-j`nproc`"
  bb_make gcc "install"

  # Libc
  (cd ${WORKSPACE}/avrlibc && ./bootstrap) || error "failed to bootstrap avr-libc source"
  bb_config avrlibc '--host=avr'
  bb_make avrlibc "-j`nproc`"
  bb_make avrlibc "install"

  # avrtest
  bb_source_command winavr "make -C avrtest"

  # Get the simulator under PATH. Needed for gcc test suite.
  export PATH=${WORKSPACE}/winavr/avrtest:${PATH}

  # Test binutils. Do not let random test case failures to mark
  # the entire build as bad.
  bb_config binutils "--disable-gdb --target=avr"
  bb_make binutils "-j`nproc`"
  bb_make binutils "install"
  bb_make --ignore-errors binutils "-k check RUNTESTFLAGS=--target_board=atmega128-sim"

  # Test GCC
  bb_make gcc "-j`nproc` check-gcc-c RUNTESTFLAGS=--target_board=atmega128-sim"
  bb_make gcc "-j`nproc` check-gcc-c++ RUNTESTFLAGS=--target_board=atmega128-sim"

  # Save all the logs
  bb_gather_log_files ${BUILD_TAG}

  # Send to real mailing list,
  pushd ${WORKSPACE}/avr-gcc-build || error "failed to enter avr-gcc-build"
  ../gcc/contrib/test_summary -m ${SUMMARY_RECIPIENTS} | sh
  popd

  bb_check_for_regressions ${PREV_BUILD_TAG} ${BUILD_TAG}
}


. `dirname ${0}`/buildbot-lib.sh

bb_init ${@}

# Workaround debian's inability to set heirloom as default
# mkdir -p ${WORKSPACE}/tools/bin
# ln -s `which s-nail` ${WORKSPACE}/tools/bin/Mail 1>/dev/null 2>&1
# export PATH=${WORKSPACE}/tools/bin:${PATH}

bb_daily_build
