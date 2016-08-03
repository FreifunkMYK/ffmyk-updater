#!/bin/bash

#Voraussetzungen:
# - ssh
# - bash >=4
# - curl (Updatecheck, Firmwaresuche)

# Konstanten
version=20160801

rot="\033[22;31m"	#Rote Schrift
gruen="\033[22;32m"	#Grüne Schrift
gelb="\033[22;33m"	#Gelbe Schrift
blau="\033[22;34m"	#Blaue Schrift
normal="\033[0m"	#Normale Schrift

#Variabeln
target=()

#Dieses Variablen werden gesetzt, sofern aber ein Config-File besteht wieder überschrieben
branch=stable
firmware=""
parallel=0
verbose=0
ssh="ssh"
ping=""
ident=""
pretend=0
force=0
cont=0
user="root"
curl="curl -s"
temp="/tmp/.ffmyk-updater/"


if [ -f ~/.ffmykupdaterc ]; then
	source ~/.ffmykupdaterc
fi


function help ()
{
cat <<HELP
FFMYKUpdate Version: $version
Dieses Script aktualisiert ein oder mehrere Freifunk-Router per SSH

Auf den Routern muss SSH aktiviert und ein Passwort oder SSH-Key eingerichtet sein. Keyfiles und ein SSH-Agent werden dringend empfohlen!
Es wird ausschließlich IP (IPv6) unterstützt, IP-legacy (IPv4) ist nicht supported.

Die Firmwaredatei kann entweder manuell angegeben oder anhand des Routers automatisch gewählt werden

Aufruf:
$0 [optionen] [-b stable | -f filename.bin] [-t routerlist.txt | -i ip]

Optionen:
-b, --branch      Update auf die letzte Firmware aus der Branch stable oder beta
-f, --firmware    Update unter Nutzung der angegebenen Firmwaredatei
                  Achtung: Angabe einer falschen Datei kann Router beschädigen
-l, --listfile    Textdatei mit Liste der zu aktualisierenden Router. Eine IP pro Zeile.
-t, --target      Update des Routers mit der angegebenen IP. Kann mehrfach angegeben werden
                  Es wird nur IP(v6) unterstützt

-u, --user        Benutzername für SSH (Standard: root)
-F, --force       Installiere auch wenn Version identisch
-c, --continue    Bei Updatefehlern nicht komplett abbrechen (TBD)

-p, --parallel    Router in der Liste parallel aktualisieren
-s, --sequential  Router in der Liste nacheinander aktualisieren (standard)
                  aka: Nächster Router erst wenn der aktuelle wieder pingbar ist

-m, --nocolor     Keine Farben verwenden
-v, --verbose     Ausführliche Ausgaben aktivieren, mehrfach für debug
-S, --simulate    Nur Firmware ermitteln aber nicht installieren

-e, --executable  Angegebenen Befehl statt SSH nutzen
-P, --ping        Angegebenen Befehl statt ping/ping6 nutzen
-c, --curl        Angegebenen Befehl statt curl nutzen
-i, --ident       Angegebenes SSH-Keyfile nutzen

-T, --temp        Verzeichnis für Firmware-Downloads
                  Standard: /tmp/.ffmyk-updater/

-h, --help        Diese Hilfe anzeigen
-V, --version     Version anzeigen
-u, --update      Nach neuer Version suchen

Author:       Florian Knodt
Homepage:     https://www.adlerweb.info
Freifunk MYK: https://www.freifunk-myk.de

Grob angeleht an otrcut.sh von Daniel Siegmanski
HELP

exit 0
}

