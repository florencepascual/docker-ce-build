#!/bin/bash

set -u

# Path to the scripts
SECONDS=0
PATH_SCRIPTS="/home/prow/go/src/github.com/ppc64le-cloud/docker-ce-build"

echo DATE=\"${DATE}\" 2>&1 | tee ${PATH_SCRIPTS}/env/containerd.list

if [[ -z ${ARTIFACTS} ]]
then
    ARTIFACTS=/logs/artifacts
    echo "Setting ARTIFACTS to ${ARTIFACTS}"
    mkdir -p ${ARTIFACTS}
fi

export PATH_SCRIPTS

echo "Prow Job to build the containerd packages"

# Go to the workdir
cd /workspace

# Start the dockerd and wait for it to start
echo "* Starting dockerd and waiting for it *"
source ${PATH_SCRIPTS}/dockerd-starting.sh

if [ -z "$pid" ]
then
    echo "There is no docker daemon."
    exit 1
else
    # Get the env file and the dockertest repo and the latest built of containerd if we don't want to build containerd
    echo "** Set up (env files) **"
    ${PATH_SCRIPTS}/get-env.sh
    ${PATH_SCRIPTS}/get-env-containerd.sh

    set -o allexport
    source env.list
    source date.list
    export DATE

    # Build containerd
    echo "*** Build containerd packages ***"
    ${PATH_SCRIPTS}/build-containerd.sh
    exit_code_build=`echo $?`
    echo "Exit code build : ${exit_code_build}"

    duration=$SECONDS
    echo "DURATION ALL : $(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

    if [[ ${exit_code_build} -eq 0 ]]
    then
        echo "Build containerd successful"
        cd ${PATH_SCRIPTS}
        git add . && git commit -m "New build containerd ${CONTAINERD_VERS}" && git push
        exit_code_git=`echo $?`
        echo "Exit code prow-build-containerd.sh : ${exit_code_git}"
        if [[ ${exit_code_git} -eq 0 ]]
        then
            echo "Git push successful"
            exit 0
        else
            echo "Git push not successful"
            exit 1
        fi
    else
        echo "Build containerd not successful"
        exit 1
    fi
fi
