#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
wrapper_dir="${repo_root}/third-party/libwebrtc"
depot_tools_dir="${repo_root}/third-party/depot_tools"
compatibility_patches=(
  "${wrapper_dir}/patchs/custom_audio_source_m125.patch"
  "${wrapper_dir}/patchs/fix_emplace.patch"
  "${repo_root}/packaging/linux/patches/libwebrtc-unused-nal-constants.patch"
)

if [[ -n "${VIBEPOLLO_DEPS_DIR:-}" ]]; then
  deps_dir="${VIBEPOLLO_DEPS_DIR}"
elif [[ -n "${VIBESHINE_DEPS_DIR:-}" ]]; then
  deps_dir="${VIBESHINE_DEPS_DIR}"
else
  deps_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/Vibepollo/deps"
fi

webrtc_dir="${deps_dir}/libwebrtc"
checkout_dir="${webrtc_dir}/src"
build_dir="${checkout_dir}/out/Release"
stage_dir="${webrtc_dir}/out"
wrapper_checkout="${checkout_dir}/libwebrtc"
branch="${WEBRTC_BRANCH:-m125_release}"
jobs="${WEBRTC_BUILD_JOBS:-$(nproc)}"
case "$(uname -m)" in
  x86_64) target_cpu="x64" ;;
  aarch64) target_cpu="arm64" ;;
  armv7l) target_cpu="arm" ;;
  i?86) target_cpu="x86" ;;
  *)
    echo "Unsupported Linux architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if [[ ! -x "${depot_tools_dir}/gclient" ]]; then
  echo "depot_tools is missing; initialize the third-party/depot_tools submodule." >&2
  exit 1
fi

mkdir -p "${webrtc_dir}"
cat > "${webrtc_dir}/.gclient" <<EOF
solutions = [
  {
    "name": "src",
    "url": "https://github.com/webrtc-sdk/webrtc.git@${branch}",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {
      "checkout_configuration": "small",
    },
  },
]
target_os = ["linux"]
EOF

export PATH="${depot_tools_dir}:${PATH}"
"${depot_tools_dir}/ensure_bootstrap"
export DEPOT_TOOLS_UPDATE=0

if [[ -d "${checkout_dir}/.git" ]]; then
  for patch_path in "${compatibility_patches[@]}"; do
    if git -C "${checkout_dir}" apply --reverse --check "${patch_path}" 2>/dev/null; then
      git -C "${checkout_dir}" apply --reverse "${patch_path}"
    fi
  done
  sed -i 's|deps = \[ ":webrtc" , "//libwebrtc:libwebrtc" \]|deps = [ ":webrtc" ]|' "${checkout_dir}/BUILD.gn"
  if [[ -n "$(git -C "${checkout_dir}" status --short --untracked-files=no)" ]]; then
    echo "Refusing to overwrite unexpected changes in ${checkout_dir}:" >&2
    git -C "${checkout_dir}" status --short --untracked-files=no >&2
    exit 1
  fi
fi

if [[ -L "${wrapper_checkout}" ]]; then
  rm "${wrapper_checkout}"
elif [[ -d "${wrapper_checkout}" ]]; then
  if [[ ! -f "${wrapper_checkout}/.vibepollo-cache-copy" ]]; then
    echo "Refusing to replace unmanaged wrapper checkout: ${wrapper_checkout}" >&2
    exit 1
  fi
  cmake -E remove_directory "${wrapper_checkout}"
elif [[ -e "${wrapper_checkout}" ]]; then
  echo "Refusing to replace unexpected wrapper path: ${wrapper_checkout}" >&2
  exit 1
fi

pushd "${webrtc_dir}" >/dev/null
gclient sync --no-history --jobs "${jobs}" --nohooks --revision "src@${branch}"
gclient runhooks
popd >/dev/null

cp -a "${wrapper_dir}" "${wrapper_checkout}"
touch "${wrapper_checkout}/.vibepollo-cache-copy"

for patch_path in "${compatibility_patches[@]}"; do
  if ! git -C "${checkout_dir}" apply --reverse --check "${patch_path}" 2>/dev/null; then
    git -C "${checkout_dir}" apply "${patch_path}"
  fi
done

if ! rg -q '"//libwebrtc:libwebrtc"' "${checkout_dir}/BUILD.gn"; then
  sed -i '/deps = \[ ":webrtc" \]/s/]$/, "\/\/libwebrtc:libwebrtc" ]/' "${checkout_dir}/BUILD.gn"
fi

pushd "${checkout_dir}" >/dev/null
gn gen "out/Release" --args="target_os=\"linux\" target_cpu=\"${target_cpu}\" is_debug=false is_component_build=false use_rtti=true use_custom_libcxx=false rtc_enable_protobuf=false rtc_include_tests=false rtc_build_examples=false rtc_use_h264=true ffmpeg_branding=\"Chrome\" libwebrtc_desktop_capture=true symbol_level=0"
autoninja -C "out/Release" -j "${jobs}" libwebrtc
popd >/dev/null

library_path=""
for candidate in "${build_dir}/libwebrtc.so" "${build_dir}/lib.unstripped/libwebrtc.so"; do
  if [[ -f "${candidate}" ]]; then
    library_path="${candidate}"
    break
  fi
done
if [[ -z "${library_path}" ]]; then
  echo "libwebrtc.so was not produced under ${build_dir}." >&2
  exit 1
fi

mkdir -p "${stage_dir}/include" "${stage_dir}/lib"
cp -a "${wrapper_dir}/include/." "${stage_dir}/include/"
install -m 0755 "${library_path}" "${stage_dir}/lib/libwebrtc.so"

echo "Native Linux WebRTC staged at ${stage_dir}"
