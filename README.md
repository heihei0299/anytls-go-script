# sing-box-deploy

一键部署 sing-box anytls / hysteria2 服务端，并输出 mihomo 客户端配置。节点名称默认使用 `hostname`，双协议默认 TCP/UDP 同端口复用。

## 一键部署

```bash
sudo curl -fsSL https://raw.githubusercontent.com/heihei0299/sing-box-deploy/refs/heads/main/deploy.sh | bash
```

部署成功后，当前目录会生成 `mihomo.yaml`（兼容 `mihomo-anytls.yaml`），直接复制到 mihomo 的 `proxies` 段即可。

> 兼容入口：`deploy-anytls.sh` 仍可用（已废弃），内部转发至 `deploy.sh`。

## 选项

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` / `--anytls-port` | anytls 监听端口 | 443 |
| `--hy2-port` | hysteria2 监听端口（默认与 `--port` 同号，TCP/UDP 同号复用） | 同 `--port` |
| `--padding-scheme` | 自定义 anytls padding scheme JSON | 标准方案 |
| `--name` | 节点基础名称（覆盖 hostname） | `hostname` 短名 |
| `--password` | 自定义 anytls 密码 | 随机生成 |
| `--hy2-password` | 自定义 hy2 密码 | 独立随机生成 |
| `--no-hy2` / `--anytls-only` | 仅部署 anytls | — |
| `--no-anytls` / `--hy2-only` | 仅部署 hy2 | — |
| `--dry-run` / `--dry` | 预览不执行 | — |
| `--help` / `-h` | 帮助 | — |

节点命名规则（`--name` 未指定时取 `hostname` 短名，非法字符替换为 `-`，空则回退 `sing-box`）：

- anytls IPv4: `<hostname>`
- anytls IPv6: `<hostname>-ipv6`
- hy2 IPv4: `<hostname>-hy2`
- hy2 IPv6: `<hostname>-hy2-ipv6`

双协议默认同端口复用：anytls 监听 TCP、hy2 监听 UDP，共享同一端口号；如需分离请显式指定 `--hy2-port`。

### 示例

```bash
# 默认双协议，端口 443，命名取 hostname
sudo ./deploy.sh

# 自定义端口与名称
sudo ./deploy.sh --port 8443 --name myhost

# 分离端口
sudo ./deploy.sh --port 443 --hy2-port 8443

# 仅部署其一
sudo ./deploy.sh --anytls-only
sudo ./deploy.sh --hy2-only

# 预览
sudo ./deploy.sh --dry

# 兼容旧入口（已废弃）
sudo ./deploy-anytls.sh --port 8443
```

## 输出（mihomo 配置）

部署完成后脚本输出如下配置并保存到 `./mihomo.yaml`（同时复制到 `./mihomo-anytls.yaml` 兼容旧路径）：

```yaml
proxies:
  - name: myhost
    type: anytls
    server: <自动检测的公网 IP>
    port: 443
    password: "<anytls 密码>"
    client-fingerprint: chrome
    udp: false
    skip-cert-verify: true
  - name: myhost-hy2
    type: hysteria2
    server: <自动检测的公网 IP>
    port: 443
    password: "<hy2 密码>"
    sni: <自动检测的公网 IP>
    skip-cert-verify: true
    alpn:
      - h3
  # IPv6 可用时额外生成 myhost-ipv6 / myhost-hy2-ipv6
```

## 原理

1. 添加 sing-box 官方 apt 仓库并安装
2. 生成 ECDSA P-256 自签名证书（anytls 与 hy2 复用）
3. 写入 `/etc/sing-box/config.json`（`anytls-in` / `hy2-in` 双 inbound，幂等合并）
4. `systemctl enable --now sing-box`
5. 自动检测公网 IP，输出 mihomo 客户端配置

## 系统要求

- Ubuntu / Debian
- 需 root 权限