function selfupdate ()
{
online_version=$(${curl} https://raw.githubusercontent.com/FreifunkMYK/ffmyk-updater/master/version | tr -d "\r")

if [ "$online_version" -gt "$version" ]; then
	echo -e "${blau}Es ist eine neue Version verfügbar.${normal}"
	echo -e "${blau}Verwendete Version: $version ${normal}"
	echo -e "${blau}Aktuelle Version: $online_version ${normal}"
	echo "Die neue Version kann unter \"https://github.com/FreifunkMYK/ffmyk-updater/\" heruntergeladen werden."
else
	echo -e "${gelb}Es wurde keine neuere Version gefunden.${normal}"
fi

exit 0
}

function version ()
{
	echo "$version"
	exit 0
}

#Hier werden die übergebenen Option ausgewertet
while [ ! -z "$1" ]; do
	case $1 in
		-b | --branch )	branch="$2"
		 		shift ;;
		-f | --firmware )	firmware="$2"
				shift;;
		-l | --listfile )
				readarray -t targetfile < "$2"
				target=( "${target[@]}" "${targetfile[@]}" )
				shift ;;
		-t | --target )	target=("${target[@]}" "$2")
				shift ;;
		-u | --user )	user="$2"
				shift ;;
		-F | --force )    force=1 ;;
		-c | --continue ) cont=1 ;;
		-p | --parallel )	parallel=1 ;;
		-s | --sequential )	parallel=0 ;;
		-v | --verbose ) let verbose++ ;;
		-m | --nocolor )
			rot=""	#Rote Schrift
			gruen=""	#Grüne Schrift
			gelb=""	#Gelbe Schrift
			blau=""	#Blaue Schrift
			normal=""	#Normale Schrift
			;;
		-S | --simulate )    pretend=1 ;;
		-e | --executable )	executable="$2"
				shift ;;
		-P | --ping ) ping="$2"
				shift ;;
		-i | --ident)	ident="$2"
		 		shift ;;
		-T | --temp ) temp="$2"
				shift ;;
		-u | --update )	selfupdate ;;
		-V | --version )	version ;;
		-h | --help )	help ;;
	esac
	shift
done

function rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
}

function prepare ()
{
	#Prüfe ob ein Router angegeben ist
	if [ -z "$target" ]; then
	    echo "${rot}Es wurde kein Router angegeben!${normal}"
	    exit 1
	fi

	if [ -z "$ping"]; then
		ping6 -c2 "::1" > /dev/null 2>/dev/null
		if [ "$?" == 0 ] ;then
			ping="ping6"
			if [ $verbose -gt 0 ]; then
				echo -e "${gelb}Verwende ping6${normal}"
			fi
		else
			ping -c2 "::1" > /dev/null 2>/dev/null
			if [ "$?" == 0 ] ;then
				ping="ping"
				if [ $verbose -gt 0 ]; then
					echo -e "${gelb}Verwende ping${normal}"
				fi
			else
				echo -e "${rot}Keine IPv6-fähige ping-Installation gefunden${normal}"
		        exit 1
			fi
		fi
	fi

	#SSH-Befehl um Keyfile ergänzen
	if [ ! -z "$ident" ]; then
		ssh="$ssh -i ${ident}"
	fi

	#SSH-Befehl und Shell um Verbose ergänzen
	if [ $verbose -gt 1 ]; then
		ssh="$ssh -v"
		set -x
	fi

	#Doppelte Einträge entfernen
	target=($(printf "%s\n" "${target[@]}" | sort -u))

	if [ $verbose -gt 0 ]; then
		echo -e "${gelb}Aktualisiere ${#target[@]} Router${normal}"
	fi

	if [ ! -d "$temp" ]; then
		mkdir -p "$temp"
		if [ "$?" != 0 ]; then
			echo -e "${rot}Downloadverzeichnis ${temp} kann nicht erstellt werden.${end}"
			exit 1
		fi
	fi

	echo "" > ${tmp}/update.log
}

#Diese Funktion überprüft verschiedene Einstellungen
function test ()
{
	$ping -c2 "$i" > /dev/null
	if [ "$?" != 0 ] ;then
        echo -e "${gelb}Router $i nicht erreichbar!${normal}"
        exit 1
		#@TODO Nicht komplett abbrechen wenn einer nicht erreichbar
    fi
}

function update_gethw () {
	#Ermittle verwendete Hardware
	if [ $verbose -gt 0 ]; then
		echo -ne "${gelb}  Ermittle Hardware...${normal}"
	fi
	curhw=`$ssh "${user}@${i}" "lua -e 'print(require(\"platform_info\").get_image_name())'"`
	if [ $verbose -gt 0 ]; then
		echo -e "${gelb}${curhw}${normal}"
	fi
}

function update_getver () {
	if [ $verbose -gt 0 ]; then
		echo -ne "${gelb}  Ermittle installierte Firmware...${normal}"
	fi
	curver=`$ssh "${user}@${i}" "cat /lib/gluon/release"`
	if [ $verbose -gt 0 ]; then
		echo -e "${gelb}Version ${curver}${normal}"
	fi
}

