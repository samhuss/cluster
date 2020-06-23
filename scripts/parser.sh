#! /bin/sh

# set -ex
#!/usr/bin/env bash
#set -Eeo pipefail


# use current folder if no services root passed
DIR=$1
pushChanges=$3
initialTag=0.1

# [ $DIR ] ||  DIR=${BASH_SOURCE[0]}
[ $DIR ] ||  DIR=$(pwd)

# DIR="$( cd "$( dirname "${DIR}" )" >/dev/null 2>&1 && pwd )"
# DIR="$( cd -P "$( dirname "$DIR" )" >/dev/null 2>&1 && pwd )"
cd $DIR

newTags=""
latestTags=""

# changed_services=() # changed services array

addTags=$2
# use lalst commit as current commit in comparising:
CURRENT=`git log --all --oneline | head -1 | awk '{print $1}'`
echo "Last commit: $CURRENT"


versionNewChanges(){
    # find all sub directories that represents deployable services, each directory will be a microservice
    services=`grep -lE 'service.deploy=true' ./**/.env | cut -d '/' -f2 2>/dev/null`
    #services=`echo */ | sed -e 's=/==g' `
    echo "Trieggered by a commit at: $(date)"
    echo "Root services directory: $DIR, path: $(pwd)"
    echo "-> Checking all microservices for new changes, only changed microservices version will be promoted" 
    echo "Checking services:  " 
    echo "$services"  

    local changed=0

    for SVC in $services; do 
        echo "----"
        echo "$SVC: comparing current commit with last service release"
        incrementVersion $SVC
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

incrementVersion(){

    svc=$1
    DIR=$1 

    # check if current commit has tag for the service, if yes then return and don't update this service
    # currTag=`git --no-pager tag -l | grep $svc`
    currTag=`git tag --points-at $CURRENT | grep $svc`

    if [ "$currTag" ]; then 
        echo "$svc: $currTag, there is a tag in current commit, returning"
        latestTags="${latestTags} $currTag"
        return; 
    fi

    # search for the last known tag for a service to compare current commit with the last konwn changed version
    oldTag=`git show-ref  --abbrev=6 --tags | grep $svc | tail -1 | sed -e 's=refs/tags/==g' | awk '{print $1 " " $2 }'`
    echo "old tag for service $1: $oldTag"

    if [ ! "$oldTag" ]; then
        # this is the very first commit, no previous commit, add new version directly
        local newVersion=$svc"/"$initialTag
        echo "$svc:$newVersion initial tag added, No Old version found"

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

    echo "$svc: old version: $oldTag,  old commit: $commit,  old tag: $otag"
    # echo "$svc: "
    # echo "$svc: "

    # in the very first run, there is no previous commit to compare against, so master will be the base commit
    # [ commit ] || commit="master"

    # shortcut code to check changed directories
    # git diff --quiet HEAD $REF -- $DIR || changed=1 && printf "$SVC: changed \n"

    # changed=`git diff --quiet HEAD $commit -- $DIR`
    #echo "command: git diff --quiet $CURRENT $commit -- $DIR"

    changed=`git diff --quiet $CURRENT $commit -- $DIR || echo "changed"`

    if [ ! "$changed" ]; then 
        echo "$svc: no change since last commit $commit, keep old version: $otag"
        # latestTags+=($otag)
        latestTags="${latestTags} $otag"
        return
    fi

    echo "$svc: changed, promoting version"
    local newVersion=""

    if [ "$otag" ]; then
        # echo "incrementing svc:$svc, from tag: $otag, commit: $commit"
        # IFS='-' read -r -a tmp <<< $otag   # read variable to array tmp
        # newVersion=$(echo "$otag" | sed -r 's/(.*)([0-9]+)$/echo "\1$((\2+1))"/ge')   # bash version
        newVersion=$(eval `echo "$otag" | sed -r 's/(.*)([0-9]+)$/echo "\1$((\2+1))"/g'`)   # sh version
        echo "$svc: promoting: $otag --> $newVersion"

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
            git tag $tag $CURRENT
        done 
        # push changes of current commit for not to re-build these packages again
        git push --tags
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
tags=`git tag --points-at HEAD`
echo $tags
# echo $tags | sed  's=/=:=g' | paste -d 
printf %s\\n $tags | sed 's=/=:=;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/docker-builds
printf %s\\n $tags | sed 's=/.*==;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/services

# git tag --points-at HEAD | sed 's=/=:=;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/docker-builds
# git tag --points-at HEAD | sed 's=/.*==;s/["\]/\\&/g;s/.*/"&"/;1s/^/[/;$s/$/]/;$!s/$/,/' > /tmp/services

echo "docker builds: " && cat /tmp/docker-builds
echo "services: " && cat /tmp/services
