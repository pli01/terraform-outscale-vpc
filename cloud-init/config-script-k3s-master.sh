#!/bin/bash
set -x

echo "# DEBUG start k3-master.sh $(date)"
cloud_user=outscale
libdir=/home/$cloud_user

# Load config
[ -f ${libdir}/config.cfg ] && source ${libdir}/config.cfg

# insecure curl
echo "-k" >> ~/.curlrc

docker version || exit $?

[ -n "${DOCKERHUB_TOKEN}" -a -n "${DOCKERHUB_LOGIN}" ] && echo "${DOCKERHUB_TOKEN}" | docker login -u ${DOCKERHUB_LOGIN}  --password-stdin

# k3s configuration
if [ -z "$K3S_TOKEN" ] ;then
  K3S_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 108  | head -n 1)
fi

DEFAULT_TIMEOUT=${DEFAULT_TIMEOUT:-1200}

INSTALL_K3S_EXEC=()

INSTALL_K3S_EXEC+=("server")

if [ -n "$K3S_CLUSTER_INIT" ] ;then
    echo "# Init first control plane"
    INSTALL_K3S_EXEC+=("--cluster-init")
fi

INSTALL_K3S_EXEC+=("--docker")
# in case of controle plane only without users workload
if [ -n "$NODE_TAINTS" ]; then
  case "$NODE_TAINTS" in
      CriticalAddonsOnly) INSTALL_K3S_EXEC+=("--node-taint CriticalAddonsOnly=true:NoExecute") ;;
  esac
fi

## INSTALL_K3S_EXEC+=("--disable traefik --disable=servicelb")

INSTALL_PARAMS="${INSTALL_K3S_EXEC[*]}"

if [ -n "$K3S_URL" ] ;then
    echo "# register this control plane to $K3S_URL"
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

#
# wait k3s.service
#
test_result=1
is_ready=5
timeout=$DEFAULT_TIMEOUT

echo "# Wait k3s service is ready"
until [ "$timeout" -le 0 -o "$is_ready" -eq "0" ] ; do
#    (sudo systemctl show  -p SubState,ActiveState k3s)
 (sudo kubectl get --raw='/readyz?verbose')
 test_result=$?
 if [ "$test_result" -gt 0 ] ;then
     echo "Wait k3s.service ready. Retry $timeout seconds: $test_result $is_ready";
     (( timeout-- ))
 else
   (( is_ready-- ))
 fi
 sleep 1
done
if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: k3s not ready $test_result"
        exit $test_result
fi

#
# wait k3s ready
#
test_result=1
timeout=$DEFAULT_TIMEOUT

echo "# Wait for node to be ready"
until [ "$timeout" -le 0 -o "$test_result" -eq "0" ] ; do
# (sudo -E kubectl get node -A)
(sudo kubectl wait --for=condition=Ready node $(cat /etc/hostname) --timeout=600s)
 test_result=$?
 if [ "$test_result" -gt 0 ] ;then
     echo "Wait node to be ready. Retry $timeout seconds: $test_result";
     (( timeout-- ))
     sleep 1
 fi
done
if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: k3s not ready $test_result"
        exit $test_result
fi

if [ -z "$K3S_CLUSTER_INIT" ] ;then
    echo "# control-plane addons end"
    exit 0
fi

#exit 0

#
# wait traefik deployment ready
#
test_result=1
timeout=$DEFAULT_TIMEOUT

until [ "$timeout" -le 0 -o "$test_result" -eq "0" ] ; do
 (sudo -E kubectl rollout status  deployment/traefik -n kube-system -w  --timeout=${DEFAULT_TIMEOUT}s)
 test_result=$?
 if [ "$test_result" -gt 0 ] ;then
     echo "Retry $timeout seconds: $test_result";
     (( timeout-- ))
     sleep 1
 fi
done
if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: traefik not ready $test_result"
        exit $test_result
fi


#
# add dockerhub credentials
#
if [ -n "$DOCKERHUB_LOGIN" -a -n "$DOCKERHUB_TOKEN" ] ; then
  sudo -E kubectl create secret docker-registry regcred \
     --docker-server=https://index.docker.io/v1/ \
     --docker-username=$DOCKERHUB_LOGIN \
     --docker-password=$DOCKERHUB_TOKEN
#
# Automatically add imagePullSecrets to default ServiceAccount
#
  sudo -E kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "regcred"}]}'
fi


#
# add portainer on /portainer path
#
# Hack: skip tls verify backend in traefik
cat <<EOF | sudo -E kubectl create --dry-run="client" -o yaml -f - | sudo -E kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    globalArguments:
    - "--serversTransport.insecureSkipVerify=true"
