# Nginx Load balancer
The mainfest is modified to install Nginx as Daemonset and listen to host network on all the nodes, acting as HTTP/HTTPS load balancer for all backend services.

This setup is to overcome the limitation in kube-proxy that is not passing the source ip of a request to subsequent services, which limit the ability to do rate limiting opertions on the connected users or gather meaninful metrics about the customers and their behavior

