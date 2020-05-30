version=v1.5.5
clusterNamespace=cluster

help:		## Show this help.
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'


install-cluster-argocd:	## install Argocd cluster wide 
	kubectl create ns cluster || true
	kustomize edit set namespace cluster
	kustomize build --enable_alpha_plugins  ./base/argocd  | kubectl apply -f -

bootstrap-cluster-applications: ## install Argocd main bootstrap application
	kubectl apply -f install/cluster-bootstrap.yaml -n $clusterNamespace

download-argocd:	## ping all VMs in ibm cloud with root user
	kustomize build github.com/argoproj/argo-cd//manifests/cluster-install?ref=$version > ../base/argocd/argocd_$version.yaml


commons-ibm-all:	## install all required packages on all VMs, open-isci, iptables, ip utils
	ansible-playbook commons-playbook.yaml  -i inventory/hosts-ibm.yaml

wireguard-ibm-kube:	## isntall wireguard on all kube k3s servers
	# ./provision.sh
	ansible-playbook wireguard-playbook.yaml  -i inventory/hosts-ibm.yaml