function update_fwfind () {
	if [ -z "$firmware" ]; then

		#Suche neue Versionen
		readarray -t upstream < <(${curl} "http://firmware.freifunk-myk.de/.static/filter/?branch%5B%5D=${branch}&output=feelinglucky&filter=$( rawurlencode "$curhw" )")

		upstream_version=`printf "%s" "${upstream[1]}"`
		upstream_url=`printf "%s" "${upstream[0]}"`
		upstream_file="`basename ${upstream[0]}`"

		if [ "${#upstream}" -gt 2 ]; then
			upstream_hash=${upstream[2]}
		else
			upstream_hash=""
		fi

		if [ $verbose -gt 0 ]; then
			echo -e "  ${gelb}  Online-Version ist ${upstream_version} (${upstream_file})${normal}"
		fi
	fi
}

function update_fwdl () {
	#Download wenn nötig
	if [ ! -f "${temp}/${upstream_file}" ]; then
		if [ $verbose -gt 0 ]; then
			echo -e "  ${gelb}    Download von ${upstream_url}${normal}"
		fi
		${curl} -o "${temp}/${upstream_file}" "${upstream_url}"
	fi
}

function update_fwhash () {
	#Hash-Check
	if [ ! -z "${upstream_hash}" ]; then
		if [ $verbose -gt 0 ]; then
			echo -ne "  ${gelb}    Hash-Check von ${upstream_file}...${normal}"
		fi
		if [ $verbose -gt 1 ]; then
			echo "${upstream_hash}..."
		fi
		#OpenWRT only supports md5 or sha512 - we've got only sha256 atm :/
		curhash=`md5sum "${temp}/${upstream_file}" | cut -d ' ' -f 1`
		if [ $verbose -gt 1 ]; then
			echo "${curhash}..."
		fi
		if [ "$curhash" != "$upstream_hash" ]; then
			if [ $verbose -gt 0 ]; then
				echo -e "${rot}FEHLGESCHLAGEN${normal}"
			else
				echo -e "${rot}Integritätsprüfung der Datei $upstream_file fehlgeschlagen!${normal}"
			fi
			exit 1
			#@TODO Nicht komplett abbrechen
		else
			echo -e "${gruen}OK${normal}"
		fi
	fi

	firmware="${temp}/${upstream_file}"
}

function flash_upload () {
	if [ $verbose -gt 0 ]; then
		echo -ne "  ${gelb}Hochladen von ${firmware}...${normal}"
	fi

	cat $firmware | $ssh "${user}@${i}" '( rm -r /tmp/opkg-lists/ 2>/dev/null ; sync && echo 3 > /proc/sys/vm/drop_caches ); cat > /tmp/update.bin'

	if [ "$?" == 0 ]; then
		if [ $verbose -gt 0 ]; then
			echo -e "${gruen}OK${normal}"
		fi
	else
		if [ $verbose -gt 0 ]; then
			echo -e "${rot}FEHLER${normal}"
		else
			echo -e "${rot}Upload der Datei $firmware auf Router $i fehlgeschlagen!${normal}"
			exit 1
			#@TODO Nicht komplett abbrechen
		fi
	fi
}

function flash_hash () {
	#Hash-Check
	if [ ! -z "${upstream_hash}" ]; then
		if [ $verbose -gt 0 ]; then
			echo -ne "  ${gelb}  Online Hash-Check auf ${i}...${normal}"
		fi
		if [ $verbose -gt 1 ]; then
			echo "${upstream_hash}..."
		fi
		#OpenWRT only supports md5 or sha512 - we've got only sha256 atm :/
		curhash=`$ssh "${user}@${i}" "md5sum '/tmp/update.bin'  | cut -d ' ' -f 1"`
		if [ $verbose -gt 1 ]; then
			echo "${curhash}..."
		fi
		if [ "$curhash" != "$upstream_hash" ]; then
			if [ $verbose -gt 0 ]; then
				echo -e "${rot}FEHLGESCHLAGEN${normal}"
			else
				echo -e "${rot}Integritätsprüfung der Datei ${upstream_file} auf dem Router ${i} fehlgeschlagen!${normal}"
			fi
			exit 1
			#@TODO Nicht komplett abbrechen
		else
			if [ $verbose -gt 0 ]; then
				echo -e "${gruen}OK${normal}"
			fi
		fi
	fi
}

