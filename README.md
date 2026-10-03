# sing-box-deploy

一键部署 sing-box anytls / hysteria2 服务端，并生成 Mihomo 客户端配置。

## 快速开始

```bash
sudo curl -fsSL https://raw.githubusercontent.com/heihei0299/sing-box-deploy/refs/heads/main/deploy.sh | bash
```

默认启用 anytls 和 hysteria2，端口为 443。部署后会在当前目录生成 `mihomo.yaml`，并生成兼容旧路径 `mihomo-anytls.yaml`。

## 常用选项

| 参数 | 说明 |
|------|------|
| `--port <端口>` | anytls 端口，默认 443；`--anytls-port` 是别名 |
| `--hy2-port <端口>` | hysteria2 端口，默认与 anytls 相同 |
| `--name <名称>` | 自定义节点名称，默认使用 hostname |
| `--password <密码>` / `--hy2-password <密码>` | 自定义对应协议的密码，默认分别随机生成 |
| `--anytls-only` / `--hy2-only` | 仅部署一种协议 |
| `--renew-cert` | 重新生成 TLS 证书；默认复用已有证书 |
| `--dry-run` | 预览操作，不执行部署或写入配置文件 |

更多选项：`sudo ./deploy.sh --help`。旧入口 `deploy-anytls.sh` 仍可用，但已弃用。

## 系统要求

- Ubuntu 或 Debian，实际部署需 root 权限。
- 防火墙和云安全组需放行对应端口：anytls 使用 TCP，hysteria2 使用 UDP。默认两者使用相同端口号；需要分开时设置 `--hy2-port`。
