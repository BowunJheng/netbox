#!/bin/bash
#openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx.key -out nginx.crt
support_service=( pihole/pihole:latest adguard/adguardhome:latest )
support_func="start|stop|restart|update|status"
service_array=()
adguardconf="AdGuardHome_v0.100.2.yaml"
piholeconf="adlists_20191218.list"

list() {
	counter=1
	for name in "${support_service[@]}"
	do
		if [[ $name == *"/"* ]];
		then
			echo "./${0} ${support_func} ${counter}|${name%%'/'*}|${name}"
		else
			echo "./${0} ${support_func} ${counter}|${name%%':'*}|${name}"
		fi
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
			if [[ ("${1}" == "${counter}") || ("${1%%'/'*}" == "${name%%'/'*}") || ("${1%%':'*}" == "${name%%':'*}") || (${1} == ${name}) ]];
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
	podman pull ${1}
	lanip=$(ip -4 addr show eth0 | grep -Po 'inet \K[\d.]+')
	podmanstr=""
	case ${1} in
		"pihole/pihole:latest")
			mkdir $(pwd)/etc-dnsmasq.d $(pwd)/etc-pihole
			podmanstr+="--name pihole "
			podmanstr+="-p 127.0.0.1:853:53/tcp -p 127.0.0.1:853:53/udp "
			#podmanstr+="-p 80:80/tcp "
			podmanstr+="-e TZ=Asia/Taipei "
			podmanstr+="-e IPv6=False "
			podmanstr+="-e DNS1=208.67.222.222 "
			podmanstr+="-e DNS2=208.67.220.220 "
			podmanstr+="-v $(pwd)/etc-pihole/:/etc/pihole/ "
			podmanstr+="-v $(pwd)/etc-dnsmasq.d/:/etc/dnsmasq.d/ "
			#podmanstr+="--restart=unless-stopped "
		;;
		"adguard/adguardhome:latest")
			mkdir $(pwd)/etc-adguardconf/
			cp $(pwd)/${adguardconf} $(pwd)/etc-adguardconf/AdGuardHome.yaml
			mkdir $(pwd)/etc-adguardwork/
			if [ -d $(pwd)/adguardwork ];
			then
				cp -R $(pwd)/adguardwork/* $(pwd)/etc-adguardwork/
			fi
			podmanstr+="--name adguardhome "
			podmanstr+="-p ${lanip}:53:53/tcp -p ${lanip}:53:53/udp "
			podmanstr+="-v $(pwd)/etc-adguardwork/:/opt/adguardhome/work/ "
			podmanstr+="-v $(pwd)/etc-adguardconf/:/opt/adguardhome/conf/ "
		;;
	esac
	podmanstr+="--sysctl net.ipv6.conf.all.disable_ipv6=1 "
	podman run -d \
		${podmanstr} \
		${1}
}

stop() {
	echo "stop [${1}]"
	container=$(podman ps -aq -f "ancestor=${1}")
	if [ ${#container} -eq 0 ];
	then
		continue
	fi
	podman container stop ${container}
	podman container rm ${container}
	case ${1} in
		"pihole/pihole:latest")
			rm -rf $(pwd)/etc-dnsmasq.d $(pwd)/etc-pihole
		;;
		"adguard/adguardhome:latest")
			rm -rf $(pwd)/etc-adguardconf $(pwd)/etc-adguardwork
		;;
	esac
}

update() {
	echo "update [${1}]"
	case ${1} in
		"pihole/pihole:latest")
      rm $(pwd)/etc-pihole/adlists.list
      cp $(pwd)/${piholeconf} $(pwd)/etc-pihole/adlists.list
			status ${1}
			if [ $? -eq 1 ];
			then
				podman exec -it $(podman ps -aq -f "ancestor=${1}") pihole -g
			fi
		;;
		"adguard/adguardhome:latest")
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
	container=$(podman ps -aq -f "ancestor=${1}")
	if [ ${#container} -eq 0 ];
	then
		echo "Status [${1}]: no running."
		return 0
	fi
	case ${1} in
		"pihole/pihole:latest")
			if [ "$(podman inspect -f "{{.State.Healthcheck.Status}}" ${container})" == "healthy" ] ; then
				echo -e "Status [${1}]: running.\n$(podman logs pihole 2> /dev/null | grep 'password:') for your pi-hole"
				return 1
			fi
		;;
		"adguard/adguardhome:latest")
			if [ "$(podman inspect -f "{{.State.Status}}" ${container})" == "running" ] ; then
				echo "Status [${1}]: $(podman inspect -f "{{.State.Status}}" ${container}), $(podman inspect -f "{{.State.Running}}" ${container})"
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
