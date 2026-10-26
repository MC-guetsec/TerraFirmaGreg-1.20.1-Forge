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
automodpack/host-modpack/main/mods/*.jar# 客户端专属 mod：发给客户端，但服务端不加载
client/automodpack-5.0.0-rc.2.jar       # 玩家用的 bootstrap jar；同时挂到 /mods 供镜像复制进 /data/mods
data/                                   # 容器 /data，服务端运行时数据（不进 git）
```

## 首次部署

```bash
cp .env.example .env
vi .env                                  # 填 CF_API_KEY（https://console.curseforge.com/）

mkdir -p modpacks
cp /path/to/TerraFirmaGreg-Modern-0.13.16-curseforge.zip modpacks/    # 198MB，不在仓库里

sudo chown -R 1000:1000 automodpack      # 容器以 uid 1000 运行，需要能回写 server.conf
docker compose up -d
docker compose logs -f minecraft
```

`modpacks/` 里的 zip 必须自己准备——仓库不收录 198MB 的整合包原件。

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
DEDICATED_SERVER`）。移动而不是删除，客户端拿到的整合包因此仍然完整。

再加新的客户端 mod：先放进 `data/mods/`，启动一次，等它崩溃，崩溃报告里会写 `Mod File: /data/mods/xxx.jar`，
把这个 jar 从 `data/mods/` 移到 `automodpack/host-modpack/main/mods/` 即可（AutoModpack 会自动把它发给客户端）。

## AutoModpack 配置

`automodpack/server.conf` 已经调过：

- `name` = `TerraFirmaGreg-Modern 0.13.16`
- `from-server` 在 `mods/*.jar`、`kubejs/**` 之外补了 `config/**`、`defaultconfigs/**`、`tacz/**`、
  `resourcepacks/**`、`shaderpacks/**`，保证客户端拿到和整合包一致的配置与资源
- `kubejs/server_scripts/**` 在 `exclude` 里（纯服务端脚本）
- `auto-exclude-server-side-mods: DISABLED`（不按 mod 元数据裁剪，避免把客户端需要的 jar 排掉）
- `require-modpack: true`（没装 AutoModpack 的客户端会被提示去装）

改完 `docker compose restart minecraft` 生效。

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
