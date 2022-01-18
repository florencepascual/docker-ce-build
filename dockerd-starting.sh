#!/bin/bash
# Script calling dockerd-entrypoint that will start the dockerd and then checking that the docker daemon has started

# Start the docker daemon in the background
bash /usr/local/bin/dockerd-entrypoint.sh --mtu=1440 &

# Check if the dockerd has started
DAEMON="dockerd"
while ! /usr/bin/pgrep ${DAEMON}
do
    echo "Waiting for the dockerd pid"
    sleep 14
done

pid=`/usr/bin/pgrep $DAEMON`
echo "$DAEMON pid:$pid"

if [ "$pid" ]
then
    while ! docker stats --no-stream
    do
        echo "Waiting for dockerd to start"
        sleep 10
        if [[ ! -z ${DOCKER_SECRET_AUTH+z} ]] && [ ! -d /root/.docker ]
        then
            mkdir /root/.docker
            echo "$DOCKER_SECRET_AUTH" > /root/.docker/config.json
            echo "Docker login"
        fi
        echo "Launching docker info"
        docker info
    done
fi
