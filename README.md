# anytls-go-script

一键部署 sing-box anytls 服务端，并输出 mihomo 客户端配置。

## 一键部署

```bash
sudo curl -fsSL https://raw.githubusercontent.com/shial/anytls-go-script/main/deploy-anytls.sh | bash
```

部署成功后，当前目录会生成 `mihomo-anytls.yaml`，直接复制到 mihomo 的 `proxies` 段即可。

## 选项

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` | 监听端口 | 443 |
| `--padding-scheme` | 自定义 padding scheme JSON | 标准方案 |
| `--dry-run` / `--dry` | 预览不执行 | — |
| `--help` / `-h` | 帮助 | — |

### 示例

```bash
# 默认 443 端口
sudo ./deploy-anytls.sh

# 自定义端口
sudo ./deploy-anytls.sh --port 8443

# 预览
sudo ./deploy-anytls.sh --dry
```

## 输出（mihomo 配置）

部署完成后脚本输出如下配置并保存到 `./mihomo-anytls.yaml`：

```yaml
proxies:
  - name: anytls
    type: anytls
    server: <自动检测的公网 IP>
    port: 443
    password: "<自动生成的密码>"
    client-fingerprint: chrome
    udp: false
    skip-cert-verify: true
```

## 原理

1. 添加 sing-box 官方 apt 仓库并安装
2. 生成 ECDSA P-256 自签名证书
3. 写入 `/etc/sing-box/config.json`（anytls inbound）
4. `systemctl enable --now sing-box`
5. 自动检测公网 IP，输出 mihomo 客户端配置

## 系统要求

- Ubuntu / Debian
- 需 root 权限
