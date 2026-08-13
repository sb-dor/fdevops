#!/bin/bash

# Enable error handling
set -e

# Localization layout (override via env if the project uses a different one)
ARB_DIR="${ARB_DIR:-lib/src/common/localization}"
L10N_OUTPUT_DIR="${L10N_OUTPUT_DIR:-lib/src/common/localization/generated}"
TEMPLATE_ARB_FILE="${TEMPLATE_ARB_FILE:-intl_en.arb}"

# Activate a global dart package only once per run
activated=""
activate_once() {
  case " $activated " in
    *" $1 "*) return 0 ;;
  esac
  dart pub global activate "$1"
  activated="$activated $1"
}

# Find directories with a pubspec.yaml (skip generated/vendored trees)
find_package_dirs() {
  find . -type f -name "pubspec.yaml" \
    -not -path "*/build/*" \
    -not -path "*/.dart_tool/*" \
    -not -path "*/ios/*" \
    -not -path "*/macos/*" \
    -exec dirname {} \;
}

# Check for a dependency entry in a pubspec.yaml
has_dependency() {
  grep -qE "^[[:space:]]+$1:" "$2"
}

generate_l10n() {
  local dir="$1"
  if [ ! -d "$dir/$ARB_DIR" ]; then
    echo "  ↷ skip l10n: no $ARB_DIR"
    return 0
  fi

  activate_once intl_utils
  (cd "$dir" && dart pub global run intl_utils:generate)

  if [ ! -f "$dir/$ARB_DIR/$TEMPLATE_ARB_FILE" ]; then
    echo "  ↷ skip gen-l10n: no $ARB_DIR/$TEMPLATE_ARB_FILE"
    return 0
  fi

  (cd "$dir" && flutter gen-l10n \
    --arb-dir "$ARB_DIR" \
    --output-dir "$L10N_OUTPUT_DIR" \
    --template-arb-file "$TEMPLATE_ARB_FILE")
}

generate_assets() {
  local dir="$1"
  if ! grep -qE "^flutter_gen:" "$dir/pubspec.yaml"; then
    echo "  ↷ skip flutter_gen: no flutter_gen: section in pubspec.yaml"
    return 0
  fi

  activate_once flutter_gen
  (cd "$dir" && fluttergen -c pubspec.yaml)
}

run_build_runner() {
  local dir="$1"
  if ! has_dependency "build_runner" "$dir/pubspec.yaml"; then
    echo "  ↷ skip build_runner: not a dependency"
    return 0
  fi

  (cd "$dir" && dart run build_runner build --delete-conflicting-outputs --release)
}

package_dirs=$(find_package_dirs)
if [ -z "$package_dirs" ]; then
  echo "No directories with pubspec.yaml found."
  exit 0
fi

echo "$package_dirs" | while read -r dir; do
  echo "▶ Generating in $dir"
  generate_l10n "$dir"
  generate_assets "$dir"
  run_build_runner "$dir"
done
