#!/bin/bash

#This script is intended as a way to set up and renew SSL certificates
# from https://www.letsnecrypt.org on a single zimbra server
# The server on which is was developed and used is a stabdalone server
# in a single server Zimbra installation. 
# The steps for the installation process are derived from:
# https://wiki.zimbra.com/wiki/Installing_a_LetsEncrypt_SSL_Certificate
# The update steps are abstractions from the installation steps above.
#
# This script is intended to be run via cron as root.
# This has been tested on an Ubuntu 14.04 VPS from Digital Ocean
# using Let's Encrypt installed according to the directions at Digital Ocean:
# https://www.digitalocean.com/community/tutorials/how-to-secure-apache-with-let-s-encrypt-on-ubuntu-14-04
#
# Please note that this script WILL take your zimbra server offline for a few moments

######
#
# Variables
#
######

#LETSENCRYPT_ROOT defines where the Let's Encrypt binaries will be found
LETSENCRYPT_ROOT=/opt/letsencrypt

#LETSENCRYPT_CONFIG defines where we can expect to find the LE config and certs. This is probably in /etc
LETSENCRYPT_CONFIG=/etc/letsencrypt

#LETSENCRYPT is the LE binary to use
LETSENCRYPT=${LETSENCRYPT_ROOT}/letsencrypt-auto

#ZIMBRA_ROOT defines where the zimbra stuff is.
ZIMBRA_ROOT=/opt/zimbra

#ZSTART/ZSTOP are the commands to start & stop Zimbra
ZSTART="/etc/init.d/zimbra start"
ZSTOP="/etc/init.d/zimbra stop"

#IS_RENEWAL defines which process to follow.
#This value will be controlled by CLI parameters, and should not be changed here.
IS_RENEWAL=1

#FORCE_RENEWAL will define the default behavior.
# By default, we will keep the cert until it is expired, and use the -f flag to override this
RENEWAL_TYPE="keep-until-expiring"

########
#
# Do this thing. The script itself starts here
#
########

if [ -z $(which letsencrypt-auto) ]; then
	if [ ! -x ${LETSENCRYPT} ]; then
		# Lets Encrypt does not seem to be installed
		echo "Please install Let's Encrypt before running this script."
		echo "# https://www.digitalocean.com/community/tutorials/how-to-secure-apache-with-let-s-encrypt-on-ubuntu-14-04"
		exit 1
	fi
else
	#Let's Encrypt is found in our path. Let's use that.
	LETSENCRYPT=$(which letsencrypt-auto)
fi

while getopts "fnrd:e:" ARG
do
	case ${ARG} in
		n)
			IS_RENEWAL=0
			;;
		r)
			IS_RENEWAL=1
			;;
		d)
			#A dirty hack. Replace all of the commas with the -d that letsencrypt-auto will expect.
			#Note that the first domain will not have a -d in front of it
			DOMAIN_STRING=$(echo ${OPTARG} | sed s'/,/ -d /g')
			PRI_DOMAIN=$(echo ${OPTARG} | cut -d"," -f1)
			;;
		e)
			EMAIL_ADDRESS=${OPTARG}
			;;
		f)
			RENEWAL_TYPE="renew-by-default"
		*)
			echo "Invalid parameter ${ARG}"
			exit 2
			;;
	esac
done

if [ -z ${DOMAIN_STRING+x} ]; then
	echo "Please use the -d parameter to pass in a comma separated list of domains."
	exit 3
fi
# Step 1, stop the zimbra services
${ZSTOP}

# Step 2, generate or renew the cert in question

if [ ${IS_RENEWAL} -eq 0 ]; then
	if [ ! -z ${EMAIL_ADDRESS} ]; then
		echo "Please use the -e parameter to pass in an email address to use for key recovery."
		${ZSTART}
		exit 4
	fi
	${LETSENCRYPT} certonly -d ${DOMAIN_STRING} --email ${EMAIL_ADDRESS} --agree-tos
else
	if ! ${LETSENCRYPT} certonly --${RENEWAL_TYPE} -d ${DOMAIN_STRING} > /var/log/letsencrypt/renew.log 2>&1 ; then
		echo "Automated renewal failed:"
		cat /var/log/letsencrypt/renew.log
		${ZSTART}
		exit 5
	fi
fi

