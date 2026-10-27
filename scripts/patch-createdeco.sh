#!/usr/bin/env bash
# 生成发给客户端的 createdeco jar：把大写贴图 BLANK_decal_dont_use.png 改成小写。
#
# 背景：MC 1.20.1 图集加载会给每个 textures/**/*.png 拼上 .mcmeta 去查动画元数据，
# 得到形如 createdeco:textures/block/palettes/decals/BLANK_decal_dont_use.png.mcmeta 的
# ResourceLocation；大写字母不合法，客户端在资源重载阶段直接崩溃：
#   net.minecraft.ResourceLocationException: Non [a-z0-9/._-] character in path of location
# 该贴图在 mod 里没有任何引用（文件名本身就是 dont_use），改名不影响任何功能。
#
# 用法：scripts/patch-createdeco.sh [原版 jar 路径]
# 输出：automodpack/host-modpack/main/mods/<同名 jar>，由 AutoModpack 发给客户端。
#       （同一路径在 host-modpack 里优先于服务端的 data/mods，所以客户端拿到改过的版本，
#        服务端继续用原版，贴图对服务端没有影响。）
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-data/mods/createdeco-2.0.3-1.20.1-forge.jar}"
OUT_DIR="automodpack/host-modpack/main/mods"
OUT="$OUT_DIR/$(basename "$SRC")"
OLD="assets/createdeco/textures/block/palettes/decals/BLANK_decal_dont_use.png"
NEW="assets/createdeco/textures/block/palettes/decals/blank_decal_dont_use.png"

[ -f "$SRC" ] || { echo "找不到 $SRC（先跑一次 docker compose up 让整合包装好）" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$SRC" "$tmp/patched.jar"
# 先把清单读进变量：set -o pipefail 下 `unzip -Z1 | grep -q` 会因为 grep 提前退出、
# unzip 收到 SIGPIPE(141) 而让整条管道判负，导致误报“文件名不存在”。
LIST=$(unzip -Z1 "$tmp/patched.jar")

if grep -qxF "$OLD" <<< "$LIST"; then
  unzip -p "$tmp/patched.jar" "$OLD" > "$tmp/blank_decal_dont_use.png"
  zip -q -d "$tmp/patched.jar" "$OLD"
  mkdir -p "$tmp/stage/$(dirname "$NEW")"
  cp "$tmp/blank_decal_dont_use.png" "$tmp/stage/$NEW"
  ( cd "$tmp/stage" && zip -q -X "$tmp/patched.jar" "$NEW" )
  echo "改名: $OLD -> $NEW"
elif grep -qxF "$NEW" <<< "$LIST"; then
  echo "已经是小写，无需改动"
else
  echo "jar 里两种文件名都不存在，createdeco 版本变了，请重新确认" >&2
  exit 1
fi

unzip -t "$tmp/patched.jar" > /dev/null
mkdir -p "$OUT_DIR"
mv -f "$tmp/patched.jar" "$OUT"
echo "输出: $OUT ($(stat -c%s "$OUT") 字节, sha1 $(sha1sum "$OUT" | cut -d' ' -f1))"
