# TerraFirmaGreg-Modern 0.13.16 服务端

Minecraft **1.20.1** + **Forge 47.4.13**，整合包 `TerraFirmaGreg-Modern-0.13.16`（CurseForge 客户端包，276 个文件，
含 GregTech Modern / TerraFirmaCraft / KubeJS 脚本）。

- 服务端镜像：`itzg/minecraft-server:java17`（Forge 47.x / MC 1.20.1 需要 Java 17）
- 整合包安装：`TYPE=AUTO_CURSEFORGE` + `CF_SLUG=custom` + `CF_MODPACK_ZIP`（直接吃本地客户端 zip，overrides 也会解压）
- 客户端 mod 分发：**AutoModpack 5.0.0-rc.2**，服务端把整包托管出去，带 AutoModpack 的客户端连上后自动同步成
  与服务端完全一致的 mod / config，不需要玩家自己装整合包

## 目录

```
compose.yaml                            # 全部编排
.env / .env.example                     # CF_API_KEY / 内存 / 端口（.env 不进 git）
modpacks/*.zip                          # 整合包原件，只读挂进容器 /modpacks（不进 git，需自己放）
automodpack/server.conf                 # AutoModpack 服务端配置，挂到 /data/automodpack/server.conf
automodpack/host-modpack/main/mods/*.jar# 发给客户端的 jar：客户端专属 mod + createdeco 修复版
scripts/patch-createdeco.sh             # 重新生成 createdeco 修复版 jar（见「createdeco 大写贴图修复」）
client/automodpack-5.0.0-rc.2.jar       # 玩家用的 bootstrap jar；同时挂到 /mods 供镜像复制进 /data/mods
data/                                   # 容器 /data，服务端运行时数据（不进 git）
                                        #   └─ automodpack/credentials/  TLS 证书与私钥（运行时生成或自己放，见「TLS 证书」）
```

## 首次部署

```bash
cp .env.example .env
vi .env                                  # 填 CF_API_KEY（https://console.curseforge.com/）

mkdir -p modpacks
cp /path/to/TerraFirmaGreg-Modern-0.13.16-curseforge.zip modpacks/    # 198MB，不在仓库里

sudo chown -R 1000:1000 automodpack      # 容器以 uid 1000 运行，要能回写 host-modpack/patch-notes.md
docker compose up -d
docker compose logs -f minecraft
```

`modpacks/` 里的 zip 必须自己准备——仓库不收录 198MB 的整合包原件。

`automodpack/` 是从仓库克隆下来的，属主是克隆者（root 机器上就是 root），而容器里跑的是 uid 1000，
所以第一次启动前必须 `chown -R 1000:1000 automodpack`。漏了这步的症状是启动日志出现
`Failed to generate modpack: /data/automodpack/host-modpack/patch-notes.md`（`AccessDeniedException` 或
`Read-only file system`），服务端起不来。`data/` 不用管，镜像会自己校正属主。

首次启动有两件慢事，`start_period` 给了 45 分钟：

1. 从 CurseForge 拉 276 个文件（`CF_PARALLEL_DOWNLOADS=8`），装 Forge 47.4.13；
2. AutoModpack 首次生成整包（全量算 SHA1 + 打包），日志是 `Modpack generation completed!`。

看到 `Done (XXs)! For help, type "help"` 即启动完成。

> 老机器上只有 Compose v1（`docker-compose`）也能用：`compose.yaml` 保留了 `version: "3.8"` 且没有顶层 `name:`。
> 用 Compose v2 时会打印一条 `version 已废弃` 的 warning，可忽略。

## 常用操作

```bash
docker compose logs -f minecraft          # 看日志
docker attach tfg-mc                      # 进控制台（Ctrl-p Ctrl-q 退出，不要按 Ctrl-c）
docker compose restart minecraft          # 重启
docker compose down                       # 停止（数据保留在 data/）
docker compose down -v                    # 连数据一起删（危险）
```

## 端口

| 端口 | 用途 |
| --- | --- |
| 25565/tcp | Minecraft 游戏 + AutoModpack 分发 |

AutoModpack 默认 `connection-mode: HOLEPUNCH`，mod 同步跑在登录握手内，复用 Minecraft 端口，
**不额外监听端口**，所以不需要发布 3001。只有改成 `HTTP` / `MAGIC` 模式时才要设 `bind-port` 并在
`compose.yaml` 里加端口映射。

## 客户端专属 mod

`automodpack/host-modpack/main/mods/` 下的 jar 会整包发给客户端，但服务端不加载。当前 4 个：

