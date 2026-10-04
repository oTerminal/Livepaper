#!/bin/bash
# Builds the shader tools Livepaper bundles: glslang's and SPIRV-Cross's command
# lines for macOS arm64, which translate a Wallpaper Engine scene's shaders to
# Metal at import.
#
#   Helpers/shader-tools/build.sh      or      make shader-tools
#
# Output, in Helpers/shader-tools/out/ (ignored by git, published by CI):
#   glslang, spirv-cross    the binaries
#   glslang-<version>.tar.gz, SPIRV-Cross-<version>.tar.gz
#                           the exact sources they were built from
#   BUILD-INFO.txt          versions, sha256s, flags, what the binaries report
#   build.sh, licenses/     this script and the licence texts
#
# The sources are compiled with the system's clang, file by file from the lists
# below, without CMake or Python. To move to other releases: change a version and
# its sha256, check the sha256 against a second source (the hash Homebrew's formula
# pins for the same URL), compare the lists below with the release's CMakeLists.txt
# files, run the script, and copy the licence texts again if it asks.

set -euo pipefail

GLSLANG_VERSION="16.6.0"
# sha256 of glslang's 16.6.0 tag archive on GitHub. Checked on 2026-09-23: it is
# the hash Homebrew's glslang formula pins for the same URL.
GLSLANG_SHA256="9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2"

SPIRV_CROSS_VERSION="vulkan-sdk-1.4.357.0"
# sha256 of SPIRV-Cross's vulkan-sdk-1.4.357.0 tag archive on GitHub. Checked on
# 2026-09-23: it is the hash Homebrew's spirv-cross formula pins for the same URL.
SPIRV_CROSS_SHA256="97c910326afdd44d794ce8561326fa675fd1958b27142f03295403044d639639"

# The app's deployment target. An older SDK cannot target it; see below.
WANTED_DEPLOYMENT_TARGET="26.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$HERE/src"
OUT_DIR="$HERE/out"
LICENSES_DIR="$HERE/licenses"
BUILD_DIR="$SRC_DIR/build"
BUILD_INFO="$OUT_DIR/BUILD-INFO.txt"

GLSLANG_ARCHIVE_NAME="glslang-$GLSLANG_VERSION.tar.gz"
GLSLANG_ARCHIVE="$SRC_DIR/$GLSLANG_ARCHIVE_NAME"
GLSLANG_URL="https://github.com/KhronosGroup/glslang/archive/refs/tags/$GLSLANG_VERSION.tar.gz"
GLSLANG_TREE="$SRC_DIR/glslang-$GLSLANG_VERSION"

SPIRV_CROSS_ARCHIVE_NAME="SPIRV-Cross-$SPIRV_CROSS_VERSION.tar.gz"
SPIRV_CROSS_ARCHIVE="$SRC_DIR/$SPIRV_CROSS_ARCHIVE_NAME"
SPIRV_CROSS_URL="https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/$SPIRV_CROSS_VERSION.tar.gz"
SPIRV_CROSS_TREE="$SRC_DIR/SPIRV-Cross-$SPIRV_CROSS_VERSION"

