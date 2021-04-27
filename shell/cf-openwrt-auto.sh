#!/bin/bash
# random cloudflare anycast ip

######################################################################################################
##注意修改！！
/etc/init.d/haproxy stop
/etc/init.d/passwall stop
######################################################################################################


wait
while true
do
	while true
	do
		declare -i m
		declare -i n
		declare -i per
		rm -rf icmp temp data.txt meta.txt log.txt anycast.txt
		mkdir icmp
		while true
		do
			if [ -f "resolve.txt" ]
			then
				#echo 指向解析获取CF节点IP
				resolveip=$(cat resolve.txt)
				while true
				do
					if [ ! -f "meta.txt" ]
					then
						curl --ipv4 --resolve speed.cloudflare.com:443:$resolveip --retry 3 -v https://speed.cloudflare.com/__down>meta.txt 2>&1
					else
						asn=$(cat meta.txt | grep cf-meta-asn: | tr '\r' '\n' | awk '{print $3}')
						city=$(cat meta.txt | grep cf-meta-city: | tr '\r' '\n' | awk '{print $3}')
						#latitude=$(cat meta.txt | grep cf-meta-latitude: | tr '\r' '\n' | awk '{print $3}')
						#longitude=$(cat meta.txt | grep cf-meta-longitude: | tr '\r' '\n' | awk '{print $3}')
						curl --ipv4 --resolve service.udpfile.com:443:$resolveip --retry 3 "https://service.udpfile.com?asn="$asn"&city="$city"" -o data.txt -s
						break
					fi
				done
			else
				#echo DNS解析获取CF节点IP
				while true
				do
					if [ ! -f "meta.txt" ]
					then
						curl --ipv4 --retry 3 -v https://speed.cloudflare.com/__down>meta.txt 2>&1
					else
						asn=$(cat meta.txt | grep cf-meta-asn: | tr '\r' '\n' | awk '{print $3}')
						city=$(cat meta.txt | grep cf-meta-city: | tr '\r' '\n' | awk '{print $3}')
						#latitude=$(cat meta.txt | grep cf-meta-latitude: | tr '\r' '\n' | awk '{print $3}')
						#longitude=$(cat meta.txt | grep cf-meta-longitude: | tr '\r' '\n' | awk '{print $3}')
						curl --ipv4 --retry 3 "https://service.udpfile.com?asn="$asn"&city="$city"" -o data.txt -s
						break
					fi
				done
			fi
			if [ -f "data.txt" ]
			then
				break
			fi
		done
		domain=$(cat data.txt | grep domain= | cut -f 2- -d'=')
		file=$(cat data.txt | grep file= | cut -f 2- -d'=')
		url=$(cat data.txt | grep url= | cut -f 2- -d'=')
		app=$(cat data.txt | grep app= | cut -f 2- -d'=')
		if [ "$app" != "20210315" ]
		then
			echo "发现新版本程序: $app">需要更新.txt
			echo "更新地址: $url">>需要更新.txt
			echo "更新后才可以使用">>需要更新.txt
			exit
		fi
		for i in `cat data.txt | sed '1,4d'`
		do
			echo $i>>anycast.txt
		done
		rm -rf meta.txt data.txt
		n=0
		m=$(cat anycast.txt | wc -l)
		for i in `cat anycast.txt`
		do
			ping -c 20 -i 1 -n -q $i > icmp/$n.log&
			n=$[$n+1]
			per=$n*100/$m
			while true
			do
				p=$(ps | grep ping | grep -v "grep" | wc -l)
				if [ $p -ge 100 ]
				then
					#echo 正在测试 ICMP 丢包率:进程数 $p,已完成 $per %
					sleep 1
				else
					#echo 正在测试 ICMP 丢包率:进程数 $p,已完成 $per %
					break
				fi
			done
		done
		rm -rf anycast.txt
		while true
		do
			p=$(ps | grep ping | grep -v "grep" | wc -l)
			if [ $p -ne 1 ]
			then
				#cho 等待 ICMP 进程结束:剩余进程数 $p
				sleep 1
			else
				#echo ICMP 丢包率测试完成
				break
			fi
		done
		cat icmp/*.log | grep 'statistics\|loss\|avg' | sed 'N;N;s/\n/ /g' | awk -F, '{print $1,$3}' | awk '{print $2,$9,$15}' | awk -F% '{print $1,$2}' | awk -F/ '{print $1,$2}' | awk '{print $2,$4,$1}' | sort -n | awk '{print $3}' | sed '21,$d' > ip.txt
		rm -rf icmp
		#echo 选取20个丢包率最少的IP地址下载测速
		mkdir temp
		for i in `cat ip.txt`
		do
			#echo $i 启动测速
			curl --resolve $domain:443:$i https://$domain/$file -o temp/$i -s --connect-timeout 5 --max-time 10&
		done
		#echo 等待测速进程结束,筛选出三个优选的IP
		wait
		#echo 测速完成
		ls -S temp > ip.txt
		rm -rf temp
		n=$(wc -l ip.txt | awk '{print $1}')
		if [ $n -ge 3 ]; then
			first=$(sed -n '1p' ip.txt)
			second=$(sed -n '2p' ip.txt)
			third=$(sed -n '3p' ip.txt)
			rm -rf ip.txt

			######################################################################################################
			##注意修改！！
			wait
			uci commit passwall
			wait
			sed -i "s/$(uci get passwall.xxxxxxxxxxxxxxxxxx.address)/${first}/g" /etc/config/passwall
			sed -i "s/$(uci get passwall.xxxxxxxxxxxxxxxxxx.address)/${second}/g" /etc/config/passwall
			sed -i "s/$(uci get passwall.xxxxxxxxxxxxxxxxxx.address)/${third}/g" /etc/config/passwall
			wait
			uci commit passwall
			wait
			/etc/init.d/haproxy restart
			wait
			/etc/init.d/passwall restart
			wait
			break
			######################################################################################################
		fi
	done
		break
done