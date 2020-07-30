#!/bin/sh

from=$1
to=$2
appsName=$3
repo=${4:-$repo}  # get 4th parameter or use exported variable 'repo' from environment variables
env=${5:-"dev"}

# nameSuffix="-$env"
nameSuffix=""
namePrefix=""
# namePrefix="$env-"
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
    app: {svcLabel}
  name: {svc}
spec:
  selector:
    matchLabels:
      app: {svcLabel}
  revisionHistoryLimit: 11
  minReadySeconds: 0
  template:
    metadata:
      labels:
        app: {svcLabel}
    spec:
      # serviceAccountName: {saName}
      hostAliases:
      - ip: "10.232.16.116"
        hostnames:
        - "wmsvc-mobile123"
      containers:
      - name: {svc}
        image: {repo}/{svcImage}:{svcVersion}
        env:
        - name: service_name
          value: {svcLabel}
        ##env##
        #volumeMounts#
      #volumes#
        #javaVolumes#

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
  labels:
    app: {svcLabel}
spec:
  type: ClusterIP
  ports:
    - port: {ingPort}
      targetPort: {svcPort}
      protocol: TCP
  selector:
    app: {svcLabel}
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
    ##annotations##
  labels:
    app: {svcLabel}
    type: ingressExternal
spec:
  rules:
  - http:
      paths:
      - path: /{svc}
        backend:
          serviceName: {svcLabel}
          servicePort: 8080
    #host: api.{envInPath}raseedy.io

  # tls:
  # - hosts:
  #   - "api.{envInPath}raseedy.io"
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
    ##annotations##
  labels:
    app: {svcLabel}
    type: ingressInternal
spec:
  rules:
  - http:
      paths:
      - path: /{appName}
        backend:
          serviceName: {svcLabel}
          servicePort: 8080
  #tls:
  #- hosts:
  #  - "api.{envInPath}raseedy.io"
'

javaVolumesTmpl='
        volumeMounts:
        - name: {svc}-config-volume
          mountPath: "/app/config"
      volumes:
      - name: {svc}-config-volume
        configMap:
          name: {svc}
          items:
          - key: application.properties
            path: application.properties'

envTmpl='
        - name: #name#
          value: "#value#"'

volumeMountsTmpl='
        volumeMounts:
        #mountsList#'
volumeMountTmpl='
        - name: {name}
          mountPath: {path}

volumesTmpl='
      volumes:
      #volumeList#'

volumeTmple='
      - name: {name}
        configMap:
          name: {cmName}
          items:
          - key: {key}
            path: {path}
      '

svcKustomization='apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

resources:
- deployment.yaml
#resources#
#ingresses#


configMapGenerator:
- name: {svc}
  files:
  - application.properties
'

envKustomization='apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: {env}

nameSuffix: {nameSuffix}
namePrefix: {namePrefix}

bases:
#bases#

patches:
- path: ingress-patch.yaml
  target:
    kind: Ingress
    labelSelector: type=ingressExternal

commonLabels:
  env: {env}

images:
#images#
'

envIngressPatch='# patch ingress files 
- op: replace
  path: /spec/rules/0/host
  value: "api.{env}.raseedy.io"

- op: add
  path: /spec/tls
  value:
  - hosts:
    - api.{env}.raseedy.io 
'

imageTmpl='
  - name: {image}
    newTag: {tag}
'


# variables to be filled dynamically and pushed to kustomization.yaml with only the generated files
bases=""
ingresses=""
ingressesInternal=""


# service directory is created under the target environment folder, dev, stg, and prod
createServicesDir(){

    mkdir -p $overlay 2>/dev/null
    mkdir -p $base 2>/dev/null

    services=`grep -lE 'service.deploy=true' ./**/.env | cut -d '/' -f2 2>/dev/null`
    # services=`grep -lE 'service.deploy=true' ./**/.env`
    # echo "found services: $services"
    for svc in $services; do
        echo "service: $svc"
        # svc="$namePrefix$svc$nameSuffix"
        # echo "${svc#env#}" 
        createDeploymentFiles $svc 
        bases="- ../../base/$appsName/$svc \n${bases}"
        # ingresses="- ingress-${svc}-${env}.yaml \n${ingresses}"
    done

    # createEnvCustomization 
    createEnvCustomizationFromRegistry
}