# Each licence text as the release ships it, and the name it has in licenses/.
# glslang's LICENSE.txt holds every licence of the project; LICENSES/ has them one
# by one. These are the ones REUSE.toml gives to the files compiled below: the
# core (BSD-3-Clause), the resource limits (BSD-2-Clause), the SPIR-V headers
# (MIT-Khronos-old), bitutils.h and hex_float.h (Apache-2.0), the preprocessor
# (AML-glslang), and the Bison-generated parser, glslang_tab.cpp (GPL-3.0 or later
# with the Bison exception, which lets it go into a larger work under any terms).
GLSLANG_LICENSE_FILES=(
	"LICENSE.txt:glslang-LICENSE.txt"
	"LICENSES/BSD-3-Clause.txt:glslang-BSD-3-Clause.txt"
	"LICENSES/BSD-2-Clause.txt:glslang-BSD-2-Clause.txt"
	"LICENSES/MIT-Khronos-old.txt:glslang-MIT-Khronos-old.txt"
	"LICENSES/Apache-2.0.txt:glslang-Apache-2.0.txt"
	"LICENSES/AML-glslang.txt:glslang-AML-glslang.txt"
	"LICENSES/GPL-3.0-or-later.txt:glslang-GPL-3.0-or-later.txt"
	"LICENSES/Bison-exception-2.2.txt:glslang-Bison-exception-2.2.txt"
)
# SPIRV-Cross's own files are Apache-2.0 or MIT; LICENSE is the Apache-2.0 text.
# The SPIR-V headers it compiles in (spirv.hpp, GLSL.std.450.h) are MIT, and
# Khronos's free-use licence in .reuse/dep5.
SPIRV_CROSS_LICENSE_FILES=(
	"LICENSE:SPIRV-Cross-LICENSE"
	"LICENSES/MIT.txt:SPIRV-Cross-MIT.txt"
	"LICENSES/LicenseRef-KhronosFreeUse.txt:SPIRV-Cross-LicenseRef-KhronosFreeUse.txt"
)

# Only the system toolchain. Nothing from Homebrew can be found, so nothing from
# Homebrew can be linked in.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export LC_ALL=C
unset CPATH CPLUS_INCLUDE_PATH LIBRARY_PATH SDKROOT

