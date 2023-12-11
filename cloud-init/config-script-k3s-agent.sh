#!/bin/bash
set -x

echo "# DEBUG start k3-agent.sh $(date)"
cloud_user=outscale
libdir=/home/$cloud_user

# Load config
[ -f ${libdir}/config.cfg ] && source ${libdir}/config.cfg

# insecure curl
echo "-k" >> ~/.curlrc

if [ -z "$K3S_URL" ] ;then
    echo "K3S_URL not defined"
    exit 1
fi

docker version || exit $?

[ -n "${DOCKERHUB_TOKEN}" -a -n "${DOCKERHUB_LOGIN}" ] && echo "${DOCKERHUB_TOKEN}" | docker login -u ${DOCKERHUB_LOGIN}  --password-stdin

# k3s configuration
if [ -z "$K3S_TOKEN" ] ;then
  K3S_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 108  | head -n 1)
fi

DEFAULT_TIMEOUT=${DEFAULT_TIMEOUT:-1200}

INSTALL_K3S_EXEC=()

INSTALL_K3S_EXEC+=("agent")
INSTALL_K3S_EXEC+=("--docker")
# in case of controle plane only without users workload
# INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC --node-taint CriticalAddonsOnly=true:NoExecute"

# set node label
#   from NODE_LABELS variables
#   from meta-data (k3s.label.XX: true)
meta_data_url=http://169.254.169.254/latest/meta-data/tags
meta_data_labels_key="$(curl -s $meta_data_url |grep k3s.label )"
meta_data_labels="$(for label in $meta_data_labels_key ; do curl -s $meta_data_url/$label |xargs -i echo ${label#k3s.label.}={} ; done)"
NODE_LABELS="${NODE_LABELS:-} ${meta_data_labels:-}"

ADD_NODE_LABELS=$(echo "$NODE_LABELS" | tr ' ' '\n' | xargs  -i echo "--node-label {}"|xargs)

INSTALL_K3S_EXEC+=("${ADD_NODE_LABELS:-}")

INSTALL_PARAMS="${INSTALL_K3S_EXEC[*]}"
#
# wait 10s ctrlplane is ready
#
test_result=1
timeout=$DEFAULT_TIMEOUT
is_ready=10

until [ "$timeout" -le 0 -o "$is_ready" -eq "0" ] ; do
  RESPONSE_CODE=$(curl -ks -o /dev/null  -w '%{http_code}' ${K3S_URL}/livez?verbose)
  if (( RESPONSE_CODE == 200 )) || (( RESPONSE_CODE == 401 )) ; then
   test_result=0
  else
   test_result=1
  fi

  if [ "$test_result" -gt 0 ] ;then
     echo "Retry $timeout seconds: $test_result";
     (( timeout-- ))
  else
   (( is_ready-- ))
  fi
     sleep 1
done

if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: curl $test_result"
        exit $test_result
fi

#
# download and install k3s
#

test_result=1
timeout=$DEFAULT_TIMEOUT
curl_args="--connect-timeout 30 --retry 300 --retry-delay 5"

until [ "$timeout" -le 0 -o "$test_result" -eq "0" ] ; do
  ( curl $curl_args -skfL https://get.k3s.io | K3S_VERSION="${K3S_VERSION:-}" K3S_TOKEN="$K3S_TOKEN" K3S_URL="${K3S_URL:-}" sh -s - $INSTALL_PARAMS )
  test_result=$?
  if [ "$test_result" -gt 0 ] ;then
     echo "Retry $timeout seconds: $test_result";
     (( timeout-- ))
     sleep 1
  fi
done

if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: curl https://get.k3s.io $test_result"
        exit $test_result
fi

echo "# DEBUG start k3-agent.sh $(date)"
exit 0
