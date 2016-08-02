<pre>Dieses Script aktualisiert ein oder mehrere Freifunk-Router per SSH
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
