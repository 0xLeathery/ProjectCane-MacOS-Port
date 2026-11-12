#!/usr/bin/env bash
set -euo pipefail

# Builds the libraries the macOS app bundles (FFmpeg, SDL3 and sdl2-compat)
# from source for macOS 26, into build/macos-deps/prefix. The macos-app CMake
# preset links against that prefix.
#
# Homebrew's own builds of these libraries require the macOS version they
# were built on (currently 27), so bundling them would raise the app's
# minimum to that. The versions below match Homebrew's at the time they were
# pinned; the deployment target must match LSMinimumSystemVersion in
# Info.plist.in and CMAKE_OSX_DEPLOYMENT_TARGET in the macos-app preset.
#
# FFmpeg is cut down to what the game uses: MPEG-1/2 video (the cutscenes are
# .m2v files), read from local files and converted with swscale. With nothing
# else enabled it needs no external libraries and stays LGPL.
#
# A finished build is reused until a version, checksum or option below
# changes.

deployment_target="26.0"

ffmpeg_version="9.0.2"
ffmpeg_url="https://ffmpeg.org/releases/ffmpeg-${ffmpeg_version}.tar.xz"
ffmpeg_sha256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"

sdl3_version="3.4.20"
sdl3_url="https://github.com/libsdl-org/SDL/releases/download/release-${sdl3_version}/SDL3-${sdl3_version}.tar.gz"
sdl3_sha256="f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f"

sdl2_compat_version="2.32.74"
sdl2_compat_url="https://github.com/libsdl-org/sdl2-compat/releases/download/release-${sdl2_compat_version}/sdl2-compat-${sdl2_compat_version}.tar.gz"
sdl2_compat_sha256="ec68abde77e2e459c8abc4f9587b8976b5d2a657b2bfda2fb3a079b0f8924588"

ffmpeg_options=(
    --enable-shared
    --disable-static
    --disable-programs
    --disable-doc
    --disable-everything
    --disable-autodetect
    --disable-network
    --disable-avdevice
    --disable-avfilter
    --disable-swresample
    --enable-protocol=file
    --enable-demuxer=mpegvideo,mpegps
    --enable-parser=mpegvideo
    --enable-decoder=mpeg1video,mpeg2video
)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(cd "${script_dir}/../.." && pwd)"
deps_dir="${source_dir}/build/macos-deps"
downloads="${deps_dir}/downloads"
prefix="${deps_dir}/prefix"
stamp="${prefix}/.projectcane-deps"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
    echo "The macOS libraries can only be built on an Apple Silicon Mac." >&2
    exit 1
fi

for tool in cmake ninja make clang curl shasum tar; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "${tool} is required to build the macOS libraries." >&2
        echo "Install the Xcode command line tools (xcode-select --install) and" >&2
        echo "Homebrew's cmake and ninja (brew install cmake ninja)." >&2
        exit 1
    fi
done

# Everything that decides what ends up in the prefix.
recipe="target=${deployment_target}
ffmpeg=${ffmpeg_version} ${ffmpeg_sha256} ${ffmpeg_options[*]}
sdl3=${sdl3_version} ${sdl3_sha256}
sdl2-compat=${sdl2_compat_version} ${sdl2_compat_sha256}"

if [[ -f "${stamp}" && "$(cat "${stamp}")" == "${recipe}" ]]; then
    echo "macOS libraries are up to date in ${prefix}"
    exit 0
fi

# Downloads a source archive once and checks it against its pinned checksum.
fetch() {
    local url="$1" sha256="$2" file
    file="${downloads}/$(basename "${url}")"
    if [[ ! -f "${file}" ]] ||
        [[ "$(shasum -a 256 "${file}" | cut -d ' ' -f 1)" != "${sha256}" ]]; then
        rm -f "${file}"
        echo "Downloading ${url}" >&2
        curl --fail --location --silent --show-error --output "${file}.part" "${url}"
        mv "${file}.part" "${file}"
    fi
    if [[ "$(shasum -a 256 "${file}" | cut -d ' ' -f 1)" != "${sha256}" ]]; then
        echo "$(basename "${file}") does not match its pinned SHA-256 (${sha256})." >&2
        rm -f "${file}"
        exit 1
    fi
    echo "${file}"
}

mkdir -p "${downloads}"
ffmpeg_archive="$(fetch "${ffmpeg_url}" "${ffmpeg_sha256}")"
sdl3_archive="$(fetch "${sdl3_url}" "${sdl3_sha256}")"
sdl2_compat_archive="$(fetch "${sdl2_compat_url}" "${sdl2_compat_sha256}")"

# Rebuild from scratch so nothing from an older recipe is left in the prefix.
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
rm -rf "${prefix}"
mkdir -p "${prefix}"

jobs="$(sysctl -n hw.ncpu)"
export MACOSX_DEPLOYMENT_TARGET="${deployment_target}"

unpack() {
    tar -xf "$1" -C "${work_dir}"
    echo "${work_dir}/$2"
}

cmake_install() {
    local source="$1"
    shift
    cmake -S "${source}" -B "${source}/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
        -DCMAKE_INSTALL_PREFIX="${prefix}" \
        -DCMAKE_PREFIX_PATH="${prefix}" \
        -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
        "$@"
    cmake --build "${source}/build"
    cmake --install "${source}/build"
}

echo "Building FFmpeg ${ffmpeg_version} for macOS ${deployment_target}"
ffmpeg_source="$(unpack "${ffmpeg_archive}" "ffmpeg-${ffmpeg_version}")"
(
    cd "${ffmpeg_source}"
    ./configure \
        --prefix="${prefix}" \
        --cc=clang \
        --arch=aarch64 \
        --extra-cflags="-mmacosx-version-min=${deployment_target}" \
        --extra-ldflags="-mmacosx-version-min=${deployment_target}" \
        "${ffmpeg_options[@]}"
    make -j"${jobs}"
    make install
)

echo "Building SDL ${sdl3_version} for macOS ${deployment_target}"
sdl3_source="$(unpack "${sdl3_archive}" "SDL3-${sdl3_version}")"
cmake_install "${sdl3_source}" \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF

echo "Building sdl2-compat ${sdl2_compat_version} for macOS ${deployment_target}"
sdl2_compat_source="$(unpack "${sdl2_compat_archive}" "sdl2-compat-${sdl2_compat_version}")"
cmake_install "${sdl2_compat_source}" \
    -DSDL2COMPAT_TESTS=OFF \
    -DSDL2COMPAT_STATIC=OFF

printf '%s' "${recipe}" > "${stamp}"
echo "macOS libraries installed in ${prefix}"