# create kustomization.yaml file for dev environment out of latest known built containers
createEnvCustomizationFromRegistry(){
  
  services=`grep -lE '^service.deploy=true' ./**/.env | cut -d '/' -f2 2>/dev/null`

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

  # kustomization=${envKustomization//#bases#/$bases}
  kustomization=${envKustomization//#bases#/$bases}
  # kustomization=${kustomization//#ingresses#/$ingresses}
  # kustomization=${kustomization//#ingressesInternal#/$ingressesInternal}
  kustomization=${kustomization//#images#/$images}
  # printf "$kustomization" 
  echo "to path: $to"
  printf "$kustomization" | sed "s/{namePrefix}/\"${namePrefix}\"/g;s/{nameSuffix}/\"${nameSuffix}\"/g;s/{env}/${env}/g" | tee $overlay/kustomization.yaml

  # print patch file
  printf "$envIngressPatch" | sed "s/{envInPath}/$envInPath/g;s/{env}/$env/g" > $overlay/ingress-patch.yaml

  # printf "$kustomization" | sed "s/{namePrefix}/\"\"/g;s/{nameSuffix}/-${env}/g" | tee $overlay/kustomization.yaml
  # printf "$kustomization" | sed "s/{namePrefix}/\"\"/g;s/{nameSuffix}/\"\"/g" | tee $overlay/kustomization.yaml
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

# create deployment files per environment for each service. Service target directory: $env/$svc 
createDeploymentFiles(){
    svcDir=$1
    # replace all '.' by '-', workaround for the project names with dots in Core repo
    # replace all '_' by '-', workaround for the project names with dots, nodejs prjects, bff
    svc=${1//\./-}
    svc=${svc//_/-}

    # used in ingress::path:: /$svcContext
    svcContext=$svc
    # used in all names
    svcLabel=$namePrefix$svc$nameSuffix

    # sv=${svc//\./-}  #replace all '.' with '-' 
    newEnv="" 
    allEnv=""
    local ingresses=""


    echo "generating folder for service: $svc under environment $env"
    # mkdir -p $base/$svc 2>/dev/null
    # local target=$overlay/$svc
    local target=$base/$svc
    mkdir -p $target 2>/dev/null
    # target variable is shortcut for all outputs 

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


    # create deployment yaml

    # substitute single variables 
    deployment=`printf "$deploymentTmp" | sed "s/{svc}/$svc/g;s/{ingPort}/$ingPort/g;s/{svcPort}/$svcPort/g;s/{env}/$env/g;s/{svcVersion}/${svcVersion}/g;s/{repo}/$repo/g;s/{svcImage}/$svcDir/g;s/{svcLabel}/$svcLabel/g"`
    # substitute multi line variables

    deployment=`printf "${deployment//##env##/$allEnv}"`

    # printf "$deployment" | tee $target/deployment.yaml
    printf "$deployment" > $target/deployment.yaml

    ##### generate ingress, read required variables from application.properties 
    # contextPath=`grep -E 'context-path' $from/**/application.properties` 
    local ingresses=""

    echo "ingress context path: /${svc}"
    ingress=`printf "$ingressTmpl" | sed "s/{svc}/$svc/g;s/{envInPath}/$envInPath/g;s/{env}/$env/g;s/{svcLabel}/$svcLabel/g"`
    # printf "$ingress" | tee $overlay/ingress-${svc}-${env}.yaml
    ingressName="ingress-$svc.yaml"

    printf "$ingress" > $target/$ingressName
    ingresses="- $ingressName \n${ingresses}"

    # search for applicationName in application.properties, if found, then create internal ingress with context /<applicaitonName>
    # no host defined, default tls will be used 

    appName=`grep -E 'application.name=' $from/$svcDir/src/main/resources/application.properties | sed 's/env.//g'`
    appName=${appName#*=}

    echo "found application.name, generating internal ingress to be called without host "
    echo "service: $svc : /$appName"
    if [ "$appName" ]; then
        ingressName="ingress-internal-${svc}.yaml"

        ingressInternal=`printf "$ingressInternalTmpl" | sed "s/{svc}/$svc/g;s/{envInPath}/$envInPath/g;s/{env}/$env/g;s/{appName}/$appName/g;s/{svcLabel}/$svcLabel/g"`
        ingressesInternal="- $ingressName \n${ingressesInternal}"
        # printf "$ingressInternal" | tee $overlay/ingress-internal-${svc}-${env}.yaml
        printf "$ingressInternal" > $target/$ingressName
        ingresses="- $ingressName \n${ingresses}"
    fi


    #### generate application.properties for config map
    properties=`grep -E '^prop.' $from/$svcDir/.env | sed 's/prop.//g'`
    echo ""
    echo "found properties: "
    printf "$properties" | tee $target/application.properties

    # generate kustomization for this service

    # printf "$svcKustomization" | sed "s/{namePrefix}/\"\"/g;s/{svc}/$svc/g" | tee $target/kustomization.yaml

    # move ingress files from global kustomization.yaml to $svc/kustomization.yaml
    # kustomize=`printf "$kustomization | sed "s/{env}/$env/g"`
    local kustomization=`printf "$svcKustomization" | sed "s/{namePrefix}/\"\"/g;s/{svc}/$svc/g" `
    kustomization=${kustomization//#ingresses#/$ingresses}
    printf "$kustomization" > $target/kustomization.yaml

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
