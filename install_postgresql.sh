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
MASTERIP=\"\"
SUBNETADDRESS=\"\"
NODETYPE=\"\"
REPLICATORPASSWORD=\"\"
CLUSTERNAME=\"\"

#Loop through options passed
while getopts :m:s:t:p:c: optname; do
    log \"Option $optname set with value ${OPTARG}\"
  case $optname in
    m)
      MASTERIP=${OPTARG}
      ;;
  	s) #Data storage subnet space
      SUBNETADDRESS=${OPTARG}
      ;;
    t) #Type of node (MASTER/SLAVE)
      NODETYPE=${OPTARG}
      ;;
    p) #Replication Password
      REPLICATORPASSWORD=${OPTARG}
      ;;
	c) #Cluster name
      CLUSTERNAME=${OPTARG}
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

export PGPASSWORD=$REPLICATORPASSWORD
echo 'export PGPASSWORD=$REPLICATORPASSWORD' >> ~/.bash_profile
echo 'export CLUSTERNAME=$CLUSTERNAME' >> ~/.bash_profile


logger \" NOW=$now MASTERIP=$MASTERIP SUBNETADDRESS=$SUBNETADDRESS NODETYPE=$NODETYPE \"

install_stolon() {

logger \"Start installing of Stolon...\"
mkdir ~/stolon
logger \"Made Stolon install directory return: $?\"
cd ~/stolon
logger \"Changed to Stolon install directory return: $?\"

wget https://github.com/oscarmherrera/azure_postgres/raw/master/stolon/debian/stolon-keeper -O stolon-keeper
logger \"Downloaded stolon-keeper return: $?\"

wget https://github.com/oscarmherrera/azure_postgres/raw/master/stolon/debian/stolon-sentinel -O stolon-sentinel
logger \"Downloaded stolon-sentinel return: $?\"

wget https://github.com/oscarmherrera/azure_postgres/raw/master/stolon/debian/stolon-proxy -O stolon-proxy
logger \"Downloaded stolon-proxy return: $?\"

wget https://github.com/oscarmherrera/azure_postgres/raw/master/stolon/debian/stolonctl -O stolonctl
logger \"Downloaded stolonctl return: $?\"

cp ./stolon-keeper /usr/bin/stolon-keeper
logger \"Copied stolon-keeper to /usr/bin return: $?\"
chmod +x /usr/bin/stolon-keeper
logger \"chmod stolon-keeper return: $?\"

cp ./stolon-sentinel /usr/bin/stolon-sentinel
logger \"Copied stolon-sentinel to /usr/bin return: $?\"
chmod +x /usr/bin/stolon-sentinel
logger \"chmod stolon-sentinel return: $?\"

cp ./stolon-proxy /usr/bin/stolon-proxy
logger \"Copied stolon-proxy to /usr/bin return: $?\"
chmod +x /usr/bin/stolon-proxy
logger \"chmod stolon-sentinel return: $?\"

cp ./stolonctl /usr/bin/stolonctl
logger \"Copied stolonctl to /usr/bin return: $?\"
chmod +x /usr/bin/stolonctl
logger \"chmod stolon-sentinel return: $?\"

echo "deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main" >> /etc/apt/sources.list.d/pgdg.list

}

