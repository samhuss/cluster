# Argocd installation manifest
This repo is for installing argo-cd as cluster wide operator that manages the whole cluster setup

## Source yaml files
The installation script is pulled using the script file in `$ROOT/scripts/argocd-pull.sh` to be downloaded under `$ROOT/base/argocd/argocd.yaml`

## Patches
To override the some default settings in the installation scripts, the file `argocd-patches.yaml` contains the following updates:
1. Set a pre-defined password hash for password known by Raseedy admins only. argocd-secret
2. Enable usage of ksops plugin that encrypts passwords in Git repos using a key configured in Azure KMS. argocd-cm

