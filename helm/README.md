# TDengine-IDMP Helm Chart

English | [简体中文](README-CN.md)

This Helm Chart deploys the **TDengine Industrial Data Management Platform** service on Kubernetes.

## Prerequisites

- Helm 3
- (Optional) PersistentVolume provisioner if persistence is enabled

## Installation

```bash
helm install tdengine-idmp .
```

Or with custom values:

```bash
helm install tdengine-idmp . -f my-values.yaml
```

## Uninstallation

```bash
helm uninstall tdengine-idmp
```

## Configuration

The following table lists the configurable parameters of the chart and their default values.

| Parameter                  | Description                                 | Default                |
|----------------------------|---------------------------------------------|------------------------|
| `replicaCount`             | Number of replicas                          | `1`                    |
| `image.repository`         | Image repository                            | `tdengine/tdengine-idmp`|
| `image.tag`                | Image tag                                   | `latest`               |
| `image.pullPolicy`         | Image pull policy                           | `IfNotPresent`         |
| `service.type`             | Kubernetes service type                     | `ClusterIP`            |
| `service.port`             | Service port                                | `6042`                 |
| `resources`                | Resource requests and limits                | `{}`                   |
| `persistence.enabled`      | Enable persistent storage                   | `false`                |
| `persistence.size`         | Persistent volume size                      | `2Gi`                  |
| `persistence.storageClass` | StorageClass for persistent volume          | `""`                   |
| `nodeSelector`             | Node selector for pod assignment            | `{}`                   |
| `tolerations`              | Tolerations for pod assignment              | `[]`                   |
| `affinity`                 | Affinity rules for pod assignment           | `{}`                   |

You can override any parameter using `--set key=value` or by editing `values.yaml`.

## Accessing the Service

- **ClusterIP (default):**
  Use port-forward to access from your local machine:
  ```bash
  kubectl port-forward svc/tdengine-idmp 6042:6042 --address 0.0.0.0
  ```
  Then access `localhost:6042`.

- **NodePort:**
  1. Get the NodePort and node IP:
     ```bash
     kubectl get svc tdengine-idmp
     kubectl get nodes -o wide
     ```
  2. Access the service at `http://<NodeIP>:<NodePort>`
     > **Note:**
     > - Make sure the NodePort is open in your firewall or cloud security group.
     > - You can use any node's IP in the cluster.

- **LoadBalancer:**
  Access via the external IP assigned by your cloud provider.

## Persistence

To enable persistent storage, set `persistence.enabled: true` in `values.yaml`.
Make sure your cluster supports PersistentVolume provisioning.

## Customization

You can customize the deployment by editing `values.yaml` or using `--set` on the command line.