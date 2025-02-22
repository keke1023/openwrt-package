#!/bin/sh

CONFIG=passwall
LOCK_FILE=/var/lock/passwall_test.lock

get_date() {
	echo "$(date "+%Y-%m-%d %H:%M:%S")"
}

test_url() {
	status=$(/usr/bin/curl -I -o /dev/null -s --connect-timeout 5 -w %{http_code} "$1" | grep 200)
	[ "$?" != 0 ] && {
		status=$(/usr/bin/wget --no-check-certificate --spider --timeout=5 "$1")
	}
	echo $status
}

test_proxy() {
	result=0
	status=$(test_url "https://www.google.com")
	if [ "$status" = "200" ]; then
		result=0
	else
		status2=$(test_url "https://www.baidu.com")
		if [ "$status2" = "200" ]; then
			result=1
		else
			result=2
		fi
	fi
	echo $result
}

test_auto_switch() {
	if [ -f "/var/etc/passwall/tcp_server_id" ]; then
		TCP_NODES1=$(cat /var/etc/passwall/tcp_server_id)
	else
		rm -f $LOCK_FILE
		exit 1
	fi

	failcount=1
	while [ "$failcount" -lt "6" ]; do
		status=$(test_proxy)
		if [ "$status" == 2 ]; then
			echo "$(get_date): 自动切换检测：无法连接到网络，请检查网络是否正常！" >>/var/log/passwall.log
			break
		elif [ "$status" == 1 ]; then
			echo "$(get_date): 自动切换检测：第$failcount次检测异常" >>/var/log/passwall.log
			let "failcount++"
			[ "$failcount" -ge 6 ] && {
				echo "$(get_date): 自动切换检测：检测异常，切换节点" >>/var/log/passwall.log
				TCP_NODES=$(uci get passwall.@auto_switch[0].tcp_node)
				has_backup_server=$(echo $TCP_NODES | grep $TCP_NODES1)
				setserver=
				if [ -z "$has_backup_server" ]; then
					setserver=$(echo $TCP_NODES | awk -F ' ' '{print $1}')
				else
					setserver=$TCP_NODES1
					flag=0
					for server in $has_backup_server; do
						if [ "$flag" == 0 ]; then
							if [ "$TCP_NODES1" == "$server" ]; then
								flag=1
								continue
							fi
						fi
						if [ "$flag" == 1 ]; then
							flag=2
							continue
						fi
						if [ "$flag" == 2 ]; then
							setserver=$server
							break
						fi
					done
				fi
				rm -f $LOCK_FILE
				uci set passwall.@global[0].tcp_node=$setserver
				uci commit passwall
				/etc/init.d/passwall restart
				exit 1
			}
			sleep 5s
		elif [ "$status" == 0 ]; then
			echo "$(get_date): 自动切换检测：检测正常" >>/var/log/passwall.log
			break
		fi
	done
}

test_reconnection() {
	failcount=1
	while [ "$failcount" -lt "6" ]; do
		status=$(test_proxy)
		if [ "$status" == 2 ]; then
			echo "$(get_date): 掉线重连检测：无法连接到网络，请检查网络是否正常！" >>/var/log/passwall.log
			break
		elif [ "$status" == 1 ]; then
			echo "$(get_date): 掉线重连检测：第$failcount次检测异常" >>/var/log/passwall.log
			let "failcount++"
			[ "$failcount" -ge 6 ] && {
				echo "$(get_date): 掉线重连检测：检测异常，重启服务" >>/var/log/passwall.log
				rm -f $LOCK_FILE
				/etc/init.d/passwall restart
				exit 1
			}
			sleep 5s
		elif [ "$status" == 0 ]; then
			echo "$(get_date): 掉线重连检测：检测正常" >>/var/log/passwall.log
			break
		fi
	done
}

start() {
	#防止并发执行
	if [ -f "$LOCK_FILE" ]; then
		exit 1
	else
		touch $LOCK_FILE
	fi

	is_auto_switch=$(uci show $CONFIG.@auto_switch[0] | grep "tcp_node")
	if [ -z "$is_auto_switch" ]; then
		test_reconnection
	else
		test_auto_switch
	fi

	rm -f $LOCK_FILE
	exit
}

case $1 in
test_url)
	test_url $2
	;;
*)
	start
	;;
esac