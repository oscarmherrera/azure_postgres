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

PEERPORT=2380

logger \" NOW=$now start parameters -n ${NODEID} -1 ${INFRA0} -2 ${INFRA1} -3 ${INFRA2} -k ${KEY}\"
export ETCD_INITIAL_CLUSTER="infra0=http://${INFRA0}:${PORT},infra1=http://${INFRA1}:${PORT},infra2=http://${INFRA2}:${PORT}"
logger \"ETCD INITIAL CLUSER: ${ETCD_INITIAL_CLUSTER}\"
echo ${ETCD_INITIAL_CLUSTER}
echo "export ETCD_INITIAL_CLUSTER='${ETCD_INITIAL_CLUSTER}'" >> ~/.profile

export ETCD_INITIAL_CLUSTER_STATE=new
echo 'export ETCD_INITIAL_CLUSTER_STATE=new' >> ~/.profile


install_etcd_service() {
  sleep 10s
	logger \"Start installing etcd...\"
	# Re-synchronize the package index files from their sources. An update should always be performed before an upgrade.
	logger \"Start Update of Packages...\"
	apt-get -o Acquire::ForceIPv4=true -y update
  apt-get -o Acquire::ForceIPv4=true install -y apt-transport-https
	apt-get -o Acquire::ForceIPv4=true install -y curl
  logger \"Installed curl return: $?\"
	logger \"Finished Update of Packages...\"

	mkdir ~/etcd_install
  logger \"Make dir etcd_install return $?\"
	cd ~/etcd_install
  logger \"cd dir etcd_install return $?\"
	wget -t 10 https://github.com/coreos/etcd/releases/download/v2.2.2/etcd-v2.2.2-linux-amd64.tar.gz -O etcd-v2.2.2-linux-amd64.tar.gz
  logger \"Downloaded etcd return: $?\"
  tar xzvf etcd-v2.2.2-linux-amd64.tar.gz
	rm etcd-v2.2.2-linux-amd64.tar.gz
        cd etcd-v2.2.2-linux-amd64
        cp ./etcd /usr/sbin
        logger \"copied etcd to /usr/sbin return: $?\"
        cp ./etcdctl /usr/sbin 
        logger \"copied etcdctl to /usr/sbin return: $?\"
        wget -t 10 https://raw.githubusercontent.com/oscarmherrera/azure_postgres/master/etcd/etcd.template -O etcd.initd
        logger \"Downloaded the template return: $?\"

        if [[ "$NODEID" -eq 0 ]]; then
        sed -i -e "s/\${CLUSTER_KEY}/${KEY}/" -e "s/\${nodeName}/infra0/"  -e "s/\${node0IP}/$INFRA0/" -e "s/\${infra0IP}/$INFRA0/" -e "s/\${infra1IP}/$INFRA1/" -e "s/\${infra2IP}/$INFRA2/" etcd.initd
        logger \"Finished replacement for infra0 return: $?\"
        fi

        if [[ "$NODEID" -eq 1 ]]; then
        sed -i -e "s/\${CLUSTER_KEY}/${KEY}/" -e "s/\${nodeName}/infra1/"  -e "s/\${node0IP}/$INFRA1/" -e "s/\${infra0IP}/$INFRA0/" -e "s/\${infra1IP}/$INFRA1/" -e "s/\${infra2IP}/$INFRA2/" etcd.initd
        logger \"Finished replacement for infra1 return: $?\"
        fi

        if [[ "$NODEID" -eq 2 ]]; then
        sed -i -e "s/\${CLUSTER_KEY}/${KEY}/" -e "s/\${nodeName}/infra2/"  -e "s/\${node0IP}/$INFRA2/" -e "s/\${infra0IP}/$INFRA0/" -e "s/\${infra1IP}/$INFRA1/" -e "s/\${infra2IP}/$INFRA2/" etcd.initd
        logger \"Finished replacement for infra0 return: $?\"
        fi

	      cp ~/etcd_install/etcd-v2.2.2-linux-amd64/etcd.initd /etc/init.d/etcd
        logger \"Copied init.d file return: $?\"

        chmod +x /etc/init.d/etcd
        systemctl enable etcd.service
        logger \"Enabled etcd service return: $?\"
        service etcd start
        logger \"Started etcd return: $?\"

        rm -rf ~/etcd_install
        #Eventually we have to set the firewall correctly but for now lets disable it
        systemctl disable firewall
	
	logger \"Done installing Etcd...\"
}


# MAIN ROUTINE
install_etcd_service

set +x
