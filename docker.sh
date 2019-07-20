#!/bin/bash
#openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx.key -out nginx.crt
support_service=( pihole/pihole:latest adguard/adguardhome:arm64-edge nginx:latest php:rc-fpm postgres:latest )
support_func="start|stop|restart|update|status"
service_array=()

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
	docker pull ${1}
	lanip=$(ip -4 addr show eth0 | grep -Po 'inet \K[\d.]+')
	dockerstr=""
	case ${1} in
		"pihole/pihole:latest")
			dockerstr+="--name pihole "
			dockerstr+="-p ${lanip}:853:53/tcp -p ${lanip}:853:53/udp "
			dockerstr+="-e TZ=Asia/Taipei "
			dockerstr+="-e IPv6=False "
			dockerstr+="-e DNS1=208.67.222.222 "
			dockerstr+="-e DNS2=208.67.220.220 "
			dockerstr+="-v $(pwd)/etc-pihole/:/etc/pihole/ "
			dockerstr+="-v $(pwd)/etc-dnsmasq.d/:/etc/dnsmasq.d/ "
			dockerstr+="--restart=unless-stopped "
		;;
		"adguard/adguardhome:arm64-edge")
			mkdir $(pwd)/etc-adguardconf/
			cp $(pwd)/AdGuardHome.yaml $(pwd)/etc-adguardconf/
			if [ -d $(pwd)/adguardwork ];
			then
				mkdir $(pwd)/etc-adguardwork/
				cp -R $(pwd)/adguardwork/* $(pwd)/etc-adguardwork/
			fi
			dockerstr+="--name adguardhome "
			dockerstr+="-p ${lanip}:5353:53/tcp -p ${lanip}:5353:53/udp "
			dockerstr+="-v $(pwd)/etc-adguardwork/:/opt/adguardhome/work/ "
			dockerstr+=" -v $(pwd)/etc-adguardconf/:/opt/adguardhome/conf/ "
		;;
		"nginx:latest")
			if [ ! -d $(pwd)/etc-html ];
			then
				mkdir $(pwd)/etc-html/
				echo "<h1>Hello World</h1>" > $(pwd)/etc-html/index.html
			fi
			mkdir -p $(pwd)/etc-nginxconf/conf.d/
			mkdir -p $(pwd)/etc-ssl/certs
			cp nginx/nginx.conf nginx/mime.types nginx/fastcgi_params $(pwd)/etc-nginxconf/
			cp nginx/conf.d/default.conf $(pwd)/etc-nginxconf/conf.d/
			cp nginx.crt nginx.key $(pwd)/etc-ssl/
			dockerstr+="--name nginx "
			dockerstr+="-p ${lanip}:80:80/tcp -p ${lanip}:443:443/tcp "
			dockerstr+="-v $(pwd)/etc-html/:/usr/share/nginx/html/ "
			dockerstr+="-v $(pwd)/etc-nginxconf/:/etc/nginx/ "
			dockerstr+="-v $(pwd)/etc-ssl/:/etc/ssl/ "
			dockerstr+="--link php-fpm "
		;;
		"php:rc-fpm")
			dockerstr+="--name php-fpm "
			dockerstr+="-p ${lanip}:80:80/tcp -p ${lanip}:443:443/tcp "
			dockerstr+="-v $(pwd)/etc-html/:/var/www/html/ "
		;;
	esac
	dockerstr+="--sysctl net.ipv6.conf.all.disable_ipv6=1 "
	docker run -d \
		${dockerstr} \
		${1}
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
		"nginx:latest")
			rm -rf $(pwd)/etc-nginxconf $(pwd)/etc-ssl
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
		"adguard/adguardhome:arm64-edge" | "nginx:latest")
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
