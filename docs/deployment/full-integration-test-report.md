# 三虚拟机完整联调测试报告

## 基本信息

```text
测试日期：2026-06-21
系统版本：Ubuntu 26.04 Server
安装介质：ubuntu-26.04-live-server-amd64
测试范围：Storage Server、NodeA、NodeB 三虚拟机联调
Storage Server IP：192.168.1.187
NodeA：已部署，IP 以实际虚拟机为准
NodeB：已部署，IP 以实际虚拟机为准
项目目录：~/ServerStorageManagementSystem
```

本次测试在已经完成 Storage Server 单机测试的基础上，继续验证登录节点自动挂载、跨节点共享访问和用户隔离。

## 测试目标

```text
1. NodeA 和 NodeB 可以访问 Storage Server 的 Samba 共享。
2. alice 在 NodeA 和 NodeB 上可以挂载同一份个人目录。
3. NodeA 创建的文件可以在 NodeB 上看到。
4. NodeB 创建的文件可以在 NodeA 上看到。
5. alice 登录节点后可以自动挂载 /home/alice/storage。
6. bob 登录后不能看到 alice 的文件。
7. Samba 用户隔离、Linux 权限隔离和 pam_mount 自动挂载均正常。
```

## 测试前置条件

Storage Server 已完成：

```text
1. Samba 服务已安装并运行。
2. /srv/samba/users 已创建。
3. alice、bob 已在 Storage Server 上创建为 Linux 用户和 Samba 用户。
4. alice、bob 的用户目录权限为 0700。
5. 用户 quota 已启用。
6. Storage Server 地址为 192.168.1.187。
```

NodeA 和 NodeB 已完成：

```text
1. 项目目录 ~/ServerStorageManagementSystem 已存在。
2. configs/system.conf 中 STORAGE_SERVER="192.168.1.187"。
3. install_node_client.sh 已安装 cifs-utils 和 libpam-mount。
4. /etc/security/pam_mount.conf.xml 已写入 Storage Server 地址。
5. 本地登录用户 alice、bob 已创建。
6. 节点本地 alice、bob 的密码与 Storage Server 上对应 Samba 密码一致。
```

## 测试步骤与结果

### 1. NodeA 手动挂载 alice 共享

在 NodeA 上执行：

```bash
sudo mkdir -p /mnt/ssms-alice
sudo mount -t cifs //192.168.1.187/alice /mnt/ssms-alice \
  -o username=alice,vers=3.0,sec=ntlmssp,uid=$(id -u alice),gid=$(id -g alice),file_mode=0600,dir_mode=0700
sudo -u alice touch /mnt/ssms-alice/manual-node01.txt
sudo -u alice ls -l /mnt/ssms-alice
sudo umount /mnt/ssms-alice
```

实测结果：

```text
NodeA 手动挂载 //192.168.1.187/alice 成功。
NodeA 可以在 alice 共享目录中创建 manual-node01.txt。
```

结论：NodeA 到 Storage Server 的 Samba 访问正常。

### 2. NodeB 手动挂载 alice 共享

在 NodeB 上首次执行手动挂载时，发现本地没有 `alice` 用户：

```text
id: 'alice': no such user
```

处理方式：

```bash
sudo scripts/create_node_user.sh alice
id alice
```

重新挂载：

```bash
sudo mkdir -p /mnt/ssms-alice
sudo mount -t cifs //192.168.1.187/alice /mnt/ssms-alice \
  -o username=alice,vers=3.0,sec=ntlmssp,uid=$(id -u alice),gid=$(id -g alice),file_mode=0600,dir_mode=0700
mount | grep /mnt/ssms-alice
sudo -u alice ls -l /mnt/ssms-alice
sudo -u alice touch /mnt/ssms-alice/manual-nodeb.txt
sudo -u alice ls -l /mnt/ssms-alice
sudo umount /mnt/ssms-alice
```

实测结果：

