# Ticket Selling KEDA & EKS Infrastructure

This repository contains the infrastructure code, **Kubernetes Event-driven Autoscaling (KEDA)** configurations, Terraform IaC modules, monitoring integration, and load testing suites for the **Ticket Selling** platform on Amazon EKS.

---

## Architecture Overview

![KEDA Architecture Diagram](assets/architecture.png)

---

## Repository Structure

```text
ticket-selling-keda/
├── .github/workflows/             # GitHub Actions automated workflows (01-06)
├── assets/                        # Architecture diagrams and documentation assets
├── cluster/
│   └── terraform/                 # Terraform IaC (VPC, EKS, SQS, AMP, AMG, IRSA, OIDC)
├── hpa/                           # Baseline CPU-based HPA manifests for benchmark comparison
│   ├── client-cpu-hpa.yaml
│   ├── payments-cpu-hpa.yaml
│   └── README.md
├── keda/                          # KEDA ScaledObjects (SQS triggers and Prometheus metrics)
├── manifests/                     # Kubernetes deployment manifests, services, and ALB ingress
├── monitoring/                    # ADOT collector, SigV4 proxy, and Grafana dashboard JSONs
├── setup/                         # Automated deployment and verification bash scripts
└── tests/                         # Load testing scripts
    ├── k6/                        # k6 load testing scenarios S1-S6 and execution runner
    └── locust/                    # Locust load testing configuration and docker-compose
```

---

## Deployment & Operation

### 1. Provision AWS Infrastructure
Initialize and apply the Terraform configuration under `cluster/terraform/`:

```bash
cd cluster/terraform
terraform init
terraform apply -auto-approve
```

### 2. Deploy Microservices Workloads
Apply the Kubernetes manifests to deploy MongoDB, microservices, and ALB ingress rules:

```bash
bash setup/deploy-app.sh
```

### 3. Deploy KEDA & ScaledObjects
Install KEDA Operator via Helm and apply SQS ScaledObjects:

```bash
bash setup/deploy-keda-sqs.sh
```

### 4. Setup Prometheus & Monitoring
Deploy ADOT Collector, SigV4 Proxy, and import Grafana dashboards:

```bash
bash setup/deploy-amp-monitoring.sh
```

### 5. Execute Load Testing & Benchmark
Run k6 load test scenarios to evaluate KEDA event-driven autoscaling vs baseline HPA:

```bash
cd tests/k6
python3 run_scenario.py S1 1 60
```

---

## Related Repositories

- **[`ticket-selling-sample-application`](https://github.com/phuocan803/ticket-selling-sample-application)**: Microservices application source code (`auth`, `client`, `orders`, `tickets`, `payments`, `expiration`).
- **[`ticket-selling-dev-setup`](https://github.com/phuocan803/ticket-selling-dev-setup)**: Local workstation setup guide, CLI installation scripts, and Rancher GUI console.
