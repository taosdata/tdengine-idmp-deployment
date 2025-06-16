# TDengine AI 部署

[English](README.md) | [简体中文](README-CN.md)

## 简介

TDengine AI 部署工具提供了多种部署方案，以支持不同的部署场景和需求。无论您是需要单机部署、多机部署还是在 Kubernetes 集群中部署，我们都提供了相应的解决方案。

## 特性

- 多种部署方式：
  - **Ansible**：自动化的多机部署
  - **Docker**：容器化部署
  - **Helm**：基于 Kubernetes 的部署
- 每种部署方式都有详细的文档
- 安全性优先的凭证管理
- 便捷的维护和更新

## 快速开始

根据您的需求选择合适的部署方式：

### Ansible 部署
适用于多机自动化部署，请参考 [Ansible 部署指南](ansible/README-CN.md)

### Docker 部署
适用于容器化部署，请参考 [Docker 部署指南](docker/README-CN.md)

### Helm 部署
适用于基于 Kubernetes 的部署，请参考 [Helm 部署指南](helm/README-CN.md)

## 环境要求

- Ansible 部署：
  - Ansible 2.9+
  - 目标机器的 SSH 访问权限
  - Python 3.6+
- Docker 部署：
  - Docker 20.10+
  - Docker Compose v2.0+（可选）
- Helm 部署：
  - Kubernetes 1.18+
  - Helm 3.0+

## 贡献指南

我们欢迎各种形式的贡献！详情请参阅 [贡献指南](https://github.com/taosdata/TDengine/blob/main/CONTRIBUTING.md)。

## 技术支持

- 访问我们的 [官方网站](https://taosdata.com)
- 电子邮件支持：support@taosdata.com