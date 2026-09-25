# Standard Operating Procedure — Secure AWS EKS Platform

## 1. Purpose

This SOP documents the implementation, validation, troubleshooting, and teardown procedures used to build a secure standardized Kubernetes platform on AWS.

The platform uses:

- Terraform for AWS infrastructure
- Amazon EKS for Kubernetes
- Amazon ECR for container images
- Docker for application packaging
- Jenkins for CI/CD
- EKS Access Entries and Kubernetes RBAC for deployment authorization
- EKS Pod Identity for workload AWS access
- Amazon S3 for least-privilege workload-access validation

This SOP reflects the portfolio implementation actually deployed and tested. Production recommendations are documented separately from the proof-of-concept configuration.

---

## 2. Business Objective

Engineering teams were deploying containerized applications inconsistently.

The objective was to establish a repeatable AWS Kubernetes platform that:

1. Provisions infrastructure through code.
2. Packages applications consistently as containers.
3. Stores immutable application images centrally.
4. Automates application deployment.
5. Avoids static AWS credentials.
6. Restricts CI/CD permissions.
7. Provides workload-specific AWS permissions.
8. Enforces container security controls.
9. Validates both authorized and unauthorized operations.
10. Can be cleanly destroyed after portfolio evidence is collected.

---

## 3. Architecture

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
    |    Workload IAM Role
    |
    v
Application
```

---

## 4. Repository Layout

```text
aws-secure-eks-platform/
├── app/
│   ├── app.py
│   └── Dockerfile
├── docs/
│   └── SOP.md
├── kubernetes/
│   ├── deployment.yaml
│   ├── jenkins-rbac.yaml
│   ├── service-account.yaml
│   └── service.yaml
├── terraform/
│   ├── jenkins.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
├── .gitignore
├── Jenkinsfile
└── README.md
```

Runtime files such as Terraform state, Terraform variable values, saved plans, provider data, credentials, and private keys must not be committed.

---

## 5. Prerequisites

Administrative workstation or AWS CloudShell:

- AWS CLI
- Terraform
- Git
- kubectl
- Docker where local container validation is performed
- AWS permissions required to provision the portfolio environment

AWS Region:

```text
us-east-1
```

Required local configuration:

```text
terraform/terraform.tfvars
```

Use the tracked example file as the template:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Populate only the required environment-specific values.

Do not commit the real `terraform.tfvars`.

---

## 6. Repository Security Controls

The `.gitignore` must exclude runtime and sensitive files, including:

```text
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
tfplan
crash.log
terraform.tfvars
*.pem
*.key
.env
.env.*
```

Before every public push, verify:

```bash
git status --short
git diff
git ls-files
```

Do not commit:

- AWS credentials
- Terraform state
- Terraform plans
- Private keys
- Environment files
- Real variable values
- Jenkins bootstrap passwords
- Account-specific screenshots
- Sensitive identifiers unnecessarily

---

## 7. Terraform Initialization

Move into the Terraform configuration directory:

```bash
cd terraform
```

Initialize Terraform:

```bash
terraform init
```

Validate formatting:

```bash
terraform fmt -check
```

Validate configuration:

```bash
terraform validate
```

Create a saved plan when performing a controlled infrastructure change:

```bash
terraform plan -out=tfplan
```

Review the plan before applying it.

Never treat a successful `terraform plan` command as approval to apply destructive changes automatically.

---

## 8. Terraform Plan Review

Before every apply, inspect the summary:

```text
Plan: X to add, Y to change, Z to destroy.
```

Unexpected replacements or destruction must be investigated before applying.

Particular attention should be paid to:

- EKS cluster replacement
- Node-group replacement
- IAM role replacement
- VPC or subnet replacement
- ECR repository replacement
- Jenkins EC2 replacement
- Pod Identity changes

Apply only after the proposed changes match the intended engineering change.

---

## 9. AWS Network Foundation

Terraform provisions a dedicated VPC for the portfolio platform.

Portfolio network design:

```text
VPC: 10.30.0.0/16
```

The implementation includes:

- Two public subnets
- Availability Zone distribution
- Internet Gateway
- Public route table
- Default internet route
- Kubernetes load-balancer subnet tags

The proof of concept intentionally does not use a NAT Gateway.

This reduces portfolio cost but is not the recommended production worker-node architecture.

---

## 10. Amazon ECR

Terraform provisions the application ECR repository.

Controls include:

- Immutable image tags
- Scan-on-push enabled

Application images must use unique tags.

The Jenkins pipeline uses:

```text
build-${BUILD_NUMBER}
```

Do not repeatedly push a fixed tag such as `latest` into the immutable repository.

Validate images:

```bash
aws ecr list-images \
  --repository-name secure-eks-dev-app \
  --region us-east-1 \
  --query 'imageIds[*].imageTag' \
  --output table
