#!/bin/bash
support_service=( pihole/pihole:latest adguard/adguardhome:arm64-edge )
support_func="start|stop|restart|update|status"
service_array=()

list() {
	counter=1
	for name in "${support_service[@]}"
	do
		echo "./${0} ${support_func} ${counter}|${name%%'/'*}|${name}"
		((counter++))
	done
	echo "./${0} ${support_func} all"
}

checkargv() {
	service_array=()
	if [ ${1,,} == "all" ];
	then
		service_array=(${support_service[@]})
	else
		counter=1
		for name in "${support_service[@]}"
		do
			if [[ ("${1}" == "${counter}") || ("${1%%'/'*}" == "${name%%'/'*}") || (${1} == ${name}) ]];
			then
				service_array=( ${name} )
				break
			fi
			((counter++))
		done
	fi
	if [ ${#service_array[@]} -eq 0 ];
	then
		list
		exit 2
	fi
}

start() {
	echo "start [${1}]"
	docker pull ${1}
	lanip=$(ip -4 addr show eth0 | grep -Po 'inet \K[\d.]+')
	case ${1} in
		"pihole/pihole:latest")
			docker run -d \
				--name pihole \
				--sysctl net.ipv6.conf.all.disable_ipv6=1 \
				-p ${lanip}:853:53/tcp -p ${lanip}:853:53/udp \
				-e TZ="Asia/Taipei" \
				-e IPv6=False \
				-e DNS1="208.67.222.222" \
				-e DNS2="208.67.220.220" \
				-v "$(pwd)/etc-pihole/:/etc/pihole/" \
				-v "$(pwd)/etc-dnsmasq.d/:/etc/dnsmasq.d/" \
				--restart=unless-stopped \
				${1}
		;;
		"adguard/adguardhome:arm64-edge")
			mkdir $(pwd)/etc-adguardconf/
			echo 'bind_host: 0.0.0.0
bind_port: 3000
auth_name: alarm
auth_pass: 3146alarm
language: ""
rlimit_nofile: 0
dns:
  bind_host: 0.0.0.0
  port: 53
  protection_enabled: true
  filtering_enabled: true
  blocking_mode: mxdomain
  blocked_response_ttl: 10
  querylog_enabled: true
  ratelimit: 20
  ratelimit_whitelist: []
  refuse_any: true
  bootstrap_dns:
  - 1.1.1.1:53
  all_servers: false
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts: []
  parental_sensitivity: 13
  parental_enabled: true
  safesearch_enabled: true
  safebrowsing_enabled: true
  resolveraddress: ""
  upstream_dns:
  - 10.10.10.10:853
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  certificate_chain: ""
  private_key: ""
filters:
- enabled: true
  url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
  name: AdGuard Simplified Domain Names filter
  id: 1
- enabled: true
  url: https://adaway.org/hosts.txt
  name: AdAway
  id: 2
- enabled: true
  url: https://hosts-file.net/ad_servers.txt
  name: hpHosts - Ad and Tracking servers only
  id: 3
- enabled: true
  url: https://www.malwaredomainlist.com/hostslist/hosts.txt
  name: MalwareDomainList.com Hosts List
  id: 4
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/2.txt
  name: Base filter
  id: 5
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/3.txt
  name: Tracking Protection filter
  id: 6
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/4.txt
  name: Social media filter
  id: 7
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/14.txt
  name: Annoyances filter
  id: 8
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/10.txt
  name: Filter unblocking search ads and self-promotions
  id: 9
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/5.txt
  name: Experimental filter
  id: 10
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/11.txt
  name: Mobile ads filter
  id: 11
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/12.txt
  name: Safari filter
  id: 12
- enabled: true
  url: https://filters.adtidy.org/extension/chromium/filters/15.txt
  name: Simplified domain names filter
  id: 13
user_rules: []
dhcp:
  enabled: false
  interface_name: "eth0"
  gateway_ip: "10.10.10.10"
  subnet_mask: "255.255.255.0"
  range_start: "10.10.10.50"
  range_end: "10.10.10.80"
  lease_duration: 86400
  icmp_timeout_msec: 1000
clients: []
log_file: ""
verbose: false
schema_version: 3' > $(pwd)/etc-adguardconf/AdGuardHome.yaml
			if [ -d $(pwd)/adguardwork ];
			then
				mkdir $(pwd)/etc-adguardwork/
				cp -R $(pwd)/adguardwork/* $(pwd)/etc-adguardwork/
			fi
			docker run -d \
				--name adguardhome \
				--sysctl net.ipv6.conf.all.disable_ipv6=1 \
				-p ${lanip}:5353:53/tcp -p ${lanip}:5353:53/udp \
				-v "$(pwd)/etc-adguardwork/:/opt/adguardhome/work" \
				-v "$(pwd)/etc-adguardconf/:/opt/adguardhome/conf" \
				${1}
		;;
	esac
}

stop() {
	echo "stop [${1}]"
	container=$(docker ps -aq -f "ancestor=${1}")
	if [ ${#container} -eq 0 ];
	then
		continue
	fi
	docker container stop ${container}
	docker container rm ${container}
	case ${1} in
		"pihole/pihole:latest")
			rm -rf $(pwd)/etc-dnsmasq.d $(pwd)/etc-pihole
		;;
		"adguard/adguardhome:arm64-edge")
			rm -rf $(pwd)/etc-adguardconf $(pwd)/etc-adguardwork
		;;
	esac
}

update() {
	echo "update [${1}]"
	case ${1} in
		"pihole/pihole:latest")
			status ${1}
			if [ $? -eq 1 ];
			then
				docker exec -it $(docker ps -aq -f "ancestor=${1}") pihole -g
			fi
		;;
		"adguard/adguardhome:arm64-edge")
			rm -rf $(pwd)/adguardwork/
			mkdir -p $(pwd)/adguardwork/data/filters/
			sed -ne "s/url: \(.*\)/\1/p" $(pwd)/etc-adguardconf/AdGuardHome.yaml |awk "{print \"wget -O adguardwork/data/filters/\"NR\".txt\"\$0\"\nwhile [ \$(wc -c <adguardwork/data/filters/\"NR\".txt) -eq 0 ]; do\n\twget -O adguardwork/data/filters/\"NR\".txt\"\$0\"\ndone\"}" > run.sh
			stop ${1}
			sh run.sh
			rm run.sh
			start ${1}
		;;
	esac
}

status() {
	container=$(docker ps -aq -f "ancestor=${1}")
	if [ ${#container} -eq 0 ];
	then
		echo "Status [${1}]: no running."
		return 0
	fi
	case ${1} in
		"pihole/pihole:latest")
			if [ "$(docker inspect -f "{{.State.Health.Status}}" ${container})" == "healthy" ] ; then
				echo -e "Status [${1}]: running.\n$(docker logs pihole 2> /dev/null | grep 'password:') for your pi-hole"
				return 1
			fi
		;;
		"adguard/adguardhome:arm64-edge")
			if [ "$(docker inspect -f "{{.State.Status}}" ${container})" == "running" ] ; then
				echo "Status [${1}]: $(docker inspect -f "{{.State.Status}}" ${container}), $(docker inspect -f "{{.State.Running}}" ${container})"
				return 1
			fi
		;;
	esac
	echo "Status [${1}]: no running."
	return 0
}

if [ $# -lt 2 ];
then
	list
	exit 1
fi

case "${1}" in
	"start" | "stop" | "status" | "update")
		checkargv ${2}
		for name in "${service_array[@]}"
		do
			${1} ${name}
		done
	;;
	"restart")
		checkargv ${2}
		for name in "${service_array[@]}"
		do
			stop ${name}
			start ${name}
		done
	;;
	*)
		list
		exit 2
	;;
esac
exit 0
