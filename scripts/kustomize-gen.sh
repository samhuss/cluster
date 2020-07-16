#!/bin/sh

from=$1
to=$2
appsName=$3

repo=${4:-$repo}  # get 4th parameter or use exported variable 'repo' from environment variables

env=${5:-"dev"}

if [ ! "$repo" ]; then
  echo "docker registry is not defined, should be passed as 4th parameter"
  exit 1
fi 


printf "generating kustomze files \nFrom directory: $from\nTo directory: $to\nUsing dockekr registry: $repo\nApplications Name: $appsName\n"

cd $from


ingPort=80
svcPort=8080
svcVersion=${svcVersion:-"0.1"}
# env=${env:-"dev"}
envInPath=${envInPath:-"$env."}
tag=0.1

base=$to/base/$appsName
overlay=$to/$env/$appsName
# apiUrls="api.dev.raseedy.io api.stg.raseedy.io"
repo="reg.dev.raseedy.io"

deploymentTmp='apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: {svc}
  name: {svc}
spec:
  selector:
    matchLabels:
      app: {svc}
  revisionHistoryLimit: 11
  minReadySeconds: 0
  template:
    metadata:
      labels:
        app: {svc}
    spec:
      # serviceAccountName: dev
      hostAliases:
      - ip: "10.232.16.116"
        hostnames:
        - "wmsvc-mobile123"
      containers:
      - name: {svc}
        image: {repo}/{svcImage}:{svcVersion}
        env:
        - name: service_name
          value: {svc}
        # --generated env
        ##env##
        # --end generated env
        volumeMounts:
        - name: {svc}-config-volume
          mountPath: "/app/config"
      volumes:
      - name: {svc}-config-volume
        configMap:
          name: {svc}
          items:
          - key: application.properties
            path: application.properties

---
apiVersion: v1
kind: Service
metadata:
  name: {svc}
spec:
  type: ClusterIP
  ports:
    - port: {ingPort}
      targetPort: {svcPort}
      protocol: TCP
  selector:
    app: {svc}
---
'

# variables {svc}, {env [dev,stg]}
ingressTmpl='apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: ingress-{svc}
  namespace: default
  annotations:
    konghq.com/protocols: "https"
    konghq.com/strip-path: "true"
    # konghq.com/plugins: keyauth
    # konghq.com/plugins: oidc-dev
    env: "{env}"
    ##annotations##
spec:
  rules:
  - host: api.{envInPath}raseedy.io
    http:
      paths:
      - path: /{svc}
        backend:
          serviceName: {svc}
          servicePort: 8080
  tls:
  - hosts:
    - "api.{envInPath}raseedy.io"
'

ingressInternalTmpl='apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: ingress-internal-{svc}
  namespace: default
  annotations:
    konghq.com/protocols: "https"
    konghq.com/strip-path: "false"
    # konghq.com/plugins: keyauth
    # konghq.com/plugins: oidc-dev
    env: "{env}"
    ##annotations##
spec:
  rules:
  - http:
      paths:
      - path: /{appName}
        backend:
          serviceName: {svc}
          servicePort: 8080
  tls:
  - hosts:
    - "api.{envInPath}raseedy.io"
'

envTmpl='
        - name: #name#
          value: "#value#"'

svcKustomization='apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default


resources:
- deployment.yaml

#resources#

configMapGenerator:
- name: {svc}
  files:
  - application.properties
'


envKustomization='apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

nameSuffix: {nameSuffix}
namePrefix: {namePrefix}

bases:
#bases#

resources:
#ingresses#
#ingressesInternal#

images:
#images#
'
imageTmpl='
  - name: {image}
    newTag: {tag}
'

# variables to be filled dynamically and pushed to kustomization.yaml with only the generated files
bases=""
ingresses=""
ingressesInternal=""


createServicesDir(){
    mkdir -p $overlay 2>/dev/null
    mkdir -p $base 2>/dev/null

    services=`grep -lE 'service.deploy=true' ./**/.env | cut -d '/' -f2 2>/dev/null`
    # services=`grep -lE 'service.deploy=true' ./**/.env`
    # echo "found services: $services"
    for svc in $services; do
        echo "service: $svc"
        # echo "${svc#env#}" 
        createDeploymentFiles $svc 
        bases="- ../../base/$appsName/$svc \n${bases}"
        ingresses="- ingress-${svc}-${env}.yaml \n${ingresses}"
    done

    # createEnvCustomization 
    createEnvCustomizationFromRegistry
}

