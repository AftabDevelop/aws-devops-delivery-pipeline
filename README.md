# AWS DevOps Delivery Pipeline

An end-to-end DevOps project on AWS, built step by step. A small Node.js app is containerized, and the infrastructure, configuration, CI/CD, deployment and monitoring are automated with Terraform, Ansible, Jenkins, Argo CD, Prometheus and Grafana.

## Planned flow

```
Terraform (AWS infra) -> Ansible (server config) -> GitHub -> Jenkins (test, build, push image) -> Argo CD (deploy on Kubernetes) -> Prometheus + Grafana (monitoring)
```

## Status

- [x] Phase 1: Node.js app with /health and /metrics, Dockerfile, container run
- [x] Phase 2: Terraform (key pair, security group, EC2 server for k3s)
- [x] Phase 3: Ansible (Docker and k3s on the new server)
- [x] Phase 4: Jenkins pipeline (build, smoke test, push image to Docker Hub)
- [ ] Phase 5: Argo CD
- [ ] Phase 6: Prometheus and Grafana

## Repository structure

```
.
├── app/          Node.js app and Dockerfile
├── terraform/    Infrastructure as Code (AWS)
├── ansible/      Server configuration (inventory and playbooks)
├── Jenkinsfile   CI pipeline
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

## Notes

- The Terraform state file (`terraform.tfstate`) and the `.terraform/` folder are not committed (see `.gitignore`).
- No passwords, access keys, tokens or private keys are stored in this repository.
