#!/bin/sh

if  [ $# -ne 2 ]
then
	echo "Usage:"
	echo "    tc.sh dev rate(Kbit)"
	exit -1
fi

INTF=$1
RATE=$2

#echo $(($RATE * 8 / 10))
#exit 0

p2pmark=6
dnsmark=2
webmark=3
smallmark=1
bigmark=4
othermark=5

tc qdisc del dev $INTF root 2>/dev/null

tc qdisc add dev $INTF root handle 1: htb default 133
tc class add dev $INTF parent 1: classid 1:1 htb rate ${RATE}Kbit ceil ${RATE}Kbit prio 8

#small
tc class add dev $INTF parent 1:1 classid 1:11 htb rate $(($RATE / 10))Kbit ceil $(($RATE / 6))Kbit prio 1
#dns
tc class add dev $INTF parent 1:1 classid 1:12 htb rate $(($RATE / 10))Kbit ceil $(($RATE / 8))Kbit prio 2


tc class add dev $INTF parent 1:1 classid 1:13 htb rate $(($RATE / 2))Kbit ceil $(($RATE * 8 / 10))Kbit prio 8
#web
tc class add dev $INTF parent 1:13 classid 1:131 htb rate $(($RATE / 3))Kbit ceil $(($RATE * 8 / 10))Kbit prio 4
#big
tc class add dev $INTF parent 1:13 classid 1:132 htb rate 50Kbit ceil $(($RATE * 8 / 10))Kbit prio 7
#other
tc class add dev $INTF parent 1:13 classid 1:133 htb rate 50Kbit ceil $(($RATE / 8))Kbit prio 8


#small
tc filter add dev $INTF parent 1:0 protocol ip prio 1 handle $smallmark fw classid 1:11
#dns
tc filter add dev $INTF parent 1:0 protocol ip prio 1 handle $dnsmark fw classid 1:12
#web
tc filter add dev $INTF parent 1:0 protocol ip prio 1 handle $webmark fw classid 1:131
#big
tc filter add dev $INTF parent 1:0 protocol ip prio 1 handle $bigmark fw classid 1:132
#other
tc filter add dev $INTF parent 1:0 protocol ip prio 1 handle $othermark fw classid 1:133

iptables -t mangle -F
iptables -t mangle -X

IPMAN="iptables -t mangle -A PREROUTING"
preconn=0xc0

#p2p
#$IPMAN -m ipp2p --ipp2p -j CONNMARK --set-mark ${preconn}${p2pmark}
#$IPMAN -m connmark --mark ${preconn}${p2pmark} -j MARK --set-mark $p2pmark
#$IPMAN -m mark --mark $p2pmark -j RETURN

#dns
$IPMAN -p udp --dport 53 -j CONNMARK --set-mark $preconn$dnsmark
$IPMAN -m connmark --mark $preconn$dnsmark -j MARK --set-mark $dnsmark
$IPMAN -m mark --mark $dnsmark -j RETURN

#web down
$IPMAN -p tcp --dport 80 -m connmark ! --mark $preconn$bigmark \
		-m connbytes --connbytes 4096000: --connbytes-dir both --connbytes-mode bytes \
		-j CONNMARK --set-mark $preconn$bigmark
$IPMAN -p tcp --dport 443 -m connmark ! --mark $preconn$bigmark \
		-m connbytes --connbytes 4096000: --connbytes-dir both --connbytes-mode bytes \
		-j CONNMARK --set-mark $preconn$bigmark
$IPMAN -m connmark --mark $preconn$bigmark -j MARK --set-mark $bigmark
$IPMAN -m mark --mark $bigmark -j RETURN

#web
$IPMAN -p tcp --dport 80 -j CONNMARK --set-mark $preconn$webmark
$IPMAN -p tcp --dport 443 -j CONNMARK --set-mark $preconn$webmark
$IPMAN -m connmark --mark $preconn$webmark -j MARK --set-mark $webmark
$IPMAN -m mark --mark $webmark -j RETURN

#small
$IPMAN -m length --length 32:512 -j MARK --set-mark $smallmark
$IPMAN -m mark --mark $smallmark -j RETURN
#big
$IPMAN -m length --length 513:1500 -j MARK --set-mark $bigmark
$IPMAN -m mark --mark $bigmark -j RETURN
#other
$IPMAN -j MARK --set-mark $othermark
$IPMAN -m mark --mark $othermark -j RETURN