```

---

## 11. Amazon EKS Cluster

Terraform provisions the EKS control plane and managed worker node group.

Portfolio node-group design:

- Managed node group
- One worker node
- On-demand capacity
- `t3.small`
- Public subnet placement

The one-node design is intentional for portfolio cost control.

Production should evaluate:

- Private worker subnets
- Multiple nodes
- Multiple Availability Zones
- Autoscaling
- Controlled outbound connectivity

---

## 12. EKS Authentication Mode

EKS Access Entries require API-based authentication.

The final cluster configuration uses:

```text
API_AND_CONFIG_MAP
```

This allowed migration from the existing `aws-auth`-based configuration while enabling EKS Access Entries.

Validate:

```bash
aws eks describe-cluster \
  --name secure-eks-dev-cluster \
  --region us-east-1 \
  --query 'cluster.accessConfig'
```

List access entries:

```bash
aws eks list-access-entries \
  --cluster-name secure-eks-dev-cluster \
  --region us-east-1
```

---

## 13. Configure kubectl

Configure the local kubeconfig:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name secure-eks-dev-cluster
```

Validate cluster access:

```bash
kubectl get nodes
```

Expected final node state:

```text
Ready
```

Validate system pods:

```bash
kubectl get pods -n kube-system
```

Critical networking and DNS workloads should be healthy before deploying the application.

---

## 14. VPC CNI Permissions

The Amazon VPC CNI requires EC2 networking permissions.

During implementation, the node initially remained:

```text
NotReady
```

The `aws-node` pod showed missing IAM permissions for EC2 networking operations.

For the portfolio implementation, the required VPC CNI IAM policy was attached to the worker-node role.

After applying the change:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

The worker node became `Ready` and the system workloads recovered.

For production, evaluate using a dedicated IAM role for the VPC CNI rather than keeping these permissions on the worker-node role.

---

## 15. Application Container

The application is a small Python HTTP service.

Endpoints:

```text
/
```

returns application status.

```text
/health
```

returns:

```text
healthy
```

The Docker image creates a dedicated non-root user and runs the application as that user.

Build locally:

```bash
docker build -t secure-eks-demo:v1 app/
```

Run locally:

```bash
docker run --rm -p 8080:8080 secure-eks-demo:v1
```

Validate:

```bash
curl http://localhost:8080/
curl http://localhost:8080/health
```

Validate runtime identity:

```bash
docker run --rm secure-eks-demo:v1 id
```

The application must not execute as root.

---

## 16. Kubernetes ServiceAccount

Create the dedicated application ServiceAccount:

```bash
kubectl apply -f kubernetes/service-account.yaml
```

Validate:

```bash
kubectl get serviceaccount secure-eks-demo
```

The application deployment references:

```text
secure-eks-demo
```

This ServiceAccount is also the Kubernetes identity associated with EKS Pod Identity.

---

## 17. Kubernetes Deployment Security

The application Deployment enforces:

- `runAsNonRoot: true`
- Explicit numeric non-root UID
- `allowPrivilegeEscalation: false`
- All Linux capabilities dropped
- CPU request and limit
- Memory request and limit
- Readiness probe
- Liveness probe
- Dedicated ServiceAccount

