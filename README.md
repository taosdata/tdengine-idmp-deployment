# TDengine AI Deployment

English | [简体中文](README-CN.md)

## Introduction

TDengine AI Deployment Tools provide multiple deployment solutions for TDengine AI, supporting various deployment scenarios and requirements. Whether you need to deploy on a single machine, multiple machines, or in a Kubernetes cluster, we offer corresponding solutions.

## Features

- Multiple deployment methods:
  - **Ansible**: Automated deployment across multiple machines
  - **Docker**: Containerized deployment
  - **Helm**: Kubernetes-based deployment
- Comprehensive documentation for each deployment method
- Security-first approach with credential management
- Easy maintenance and updates

## Quick Start

Choose the deployment method that best suits your needs:

### Ansible Deployment
For multi-machine automated deployment, see [Ansible Deployment Guide](ansible/README.md)

### Docker Deployment
For containerized deployment, see [Docker Deployment Guide](docker/README.md)

### Helm Deployment
For Kubernetes-based deployment, see [Helm Deployment Guide](helm/README.md)

## Requirements

- For Ansible deployment:
  - Ansible 2.9+
  - SSH access to target machines
  - Python 3.6+
- For Docker deployment:
  - Docker 19.03+
  - Docker Compose v1.27.0+ (optional)
- For Helm deployment:
  - Kubernetes 1.24+
  - Helm 3.0+

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](https://github.com/taosdata/TDengine/blob/main/CONTRIBUTING.md) for details.

## Support

- Visit our [Official Website](https://tdengine.com)
- Email Support: support@taosdata.com
