# Storage Agent

`agent/` 是 Server Storage Management System 的节点状态采集程序。

它负责采集当前节点的 CPU、内存、磁盘使用率，并上报到 Go 管理后台：

```text
Agent 节点
  -> POST /api/servers/report
  -> Management Server
  -> /servers 页面展示节点状态
```

## 重要说明

当前项目只有一个 Go module，`go.mod` 位于仓库根目录。

因此，`agent/` 不是独立 Go module。不要只复制 `agent/` 文件夹到服务机后直接执行 `go build`，否则会缺少根目录的 `go.mod` 和 `go.sum`。

推荐做法是在仓库根目录编译二进制，然后把二进制分发到各节点。

## 本地测试

在项目根目录执行：

```bash
go run ./agent \
  -server http://192.168.1.187:8080 \
  -name NodeA \
  -address 192.168.1.188 \
  -disk / \
  -once
```

参数说明：

- `-server`：管理后台地址。
- `-name`：当前节点名称，例如 `storage-server`、`NodeA`、`NodeB`。
- `-address`：当前节点 IP。
- `-disk`：要统计的磁盘路径，默认 `/`。
- `-interval`：持续运行时的上报间隔，默认 `30s`。
- `-once`：只上报一次后退出，适合测试。

## 编译

在项目根目录执行：

```bash
go build -o bin/storage-agent ./agent
```

## 分发到节点

示例：

```bash
scp bin/storage-agent user@192.168.1.188:/tmp/storage-agent
ssh user@192.168.1.188 'sudo install -m 0755 /tmp/storage-agent /usr/local/bin/storage-agent'
```

每台节点都安装一份 `storage-agent`，但启动参数里的 `-name` 和 `-address` 应该不同。

## 手动运行

```bash
/usr/local/bin/storage-agent \
  -server http://192.168.1.187:8080 \
  -name NodeA \
  -address 192.168.1.188 \
  -disk /
```

只测试一次：

```bash
/usr/local/bin/storage-agent \
  -server http://192.168.1.187:8080 \
  -name NodeA \
  -address 192.168.1.188 \
  -disk / \
  -once
```

## systemd 部署

项目提供了 systemd 模板：

```text
configs/storage-agent.service
```

安装 Agent：

```bash
sudo scripts/install_storage_agent.sh
```

如果还没有准备统一部署配置，先执行：

```bash
cp configs/site.env.example configs/site.env
vim configs/site.env
```

每台节点部署前，在 `configs/site.env` 中把 `SSMS_AGENT_NAME` 和 `SSMS_AGENT_ADDRESS` 改成当前节点值。`SSMS_SERVER_URL`、`SSMS_AGENT_NAME`、`SSMS_AGENT_ADDRESS` 不能为空，否则安装脚本和 systemd 都会拒绝启动 Agent。

当前 Go 后端是 HTTP 服务，`SSMS_SERVER_URL` 应使用 `http://主节点IP:8080`，不要写成 `https://`。

生成后的环境变量示例：

```text
SSMS_SERVER_URL=http://192.168.1.187:8080
SSMS_AGENT_NAME=NodeA
SSMS_AGENT_ADDRESS=192.168.1.188
SSMS_AGENT_DISK=/
SSMS_AGENT_INTERVAL=30s
```

启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now storage-agent
sudo systemctl status storage-agent
```

查看日志：

```bash
journalctl -u storage-agent -f
```

## 页面验证

打开管理后台：

```text
http://192.168.1.187:8080/servers
```

预期结果：

- 节点名称显示为 `-name` 参数传入的值。
- 节点状态为在线。
- CPU、内存、磁盘使用率正常显示。
- 最后上报时间会持续更新。
