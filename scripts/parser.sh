#! /bin/sh

# set -ex
#!/usr/bin/env bash
#set -Eeo pipefail


# use current folder if no services root passed
DIR=$1
pushChanges=$3
initialTag=0.1
isMonoRepo="true"
serviceName=""  # used in case of multi-repo and only one repo to be checked

# [ $DIR ] ||  DIR=${BASH_SOURCE[0]}
[ $DIR ] ||  DIR=$(pwd)

# DIR="$( cd "$( dirname "${DIR}" )" >/dev/null 2>&1 && pwd )"
# DIR="$( cd -P "$( dirname "$DIR" )" >/dev/null 2>&1 && pwd )"
cd $DIR
# keep directory full path for reference
RootDir=`pwd`

 # check if repo is multi-repo or mono-repo. Mono-repo will contain multiple projects under the parent directory
 # multi-repo means every repo contains one project, so we have to cd into that project to start using git commands

gitDir=$DIR

servicesCount=`ls | wc -l`
echo "sub directories of passed root are: $servicesCount"

if [ ! $servicesCount -eq "1" ]; then
    echo "passed root has more than 1 service, build mode is mono-repo, will work on all sub directories of: $DIR"
    isMonoRepo="true"
else
    echo "passed root has $servicesCount directory, build mode is multi-repo, will use the first directory as the main git directory"
    gitDir="$gitDir/`ls | head -1`"
    echo "using new git directory: $gitDir"
    isMonoRepo="false"
fi


# subProjectsCount=0
# subProjectsCount=`ls | wc -l`


# echo "passed git directory: $gitDir"
# echo "sub directories count of passed git directory: $subProjectsCount"

# # if (($subProjectsCount == 1)); then 
# if [ $subProjectsCount -eq 1 ]; then 
#     gitDir="$gitDir/`ls`"
#     isMonoRepo="false"
#     echo "Working on one service under passed git directory, thus all git commands will run from service directory: $gitDir" 
# fi 

newTags=""
latestTags=""

# changed_services=() # changed services array

addTags=$2
# use lalst commit as current commit in comparising:
#CURRENT=`git log --all --oneline | head -1 | awk '{print $1}'`

versionNewChanges(){
    # fix getting last commit for current branch. --all  gets the latest commit for all branches 
    # while we want the last commit of the current branch
    currentBranch=`git -C $gitDir branch | grep "\*"`
    # currentCommit=`git log --oneline -n 1 HEAD | head -1`
    currentCommit=`git -C $gitDir log --oneline --decorate -n 1 HEAD `
    CURRENT=`echo $currentCommit | awk '{print $1}'`
    # CURRENT=`git log --oneline -n 1 HEAD | head -1 | awk '{print $1}'`
    echo "Current branch: $currentBranch"
    echo "Current commit: $currentCommit"
    # serviceName not found, means working with mono-repo, list all sub directories
    # find all sub directories that represents deployable services, each directory will be a microservice
    services=`grep -lE 'service.deploy=true' ./**/.env | cut -d '/' -f2 2>/dev/null`
    
    #services=`echo */ | sed -e 's=/==g' `
    echo "Find and promote changed services with new tags."
    echo "Root directory: $DIR"
    echo "Git directory: $gitDir"
    echo "isMonoRepo: $isMonoRepo"
    echo "--> Checking following microservices for new changes, only services with .env file will be checked and promoted" 
    echo "$services"  

    local changed=0

    for SVC in $services; do 
        echo "----"
        echo "$SVC: comparing current commit with last service release"
        incrementServiceVersion $SVC
    done;

    # echo "all services with echo: "
    # echo $changed_services

    # echo "found services with tags: "
    # echo "length of found services: "  ${#changed_services}

    # echo "All changed services"
    # printf "${changed_services[@]}"
    # echo ""
    
    # while IFS="\n" read -r line
    # do
    #     echo "reading lines: $line"
    # done <<< "$changed_services"

    # while IFS= read -r line
    # do
    # incrementTag $line
    # done < <(printf '%s\n' "$changed_services")

}