- `cwb-forge-3.0.0+mc1.20.jar`（Cubes Without Borders）
- `blur-forge-3.1.1.jar`（Blur）
- `ItemPhysicLite_FORGE_v1.6.13_mc1.20.1.jar`（ItemPhysic Lite）
- `sodiumextras-forge-1.0.7-1.20.1.jar`（Sodium Extras）

它们里面有客户端专用 `@Mod` 类，专用服务端加载会直接崩（`Attempted to load class ... for invalid dist
DEDICATED_SERVER`）。所以这 4 个 CurseForge 项目 ID 写在 `compose.yaml` 的 `CF_EXCLUDE_MODS` 里，安装器根本不下载它们；
客户端那份由 `automodpack/host-modpack/main/mods/` 提供，客户端拿到的整合包因此仍然完整。

现在 `CF_EXCLUDE_MODS` = `823106`(Blur) `975120`(Cubes Without Borders) `270441`(ItemPhysic Lite) `558905`(Sodium Extras)。

已经装过旧数据的机器（`data/mods` 里还留着这 4 个 jar）手工删一次即可，`mods/*.jar` 已在
`CF_IGNORE_MISSING_FILES` 里，删掉不会触发重装：

```bash
rm -f data/mods/cwb-forge-*.jar data/mods/blur-forge-*.jar \
      data/mods/ItemPhysicLite_*.jar data/mods/sodiumextras-*.jar
```

再加新的客户端 mod：先放进 `data/mods/` 启动一次，崩溃报告里会写 `Mod File: /data/mods/xxx.jar`；
把这个 jar 移到 `automodpack/host-modpack/main/mods/`，并把它的 CurseForge 项目 ID 加进 `CF_EXCLUDE_MODS`
（ID 可以在 CurseForge 页面 URL 的 `/mc-mods/<slug>/<id>` 里看到）。

## createdeco 大写贴图修复

`automodpack/host-modpack/main/mods/createdeco-2.0.3-1.20.1-forge.jar` 是**改过一个文件名的** Create Deco 2.0.3：

```
assets/createdeco/textures/block/palettes/decals/BLANK_decal_dont_use.png
                                        →  blank_decal_dont_use.png
```

原版 jar 里这个贴图是大写开头，而 MC 1.20.1 的图集加载会给每个 `textures/**/*.png` 拼上 `.mcmeta` 去查动画元数据，
于是构造出 `createdeco:textures/block/palettes/decals/BLANK_decal_dont_use.png.mcmeta` 这个 ResourceLocation；
路径里出现大写字母直接抛异常，客户端在资源重载阶段崩溃：

```
net.minecraft.ResourceLocationException: Non [a-z0-9/._-] character in path of location: createdeco:textures/.../BLANK_decal_dont_use.png.mcmeta
```

这个贴图在 mod 内部没有任何引用（文件名本身就是 `dont_use`），改名不影响任何功能，jar 也没有签名或摘要，改动是安全的。
改好的 jar 放在 `host-modpack` 里只发给客户端，服务端 `data/mods` 保持 CurseForge 原版（贴图对专用服务端无影响），
所以同一逻辑路径以 host-modpack 那份为准。

从原版 jar 重新生成（整合包升级、`data/` 重装后需要重跑）：

```bash
scripts/patch-createdeco.sh          # 默认读 data/mods/createdeco-*.jar，输出到 host-modpack
```

脚本会做原地改名（`zip -d` 删旧条目 + `zip -X` 加新条目），条目总数不变、其余条目字节不变，并打印 sha1。
如果整合包升级后 createdeco 换了版本，脚本会报「两种文件名都不存在」，此时要重新确认新版里的大写贴图路径再改。

## AutoModpack 配置

`automodpack/server.conf` 已经调过：

- `name` = `TerraFirmaGreg-Modern 0.13.16`
- `from-server` 在 `mods/*.jar`、`kubejs/**` 之外补了 `config/**`、`defaultconfigs/**`、`tacz/**`、
  `resourcepacks/**`、`shaderpacks/**`，保证客户端拿到和整合包一致的配置与资源
- `kubejs/server_scripts/**` 在 `exclude` 里（纯服务端脚本）
- `auto-exclude-server-side-mods: DISABLED`（不按 mod 元数据裁剪，避免把客户端需要的 jar 排掉）
- `require-modpack: true`（没装 AutoModpack 的客户端会被提示去装）

改完 `docker compose restart minecraft` 生效。

## TLS 证书

AutoModpack 分发整合包时走 TLS，证书和私钥固定在容器的
`/data/automodpack/credentials/certificate.crt`、`/data/automodpack/credentials/private-key.pem`
（即宿主机 `data/automodpack/credentials/`，不在 git 里）。

