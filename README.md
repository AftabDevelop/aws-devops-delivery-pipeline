# aws-devops-delivery-pipeline
“End-to-end DevOps pipeline on AWS: Terraform, Ansible, Jenkins, Docker, Argo CD, Prometheus and Grafana".
cat > README.md << 'EOF'
# AWS DevOps Delivery Pipeline

An end-to-end DevOps project on AWS, built step by step.

## Planned flow
Terraform (AWS infra) -> Ansible (server config) -> GitHub -> Jenkins (test, build, push image) -> Argo CD (deploy on Kubernetes) -> Prometheus + Grafana (monitoring)

## Status
- [x] Phase 1: Node.js app with /health and /metrics, Dockerfile, container run
- [ ] Phase 2: Terraform (EC2, Security Group)
- [ ] Phase 3: Ansible (Docker, k3s)
- [ ] Phase 4: Jenkins pipeline
- [ ] Phase 5: Argo CD
- [ ] Phase 6: Prometheus and Grafana

## Run the app locally with Docker
