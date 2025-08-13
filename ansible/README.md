# Deploy TDengine IDMP with Ansible

English | [简体中文](README-CN.md)

This project provides an Ansible-based automation tool to simplify the deployment of TDengine IDMP. With this tool, you can easily install and configure TDengine IDMP across multiple servers.

## Ansible Introduction

Ansible is an open-source automation tool for configuration management, application deployment, and cloud orchestration. It uses YAML language to describe automation tasks and has the following features:

- No client installation required on managed nodes
- Uses SSH for communication
- Uses YAML format playbooks to describe automation tasks
- Rich module library

For Ansible installation and usage, please refer to the [Ansible Official Documentation](https://docs.ansible.com/ansible/latest/getting_started/index.html)

## TDengine IDMP Deployment Steps

> **NOTE:**
> This deployment solution uses `ansible-vault` to manage sensitive information, ensuring passwords and other sensitive data are securely stored in version control.

### 1. Edit Hosts File

First, edit the `inventory/hosts` file to configure target server information. Please modify server addresses and connection information according to your environment.

### 2. Configure Server Password

Use the following command to edit the encrypted configuration file:

```bash
ansible-vault edit inventory/group_vars/public.yml
```

When prompted for `Vault password`, enter: `taosdata`

In this file, you need to configure the username and password information for all servers. Please note:
- All servers must use the same password
- Keep the password information secure

### 3. Execute Deployment

Run the following command to start deploy TDengine IDMP:

**Note:** Please replace `<idmp_version>` and `<tsdb_version>` with the actual version number.

```bash
ansible-playbook playbooks/tdengine-idmp.yml --ask-vault-pass -e tdengine_idmp_version=<idmp_version>
```

Or run the following command to start deploy TDengine TSDB Enterprise and TDengine IDMP:

```bash
ansible-playbook playbooks/tdengine-idmp.yml --ask-vault-pass -e tdengine_idmp_version=<idmp_version> -e deploy_tdengine_tsdb=true -e tdengine_tsdb_version=<tsdb_version>
```

When prompted for `Vault password`, enter: `taosdata`

## Important Notes

- Ensure all target servers are accessible via SSH
- Carefully check configuration information before deployment
- It is recommended to verify the configuration in a test environment before deploying to production