.ONESHELL:

SHELL=/bin/bash
PYTHON=/usr/bin/python3


define HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
	match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
	if match:
		target, help = match.groups()
		print("	%-20s %s" % (target, help))
endef
export HELP_PYSCRIPT


help:
	@echo Commands:
	@$(PYTHON) -c "$$HELP_PYSCRIPT" < $(MAKEFILE_LIST)


brew:  ## Install/Uninstall brew package manager. action=install|uninstall
ifeq ("$(action)", "install")
	@sudo apt update && \
	  sudo apt install build-essential curl file git

	@/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)" && \
	  echo -e '\neval $$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)' >> ~/.profile

	@echo "==== Now run the following command: " && \
	  echo "source ~/.profile && make dependencies"

else ifeq ("$(action)", "uninstall")
	@/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall.sh)" && \
	  sed -i '/linuxbrew/d'

	@echo "==== Now run the following command:" && \
	  echo "source /etc/environment"

else
	@echo "==== Action not found"
endif

dependencies:  ## Install dependencies
	@brew install sops
	@brew install argocd
	@brew install minikube
	@brew install act

minikube:  ## Start/Stop minikube. action=start|stop
ifeq ("$(action)", "start")
	@sudo chmod 666 /var/run/docker.sock && \
	  minikube start --cpus 4 --memory 8g --driver docker --container-runtime containerd --cni bridge

else ifeq ("$(action)", "stop")
	@minikube stop
else
	@echo "==== Action not found"
endif

minikube-dashboard:  ## Start minikube dashboard
	@minikube dashboard

minikube-tunnel:  ## Start minikube tunnel
	@minikube tunnel

minikube-delete:  ## Delete minikube
	@minikube stop

argocd: -B  ## Install/Uninstall argocd. action=install|uninstall
ifeq ("$(action)", "install")
	@kubectl apply -f ArgoCD/namespace.yaml

	@wget https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -O ArgoCD/dashboard.yaml && \
	  kubectl apply -n argocd -f ArgoCD/dashboard.yaml

	@echo
	@echo "==== Wait until all pods are up before run gpg-secrets"

else ifeq ("$(action)", "uninstall")
	@kubectl delete -n argocd -f ArgoCD/dashboard.yaml && \
	  kubectl delete -f ArgoCD/namespace.yaml

else
	@echo "==== Action not found"
endif

gpg-secrets:  ## Create and export gpg secrets.
	@GPG_NAME="$$(kubectl config get-contexts -o name)"
	@GPG_COMMENT="gpg secrets"

	@gpg --batch --full-generate-key << EOF
	%no-protection
	Key-Type: 1
	Key-Length: 4096
	Subkey-Type: 1
	Subkey-Length: 4096
	Expire-Date: 0
	Name-Real: $$GPG_NAME
	Name-Comment: $$GPG_COMMENT
	Name-Email: rempel.oliveira@gmail.com
	EOF

	@GPG_ID="$$(gpg --list-secret-keys $$(kubectl config get-contexts -o name) | sed -n 2p | xargs)"

	@gpg --export-secret-keys --armor $$GPG_ID |
	  kubectl create secret generic sops-gpg --namespace=argocd --from-file=sops.asc=/dev/stdin

	@echo
	@echo "==== Ready to run argocd-patches"

argocd-patches:  ## Apply custom confs to argocd
	@kubectl apply -n argocd -f ArgoCD/configmap.yaml && \
	  kubectl apply -n argocd -f ArgoCD/roles.yaml

	@kubectl patch deployment argocd-repo-server \
	  -n argocd --patch-file ArgoCD/deployment-gpg.yaml

	@kubectl patch svc argocd-server \
	  -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

argocd-token:  ## Show argocd login token
	@kubectl get secret argocd-initial-admin-secret \
	  -n argocd -o jsonpath="{.data.password}" | base64 -d; echo

argocd-login:  ## Login to argocd. Requires minikube-tunnel
	@argocd login localhost

argocd-password:  ## Change argocd login password
	@argocd account update-password

argocd-cluster:  ## Apply argocd cluster
	@argocd cluster add "$$(kubectl config get-contexts -o name)" --in-cluster

app-namespaces:  ## Create staging and production app namespaces
	@kubectl apply -f Apps/namespaces.yaml


%:
	@:
