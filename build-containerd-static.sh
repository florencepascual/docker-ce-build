#!/bin/bash
# Script building the dynamic containerd packages and the static binaries

set -u

set -o allexport
source env.list

# Function to create the directory if it does not exist
checkDirectory() {
  if ! test -d $1
  then
    mkdir $1
    echo "$1 created"
  else
    echo "$1 already created"
  fi
}

DIR_COS_BUCKET="/mnt/s3_ppc64le-docker/prow-docker/build-docker-${DOCKER_VERS}_${DATE}"
checkDirectory ${DIR_COS_BUCKET}

DIR_DOCKER="/workspace/docker-ce-${DOCKER_VERS}_${DATE}"
DIR_DOCKER_COS="${DIR_COS_BUCKET}/docker-ce-${DOCKER_VERS}"

if [[ ${CONTAINERD_BUILD} != "0" ]]
then
  DIR_CONTAINERD="/workspace/containerd-${CONTAINERD_VERS}_${DATE}"
  checkDirectory ${DIR_CONTAINERD}
  DIR_CONTAINERD_COS="${DIR_COS_BUCKET}/containerd-${CONTAINERD_VERS}"
  checkDirectory ${DIR_CONTAINERD_COS}
fi

DIR_LOGS="/workspace/logs"
checkDirectory ${DIR_LOGS}

DIR_LOGS_COS="${DIR_COS_BUCKET}/logs"
checkDirectory ${DIR_LOGS_COS}

PATH_DISTROS_MISSING="/workspace/distros-missing.txt"

STATIC_LOG="static.log"

# Function to build containerd packages
# $1 : distro
buildContainerd() {
  echo "= Building containerd for $1 ="
  build_before=$SECONDS
  DISTRO=$1
  DISTRO_NAME="$(cut -d'-' -f1 <<<"${DISTRO}")"
  DISTRO_VERS="$(cut -d'-' -f2 <<<"${DISTRO}")"

  cd /workspace/containerd-packaging && make REF=${CONTAINERD_VERS} docker.io/library/${DISTRO_NAME}:${DISTRO_VERS} > ${DIR_LOGS}/build_containerd_${DISTRO}.log 2>&1

  # Check if the dynamic containerd package has been built
  if test -d build/${DISTRO_NAME}/${DISTRO_VERS}
  then
    echo "Containerd for ${DISTRO} built"

    echo "== Copying packages to ${DIR_CONTAINERD} =="
    checkDirectory ${DIR_CONTAINERD}/${DISTRO_NAME}
    cp -r build/${DISTRO_NAME}/${DISTRO_VERS} ${DIR_CONTAINERD}/${DISTRO_NAME}/${DISTRO_VERS}

    echo "=== Copying packages to ${DIR_CONTAINERD_COS} ==="
    checkDirectory ${DIR_CONTAINERD_COS}/${DISTRO_NAME}
    cp -r build/${DISTRO_NAME}/${DISTRO_VERS} ${DIR_CONTAINERD_COS}/${DISTRO_NAME}/${DISTRO_VERS}

    echo "==== Copying log to ${DIR_LOGS_COS} ===="
    cp ${DIR_LOGS}/build_containerd_${DISTRO}.log ${DIR_LOGS_COS}/build_containerd_${DISTRO}.log

    # Checking everything has been copied
    if test -d ${DIR_CONTAINERD}/${DISTRO_NAME}/${DISTRO_VERS} && test -d ${DIR_CONTAINERD_COS}/${DISTRO_NAME}/${DISTRO_VERS}
    then
      echo "Containerd for ${DISTRO} was copied."
    else
      echo "Containerd for ${DISTRO} was not copied."
    fi
  else
    echo "Containerd for ${DISTRO} not built"
  fi
  build_after=$SECONDS
  build_duration=$(expr $build_after - $build_before) && echo "DURATION BUILD containerd ${DISTRO} : $(($build_duration / 60)) minutes and $(($build_duration % 60)) seconds elapsed."
}

if [[ ${CONTAINERD_BUILD} != "0" ]]
then
  echo "= Cloning containerd-packaging ="

  mkdir containerd-packaging
  cd containerd-packaging
  git init
  git remote add origin https://github.com/docker/containerd-packaging.git
  git fetch origin ${CONTAINERD_PACKAGING_REF}
  git checkout FETCH_HEAD

  make REF=${CONTAINERD_VERS} checkout
fi

before=$SECONDS
for PACKTYPE in DEBS RPMS
do
  for DISTRO in ${!PACKTYPE}
  do
    if [[ ${CONTAINERD_BUILD} != "0" ]]
    then
      buildContainerd ${DISTRO}
    else
      # Check if the package is there for this distribution
      echo "= Check containerd ="

      DIR_CONTAINERD="/workspace/containerd-${CONTAINERD_VERS}_${DATE}"

      DISTRO_NAME="$(cut -d'-' -f1 <<<"${DISTRO}")"
      DISTRO_VERS="$(cut -d'-' -f2 <<<"${DISTRO}")"

      if test -d ${DIR_CONTAINERD}/${DISTRO_NAME}/${DISTRO_VERS}
      then
        echo "${DISTRO} already built"
      else
        echo "== ${DISTRO} missing =="
        if ! test -f ${PATH_DISTROS_MISSING}
        then
          touch ${PATH_DISTROS_MISSING}
        fi
        # Add the distro to the distros-missing.txt
        echo "${DISTRO}" >> ${PATH_DISTROS_MISSING}
      fi
    fi
  done
done
after=$SECONDS
duration=$(expr $after - $before) && echo "DURATION TOTAL CONTAINERD : $(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."

# Build containerd fo the distros in ${PATH_DISTROS_MISSING}
if [[ ${CONTAINERD_BUILD} == "0" ]] && test -f ${PATH_DISTROS_MISSING}
then
  echo "= Building containerd - distros missing ="
  if ! test -d containerd-packaging
  then
    mkdir containerd-packaging
    cd /workspace/containerd-packaging
    git init
    git remote add origin https://github.com/docker/containerd-packaging.git
    git fetch origin ${CONTAINERD_PACKAGING_REF}
    git checkout FETCH_HEAD
    make REF=${CONTAINERD_VERS} checkout
  fi

  while read -r line
  do
    buildPackages "containerd" $line
  done < ${PATH_DISTROS_MISSING}
fi

echo "= Building static binaries ="

before_build=$SECONDS

# Cloning docker-ce-packaging
mkdir docker-ce-packaging
pushd docker-ce-packaging
git init
git remote add origin https://github.com/docker/docker-ce-packaging.git
git fetch origin ${DOCKER_PACKAGING_REF}
git checkout FETCH_HEAD

make REF=${DOCKER_VERS} checkout
popd

cd /workspace/docker-ce-packaging/static

CONT_NAME=docker-build-static
if [[ ! -z ${DOCKER_SECRET_AUTH+z} ]]
then
  docker run -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} -v ${ARTIFACTS}:${ARTIFACTS} --env PATH_SCRIPTS --env DOCKER_SECRET_AUTH --privileged --name ${CONT_NAME} quay.io/powercloud/docker-ce-build ${PATH_SCRIPTS}/build-static.sh
else
  docker run -d -v /workspace:/workspace -v ${PATH_SCRIPTS}:${PATH_SCRIPTS} -v ${ARTIFACTS}:${ARTIFACTS} --env PATH_SCRIPTS --privileged --name ${CONT_NAME} quay.io/powercloud/docker-ce-build ${PATH_SCRIPTS}/build-static.sh
fi

status_code="$(docker container wait ${CONT_NAME})"
if [[ ${status_code} -ne 0 ]]; then
  echo "The static binaries build failed. See details from '${STATIC_LOG}'"
  docker logs ${CONT_NAME}
else
  after_build=$SECONDS
  duration_build=$(expr $after_build - $before_build)
  echo "DURATION BUILD STATIC : $(($duration_build / 60)) minutes and $(($duration_build % 60)) seconds elapsed."
  docker logs ${CONT_NAME}

  # Check if the static packages have been built
  if test -f build/linux/tmp/docker-ppc64le.tgz
  then
    echo "Static binaries built"

    echo "== Copying static packages to ${DIR_DOCKER} =="
    cp build/linux/tmp/*.tgz ${DIR_DOCKER}

    echo "=== Copying static packages to ${DIR_DOCKER_COS} ==="
    cp build/linux/tmp/*.tgz ${DIR_DOCKER_COS}

    echo "==== Copying log to ${DIR_LOGS_COS} ===="
    cp ${DIR_LOGS}/${STATIC_LOG} ${DIR_LOGS_COS}/${STATIC_LOG}

    # Checking everything has been copied
    ls -f ${DIR_DOCKER}/*.tgz && ls -f ${DIR_DOCKER_COS}/*.tgz && ls -f ${DIR_LOGS_COS}/${STATIC_LOG}
    if [[ $? -eq 0 ]]
    then
      echo "The static binaries were copied."
    else
      echo "The static binaries were not copied."
    fi
  fi
fi

cd /workspace

# Check if the containerd packages have been built
ls ${DIR_CONTAINERD}/*
if [[ $? -ne 0 ]]
then
  # No containerd packages built
  echo "No packages built for containerd"
  BOOL_CONTAINERD=0
else
  # Containerd packages built
  BOOL_CONTAINERD=1
fi

# Check if the static packages have been built
ls -f ${DIR_DOCKER}/docker-ppc64le.tgz
if [[ $? -ne 0 ]]
then
  # No static packages built
  echo "No static packages built"
  BOOL_STATIC=0
else
  # Containerd packages built
  BOOL_STATIC=1
fi

if [[ ${BOOL_STATIC} -eq 0 ]] || [[ ${BOOL_CONTAINERD} -eq 0 ]]
then
  # There are no containerd packages built and no static packages built
  echo "No containerd packages built nor static packages built"
  exit 1
elif [[ ${BOOL_STATIC} -eq 1 ]] && [[ ${BOOL_CONTAINERD} -eq 1 ]]
then
  # There are containerd packages built and static packages built
  echo "All packages built"
fi