EOF
sudo -E kubectl rollout status  deployment/traefik -n kube-system -w  --timeout=${DEFAULT_TIMEOUT}s


#
# optional install portainer agent (9001)
#
sudo -E kubectl create -f https://downloads.portainer.io/portainer-agent-ce29-k8s-lb.yaml --dry-run="client" -o json | \
   jq '.|(if .kind == "ServiceAccount" then . + {"imagePullSecrets": [{"name": "regcred"}]} else . end)'  | \
   jq '.|(if .kind == "Deployment" then .spec.template.spec.containers[0].imagePullPolicy = "IfNotPresent"  else . end)' | \
   jq '.|(if .kind == "Deployment" then .spec.template.spec.tolerations = [{"key":"CriticalAddonsOnly","operator":"Exists"},{"key":"node-role.kubernetes.io/master","operator":"Exists","effect":"NoSchedule"},{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}] else . end)' | \
   sudo -E kubectl apply -f -

#
# install portainer with following specifications:
#   * use image pull secrets to download image from dockerhub auth registry
#   * download container if not present
#   * stick portainer to control-plane/master node only
#   * add http_proxy,no_proxy env variable (corporate proxy)
#
MASTER_IP=$(( /sbin/ip add show dev eth0 2>&- || /sbin/ifconfig eth0  2>&- || /sbin/ifconfig en0 2>&- ) | awk '{ print $2}' | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")

sudo -E kubectl create -f https://raw.githubusercontent.com/portainer/k8s/master/deploy/manifests/portainer/portainer-lb.yaml --dry-run="client" -o json | \
   jq '.|(if .kind == "ServiceAccount" then . + {"imagePullSecrets": [{"name": "regcred"}]} else . end)'  | \
   jq '.|(if .kind == "Deployment" then .spec.template.spec.containers[0].imagePullPolicy = "IfNotPresent"  else . end)' |  \
   jq --arg PORTAINER_ADMIN_PASSWORD "$PORTAINER_ADMIN_PASSWORD" '.|(if $PORTAINER_ADMIN_PASSWORD != "" and .kind == "Deployment" then .spec.template.spec.containers[0].args[0] = "--admin-password"  else . end)' |   \
   jq --arg PORTAINER_ADMIN_PASSWORD "$PORTAINER_ADMIN_PASSWORD" '.|(if $PORTAINER_ADMIN_PASSWORD != "" and .kind == "Deployment" then .spec.template.spec.containers[0].args[1] = $PORTAINER_ADMIN_PASSWORD  else . end)' |   \
   jq '.|(if .kind == "Deployment" then .spec.template.spec.tolerations = [{"key":"CriticalAddonsOnly","operator":"Exists"},{"key":"node-role.kubernetes.io/master","operator":"Exists","effect":"NoSchedule"},{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}] else . end)' | \
   sudo -E kubectl apply -f -

#   jq \
#    --arg http_proxy "$http_proxy" \
#    --arg https_proxy "$https_proxy" \
#    --arg no_proxy "$no_proxy,kubernetes.default.svc,$MASTER_IP" \
#   '.|(if .kind == "Deployment" then .spec.template.spec.containers[0].env = [{"name":"HTTP_PROXY","value":$http_proxy},{"name":"HTTPS_PROXY","value":$http_proxy},{"name":"NO_PROXY","value":$no_proxy}] else . end)' | \

test_result=1
timeout=$DEFAULT_TIMEOUT
until [ "$timeout" -le 0 -o "$test_result" -eq "0" ] ; do
 ( sudo -E kubectl rollout status  deployment/portainer -n portainer -w  --timeout=${DEFAULT_TIMEOUT}s )
 test_result=$?
 if [ "$test_result" -gt 0 ] ;then
     echo "Retry $timeout seconds: $test_result";
     (( timeout-- ))
     sleep 1
 fi
done
if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: portainer not ready $test_result"
        exit $test_result
fi

#
# install ingressroute for portainer
#
export PORTAINER_HOST_REGEXP="${PORTAINER_HOST_REGEXP:-portainer}"
#   jq \
#    --arg PORTAINER_HOST_REGEXP "$PORTAINER_HOST_REGEXP" \
#    '.|(if .kind == "IngressRoute" then .spec.routes[0].match = "HostRegexp(`"+$PORTAINER_HOST_REGEXP+"`)" else . end)'  | \

sudo -E kubectl create --dry-run="client" -o json \
    -f https://raw.githubusercontent.com/pli01/terraform-outscale-vpc/main/examples/k3s-kube-cluster/kubernetes-portainer-ingressroute.yml | \
   sudo -E kubectl apply -f -

echo "# DEBUG end k3-master.sh $(date)"
exit 0
