#!/usr/bin/env bash
# 迭代把「客户端专属 mod」从 data/mods 移到 automodpack/host-modpack/main/mods：
# 服务端不再加载它，AutoModpack 仍会把该目录整份发给客户端 —— 整合包不缺任何 mod。
# 依据 docs/pack-content.mdx「Give clients a file the server does not need」+ faq「How do I add client-only mods to the pack?」
set -u
cd "$(dirname "$0")/.." || exit 1

MAP=/tmp/jarmap.txt
DEST=data/automodpack/host-modpack/main/mods
mkdir -p "$DEST"
if [ ! -s "$MAP" ]; then
  : > "$MAP"
  for j in data/mods/*.jar; do
    unzip -Z1 "$j" 2>/dev/null | grep -E '\.class$' | sed "s|^|$j\t|" >> "$MAP"
  done
fi

find_jar() {
  local p; p=$(printf '%s' "$1" | tr '.' '/')
  awk -F'\t' -v e="$p.class" '$2==e {print $1; exit}' "$MAP"
}

last_crash=0
progress=$SECONDS
for _ in $(seq 1 900); do
  docker logs tfg-mc > /tmp/mc-v4.log 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' /tmp/mc-v4.log

  if grep -q 'For help, type' /tmp/mc-v4.log; then
    echo "=== READY ==="
    exit 0
  fi

  crashes=$(grep -c 'Minecraft server failed\|LoadingFailedException' /tmp/mc-v4.log || true)
  if [ "${crashes:-0}" -gt "$last_crash" ]; then
    last_crash=$crashes
    n=$(grep -n 'Minecraft server failed' /tmp/mc-v4.log | tail -1 | cut -d: -f1)
    [ -z "$n" ] && n=$(wc -l < /tmp/mc-v4.log)
    start=$(( n > 400 ? n - 400 : 1 ))
    sed -n "${start},${n}p" /tmp/mc-v4.log > /tmp/mc-crash.log

    moved=0
    for cls in $(grep -oE '(Attempted|Failed) to load class [A-Za-z0-9_.$/]+' /tmp/mc-crash.log \
                 | awk '{print $NF}' | tr '/' '.' | sed 's/\.class$//' | sort -u); do
      jar=$(find_jar "$cls")
      if [ -n "$jar" ] && [ -f "$jar" ]; then
        mv "$jar" "$DEST"/ && { echo "[$((SECONDS))s] $(basename "$jar")  ->  host-modpack/main/mods/"; moved=1; }
      fi
    done
    if [ "$moved" = 1 ]; then
      progress=$SECONDS
    else
      echo "[$((SECONDS))s] 崩溃但无可解析 jar："
      grep -E "LoadingFailedException|Exception message|Description:|Caused by" /tmp/mc-crash.log | head -10
    fi
  fi

  [ $((SECONDS - progress)) -gt 600 ] && { echo "=== 600s 无进展 ==="; grep -E "LoadingFailedException|Exception message|Description:" /tmp/mc-crash.log 2>/dev/null | head -10; exit 2; }
  sleep 4
done
echo "=== TIMEOUT ==="
exit 1
