#!/usr/bin/env bash

# Exit on any error
set -e
# Enable debug output
# set -x

# This script have 3 modes
# issue - issue certificate and run acme.sh install command, which also cause "deploy"
# install - only run acme.sh install command, which also cause "deploy"
# deploy - validate certificate with zimbra cert manager and deploy it to Zimbra

## HOWTO
# This script developed to be run as root.
# You must have valid DNS record[s] for domain[s] you wish to use.
#
# Install acme.sh for root user first https://github.com/Neilpang/acme.sh/wiki/How-to-install
# i.e.
# curl https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh | INSTALLONLINE=1  sh
# wget -O -  https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh | INSTALLONLINE=1  sh
#
# Put this scipt in some persistent location i.e. /root/bin
# curl -s https://raw.githubusercontent.com/hatifnatt/zimbra-letsencrypt/master/zimbra-le.sh > /root/bin/zimbra-le.sh
# chmod +x /root/bin/zimbra-le.sh
#
# If you have single domain just run
# /root/bin/zimbra-le.sh --init -d mail.example.com -e yourmail@example.com
# I can recommend run in test mode first
# /root/bin/zimbra-le.sh --init -d mail.example.com -e yourmail@example.com --test
#
# If you need certificate for multiple domains, issue certificate with acme.sh first
# acme.sh --update-account --accountemail yourmail@example.com
# acme.sh --standalone --issue -d mail.main.com -d mail.secondary.net
# than run script in "install" mode, note that main (first) domain must be used
# /root/bin/zimbra-le.sh --install -d mail.main.com
#
# That's all, acme.sh will issue certificate and will renew it when needed, this script will be
# executed as "reloadcmd" and will deploy newly issued certificate to Zimbra.

## Known limitations
# In "init" mode this script will use acme.sh "standalone" mode for domain verification which require
# free port 80/tcp which can be already used by Zimbra itself.
# This issue can be workarounded by using "dns" verification mode, check acme.sh documentation:
# https://github.com/Neilpang/acme.sh/tree/master/dnsapi
#
# Stateless mode also can be used, follow links for information
# https://github.com/Neilpang/acme.sh/wiki/Stateless-Mode
# https://github.com/JimDunphy/deploy-zimbra-letsencrypt.sh/tree/master/Recipies/SingleServer#method-3-stateless

# Script full path
ME=$(readlink -f "$0")
# acme.sh script
ACME="$HOME/.acme.sh/acme.sh"

# Variables
zimbra_ssl="/opt/zimbra/ssl"
zimbra_le_dir="$zimbra_ssl/letsencrypt"
zimbra_bin="/opt/zimbra/bin"
zimbra_user=zimbra
zimbra_group=zimbra
restart_attempts=3

# Mode can be "init", "install" or "deploy"
mode=""
test=""
force=""
email=""
domain=$(hostname -f)

