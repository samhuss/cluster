#!/bin/bash

install(){
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
}

getArgocdPodName(){
    kubectl get pod -n argocd -l app.kubernetes.io/name=argocd-server
}

getArgoAdminPassword(){
    echo "Getting password hash from argocd-secret secret"
    kubectl get secret -n argocd argocd-secret -o yaml | awk '/admin.password:/{print $2}' | base64 -d 
    echo ""
}

changePasswrd(){


if [ -z "$1" ]; then 
    echo  "Usage: Password hash is required as first parameter" 
    return
fi

echo "Setting Admin password hash for Argocd admin user: $1"
# $2a$10$by8MS08UizikPE6jVBPDGOtqfEJRVcv7Y5FSVEYwb5GnOhj7ttj4a
kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "$2a$10$by8MS08UizikPE6jVBPDGOtqfEJRVcv7Y5FSVEYwb5GnOhj7ttj4a",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'

}

# download latest version of argocd kubernetes yaml files
download() {
    curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml -o ../base/argocd/argocd.yaml
}

# build and download using kustomize
build(){
    version=v1.5.5
    kustomize build github.com/argoproj/argo-cd//manifests/cluster-install?ref=$version > ../base/argocd/argocd_$version.yaml 
}

build
