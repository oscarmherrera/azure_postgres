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

#Format the data disk
bash vm-disk-utils-0.1.sh -s

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
while getopts :n:1:2:3: optname; do
    log \"Option $optname set with value ${OPTARG}\"
  case $optname in
    n)
      NODEID=${OPTARG}
      ;;
  	1) #Data storage subnet space
      INFRA0=${OPTARG}
      ;;
    2) #Type of node (MASTER/SLAVE)
      INFRA1=${OPTARG}
      ;;
    3) #Replication Password
      INFRA2=${OPTARG}
      ;;
    h)  #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n\"Option -${BOLD}$OPTARG${NORM} not allowed.\"
      help
      exit 2
      ;;
  esac
done

PORT=2380
export ETCD_INITIAL_CLUSTER="infra0=${INFR0}:${PORT},infra1=${INFR1}:${PORT},infra2=${INFR2}:${PORT}"
export ETCD_INITIAL_CLUSTER_STATE=new

logger \" NOW=$now ETCD_INITIAL_CLUSTER=${ETCD_INITIAL_CLUSTER} \"

install_etcd_service() {
	logger \"Start installing etcd...\"
	# Re-synchronize the package index files from their sources. An update should always be performed before an upgrade.
	logger \"Start Update of Packages...\"
	# apt-get -o Acquire::ForceIPv4=true -y update
	logger \"Finished Update of Packages...\"

  apt-get -y install etcd
	
	logger \"Done installing Etcd...\"
}


# MAIN ROUTINE
install_etcd_service


set +x
