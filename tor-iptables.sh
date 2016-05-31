#!/bin/bash

export BLUE='\033[1;94m'
export GREEN='\033[1;92m'
export RED='\033[1;91m'
export ENDC='\033[1;00m'

# Config file tor
CONFFILE=/etc/tor/torrc

# Destinations you don't want routed through Tor
NON_TOR="192.168.0.0/16 172.16.0.0/12 10.0.0.0/8"

# The GID Tor runs as
TOR_GID="tor"

# Tor's TransPort
TRANS_PORT="9040"


function print_config_tor {
    echo -e "\n$RED[!] Please add the following to your ${CONFFILE} and restart service:$ENDC\n" >&2
    echo -e "$BLUE#----------------------------------------------------------------------#$ENDC"
    echo -e "User tor"
    echo -e "RunAsDaemon 1"
    echo -e "PIDFile /var/run/tor/tor.pid"
    echo -e "DataDirectory /var/lib/tor/data"
    echo -e "VirtualAddrNetwork 10.192.0.0/10"
    echo -e "AutomapHostsOnResolve 1"
    echo -e "TransPort 9040"
    echo -e "DNSPort 53"
    echo -e "$BLUE#----------------------------------------------------------------------#$ENDC\n"
    exit 1
}

function checkconfig() {

    echo -e "\n$BLUE[i] Check config:$ENDC\n"

    # Make sure only root can run this script
    if [ $(id -u) -ne 0 ]; then
        echo -e "\n$RED[!] This script must be run as root$ENDC\n" >&2
        exit 1
    fi

    if [ ! -e /usr/bin/tor ]; then
        echo -e " $RED*$ENDC Tor is not installer! Quitting...\n" >&2
        exit 1
    fi

    # now verify whether the configuration is valid
    /usr/bin/tor --verify-config -f ${CONFFILE} > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
            echo -e " $GREEN*$ENDC Tor configuration (${CONFFILE}) is valid."
    else
            echo -e " $RED*$ENDC Tor configuration (${CONFFILE}) not valid."
            /usr/bin/tor --verify-config -f ${CONFFILE}
            exit 1
    fi


    get_parameter=$( grep -icx 'RunAsDaemon 1' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi

    get_parameter=$( grep -icx 'PIDFile /var/run/tor/tor.pid' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi

    get_parameter=$( grep -icx 'DataDirectory /var/lib/tor/data' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi

    get_parameter=$( grep -icx 'AutomapHostsOnResolve 1' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi

    get_parameter=$( grep -icx 'TransPort 9040' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi

    get_parameter=$( grep -icx 'DNSPort 53' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi

    get_parameter=$( grep -icx 'User tor' ${CONFFILE} )
    if [ $get_parameter -eq 0 ]; then
        print_config_tor
    fi


}

case "$1" in
    start)

        #check Tor
        checkconfig || return 1

        if [ ! -d /var/run/tor/ ]; then
            mkdir -p /var/run/tor/
            chown tor /var/run/tor/
            chmod 02750 /var/run/tor/
        fi

        echo -e "\n$BLUE[i] Starting anonymous mode:$ENDC\n"

        if [ ! -e /var/run/tor/tor.pid ]; then
            echo -e " $GREEN*$ENDC Start tor!\n"
            /usr/bin/tor -f ${CONFFILE} --quiet
        fi

        iptables -F
        iptables -t nat -F
        echo -e " $GREEN*$ENDC Deleted all iptables rules"

        echo -e 'nameserver 127.0.0.1' > /etc/resolv.conf
        echo -e " $GREEN*$ENDC Modified resolv.conf to use Tor"

        iptables -t nat -A OUTPUT -m owner --gid-owner $TOR_GID -j RETURN
        iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 53
        for NET in $NON_TOR 127.0.0.0/9 127.128.0.0/10; do
            iptables -t nat -A OUTPUT -d $NET -j RETURN
        done
        iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT
        iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        for NET in $NON_TOR 127.0.0.0/8; do
                iptables -A OUTPUT -d $NET -j ACCEPT
        done
        iptables -A OUTPUT -m owner --gid-owner $TOR_GID -j ACCEPT
        iptables -A OUTPUT -j REJECT
        echo -e "$GREEN *$ENDC Redirected all traffic throught Tor\n"

        echo -e "$BLUE[i] Are you using Tor?$ENDC\n"
        echo -e "$GREEN *$ENDC Please refer to https://check.torproject.org\n";
    ;;
    stop)

        # Make sure only root can run this script
        if [ $(id -u) -ne 0 ]; then
            echo -e "\n$RED[!] This script must be run as root$ENDC\n" >&2
            exit 1
        fi

        echo -e "\n$BLUE[i] Stopping anonymous mode:$ENDC\n"

        echo -e 'nameserver 208.67.222.222' >  /etc/resolv.conf
        echo -e 'nameserver 208.67.220.220' >> /etc/resolv.conf
        echo -e " $GREEN*$ENDC Modified resolv.conf to use OpenDNS"

        iptables -F
        iptables -t nat -F
        echo -e " $GREEN*$ENDC Deleted all iptables rules\n"

        if [ -e /var/run/tor/tor.pid ]; then
            killall tor
            echo -e " $GREEN*$ENDC Stop tor!\n"
        fi
    ;;
    restart)
        $0 stop
        $0 start
    ;;
    *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
