#!/usr/bin/env bash
set -u

files=(README.md README.zh-CN.md README.ja.md README.ko.md)
anchors=(
  'Review Agent Activity'
  'Code checks'
  'Orca'
  'incidents.json'
  'rm -rf ~/Library/Application\ Support/Vibra'
  'defaults delete ai.silexlab.vibra'
  '⌘U'
  '⌘Y'
)
stale=('完整删除' '完全に削除するには' '완전히 제거하려면' 'remove it completely')

status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    printf '%-16s  missing file\n' "$f"
    status=1
    continue
  fi
  row=$(printf '%-16s' "$f")
  for a in "${anchors[@]}"; do
    if grep -qF -- "$a" "$f"; then
      row+="  $a=ok"
    else
      row+="  $a=MISSING"
      status=1
    fi
  done
  for a in "${stale[@]}"; do
    if grep -qF -- "$a" "$f"; then
      row+="  no-$a=PRESENT"
      status=1
    else
      row+="  no-$a=ok"
    fi
  done
  printf '%s\n' "$row"
done

if [ "$status" -ne 0 ]; then
  printf '\nFAIL: a MISSING or PRESENT cell above\n'
  exit 1
fi
printf '\nOK: all four READMEs have every anchor and no stale removal phrase\n'