incrementServiceVersion(){
    svc=$1

    # check if current commit has tag for the service, if yes then return and don't update this service
    # currTag=`git --no-pager tag -l | grep $svc`
    # currTag=`git tag --points-at $CURRENT | grep $svc`
    # currTag=`git tag --points-at HEAD | grep $svc`

    # currentCommit has all tag names, check if service name is already in the latest commit which means no changes
    currTag=`echo $currentCommit | grep $svc`


    if [ "$currTag" ]; then 
        echo "Returning: found tag for service $svc current commit: $currTag"
        latestTags="${latestTags} $currTag"
        return; 
    fi

    echo "no current tag found, promoting last known tag for the service"
    # search for the last known tag for a service to compare current commit with the last konwn changed version
    # error: show-ref doesn't sort by date, alphanumeric search only
    #oldTag=`git show-ref  --abbrev=6 --tags | grep $svc | tail -1 | sed -e 's=refs/tags/==g' | awk '{print $1 " " $2 }'`

    # oldTag=`git tag -l --sort=-version:refname | grep $svc | head -1 |  awk '{print $1 " " $2 }'`
    # oldTag=`git for-each-ref --sort=creatordate --format '%(refname)' refs/tags  | grep $svc | tail -1 | sed -e 's=refs/tags/==g' | awk '{print $1 " " $2 }'`
    oldTag=`git -C $gitDir for-each-ref --sort=creatordate --format '%(objectname:short) %(refname:short)' refs/tags  | grep $svc | tail -1`

    if [ ! "$oldTag" ]; then
        # this is the very first commit, no previous commit, add new version directly
        local newVersion=$svc"/"$initialTag
        echo "No Old tag found, initial tag added: $svc:$newVersion"

        # bash syntax for array
        # newTags+=($newVersion)
        # latestTags+=($newVersion)

        # sh syntax for array
        newTags="${newTags} $newVersion"
        latestTags="${latestTags} $newVersion"

        return
    fi


    # continue with the normal path, old version found and promot version if a change found in the directory


    # oldTag=($oldTag)
    # oldTag=$oldTag
    # commit=${oldTag[0]}
    # otag=${oldTag[1]}
    commit=`echo $oldTag | cut -d" " -f1`
    otag=`eval echo $oldTag | cut -d" " -f2`

    # commit= "$(echo $oldTag | cut -d' ' -f1)" #${oldTag[0]}
    # otag= "$(echo $oldTag | cut -d' ' -f2)" #${oldTag[0]}
    # otag=${oldTag[1]}


    # in the very first run, there is no previous commit to compare against, so master will be the base commit
    # [ commit ] || commit="master"

    # shortcut code to check changed directories
    # git diff --quiet HEAD $REF -- $svc || changed=1 && printf "$SVC: changed \n"

    # changed=`git diff --quiet HEAD $commit -- $svc`
    #echo "command: git diff --quiet $CURRENT $commit -- $svc"

    # changed=`git diff --quiet $CURRENT $commit -- $svc || echo "changed"`
    changed=`git -C $gitDir diff --quiet HEAD $commit -- $svc || echo "changed"`

    if [ ! "$changed" ]; then 
        echo "$svc: no change since last commit $commit, keep old version: $otag"
        # latestTags+=($otag)
        latestTags="${latestTags} $otag"
        return
    fi

    local newVersion=""

    if [ "$otag" ]; then
        # echo "incrementing svc:$svc, from tag: $otag, commit: $commit"
        # IFS='-' read -r -a tmp <<< $otag   # read variable to array tmp
        # newVersion=$(echo "$otag" | sed -r 's/(.*)([0-9]+)$/echo "\1$((\2+1))"/ge')   # bash version
        newVersion=$(eval `echo "$otag" | sed -r 's/(.*)([0-9]+)$/echo "\1$((\2+1))"/g'`)   # sh version
        echo "promoting tag: $otag --> $newVersion"

        newTags="${newTags} $newVersion"
        latestTags="${latestTags} $newVersion"

        # newTags+=($newVersion)
        # latestTags+=($newVersion)
        # echo "old tag version: ${tmp[1]}, new version: v$newVersion"
    fi

    # add new version to changes array to update last commit with the new tag (version) 
}

# changed_services=($( for SVC in $services; do 
# echo  `git show-ref  --abbrev=6 --tags | grep $SVC | tail -1 | awk '{print $1 " " $2 }' | sed -e 's=refs/tags/==g'`
# done;
# ))

# add new tags
addNewTags(){
    if [ "$addTags" ]; then
        echo "adding new tags: true"
        # for tag in ${newTags[@]}; do
        for tag in ${newTags}; do
            echo "adding tag $tag"
            # git tag $tag $CURRENT
            git -C $gitDir tag $tag HEAD
        done 
        # push changes of current commit for not to re-build these packages again
        git -C $gitDir push --tags
    else
echo "----
addTag argument is not passed to the command, no changes will be applied.  
To change the commit with the new tags, please call the command with addTag parameter
----"
    fi
}

# scan all subfolder that contains .env file and pump version if any changes found
versionNewChanges

echo "-------"

echo "Finished checking all services"
echo "Adding new tags to current commit for the changed services: "
#echo "+++> ${newTags[@]}"
echo "+++> ${newTags}"
echo "Latest versions for all services: ready for release: "
# echo "===> ${latestTags[@]}"  # bash syntax in case of using arrays (), in sh no arrays, just strings with spaces
echo "===> $latestTags"

addNewTags


# the following script converts tag name to docker package name: replace A/0.1 by $tag when looping over tags
# echo A/0.1 | sed -e 's=/=:=g'

# list tags without blocking the prompt, add --no-pager to git command
# git --no-pager tag -l

echo "Tags to be used in this builds"
# git --no-pager tag -l --sort="version:refname" | sed -s 's=/=:=g'
# git --no-pager tag -l  | sed  's=/=:=g'
# git --no-pager tag -l  