say() { printf 'shader tools: %s\n' "$*"; }
die() { printf 'shader tools: error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] \
	|| die "this builds and then runs arm64 macOS binaries; run it on an Apple silicon Mac"

# --- Deployment target -------------------------------------------------------

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
DEPLOYMENT_TARGET="$WANTED_DEPLOYMENT_TARGET"
if (( ${SDK_VERSION%%.*} < ${WANTED_DEPLOYMENT_TARGET%%.*} )); then
	DEPLOYMENT_TARGET="${SDK_VERSION%%.*}.0"
	say "warning: the macOS $SDK_VERSION SDK cannot target $WANTED_DEPLOYMENT_TARGET;" \
		"building for $DEPLOYMENT_TARGET. Do not ship these binaries."
fi
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"

# --- Sources and flags -------------------------------------------------------
# No paths in the flags: the quick exit below compares them with BUILD-INFO.txt.
# The include directories are added when compiling.

CXX=(xcrun --sdk macosx clang++)
COMMON_FLAGS=(-arch arm64 "-mmacosx-version-min=$DEPLOYMENT_TARGET" -O2 -DNDEBUG
	-fstack-protector-strong)
LINK_FLAGS=(-arch arm64 "-mmacosx-version-min=$DEPLOYMENT_TARGET")

# glslang's StandAlone front end and the libraries it links, as glslang's
# CMakeLists.txt files list them, less two things we never feed it: HLSL input
# (ENABLE_HLSL off, so glslang/HLSL/ is left out) and the SPIR-V optimiser
# (ENABLE_OPT=0, so no SPIRV-Tools). The C interfaces are left out too. With
# SPIR-V output on, glslang needs no SPIRV-Headers: it carries SPIRV/spirv.hpp11.
GLSLANG_FLAGS=(-std=c++17 -fno-rtti -fno-exceptions
	-DENABLE_SPIRV -DENABLE_OPT=0 -DGLSLANG_OSINCLUDE_UNIX)
GLSLANG_SOURCES=(
	glslang/GenericCodeGen/CodeGen.cpp
	glslang/GenericCodeGen/Link.cpp
	glslang/MachineIndependent/glslang_tab.cpp
	glslang/MachineIndependent/attribute.cpp
	glslang/MachineIndependent/Constant.cpp
	glslang/MachineIndependent/iomapper.cpp
	glslang/MachineIndependent/InfoSink.cpp
	glslang/MachineIndependent/Initialize.cpp
	glslang/MachineIndependent/IntermTraverse.cpp
	glslang/MachineIndependent/Intermediate.cpp
	glslang/MachineIndependent/ParseContextBase.cpp
	glslang/MachineIndependent/ParseHelper.cpp
	glslang/MachineIndependent/PoolAlloc.cpp
	glslang/MachineIndependent/RemoveTree.cpp
	glslang/MachineIndependent/Scan.cpp
	glslang/MachineIndependent/ShaderLang.cpp
	glslang/MachineIndependent/SpirvIntrinsics.cpp
	glslang/MachineIndependent/SymbolTable.cpp
	glslang/MachineIndependent/Versions.cpp
	glslang/MachineIndependent/intermOut.cpp
	glslang/MachineIndependent/limits.cpp
	glslang/MachineIndependent/linkValidate.cpp
	glslang/MachineIndependent/parseConst.cpp
	glslang/MachineIndependent/reflection.cpp
	glslang/MachineIndependent/preprocessor/Pp.cpp
	glslang/MachineIndependent/preprocessor/PpAtom.cpp
	glslang/MachineIndependent/preprocessor/PpContext.cpp
	glslang/MachineIndependent/preprocessor/PpScanner.cpp
	glslang/MachineIndependent/preprocessor/PpTokens.cpp
	glslang/MachineIndependent/propagateNoContraction.cpp
	glslang/OSDependent/Unix/ossource.cpp
	glslang/ResourceLimits/ResourceLimits.cpp
	SPIRV/GlslangToSpv.cpp
	SPIRV/InReadableOrder.cpp
	SPIRV/Logger.cpp
	SPIRV/SpvBuilder.cpp
	SPIRV/SpvPostProcess.cpp
	SPIRV/doc.cpp
	SPIRV/SpvTools.cpp
	SPIRV/disassemble.cpp
	StandAlone/StandAlone.cpp
)

# SPIRV-Cross's command line and the libraries it links, as its CMakeLists.txt
# lists them (the C API left out). Its CLI needs every back end, not only MSL.
SPIRV_CROSS_FLAGS=(-std=c++11 -DHAVE_SPIRV_CROSS_GIT_VERSION)
SPIRV_CROSS_SOURCES=(
	spirv_cross.cpp
	spirv_parser.cpp
	spirv_cross_parsed_ir.cpp
	spirv_cfg.cpp
	spirv_glsl.cpp
	spirv_cpp.cpp
	spirv_msl.cpp
	spirv_hlsl.cpp
	spirv_reflect.cpp
	spirv_cross_util.cpp
	main.cpp
)

GLSLANG_FLAGS_LINE="${COMMON_FLAGS[*]} ${GLSLANG_FLAGS[*]}"
SPIRV_CROSS_FLAGS_LINE="${COMMON_FLAGS[*]} ${SPIRV_CROSS_FLAGS[*]}"
LINK_FLAGS_LINE="${LINK_FLAGS[*]}"

# What `spirv-cross --revision` prints starts with this. It is written into the
# build (gitversion.h), with the release's commit time, as CMake would from git.
SPIRV_CROSS_REVISION_PREFIX="Git commit: $SPIRV_CROSS_VERSION Timestamp: "

# --- Checks on built binaries ------------------------------------------------

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

SMOKE_DIR=""
trap '[[ -z "$SMOKE_DIR" ]] || rm -rf "$SMOKE_DIR"' EXIT

check_binary() {
	local binary="$1" libraries foreign

	[[ -x "$binary" ]] || die "$binary is missing or not executable"
	[[ "$(lipo -archs "$binary")" == "arm64" ]] || die "$binary is not an arm64-only binary"

	libraries="$(otool -L "$binary" | tail -n +2 | awk '{print $1}')"
	foreign="$(grep -v -e '^/usr/lib/' -e '^/System/Library/' <<<"$libraries" || true)"
	[[ -z "$foreign" ]] || die "$binary links outside the system: $foreign"
}

# The four calls the importer makes, on a vertex and fragment pair that includes a
# header of its own, as a scene's shaders do.
smoke_test() {
	local glslang="$1" spirv_cross="$2" stage

	SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/livepaper-shader-tools.XXXXXX")"
	mkdir "$SMOKE_DIR/include"
	cat >"$SMOKE_DIR/include/common.h" <<-'EOF'
		vec4 lpTint(vec4 colour, float amount) { return vec4(colour.rgb, colour.a * amount); }
	EOF
	cat >"$SMOKE_DIR/in.vert" <<-'EOF'
		#version 450
		#extension GL_GOOGLE_include_directive : enable
		#include "common.h"
		layout(location = 0) in vec3 a_Position;
		layout(location = 1) in vec2 a_TexCoord;
		layout(location = 0) out vec2 v_TexCoord;
		void main() {
		    v_TexCoord = a_TexCoord;
		    gl_Position = lpTint(vec4(a_Position, 1.0), 1.0);
		}
	EOF
	cat >"$SMOKE_DIR/in.frag" <<-'EOF'
		#version 450
		#extension GL_GOOGLE_include_directive : enable
		#include "common.h"
		layout(set = 0, binding = 0) uniform sampler2D g_Texture0;
		layout(std140, set = 1, binding = 0) uniform LPUniforms { float g_Alpha; };
		layout(location = 0) in vec2 v_TexCoord;
		layout(location = 0) out vec4 _lpFragColor;
		void main() {
		    _lpFragColor = lpTint(texture(g_Texture0, v_TexCoord), g_Alpha);
		}
	EOF

	for stage in vert frag; do
		"$glslang" -E "-I$SMOKE_DIR/include" "$SMOKE_DIR/in.$stage" >"$SMOKE_DIR/pre.$stage" \
			|| die "glslang -E failed on the $stage shader: $(cat "$SMOKE_DIR/pre.$stage")"
		grep -q 'vec4 lpTint(' "$SMOKE_DIR/pre.$stage" \
			|| die "glslang -E did not resolve the #include in the $stage shader"

		# As the importer does: the directives out, one #version back in.
		{
			echo "#version 450"
			grep -v -E '^[[:space:]]*#[[:space:]]*(version|extension|line|pragma)' "$SMOKE_DIR/pre.$stage"
		} >"$SMOKE_DIR/lp.$stage"

		"$glslang" -V --target-env vulkan1.1 -o "$SMOKE_DIR/$stage.spv" "$SMOKE_DIR/lp.$stage" \
			>"$SMOKE_DIR/glslang.log" 2>&1 \
			|| die "glslang -V failed on the $stage shader: $(cat "$SMOKE_DIR/glslang.log")"
		[[ "$(od -An -tx1 -N4 "$SMOKE_DIR/$stage.spv" | tr -d ' \n')" == "03022307" ]] \
			|| die "glslang -V did not write SPIR-V for the $stage shader"

		"$spirv_cross" "$SMOKE_DIR/$stage.spv" --msl --msl-version 20400 --msl-decoration-binding \
			--output "$SMOKE_DIR/$stage.metal" >"$SMOKE_DIR/spirv-cross.log" 2>&1 \
			|| die "spirv-cross failed on the $stage shader: $(cat "$SMOKE_DIR/spirv-cross.log")"
		grep -q 'main0' "$SMOKE_DIR/$stage.metal" \
			|| die "the MSL for the $stage shader has no main0"
	done
	# --msl-decoration-binding: the texture keeps the binding the GLSL gave it.
	grep -q 'texture2d<float> g_Texture0 \[\[texture(0)\]\]' "$SMOKE_DIR/frag.metal" \
		|| die "the fragment MSL does not bind g_Texture0 at texture(0)"

	rm -rf "$SMOKE_DIR"
	SMOKE_DIR=""
}

verify_tools() {
	local glslang="$1" spirv_cross="$2" version revision

	check_binary "$glslang"
	check_binary "$spirv_cross"

	# "Glslang Version: 11:16.6.0": the SPIR-V generator version, then glslang's.
	version="$("$glslang" --version | sed -n 's/^Glslang Version: [0-9][0-9]*://p')"
	[[ "$version" == "$GLSLANG_VERSION" ]] \
		|| die "glslang reports version '$version', expected $GLSLANG_VERSION"

	revision="$("$spirv_cross" --revision 2>&1)"
	[[ "$revision" == "$SPIRV_CROSS_REVISION_PREFIX"* ]] \
		|| die "spirv-cross does not report $SPIRV_CROSS_VERSION: $revision"

	smoke_test "$glslang" "$spirv_cross"
}

licenses_in_out_are_current() {
	local entry name
	for entry in "${GLSLANG_LICENSE_FILES[@]}" "${SPIRV_CROSS_LICENSE_FILES[@]}"; do
		name="${entry#*:}"
		cmp -s "$LICENSES_DIR/$name" "$OUT_DIR/licenses/$name" || return 1
	done
}

# --- Quick exit when out/ is already this build --------------------------------

if [[ -x "$OUT_DIR/glslang" && -x "$OUT_DIR/spirv-cross" && -f "$BUILD_INFO" \
	&& -f "$OUT_DIR/$GLSLANG_ARCHIVE_NAME" && -f "$OUT_DIR/$SPIRV_CROSS_ARCHIVE_NAME" ]] \
	&& grep -Fxq "glslang: $GLSLANG_VERSION" "$BUILD_INFO" \
	&& grep -Fxq "glslang-sha256: $GLSLANG_SHA256" "$BUILD_INFO" \
	&& grep -Fxq "spirv-cross: $SPIRV_CROSS_VERSION" "$BUILD_INFO" \
	&& grep -Fxq "spirv-cross-sha256: $SPIRV_CROSS_SHA256" "$BUILD_INFO" \
	&& grep -Fxq "deployment-target: $DEPLOYMENT_TARGET" "$BUILD_INFO" \
	&& grep -Fxq "glslang-flags: $GLSLANG_FLAGS_LINE" "$BUILD_INFO" \
	&& grep -Fxq "spirv-cross-flags: $SPIRV_CROSS_FLAGS_LINE" "$BUILD_INFO" \
	&& grep -Fxq "link-flags: $LINK_FLAGS_LINE" "$BUILD_INFO" \
	&& [[ "$(sha256_of "$OUT_DIR/$GLSLANG_ARCHIVE_NAME")" == "$GLSLANG_SHA256" ]] \
	&& [[ "$(sha256_of "$OUT_DIR/$SPIRV_CROSS_ARCHIVE_NAME")" == "$SPIRV_CROSS_SHA256" ]] \
	&& licenses_in_out_are_current; then
	verify_tools "$OUT_DIR/glslang" "$OUT_DIR/spirv-cross"
	cp "$HERE/build.sh" "$OUT_DIR/build.sh"
	say "out/ is already glslang $GLSLANG_VERSION and SPIRV-Cross $SPIRV_CROSS_VERSION" \
		"with these flags; nothing to do"
	exit 0
fi

# --- Sources -----------------------------------------------------------------

fetch() {
	local url="$1" archive="$2" sha256="$3" actual
	if [[ -f "$archive" && "$(sha256_of "$archive")" != "$sha256" ]]; then
		say "$(basename "$archive") in src/ has the wrong sha256; downloading it again"
		rm -f "$archive"
	fi
	if [[ ! -f "$archive" ]]; then
		say "downloading $url"
		curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
			--retry 3 --output "$archive.part" "$url"
		mv "$archive.part" "$archive"
	fi
	actual="$(sha256_of "$archive")"
	[[ "$actual" == "$sha256" ]] \
		|| die "sha256 of $(basename "$archive") is $actual, expected $sha256; not building"
}

# The licence texts in the repository must be the ones this release ships.
check_licenses() {
	local tree="$1" entry source name
	shift
	for entry in "$@"; do
		source="${entry%%:*}"
		name="${entry#*:}"
		cmp -s "$tree/$source" "$LICENSES_DIR/$name" \
			|| die "licenses/$name differs from $source in $(basename "$tree");" \
				"copy it from src/$(basename "$tree")/$source, read the change, and commit it"
	done
}

mkdir -p "$SRC_DIR"
fetch "$GLSLANG_URL" "$GLSLANG_ARCHIVE" "$GLSLANG_SHA256"
fetch "$SPIRV_CROSS_URL" "$SPIRV_CROSS_ARCHIVE" "$SPIRV_CROSS_SHA256"

say "unpacking $GLSLANG_ARCHIVE_NAME and $SPIRV_CROSS_ARCHIVE_NAME"
rm -rf "$GLSLANG_TREE" "$SPIRV_CROSS_TREE" "$BUILD_DIR"
tar -xzf "$GLSLANG_ARCHIVE" -C "$SRC_DIR"
tar -xzf "$SPIRV_CROSS_ARCHIVE" -C "$SRC_DIR"
[[ -d "$GLSLANG_TREE" && -d "$SPIRV_CROSS_TREE" ]] \
	|| die "an archive did not unpack to the directory expected"

check_licenses "$GLSLANG_TREE" "${GLSLANG_LICENSE_FILES[@]}"
check_licenses "$SPIRV_CROSS_TREE" "${SPIRV_CROSS_LICENSE_FILES[@]}"

# --- Generated headers ---------------------------------------------------------
# What CMake and two Python scripts would write, written here.

GLSLANG_INCLUDE="$BUILD_DIR/glslang-include"
SPIRV_CROSS_INCLUDE="$BUILD_DIR/spirv-cross-include"
mkdir -p "$GLSLANG_INCLUDE/glslang" "$SPIRV_CROSS_INCLUDE"

# glslang/build_info.h, from build_info.h.tmpl, with the version CMake would read
# from the first release heading in CHANGES.md.
changes_version="$(grep -m 1 -E '^#+ *[0-9]+\.[0-9]+\.[0-9]+' "$GLSLANG_TREE/CHANGES.md" \
	| sed -E 's/^#+ *([0-9]+\.[0-9]+\.[0-9]+[^ ]*).*/\1/')"
[[ "$changes_version" == "$GLSLANG_VERSION" ]] \
	|| die "glslang's CHANGES.md names version $changes_version, expected $GLSLANG_VERSION"
IFS=. read -r major minor patch <<<"$GLSLANG_VERSION"
sed -e "s/@major@/$major/" -e "s/@minor@/$minor/" -e "s/@patch@/$patch/" -e "s/@flavor@//" \
	"$GLSLANG_TREE/build_info.h.tmpl" >"$GLSLANG_INCLUDE/glslang/build_info.h"
if grep -q '@[a-z]*@' "$GLSLANG_INCLUDE/glslang/build_info.h"; then
	die "build_info.h.tmpl has a placeholder this script does not fill"
fi

# glslang/glsl_intrinsic_header.h, as gen_extension_headers.py writes it: each
# GLSL file in glslang/ExtensionHeaders as a string, and getIntrinsic() to pick
# the ones a shader names.
{
	echo "// Generated by Helpers/shader-tools/build.sh from glslang/ExtensionHeaders,"
	echo "// as glslang's gen_extension_headers.py would write it."
	echo "#pragma once"
	echo
	echo "#ifndef _INTRINSIC_EXTENSION_HEADER_H_"
	echo "#define _INTRINSIC_EXTENSION_HEADER_H_"
	echo
	symbols=()
	for file in "$GLSLANG_TREE"/glslang/ExtensionHeaders/*.glsl; do
		if grep -q ')"' "$file"; then
			die "$(basename "$file") contains )\", which would end the raw string"
		fi
		symbol="$(basename "$file")"
		symbol="${symbol%%.*}"
		symbols+=("$symbol")
		printf 'std::string %s_GLSL = R"(\n' "$symbol"
		cat "$file"
		printf '\n)";\n\n'
	done
	echo "std::string getIntrinsic(const char* const* shaders, int n) {"
	printf '\tstd::string shaderString = "";\n'
	printf '\tfor (int i = 0; i < n; i++) {\n'
	for symbol in "${symbols[@]}"; do
		printf '\t\tif (strstr(shaders[i], "%s") != nullptr) {\n' "$symbol"
		printf '\t\t    shaderString.append(%s_GLSL);\n' "$symbol"
		printf '\t\t}\n'
	done
	printf '\t}\n'
	printf '\treturn shaderString;\n'
	echo "}"
	echo
	echo "#endif"
} >"$GLSLANG_INCLUDE/glslang/glsl_intrinsic_header.h"

# gitversion.h, from SPIRV-Cross's cmake/gitversion.in.h. CMake fills in
# `git describe` and the time it ran; a release archive has no git, so the tag and
# the commit time the archive's files carry go in instead, and the build is the
# same every time.
spirv_cross_timestamp="$(date -u -r "$(stat -f %m "$SPIRV_CROSS_TREE/main.cpp")" '+%Y-%m-%dT%H:%M:%S')"
sed -e "s/@spirv-cross-build-version@/$SPIRV_CROSS_VERSION/" \
	-e "s/@spirv-cross-timestamp@/$spirv_cross_timestamp/" \
	"$SPIRV_CROSS_TREE/cmake/gitversion.in.h" >"$SPIRV_CROSS_INCLUDE/gitversion.h"
grep -Fq "\"$SPIRV_CROSS_REVISION_PREFIX$spirv_cross_timestamp\"" "$SPIRV_CROSS_INCLUDE/gitversion.h" \
	|| die "cmake/gitversion.in.h is not the template this script expects"

# --- Build ---------------------------------------------------------------------

JOBS="$(sysctl -n hw.ncpu)"

# compile <name> <tree> <flags...>: compiles <NAME>_SOURCES, relative to <tree>,
# into $BUILD_DIR/<name>/, one compiler per core. Each object is named after its
# source, so the names must not repeat.
compile() {
	local name="$1" tree="$2" objects="$BUILD_DIR/$1" list duplicates
	shift 2
	case "$name" in
		glslang) list=("${GLSLANG_SOURCES[@]}") ;;
		spirv-cross) list=("${SPIRV_CROSS_SOURCES[@]}") ;;
		*) die "no sources for $name" ;;
	esac
	duplicates="$(printf '%s\n' "${list[@]##*/}" | sort | uniq -d)"
	[[ -z "$duplicates" ]] || die "$name has two sources with the same name: $duplicates"

	mkdir -p "$objects"
	say "compiling $name (${#list[@]} files)"
	(cd "$objects" && for file in "${list[@]}"; do printf '%s/%s\0' "$tree" "$file"; done \
		| xargs -0 -n 1 -P "$JOBS" "${CXX[@]}" -c "$@") >"$objects.log" 2>&1 \
		|| { tail -n 40 "$objects.log" >&2; die "compiling $name failed; the full log is $objects.log"; }
}

