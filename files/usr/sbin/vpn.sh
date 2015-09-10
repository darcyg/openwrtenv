CADIR=/etc/CA
CACERT=$CADIR/caCert.pem
CAKEY=$CADIR/caKey.pem
SERVERCERT=$CADIR/serverCert.pem
SERVERKEY=$CADIR/serverKey.pem
KEYSIZE=1024
DAYS=1825

. /lib/functions/network.sh
network_get_ipaddr wan_ip wan

buildca () {
  mkdir -p $CADIR
  ipsec pki --gen --outform pem -s $KEYSIZE > $CAKEY
  ipsec pki --self --lifetime $DAYS --in $CAKEY --dn "CN=OpenWrt CA" --ca --outform pem > $CACERT
  ln -sf $CACERT /www_blank/
  ln -sf $CACERT /etc/ipsec.d/cacerts/
}

builddh () {
  openssl dhparam -out $CADIR/dh.pem $KEYSIZE
}

buildserver () {
  # Create key/cert
  ipsec pki --gen --outform pem -s $KEYSIZE > $SERVERKEY
  ipsec pki --pub --in $SERVERKEY | ipsec pki --issue --lifetime $DAYS --cacert $CACERT --cakey $CAKEY --dn "CN=$1" --san="$1" --flag serverAuth --flag ikeIntermediate --outform pem > $SERVERCERT
  # Create symlink for key/cert in strongSwan directories
  ln -sf $SERVERKEY /etc/ipsec.d/private/
  ln -sf $SERVERCERT /etc/ipsec.d/certs/
  # Change leftid
  sed -i s/leftid.*/leftid=$1/ /etc/ipsec.conf
  # Create iOS profile
  CERT=$(sed -n '/BEGIN/,/END/p' $CACERT | sed '/BEGIN/d' | sed '/END/d')
  cat /etc/templates/ios-ikev2.template | awk '{gsub("WANIP",x)}1' x="$wan_ip" | awk '{gsub("CERT",x)}1' x="$CERT" > /www_blank/ios.mobileconfig
}

buildclient () {
  # Create key/cert 
  CLIENTKEY=$CADIR/${1}Key.pem
  CLIENTCERT=$CADIR/${1}Cert.pem
  ipsec pki --gen --outform pem -s $KEYSIZE > $CLIENTKEY
  ipsec pki --pub --in $CLIENTKEY | ipsec pki --issue --lifetime $DAYS --cacert $CACERT --cakey $CAKEY --dn "CN=$1" --outform pem > $CLIENTCERT
  # Create .ovpn profile
  CA=`cat $CACERT`
  CERT=`awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' $CLIENTCERT`
  KEY=`cat $CLIENTKEY`
  cat /etc/templates/ovpn.template | awk '{gsub("WANIP",x)}1' x="$wan_ip" | awk '{gsub("CA",x)}1' x="$CA" | awk '{gsub("CLIENTCERT",x)}1' x="$CERT" | awk '{gsub("CLIENTKEY",x)}1' x="$KEY" > /www_blank/$1.ovpn
}

clean () {
  rm -f $CADIR/*.pem
  rm -f /www_blank/*.ovpn
  rm -f /www_blank/*.mobileconfig
  cp /rom/etc/CA/dh.pem $CADIR/
}

case $1 in 
  buildca)
    buildca > /dev/null 2>&1
    echo "CA built in $CADIR."
    echo "Certificate can be downloaded at http://192.168.3.254/caCert.pem"
  ;;
  builddh)
    builddh
    echo "DH created."
  ;;
  buildserver)
    [ ! -z "$2" ] && wan_ip="$2"
    if [ -z "$wan_ip" ]; then
      echo "No WAN IP found and none specified."
      echo "Usage: $0 buildserver my.ddns.com"
      exit 0
    fi
    buildserver $wan_ip > /dev/null 2>&1
    echo "Server certificate for $wan_ip built"
    echo "iOS IKEv2 profile can be downloaded at http://192.168.3.254/ios.mobileconfig"
    echo "You should restart ipsec/openvpn/uhttpd as needed"
  ;;
  buildclient)
    if [ -z "$2" ]; then
      echo "No client name specified."
      echo "Usage: $0 buildclient myclient"
      exit 0
    fi
    buildclient $2 > /dev/null 2>&1
    echo "OpenVPN profile can be downloaded at http://192.168.3.254/$2.ovpn"
  ;;
  clean)
    clean
  ;;
  *)
    echo "Usage: $0 [buildca|builddh|buildserver|buildclient|clean]"
  ;;
esac