The source manifest uses:

```text
ECR_IMAGE_PLACEHOLDER
```

rather than embedding an account-specific ECR registry URI in the public repository.

---

## 18. Render Runtime Deployment Manifest

For manual validation, render the deployment using the actual ECR image URI into a temporary file.

Example pattern:

```bash
sed "s|ECR_IMAGE_PLACEHOLDER|${IMAGE_URI}|g" \
  kubernetes/deployment.yaml \
  > /tmp/deployment.yaml
```

Validate before applying:

```bash
kubectl apply \
  --dry-run=client \
  -f /tmp/deployment.yaml
```

Do not commit the rendered account-specific manifest.

---

## 19. Deploy Application Manually

Apply the Service:

```bash
kubectl apply -f kubernetes/service.yaml
```

Apply the rendered Deployment:

```bash
kubectl apply -f /tmp/deployment.yaml
```

Wait for rollout:

```bash
kubectl rollout status \
  deployment/secure-eks-demo \
  --timeout=180s
```

Validate:

```bash
kubectl get deployment secure-eks-demo
kubectl get pods -l app=secure-eks-demo
kubectl get service secure-eks-demo
```

Expected application pod state:

```text
1/1 Running
```

---

## 20. Validate Container Runtime Security

Run:

```bash
kubectl exec deployment/secure-eks-demo -- id
```

The output must show a non-root UID.

Also verify the ServiceAccount:

```bash
kubectl get deployment secure-eks-demo \
  -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
```

Expected:

```text
secure-eks-demo
```

---

## 21. Validate Application Functionality

Use port forwarding:

```bash
kubectl port-forward \
  service/secure-eks-demo \
  8080:80
```

From another terminal:

```bash
curl http://localhost:8080/
echo

curl http://localhost:8080/health
echo
```

Expected health result:

```text
healthy
```

Stop port forwarding when validation is complete:

```text
Ctrl+C
```

---

## 22. EKS Pod Identity Agent

The platform uses the EKS Pod Identity Agent managed add-on.

Validate:

```bash
aws eks describe-addon \
  --cluster-name secure-eks-dev-cluster \
  --addon-name eks-pod-identity-agent \
  --region us-east-1
```

Expected add-on state:

```text
ACTIVE
```

---

## 23. Workload IAM Role

The application workload uses a dedicated IAM role trusted by:

```text
pods.eks.amazonaws.com
```

The trust relationship allows the Pod Identity service to use the workload role.

The application IAM policy grants only the S3 permission required for the validation use case:

```text
s3:GetObject
```

against the approved validation object.

It does not grant broad bucket access.

---

## 24. Pod Identity Association

The EKS Pod Identity association connects:

```text
Cluster
    +
Namespace: default
    +
ServiceAccount: secure-eks-demo
    +
Workload IAM Role
```

Validate:

```bash
aws eks list-pod-identity-associations \
  --cluster-name secure-eks-dev-cluster \
  --region us-east-1
```

Restart or recreate the application pod after creating the association when necessary so the workload receives the Pod Identity configuration.

---

## 25. Pod Identity Security Validation

Use a temporary AWS CLI pod configured with the same ServiceAccount.

The validation must test both sides of the access model.

Authorized test:

```text
Read approved S3 validation object
```

Expected:

```text
ALLOWED
```

Unauthorized test:

```text
List the S3 bucket
```

Expected:

```text
AccessDenied
```

Do not add `s3:ListBucket` merely to make the unauthorized validation command succeed.

The denial proves the workload role is narrower than general S3 access.

Delete temporary validation pods after testing.

---

## 26. Jenkins IAM Identity

Jenkins runs on an EC2 instance using an instance profile.

The Jenkins instance does not require static AWS access keys.

Validate from the Jenkins instance:

```bash
sudo -u jenkins aws sts get-caller-identity
```

