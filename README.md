# TerraFirmaGreg-Modern 0.13.16 服务端

Minecraft **1.20.1** + **Forge 47.4.13**，整合包 `modpacks/TerraFirmaGreg-Modern-0.13.16-curseforge.zip`（CurseForge 包，276+ 个 mod，
含 GregTech Modern / TerraFirmaCraft / KubeJS 脚本）。

- 服务端镜像：`itzg/minecraft-server:java17`（Forge 47.x / MC 1.20.1 需要 Java 17）
- 整合包安装：`TYPE=AUTO_CURSEFORGE` + `CF_SLUG=custom` + `CF_MODPACK_ZIP`
- 客户端 mod 分发：**AutoModpack 5.0.0-rc.2**（`data/mods/automodpack.jar`），服务器直接托管整包，
  有 AutoModpack 的客户端连上就会被同步成与服务端完全一致的 mod / config

## 目录

```
compose.yaml                 # 全部编排
.env                         # CF_API_KEY / 内存 / 端口（不进 git）
modpacks/*.zip               # 整合包原件，只读挂进容器 /modpacks
data/                        # 容器 /data，服务端全部运行时数据
  mods/automodpack.jar       # 手工放入，整合包自带的 mod 之外的那一个
  automodpack/               # AutoModpack 生成的配置、证书、host-modpack
client/automodpack-*.jar     # 发给玩家的 bootstrap jar
```

## 启动

```bash
cp .env.example .env      # 首次：填入 CF_API_KEY（https://console.curseforge.com/）
docker compose up -d
docker compose logs -f minecraft
```

首次启动要做两件慢事，`start_period` 给了 45 分钟：

1. 从 CurseForge 下 276+ 个 mod（`CF_PARALLEL_DOWNLOADS=8`）；
2. AutoModpack 在首次启动后生成整包（要算全量 SHA1 并打 zip），日志里是
   `Generating modpack...`，耗时几分钟。

看到 `Done (XXs)! For help, type "help"` 即启动完成。

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
| 25565/tcp | Minecraft 游戏 |
| 3001/tcp | AutoModpack 客户端 mod 同步（TLS） |

`docker ps` 里没有 `0.0.0.0:3001` 不代表没监听——AutoModpack 的监听器是 mod 自己起的，
且首次启动时还没生成整包，端口要等服务端 ready 之后才可用。

## 内存

`.env` 里 `MC_MEMORY=10G`（JVM `-Xmx`），`INIT_MEMORY=4G`。GregTech + TFC 属于吃内存大户，
8 人以内 10G 起，机器内存 ≥16G 再考虑往上加；下调到 8G 以下容易出现卡顿与 GC 抖动。

## 让玩家连进来

玩家侧两种方式，任选其一：

**A. 走 AutoModpack（推荐，永远和服务端一致）**

1. 装 Forge 1.20.1（47.4.13）；
2. 把 `client/automodpack-5.0.0-rc.2.jar`（与服务端 `data/mods/automodpack.jar` 同一份）
   丢进 `.minecraft/mods/`；
3. 启动游戏，直连服务器 IP:25565，连上后会提示同步整包，确认后自动下载。

**B. 直接用 CurseForge 启动器装整合包**：搜 `TerraFirmaGreg-Modern` 0.13.16，装完再连。

## 修改服务端行为

- 原版设置（MOTD、难度、视距、白名单…）走 `compose.yaml` 的 `environment`，
  或直接改 `data/server.properties` 后 `docker compose restart minecraft`。
- AutoModpack 设置：`data/automodpack/server.conf`（修改后重启容器生效）。
- 整合包自带的 config 已由安装器写进 `data/config`、`data/defaultconfigs`，改完记得也同步给玩家，
  否则 AutoModpack 会把你的改动当成"服务器版配置"下发（这是期望行为）。

## 升级整合包

1. 换成新的 zip 放进 `modpacks/`，改 `compose.yaml` 里 `CF_MODPACK_ZIP` 的文件名；
2. `docker compose up -d`（安装器会重新对比安装）；
3. `data/mods/automodpack.jar` 如果被清掉，重新拷一份进去（整合包更新不会自动带上它）；
4. 服务端 ready 后 AutoModpack 会重新生成整包并做校验，玩家下次连接自动增量更新。

## 注意

- 本机的 `watchtower` 是 `--label-enable` 模式，本容器没有加 `com.centurylinklabs.watchtower.enable`
  标签，所以不会被自动更新重启。
- `MAX_TICK_TIME=-1`（关闭看门狗）：TFC 世界生成、GregTech 多方块会长时间占满单个 tick，
  开着看门狗会把正常的世界生成误判成卡死并 kill 服务端。
- `CF_IGNORE_MISSING_FILES` 里排除了 `mods/gregtech*.jar` / `mods/gtm*.jar`：
  GregTech 会自己改 jar 文件名，不加这条每次启动都判定"文件缺失"进而重装整个包。
- `CF_EXCLUDE_INCLUDE_FILE=""`（关掉镜像自带的排除表）：镜像的默认排除表会通过 CurseForge API 逐个解析里面的条目，
  在本项目下返回 403 直接中断安装；而且完整的 mod 集合必须留在服务端，客户端才能通过 AutoModpack 拿到一致的内容。
- `ONLINE_MODE=TRUE`：只允许正版账号。
