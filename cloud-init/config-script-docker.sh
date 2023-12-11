#!/bin/bash
set -e -o pipefail
echo "# DEBUG start docker.sh $(date)"
cloud_user=outscale
libdir=/home/$cloud_user

# Load config
[ -f ${libdir}/config.cfg ] && source ${libdir}/config.cfg

export docker_version="${docker_version:-docker-ce}"
export docker_compose_version="${docker_compose_version:-2.23.3}"

cat <<EOF > /etc/apt/apt.conf.d/00InstallRecommends
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
chown root:root /etc/apt/apt.conf.d/00InstallRecommends
chmod 0644  /etc/apt/apt.conf.d/00InstallRecommends

# disable unattended-upgrades
systemctl stop unattended-upgrades
systemctl disable unattended-upgrades
apt-get purge -qy unattended-upgrades

mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" },
  "mtu": 1450,
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
chown root:root /etc/docker/daemon.json
chmod 0644 /etc/docker/daemon.json


PACKAGES="sudo curl jq apt-transport-https ca-certificates curl software-properties-common gnupg make git unzip python3-pip"

DEFAULT_TIMEOUT=${DEFAULT_TIMEOUT:-1200}
test_result=1
timeout=$DEFAULT_TIMEOUT
until [ "$timeout" -le 0 -o "$test_result" -eq "0" ] ; do
  ( apt-get -q update && apt-get install -qy --no-install-recommends $PACKAGES )
  test_result=$?
  if [ "$test_result" -gt 0 ] ;then
     echo "Retry $timeout seconds: $test_result";
     (( timeout-- ))
     sleep 1
  fi
done
if [ "$test_result" -gt 0 ] ;then
        test_status=ERROR
        echo "$test_status: apt-get failed: network not ready $test_result"
        exit $test_result
fi

# Install Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
chmod a+r /etc/apt/trusted.gpg.d/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/docker.gpg] \
       https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker-ce.list > /dev/null

export DEBIAN_FRONTEND=noninteractive
apt-get update -qy
apt-get install -qy ${docker_version} docker-ce-cli containerd.io
usermod -aG docker $cloud_user

systemctl daemon-reload
systemctl enable docker
systemctl restart docker

# Install docker-compose
curl -fsSL https://github.com/docker/compose/releases/download/v${docker_compose_version}/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose && \
chmod +x /usr/local/bin/docker-compose

# check
docker version || exit $?
docker-compose  version || exit $?
id $cloud_user  | grep '(docker)' || exit $?

echo "# DEBUG end docker.sh $(date)"