The identity should resolve to the Jenkins IAM role through temporary EC2 role credentials.

Do not publish account identifiers or complete ARNs from this output.

---

## 27. Jenkins EC2 Security

Portfolio Jenkins controls include:

- Dedicated IAM role
- EC2 instance profile
- Systems Manager access
- No SSH requirement
- IMDSv2 required
- Encrypted root volume
- Port 8080 restricted to the administrator's current public IP `/32`

Do not configure Jenkins port 8080 as:

```text
0.0.0.0/0
```

merely to resolve connectivity problems.

Diagnose the network path first.

---

## 28. Jenkins Software Requirements

The Jenkins controller requires:

- Java 21
- Jenkins
- Git
- Docker
- AWS CLI
- kubectl

The Jenkins user must be able to access Docker:

```bash
sudo -u jenkins docker version
```

Validate AWS identity:

```bash
sudo -u jenkins aws sts get-caller-identity
```

Validate kubectl client:

```bash
sudo -u jenkins kubectl version --client
```

---

## 29. Jenkins EKS Access Entry

Terraform creates an EKS Access Entry for the Jenkins IAM role.

The access entry uses the Kubernetes group:

```text
jenkins-deployers
```

Validate:

```bash
aws eks describe-access-entry \
  --cluster-name secure-eks-dev-cluster \
  --principal-arn <JENKINS_ROLE_ARN> \
  --region us-east-1
```

Do not place a real account-specific ARN into public documentation.

---

## 30. Kubernetes RBAC for Jenkins

Apply:

```bash
kubectl apply -f kubernetes/jenkins-rbac.yaml
```

The namespace Role permits Jenkins to perform required application deployment operations.

It does not grant Jenkins:

- Secret-reading privileges
- Node deletion
- ClusterRole management
- Namespace administration
- Cluster-wide administrator privileges

The RoleBinding maps:

```text
jenkins-deployers
```

to the namespace-scoped Role.

---

## 31. Validate Jenkins Authorization

From the actual Jenkins EC2 identity, configure kubeconfig:

```bash
sudo -u jenkins aws eks update-kubeconfig \
  --region us-east-1 \
  --name secure-eks-dev-cluster
```

Validate intended access:

```bash
sudo -u jenkins kubectl auth can-i \
  patch deployments \
  -n default
```

Expected:

```text
yes
```

Validate denied Secret access:

```bash
sudo -u jenkins kubectl auth can-i \
  get secrets \
  -n default
```

Expected:

```text
no
```

Validate denied node deletion:

```bash
sudo -u jenkins kubectl auth can-i \
  delete nodes
```

Expected:

```text
no
```

These tests validate:

```text
EC2 Instance Profile
    -> Jenkins IAM Role
    -> EKS Access Entry
    -> Kubernetes Group
    -> RoleBinding
    -> Namespace Role
```

---

## 32. Jenkins Job Configuration

Create a Jenkins Pipeline job using:

```text
Pipeline script from SCM
```

SCM:

```text
Git
```

Repository:

```text
Public project Git repository
```

Branch:

```text
*/main
```

Script path:

```text
Jenkinsfile
```

Static Git credentials are not required for a public repository.

---

## 33. Jenkins Pipeline

The final pipeline performs:

```text
Checkout
    |
Test Application
    |
Validate AWS Identity
    |
Build Docker Image
    |
Push Image to ECR
    |
Authenticate to EKS
    |
Render Deployment Manifest
    |
Deploy to EKS
    |
Validate Rollout
```

The Jenkinsfile disables Declarative Pipeline's automatic checkout because the pipeline contains an explicit Checkout stage.

This avoids performing the SCM checkout twice.

---

## 34. Docker Build in Jenkins

Jenkins creates a unique tag:

```text
build-${BUILD_NUMBER}
```

The pipeline builds:

```bash
docker build \
  -t "${ECR_REPOSITORY}:${IMAGE_TAG}" \
  app/
```

Unique tags are required because ECR tag immutability is enabled.

