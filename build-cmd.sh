#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

mkdir -p $stage

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

SDBUSCPP_DIR="sdbus-cpp"

build=${AUTOBUILD_BUILD_ID:=0}

# Create the staging folders
mkdir -p "$stage/lib"/{debug,release}
mkdir -p "$stage/include/sdbus-c++"
mkdir -p "$stage/LICENSES"

echo "1.4.0" > "${stage}/VERSION.txt"

pushd "$SDBUSCPP_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
        ;;
        darwin*)
        ;;
        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CFLAGS CPPFLAGS CXXFLAGS
        
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$opts -O3 -ffast-math -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC -D_FORTIFY_SOURCE=2"
 
            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Debug
            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" \
                CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" \
                    cmake ../ -G"Ninja" \
                        -DCMAKE_BUILD_TYPE=Debug \
                        -DCMAKE_C_FLAGS="$DEBUG_CFLAGS" \
                        -DCMAKE_CXX_FLAGS="$DEBUG_CXXFLAGS" \
                        -DCMAKE_INSTALL_PREFIX="$stage/install_debug"

                cmake --build . --config Debug --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config Debug

                mkdir -p ${stage}/lib/debug
                mv ${stage}/install_debug/lib/*.so* ${stage}/lib/debug
            popd

            # Release
            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                    cmake ../ -G"Ninja" \
                        -DCMAKE_BUILD_TYPE=Release \
                        -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                        -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                        -DCMAKE_INSTALL_PREFIX="$stage/install_release"

                cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                cmake --install . --config Release

                mkdir -p ${stage}/lib/release
                mv ${stage}/install_release/lib/*.so* ${stage}/lib/release
            popd

            cp $stage/install_release/include/sdbus-c++/*.* "$stage/include/sdbus-c++"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/sdbus-cpp.txt"
    cp COPYING-LGPL-Exception "$stage/LICENSES/sdbus-cpp-addtl.txt"
popd
