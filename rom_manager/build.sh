#!/usr/bin/env bash
# Builds Dolphin's dolphin-tool CLI (this checkout: branch rom_manager of nero81af/dolphin, 2609a with
# our patches) as a standalone Android PIE executable (static libc++) and installs it as src/RomManager/Android/app/src/main/jniLibs/<abi>/libdolphintool.so.
#   ./build.sh            Android builds
#   ./build.sh --windows  win-x64 build with MSVC (static CRT) into src/RomManager/Tools/win-x64/dolphin-tool.exe
# Override ANDROID_SDK, ANDROID_NDK, CMAKE_BIN or WIN_CMAKE if the defaults below do not match.
set -euo pipefail

API=30
ABIS="arm64-v8a x86_64"
OPTIONS=(
	-DENABLE_HEADLESS=ON
	-DENABLE_CLI_TOOL=ON
	-DENABLE_NOGUI=OFF
	-DENABLE_QT=OFF
	-DENABLE_TESTS=OFF
	-DENABLE_VULKAN=OFF
	-DENABLE_EGL=OFF
	-DENABLE_X11=OFF
	-DENABLE_ALSA=OFF
	-DENABLE_PULSEAUDIO=OFF
	-DENABLE_CUBEB=OFF
	-DENABLE_SDL=OFF
	-DENABLE_LLVM=OFF
	-DENABLE_EVDEV=OFF
	-DENABLE_HWDB=OFF
	-DENABLE_AUTOUPDATE=OFF
	-DENABLE_ANALYTICS=OFF
	-DENCODE_FRAMEDUMPS=OFF
	-DUSE_DISCORD_PRESENCE=OFF
	-DUSE_MGBA=OFF
	-DUSE_RETRO_ACHIEVEMENTS=OFF
	-DUSE_UPNP=OFF
	-DUSE_SYSTEM_LIBS=OFF
)

native_path() {
	if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

unix_path() {
	if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else echo "$1"; fi
}

ROOT=$(native_path "$(cd "$(dirname "$0")" && pwd)")
SRC=$(dirname "$ROOT")
JNILIBS=$ROOT/../../../src/RomManager/Android/app/src/main/jniLibs

ANDROID_SDK=$(native_path "${ANDROID_SDK:-${ANDROID_HOME:-C:/Users/nero81af/AppData/Local/Android/Sdk}}")
ANDROID_NDK=$(native_path "${ANDROID_NDK:-$ANDROID_SDK/ndk/29.0.14206865}")
CMAKE_BIN=$(native_path "${CMAKE_BIN:-$ANDROID_SDK/cmake/3.31.6/bin}")
export PATH="$(unix_path "$CMAKE_BIN"):$PATH"

LLVM_BIN=$(echo "$ANDROID_NDK"/toolchains/llvm/prebuilt/*/bin)
STRIP=$LLVM_BIN/llvm-strip
READELF=$LLVM_BIN/llvm-readelf

# the submodules dolphin-tool needs (the others have update = none), if the clone was not recursive
git -C "$SRC" -c core.autocrlf=false submodule update --init --depth 1 --jobs 8

if [ "${1:-}" = "--windows" ]; then
	WIN_CMAKE=${WIN_CMAKE:-"C:/Program Files/CMake/bin/cmake.exe"}
	build=$ROOT/build/windows
	out=$ROOT/../../../src/RomManager/Tools/win-x64/dolphin-tool.exe

	"$WIN_CMAKE" -S "$SRC" -B "$build" -A x64 \
		-DCMAKE_POLICY_DEFAULT_CMP0091=NEW \
		-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded \
		"${OPTIONS[@]}"

	"$WIN_CMAKE" --build "$build" --config Release --target dolphin-tool --parallel

	mkdir -p "$(dirname "$out")"
	cp "$build/Binaries/DolphinTool.exe" "$out"
	echo "windows: $out ($(wc -c < "$out") bytes)"
	exit 0
fi

for abi in $ABIS; do
	build=$ROOT/build/$abi

	cmake -S "$SRC" -B "$build" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
		-DANDROID_ABI="$abi" \
		-DANDROID_PLATFORM="android-$API" \
		-DANDROID_STL=c++_static \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_C_FLAGS=-UANDROID \
		-DCMAKE_CXX_FLAGS=-UANDROID \
		"${OPTIONS[@]}"

	cmake --build "$build" --target dolphin-tool --parallel

	out=$JNILIBS/$abi/libdolphintool.so
	mkdir -p "$(dirname "$out")"
	"$STRIP" --strip-all -o "$out" "$build/Binaries/dolphin-tool"

	needed=$("$READELF" -d "$out" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | tr '\n' ' ')
	if echo "$needed" | grep -q 'c++_shared'; then
		echo "error: $out depends on libc++_shared.so" >&2
		exit 1
	fi
	echo "$abi: $out ($(wc -c < "$out") bytes) NEEDED: $needed"
done
