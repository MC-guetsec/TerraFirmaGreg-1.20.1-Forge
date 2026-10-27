#!/usr/bin/env bash
# 生成发给客户端的 sandworm jar：删掉 effeks/Texture/ 下三个残留 .efkefc。
#
# 背景：AAA Particles 的资源加载器会枚举所有 `effeks/**.efkefc|.efkpkg`，
# 用 createEffekName() 把 `effeks/xxx.efkefc` 裁成 `xxx` 再新建 ResourceLocation。
# 它的 MixinResourceLocation 只让「以 effeks/ 开头」的路径跳过字符校验，
# 裁剪后的 `Texture/sandimpact` 不再以 effeks/ 开头，于是大写字母触发校验，
# 客户端在初始化资源重载第一个包时直接崩溃：
#   net.minecraft.ResourceLocationException: Non [a-z0-9/._-] character in path of location
#   at mod.chloeprime.aaaparticles.client.loader.EffekAssetLoader.createEffekName(EffekAssetLoader.java:210)
# 这三个文件是作者遗留在贴图目录里的副本（sandworm 代码只按 sandimpact/sandsmoke/
# slowersandimpact 名字取特效，LossOfBlood 全库无引用），删掉不影响任何特效。
# effeks/Texture/*.png 这些大写贴图本身不用改：路径仍以 effeks/ 开头、校验被放行，
# 而且资源查找用的就是磁盘上的原始大小写。
#
# 用法：scripts/patch-sandworm.sh [原版 jar 路径]
# 输出：automodpack/host-modpack/main/mods/<同名 jar>，由 AutoModpack 发给客户端。
#       （同一路径在 host-modpack 里优先于服务端的 data/mods，所以客户端拿到改过的版本，
#        服务端继续用原版。）
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-data/mods/sandworm_mod-1.2.0.jar}"
OUT_DIR="automodpack/host-modpack/main/mods"
OUT="$OUT_DIR/$(basename "$SRC")"
STRAYS=(
  "assets/sandworm_mod/effeks/Texture/LossOfBlood.efkefc"
  "assets/sandworm_mod/effeks/Texture/sandimpact.efkefc"
  "assets/sandworm_mod/effeks/Texture/slowersandimpact.efkefc"
)

[ -f "$SRC" ] || { echo "找不到 $SRC（先跑一次 docker compose up 让整合包装好）" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$SRC" "$tmp/patched.jar"
# 先把清单读进变量：set -o pipefail 下 `unzip -Z1 | grep -q` 会因为 grep 提前退出、
# unzip 收到 SIGPIPE(141) 而让整条管道判负。
LIST=$(unzip -Z1 "$tmp/patched.jar")

victims=()
for p in "${STRAYS[@]}"; do
  grep -qxF "$p" <<< "$LIST" && victims+=("$p")
done

if [ "${#victims[@]}" -eq 0 ]; then
  echo "三个残留 .efkefc 都已不存在，无需改动"
else
  for p in "${victims[@]}"; do
    echo "删除: $p"
  done
  zip -q -d "$tmp/patched.jar" "${victims[@]}"
fi

unzip -t "$tmp/patched.jar" > /dev/null
# 校验：effeks 下不能再有 .efkefc/.efkpkg 含大写字符
LIST=$(unzip -Z1 "$tmp/patched.jar")
bad=$(grep -E '^(.*/)?effeks/.*\.(efkefc|efkpkg)$' <<< "$LIST" | grep -E '[A-Z]' || true)
if [ -n "$bad" ]; then
  echo "仍有含大写的特效文件，请重新确认：" >&2
  echo "$bad" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
mv -f "$tmp/patched.jar" "$OUT"
echo "输出: $OUT ($(stat -c%s "$OUT") 字节, sha1 $(sha1sum "$OUT" | cut -d' ' -f1))"
echo "剩余特效文件:"
grep -E '^(.*/)?effeks/.*\.(efkefc|efkpkg)$' <<< "$LIST" | sed 's/^/  /'
