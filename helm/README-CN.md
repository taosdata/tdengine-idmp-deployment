# TDengine-AI Helm Chart

简体中文 | [English](README.md)

此 Helm Chart 用于在 Kubernetes 上部署 **TDengine 资产智能** 服务。

## 前置条件

- Helm 3
- （可选）如果启用持久化存储，需要 PersistentVolume 供应器

## 安装

```bash
helm install tdengine-ai .
```

或使用自定义配置值：

```bash
helm install tdengine-ai . -f my-values.yaml
```

## 卸载

```bash
helm uninstall tdengine-ai
```

## 配置

下表列出了 chart 的可配置参数及其默认值。

| 参数                      | 描述                                       | 默认值                  |
|--------------------------|-------------------------------------------|------------------------|
| `replicaCount`           | 副本数量                                   | `1`                    |
| `image.repository`       | 镜像仓库                                   | `tdengine/tdengine-ai` |
| `image.tag`              | 镜像标签                                   | `latest`               |
| `image.pullPolicy`       | 镜像拉取策略                               | `IfNotPresent`         |
| `service.type`           | Kubernetes 服务类型                        | `ClusterIP`            |
| `service.port`           | 服务端口                                   | `6042`                 |
| `resources`              | 资源请求和限制                             | `{}`                   |
| `persistence.enabled`    | 启用持久化存储                             | `false`                |
| `persistence.size`       | 持久卷大小                                 | `2Gi`                  |
| `persistence.storageClass`| 持久卷的存储类                            | `""`                   |
| `nodeSelector`           | Pod 分配的节点选择器                       | `{}`                   |
| `tolerations`            | Pod 分配的容忍设置                         | `[]`                   |
| `affinity`               | Pod 分配的亲和性规则                       | `{}`                   |

您可以通过使用 `--set key=value` 或编辑 `values.yaml` 来覆盖任何参数。

## 访问服务

- **ClusterIP（默认）：**
  使用端口转发从本地机器访问：
  ```bash
  kubectl port-forward svc/tdengine-ai 6042:6042
  ```
  然后访问 `localhost:6042`。

- **NodePort：**
  1. 获取 NodePort 和节点 IP：
     ```bash
     kubectl get svc tdengine-ai
     kubectl get nodes -o wide
     ```
  2. 通过 `http://<节点IP>:<NodePort>` 访问服务
     > **注意：**
     > - 确保防火墙或云安全组中开放了 NodePort
     > - 您可以使用集群中任何节点的 IP

- **LoadBalancer：**
  通过云服务提供商分配的外部 IP 访问。

## 持久化

要启用持久化存储，在 `values.yaml` 中设置 `persistence.enabled: true`。
确保您的集群支持 PersistentVolume 供应。

## 自定义

您可以通过编辑 `values.yaml` 或在命令行中使用 `--set` 来自定义部署。