link() {
	local name="$1" objects="$BUILD_DIR/$1"
	say "linking $name"
	"${CXX[@]}" "${LINK_FLAGS[@]}" -o "$BUILD_DIR/bin/$name" "$objects"/*.o >>"$objects.log" 2>&1 \
		|| { tail -n 40 "$objects.log" >&2; die "linking $name failed; the full log is $objects.log"; }
}

say "building (deployment target $DEPLOYMENT_TARGET, SDK $SDK_VERSION)"
mkdir -p "$BUILD_DIR/bin"
compile glslang "$GLSLANG_TREE" "${COMMON_FLAGS[@]}" "${GLSLANG_FLAGS[@]}" \
	"-I$GLSLANG_TREE" "-I$GLSLANG_INCLUDE"
compile spirv-cross "$SPIRV_CROSS_TREE" "${COMMON_FLAGS[@]}" "${SPIRV_CROSS_FLAGS[@]}" \
	"-I$SPIRV_CROSS_TREE" "-I$SPIRV_CROSS_INCLUDE"
link glslang
link spirv-cross

verify_tools "$BUILD_DIR/bin/glslang" "$BUILD_DIR/bin/spirv-cross"

# --- Install -----------------------------------------------------------------

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/licenses"
install -m 755 "$BUILD_DIR/bin/glslang" "$OUT_DIR/glslang"
install -m 755 "$BUILD_DIR/bin/spirv-cross" "$OUT_DIR/spirv-cross"
cp "$GLSLANG_ARCHIVE" "$OUT_DIR/$GLSLANG_ARCHIVE_NAME"
cp "$SPIRV_CROSS_ARCHIVE" "$OUT_DIR/$SPIRV_CROSS_ARCHIVE_NAME"
cp "$HERE/build.sh" "$OUT_DIR/build.sh"
for entry in "${GLSLANG_LICENSE_FILES[@]}" "${SPIRV_CROSS_LICENSE_FILES[@]}"; do
	cp "$LICENSES_DIR/${entry#*:}" "$OUT_DIR/licenses/${entry#*:}"
done

{
	echo "Shader tools for Livepaper, built by Helpers/shader-tools/build.sh"
	echo "glslang: $GLSLANG_VERSION"
	echo "glslang-source: $GLSLANG_URL"
	echo "glslang-sha256: $GLSLANG_SHA256"
	echo "spirv-cross: $SPIRV_CROSS_VERSION"
	echo "spirv-cross-source: $SPIRV_CROSS_URL"
	echo "spirv-cross-sha256: $SPIRV_CROSS_SHA256"
	echo "deployment-target: $DEPLOYMENT_TARGET"
	echo "sdk: $SDK_VERSION"
	echo "compiler: $("${CXX[@]}" --version | head -n 1)"
	echo "glslang-flags: $GLSLANG_FLAGS_LINE"
	echo "spirv-cross-flags: $SPIRV_CROSS_FLAGS_LINE"
	echo "link-flags: $LINK_FLAGS_LINE"
	echo "glslang-sources: ${GLSLANG_SOURCES[*]}"
	echo "spirv-cross-sources: ${SPIRV_CROSS_SOURCES[*]}"
	echo "glslang-binary-sha256: $(sha256_of "$OUT_DIR/glslang")"
	echo "spirv-cross-binary-sha256: $(sha256_of "$OUT_DIR/spirv-cross")"
	echo
	echo "--- glslang --version"
	"$OUT_DIR/glslang" --version
	echo
	echo "--- spirv-cross --revision"
	"$OUT_DIR/spirv-cross" --revision 2>&1
	echo
	echo "--- otool -L glslang"
	otool -L "$OUT_DIR/glslang" | tail -n +2
	echo
	echo "--- otool -L spirv-cross"
	otool -L "$OUT_DIR/spirv-cross" | tail -n +2
} >"$BUILD_INFO"

verify_tools "$OUT_DIR/glslang" "$OUT_DIR/spirv-cross"

# src/ keeps the archives only; the unpacked trees and the objects are rebuilt from them.
cd "$HERE"
rm -rf "$GLSLANG_TREE" "$SPIRV_CROSS_TREE" "$BUILD_DIR"

size() { printf '%s, %s bytes' "$(du -h "$1" | cut -f1 | tr -d ' ')" "$(stat -f %z "$1")"; }
say "built out/glslang ($(size "$OUT_DIR/glslang")) and out/spirv-cross ($(size "$OUT_DIR/spirv-cross"))"
