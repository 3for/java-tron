#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 IMAGE" >&2
  exit 1
fi

image="$1"

if ! output=$(docker run --rm --entrypoint bash "$image" -c '
  set -euo pipefail

  vm_options_file=/java-tron/bin/java-tron.vmoptions

  # Cover comments, blank lines, CRLF endings, and a quoted value containing
  # spaces. Append the final option without a trailing newline.
  printf "%s\r\n" \
    "# This comment must not be passed to the JVM." \
    "" \
    "-Djava.tron.vmoptions.spaced=\"value with spaces\"" \
    > "$vm_options_file"
  printf "%s" \
    "-Djava.tron.vmoptions.final=\"last line without newline\"" \
    >> "$vm_options_file"

  JAVA_OPTS="-XshowSettings:properties -version" exec /java-tron/bin/FullNode
' 2>&1); then
  echo "$output" >&2
  echo "FullNode failed while parsing the JVM options fixture." >&2
  exit 1
fi

assert_output() {
  local expected="$1"

  if ! grep -Fq -- "$expected" <<< "$output"; then
    echo "Missing expected JVM property: $expected" >&2
    echo "$output" >&2
    exit 1
  fi
}

assert_output "java.tron.vmoptions.spaced = value with spaces"
assert_output "java.tron.vmoptions.final = last line without newline"

echo "JVM options parsing test passed for $image"