# list tags of current commit only, whether use HEAD or $CURRENT commit id
# git tag --points-at $CURRENT | sed  's=/=:=g'
tags=`git -C $gitDir tag --points-at HEAD`
echo $tags
# echo $tags | sed  's=/=:=g' | paste -d 
printf %s\\n $tags | sed 's=/=:=;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/docker-builds
printf %s\\n $tags | sed 's=/.*==;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/services

# git tag --points-at HEAD | sed 's=/=:=;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/docker-builds
# git tag --points-at HEAD | sed 's=/.*==;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/services

echo "docker builds as array: " && cat /tmp/docker-builds
echo "services as array: " && cat /tmp/services

if [ "$registry" ]; then
    newImages=""
    echo "check all tags, latest tags from previous commits and new tags in this commit"
    # tags="${tags} ${latestTags}"
    # url="https://$registry/v2/repository/$1/tags/$2"
    echo "docker registry found, checking docker images availablity before bilding new ones"
    # for image in ${tags}; do
    for svc in ${services}; do
        # echo "checking image: $image"
        # most recent tags that were not built

        # git tag doesn't sort by date, sort alphanumeric, this line returns wrong name for last image
        image=`git -C $gitDir tag -l --sort=-version:refname "$svc*" | head -1`  

        # use for-each-ref to get all tags sorted by date
        # image=`git for-each-ref --sort=creatordate --format '%(refname:short)' refs/tags  | grep $svc | tail -1`
        echo "$svc:     $image"
        repo=`echo $image | cut -d'/' -f1`
        tag=`echo $image | cut -d'/' -f2`
        # echo "checking image: $repo with tag $tag"
        url="https://$registry/v2/$repo/tags/list"
        # echo "calling url: $url" 
        result=`curl -s $url | grep \"$tag\"`
        # echo "curl result: $result"
        if [ "$result" ]; then 
            echo "--- exclude: $image from docker builds"; 
        else 
            newImages="$image ${newImages}"
            echo "+++ include: $image in docker builds " ; 
        fi;
    done
    if [ "$newImages" ]; then 
        echo "exporting new /tmp/docker-builds and /tmp/services files"
        printf %s\\n $newImages | sed 's=/=:=;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/docker-builds
        printf %s\\n $newImages | sed 's=/.*==;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/services
    else
        echo "no services to be built, all tags have docker images"
        echo "[]" > /tmp/docker-builds
        echo "[]" > /tmp/services
    fi
fi

# if builderTemplate xml file is loaded as env variable, read all .env files and load modules property to generate 
# builder-pom.xml file in each project for each java project

# modulesPath sample: ./test-mpn-bulk-registration/.env:modules=Utils

pomTemplate=`cat<<EOT
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
<modelVersion>4.0.0</modelVersion>
<groupId>com.raseedy</groupId>
<artifactId>utils-builder</artifactId>
<version>0.0.10</version>
<name>utils-builder</name>
<properties> <java.version>1.8</java.version> </properties>
<packaging>pom</packaging>
<modules>
##modules##
</modules>
</project>
EOT
`
#  <module>.</module> 

# loop on all services, read modules= property from .env, then create one pom file for all utility modules 
# to be executed before building all servcies

allModules=""
modulesString=""
for service in $services;do

    modules=`grep -E 'modules=' $service/.env | cut -f2 -d=`
    for module in $modules; do
        alreadyInModules=`echo $allModules | grep $module`
        if [ -z "$alreadyInModules" ]; then
            allModules="${allModules} $module"
            # modulesString="${modulesString} $module"
        fi
    done

    # modulesString="${modulesString} <module>../$module</module>\n"
done

# build one pom file for all utility projects

echo "modules to be built as utilsity projects"
echo $allModules

for module in $allModules; do
    modulesString="${modulesString} <module>$module</module>\n"
    # modulesString="${modulesString} $module"
done

# echo "modulesString $modulesString"
pom=${pomTemplate//##modules##/$modulesString}


# print utils-pom file only if build is for mono-repo, only use case is build java mono-repo
if [[ "$modulesString" && "$newImages" ]]; then 
    printf "$pom" > utils-pom.xml
    echo "true" > /tmp/build-utils
else
    echo "false" > /tmp/build-utils
fi



# printf %s $pomTemplate  
# echo writing builder-pom.xml to service directory
# echo $pom | tee "$service/builder-pom.xml"

# allModules=""
# for service in $services;do

#     modules=`grep -E 'modules=' $service/.env | cut -f2 -d=`
#     modulesString=""
#     for module in $modules; do
#         alreadyInModules=`echo modulesString | grep $module`
#         if [[ ! alreadyInModules ]]; then
#             modulesString="${modulesString} <module>../$module</module>\n"
#         fi
#     done
#     # echo "modulesString $modulesString"
#     pom=${pomTemplate//##modules##/$modulesString}
#     # pom=`sed -n 's/\${modulesString}/$modulesString/g' $pomTemplate`
#     # printf "$pom" | tee $service/builder-pom.xml
#     printf "$pom" > $service/builder-pom.xml

#     # printf %s $pomTemplate  
#     # echo writing builder-pom.xml to service directory
#     # echo $pom | tee "$service/builder-pom.xml"
# done