---

## 35. ECR Authentication in Jenkins

Jenkins obtains an ECR authorization token using its IAM role:

```bash
aws ecr get-login-password \
  --region "$AWS_REGION"
```

The token is piped to:

```bash
docker login
```

No permanent ECR password is stored in Jenkins.

---

## 36. ECR Push

The pipeline tags the local image with the ECR registry path and pushes the immutable build tag.

The Jenkins IAM role is scoped to the ECR actions required for image upload plus ECR authorization.

A denied `ecr:DescribeRepositories` diagnostic request should not automatically result in broader IAM permissions.

If the deployment workflow does not require that API, leave it denied.

---

## 37. Jenkins EKS Authentication

The pipeline creates a workspace-specific kubeconfig:

```text
${WORKSPACE}/.kube/config
```

Then runs:

```bash
aws eks update-kubeconfig
```

The pipeline verifies deployment authorization with:

```bash
kubectl auth can-i patch deployments \
  --namespace default
```

Expected:

```text
yes
```

---

## 38. Jenkins Manifest Rendering

The public Kubernetes manifest contains:

```text
ECR_IMAGE_PLACEHOLDER
```

Jenkins replaces this placeholder with the build-specific ECR image URI.

The rendered manifest remains a workspace artifact and must not be committed.

This avoids hardcoding account-specific ECR registry information into the repository.

---

## 39. Jenkins Deployment

Jenkins applies:

```text
kubernetes/service.yaml
```

and the rendered Deployment manifest.

Jenkins intentionally does not apply:

```text
kubernetes/service-account.yaml
```

The pipeline therefore cannot use its normal deployment permissions to modify the application's ServiceAccount identity path.

---

## 40. Jenkins Rollout Validation

After applying the manifests, Jenkins runs:

```bash
kubectl rollout status \
  deployment/secure-eks-demo \
  --namespace default \
  --timeout=180s
```

The pipeline also retrieves Deployment, Pod, and Service status.

A successful pipeline must end with a healthy Kubernetes rollout rather than treating a successful image push as completion.

---

## 41. Post-Pipeline Runtime Validation

After Jenkins reports success, independently verify the deployed image:

```bash
kubectl get deployment secure-eks-demo \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Confirm that the running Deployment references the Jenkins-generated build tag.

Validate pods:

```bash
kubectl get pods \
  -l app=secure-eks-demo \
  -o wide
```

Validate runtime identity:

```bash
kubectl exec deployment/secure-eks-demo -- id
```

Validate ServiceAccount:

```bash
kubectl get deployment secure-eks-demo \
  -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
```

Finally validate the application and health endpoint through port forwarding.

---

## 42. Final Terraform Drift Validation

From the repository root:

```bash
terraform -chdir=terraform plan
```

Expected:

```text
No changes. Your infrastructure matches the configuration.
```

Do not apply a plan if unexpected changes appear.

Investigate drift first.

---

## 43. Troubleshooting — Interrupted Terraform Apply

### Symptom

Terraform attempted to create an EKS managed node group but AWS returned:

```text
ResourceInUseException
```

### Diagnosis

The resource existed in AWS but was missing from Terraform state because a prior apply had been interrupted.

### Resolution

Inspect state:

```bash
terraform state list
```

Confirm the resource exists in AWS.

Import the existing node group using the EKS cluster and node-group identifiers:

```bash
terraform import \
  aws_eks_node_group.main \
  <cluster-name>:<node-group-name>
