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
	@brew install age
	@brew install sops
	@brew install argocd
	@brew install minikube
	@brew install act

minikube:  ## Start/Stop/Delete minikube. action=start|stop|delete cpus=[0-9] memory=[0-9]g
ifeq ("$(action)", "start")
	@sudo chmod 666 /var/run/docker.sock && minikube start \
		--cpus $(if $(cpus), $(cpus), 4) --memory $(if $(memory), $(memory), 8g) --driver docker --container-runtime containerd --cni bridge

else ifeq ("$(action)", "stop")
	@minikube stop

else ifeq ("$(action)", "delete")
	@minikube delete

else
	@echo "==== Action not found"
endif

minikube-dashboard:  ## Start minikube dashboard
	@minikube dashboard --url false

minikube-tunnel:  ## Start minikube tunnel
	@minikube tunnel

argocd: -B  ## Install/Uninstall argocd. action=install|uninstall
ifeq ("$(action)", "install")
	@kubectl apply -f ArgoCD/namespace.yaml

	@wget https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -O ArgoCD/dashboard.yaml && \
	  kubectl apply -n argocd -f ArgoCD/dashboard.yaml

	@echo
	@echo "==== Wait until all pods are up before run age-secrets"

else ifeq ("$(action)", "uninstall")
	@kubectl delete -n argocd -f ArgoCD/dashboard.yaml && \
	  kubectl delete -f ArgoCD/namespace.yaml

else
	@echo "==== Action not found"
endif

age-secrets:  ## Create and export age secrets. complete=true (default: false)
ifeq ("$(complete)", "true")
	@age-keygen -o sops-age.txt

endif

	@cat sops-age.txt |
	  kubectl create secret generic sops-age --namespace=argocd --from-file=sops-age.txt=/dev/stdin

	@echo
	@echo "==== Ready to run argocd-patches"

argocd-patches:  ## Apply custom confs to argocd
	@kubectl apply -n argocd -f ArgoCD/configmap.yaml
	@kubectl apply -n argocd -f ArgoCD/roles.yaml

	@kubectl patch deployment argocd-repo-server -n argocd \
	  --patch-file ArgoCD/deployment-age.yaml

	@kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

	@echo
	@echo "==== Wait until all pods are up before continue"

argocd-token:  ## Show argocd login token
	@kubectl get secret argocd-initial-admin-secret \
	  -n argocd -o jsonpath="{.data.password}" | base64 -d; echo

argocd-login:  ## Login to argocd. Requires minikube-tunnel
	@argocd login localhost

argocd-password:  ## Change argocd login password
	@argocd account update-password

argocd-cluster:  ## Apply argocd cluster
	@argocd cluster add "$$(kubectl config get-contexts -o name)" --in-cluster

namespaces:  ## Install/Uninstall staging and production namespaces. action=install|uninstall
ifeq ("$(action)", "install")
	@kubectl apply -f Apps/namespaces.yaml

else ifeq ("$(action)", "uninstall")
	@kubectl delete -f Apps/namespaces.yaml

else
	@echo "==== Action not found"
endif


%:
	@:
