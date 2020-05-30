#!/bin/bash

# Deploy Loki Stack (Loki, Fluent Bit, Grafana, Prometheus)
# https://github.com/grafana/loki/blob/master/docs/installation/helm.md

# add helm charts for loki
helm repo add loki https://grafana.github.io/loki/charts

# install with the default settings, no persistent volume 

helm upgrade --install loki loki/loki-stack \
    --set fluent-bit.enabled=true,promtail.enabled=false,grafana.enabled=true,prometheus.enabled=true,prometheus.alertmanager.persistentVolume.enabled=false,prometheus.server.persistentVolume.enabled=false


# add ingress for the new installation
kubectl crate -f /home/sam/src/work-raseedy/workspace/infrastructure/kubernetes/traefik/ingress-loki-grafana.yaml

