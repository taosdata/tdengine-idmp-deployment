# 使用 Ansible 部署 TDengine IDMP

简体中文 | [English](README.md)

本项目提供了一套基于 Ansible 的自动化部署工具，用于简化 TDengine IDMP 的部署过程。通过这套工具，您可以轻松地在多台服务器上完成 TDengine IDMP 的安装和配置。

## Ansible 简介

Ansible 是一个开源的自动化工具，用于配置管理、应用部署、云服务编排等。它使用 YAML 语言描述自动化任务，具有以下特点：

- 无需在被管理节点安装客户端
- 使用 SSH 进行通信
- 使用 YAML 格式的 playbook 来描述自动化任务
- 具有丰富的模块库

`Ansible` 安装和使用请参考 [Ansible 官方文档](https://docs.ansible.com/ansible/latest/getting_started/index.html)

## TDengine IDMP 部署步骤

> **NOTE:**
> 本部署方案使用 `ansible-vault` 来管理敏感信息，以确保密码等敏感信息在版本控制中安全存储。

### 1. 编辑 hosts 文件

首先需要编辑 `inventory/hosts` 文件，配置目标服务器信息。请根据您的实际环境修改服务器地址和连接信息。

### 2. 配置服务器密码

使用以下命令编辑加密的配置文件：

```bash
ansible-vault edit inventory/group_vars/public.yml
```

当系统提示输入 `Vault password` 时，请输入：`taosdata`

在此文件中，您需要配置所有服务器的用户名和密码信息。请注意：
- 所有服务器必须使用相同的密码
- 请妥善保管密码信息

### 3. 执行部署

运行以下命令仅部署 TDengine IDMP 服务：

```bash
ansible-playbook playbooks/tdengine-idmp.yml --ask-vault-pass
```

或运行以下命令部署 TDengine TSDB 和 TDengine IDMP 服务

```bash
ansible-playbook playbooks/tdengine-idmp.yml --ask-vault-pass -e deploy_tdengine=true
```

当系统提示输入 `Vault password` 时，请输入：`taosdata`

## 注意事项

- 请确保所有目标服务器可以通过 SSH 访问
- 部署前请仔细检查配置信息
- 建议在测试环境验证配置后再在生产环境部署