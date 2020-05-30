#!/bin/bash



execute() {
    cmd=$command
    FLUENT_ELASTICSEARCH_HOST=demo-coordinating-only
    FLUENT_ELASTICSEARCH_PORT=9200

    kubectl $cmd namespace logging
    kubens logging

    kubectl $cmd -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-service-account.yaml
    kubectl $cmd -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role.yaml
    kubectl $cmd -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role-binding.yaml

    # kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-configmap.yaml
    kubectl $cmd -f ./fluent-bit-configmap.yaml
    # kubectl $cmd -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-ds.yaml
    cat ./fluent-bit-ds.yaml | kubectl $cmd -f -
}




command=$1
echo "command $command"

# [ $command ]  || echo "yuo didn't define command, command can be 'create' or 'delete'"  #&& exit 1


case $command in
"apply" | "delete")
    echo "executing command: $command"
    execute $command
;;
*)
echo "you didn't select create or delete"
exit 1
;;

esac






