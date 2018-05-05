#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the \"Software\"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#
# Author: Full Scale 180 Inc.
set -x
# You must be root to run this script
if [ \"${UID}\" -ne 0 ];
then
    log \"Script executed without root permissions\"
    echo \"You must be root to run this program.\" >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM (If it does not exist add it)
grep -q \"${HOSTNAME}\" /etc/hosts
if [ $? == 0 ];
then
  echo \"${HOSTNAME}found in /etc/hosts\"
else
  echo \"${HOSTNAME} not found in /etc/hosts\"
  # Append it to the hsots file if not there
  echo \"127.0.0.1 ${HOSTNAME}\" >> /etc/hosts
fi

# Get today's date into YYYYMMDD format
now=$(date +\"%Y%m%d\")
 
# Get passed in parameters $1, $2, $3, $4, and others...
NODEID=\"\"
INFRA0=\"\"
INFRA1=\"\"
INFRA2=\"\"

#Loop through options passed
while getopts :n:1:2:3:k: optname; do
    log \"Option $optname set with value ${OPTARG}\"
  case $optname in
    n)
      NODEID=${OPTARG}
      ;;
  	1) #etcd cluser 0 ip address
      INFRA0=${OPTARG}
      ;;
    2) #etcd cluser 1 ip address
      INFRA1=${OPTARG}
      ;;
    3) #etcd cluser 2 ip address
      INFRA2=${OPTARG}
      ;;
    k) #etcd cluser key 
      KEY=${OPTARG}
      ;;
    h)  #show help
      help
      exit 3
      ;;
    \?) #unrecognized option - show help
      echo -e \\n\"Option -${BOLD}$OPTARG${NORM} not allowed.\"
      help
      exit 3
      ;;
  esac
done

PORT=2380

logger \" NOW=$now ETCD_INITIAL_CLUSTER=${ETCD_INITIAL_CLUSTER} \"

install_etcd_service() {
	logger \"Start installing etcd...\"
	# Re-synchronize the package index files from their sources. An update should always be performed before an upgrade.
	logger \"Start Update of Packages...\"
	apt-get -o Acquire::ForceIPv4=true -y update
	logger \"Finished Update of Packages...\"

	mkdir ~/etcd_install
	cd ~/etcd_install
	sudo apt-get install curl -y
	curl -L  https://github.com/coreos/etcd/releases/download/v2.2.2/etcd-v2.2.2-linux-amd64.tar.gz -o etcd-v2.2.2-linux-amd64.tar.gz
	tar xzvf etcd-v2.2.2-linux-amd64.tar.gz
	rm etcd-v2.2.2-linux-amd64.tar.gz
        cd etcd-v2.2.2-linux-amd64
        cp ./etcd /usr/sbin
        cp ./etcdctl /usr/sbin 
        curl -L https://raw.githubusercontent.com/oscarmherrera/azure_postgres/master/etcd/etcd.template -o etcd.initd
        if [[ "$NODEID" -eq 0 ]]; then
        sed -i -e "s/\${CLUSTER_KEY}/${KEY}/" -e "s/\${node0Name}/infra0/"  -e "s/\${PORT}/2378/" -e "s/\${node0IP}/$INFRA0/" -e "s/\${infra0IP}/$INFRA0/" -e "s/\${infra1IP}/$INFRA1/" -e "s/\${infra2IP}/$INFRA2/" etcd.initd
        fi

        if [[ "$NODEID" -eq 1 ]]; then
        sed -i -e "s/\${CLUSTER_KEY}/${KEY}/" -e "s/\${node1Name}/infra1/"  -e "s/\${PORT}/2378/" -e "s/\${node0IP}/$INFRA1/" -e "s/\${infra0IP}/$INFRA0/" -e "s/\${infra1IP}/$INFRA1/" -e "s/\${infra2IP}/$INFRA2/" etcd.initd
        fi

        if [[ "$NODEID" -eq 2 ]]; then
        sed -i -e "s/\${CLUSTER_KEY}/${KEY}/" -e "s/\${node2Name}/infra2/"  -e "s/\${PORT}/2378/" -e "s/\${node0IP}/$INFRA2/" -e "s/\${infra0IP}/$INFRA0/" -e "s/\${infra1IP}/$INFRA1/" -e "s/\${infra2IP}/$INFRA2/" etcd.initd
        fi

	cp ~/etcd_install/etcd-v2.2.2-linux-amd64/etcd.initd /etc/init.d/etcd

        rm -rf ~/etcd_install
	
	logger \"Done installing Etcd...\"
}


# MAIN ROUTINE
install_etcd_service


set +x