# https://www.identrust.com/support/downloads
# TrustID X3
dst_root_ca_x3="-----BEGIN CERTIFICATE-----
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
"
# Let's Encrypt staging Root CA
# https://letsencrypt.org/docs/staging-environment/
# Used in test mode
fake_le_root_x1="-----BEGIN CERTIFICATE-----
MIIFATCCAumgAwIBAgIRAKc9ZKBASymy5TLOEp57N98wDQYJKoZIhvcNAQELBQAw
GjEYMBYGA1UEAwwPRmFrZSBMRSBSb290IFgxMB4XDTE2MDMyMzIyNTM0NloXDTM2
MDMyMzIyNTM0NlowGjEYMBYGA1UEAwwPRmFrZSBMRSBSb290IFgxMIICIjANBgkq
hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA+pYHvQw5iU3v2b3iNuYNKYgsWD6KU7aJ
diddtZQxSWYzUI3U0I1UsRPTxnhTifs/M9NW4ZlV13ZfB7APwC8oqKOIiwo7IwlP
xg0VKgyz+kT8RJfYr66PPIYP0fpTeu42LpMJ+CKo9sbpgVNDZN2z/qiXrRNX/VtG
TkPV7a44fZ5bHHVruAxvDnylpQxJobtCBWlJSsbIRGFHMc2z88eUz9NmIOWUKGGj
EmP76x8OfRHpIpuxRSCjn0+i9+hR2siIOpcMOGd+40uVJxbRRP5ZXnUFa2fF5FWd
O0u0RPI8HON0ovhrwPJY+4eWKkQzyC611oLPYGQ4EbifRsTsCxUZqyUuStGyp8oa
aoSKfF6X0+KzGgwwnrjRTUpIl19A92KR0Noo6h622OX+4sZiO/JQdkuX5w/HupK0
A0M0WSMCvU6GOhjGotmh2VTEJwHHY4+TUk0iQYRtv1crONklyZoAQPD76hCrC8Cr
IbgsZLfTMC8TWUoMbyUDgvgYkHKMoPm0VGVVuwpRKJxv7+2wXO+pivrrUl2Q9fPe
Kk055nJLMV9yPUdig8othUKrRfSxli946AEV1eEOhxddfEwBE3Lt2xn0hhiIedbb
Ftf/5kEWFZkXyUmMJK8Ra76Kus2ABueUVEcZ48hrRr1Hf1N9n59VbTUaXgeiZA50
qXf2bymE6F8CAwEAAaNCMEAwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMB
Af8wHQYDVR0OBBYEFMEmdKSKRKDm+iAo2FwjmkWIGHngMA0GCSqGSIb3DQEBCwUA
A4ICAQBCPw74M9X/Xx04K1VAES3ypgQYH5bf9FXVDrwhRFSVckria/7dMzoF5wln
uq9NGsjkkkDg17AohcQdr8alH4LvPdxpKr3BjpvEcmbqF8xH+MbbeUEnmbSfLI8H
sefuhXF9AF/9iYvpVNC8FmJ0OhiVv13VgMQw0CRKkbtjZBf8xaEhq/YqxWVsgOjm
dm5CAQ2X0aX7502x8wYRgMnZhA5goC1zVWBVAi8yhhmlhhoDUfg17cXkmaJC5pDd
oenZ9NVhW8eDb03MFCrWNvIh89DDeCGWuWfDltDq0n3owyL0IeSn7RfpSclpxVmV
/53jkYjwIgxIG7Gsv0LKMbsf6QdBcTjhvfZyMIpBRkTe3zuHd2feKzY9lEkbRvRQ
zbh4Ps5YBnG6CKJPTbe2hfi3nhnw/MyEmF3zb0hzvLWNrR9XW3ibb2oL3424XOwc
VjrTSCLzO9Rv6s5wi03qoWvKAQQAElqTYRHhynJ3w6wuvKYF5zcZF3MDnrVGLbh1
Q9ePRFBCiXOQ6wPLoUhrrbZ8LpFUFYDXHMtYM7P9sc9IAWoONXREJaO08zgFtMp4
8iyIYUyQAbsvx8oD2M8kRvrIRSrRJSl6L957b4AFiLIQ/GgV2curs0jje7Edx34c
idWw1VrejtwclobqNMVtG3EiPUIpJGpbMcJgbiLSmKkrvQtGng==
-----END CERTIFICATE-----
"

err(){
	echo "$*" >&2
}

say(){
	echo "$*"
}

_help(){
	echo "Usage:
--init          Issue certificate, also certificate will be deployed to Zimbra
--install       Only install certificate to Zimbra, don't try to issue
--deploy        Deploy certificate to Zimbra, intended to use with 'acme.sh --reloadcmd' only
-h --help       Show this help
-t --test       Use Let's Encrypt test servers
-f --force      With force!
-e mail@tld     Email for Let's Encrypt account
-d domain.tld   domain name to work with, current host FQDN will be used if not specified.
                If you need multi domain certificate you can issue it with acme.sh, and then
                use main domain as parameter for this script"
}

prepare(){
	say "Preparing directory for Let's Encrypt certificate files"
	# Create subdir for certificates
	if [[ -d "$zimbra_ssl" ]]; then
		mkdir -p "$zimbra_ssl/letsencrypt/"
	else
		err "Zimbra SSL directory '$zimbra_ssl' does not exist, can't create subdir for Let's Encrypt certificates"
	fi
	chown -R $zimbra_user:$zimbra_group "$zimbra_le_dir"
}

