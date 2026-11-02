# AWS DevOps Delivery Pipeline

An end-to-end DevOps project on AWS, built step by step. A small Node.js app is containerized, and the infrastructure, configuration, CI, GitOps deployment and monitoring are automated with Terraform, Ansible, Jenkins, Argo CD, Prometheus and Grafana.

## Flow

```
Terraform (AWS infra) -> Ansible (server config) -> GitHub -> Jenkins (test, build, push image) -> Argo CD (deploy on Kubernetes) -> Prometheus + Grafana (monitoring)
```

## Status

- [x] Phase 1: Node.js app with /health and /metrics, Dockerfile, container run
- [x] Phase 2: Terraform (key pair, security group, EC2 server for k3s)
- [x] Phase 3: Ansible (Docker and k3s on the new server)
- [x] Phase 4: Jenkins pipeline (build, smoke test, push image to Docker Hub)
- [x] Phase 5: Argo CD (GitOps deployment on k3s)
- [x] Phase 6: Prometheus and Grafana (monitoring)

## Repository structure

```
.
├── app/            Node.js app and Dockerfile
├── terraform/      Infrastructure as Code (AWS)
├── ansible/        Server configuration (inventory and playbooks)
├── k8s/            Kubernetes manifests (Deployment, Service, ServiceMonitor)
├── argocd/         Argo CD Applications (app and monitoring stack)
├── Jenkinsfile     CI pipeline
└── README.md
```

## Phase 1: Run the app with Docker

The app exposes three endpoints: `/` (hello message), `/health` (status) and `/metrics` (Prometheus metrics).

```
cd app
docker build -t devops-app:v1 .
docker run -d --name devops-app -p 3000:3000 devops-app:v1
curl localhost:3000/health
```

## Phase 2: Infrastructure with Terraform

Terraform creates the following in `ap-south-1` (Mumbai):

- A key pair (public key of the SSH key created on the control machine)
- A security group that allows SSH only from inside the VPC
- An Amazon Linux 2023 EC2 instance, which runs k3s (lightweight Kubernetes)

Terraform runs from a control EC2 instance that uses an IAM role (`AmazonEC2FullAccess`), so no access keys are stored anywhere.

```
cd terraform
terraform init
terraform plan
terraform apply
```

To remove everything that Terraform created:

```
terraform destroy
```

## Phase 3: Server configuration with Ansible

Ansible runs from the control machine and configures the new server over SSH (agentless). The inventory lists the server, and two playbooks do the work:

- `docker.yml`: installs Git and Docker, starts and enables the Docker service, and adds `ec2-user` to the docker group
- `k3s.yml`: downloads the k3s installer, installs k3s, and waits until the node is `Ready`

```
cd ansible
ansible -i inventory.ini k3s -m ping
ansible-playbook -i inventory.ini docker.yml
ansible-playbook -i inventory.ini k3s.yml
```

Both playbooks are idempotent. Running them a second time reports `changed=0`, because Ansible checks the current state of the server first and only changes what is missing.

Result: a single-node k3s cluster with CoreDNS, Traefik, metrics-server and local-path-provisioner running.

## Phase 4: CI with Jenkins

Jenkins runs on the control machine and builds the pipeline from the `Jenkinsfile` in this repository (Pipeline script from SCM). The Jenkins UI is reached through an SSH tunnel, so port 8080 is not exposed to the internet.

Pipeline stages:

1. **Checkout**: pulls the code from GitHub
2. **Build Docker image**: builds the image from `app/`
3. **Smoke test**: runs the container and calls `/health`; the pipeline fails if it does not respond
4. **Push to Docker Hub**: pushes the image tagged with the build number and `latest`

The Docker Hub access token is stored in the Jenkins credential store and is never written in the code. The pipeline logs out of Docker Hub at the end of every run.

Result: [`aftab710/devops-app`](https://hub.docker.com/r/aftab710/devops-app) on Docker Hub, with the build number tag and `latest` pointing to the same image.

## Phase 5: GitOps deployment with Argo CD

Argo CD runs on the k3s cluster and keeps the cluster in sync with this repository.

- `k8s/deployment.yaml`: Deployment with replicas, readiness and liveness probes on `/health`, and CPU and memory requests and limits. The image is pinned to a tag (not `latest`), so Git always shows exactly which version is running.
- `k8s/service.yaml`: NodePort Service in front of the pods.
- `argocd/application.yaml`: Argo CD Application that watches the `k8s/` folder on the `main` branch, with automated sync, prune and self-heal.

```
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd/application.yaml
kubectl get applications -n argocd
```

Verified behaviour:

- Changing replicas in Git (2 to 3) is applied to the cluster automatically.
- Scaling the Deployment by hand (to 5 replicas) is reverted by Argo CD within seconds (self-heal).
- The application reports `Synced` and `Healthy`.

## Phase 6: Monitoring with Prometheus and Grafana

The monitoring stack is also deployed through Argo CD, as a Helm chart.

- `argocd/monitoring.yaml`: Argo CD Application for the `kube-prometheus-stack` Helm chart (version pinned). The Helm values are kept in Git: Alertmanager is disabled, retention is 24 hours, Prometheus has a memory limit, and the control plane components that k3s does not expose (controller manager, scheduler, kube-proxy, etcd) are turned off.
- `k8s/servicemonitor.yaml`: tells Prometheus to scrape `/metrics` from the app every 15 seconds. The Service has a matching label and a named port.

```
kubectl apply -f argocd/application.yaml
kubectl apply -f argocd/monitoring.yaml
kubectl get pods -n monitoring
```

Grafana is not exposed to the internet. It is reached through SSH tunnels (laptop to control machine to k3s server) and `kubectl port-forward`.

Verified behaviour:

- Prometheus reports `up == 1` for all three app pods (`up{job="devops-app"}`).
- The custom metric `http_requests_total` is visible in Grafana, for example with `sum(rate(http_requests_total{job="devops-app"}[1m])) by (route)`.
- The request rate on `/health` is about 0.9 requests per second, which comes from the Kubernetes probes of the three pods. The rate on `/metrics` is about 0.2 requests per second, which is the Prometheus scrape interval.
- Each pod uses roughly 25 MB of memory and about 0.003 CPU cores.

## Limitations and next steps

- The image tag in `k8s/deployment.yaml` is updated by hand after a Jenkins build. A next step is to let Jenkins update the tag in Git, so CI and CD form one loop.
- The Grafana dashboard was built in the Grafana UI and is not stored in Git yet. It can be provisioned from a ConfigMap.
- The k3s server (4 GiB RAM) is tight with Argo CD and the monitoring stack together. A larger instance type can be set in Terraform.
- The Terraform state is local to the control machine. A remote state in S3 would be safer.

## Notes

- The Terraform state file (`terraform.tfstate`) and the `.terraform/` folder are not committed (see `.gitignore`).
- No passwords, access keys, tokens or private keys are stored in this repository.