```

Run:

```bash
terraform plan
```

Expected final result:

```text
No changes.
```

### Lesson

Do not recreate an existing cloud resource simply because it is absent from Terraform state.

Reconcile state with actual infrastructure first.

---

## 44. Troubleshooting — EKS Node NotReady

### Symptom

```text
kubectl get nodes
```

showed:

```text
NotReady
```

The `aws-node` pod was not fully healthy.

### Diagnosis

Kubernetes events showed unauthorized EC2 networking operations.

### Root Cause

The VPC CNI did not have the EC2 networking permissions required to configure pod networking.

### Resolution

Add the required VPC CNI IAM permissions through Terraform.

Apply the intended IAM change.

Validate:

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

### Lesson

A Kubernetes node can successfully join EKS while still being unusable for workloads if the networking plugin cannot configure pod networking.

---

## 45. Troubleshooting — runAsNonRoot Failure

### Symptom

Application pod entered:

```text
CreateContainerConfigError
```

### Diagnosis

Events showed that Kubernetes could not verify that the image's named user was non-root while `runAsNonRoot` was enabled.

### Resolution

Determine the image's numeric UID:

```bash
docker run --rm secure-eks-demo:v1 id
```

Configure that UID using:

```yaml
runAsUser: <NON_ROOT_UID>
```

Keep:

```yaml
runAsNonRoot: true
```

Validate the manifest and redeploy.

### Lesson

Do not disable a security control merely because the container image metadata is ambiguous.

Make the runtime identity explicit.

---

## 46. Troubleshooting — Dangerous EKS Replacement Plan

### Symptom

Terraform proposed an EKS cluster replacement while enabling EKS Access Entries.

### Response

Do not apply.

### Diagnosis

Configuration values did not fully match the existing deployed cluster, including bootstrap-access and endpoint settings.

### Resolution

Preserve the existing cluster configuration while changing only the intended authentication mode.

Generate a new plan.

Apply only when the plan shows the intended in-place modification and no cluster destruction.

### Lesson

Terraform plan review is a security and availability control.

The plan is not merely a preview to click through.

---

## 47. Troubleshooting — Jenkins UI Timeout

### Symptom

Jenkins was active on the EC2 instance but the browser could not connect.

### Validation

Check:

```bash
systemctl status jenkins
ss -lntp
curl -I http://localhost:8080
```

Validate:

- Service health
- Listener
- Security group
- Route table
- Internet Gateway
- Network ACL

### Root Cause

The security group allowed a `/32` source address that did not match the browser's actual public IP.

### Resolution

Determine the browser's actual public IP and update the Terraform variable controlling the Jenkins administrator CIDR.

Apply only the security-group ingress change.

### Lesson

Do not solve source-IP mistakes by opening administrative services to the entire internet.

---

## 48. Troubleshooting — Jenkins Executor Offline

### Symptom

Pipeline displayed:

```text
Waiting for next available executor
```

### Diagnosis

The built-in Jenkins node was offline because `/tmp` free space was slightly below Jenkins' default temporary-space monitor threshold.

### Resolution

In Jenkins:

```text
Manage Jenkins
    -> Nodes
    -> Configure Monitors
    -> Free Temp Space
```

Set an appropriate threshold for the small portfolio controller.

The implementation used:

```text
256MiB
```

Do not disable the monitor.

### Lesson

Tune monitoring to the environment rather than removing monitoring controls when a threshold is inappropriate.

---

## 49. Troubleshooting — ECR DescribeRepositories AccessDenied

### Symptom

The Jenkins role received:

```text
AccessDenied
```

for:

```text
ecr:DescribeRepositories
```

### Diagnosis

The custom Jenkins IAM policy did not grant that diagnostic API.

### Decision

No permission was added.

The pipeline already knew the repository name and could construct the registry path using its AWS identity and region.

### Lesson

An AccessDenied result is not automatically a defect.

First determine whether the denied action is actually required by the workload.

---

## 50. Evidence Collection

Before teardown, capture evidence showing:

1. Architecture and Terraform design
2. Terraform state recovery and reconciliation
3. CNI failure and remediation
4. Healthy Kubernetes system state
5. Docker build and non-root execution
6. ECR image delivery
7. Pod Identity allowed access
8. Pod Identity denied access
9. Jenkins IAM-to-Kubernetes RBAC validation
10. Successful full Jenkins pipeline
11. Healthy deployed application
12. Runtime non-root identity and ServiceAccount
13. Final Terraform zero drift

Public screenshots must be sanitized.

Redact or avoid exposing:

- AWS account IDs
- Full ARNs containing account identifiers
- Instance IDs where unnecessary
- Public IP addresses
- Emails
- Credentials
- Jenkins bootstrap passwords
- Temporary AWS credentials
- Other environment-specific identifiers

Keep original screenshots privately as engineering evidence.

---

## 51. Public Repository Audit

Before final publication:

```bash
git status --short
git diff
git ls-files
```

Check for state and runtime artifacts:

```bash
git ls-files | grep -E \
'(\.tfstate|tfplan|terraform\.tfvars$|\.pem$|\.key$|\.env$)'
```

Expected:

```text
No output
```

Search tracked files for AWS access-key patterns:

```bash
git grep -nE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}' || true
```

Search for private-key markers:

```bash
git grep -n \
  'BEGIN.*PRIVATE KEY' || true
