#!/bin/zsh
# Compares the launcher's SelfUnwrap with upstream's tools/unwrap_self.py on every SELF container
# (eboot.bin, *.prx, *.sprx, *.self) under a games folder, byte for byte. The games folder is
# only read; each pair of outputs goes to a scratch folder and is deleted at once.
#
#   swift build --product anyps5-tool
#   scripts/compare-unwrap.sh .build/debug/anyps5-tool ~/Games [scratch folder]
set -u
here=${0:A:h}
tool=${1:A}
games=$2
out=${3:-$(mktemp -d)}
reference=${UNWRAP_REFERENCE:-$here/../../../unwrap_self.py}
mkdir -p "$out"
same=0; differ=0; refused=0
while IFS= read -r -d '' file; do
  magic=$(xxd -p -l 4 "$file")
  [[ $magic == 4f153d1d || $magic == 5414f5ee ]] || continue
  rm -f "$out/py.elf" "$out/swift.elf"
  python=$(python3 -I "$reference" "$file" "$out/py.elf" 2>&1); python_status=$?
  swift=$("$tool" unwrap "$file" "$out/swift.elf" 2>&1); swift_status=$?
  if (( python_status != 0 && swift_status != 0 )); then
    echo "BOTH REFUSE $file: $python"; (( refused++ ))
  elif (( python_status != 0 || swift_status != 0 )); then
    echo "ONE REFUSES $file: python $python_status $python / swift $swift_status $swift"; (( differ++ ))
  elif cmp -s "$out/py.elf" "$out/swift.elf"; then
    echo "SAME $file"; (( same++ ))
  else
    echo "DIFFER $file: python $(stat -f %z "$out/py.elf") bytes, swift $(stat -f %z "$out/swift.elf") bytes"; (( differ++ ))
  fi
  rm -f "$out/py.elf" "$out/swift.elf"
done < <(find "$games" -type f \( -iname 'eboot.bin' -o -iname '*.prx' -o -iname '*.sprx' -o -iname '*.self' \) -print0)
echo "same $same, differ $differ, both refuse $refused"
(( differ == 0 ))
