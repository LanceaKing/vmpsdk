#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$root/.build/work"
out="$root/.build/artifacts"
case "${1:?Expected linux, gcc, fpc, xcode-markers, or xcode-licensing}" in
  linux)
    cd "$work/Examples/Code Markers/GCC"
    bash makeit.sh
    for bits in 32 64; do
      arch=x86
      [[ $bits == 64 ]] && arch=x64
      mkdir -p "$out/linux-$arch"
      cp "Project1-linux-$arch" "libVMProtectSDK$bits.so" "$out/linux-$arch/"
      python3 "$root/ci/smoke.py" "$out/linux-$arch/Project1-linux-$arch"
    done
    # Equivalent to MinGW/makeit.bat with the installed compiler prefix.
    cd "$work/Examples/Code Markers/MinGW"
    mkdir -p "$out/mingw-x86" "$root/.build/mingw-includes"
    # Windows ignores case; Linux needs an external alias for #include "Resource.h".
    ln -s "$PWD/resource.h" "$root/.build/mingw-includes/Resource.h"
    i686-w64-mingw32-windres Resource.rc -O coff -o Resource.o
    i686-w64-mingw32-g++ -I "$root/.build/mingw-includes" -mwindows Project1.cpp Resource.o VMProtectSDK32.a \
      -o "$out/mingw-x86/Project1.exe" -Os -static-libgcc -static-libstdc++ \
      "-Wl,-Map=$out/mingw-x86/Project1.map"
    cp VMProtectSDK32.dll "$out/mingw-x86/"
    ;;
  gcc)
    cd "$work/Examples/Code Markers/GCC"
    bash makeit.sh
    mkdir -p "$out/gcc-x64"
    cp Project1 libVMProtectSDK.dylib "$out/gcc-x64/"
    python3 "$root/ci/smoke.py" "$out/gcc-x64/Project1"
    ;;
  fpc)
    cd "$work/Examples/Code Markers/Free Pascal"
    # Original makeit.sh options plus the current SDK and library search paths.
    fpc -g- -b- -Tdarwin -Px86_64 -Sd -Wb -Fl. "-XR$(xcrun --show-sdk-path)" Project1.pas
    strip ./Project1
    mkdir -p "$out/fpc-x64"
    cp Project1 libVMProtectSDK.dylib "$out/fpc-x64/"
    python3 "$root/ci/smoke.py" "$out/fpc-x64/Project1"
    ;;
  xcode-markers|xcode-licensing)
    target=Project1
    folder='Code Markers'
    if [[ $1 == xcode-licensing ]]; then
      target='VMProtect Licensing Test'
      folder=Licensing
    fi
    cd "$work/Examples/$folder/Xcode"
    xcodebuild -project "$target.xcodeproj" -target "$target" -configuration Release \
      -sdk macosx ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=10.13 \
      CLANG_CXX_LIBRARY=libc++ CLANG_CXX_LANGUAGE_STANDARD=gnu++14 \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      "SYMROOT=$root/.build/xcode-products" "OBJROOT=$root/.build/xcode-objects" \
      "CONFIGURATION_BUILD_DIR=$out" \
      "LIBRARY_SEARCH_PATHS=$work/Lib/OSX" build
    # The dylib install name is @executable_path/libVMProtectSDK.dylib.
    cp "$work/Lib/OSX/libVMProtectSDK.dylib" "$out/$target.app/Contents/MacOS/"
    test -x "$out/$target.app/Contents/MacOS/$target"
    ;;
  *) echo "Unknown build: $1" >&2; exit 2 ;;
esac