- 首次启动时这两个文件不存在，mod 会自己生成一对自签证书，并在日志打印
  `Certificate fingerprint: <叶证书 SHA-256>`。自签证书能连，但客户端要么在弹窗里手动信任，
  要么靠 DNS TXT 发布的指纹（AutoModpack 的 ADDRESS_PIN）才会静默通过。
- 想免掉这一步就用公网 CA 证书（当前是 `*.painwind.cn` 的 Let's Encrypt 证书）：
  把**证书链和私钥**覆盖到上面两个路径即可。文件必须**成对且匹配**，只放一个会启动失败
  （`the certificate or the private key is unreadable` / `IllegalStateException`）。
- 证书文件里放整条链（叶 + 中间证书 + 根）没关系，AutoModpack 会把整个文件当作证书链发给客户端；
  私钥 RSA 与 EC（PKCS#8）都支持。
- 换证书后必须重启容器：`docker compose restart minecraft`，然后在日志确认
  `Certificate fingerprint:` 变成了新证书叶证书的 SHA-256（小写、无冒号）。启动约 3–5 分钟，
  AutoModpack 会重新校验整包。
- 仓库里的 `automodpack/credentials/` 不是运行时目录（compose 只挂 `server.conf` 和 `host-modpack`），
  放在那里不会生效。
- 公网 CA 证书有到期时间（当前证书 2027-01-06 到期），续期后要重新拷一次并重启；
  替换前建议先备份自签那对文件。

## 内存

`.env` 里 `MC_MEMORY=10G`（JVM `-Xmx`），`INIT_MEMORY=4G`。GregTech + TFC 属于吃内存大户，
8 人以内 10G 起，机器内存 ≥16G 再考虑往上加；下调到 8G 以下容易出现卡顿与 GC 抖动。

## 让玩家连进来

**A. 走 AutoModpack（推荐，永远和服务端一致）**

1. 装 Forge 1.20.1（47.4.13）；
2. 把 `client/automodpack-5.0.0-rc.2.jar` 丢进 `.minecraft/mods/`；
3. 启动游戏，直连服务器 IP:25565，连上后提示同步整包，确认后自动下载，重启游戏生效。

**B. 直接用 CurseForge 启动器**：搜 `TerraFirmaGreg-Modern` 0.13.16，装完再连。

## 升级整合包

1. 新 zip 放进 `modpacks/`，改 `compose.yaml` 里 `CF_MODPACK_ZIP` 的文件名；
2. `docker compose up -d`（安装器会重新对比安装）；
3. 服务端 ready 后 AutoModpack 会重新生成整包，玩家下次连接自动增量更新。

`data/mods/automodpack.jar` 由 `client/automodpack-5.0.0-rc.2.jar` 经 `/mods` 挂载自动复制，不需要手工放；
`automodpack/host-modpack/` 在仓库里，也不会被整合包更新冲掉。

升级后如果 `createdeco` 换了版本，要重跑一次 `scripts/patch-createdeco.sh`（见「createdeco 大写贴图修复」）；
新版本若已修掉大写文件名，脚本会提示并保留原样即可。

## 注意

- 本机的 `watchtower` 是 `--label-enable` 模式，本容器没有加 `com.centurylinklabs.watchtower.enable`
  标签，所以不会被自动更新重启。
- `MAX_TICK_TIME=-1`（关闭看门狗）：TFC 世界生成、GregTech 多方块会长时间占满单个 tick，开着看门狗会把
  正常的世界生成误判成卡死并 kill 服务端。
- `CF_IGNORE_MISSING_FILES: mods/*.jar`：客户端专属 mod 被移到 host-modpack、GregTech 会自改 jar 名，
  都会让安装器判定「整合包文件缺失」并重装整包；整体放开后缺失文件不会触发重装，
  要重新校验可用 `CF_FORCE_SYNCHRONIZE=true` 临时启动一次。
- `CF_EXCLUDE_INCLUDE_FILE=""`（关掉镜像自带的排除表）：镜像默认排除表会通过 CurseForge API 逐个解析条目，
  本项目下返回 403 直接中断安装；而且完整的 mod 集合必须留在服务端，客户端才能通过 AutoModpack 拿到一致内容。
- `ONLINE_MODE=FALSE`：离线模式，局域网验证用。要只允许正版账号就把 `compose.yaml` 里改成 `"TRUE"`。
- 世界类型不需要 `LEVEL_TYPE`：TFC 把 `tfc:overworld` 追加进了 `minecraft:normal` 世界预设，默认世界就是 TFC 地形。
