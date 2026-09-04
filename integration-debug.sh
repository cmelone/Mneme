#!/usr/bin/env bash
set -euo pipefail

ROOT=$PWD
BUILD_DIR="/tmp/mneme-vecadd-off"
SIZES=(24 32)

if [[ $# -gt 0 ]]; then
  SIZES=("$@")
else
  SIZES=("${SIZES[@]}")
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake \
  -DCMAKE_C_COMPILER="$(mneme config cc)" \
  -DCMAKE_CXX_COMPILER="$(mneme config cxx)" \
  -DCMAKE_PREFIX_PATH="$(mneme config cmakedir)" \
  -DENABLE_HIP=On \
  "${ROOT}/python/tests/c_src/cmake"

make -j

for size in "${SIZES[@]}"; do
  record_dir="/tmp/mneme-record-${size}g"
  rm -rf "${record_dir}"
  mkdir -p "${record_dir}"

  mneme -v debug record \
    --record-db-dir "${record_dir}" \
    -vass "${size}" \
    -- "${BUILD_DIR}/vecAdd" 1024

  records=("${record_dir}"/*.json)
  if [[ ${#records[@]} -ne 1 ]]; then
    echo "Expected exactly one record file in ${record_dir}, found ${#records[@]}" >&2
    exit 1
  fi

  mneme -v debug replay \
    -rdb "${records[0]}" \
    'default<O3>'
done
