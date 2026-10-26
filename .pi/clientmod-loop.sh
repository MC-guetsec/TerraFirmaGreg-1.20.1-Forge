#!/usr/bin/env bash
# 把「客户端专属 mod」从 data/mods 移到 automodpack/host-modpack/main/mods：
# 服务端不再加载它，AutoModpack 仍把该目录整份发给客户端 —— 整合包不缺任何 mod。
# 依据 docs/pack-content.mdx:100、docs/faq.mdx:4-5。
# 判据：崩溃报告中 Forge 直接给出 "Mod File: /data/mods/xxx.jar"。
set -u
cd "$(dirname "$0")/.." || exit 1

DEST=data/automodpack/host-modpack/main/mods
mkdir -p "$DEST"
last_crash=0
progress=$SECONDS

for _ in $(seq 1 900); do
  docker logs tfg-mc > /tmp/mc-v5.log 2>&1
  sed -i 's/\x1b\[[0-9;]*m//g' /tmp/mc-v5.log

  if grep -q 'For help, type' /tmp/mc-v5.log; then echo "=== READY ==="; exit 0; fi

  crashes=$(grep -c 'Minecraft server failed' /tmp/mc-v5.log || true)
  if [ "${crashes:-0}" -gt "$last_crash" ]; then
    last_crash=$crashes
    n=$(grep -n 'Minecraft server failed' /tmp/mc-v5.log | tail -1 | cut -d: -f1)
    start=$(( n > 600 ? n - 600 : 1 ))
    sed -n "${start},${n}p" /tmp/mc-v5.log > /tmp/mc-crash.log

    moved=0
    for jar in $(grep -oE 'Mod File: /data/mods/[^ ]+\.jar' /tmp/mc-crash.log | sed 's|.*/||' | sort -u); do
      if [ -f "data/mods/$jar" ]; then
        mv "data/mods/$jar" "$DEST"/ && { echo "[$((SECONDS))s] $jar -> host-modpack"; moved=1; }
      fi
    done
    if [ "$moved" = 1 ]; then progress=$SECONDS; else
      echo "[$((SECONDS))s] 崩溃但报告里没有 Mod File 行，摘录："
      grep -E "Failure message|Mod File|Exception message" /tmp/mc-crash.log | head -12
    fi
  fi

  [ $((SECONDS - progress)) -gt 600 ] && { echo "=== 600s 无进展 ==="; exit 2; }
  sleep 4
done
echo "=== TIMEOUT ==="
exit 1