```text
NodeB 手动挂载 //192.168.1.187/alice 成功。
NodeB 可以看到 NodeA 创建的 manual-node01.txt。
NodeB 可以创建 manual-nodeb.txt。
```

说明：

```text
普通用户 nodeb1 执行 ls -l /mnt/ssms-alice 时出现 Permission denied。
这是预期行为，因为挂载参数将目录权限映射为 uid=alice、gid=alice、dir_mode=0700。
使用 sudo ls 或 sudo -u alice ls 可以正常查看。
```

结论：NodeB 到 Storage Server 的 Samba 访问正常，权限映射符合设计。

### 3. NodeB 登录自动挂载

在 NodeB 上执行：

```bash
su - alice
mount | grep /home/alice/storage
ls -l /home/alice/storage
touch /home/alice/storage/auto-nodeb.txt
exit
```

实测结果：

```text
alice 登录 NodeB 后，/home/alice/storage 自动挂载成功。
自动挂载目录中可以看到 NodeA 和 NodeB 手动挂载测试创建的文件。
NodeB 可以通过自动挂载目录创建 auto-nodeb.txt。
```

结论：NodeB 的 pam_mount 自动挂载生效。

### 4. NodeA 验证 NodeB 写入文件

在 NodeA 上执行：

```bash
su - alice
ls -l /home/alice/storage
exit
```

实测结果：

```text
NodeA 可以看到 NodeB 创建的 manual-nodeb.txt 和 auto-nodeb.txt。
```

结论：alice 在 NodeA 和 NodeB 上访问的是 Storage Server 上的同一份个人数据。

### 5. bob 用户隔离测试

在节点上以 bob 登录：

```bash
su - bob
mount | grep /home/bob/storage
ls -l /home/bob/storage
exit
```

实测结果：

```text
bob 登录后看不到 alice 的文件。
```

结论：用户隔离生效，bob 不能访问 alice 的数据。

## 测试结论

三虚拟机完整联调测试通过。

已验证功能：

```text
1. NodeA 手动挂载 //192.168.1.187/alice 成功。
2. NodeB 手动挂载 //192.168.1.187/alice 成功。
3. NodeB 能看到 NodeA 创建的 manual-node01.txt。
4. NodeB 能创建 manual-nodeb.txt。
5. alice 登录 NodeB 后，/home/alice/storage 自动挂载成功。
6. NodeA 能看到 NodeB 创建的文件。
7. alice 在不同节点访问同一份共享数据。
8. bob 登录后看不到 alice 的文件。
9. Samba 用户隔离、Linux 权限隔离、pam_mount 自动挂载、跨节点共享访问均通过。
```

## 本次测试发现的问题与处理

### 1. NodeB 缺少本地 alice 用户

现象：

```text
id: 'alice': no such user
```

原因：

```text
NodeB 尚未创建本地 Linux 登录用户 alice。
手动挂载命令中的 uid=$(id -u alice)、gid=$(id -g alice) 无法解析。
```

处理：

```bash
sudo scripts/create_node_user.sh alice
```

结果：问题解决。

### 2. nodeb1 查看 alice 挂载目录被拒绝

现象：

```text
ls: cannot open directory '/mnt/ssms-alice': Permission denied
```

原因：

```text
CIFS 挂载使用 uid=alice、gid=alice、dir_mode=0700。
这表示只有 alice 或 root 可以访问该挂载目录。
nodeb1 不是 alice，因此访问被拒绝是正确的权限隔离表现。
```

验证：

```bash
sudo ls -l /mnt/ssms-alice
sudo -u alice ls -l /mnt/ssms-alice
```

结果：root 和 alice 均可查看，权限设计正确。

## 后续建议

```text
1. 在 docs/deployment/node-client.md 中补充 Permission denied 排错说明。
2. 后续可把 NodeA、NodeB 的实际 IP 写入本报告，便于最终归档。
3. 若需要长期运行节点状态采集 Agent，可继续补充 systemd 服务文件。
```
