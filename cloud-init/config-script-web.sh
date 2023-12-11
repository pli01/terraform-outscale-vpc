#!/bin/bash

node_number=$(curl -s http://169.254.169.254/latest/meta-data/tags/Name |sed -e 's/[^0-9]*//g' )
availability_zone=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone  |sed -e 's/[^0-9]..//g')

colors=("blue" "red" "green" "yellow" "black")
node_color=${colors[node_number]}
dest="/var/www/html/index.html"

apt-get update -qy
apt-get install -qy lighttpd
( cd /etc/lighttpd/conf-enabled
  ln -sf ../conf-available/11-extforward.conf .
  ln -sf ../conf-available/10-accesslog.conf .
)

echo "<html><body style=\"background-color:${node_color};color:white;text-align:center;font-size:80px;\">Node ${node_number} ${availability_zone}</body></html>" > $dest
service lighttpd restart

echo "Hello World! I'm starting up now" > $HOME/out