install_postgresql_service() {

	logger \"Start installing PostgreSQL...\"
	# Re-synchronize the package index files from their sources. An update should always be performed before an upgrade.
	logger \"Start Update of Packages...\"
	# apt-get -o Acquire::ForceIPv4=true -y update
	logger \"Finished Update of Packages...\"

# \"deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -sc)-pgdg main\"
	# Install PostgreSQL if it is not yet installed
	if [ $(dpkg-query -W -f='${Status}' postgresql 2>/dev/null | grep -c \"ok installed\") -eq 0 ];
	then

		add-apt-repository \"deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main 
		wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
		apt-get update
	  	apt-get -y install postgresql-9.6 
	fi
	
	logger \"Done installing PostgreSQL...\"

}

setup_datadisks() {

	MOUNTPOINT=\"/mnt/resource/datadisks/disk1\"

	# Move database files to the striped disk
	if [ -L /var/lib/postgresql/9.6/main ];
	then
		logger \"Symbolic link from /var/lib/postgresql/9.6/main already exists\"
		echo \"Symbolic link from /var/lib/postgresql/9.6/main already exists\"
	else
		logger \"Moving  data to the $MOUNTPOINT/main\"
		echo \"Moving PostgreSQL data to the $MOUNTPOINT/main\"
		service postgresql stop
		# mkdir $MOUNTPOINT/main
		mv -f /var/lib/postgresql/9.6/main $MOUNTPOINT

		# Create symbolic link so that configuration files continue to use the default folders
		logger \"Create symbolic link from /var/lib/postgresql/9.6/main to $MOUNTPOINT/main\"
		ln -s $MOUNTPOINT/main /var/lib/postgresql/9.6/main

        chown postgres:postgres $MOUNTPOINT/main
        chmod 0700 $MOUNTPOINT/main
	fi
}

configure_streaming_replication() {
	logger \"Starting configuring PostgreSQL streaming replication...\"
	
	# Configure the MASTER node
	if [ \"$NODETYPE\" == \"MASTER\" ];
	then
		logger \"Create user replicator...\"
		echo \"CREATE USER replicator WITH REPLICATION PASSWORD '$PGPASSWORD';\"
		sudo -u postgres psql -c \"CREATE USER replicator WITH REPLICATION PASSWORD '$PGPASSWORD';\"
	fi
	# Stop service
	service postgresql stop

	# Update configuration files
	cd /etc/postgresql/9.6/main

	if grep -Fxq \"# install_postgresql.sh\" pg_hba.conf
	then
		logger \"Already in pg_hba.conf\"
		echo \"Already in pg_hba.conf\"
	else
		# Allow access from other servers in the same subnet
		echo \"\" >> pg_hba.conf
		echo \"# install_postgresql.sh\" >> pg_hba.conf
		echo \"host replication replicator $SUBNETADDRESS md5\" >> pg_hba.conf
		echo \"hostssl replication replicator $SUBNETADDRESS md5\" >> pg_hba.conf
		echo \"\" >> pg_hba.conf
			
		logger \"Updated pg_hba.conf\"
		echo \"Updated pg_hba.conf\"
	fi

	if grep -Fxq \"# install_postgresql.sh\" postgresql.conf
	then
		logger \"Already in postgresql.conf\"
		echo \"Already in postgresql.conf\"
	else
		# Change configuration including both master and slave configuration settings
		echo \"\" >> postgresql.conf
		echo \"# install_postgresql.sh\" >> postgresql.conf
		echo \"listen_addresses = '*'\" >> postgresql.conf
		echo \"wal_level = hot_standby\" >> postgresql.conf
		echo \"max_wal_senders = 10\" >> postgresql.conf
		echo \"wal_keep_segments = 500\" >> postgresql.conf
		echo \"checkpoint_segments = 8\" >> postgresql.conf
		echo \"archive_mode = on\" >> postgresql.conf
		echo \"archive_command = 'cd .'\" >> postgresql.conf
		echo \"hot_standby = on\" >> postgresql.conf
		echo \"\" >> postgresql.conf
		
		logger \"Updated postgresql.conf\"
		echo \"Updated postgresql.conf\"

		/usr/bin/stolon-sentinel --cluster-name=${CLUSTERNAME} --store-backend=etcdv2 --store-endpoints=http://10.10.6.200:2379 init
		logger \"Starting up lead sentinel clustername - ${CLUSTERNAME} return: $?\"
	fi

	# Synchronize the slave
	if [ \"$NODETYPE\" == \"SLAVE\" ];
	then
		# Remove all files from the slave data directory
		logger \"Remove all files from the slave data directory\"
		sudo -u postgres rm -rf /datadisks/disk1/main

		# Make a binary copy of the database cluster files while making sure the system is put in and out of backup mode automatically
		logger \"Make binary copy of the data directory from master\"
		sudo PGPASSWORD=$PGPASSWORD -u postgres pg_basebackup -h $MASTERIP -D /datadisks/disk1/main -U replicator -x
		 
		# Create recovery file
		logger \"Create recovery.conf file\"
		cd /var/lib/postgresql/9.6/main/
		
		sudo -u postgres echo \"standby_mode = 'on'\" > recovery.conf
		sudo -u postgres echo \"primary_conninfo = 'host=$MASTERIP port=5432 user=replicator password=$PGPASSWORD'\" >> recovery.conf
		sudo -u postgres echo \"trigger_file = '/var/lib/postgresql/9.6/main/failover'\" >> recovery.conf

		/usr/bin/stolon-sentinel --cluster-name ${CLUSTERNAME} --store-backend=etcdv2 --store-endpoints=http://10.10.6.200:2379
		logger \"Starting up standby sentinel clustername - ${CLUSTERNAME} return: $?\"
	fi
	
	logger \"Done configuring PostgreSQL streaming replication\"
}

init_stolon() {
	/usr/bin/stolonctl --cluster-name ${CLUSTERNAME} --store-backend etcdv2 --log-level debug --store-endpoints http://10.10.6.200:2379 init
	logger \"Initializing stolon cluster with clustername - ${CLUSTERNAME} return: $?\"
}

start_stolon_keeper() {
		/usr/bin/stolon-keeper --cluster-name ${CLUSTERNAME} \
		--store-backend etcdv2 \
		--store-endpoints http://10.10.6.200:2379 \
		--uid postgres \
		--data-dir /datadisks/disk1/main \
		--pg-su-password ${PGPASSWORD} \
		--pg-repl-username repluser \
		--pg-repl-password ${PGPASSWORD} \
		--pg-listen-address=127.0.0.1 \
		--log-level info &
		logger \"Starting up stolon keeper  clustername - ${CLUSTERNAME} return: $?\"

}

# MAIN ROUTINE
install_stolon

install_postgresql_service

setup_datadisks

init_stolon

start_stolon_keeper
#service postgresql start

configure_streaming_replication

#service postgresql start

set +x
