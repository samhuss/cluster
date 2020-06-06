# Traefik as LoadBalancer
Traefik will be installed as load balancer by deploying as Daemonset and listening to ports 80/443 on the host.

Traefik deployment is simple, have more control over Nginx. using `NET_BIND_SERVICE` allows Traefik to listen to host ports