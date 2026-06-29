# 部署文档索引

本目录保存部署说明、命令参考和测试报告。建议优先阅读操作文档；测试报告主要用于追溯实测过程和问题处理。

## 推荐阅读顺序

1. [../design/runbook.md](../design/runbook.md)：后端、Agent、systemd 和接口验证总入口。
2. [ssmsctl.md](ssmsctl.md)：统一管理命令。
3. [bootstrap-storage-server.md](bootstrap-storage-server.md)：全新 Storage Server 自动部署。
4. [storage-server.md](storage-server.md)：Storage Server 手工部署。
5. [node-client.md](node-client.md)：登录节点客户端部署。
6. [smb-gateway.md](smb-gateway.md)：SMB Gateway 部署和验证。
7. [testing.md](testing.md)：第一版 demo 测试流程。

## 操作文档

| 文档 | 用途 |
| --- | --- |
| [commands.md](commands.md) | 常用命令速查 |
| [ssmsctl.md](ssmsctl.md) | 统一命令入口 |
| [bootstrap-storage-server.md](bootstrap-storage-server.md) | 全新 Storage Server 自动部署 |
| [storage-server.md](storage-server.md) | 存储服务安装和配置 |
| [node-client.md](node-client.md) | 登录节点安装和自动挂载 |
| [smb-gateway.md](smb-gateway.md) | 节点 SMB Gateway |
| [user-sync.md](user-sync.md) | 用户同步、删除和跨节点分发 |
| [winpc-ubuntu26.md](winpc-ubuntu26.md) | Windows PC 上 Ubuntu 虚拟机环境准备 |
| [agentB-integration.md](agentB-integration.md) | A/B 脚本与后台接口对接说明 |
| [architecture.md](architecture.md) | 部署侧架构简述 |

## 测试报告

| 文档 | 用途 |
| --- | --- |
| [demo-test-report.md](demo-test-report.md) | 第一版 demo 与接口测试记录 |
| [storage-server-test-report.md](storage-server-test-report.md) | Storage Server 单机测试记录 |
| [full-integration-test-report.md](full-integration-test-report.md) | NodeA / NodeB 联调记录 |
| [nodec-integration-test-report.md](nodec-integration-test-report.md) | NodeC 接入和回归记录 |
| [bootstrap-storage-server-test-report.md](bootstrap-storage-server-test-report.md) | 新 Storage Server 自动部署实测 |

## 维护原则

- 新的部署步骤优先写入操作文档，不再把同一流程复制到多个测试报告。
- 测试报告保留实测命令、现象和结论，不作为日常操作入口。
- IP 地址、节点名和用户名如属于示例，应明确写成示例；真实环境以 `configs/site.env.example` 和实际配置为准。