function flash_sysupgrade () {
	#Poor mans nohup
	#Disconnect vor Start des Updates um blockade des SSH-client zu verhindern
	if [ $verbose -gt 0 ]; then
		echo -ne "  ${gelb}  Starte Update auf ${i}..."
	fi
	#@TODO in dem Fall wird das Update gar nicht gestartet :(
	#$ssh "${user}@${i}" 'echo 3 > /proc/sys/vm/drop_caches ; (((sysupgrade /tmp/update.bin)&)&) ; exit' > /dev/null

	#@TODO funktioniert vermutlich nicht mit passwort-auth...
	$ssh "${user}@${i}" 'echo 3 > /proc/sys/vm/drop_caches ; sysupgrade /tmp/update.bin' >> ${tmp}/update.log &

	if [ $verbose -gt 0 ]; then
		echo -e "${gruen}OK${normal}"
	fi
}

function flash_wait () {
	timer=120
	go=1

	if [ $verbose -gt 0 ]; then
		echo -ne "  ${gelb}  Warte bis Router ${i} neu gestartet hat...${normal}"
	fi

	while [ $go -gt 0 ] ;do
		sleep 1
		$ping -c2 "$i" > /dev/null
		if [ "$?" != 0 ] ;then
			echo -e "${gelb}.${normal}"
		else
			go=0
		fi

		let timer--

		if [ $timer -lt 1 ] ;then
			go=0
		fi
	done

	if [ $timer -lt 1 ]; then
		if [ $verbose -gt 0 ]; then
			echo -e "${rot}FEHLGESCHLAGEN${normal}"
		else
			echo -e "${rot}Router ${i} nach Update nicht wieder gestartet!${normal}"
		fi
		exit 1
		#@TODO Nicht komplett abbrechen
	else
		if [ $verbose -gt 0 ]; then
			echo -e "${gruen}OK${normal}"
		fi
	fi
}

function flash_abort () {
	if [ $verbose -gt 0 ]; then
		echo -ne "  ${gelb}  Update auf Router ${i} wird abgebrochen...${normal}"
	fi
	$ssh "${user}@${i}" 'rm /tmp/update.bin' >> ${tmp}/update.log
	if [ $verbose -gt 0 ]; then
		echo -e "${gruen}OK${normal}"
	fi
}

function flash_verify () {
	update_getver
	if [ "$upstream_version" != "$curver" ]; then
		echo -e "${rot}Router ${i} nach Update nicht auf erwarteter Version!${normal}"
		exit 1
		#@TODO Nicht komplett abbrechen
	fi
}

function update () {
	if [ $verbose -gt 0 ]; then
		echo -e "${gelb}Aktualisiere Router ${i}...${normal}"
	fi

	#Download wenn nötig
	if [ -z "$firmware" ]; then
		update_gethw
		update_getver
		update_fwfind
		if [ "$upstream_version" != "$curver" ] || [ $force -gt 0 ] ;then
			update_fwdl
			update_fwhash
		else
			echo -e "${gelb}Router ${i} ist bereits mit aktuellster Firmware aktiv. Nutze --force um neu zu installieren.${normal}"
			exit 2
			#@TODO Nicht komplett abbrechen
		fi
	fi

	if [ ! -f "$firmware" ];then
		echo -e "${rot}Firmwaredatei nicht gefunden: ${firmware}${normal}"
		exit 1
		#@TODO Nicht komplett abbrechen
	fi

	flash_upload

	if [ -z "${upstream_hash}" ]; then
		upstream_hash=`md5sum "${firmware}" | cut -d ' ' -f 1`
	fi

	flash_hash

	if [ $pretend -gt 0 ] ;then
		flash_abort
	else
		flash_sysupgrade

		if [ $parallel -eq 0 ];then
			sleep 35 #Nach ca. 30 Sekunden sollte der Router mit den Neustart beginnen...
			flash_wait
			flash_verify
		fi
	fi

}

prepare
for i in "${target[@]}"; do
    test
	update
done

exit 0