# Step 3, create the correct chain file
# Another dirty hack. This is the IdenTrust cert. When it expires, this will break everything. Need a better way of getting this.
echo | cat > /tmp/IdenTrust.pem << ENDCERT
-----BEGIN CERTIFICATE-----
MIIDSjCCAjKgAwIBAgIQRK+wgNajJ7qJMDmGLvhAazANBgkqhkiG9w0BAQUFADA/
MSQwIgYDVQQKExtEaWdpdGFsIFNpZ25hdHVyZSBUcnVzdCBDby4xFzAVBgNVBAMT
DkRTVCBSb290IENBIFgzMB4XDTAwMDkzMDIxMTIxOVoXDTIxMDkzMDE0MDExNVow
PzEkMCIGA1UEChMbRGlnaXRhbCBTaWduYXR1cmUgVHJ1c3QgQ28uMRcwFQYDVQQD
Ew5EU1QgUm9vdCBDQSBYMzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
AN+v6ZdQCINXtMxiZfaQguzH0yxrMMpb7NnDfcdAwRgUi+DoM3ZJKuM/IUmTrE4O
rz5Iy2Xu/NMhD2XSKtkyj4zl93ewEnu1lcCJo6m67XMuegwGMoOifooUMM0RoOEq
OLl5CjH9UL2AZd+3UWODyOKIYepLYYHsUmu5ouJLGiifSKOeDNoJjj4XLh7dIN9b
xiqKqy69cK3FCxolkHRyxXtqqzTWMIn/5WgTe1QLyNau7Fqckh49ZLOMxt+/yUFw
7BZy1SbsOFU5Q9D8/RhcQPGX69Wam40dutolucbY38EVAjqr2m7xPi71XAicPNaD
aeQQmxkqtilX4+U9m5/wAl0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNV
HQ8BAf8EBAMCAQYwHQYDVR0OBBYEFMSnsaR7LHH62+FLkHX/xBVghYkQMA0GCSqG
SIb3DQEBBQUAA4IBAQCjGiybFwBcqR7uKGY3Or+Dxz9LwwmglSBd49lZRNI+DT69
ikugdB/OEIKcdBodfpga3csTS7MgROSR6cz8faXbauX+5v3gTt23ADq1cEmv8uXr
AvHRAosZy5Q6XkjEGB5YGV8eAlrwDPGxrancWYaLbumR9YbK+rlmM6pZW87ipxZz
R8srzJmwN0jP41ZL9c8PDHIyh8bwRLtTcm1D9SZImlJnt1ir/md2cXjbDaJWFBM5
JDGFoqgCWjBH4d1QB7wCCZAA62RjYJsWvIjJEubSfZGL+T0yjWW06XyxV3bqxbYo
Ob8VZRzI9neWagqNdwvYkQsEjgfbKbYK7p2CNTUQ
-----END CERTIFICATE-----
ENDCERT
cat ${LETSENCRYPT_CONFIG}/live/${PRI_DOMAIN}/chain.pem /tmp/IdenTrust.pem > /tmp/zimbra_chain.pem

# Step 4, verify the new cert

${ZIMBRA_ROOT}/bin/zmcertmgr verifycrt comm ${LETSENCRYPT_CONFIG}/live/${PRI_DOMAIN}/privkey.pem ${LETSENCRYPT_CONFIG}/live/${PRI_DOMAIN}/cert.pem /tmp/zimbra_chain.pem
if [ $? -ne 0 ]; then
	echo "Verification failed"
	${ZSTART}
	exit 6
fi

# Step 5, backup existing zimbra ssl
cp -a ${ZIMBRA_ROOT}/ssl/zimbra ${ZIMBRA_ROOT}/ssl/zimbra.$(date "+%Y%m%d")

# Step 6, Deploy the new certificate
cp ${LETSENCRYPT_CONFIG}/live/${PRI_DOMAIN}/privkey.pem ${ZIMBRA_ROOT}/ssl/zimbra/commercial/commercial.key

${ZIMBRA_ROOT}/bin/zmcertmgr deploycrt comm ${LETSENCRYPT_CONFIG}/live/${PRI_DOMAIN}/cert.pem /tmp/zimbra_chain.pem

if [ $? -ne 0 ]; then
	echo "Installation failed. Rolling back."
	cp -a ${ZIMBRA_ROOT}/ssl/zimbra /opt/zimbra/ssl/zimbra_broken.$(date "+%Y%m%d")
	rm -rf ${ZIMBRA_ROOT}/ssl/zimbra
	cp -a ${ZIMBRA_ROOT}/ssl/zimbra.$(date "+%Y%m%d") ${ZIMBRA_ROOT}/ssl/zimbra
	${ZSTART}
	exit 6
fi

# Step 7, Start the zimbra services
${ZSTART}

# Step 8, Profit!