```

Search for 12-digit account-number patterns:

```bash
git grep -nE \
  '(^|[^0-9])[0-9]{12}([^0-9]|$)' || true
```

Review every result before publishing.

A safe example variable file may remain tracked.

The real `terraform.tfvars` must remain ignored.

---

## 52. Git Closeout

After documentation and security review:

```bash
git add README.md docs/SOP.md
git status
git diff --cached
```

Review the staged content.

Commit:

```bash
git commit -m "Document secure EKS platform implementation"
```

Push:

```bash
git push origin main
```

Verify:

```bash
git status
```

Expected:

```text
nothing to commit, working tree clean
```

---

## 53. Teardown Preparation

Do not destroy the environment until:

- Required screenshots are captured
- README is complete
- SOP is complete
- Git audit is complete
- GitHub is current
- Terraform state is intact
- Temporary Kubernetes validation resources are removed

Because EKS and EC2 incur ongoing cost, teardown should follow documentation closeout promptly.

---

## 54. Remove Temporary Kubernetes Resources

Check for temporary validation pods:

```bash
kubectl get pods
```

Delete only temporary test pods that are not part of the application deployment.

Do not delete resources merely because their purpose is unclear.

Confirm what each resource is first.

---

## 55. ECR Teardown Preparation

Because the ECR repository contains images, confirm whether Terraform is configured to delete a non-empty repository.

If not, list images:

```bash
aws ecr list-images \
  --repository-name secure-eks-dev-app \
  --region us-east-1
```

Delete application images before Terraform destroys the repository when required.

Do not delete the repository manually if Terraform is expected to manage its lifecycle unless necessary for a controlled destroy recovery.

---

## 56. Terraform Destroy

Move to the Terraform configuration:

```bash
cd terraform
```

Create and review a destroy plan:

```bash
terraform plan -destroy
```

Review the complete resource summary.

Ensure the destroy plan targets only the project environment.

Then execute:

```bash
terraform destroy
```

Review Terraform's final plan before confirming.

Do not delete Terraform state before successful teardown validation.

---

## 57. Post-Destroy Validation

After Terraform completes, verify that project resources no longer remain.

Check at minimum:

- EKS cluster
- EKS node group
- Jenkins EC2 instance
- Project ECR repository
- Project VPC resources
- Project IAM roles and policies
- Pod Identity resources
- Validation S3 resources

A post-destroy `terraform plan` may propose recreating resources because the configuration files still describe the desired environment.

That is expected after a successful destroy and does not mean teardown failed.

The relevant teardown question is whether the previously managed AWS resources still exist.

---

## 58. Final Engineering Standard

A cloud resource is not considered complete merely because it starts working.

The engineering sequence used for this project is:

```text
Build
  ->
Validate Functionality
  ->
Secure
  ->
Validate Security
  ->
Document Evidence
  ->
Tear Down
```

Security controls should be demonstrated through both intended success and intended denial wherever practical.

The objective is not to build the largest possible lab.

The objective is to build the smallest implementation that convincingly proves the business problem can be solved.
