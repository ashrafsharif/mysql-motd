#!/bin/bash
## Generate important MySQL status into motd
## Also works as as cron, with -cron (require https://github.com/fabianonline/telegram.sh)

CRON=0
if [ ! -z $1 ]; then
	[ $1 == '-cron' ] && CRON=1
fi
HOSTNAME=$(hostname)
UPTIME=$(uptime -p)
MYSQL_COMMAND='mysql --connect-timeout=3 -A -Bse'
MYSQL_READONLY=$(${MYSQL_COMMAND} 'SHOW GLOBAL VARIABLES LIKE "read_only"' | awk {'print $2'})
TIER='Production'
PREFER_ROLE='Slave'
#PREFER_ROLE='Slave'
MAIN_IP=$(hostname -I)
CHECK_MYSQL_REPLICATION=$(${MYSQL_COMMAND} 'SHOW SLAVE STATUS\G' | egrep 'Slave_.*_Running: Yes$')
MYSQL_MASTER=$(${MYSQL_COMMAND} 'SHOW SLAVE STATUS\G' | grep Master_Host | awk {'print $2'})
MYSQL_UPTIME=$(${MYSQL_COMMAND} 'SELECT TIME_FORMAT(SEC_TO_TIME(VARIABLE_VALUE ),"%Hh %im")  AS Uptime FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME="Uptime"')
alert_dir=/usr/local/src
TELEGRAM=$(which telegram)

bold=$(tput bold)
red=$(tput setaf 1)
green=$(tput setaf 2)
normal=$(tput sgr0)

function send_alert()
{
	local alert_id=$1
	local notification=$*
	local alert_path=$alert_dir/$alert_id

	if [ $alert_id -eq 000 ]; then
		$TELEGRAM "Alarm cleared"
	else
		if [ ! -e $alert_path ]; then
			touch $alert_path
	                $TELEGRAM "${notification}"
		fi
	fi
}

MYSQL_SHOW=1
if [ $MYSQL_READONLY == 'ON' ]; then
        CURRENT_MYSQL_ROLE='Slave'
        if ${MYSQL_COMMAND} 'SHOW SLAVE STATUS\G' | egrep 'Slave_.*_Running: Yes$' &>/dev/null ; then
                lag=$(${MYSQL_COMMAND} 'SHOW SLAVE STATUS\G' | egrep 'Seconds_Behind_Master:' | awk {'print $2'})
                if [ $lag -eq 0 ]; then
                        REPLICATION_STATUS="${green}Healthy  "
			if [ $CRON -eq 1 ]; then
				[ -e $alert_dir/100 ] && rm -Rf $alert_dir/100 && send_alert 000
				[ -e $alert_dir/101 ] && rm -Rf $alert_dir/101 && send_alert 000
				[ -e $alert_dir/102 ] && rm -Rf $alert_dir/102 && send_alert 000
			fi
                else
                        REPLICATION_STATUS="${red}Lagging ${lag}s"
			[ $CRON -eq 1 ] && send_alert 101 "Replication is lagging: $lag s"
                fi
        else
                REPLICATION_STATUS=${red}Unhealthy
		[ $CRON -eq 1 ] && send_alert 102 "Replication is broken."
        fi

elif [ $MYSQL_READONLY == 'OFF' ]; then
        CURRENT_MYSQL_ROLE='Master'
        SLAVE_HOSTS=$(${MYSQL_COMMAND} 'SHOW SLAVE HOSTS' | awk {'print $2'})
	if [ $CRON -eq 1 ]; then
		[ -e $alert_dir/100 ] && rm -Rf $alert_dir/100 && send_alert 000
	fi
else
        MYSQL_SHOW=0
	[ $CRON -eq 1 ] && send_alert 100 "It looks like MySQL is down"
fi

if [ $TIER == 'Production' ]; then
        TIER=${green}Production
fi

if [ $PREFER_ROLE == $CURRENT_MYSQL_ROLE ]; then
        MYSQL_ROLE=${green}$CURRENT_MYSQL_ROLE
else
        MYSQL_ROLE=${red}$CURRENT_MYSQL_ROLE
fi

echo
echo "HOST INFO"
echo "========="
echo -e "  Hostname          : ${bold}$HOSTNAME${normal} \t\t Server Uptime  : ${bold}$UPTIME${normal}"
echo -e "  IP Address        : ${bold}$MAIN_IP${normal} \t Tier           : ${bold}$TIER${normal}"
echo
if [ $MYSQL_SHOW -eq 1 ]; then
echo "MYSQL STATE"
echo "==========="
echo -e "  Current role      : ${bold}$MYSQL_ROLE${normal} \t\t Read-only      : ${bold}$MYSQL_READONLY${normal}"
echo -e "  Preferred role    : ${bold}$PREFER_ROLE${normal} \t\t DB Uptime      : ${bold}$MYSQL_UPTIME${normal}"
if [ $CURRENT_MYSQL_ROLE == 'Slave' ]; then
echo -e "  Replication state : ${bold}$REPLICATION_STATUS${normal} \t Current Master : ${bold}$MYSQL_MASTER${normal}"
else
echo -e "  Slave Hosts(s)    : "
for i in $SLAVE_HOSTS; do
echo -e "      - ${bold}$i${normal} \t"; done
fi
echo
fi