# create kustomization.yaml file for dev environment out of latest known built containers
createEnvCustomizationFromRegistry(){
  
  services=`grep -lE 'service.deploy=true' ./**/.env | cut -d '/' -f2 2>/dev/null`

  for svc in $services; do

    url="https://$repo/v2/$svc/tags/list"
    echo "calling container rgistry with: $url"
    result=`curl -s $url`
    echo "returned result: $result"
    # example result: {"name":"raseedy-scheme-online-transaction","tags":["0.9","0.11","0.7","0.10","0.8","0.6","0.5","0.12","0.13"]}
    # get tags numbers, remove double quote and, replace ',' by new line, sort by fields from 1 to 4.
    # sorting by field is important to get the right sort with precision. field delimiter is '.' defined by -t. 
    # fields to be sorted are -k1,1, means field 1 to 1, field 2 to 2, etc..
    if [ ! "$result"]; then
      echo "Error: No container found for service $svc"
      echo "continue with next service"
      continue
    fi

    sortedTags=`echo $result | sed -r "s/.*\[(.*)]}/\1/g;s/\"//g" | tr , '\n' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n`
    # tagsCount=`echo $sortedTags | wc -l`
    # echo "sorted tags: $sortedTags"

    # get last built container tag like: 0.13
    tag=`printf "$sortedTags" | tail -1` 

    echo "latest built image tag: $svc :: $tag"

    # tag=`printf "$allTags" | grep $svc | head -1 `
    # tag=${tag##*/}
    # echo "$svc : tag ==> $tag"

    image=`printf "$imageTmpl" | sed "s/{image}/$repo\/$svc/g;s/{tag}/\"$tag\"/g"`
    images="${image}${images}"
  done

  # print all found images 

  echo "images: $images"

  kustomization=${envKustomization//#bases#/$bases}
  kustomization=${kustomization//#ingresses#/$ingresses}
  kustomization=${kustomization//#ingressesInternal#/$ingressesInternal}
  kustomization=${kustomization//#images#/$images}
  # printf "$kustomization" 
  echo "to path: $to"
  # printf "$kustomization" | sed "s/{namePrefix}/\"\"/g;s/{nameSuffix}/-${env}/g" | tee $overlay/kustomization.yaml
  printf "$kustomization" | sed "s/{namePrefix}/\"\"/g;s/{nameSuffix}/\"\"/g" | tee $overlay/kustomization.yaml
}

createEnvCustomization(){
    # create environment directory, first time
    # envDir=$to/overlay/$env
    mkdir -p $overlay 2>/dev/null

    # printf "\n\nBases\n$bases"
    # kustomization=""
    # get all git tags from source project
    # git -C $from pull --tags
    allTags=`git -C $from tag -l --sort=-version:refname`
    echo "all tags: $allTags"

    images=""
    for svc in $services; do
        tag=`printf "$allTags" | grep $svc | head -1 `
        tag=${tag##*/}
        echo "$svc : tag ==> $tag"

        image=`printf "$imageTmpl" | sed "s/{image}/$repo\/$svc/g;s/{tag}/\"$tag\"/g"`
        images="${image}${images}"
    done



    echo "images: $images"

    kustomization=${envKustomization//#bases#/$bases}
    kustomization=${kustomization//#ingresses#/$ingresses}
    kustomization=${kustomization//#ingressesInternal#/$ingressesInternal}
    kustomization=${kustomization//#images#/$images}
    # printf "$kustomization" 
    echo "to path: $to"
    # printf "$kustomization" | sed "s/{namePrefix}/\"\"/g;s/{nameSuffix}/-${env}/g" | tee $overlay/kustomization.yaml
    printf "$kustomization" | sed "s/{namePrefix}/\"\"/g;s/{nameSuffix}/\"\"/g" | tee $overlay/kustomization.yaml

    
}


createDeploymentFiles(){
    svcDir=$1
    svc=${1//\./-}
    # sv=${svc//\./-}  #replace all '.' with '-' 
    newEnv="" 
    allEnv=""

    echo "generating folder for service: $svc"
    mkdir -p $base/$svc 2>/dev/null

    # generate environment variables from every line in .env that starts with var.
    envVars=`grep -E "^env." $from/$svcDir/.env | sed 's/env.//g'`
    echo "found environment variables: $envVars"
    for var in $envVars; do
        # name=; value=
        newEnv=${envTmpl//#name#/${var%=*}}; newEnv=${newEnv//#value#/${var#*=}}
        # newEnv=`printf "$envTmpl" | sed "s/{name}/$name/g;s/{value}/$value/g"`
        allEnv="${allEnv} ${newEnv}"
    done

    # generate environment variables from specific environment like dev,stg,prod from every line in .env that starts with $env.var
    envVars=`grep -E "^$env.env." $from/$svcDir/.env | sed "s/${env}.env.//g"`
    echo "found environment variables for $env environment: $envVars"
    for var in $envVars; do
        # name=; value=
        newEnv=${envTmpl//#name#/${var%=*}}; newEnv=${newEnv//#value#/${var#*=}}
        # newEnv=`printf "$envTmpl" | sed "s/{name}/$name/g;s/{value}/$value/g"`
        allEnv="${allEnv} ${newEnv}"
    done
    # generate all secrets
    # for var in { 1..3 }; do
    #     newEnv=`printf "$envTmpl" | sed "s/{name}/variable-name/;s/{value}/value-here/"`
    #     allEnv="${allEnv}  ${newEnv}"
    # done

    # printf "$allEnv"

    #service target directory
    local target=$base/$svc

    # create deployment yaml

    # substitute single variables 
    deployment=`printf "$deploymentTmp" | sed "s/{svc}/$svc/g;s/{ingPort}/$ingPort/g;s/{svcPort}/$svcPort/g;s/{env}/$env/g;s/{svcVersion}/${svcVersion}/g;s/{repo}/$repo/g;s/{svcImage}/$svcDir/"`
    # substitute multi line variables

    deployment=`printf "${deployment//##env##/$allEnv}"`
    # printf "$deployment" | tee $target/deployment.yaml
    printf "$deployment" > $target/deployment.yaml

    # generate ingress, read required variables from application.properties 
    # contextPath=`grep -E 'context-path' $from/**/application.properties` 

    echo "context path: ${svc}"
    ingress=`printf "$ingressTmpl" | sed "s/{svc}/$svc/g;s/{envInPath}/$envInPath/g;s/{env}/$env/g"`
    # printf "$ingress" | tee $overlay/ingress-${svc}-${env}.yaml
    printf "$ingress" > $overlay/ingress-${svc}-${env}.yaml

    # search for applicationName in application.properties, if found, then create internal ingress with context /<applicaitonName>
    # no host defined, default tls will be used 

    appName=`grep -E 'application.name=' $from/$svcDir/src/main/resources/application.properties | sed 's/env.//g'`
    appName=${appName#*=}

    echo "found application.name, generating internal ingress to be called without host "
    echo "service: $svc : /$appName"
    if [ "$appName" ]; then
        ingressInternal=`printf "$ingressInternalTmpl" | sed "s/{svc}/$svc/g;s/{envInPath}/$envInPath/g;s/{env}/$env/g;s/{appName}/$appName/g"`
        ingressesInternal="- ingress-internal-${svc}-${env}.yaml \n${ingressesInternal}"
        # printf "$ingressInternal" | tee $overlay/ingress-internal-${svc}-${env}.yaml
        printf "$ingressInternal" > $overlay/ingress-internal-${svc}-${env}.yaml
    fi


    # generate application.properties for config map
    properties=`grep -E '^prop.' $from/$svcDir/.env | sed 's/prop.//g'`
    echo ""
    echo "found properties: "
    printf "$properties" | tee $target/application.properties

    # generate kustomization for this service

    # kustomize=`printf "$kustomization | sed "s/{env}/$env/g"`
    printf "$svcKustomization" | sed "s/{namePrefix}/\"\"/g;s/{svc}/$svc/g" | tee $target/kustomization.yaml

    # mkdir -p $target 2>/dev/null


}

commitChanges(){
  echo "submitting changes to CD repo"
  current=`git -C $from log --tags --simplify-by-decoration --pretty='format:%ai %d' | head -1`
  msg="ci-cd workflow update::Apps: ${appsName}, for commit: $current"
  cd $to
  git add . 
  git -c user.name='argo-ci-cd-workflow' -c user.email='shussein@raseedyapp.com' commit -am "$msg" 
  git push

}

# git -C $from pull --tags

createServicesDir
commitChanges
