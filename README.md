# Secure Standardized Kubernetes Platform on AWS

## Business Problem

Engineering teams were deploying containerized applications inconsistently. The company needed a standardized Kubernetes platform on AWS that provided repeatable deployments, controlled access, workload-specific AWS permissions, and security controls without requiring engineers to manually configure infrastructure.

## Solution

Designed and implemented a secure Amazon EKS platform using Terraform, Docker, Amazon ECR, Jenkins, Kubernetes RBAC, and EKS Pod Identity.

The platform provides:

- Infrastructure provisioning through Terraform
- Containerized application delivery with Docker
- Immutable container image storage in Amazon ECR
- Automated deployments through Jenkins
- IAM-based Jenkins authentication without static AWS credentials
- EKS Access Entries integrated with Kubernetes RBAC
- Workload-specific AWS permissions through EKS Pod Identity
- Non-root container execution and restricted Linux capabilities
- Kubernetes readiness and liveness health checks
- Functional and security validation
- Infrastructure drift validation

## Architecture

```text
Developer
    |
    v
GitHub
    |
    v
Jenkins on EC2
    |
    +---- Docker Build ----> Amazon ECR
    |
    +---- IAM Role
    |        |
    |        v
    |    EKS Access Entry
    |        |
    |        v
    |    Kubernetes RBAC
    |
    v
Amazon EKS
    |
    v
Kubernetes Deployment
    |
    +---- ServiceAccount
    |        |
    |        v
    |    EKS Pod Identity
    |        |
    |        v
    |    Least-Privilege IAM Role
    |
    v
Containerized Application


