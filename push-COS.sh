#!/bin/bash
# Script to push to the COS buckets
# ${CHECK_TESTS_BOOL} -> 0 or 1
# if 0 (there are no errors) : push to the COS Bucket shared with docker (ibm-docker-builds)
# if 1 (there are errors) : exit 1

set -u

set -o allexport
source env.list

PATH_COS="/mnt"
PATH_PASSWORD="/root/.s3fs_cos_secret"

COS_BUCKET_SHARED="ibm-docker-builds"
URL_COS_SHARED="https://s3.us-east.cloud-object-storage.appdomain.cloud"

PATH_DISTROS_MISSING="/workspace/distros-missing.txt"

# If there are no errors
if [[ ${CHECK_TESTS_BOOL} -eq 0 ]]
then
    echo "- Push to ibm-docker-builds -"

    # Mount the ibm-docker-builds COS bucket
    mkdir -p ${PATH_COS}/s3_${COS_BUCKET_SHARED}
    s3fs ${COS_BUCKET_SHARED} ${PATH_COS}/s3_${COS_BUCKET_SHARED} -o url=${URL_COS_SHARED} -o passwd_file=${PATH_PASSWORD} -o ibm_iam_auth

    # Get the directory name ex: "docker-ce-20.10-11" (version without patch number then build tag)
    DIR_DOCKER_VERS=$(eval "echo ${DOCKER_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")
    echo "List of the directories beginning with docker-ce : "
    ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/docker-ce-*/
    if [[ $? -eq 0 ]]
    then
        DOCKER_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/docker-ce-${DIR_DOCKER_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f6)
        DOCKER_BUILD_TAG=$((DOCKER_LAST_BUILD_TAG+1))
    else
        # If there are no directories yet
        DOCKER_BUILD_TAG="1"
    fi
    DIR_DOCKER_SHARED=docker-ce-${DIR_DOCKER_VERS}-${DOCKER_BUILD_TAG}
    echo "Build tag : ${DOCKER_BUILD_TAG}"

    # Copy the docker-ce packages to the COS bucket
    # cp -r /workspace/docker-ce-${DOCKER_VERS}_${DATE} ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_DOCKER_SHARED}

    if test -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_DOCKER_SHARED}
    then
        echo "${DIR_DOCKER_SHARED} copied"
    else
        echo "${DIR_DOCKER_SHARED} not copied"
    fi

    if [[ ${CONTAINERD_BUILD} -eq "1" ]]
    then
        # We built a new version of containerd

        # Get the directory name ex: "containerd-1.4-9" (version without patch number then build tag)
        DIR_CONTAINERD_VERS=$(eval "echo ${CONTAINERD_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")
        echo "List of the directories beginning with containerd : "
        ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-*/
        if [[ $? -eq 0 ]]
        then
            CONTAINERD_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-${DIR_CONTAINERD_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f5)
            CONTAINERD_BUILD_TAG=$((CONTAINERD_LAST_BUILD_TAG+1))
        else
            # If there are no directories yet
            CONTAINERD_BUILD_TAG="1"
        fi
        DIR_CONTAINERD=containerd-${DIR_CONTAINERD_VERS}-${CONTAINERD_BUILD_TAG}
        echo "Build tag : ${CONTAINERD_BUILD_TAG}"

        # Copy the containerd packages to the COS bucket
        # mkdir ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
        # cp -r /workspace/containerd-${CONTAINERD_VERS}_${DATE}/* ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}

        if test -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
        then
            echo "${DIR_CONTAINERD} copied"
        else
            echo "${DIR_CONTAINERD} not copied"
        fi

    else
        # Check if distros-missing.txt exists and if exists, push only the distros mentionned
        if test -f ${PATH_DISTROS_MISSING}
        then
            # distros-missing.txt exists

            # Get the directory name ex: "containerd-1.4-9" (version without patch number then build tag)
            DIR_CONTAINERD_VERS=$(eval "echo ${CONTAINERD_VERS} | cut -d'v' -f2 | cut -d'.' -f1-2")

            echo "List of the directories beginning with containerd : "
            ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-*/
            if [[ $? -eq 0 ]]
            then
                CONTAINERD_LAST_BUILD_TAG=$(ls -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/containerd-${DIR_CONTAINERD_VERS}-* | sort --version-sort | tail -1| cut -d'-' -f5)
                CONTAINERD_BUILD_TAG=$((CONTAINERD_LAST_BUILD_TAG+1))
            else
                # If there are no directories yet
                CONTAINERD_BUILD_TAG="1"
            fi
            DIR_CONTAINERD=containerd-${DIR_CONTAINERD_VERS}-${CONTAINERD_BUILD_TAG}
            echo "Build tag : ${CONTAINERD_BUILD_TAG}"

            while read -r line
            do
                # Copy the containerd package
                DISTRO_NAME="$(cut -d':' -f1 <<<"${line}")"
                DISTRO_VERS="$(cut -d':' -f2 <<<"${line}")"
                if ! test ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
                then
                    echo "Create ${DIR_CONTAINERD}"
                    # mkdir -p ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}
                fi
                if ! test ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}/${DISTRO_NAME}
                then
                    echo "Create ${DIR_CONTAINERD}/${DISTRO_NAME}"
                    # mkdir -p ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}/${DISTRO_NAME}
                fi
                # cp -r /workspace/containerd-${CONTAINERD_VERS}_${DATE}/${DISTRO_NAME}/${DISTRO_VERS} ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}/${DISTRO_NAME}
                if test -d ${PATH_COS}/s3_${COS_BUCKET_SHARED}/${DIR_CONTAINERD}/${DISTRO_NAME}/${DISTRO_VERS}
                then
                    echo "${DIR_CONTAINERD} copied"
                else
                    echo "${DIR_CONTAINERD} not copied"
                fi
            done
        fi
    fi
fi

if [[ ${CHECK_TESTS_BOOL} -eq 0 ]]
then
    echo "There were no errors in the tests."
    exit 0
else
    echo "There were some errors in the tests."
    exit 1
fi
