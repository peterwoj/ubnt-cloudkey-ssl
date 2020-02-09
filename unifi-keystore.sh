#!/bin/bash
# Ubiquiti CloudKey signed SSL
# Guide used to prepare this can be found at
#  https://community.ui.com/questions/How-to-install-a-SSL-Certificate-on-Unifi-Cloud-Key/944dbbd6-cbf6-4112-bff5-6b992fcbf2c4

# Copyright (C) 2020  Peter J Wojcicehowski

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

_sslCountry="US"
_sslState="CA"
_sslEmail="peterwoj@dwellersoul.com"
_sslOU="Unifi"
_sslFQDN="unifi.wojstead.org"
_sslO="wojstead.org"

_password=""

# RSA private key file used to sign the certificate request
_sslKeyFile="cloudkey.key"

# SSL Certificate Request file use to request a signed certificate
_sslCsrFile="cloudkey.csr"

# Combined file containing all certificates needed to fullfil 
# the SSL handshake
#   1. Signed Certificate
#   2. All intermediary Certificates from the Certificate Authority
#     a. each files contents combined together
_sslCerFile="cerfile.cer"

# A PKCS12 file used to prepare a keystore file for use by the Ubiquiti
# application.
_sslPfxFile="cloudkey.pfx"

# Keystore file used to serve SSL requests from the Ubiquiti application
_keystoreFile="unifi.keystore.jks"

_sslCmd="/usr/bin/openssl"
_keyToolCmd="/usr/bin/keytool"

checkCmdFile() {
    local fileToCheck=$1; shift
    
    if [ ! -f ${fileToCheck} ]; then
        echo "${fileToCheck} was not found cannot continue"
        exit 1
    fi
}

showUsage() {
    local exitCode=${1:-0}

    echo "usage: ${0} [opts}"
    echo ""
    echo "  -c          Country Code        (default: ${_sslCountry}"
    echo "  -d          Full domain name    (default: ${_sslFQDN}"
    echo "  -e          EMail Address       (default: ${_sslEmail})"
    echo "  -h          Display this help"
    echo "  -o          Organization        (default: ${_sslO}"
    echo "  -p          (REQUIRED): Password to use for keystore and certificate"
    echo "  -s          State               (default: ${_sslState})"
    echo "  -u          Organization Unit   (default: ${_sslOU})"
    
    exit ${exitCode}
}

checkCmdFile ${_sslCmd}
checkCmdFile ${_keyToolCmd}

while getopts "c:d:e:ho:p:s:u:" option; do
    case ${option} in
        c ) 
            _sslCountry=$OPTARG
            ;;
        d )
            _sslFQDN=$OPTARG
            ;;
        e )
            _sslEmail=$OPTARG
            ;;
        h )
            showUsage
            ;;
        o )
            _sslO=$OPTARG
            ;;
        p )
            _password=$OPTARG
            ;;
        s )
            _sslState=$OPTARG
            ;;
        u )
            _sslOU=$OPTARG
            ;;
        * )
            echo "Unknown option passed"
            showUsage 1
            ;;
        esac
done
shift $(( OPTIND - 1))

if [ "${_password}" = "" ]; then
    echo "Missing password"
    showUsage 1
fi

if [ ! -f ${_sslKeyFile} ]; then
    echo "Creating private key for signing"
    ${_sslCmd} genrsa -passout pass:${_password} -out ${_sslKeyFile} 2048

    if [ $? -ne 0 ]; then
        echo "Unable to create private key for signing"
        exit 2
    fi
fi

if [ ! -f ${_sslCsrFile} ]; then
    echo "Creating Certificate Signing Request (csr file)"
    ${_sslCmd} req -new \
        -subj "/C=${_sslCountry}/ST=${_sslState}/O=${_sslO}/OU=${_sslOU}/CN=${_sslFQDN}/emailAddress=${_sslEmail}" \
        -key ${_sslKeyFile} \
        -out ${_sslCsrFile}

    if [ $? -ne 0 ]; then
        echo "Unable to create a certificate signing request"
        exit 3
    fi
    echo "Have this file signed: ${_sslCsrFile}"
fi

if [ ! -f ${_sslCerFile} ]; then
    echo " Get the ${_sslCsrFile} file signed and create a ${_sslCerFile}"
    echo " by combining the contents of the crt and any intermediate"
    echo " certs needed."
    echo ""
    echo "    ex:   cat ${_sslFQDN}.crt ${_sslFQDN}.ca-bundle > ${_sslCerFile}"
    echo ""

    exit
else
    echo "Exporting the certificates to prepare the keystore"
    ${_sslCmd} pkcs12 -export \
        -password pass:${_password} \
        -in ${_sslCerFile} \
        -inkey ${_sslKeyFile} \
        -out ${_sslPfxFile}

    if [ $? -ne 0 ]; then
        echo "Unable to prepare the PKCS#12 file"
        exit 4
    fi

    echo "Creating the keystore for Unifi"
    ${_keyToolCmd} -importkeystore \
        -destkeystore ${_keystoreFile} \
        -deststorepass ${_password} \
        -deststoretype pkcs12 \
        -srckeystore ${_sslPfxFile} \
        -srcstorepass ${_password} 

    if [ $? -ne 0 ]; then
        echo "Failed importing certificates into the keystore"
        exit 5
    fi

    ${_keyToolCmd} -changealias \
        -keystore ${_keystoreFile}  \
        -storepass ${_password} \
        -alias 1 -destalias unifi

    _retCode=$?
    if [ ${_retCode} -ne 0 ]; then
        echo "Failed updating the certificate alias: ${_retCode}"
        exit 6
    fi

    echo "Remember to update the system.properties file to include the"
    echo "keystore password.  The following property needs to be added to"
    echo "the file /usr/lib/unifi/data/system.properties"
    echo ""
    echo "app.keystore.pass=<password>"
    echo ""
fi



