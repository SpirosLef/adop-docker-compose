#!/bin/bash -e

# A docker machine needs to be created
# docker-machine create --driver amazonec2 --amazonec2-access-key $AWS_ACCESS_KEY --amazonec2-secret-key $AWS_SECRET_ACCESS_KEY --amazonec2-vpc-id $VPC_ID --amazonec2-instance-type t2.large --amazonec2-region $REGION $MACHINE_NAME
OVERRIDES=

echo ' 
      ###    ########   #######  ########  
     ## ##   ##     ## ##     ## ##     ## 
    ##   ##  ##     ## ##     ## ##     ## 
   ##     ## ##     ## ##     ## ########  
   ######### ##     ## ##     ## ##        
   ##     ## ##     ## ##     ## ##        
   ##     ## ########   #######  ##        
'

usage(){
	echo "Usage: ./startup.sh [-m MACHINE_NAME] [-v VOLUME_DRIVER] [-l LOGGING_DRIVER] [-f path/to/additional_override1.yml] COMMAND"
        echo
        echo "COMMAND:"
        echo "   init          - Create the platform"
        echo "   up            - Start the platform"
        echo "   stop          - Stop the platform"
        echo "   cloneimages   - Clone the images within docker-compose to the images directory"
        echo "   Anything else - Argument passed to docker-compose."
}

# Defaults
export MACHINE_NAME=${DOCKER_MACHINE_NAME:-default}
export VOLUME_DRIVER=local
export LOGGING_DRIVER=syslog
export NETWORK_TYPE=bridge

while getopts "m:f:v:l:b:" opt; do
  case $opt in
    m)
      export MACHINE_NAME=${OPTARG}
      # Set the machine
      eval $( docker-machine env $MACHINE_NAME )
      ;;
    f)
      export OVERRIDES="${OVERRIDES} -f ${OPTARG}"
      ;;
    l)
      export LOGGING_DRIVER="${OPTARG}"
      ;;
    v)
      export VOLUME_DRIVER="${OPTARG}"
      ;;
    b)
      export NETWORK_TYPE="${OPTARG}"
      ;;
    *)
      echo "Invalid parameter(s) or option(s)."
      usage
      exit 1
      ;;
  esac
done

shift $(($OPTIND -1))
CMD="${1:-init}"

source env.config.sh

# TODO:
#   This is a kludge because of a defect in docker-compose, which prevents network tags being
#   Correctly merged when multiple files are specified... instead the relevant sections of the default
#   options local, syslog, bridge - have been merged into the docker-compose file.
#   Similarly elk.yml has been merged into the file.
#
# ADOPFILEOPTS="-f docker-compose.yml -f etc/volumes/${VOLUME_DRIVER}.yml -f etc/logging/${LOGGING_DRIVER}.yml -f etc/networks/${NETWORK_TYPE}.yml ${OVERRIDES}"

ADOPFILEOPTS="-f docker-compose.yml"
ELKFILEOPTS="-f compose/elk.yml -f etc/networks/${NETWORK_TYPE}.yml"

case $CMD in
  init)
    # Run the Docker compose commands
    export TARGET_HOST=$(docker-machine ip $MACHINE_NAME)
    export LOGSTASH_HOST=$(docker-machine ip $MACHINE_NAME)

    # docker-compose  ${ELKFILEOPTS} pull
    # docker-compose  ${ELKFILEOPTS} up -d
    docker-compose  ${ADOPFILEOPTS} pull
    docker-compose  ${ADOPFILEOPTS} up -d

    # Wait for Jenkins and Gerrit to come up before proceeding
    until [[ $(docker exec jenkins curl -I -s jenkins:jenkins@localhost:8080/jenkins/|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo \"Jenkins unavailable, sleeping for 60s\"; sleep 60; done
    until [[ $(docker exec gerrit curl -I -s gerrit:gerrit@localhost:8080/gerrit/|head -n 1|cut -d$' ' -f2) == 200 ]]; do echo \"Gerrit unavailable, sleeping for 60s\"; sleep 60; done
    
    # Trigger Load_Platform in Jenkins
    docker exec jenkins curl -X POST jenkins:jenkins@localhost:8080/jenkins/job/Load_Platform/buildWithParameters \
	    --data token=gAsuE35s \

    # Generate and copy the certificates to jenkins slave
    $(pwd)/generate_client_certs.sh ${DOCKER_CLIENT_CERT_PATH} >/dev/null 2>&1
    
    # Tell the user something useful
    echo
    echo '##########################################################'
    echo
    echo SUCCESS, your new ADOP instance is ready!
    echo
    echo Run these commands in your shell:
    echo '  eval \"$(docker-machine env $MACHINE_NAME)\"'
    echo '  source env.config.sh'
    echo
    echo Navigate to http://$TARGET_HOST in your browser to use your new DevOps Platform!
    ;;

  cloneimages)
    mkdir -p images
    # Sed command to extract the repo URL and name(dirname) from docker-compose.yml
    sed -n '/^ *#source/s/^ *#source *\(.*\)\/\([a-zA-Z0-9_-]*\).git/\1\/\2.git \2/gp' < docker-compose.yml | \
      while read repo dir ; do
        if [ -d images/$dir ]; then
          echo "WARNING: images/$dir already exists. Repository $repo not cloned."
        else
          ( cd images ; git clone "$repo" )
        fi
      done
    ;;

  up)
    # docker-compose  ${ELKFILEOPTS} up -d
    docker-compose  ${ADOPFILEOPTS} up -d
    ;;

  stop)
    docker-compose  ${ADOPFILEOPTS} stop
    # docker-compose  ${ELKFILEOPTS} stop
    ;;

  *)
    # TODO: Kludge as described abvoe
    #docker-compose  -f docker-compose.yml -f etc/volumes/${VOLUME_DRIVER}.yml -f etc/logging/${LOGGING_DRIVER}.yml -f etc/networks/${NETWORK_TYPE}.yml ${OVERRIDES} $@
    docker-compose  -f docker-compose-combined.yml $@
    ;;
    
esac