register(){
	say "Registering Let's Encrypt account with acme.sh"
	if [[ $email ]]; then
		$ACME $test --update-account --accountemail "$email"
	else
		$ACME $test --update-account
	fi
}

# Issue certificates with acme.sh "--standalone" require free port: 80/tcp
issue(){
	say "Issue certificate with acme.sh"
	$ACME $test $force --standalone --issue -d "$domain"
}

# Install certificate with acme.sh
# During installation acme.sh will also run command provided as
# option for "--reloadcmd" so we have some recursion there
installcert(){
	say "Installing certificate with acme.sh"
	$ACME --installcert -d "$domain" \
		--certpath "$zimbra_ssl/letsencrypt/$domain.cer" \
		--keypath "$zimbra_ssl/letsencrypt/$domain.key" \
		--fullchain-file "$zimbra_ssl/letsencrypt/fullchain.cer" \
		--reloadcmd "$ME $test --deploy -d $domain"
}

fullchain(){
	say "Adding Root CA to fullchain"
	if [[ $test ]]; then
		cat "$zimbra_ssl/letsencrypt/fullchain.cer" <(echo -n "$fake_le_root_x1") > "$zimbra_ssl/letsencrypt/fullchain_ca.cer"
		say "Fake LE Root X1 added to fullchain"
	else
		cat "$zimbra_ssl/letsencrypt/fullchain.cer" <(echo -n "$dst_root_ca_x3") > "$zimbra_ssl/letsencrypt/fullchain_ca.cer"
		say "DST Root CA X3 added to fullchain"
	fi
}

# All files must belong to zimbra user
postinstall(){
	say "Running post install tasks"
	chown -R $zimbra_user:$zimbra_group "$zimbra_le_dir"
}

validate(){
	say "Validating certificate with Zimbra cert manager tool"
	su $zimbra_user -c "cd $zimbra_le_dir; $zimbra_bin/zmcertmgr verifycrt comm $domain.key $domain.cer fullchain_ca.cer"
}

deploy(){
	say "Deploying certificate to Zimbra"
	su - $zimbra_user -c "cd $zimbra_le_dir; cp $domain.key $zimbra_ssl/zimbra/commercial/commercial.key"
	su - $zimbra_user -c "cd $zimbra_le_dir; $zimbra_bin/zmcertmgr deploycrt comm $domain.cer fullchain_ca.cer"
}

zmrestart(){
	# Disable "exit on error" temporary, to workaround any errors during zimbra services restart
	set +e
	# Sometimes not all services are restarted correctly.
	# We try to start everyting again in this case
	if su - $zimbra_user -c "$zimbra_bin/zmcontrol restart"; then
		say "Zimbra services restarted sucessfully"
	else
		n=0
		until [ $n -ge $restart_attempts ]
		do
			say "Not all services are restarted. Trying to start everyting again... [$n]"
			sleep 5
			su - $zimbra_user -c "$zimbra_bin/zmcontrol start" && break
			n=$((n+1))
		done
	fi
	# Enable "exit on error" again
	set -e
}

# Change working directory
cd "$zimbra_le_dir"

# Show help if no parameters provided
if [[ $# -eq 0 ]]; then
	_help
	exit 0
fi

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h | --help) # Display help
			_help
			exit 0
			;;
		--init)
			mode="init"
			shift
			;;
		--install)
			mode="install"
			shift
			;;
		--deploy)
			mode="deploy"
			shift
			;;
		-t | --test)
			test="--test"
			shift
			;;
		-f | --force)
			force="--force"
			shift
			;;
		-d) # Set domain
			domain="$2"
			shift 2
			;;
		-e) # Set email
			email="$2"
			shift 2
			;;
		--) # End of all options
			shift
			break
			;;
		-*)
			err "Error: Unknown option: $1"
			exit 1
			;;
		*) # No more options, break from loop
			break
			;;
	esac
done

case "$mode" in
	init)
		# Run init sequence
		prepare
		register
		issue
		installcert
		;;
	install)
		# Run install sequence
		prepare
		installcert
		;;
	deploy)
		# Run deploy sequence
		fullchain
		postinstall
		validate
		deploy
		zmrestart
		;;
esac

# Disable debug output
# set +x
