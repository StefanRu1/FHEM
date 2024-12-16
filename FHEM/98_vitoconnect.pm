#########################################################################
# $Id: 98_vitoconnect.pm 26738 2022-11-23 00:22:25Z mcp $
# fhem Modul für Viessmann API. Based on investigation of "thetrueavatar"
# (https://github.com/thetrueavatar/Viessmann-Api)
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#

#   https://wiki.fhem.de/wiki/DevelopmentModuleAPI
#   https://forum.fhem.de/index.php/topic,93664.0.html
#   https://www.viessmann-community.com/t5/Announcements/Important-adjustment-in-IoT-features-Split-heating-circuits-and/td-p/281527
#   https://forum.fhem.de/index.php/topic,93664.msg1257651.html#msg1257651
#   https://www.viessmann-community.com/t5/Getting-started-programming-with/Syntax-for-setting-a-value/td-p/374222
#   https://forum.fhem.de/index.php?msg=1326376

sub vitoconnect_Initialize;             # Modul initialisieren und Namen zusätzlicher Funktionen bekannt geben
sub vitoconnect_Define;                 # wird beim 'define' eines Gerätes aufgerufen
sub vitoconnect_Undef;                  # wird beim Löschen einer Geräteinstanz aufgerufen
sub vitoconnect_Get;                    # bisher kein 'get' implementiert
sub vitoconnect_check_gwa_and_get_gw;   # Nötig für Actions die nur mit einem gw laufen
sub vitoconnect_Set_New;                # Implementierung set-Befehle New dynamisch auf raw readings
sub vitoconnect_Set;                    # Implementierung set-Befehle SVN
sub vitoconnect_Set_Roger;              # Implementierung set-Befehle Roger
sub vitoconnect_Attr;                   # Attribute setzen/ändern/löschen

sub vitoconnect_GetUpdate;              # Abfrage aller Werte starten

sub vitoconnect_getCode;                # Werte für: Access-Token, Install-ID, Gateway anfragen
sub vitoconnect_getCodeCallback;        # Rückgabe: Access-Token, Install-ID, Gateway von vitoconnect_getCode Anfrage

sub vitoconnect_getAccessToken;         # Access & Refresh-Token holen
sub vitoconnect_getAccessTokenCallback; # Access & Refresh-Token speichern, Antwort auf: vitoconnect_getAccessToken

sub vitoconnect_getRefresh;             # neuen Access-Token anfragen
sub vitoconnect_getRefreshCallback;     # neuen Access-Token speichern

sub vitoconnect_getGw;                  # Abfrage Gateway-Serial
sub vitoconnect_getGwCallback;          # Gateway-Serial speichern, Anwort von Abfrage Gateway-Serial

sub vitoconnect_getInstallation;        # Abfrage Install-ID
sub vitoconnect_getInstallationCallback;# Install-ID speichern, Antwort von Abfrage Install-ID

sub vitoconnect_getDevice;              # Abfrage Device-ID
sub vitoconnect_getDeviceCallback;      # Device-ID speichern, Anwort von Abfrage Device-ID

sub vitoconnect_getFeatures;            # Abruf GW Features
sub vitoconnect_getFeaturesCallback;    # gw_features speichern

sub vitoconnect_errorHandling;          # Errors bearbeiten für alle Calls
sub vitoconnect_getResource_per_gw;     # API call per Gateway
sub vitoconnect_getResource;            # API call for all Gateways
sub vitoconnect_getResourceCallback;    # Get all API readings
sub vitoconnect_getPowerLast;           # Write the power reading of the full last day to the DB

sub vitoconnect_action;                 # 

sub vitoconnect_StoreKeyValue;          # Werte verschlüsselt speichern
sub vitoconnect_ReadKeyValue;           # verschlüsselte Werte auslesen

##############################################################################
#   Changelog:
#               Changed to %vNotesIntern. See %vNotesIntern below.
#   2024-12-12  In case of more than one Gateway only allow Set_New if serial is provided
#               Get Object and Hash in Array readings. E.g. device.messages.errors.raw
#               In case of expired token (every hour) do not do uncessary gateway calls, just get the new token.
#               This will safe API calls and reduce the API overhead.
#   2024-12-06  Remove internal timer when Device gets defined or redefined
#   2024-12-05  Error fixed remove logReponseOnce Flag after one run
#   2024-12-04  Fixed getResource to read gw in first try, this will fix the unnecessary API calls if you do not specify a Gateway Serial
#               Fixed timers if more than one Gateway
#   2024-12-03  Fixed Gateway Serial handling.
#   2024-12-02  Day power readings werden nun unter .asSingleValue gespeichert.
#               Die Daten kommen von der API nur sporatisch, erst nach mehreren Tagen.
#               Diese Funktion trägt sie nach und man kann so Graphen malen.
#   2024-12-01  Statisches Mapping von SVN übernommen.
#               Bug bei Fehlerbehandlung von vitoconnect_action behoben
#               Parmeter vitoconnect_mapping_roger um Rogers mapping zu benutzen
#               RequestLists aufgespalten nach SVN und Roger
#               neue sub vitoconnect_Set_Roger
#   2024-11-30  HK1_Betriebsart:active,standby  + heating,dhw,dhwAndHeating,forcedReduced,forcedNormal
#               Mehr Readings siehe https://forum.fhem.de/index.php?msg=1326591
#               If setter is called with ok, also set the value in the reading
#   2024-11-16  Änderungen für Hybrid Anlagen mit 2 Gateways und eigenem Mapping der Werte.
#               Mehrere Gateways werden abgefragt.
#               Die Readings oder gedumpen Files haben als Suffix die Gateway Serial.
#               Es kann über das neue Attribut vitoconnect_serial eine Gateway Serial festgelegt werden die fortan allein abgerufen werden soll.
#               Somit ist es möglich für jeden Gateway ein vitoconnect Device anzulegen oder alle Readings in einem Device zu verwalten.
#               Dadurch kann man z.B. ein Device Wärmepumpe und eines Brenner haben.
#               Diese können dann unterschiedliche Abfrageintervalle haben.
#               Z.b. WP die normalerweise arbeitet und alles Steuert alle 100 Sek und den Brenner nur all 300 Sek.
#               Ein eignes Mapping der Werte kann im Attribut mapping erstellt werden.
#               Das Format ist { 'Key1' => 'Value1', 'Key2' => 'Value2' }
#               Wenn angegeben ersetzt dieses Mapping das statische Standard mapping.
#               Eine eigene translation kann angegeben werden um jedes einzelne Wort zu übersetzen.
#               Das Format ist { 'Key1' => 'Value1', 'Key2' => 'Value2' }
#               Translation hat vorrang for mapping hat vorrang vor statischem mapping im modul
#               Code fixes in Bezug auf subs und Komentare
#               Error Handling überarbeitet
#               Initialisierung von installationFeatures aufgetrennt, alle subs sind nun nonBlocking
#               Attribut model entfernt, wird nicht verwendet
#               vitoconnect_gw_readings implementiert, wenn 1 werden die internen readings in readings gespeichert wenn 0 nicht
#               vitoconnect_actions_active implementiert, Setter im JSON werden als reading.setURI gespeichert
#               Set für RAW readings implementiert, so dynamisch wie möglich, VIESSMANN API ist nicht eindeutig und Reihenfolge im JSON ist wichtig, das ist großer murks
#               Beschreibungen für Attribute im WEBUI nun auch anzeigen und angepasst
#               Achtung! Keine Umlaute in Heizkreisnamen verwenden!
#               stefanru
#   2023-11-04  set-Befehle an Viessmann-Api angepasst
#               Heizung:    set <name> HK1_Betriebsart standby,heating
#                           set <name> HK1_Soll_Temp_normal nn      ## 3-37,1
#               Warmwasser: set <name> WW_Betriebsart  off,balanced
#               diverse Namen von readings angepasst
#
#   2018-11-24  initial version
#   2018-12-11  non-blocking
#               Reading "status" in "state" umbenannt
#   2018-12-23  Neue Werte in der API werden unter ihrem JSON Name als Reading eingetragen
#               Neue Readings:
#                   heating.boiler.sensors.temperature.commonSupply.status error
#                   heating.boiler.temperature.value                          48.1
#                   heating.burner.modulation.value                        11
#                   heating.burner.statistics.hours                        933.336666666667
#                   heating.burner.statistics.starts                       2717
#                   heating.circuits.0.circulation.pump.status             on
#                   heating.dhw.charging.active                            0
#                   heating.dhw.pumps.circulation.schedule.active          1
#                   heating.dhw.pumps.circulation.schedule.entries         sun mode:on end:22:30 start:04:30 position:0, fri end:22:30 mode:on position:0 start:04:30,
#                                                                          mon mode:on end:22:30 start:04:30 position:0,
#                                                                          wed start:04:30 position:0 end:22:30 mode:on, thu mode:on end:22:30 position:0 start:04:30, sat end:22:30 mode:on position:0 start:04:30,
#                                                                          tue position:0 start:04:30 end:22:30 mode:on,
#                   heating.dhw.pumps.circulation.status                   on
#                   heating.dhw.pumps.primary.status                       off
#                   heating.dhw.sensors.temperature.outlet.status          error
#                   heating.dhw.temperature.main.value                     53
#   2018-12-30     initial offical release
#                 remove special characters from readings
#                 some internal improvements suggested by CoolTux
#   2019-01-01     "disabled" implemented
#                 "set update implemented
#                       renamed "WW-onTimeCharge_aktiv" into "WW-einmaliges_Aufladen_aktiv"
#                       Attribute vitoconnect_raw_readings:0,1 " and  ."vitoconnect_actions_active:0,1 " implemented
#                       "set clearReadings" implemented
#   2019-01-05      Passwort wird im KeyValue gespeichert statt im Klartext
#                 Action "oneTimeCharge" implemented
#   2019-01-14      installation, code and gw in den Internals unsichtbar gemacht
#                 Reading "counter" entfernt (ist weiterhin in Internals sichtbar)
#                       Reading WW-einmaliges_Aufladen_active umbenannt in WW-einmaliges_Aufladen
#                 Befehle zum setzen von
#                       HK1-Betriebsart
#                       HK2-Betriebsart
#                       HK1-Solltemperatur_normal
#                       HK2-Solltemperatur_normal
#                       HK1-Solltemperatur_reduziert
#                       HK2-Solltemperatur_reduziert
#                       WW-einmaliges_Aufladen
#                 Bedienfehler (z.B. Ausführung einer Befehls für HK2, wenn die Hezung nur einen Heizkreis hat)
#                       führen zu einem "Bad Gateway" Fehlermeldung in Logfile
#                       Achtung: Keine Prüfung ob Befehle sinnvoll und oder erlaubt sind! Nutzung auf eigene Gefahr!
#   2019-01-15     Fehler bei der Befehlsausführung gefixt
#   2019-01-22      Klartext für Readings für HK3 und heating.dhw.charging.level.* hinzugefügt
#                       set's für HK2 implementiert
#                      set für Slope und Shift implementiert
#                       set WW-Haupttemperatur und WW-Solltemperatur implementiert
#                       set HK1-Solltemperatur_comfort_aktiv HK1-Solltemperatur_comfort implementiert
#                       set  HK1-Solltemperatur_eco implementiert (set HK1-Solltemperatur_eco_aktiv scheint es nicht zu geben?!)
#                       vor einem set vitoconnect update den alten Timer löschen
#                       set vitoconnect logResponseOnce implementiert (eventuell werden zusätzliche perl Pakete benötigt?)
#   2019-01-26      Fehler, dass HK3 Readings auf HK2 gemappt wurden gefixt
#   2019-02-17      Readings für den Stromverbrauch (heating.power.consumption.*) und
#                         Raumtemperatur (heating.circuits.?.sensors.temperature.room.value) ergänzt
#                       set-Befehle für HKs werden nur noch angezeigt, wenn der HK auch aktiv ist
#                       Wiki aktualisiert
#   2019-02-27      stacktrace-Fehler (hoffentlich) behoben
#                       Betriebsarten "heating" und "active" ergänzt
#   2019-03-02      Readings für heating.boiler.sensors.temperature.commonSupply.value und
#                           heating.circuits.1.operating.modes.heating.active hinzugefügt
#                       Typo fixed ("Brenner_Be-t-riebsstunden")
#   2019-03-29      neue Readings:
#                           heating.circuits.1.operating.modes.dhwAndHeatingCooling.active 1
#                           heating.circuits.1.operating.modes.normalStandby.active 0
#                           heating.circuits.1.operating.programs.fixed.active 0
#                           heating.compressor.active 0
#                           heating.dhw.temperature.hysteresis.value 5
#                           heating.dhw.temperature.temp2.value 60
#                       Passwort wird bei "define" nur noch gesetzt, wenn noch kein Passwort gespeichert war
#                 Attribut "model" implementiert
#   2019-04-26      neue Readings für
#                       heating.gas.consumption.dhw.unit kilowattHour
#                       heating.gas.consumption.heating.unit kilowattHour
#                       heating.power.consumption.unit kilowattHour
#                       Typo in WW-Zirkulationspumpe_Zeitsteuerung_aktiv fixt
# 2019-06-01        neue Readings für
#                       heating.solar.power.production.day  3.984,3.797,5.8,5.5,6.771,5.77,5.441,9.477
#                       heating.solar.power.production.month
#                       heating.solar.power.production.unit kilowattHour
#                       heating.solar.power.production.week
#                       heating.solar.power.production.year
#                     heating.circuits.X.name (wird im Moment noch nicht von der API gefüllt!)
#                 Format der "Schedule" Readings in JSON geändert
#                       das Format von HKx-Urlaub_Start und _Ende ist jetzt YYYY-MM-TT.
#                   Wenn noch kein Urlaub aktiviert wurde, wird bei
#                    HKx-Urlaub_Start das Datum für _Ende auf den Folgetag gesetzt
#                    Dafür werden die Perl Module DateTime, Time:Piece und Time::Seconds
#                    benötigt (installieren mit apt install libdatetime-perl!)
#
# 2019-08-11        Dokumentation aktualisiert
#                       Das Reading 'stat' zeigt jetzt den "aggregatedStatus" an, der von der API geliefert wird
#                                   Bsp: "Offline", "WorksProperly"
#                 Readings werden nur noch aktualisiert (und ein entsprechendes Event erzeugt),
#                          wenn sich ihr Wert geändert hat. "state" wird immer aktualisiert.
#                       Reading für Solarunterstützung hinzugefügt:
#                          "heating.solar.active"                                           => "Solar_aktiv",
#                          "heating.solar.pumps.circuit.status"                         => "Solar_Pumpe_Status",
#                          "heating.solar.rechargeSuppression.status"               => "Solar_Aufladeunterdrueckung_Status",
#                          "heating.solar.sensors.power.status"                         => "Solar_Sensor_Power_Status",
#                          "heating.solar.sensors.power.value"                      => "Solar_Sensor_Power",
#                          "heating.solar.sensors.temperature.collector.status"     => "Solar_Sensor_Temperatur_Kollektor_Status",
#                          "heating.solar.sensors.temperature.collector.value"  => "Solar_Sensor_Temperatur_Kollektor",
#                          "heating.solar.sensors.temperature.dhw.status"           => "Solar_Sensor_Temperatur_WW_Status",
#                          "heating.solar.sensors.temperature.dhw.value"            => "Solar_Sensor_Temperatur_WW",
#                          "heating.solar.statistics.hours"                            => "Solar_Sensor_Statistik_Stunden"
#                       ErrorListChanges (Fehlereintraege_Historie und Fehlereintraege_aktive) werden jetzt im JSON
#                          JSON Format ausgegeben (z.B.: "{"new":[],"current":[],"gone":[]}")
#
# 2019-09-07        Readings werden wieder erzeugt auch wenn sich der Wert nicht ändert
#
# 2019-11-23        Readings für "heating.power.consumption.total.*" hinzugefügt. Scheint identisch mit "heating.power.consumption.*"
#                   Behoben: Readings wurden nicht mehr aktualisiert, wenn in getResourceCallback die Resource nicht als JSON interpretiert werden konnte (Forum: #390)
#                   Behoben: vitoconnect bringt FHEM zum Absturz in Zeile 1376 (Forum: #391)
#                   Überwachung der Aktualität: Zeitpunkt des letzten Updates wird in State angezeigt (Forum #397)
#
# 2019-12-25        heating.solar.power.cumulativeProduced.value, heating.circuits.X.geofencing.active, heating.circuits.X.geofencing.status hinzugefügt
#                   Behoben: Readings wurden nicht mehr aktualisiert, wenn Resource an weiteren Stellen nicht als JSON interpretiert werden konnte(Forum: #390)
#
# 2020-03-02      Bei Aktionen wird nicht mehr auf defined($data) sondern auf ne "" getestet.
# 2020-04-05      s.o. 2. Versuch
#
# 2020-04-09      my $dir = path(AttrVal("global","logdir","log"));
#
# 2020-04-17      "Viessmann" Tippfehler gefixt
#                 Prototypen und "undef"s entfernt
#
# 2020-04-22      Reading heating.boiler.temperature.unit heating.operating.programs.holiday.active
#                            heating.operating.programs.holiday.end heating.operating.programs.holiday.start
#                 set Befehle hinzugefügt: Urlaub_Start, Urlaub_Ende, Urlaub_unschedule
#                            HKx-Name, HKx-Zeitsteuerung_Heizung, WW-Zeitplan, WW-Zirkulationspumpe_Zeitplan
#
# 2020-04-23      Refactoring (kein Einloggen mehr beim Ausführen einer Aktion)
# 2020-05-20      Neue Readings:
#                   heating.boiler.sensors.temperature.main.unit celsius
#                   heating.circuits.0.sensors.temperature.supply.unit celsius
#                   heating.dhw.sensors.temperature.hotWaterStorage.unit celsius
#                   heating.dhw.sensors.temperature.outlet.unit celsius
#                   heating.sensors.temperature.outside.unit celsius
#                 Fehlerbehandlung verbessert
#                 nur noch einloggen, wenn nötig (Token läuft nach 1h aus.)
#
# 2020-06-25      Fehlerbehandlung für API (statusCode 401 (UNAUTHORIZED), 404 (DEVICE_NOT_FOUND)
#                    und 429 (RATE_LIMIT_EXCEEDED) und 502 (DEVICE_COMMUNICATION_ERROR)
#                 Neue Readings für Vitodens 200-W B2HF-19 und Brennstoffzelle von Viessmann (PA2)
#                 Information aus dem GW auslesen (Attribut "vitoconnect_gw_readings" auf "1" setzen;
#                    noch unvollständig!)
#
# 2020-07-06      readings for heating.power.production.demandCoverage.* fixed
#                 bei logResponseOnce wird bei getCode angefangen damit auch gw.json neu erzeugt wird
#
# 2020-11-26      Bugfix für einige "set"-Kommandos für HK2 und HK3
#
# 2020-12-21      Neue Readings "heating.power.production.current.status" => "Stromproduktion_aktueller_Status",
#                   "heating.power.production.current.value" => "Stromproduktion",
#                   "heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
#                   "heating.sensors.power.output.value" => "Sensor_Stromproduktion" und
#                   "heating.circuits.X.operating.programs.Y.demand" =>
#                     "HK(X+1)-Solltemperatur_Y_Anforderung" (X=0,1,2 und Y=normal,reduced,comfort)
# 2021-02-21      Umstieg auf Endpoint v2 zur Authorization
#                 *experimentell* Attribut vitoconnect_device
#                 Workaround für Forum #561
#                 Neue Readings für "*ValueReadAt"
#
#   2021-07-19  Anpassungen für privaten apiKey. Redirect URIs muss "http://localhost:4200/" sein.
#               Nutzung des refresh_token
#
#   2021-07-19  neue Readings für heating.burners.0.*
#
#   ToDo:         timeout, intervall konfigurierbar machen
#                 Attribute implementieren und dokumentieren
#                 Mehrsprachigkeit
#                 Auswerten der Readings in getCode usw.
#                 devices/0 ? Was, wenn es mehrere Devices gibt?
#                 nach einem set Befehl Readings aktualisieren, vorher alten Timer löschen
#                 heating.circuits.0.operating.programs.holiday.changeEndDate action: end implementieren?
#

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;
use JSON::XS qw( decode_json );
use HttpUtils;
use Encode qw(decode encode);
use Data::Dumper;
use Path::Tiny;
use DateTime;
use Time::Piece;
use Time::Seconds;

eval "use FHEM::Meta;1"                   or my $modMetaAbsent = 1;                  ## no critic 'eval'
use FHEM::SynoModules::SMUtils qw (
                                   moduleVersion
                                  );                                                 # Hilfsroutinen Modul

my %vNotesIntern = (
  "0.2.1"  => "16.12.2024  German and English texts in UI".
  "0.2.0"  => "14.12.2024  FVersion introduced, a bit of code beautifying".
                          "sort keys per reading to ensure power readings are in the right order, day before dayvalue",
  "0.1.1"  => "12.12.2024  In case of more than one Gateway only allow Set_New if serial is provided. ".
                          "Get Object and Hash in Array readings. E.g. device.messages.errors.raw. ".
                          "In case of expired token (every hour) do not do uncessary gateway calls, just get the new token. ".
                          "This will safe API calls and reduce the API overhead. ",
  "0.1.0"  => "12.12.2024  first release with Version. "
);

my $client_secret = "2e21faa1-db2c-4d0b-a10f-575fd372bc8c-575fd372bc8c";
my $callback_uri  = "http://localhost:4200/";
my $apiURL        = "https://api.viessmann.com/iot/v1/equipment/";
my $iotURL_V1     = "https://api.viessmann.com/iot/v1/equipment/";
my $iotURL_V2     = "https://api.viessmann.com/iot/v2/features/";

my $RequestListMapping; # Über das Attribut Mapping definierte Readings zum überschreiben der RequestList
my %translations;       # Über das Attribut translations definierte Readings zum überschreiben der RequestList
my $Response;           # Gespeicherts JSON um dynamische Setter zu erstellen



# Feste Readings, orignal Verhalten des Moduls, können über RequestListMapping oder translations überschrieben werden.
# letzte SVN Version vor meinen Änderungen am 2024-11-16 oder letzte Version von Roger vom 8. November (https://forum.fhem.de/index.php?msg=1292441).
my $RequestListSvn = {
    "heating.boiler.serial.value"      => "Kessel_Seriennummer",
    "heating.boiler.temperature.value" => "Kessel_Solltemperatur",
    "heating.boiler.sensors.temperature.commonSupply.status" =>
      "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.commonSupply.unit" =>
      "Kessel_Common_Supply_Temperatur/Einheit",
    "heating.boiler.sensors.temperature.commonSupply.value" =>
      "Kessel_Common_Supply_Temperatur",
    "heating.boiler.sensors.temperature.main.status" => "Kessel_Status",
    "heating.boiler.sensors.temperature.main.unit" =>
      "Kesseltemperatur/Einheit",
    "heating.boiler.sensors.temperature.main.value" => "Kesseltemperatur",
    "heating.boiler.temperature.unit" => "Kesseltemperatur/Einheit",

    "heating.burner.active"              => "Brenner_aktiv",
    "heating.burner.automatic.status"    => "Brenner_Status",
    "heating.burner.automatic.errorCode" => "Brenner_Fehlercode",
    "heating.burner.current.power.value" => "Brenner_Leistung",
    "heating.burner.modulation.value"    => "Brenner_Modulation",
    "heating.burner.statistics.hours"    => "Brenner_Betriebsstunden",
    "heating.burner.statistics.starts"   => "Brenner_Starts",

    "heating.burners.0.active"            => "Brenner_1_aktiv",
    "heating.burners.0.modulation.unit"   => "Brenner_1_Modulation/Einheit",
    "heating.burners.0.modulation.value"  => "Brenner_1_Modulation",
    "heating.burners.0.statistics.hours"  => "Brenner_1_Betriebsstunden",
    "heating.burners.0.statistics.starts" => "Brenner_1_Starts",

    "heating.circuits.enabled"                   => "Aktive_Heizkreise",
    "heating.circuits.0.active"                  => "HK1-aktiv",
    "heating.circuits.0.type"                    => "HK1-Typ",
    "heating.circuits.0.circulation.pump.status" => "HK1-Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active" =>
      "HK1-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries" =>
      "HK1-Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status" => "HK1-Frostschutz_Status",
    "heating.circuits.0.geofencing.active"      => "HK1-Geofencing",
    "heating.circuits.0.geofencing.status"      => "HK1-Geofencing_Status",
    "heating.circuits.0.heating.curve.shift"    => "HK1-Heizkurve-Niveau",
    "heating.circuits.0.heating.curve.slope"    => "HK1-Heizkurve-Steigung",
    "heating.circuits.0.heating.schedule.active" =>
      "HK1-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries" =>
      "HK1-Zeitsteuerung_Heizung",
    "heating.circuits.0.name"                         => "HK1-Name",
    "heating.circuits.0.operating.modes.active.value" => "HK1-Betriebsart",
    "heating.circuits.0.operating.modes.dhw.active"   => "HK1-WW_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeating.active" =>
      "HK1-WW_und_Heizen_aktiv",
    "heating.circuits.0.operating.modes.dhwAndHeatingCooling.active" =>
      "HK1-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active" =>
      "HK1-Solltemperatur_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active" =>
      "HK1-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.0.operating.modes.heating.active" => "HK1-heizen_aktiv",
    "heating.circuits.0.operating.modes.normalStandby.active" =>
      "HK1-Normal_Standby_aktiv",
    "heating.circuits.0.operating.modes.standby.active" => "HK1-Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value" =>
      "HK1-Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active" =>
      "HK1-Solltemperatur_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.demand" =>
      "HK1-Solltemperatur_comfort_Anforderung",
    "heating.circuits.0.operating.programs.comfort.temperature" =>
      "HK1-Solltemperatur_comfort",
    "heating.circuits.0.operating.programs.eco.active" =>
      "HK1-Solltemperatur_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature" =>
      "HK1-Solltemperatur_eco",
    "heating.circuits.0.operating.programs.external.active" =>
      "HK1-External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature" =>
      "HK1-External_Temperatur",
    "heating.circuits.0.operating.programs.fixed.active" => "HK1-Fixed_aktiv",
    "heating.circuits.0.operating.programs.forcedLastFromSchedule.active" =>
      "HK1-forcedLastFromSchedule_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.active" =>
      "HK1-HolidayAtHome_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.end" =>
      "HK1-HolidayAtHome_Ende",
    "heating.circuits.0.operating.programs.holidayAtHome.start" =>
      "HK1-HolidayAtHome_Start",
    "heating.circuits.0.operating.programs.holiday.active" =>
      "HK1-Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start" => "HK1-Urlaub_Start",
    "heating.circuits.0.operating.programs.holiday.end"   => "HK1-Urlaub_Ende",
    "heating.circuits.0.operating.programs.normal.active" =>
      "HK1-Solltemperatur_aktiv",
    "heating.circuits.0.operating.programs.normal.demand" =>
      "HK1-Solltemperatur_Anforderung",
    "heating.circuits.0.operating.programs.normal.temperature" =>
      "HK1-Solltemperatur_normal",
    "heating.circuits.0.operating.programs.reduced.active" =>
      "HK1-Solltemperatur_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.demand" =>
      "HK1-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.0.operating.programs.reduced.temperature" =>
      "HK1-Solltemperatur_reduziert",
    "heating.circuits.0.operating.programs.summerEco.active" =>
      "HK1-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.0.operating.programs.standby.active" =>
      "HK1-Standby_aktiv",
    "heating.circuits.0.zone.mode.active" => "HK1-ZoneMode_aktive",
    "heating.circuits.0.sensors.temperature.room.status" => "HK1-Raum_Status",
    "heating.circuits.0.sensors.temperature.room.value" =>
      "HK1-Raum_Temperatur",
    "heating.circuits.0.sensors.temperature.supply.status" =>
      "HK1-Vorlauftemperatur_aktiv",
    "heating.circuits.0.sensors.temperature.supply.unit" =>
      "HK1-Vorlauftemperatur/Einheit",
    "heating.circuits.0.sensors.temperature.supply.value" =>
      "HK1-Vorlauftemperatur",
    "heating.circuits.0.zone.mode.active" => "HK1-ZoneMode_aktive",

    "heating.circuits.1.active"                  => "HK2-aktiv",
    "heating.circuits.1.type"                    => "HK2-Typ",
    "heating.circuits.1.circulation.pump.status" => "HK2-Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active" =>
      "HK2-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries" =>
      "HK2-Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status" => "HK2-Frostschutz_Status",
    "heating.circuits.1.geofencing.active"      => "HK2-Geofencing",
    "heating.circuits.1.geofencing.status"      => "HK2-Geofencing_Status",
    "heating.circuits.1.heating.curve.shift"    => "HK2-Heizkurve-Niveau",
    "heating.circuits.1.heating.curve.slope"    => "HK2-Heizkurve-Steigung",
    "heating.circuits.1.heating.schedule.active" =>
      "HK2-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries" =>
      "HK2-Zeitsteuerung_Heizung",
    "heating.circuits.1.name"                         => "HK2-Name",
    "heating.circuits.1.operating.modes.active.value" => "HK2-Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active"   => "HK2-WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active" =>
      "HK2-WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeatingCooling.active" =>
      "HK2-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" =>
      "HK2-Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" =>
      "HK2-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.heating.active" => "HK2-heizen_aktiv",
    "heating.circuits.1.operating.modes.normalStandby.active" =>
      "HK2-Normal_Standby_aktiv",
    "heating.circuits.1.operating.modes.standby.active" => "HK2-Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" =>
      "HK2-Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" =>
      "HK2-Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.demand" =>
      "HK2-Solltemperatur_comfort_Anforderung",
    "heating.circuits.1.operating.programs.comfort.temperature" =>
      "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" =>
      "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" =>
      "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" =>
      "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" =>
      "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.fixed.active" => "HK2-Fixed_aktiv",
    "heating.circuits.1.operating.programs.forcedLastFromSchedule.active" =>
      "HK2-forcedLastFromSchedule_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.active" =>
      "HK2-HolidayAtHome_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.end" =>
      "HK2-HolidayAtHome_Ende",
    "heating.circuits.1.operating.programs.holidayAtHome.start" =>
      "HK2-HolidayAtHome_Start",
    "heating.circuits.1.operating.programs.holiday.active" =>
      "HK2-Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" => "HK2-Urlaub_Start",
    "heating.circuits.1.operating.programs.holiday.end"   => "HK2-Urlaub_Ende",
    "heating.circuits.1.operating.programs.normal.active" =>
      "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.demand" =>
      "HK2-Solltemperatur_Anforderung",
    "heating.circuits.1.operating.programs.normal.temperature" =>
      "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active" =>
      "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.demand" =>
      "HK2-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.1.operating.programs.reduced.temperature" =>
      "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.summerEco.active" =>
      "HK2-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.1.operating.programs.standby.active" =>
      "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" => "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.room.value" =>
      "HK2-Raum_Temperatur",
    "heating.circuits.1.sensors.temperature.supply.status" =>
      "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.unit" =>
      "HK2-Vorlauftemperatur/Einheit",
    "heating.circuits.1.sensors.temperature.supply.value" =>
      "HK2-Vorlauftemperatur",
    "heating.circuits.1.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.2.active"                  => "HK3-aktiv",
    "heating.circuits.2.type"                    => "HK3-Typ",
    "heating.circuits.2.circulation.pump.status" => "HK3-Zirkulationspumpe",
    "heating.circuits.2.circulation.schedule.active" =>
      "HK3-Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.2.circulation.schedule.entries" =>
      "HK3-Zeitsteuerung_Zirkulation",
    "heating.circuits.2.frostprotection.status" => "HK3-Frostschutz_Status",
    "heating.circuits.2.geofencing.active"      => "HK3-Geofencing",
    "heating.circuits.2.geofencing.status"      => "HK3-Geofencing_Status",
    "heating.circuits.2.heating.curve.shift"    => "HK3-Heizkurve-Niveau",
    "heating.circuits.2.heating.curve.slope"    => "HK3-Heizkurve-Steigung",
    "heating.circuits.2.heating.schedule.active" =>
      "HK3-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.2.heating.schedule.entries" =>
      "HK3-Zeitsteuerung_Heizung",
    "heating.circuits.2.name"                         => "HK3-Name",
    "heating.circuits.2.operating.modes.active.value" => "HK3-Betriebsart",
    "heating.circuits.2.operating.modes.dhw.active"   => "HK3-WW_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeating.active" =>
      "HK3-WW_und_Heizen_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeatingCooling.active" =>
      "HK3-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.2.operating.modes.forcedNormal.active" =>
      "HK3-Solltemperatur_erzwungen",
    "heating.circuits.2.operating.modes.forcedReduced.active" =>
      "HK3-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.2.operating.modes.heating.active" => "HK3-heizen_aktiv",
    "heating.circuits.2.operating.modes.normalStandby.active" =>
      "HK3-Normal_Standby_aktiv",
    "heating.circuits.2.operating.modes.standby.active" => "HK3-Standby_aktiv",
    "heating.circuits.2.operating.programs.active.value" =>
      "HK3-Programmstatus",
    "heating.circuits.2.operating.programs.comfort.active" =>
      "HK3-Solltemperatur_comfort_aktiv",
    "heating.circuits.2.operating.programs.comfort.demand" =>
      "HK3-Solltemperatur_comfort_Anforderung",
    "heating.circuits.2.operating.programs.comfort.temperature" =>
      "HK3-Solltemperatur_comfort",
    "heating.circuits.2.operating.programs.eco.active" =>
      "HK3-Solltemperatur_eco_aktiv",
    "heating.circuits.2.operating.programs.eco.temperature" =>
      "HK3-Solltemperatur_eco",
    "heating.circuits.2.operating.programs.external.active" =>
      "HK3-External_aktiv",
    "heating.circuits.2.operating.programs.external.temperature" =>
      "HK3-External_Temperatur",
    "heating.circuits.2.operating.programs.fixed.active" => "HK3-Fixed_aktiv",
    "heating.circuits.2.operating.programs.forcedLastFromSchedule.active" =>
      "HK3-forcedLastFromSchedule_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.active" =>
      "HK3-HolidayAtHome_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.end" =>
      "HK3-HolidayAtHome_Ende",
    "heating.circuits.2.operating.programs.holidayAtHome.start" =>
      "HK3-HolidayAtHome_Start",
    "heating.circuits.2.operating.programs.holiday.active" =>
      "HK3-Urlaub_aktiv",
    "heating.circuits.2.operating.programs.holiday.start" => "HK3-Urlaub_Start",
    "heating.circuits.2.operating.programs.holiday.end"   => "HK3-Urlaub_Ende",
    "heating.circuits.2.operating.programs.normal.active" =>
      "HK3-Solltemperatur_aktiv",
    "heating.circuits.2.operating.programs.normal.demand" =>
      "HK3-Solltemperatur_Anforderung",
    "heating.circuits.2.operating.programs.normal.temperature" =>
      "HK3-Solltemperatur_normal",
    "heating.circuits.2.operating.programs.reduced.active" =>
      "HK3-Solltemperatur_reduziert_aktiv",
    "heating.circuits.2.operating.programs.reduced.demand" =>
      "HK3-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.2.operating.programs.reduced.temperature" =>
      "HK3-Solltemperatur_reduziert",
    "heating.circuits.2.operating.programs.summerEco.active" =>
      "HK3-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.2.operating.programs.standby.active" =>
      "HK3-Standby_aktiv",
    "heating.circuits.2.sensors.temperature.room.status" => "HK3-Raum_Status",
    "heating.circuits.2.sensors.temperature.room.value" =>
      "HK3-Raum_Temperatur",
    "heating.circuits.2.sensors.temperature.supply.status" =>
      "HK3-Vorlauftemperatur_aktiv",
    "heating.circuits.2.sensors.temperature.supply.unit" =>
      "HK3-Vorlauftemperatur/Einheit",
    "heating.circuits.2.sensors.temperature.supply.value" =>
      "HK3-Vorlauftemperatur",
    "heating.circuits.2.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.3.geofencing.active" => "HK4-Geofencing",
    "heating.circuits.3.geofencing.status" => "HK4-Geofencing_Status",
    "heating.circuits.3.operating.programs.summerEco.active" =>
      "HK4-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.3.zone.mode.active" => "HK4-ZoneMode_aktive",

    "heating.compressor.active"                     => "Kompressor_aktiv",
    "heating.configuration.multiFamilyHouse.active" => "Mehrfamilenhaus_aktiv",
    "heating.configuration.regulation.mode"         => "Regulationmode",
    "heating.controller.serial.value"  => "Controller_Seriennummer",
    "heating.device.time.offset.value" => "Device_Time_Offset",
    "heating.dhw.active"               => "WW-aktiv",
    "heating.dhw.status"               => "WW-Status",
    "heating.dhw.charging.active"      => "WW-Aufladung",

    "heating.dhw.charging.level.bottom" => "WW-Speichertemperatur_unten",
    "heating.dhw.charging.level.middle" => "WW-Speichertemperatur_mitte",
    "heating.dhw.charging.level.top"    => "WW-Speichertemperatur_oben",
    "heating.dhw.charging.level.value"  => "WW-Speicherladung",

    "heating.dhw.oneTimeCharge.active" => "WW-einmaliges_Aufladen",
    "heating.dhw.pumps.circulation.schedule.active" =>
      "WW-Zirkulationspumpe_Zeitsteuerung_aktiv",
    "heating.dhw.pumps.circulation.schedule.entries" =>
      "WW-Zirkulationspumpe_Zeitplan",
    "heating.dhw.pumps.circulation.status" => "WW-Zirkulationspumpe_Status",
    "heating.dhw.pumps.primary.status"     => "WW-Zirkulationspumpe_primaer",
    "heating.dhw.sensors.temperature.outlet.status" =>
      "WW-Sensoren_Auslauf_Status",
    "heating.dhw.sensors.temperature.outlet.unit" =>
      "WW-Sensoren_Auslauf_Wert/Einheit",
    "heating.dhw.sensors.temperature.outlet.value" =>
      "WW-Sensoren_Auslauf_Wert",
    "heating.dhw.temperature.main.value"       => "WW-Haupttemperatur",
    "heating.dhw.temperature.hysteresis.value" => "WW-Hysterese",
    "heating.dhw.temperature.temp2.value"      => "WW-Temperatur_2",
    "heating.dhw.sensors.temperature.hotWaterStorage.status" =>
      "WW-Temperatur_aktiv",
    "heating.dhw.sensors.temperature.hotWaterStorage.unit" =>
      "WW-Isttemperatur/Einheit",
    "heating.dhw.sensors.temperature.hotWaterStorage.value" =>
      "WW-Isttemperatur",
    "heating.dhw.temperature.value" => "WW-Solltemperatur",
    "heating.dhw.schedule.active"   => "WW-zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries"  => "WW-Zeitplan",

    "heating.errors.active.entries"  => "Fehlereintraege_aktive",
    "heating.errors.history.entries" => "Fehlereintraege_Historie",

    "heating.flue.sensors.temperature.main.status" => "Abgassensor_Status",
    "heating.flue.sensors.temperature.main.unit" =>
      "Abgassensor_Temperatur/Einheit",
    "heating.flue.sensors.temperature.main.value" => "Abgassensor_Temperatur",

    "heating.fuelCell.operating.modes.active.value" => "Brennstoffzelle_Mode",
    "heating.fuelCell.operating.modes.ecological.active" =>
      "Brennstoffzelle_Mode_Ecological",
    "heating.fuelCell.operating.modes.economical.active" =>
      "Brennstoffzelle_Mode_Economical",
    "heating.fuelCell.operating.modes.heatControlled.active" =>
      "Brennstoffzelle_wärmegesteuert",
    "heating.fuelCell.operating.modes.maintenance.active" =>
      "Brennstoffzelle_Wartung",
    "heating.fuelCell.operating.modes.standby.active" =>
      "Brennstoffzelle_Standby",
    "heating.fuelCell.operating.phase.value" => "Brennstoffzelle_Phase",
    "heating.fuelCell.power.production.day" =>
      "Brennstoffzelle_Stromproduktion/Tag",
    "heating.fuelCell.power.production.month" =>
      "Brennstoffzelle_Stromproduktion/Monat",
    "heating.fuelCell.power.production.unit" =>
      "Brennstoffzelle_Stromproduktion/Einheit",
    "heating.fuelCell.power.production.week" =>
      "Brennstoffzelle_Stromproduktion/Woche",
    "heating.fuelCell.power.production.year" =>
      "Brennstoffzelle_Stromproduktion/Jahr",
    "heating.fuelCell.sensors.temperature.return.status" =>
      "Brennstoffzelle_Temperatur_Ruecklauf_Status",
    "heating.fuelCell.sensors.temperature.return.unit" =>
      "Brennstoffzelle_Temperatur_Ruecklauf/Einheit",
    "heating.fuelCell.sensors.temperature.return.value" =>
      "Brennstoffzelle_Temperatur_Ruecklauf",
    "heating.fuelCell.sensors.temperature.supply.status" =>
      "Brennstoffzelle_Temperatur_Vorlauf_Status",
    "heating.fuelCell.sensors.temperature.supply.unit" =>
      "Brennstoffzelle_Temperatur_Vorlauf/Einheit",
    "heating.fuelCell.sensors.temperature.supply.value" =>
      "Brennstoffzelle_Temperatur_Vorlauf",
    "heating.fuelCell.statistics.availabilityRate" =>
      "Brennstoffzelle_Statistic_Verfügbarkeit",
    "heating.fuelCell.statistics.insertions" =>
      "Brennstoffzelle_Statistic_Einschub",
    "heating.fuelCell.statistics.operationHours" =>
      "Brennstoffzelle_Statistic_Bestriebsstunden",
    "heating.fuelCell.statistics.productionHours" =>
      "Brennstoffzelle_Statistic_Produktionsstunden",
    "heating.fuelCell.statistics.productionStarts" =>
      "Brennstoffzelle_Statistic_Produktionsstarts",

    "heating.gas.consumption.dhw.day"   => "Gasverbrauch_WW/Tag",
    "heating.gas.consumption.dhw.week"  => "Gasverbrauch_WW/Woche",
    "heating.gas.consumption.dhw.month" => "Gasverbrauch_WW/Monat",
    "heating.gas.consumption.dhw.year"  => "Gasverbrauch_WW/Jahr",
    "heating.gas.consumption.dhw.dayValueReadAt" =>
      "Gasverbrauch_WW/Tag_gelesen_am",
    "heating.gas.consumption.dhw.weekValueReadAt" =>
      "Gasverbrauch_WW/Woche_gelesen_am",
    "heating.gas.consumption.dhw.monthValueReadAt" =>
      "Gasverbrauch_WW/Monat_gelesen_am",
    "heating.gas.consumption.dhw.yearValueReadAt" =>
      "Gasverbrauch_WW/Jahr_gelesen_am",
    "heating.gas.consumption.dhw.unit" => "Gasverbrauch_WW/Einheit",

    "heating.gas.consumption.heating.day"   => "Gasverbrauch_Heizung/Tag",
    "heating.gas.consumption.heating.week"  => "Gasverbrauch_Heizung/Woche",
    "heating.gas.consumption.heating.month" => "Gasverbrauch_Heizung/Monat",
    "heating.gas.consumption.heating.year"  => "Gasverbrauch_Heizung/Jahr",
    "heating.gas.consumption.heating.dayValueReadAt" =>
      "Gasverbrauch_Heizung/Tag_gelesen_am",
    "heating.gas.consumption.heating.weekValueReadAt" =>
      "Gasverbrauch_Heizung/Woche_gelesen_am",
    "heating.gas.consumption.heating.monthValueReadAt" =>
      "Gasverbrauch_Heizung/Monat_gelesen_am",
    "heating.gas.consumption.heating.yearValueReadAt" =>
      "Gasverbrauch_Heizung/Jahr_gelesen_am",
    "heating.gas.consumption.heating.unit" => "Gasverbrauch_Heizung/Einheit",
    "heating.gas.consumption.total.day"    => "Gasverbrauch_Total/Tag",
    "heating.gas.consumption.total.month"  => "Gasverbrauch_Total/Monat",
    "heating.gas.consumption.total.unit"   => "Gasverbrauch_Total/Einheit",
    "heating.gas.consumption.total.week"   => "Gasverbrauch_Total/Woche",
    "heating.gas.consumption.total.year"   => "Gasverbrauch_Total/Jahr",
    "heating.gas.consumption.total.dayValueReadAt" =>
      "Gasverbrauch_Total/Tag_gelesen_am",
    "heating.gas.consumption.total.monthValueReadAt" =>
      "Gasverbrauch_Total/Woche_gelesen_am",
    "heating.gas.consumption.total.weekValueReadAt" =>
      "Gasverbrauch_Total/Woche_gelesen_am",
    "heating.gas.consumption.total.yearValueReadAt" =>
      "Gasverbrauch_Total/Jahr_gelesen_am",

    "heating.gas.consumption.fuelCell.day" =>
      "Gasverbrauch_Brennstoffzelle/Tag",
    "heating.gas.consumption.fuelCell.week" =>
      "Gasverbrauch_Brennstoffzelle/Woche",
    "heating.gas.consumption.fuelCell.month" =>
      "Gasverbrauch_Brennstoffzelle/Monat",
    "heating.gas.consumption.fuelCell.year" =>
      "Gasverbrauch_Brennstoffzelle/Jahr",
    "heating.gas.consumption.fuelCell.unit" =>
      "Gasverbrauch_Brennstoffzelle/Einheit",

    "heating.heat.production.day"   => "Wärmeproduktion/Tag",
    "heating.heat.production.month" => "Wärmeproduktion/Woche",
    "heating.heat.production.unit"  => "Wärmeproduktion/Einheit",
    "heating.heat.production.week"  => "Wärmeproduktion/Woche",
    "heating.heat.production.year"  => "Wärmeproduktion/Jahr",

    "heating.operating.programs.holiday.active" => "Urlaub_aktiv",
    "heating.operating.programs.holiday.end"    => "Urlaub_Ende",
    "heating.operating.programs.holiday.start"  => "Urlaub_Start",

    "heating.operating.programs.holidayAtHome.active" => "holidayAtHome_aktiv",
    "heating.operating.programs.holidayAtHome.end"    => "holidayAtHome_Ende",
    "heating.operating.programs.holidayAtHome.start"  => "holidayAtHome_Start",

    "heating.power.consumption.day"   => "Stromverbrauch/Tag",
    "heating.power.consumption.month" => "Stromverbrauch/Monat",
    "heating.power.consumption.week"  => "Stromverbrauch/Woche",
    "heating.power.consumption.year"  => "Stromverbrauch/Jahr",
    "heating.power.consumption.unit"  => "Stromverbrauch/Einheit",

    "heating.power.consumption.dhw.day"   => "Stromverbrauch_WW/Tag",
    "heating.power.consumption.dhw.month" => "Stromverbrauch_WW/Monat",
    "heating.power.consumption.dhw.week"  => "Stromverbrauch_WW/Woche",
    "heating.power.consumption.dhw.year"  => "Stromverbrauch_WW/Jahr",
    "heating.power.consumption.dhw.unit"  => "Stromverbrauch_WW/Einheit",

    "heating.power.consumption.heating.day"   => "Stromverbrauch_Heizung/Tag",
    "heating.power.consumption.heating.month" => "Stromverbrauch_Heizung/Monat",
    "heating.power.consumption.heating.week"  => "Stromverbrauch_Heizung/Woche",
    "heating.power.consumption.heating.year"  => "Stromverbrauch_Heizung/Jahr",
    "heating.power.consumption.heating.unit" =>
      "Stromverbrauch_Heizung/Einheit",

    "heating.power.consumption.total.day"   => "Stromverbrauch_Total/Tag",
    "heating.power.consumption.total.month" => "Stromverbrauch_Total/Monat",
    "heating.power.consumption.total.week"  => "Stromverbrauch_Total/Woche",
    "heating.power.consumption.total.year"  => "Stromverbrauch_Total/Jahr",
    "heating.power.consumption.total.dayValueReadAt" =>
      "Stromverbrauch_Total/Tag_gelesen_am",
    "heating.power.consumption.total.monthValueReadAt" =>
      "Stromverbrauch_Total/Monat_gelesen_am",
    "heating.power.consumption.total.weekValueReadAt" =>
      "Stromverbrauch_Total/Woche_gelesen_am",
    "heating.power.consumption.total.yearValueReadAt" =>
      "Stromverbrauch_Total/Jahr_gelesen_am",
    "heating.power.consumption.total.unit" => "Stromverbrauch_Total/Einheit",

    "heating.power.production.current.status" =>
      "Stromproduktion_aktueller_Status",
    "heating.power.production.current.value" => "Stromproduktion",

    "heating.power.production.demandCoverage.current.unit" =>
      "Stromproduktion_Bedarfsabdeckung/Einheit",
    "heating.power.production.demandCoverage.current.value" =>
      "Stromproduktion_Bedarfsabdeckung",
    "heating.power.production.demandCoverage.total.day" =>
      "Stromproduktion_Bedarfsabdeckung_total/Tag",
    "heating.power.production.demandCoverage.total.month" =>
      "Stromproduktion_Bedarfsabdeckung_total/Monat",
    "heating.power.production.demandCoverage.total.unit" =>
      "Stromproduktion_Bedarfsabdeckung_total/Einheit",
    "heating.power.production.demandCoverage.total.week" =>
      "Stromproduktion_Bedarfsabdeckung_total/Woche",
    "heating.power.production.demandCoverage.total.year" =>
      "Stromproduktion_Bedarfsabdeckung_total/Jahr",

    "heating.power.production.day"   => "Stromproduktion_Total/Tag",
    "heating.power.production.month" => "Stromproduktion_Total/Monat",
    "heating.power.production.productionCoverage.current.unit" =>
      "Stromproduktion_Produktionsabdeckung/Einheit",
    "heating.power.production.productionCoverage.current.value" =>
      "Stromproduktion_Produktionsabdeckung",
    "heating.power.production.productionCoverage.total.day" =>
      "Stromproduktion_Produktionsabdeckung_Total/Tag",
    "heating.power.production.productionCoverage.total.month" =>
      "Stromproduktion_Produktionsabdeckung_Total/Monat",
    "heating.power.production.productionCoverage.total.unit" =>
      "Stromproduktion_Produktionsabdeckung_Total/Einheit",
    "heating.power.production.productionCoverage.total.week" =>
      "Stromproduktion_Produktionsabdeckung_Total/Woche",
    "heating.power.production.productionCoverage.total.year" =>
      "Stromproduktion_Produktionsabdeckung_Total/Jahr",
    "heating.power.production.unit" => "Stromproduktion_Total/Einheit",
    "heating.power.production.week" => "Stromproduktion_Total/Woche",
    "heating.power.production.year" => "Stromproduktion_Total/Jahr",

    "heating.power.purchase.current.unit"  => "Stromkauf/Einheit",
    "heating.power.purchase.current.value" => "Stromkauf",
    "heating.power.sold.current.unit"      => "Stromverkauf/Einheit",
    "heating.power.sold.current.value"     => "Stromverkauf",
    "heating.power.sold.day"               => "Stromverkauf/Tag",
    "heating.power.sold.month"             => "Stromverkauf/Monat",
    "heating.power.sold.unit"              => "Stromverkauf/Einheit",
    "heating.power.sold.week"              => "Stromverkauf/Woche",
    "heating.power.sold.year"              => "Stromverkauf/Jahr",

    "heating.sensors.pressure.supply.status" => "Drucksensor_Vorlauf_Status",
    "heating.sensors.pressure.supply.unit"   => "Drucksensor_Vorlauf/Einheit",
    "heating.sensors.pressure.supply.value"  => "Drucksensor_Vorlauf",

    "heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
    "heating.sensors.power.output.value"  => "Sensor_Stromproduktion",

    "heating.sensors.temperature.outside.status"      => "Aussen_Status",
    "heating.sensors.temperature.outside.statusWired" => "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" =>
      "Aussen_StatusWireless",
    "heating.sensors.temperature.outside.unit"  => "Aussentemperatur/Einheit",
    "heating.sensors.temperature.outside.value" => "Aussentemperatur",

    "heating.service.timeBased.serviceDue" => "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" =>
      "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" =>
      "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" => "Service_Letzter",
    "heating.service.burnerBased.serviceDue" =>
      "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" =>
      "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" =>
      "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" =>
      "Service_Letzter_brennerbasiert",

    "heating.solar.active"               => "Solar_aktiv",
    "heating.solar.pumps.circuit.status" => "Solar_Pumpe_Status",
    "heating.solar.rechargeSuppression.status" =>
      "Solar_Aufladeunterdrueckung_Status",
    "heating.solar.sensors.power.status" => "Solar_Sensor_Power_Status",
    "heating.solar.sensors.power.value"  => "Solar_Sensor_Power",
    "heating.solar.sensors.temperature.collector.status" =>
      "Solar_Sensor_Temperatur_Kollektor_Status",
    "heating.solar.sensors.temperature.collector.value" =>
      "Solar_Sensor_Temperatur_Kollektor",
    "heating.solar.sensors.temperature.dhw.status" =>
      "Solar_Sensor_Temperatur_WW_Status",
    "heating.solar.sensors.temperature.dhw.value" =>
      "Solar_Sensor_Temperatur_WW",
    "heating.solar.statistics.hours" => "Solar_Sensor_Statistik_Stunden",

    "heating.solar.power.cumulativeProduced.value" =>
      "Solarproduktion_Gesamtertrag",
    "heating.solar.power.production.month" => "Solarproduktion/Monat",
    "heating.solar.power.production.day"   => "Solarproduktion/Tag",
    "heating.solar.power.production.unit"  => "Solarproduktion/Einheit",
    "heating.solar.power.production.week"  => "Solarproduktion/Woche",
    "heating.solar.power.production.year"  => "Solarproduktion/Jahr"
};

my $RequestListRoger = {
    "device.serial.value"                                       => "Seriennummer",
    "device.messages.errors.raw.entries"                        => "Fehlermeldungen",

    "heating.boiler.serial.value"                               => "Kessel_Seriennummer",
    "heating.boiler.temperature.value"                          => "Kessel_Solltemp__C",
    "heating.boiler.sensors.temperature.commonSupply.status"    => "Kessel_Common_Supply",
    "heating.boiler.sensors.temperature.commonSupply.unit"      => "Kessel_Common_Supply_Temp_Einheit",
    "heating.boiler.sensors.temperature.commonSupply.value"     => "Kessel_Common_Supply_Temp__C",
    "heating.boiler.sensors.temperature.main.status"            => "Kessel_Status",
    "heating.boiler.sensors.temperature.main.value"             => "Kessel_Temp__C",
    "heating.boiler.sensors.temperature.main.unit"              => "Kessel_Temp_Einheit",
    "heating.boiler.temperature.unit"                           => "Kesseltemp_Einheit",

    "heating.device.time.offset.value"                          => "Device_Time_Offset",
    "heating.sensors.temperature.outside.status"                => "Aussen_Status",
    "heating.sensors.temperature.outside.unit"                  => "Temp_aussen_Einheit",
    "heating.sensors.temperature.outside.value"                 => "Temp_aussen__C",

    "heating.burners.0.active"                                  => "Brenner_1_aktiv",
    "heating.burners.0.statistics.starts"                       => "Brenner_1_Starts",
    "heating.burners.0.statistics.hours"                        => "Brenner_1_Betriebsstunden__h",
    "heating.burners.0.modulation.value"                        => "Brenner_1_Modulation__Prz",
    "heating.burners.0.modulation.unit"                         => "Brenner_1_Modulation_Einheit",



    "heating.burner.active"                                     => "Brenner_aktiv",
    "heating.burner.automatic.status"                           => "Brenner_Status",
    "heating.burner.automatic.errorCode"                        => "Brenner_Fehlercode",
    "heating.burner.current.power.value"                        => "Brenner_Leistung",
    "heating.burner.modulation.value"                           => "Brenner_Modulation",
    "heating.burner.statistics.hours"                           => "Brenner_Betriebsstunden__h",
    "heating.burner.statistics.starts"                          => "Brenner_Starts",

    "heating.sensors.volumetricFlow.allengra.status"            => "Heiz_Volumenstrom_Status",
    "heating.sensors.volumetricFlow.allengra.value"             => "Heiz_Volumenstrom__l/h",

    "heating.circuits.enabled"                                  => "aktive_Heizkreise",
    "heating.circuits.0.name"                                   => "HK1_Name",
    "heating.circuits.0.operating.modes.active.value"           => "HK1_Betriebsart",
    "heating.circuits.0.active"                                 => "HK1_aktiv",
    "heating.circuits.0.type"                                   => "HK1_Typ",
    "heating.circuits.0.circulation.pump.status"                => "HK1_Zirkulationspumpe",
    "heating.circuits.0.circulation.schedule.active"            => "HK1_Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.0.circulation.schedule.entries"           => "HK1_Zeitsteuerung_Zirkulation",
    "heating.circuits.0.frostprotection.status"                 => "HK1_Frostschutz_Status",
    "heating.circuits.0.geofencing.active"                      => "HK1_Geofencing",
    "heating.circuits.0.geofencing.status"                      => "HK1_Geofencing_Status",
    "heating.circuits.0.heating.curve.shift"                    => "HK1_Heizkurve_Niveau",
    "heating.circuits.0.heating.curve.slope"                    => "HK1_Heizkurve_Steigung",
    "heating.circuits.0.heating.schedule.active"                => "HK1_Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.0.heating.schedule.entries"               => "HK1_Zeitsteuerung_Heizung",

    "heating.circuits.0.operating.modes.dhwAndHeatingCooling.active"    => "HK1_WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.0.operating.modes.forcedNormal.active"            => "HK1_Soll_Temp_erzwungen",
    "heating.circuits.0.operating.modes.forcedReduced.active"           => "HK1_Reduzierte_Temp_erzwungen",
    "heating.circuits.0.operating.modes.heating.active"                 => "HK1_heizen_aktiv",
    "heating.circuits.0.operating.modes.normalStandby.active"           => "HK1_Normal_Standby_aktiv",
    "heating.circuits.0.operating.modes.standby.active"                 => "HK1_Standby_aktiv",
    "heating.circuits.0.operating.programs.active.value"                => "HK1_Programmstatus",
    "heating.circuits.0.operating.programs.comfort.active"              => "HK1_Soll_Temp_comfort_aktiv",
    "heating.circuits.0.operating.programs.comfort.demand"              => "HK1_Soll_Temp_comfort_Anforderung",
    "heating.circuits.0.operating.programs.comfort.temperature"         => "HK1_Soll_Temp_comfort__C",
    "heating.circuits.0.operating.programs.eco.active"                  => "HK1_Soll_Temp_eco_aktiv",
    "heating.circuits.0.operating.programs.eco.temperature"             => "HK1_Soll_Temp_eco__C",
    "heating.circuits.0.operating.programs.external.active"             => "HK1_External_aktiv",
    "heating.circuits.0.operating.programs.external.temperature"        => "HK1_External_Temp",
    "heating.circuits.0.operating.programs.fixed.active"                => "HK1_Fixed_aktiv",
    "heating.circuits.0.operating.programs.forcedLastFromSchedule.active"   => "HK1_forcedLastFromSchedule_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.active"        => "HK1_HolidayAtHome_aktiv",
    "heating.circuits.0.operating.programs.holidayAtHome.end"           => "HK1_HolidayAtHome_Ende",
    "heating.circuits.0.operating.programs.holidayAtHome.start"         => "HK1_HolidayAtHome_Start",
    "heating.circuits.0.operating.programs.holiday.active"              => "HK1_Urlaub_aktiv",
    "heating.circuits.0.operating.programs.holiday.start"               => "HK1_Urlaub_Start_Zeit",
    "heating.circuits.0.operating.programs.holiday.end"                 => "HK1_Urlaub_Ende_Zeit",
    "heating.circuits.0.operating.programs.normal.active"               => "HK1_Soll_Temp_aktiv",
    "heating.circuits.0.operating.programs.normal.demand"               => "HK1_Soll_Temp_Anforderung",
    "heating.circuits.0.operating.programs.normal.temperature"          => "HK1_Soll_Temp_normal",
    "heating.circuits.0.operating.programs.reduced.active"              => "HK1_Soll_Temp_reduziert_aktiv",
    "heating.circuits.0.operating.programs.reduced.demand"              => "HK1_Soll_Temp_reduziert_Anforderung",
    "heating.circuits.0.operating.programs.reduced.temperature"         => "HK1_Soll_Temp_reduziert",
    "heating.circuits.0.operating.programs.summerEco.active"            => "HK1_Soll_Temp_SummerEco_aktiv",
    "heating.circuits.0.operating.programs.standby.active"              => "HK1_Standby_aktiv",
    "heating.circuits.0.zone.mode.active"                               => "HK1_ZoneMode_aktive",
    "heating.circuits.0.sensors.temperature.room.status"                => "HK1_Raum_Status",
    "heating.circuits.0.sensors.temperature.room.value"                 => "HK1_Raum_Temp",
    "heating.circuits.0.sensors.temperature.supply.status"              => "HK1_Vorlauf_Temp_Status",
    "heating.circuits.0.sensors.temperature.supply.unit"                => "HK1_Vorlauf_Temp_Einheit",
    "heating.circuits.0.sensors.temperature.supply.value"               => "HK1_Vorlauf_Temp__C",
    "heating.circuits.0.zone.mode.active"                               => "HK1_ZoneMode_aktive",

    "heating.dhw.operating.modes.active.value"                  => "WW_Betriebsart",
    "heating.dhw.operating.modes.balanced.active"               => "WW_Betriebsart_balanced",
    "heating.dhw.operating.modes.off.active"                    => "WW_Betriebsart_off",
    "heating.dhw.temperature.main.value"                        => "WW_Temp_Soll__C",
    "heating.dhw.sensors.temperature.hotWaterStorage.value"     => "WW_Temp_Ist__C",
    "heating.dhw.sensors.temperature.hotWaterStorage.unit"      => "WW_Temp_Ist_Einheit",
    "heating.dhw.oneTimeCharge.active"                          => "WW_einmaliges_Aufladen",
    "heating.dhw.sensors.temperature.dhwCylinder.value"         => "WW_Temp__C",
    "heating.dhw.sensors.temperature.dhwCylinder.status"        => "WW_Temp_Status",
    "heating.dhw.hygiene.active"                                => "WW_Hygiene_laeft",
    "heating.dhw.hygiene.enabled"                               => "WW_Hygiene_enabled",
    "heating.dhw.hygiene.trigger.startHour"                     => "WW_Hygiene_Start__hh",
    "heating.dhw.hygiene.trigger.startMinute"                   => "WW_Hygiene_Start__mm",
    "heating.dhw.hygiene.trigger.weekdays"                      => "WW_Hygiene_Start__dd",
    "heating.dhw.temperature.hygiene.value"                     => "WW_Hygiene_Temp__C",

    "heating.dhw.pumps.circulation.schedule.active"             => "WW_Zirkulationspumpe_Zeitsteuerung_aktiv",
    "heating.dhw.pumps.circulation.schedule.entries"            => "WW_Zirkulationspumpe_Zeitplan",
    "heating.dhw.pumps.circulation.status"                      => "WW_Zirkulationspumpe_Status",
    "heating.dhw.pumps.primary.status"                          => "WW_Zirkulationspumpe_primaer",
    "heating.dhw.sensors.temperature.outlet.status"             => "WW_Sensoren_Auslauf_Status",
    "heating.dhw.sensors.temperature.outlet.unit"               => "WW_Sensoren_Auslauf_Wert_Einheit",
    "heating.dhw.sensors.temperature.outlet.value"              => "WW_Sensoren_Auslauf_Wert",
    "heating.dhw.temperature.hysteresis.value"                  => "WW_Hysterese",
    "heating.dhw.sensors.temperature.hotWaterStorage.status"    => "WW_Temp_aktiv",
#   "heating.dhw.temperature.value"                             => "WW_Solltemp__C",
    "heating.dhw.schedule.active"                               => "WW_zeitgesteuert_aktiv",
    "heating.dhw.schedule.entries"                              => "WW_Zeitplan",
    "heating.dhw.temperature.temp2.value"                       => "WW_Temp2__C",

    "heating.gas.consumption.summary.dhw.currentDay"            => "Gas_WW_Day__m3",
    "heating.gas.consumption.summary.dhw.lastSevenDays"         => "Gas_WW_7dLast__m3",
    "heating.gas.consumption.summary.dhw.currentMonth"          => "Gas_WW_Month__m3",
    "heating.gas.consumption.summary.dhw.lastMonth"             => "Gas_WW_MonthLast__m3",
    "heating.gas.consumption.summary.dhw.currentYear"           => "Gas_WW_Year__m3",
    "heating.gas.consumption.summary.dhw.lastYear"              => "Gas_WW_YearLast__m3",

    "heating.gas.consumption.summary.heating.currentDay"        => "Gas_Day__m3",
    "heating.gas.consumption.summary.heating.lastSevenDays"     => "Gas_7dLast__m3",
    "heating.gas.consumption.summary.heating.currentMonth"      => "Gas_Month__m3",
    "heating.gas.consumption.summary.heating.lastMonth"         => "Gas_MonthLast__m3",
    "heating.gas.consumption.summary.heating.currentYear"       => "Gas_Year__m3",
    "heating.gas.consumption.summary.heating.lastYear"          => "Gas_YearLast__m3",

    "heating.gas.consumption.dhw.day"                           => "Gas_WW_Tage__m3",
    "heating.gas.consumption.dhw.dayValueReadAt"                => "Gas_WW_Tage_Zeit",
    "heating.gas.consumption.dhw.week"                          => "Gas_WW_Wochen__m3",
    "heating.gas.consumption.dhw.weekValueReadAt"               => "Gas_WW_Wochen_Zeit",
    "heating.gas.consumption.dhw.month"                         => "Gas_WW_Monate__m3",
    "heating.gas.consumption.dhw.monthValueReadAt"              => "Gas_WW_Monate_Zeit",
    "heating.gas.consumption.dhw.year"                          => "Gas_WW_Jahre__m3",
    "heating.gas.consumption.dhw.yearValueReadAt"               => "Gas_WW_Jahre_Zeit",
    "heating.gas.consumption.dhw.unit"                          => "Gas_WW_Einheit",

    "heating.gas.consumption.heating.day"                       => "Gas_Heiz_Tage__m3",
    "heating.gas.consumption.heating.dayValueReadAt"            => "Gas_Heiz_Tage_Zeit",
    "heating.gas.consumption.heating.week"                      => "Gas_Heiz_Wochen__m3",
    "heating.gas.consumption.heating.weekValueReadAt"           => "Gas_Heiz_Wochen_Zeit",
    "heating.gas.consumption.heating.month"                     => "Gas_Heiz_Monate__m3",
    "heating.gas.consumption.heating.monthValueReadAt"          => "Gas_Heiz_Monate_Zeit",
    "heating.gas.consumption.heating.year"                      => "Gas_Heiz_Jahre__m3",
    "heating.gas.consumption.heating.yearValueReadAt"           => "Gas_Heiz_Jahre_Zeit",
    "heating.gas.consumption.heating.unit"                      => "Gas_Heiz_Einheit",

    "heating.gas.consumption.total.day"                         => "Gas_Total_Tage__m3",
    "heating.gas.consumption.total.dayValueReadAt"              => "Gas_Total_Tage_Zeit",
    "heating.gas.consumption.total.week"                        => "Gas_Total_Wochen__m3",
    "heating.gas.consumption.total.weekValueReadAt"             => "Gas_Total_Wochen_Zeit",
    "heating.gas.consumption.total.month"                       => "Gas_Total_Monate__m3",
    "heating.gas.consumption.total.monthValueReadAt"            => "Gas_Total_Monate_Zeit",
    "heating.gas.consumption.total.year"                        => "Gas_Total_Jahre__m3",
    "heating.gas.consumption.total.yearValueReadAt"             => "Gas_Total_Jahre_Zeit",
    "heating.gas.consumption.total.unit"                        => "Gas_Total_Einheit",

    "heating.power.consumption.summary.dhw.currentDay"          => "Strom_WW_Day__kWh",
    "heating.power.consumption.summary.dhw.lastSevenDays"       => "Strom_WW_7dLast__kWh",
    "heating.power.consumption.summary.dhw.currentMonth"        => "Strom_WW_Month__kWh",
    "heating.power.consumption.summary.dhw.lastMonth"           => "Strom_WW_MonthLast__kWh",
    "heating.power.consumption.summary.dhw.currentYear"         => "Strom_WW_Year__kWh",
    "heating.power.consumption.summary.dhw.lastYear"            => "Strom_WW_YearLast__kWh",

    "heating.power.consumption.summary.heating.currentDay"      => "Strom_Heiz_Day__kWh",
    "heating.power.consumption.summary.heating.lastSevenDays"   => "Strom_Heiz_7dLast__kWh",
    "heating.power.consumption.summary.heating.currentMonth"    => "Strom_Heiz_Month__kWh",
    "heating.power.consumption.summary.heating.lastMonth"       => "Strom_Heiz_MonthLast__kWh",
    "heating.power.consumption.summary.heating.currentYear"     => "Strom_Heiz_Year__kWh",
    "heating.power.consumption.summary.heating.lastYear"        => "Strom_Heiz_YearLast__kWh",

    "heating.circuits.3.heating.curve.shift"                    => "HK4_Heizkurve_Niveau",
    "heating.circuits.3.heating.curve.slope"                    => "HK4_Heizkurve_Steigung",
    "heating.circuits.3.geofencing.active"                      => "HK4_Geofencing",
    "heating.circuits.3.geofencing.status"                      => "HK4_Geofencing_Status",
    "heating.circuits.3.operating.programs.summerEco.active"    => "HK4_Solltemperatur_SummerEco_aktiv",
    "heating.circuits.3.zone.mode.active"                       => "HK4_ZoneMode_aktive",


    "heating.circuits.1.active"                                 => "HK2_aktiv",
    "heating.circuits.1.type"                                   => "HK2_Typ",
    "heating.circuits.1.circulation.pump.status"                => "HK2_Zirkulationspumpe",
    "heating.circuits.1.circulation.schedule.active"            => "HK2_Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.1.circulation.schedule.entries"           => "HK2_Zeitsteuerung_Zirkulation",
    "heating.circuits.1.frostprotection.status"                 => "HK2_Frostschutz_Status",
    "heating.circuits.1.geofencing.active"                      => "HK2_Geofencing",
    "heating.circuits.1.geofencing.status"                      => "HK2_Geofencing_Status",
    "heating.circuits.1.heating.curve.shift"                    => "HK2_Heizkurve_Niveau",
    "heating.circuits.1.heating.curve.slope"                    => "HK2_Heizkurve_Steigung",
    "heating.circuits.1.heating.schedule.active"                => "HK2_Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.1.heating.schedule.entries"               => "HK2_Zeitsteuerung_Heizung",
    "heating.circuits.1.name"                                   => "HK2_Name",
    "heating.circuits.1.operating.modes.active.value"           => "HK2_Betriebsart",
    "heating.circuits.1.operating.modes.dhw.active"             => "HK2_WW_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeating.active"   => "HK2_WW_und_Heizen_aktiv",
    "heating.circuits.1.operating.modes.dhwAndHeatingCooling.active"    => "HK2_WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.1.operating.modes.forcedNormal.active" => "HK2_Solltemperatur_erzwungen",
    "heating.circuits.1.operating.modes.forcedReduced.active" => "HK2_Reduzierte_Temperatur_erzwungen",
    "heating.circuits.1.operating.modes.heating.active" => "HK2_heizen_aktiv",
    "heating.circuits.1.operating.modes.normalStandby.active" => "HK2_Normal_Standby_aktiv",
    "heating.circuits.1.operating.modes.standby.active" => "HK2_Standby_aktiv",
    "heating.circuits.1.operating.programs.active.value" => "HK2_Programmstatus",
    "heating.circuits.1.operating.programs.comfort.active" => "HK2_Solltemperatur_comfort_aktiv",
    "heating.circuits.1.operating.programs.comfort.demand" =>
      "HK2-Solltemperatur_comfort_Anforderung",
    "heating.circuits.1.operating.programs.comfort.temperature" =>
      "HK2-Solltemperatur_comfort",
    "heating.circuits.1.operating.programs.eco.active" =>
      "HK2-Solltemperatur_eco_aktiv",
    "heating.circuits.1.operating.programs.eco.temperature" =>
      "HK2-Solltemperatur_eco",
    "heating.circuits.1.operating.programs.external.active" =>
      "HK2-External_aktiv",
    "heating.circuits.1.operating.programs.external.temperature" =>
      "HK2-External_Temperatur",
    "heating.circuits.1.operating.programs.fixed.active" => "HK2-Fixed_aktiv",
    "heating.circuits.1.operating.programs.forcedLastFromSchedule.active" =>
      "HK2-forcedLastFromSchedule_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.active" =>
      "HK2-HolidayAtHome_aktiv",
    "heating.circuits.1.operating.programs.holidayAtHome.end" => "HK2-HolidayAtHome_Ende",
    "heating.circuits.1.operating.programs.holidayAtHome.start" => "HK2-HolidayAtHome_Start",
    "heating.circuits.1.operating.programs.holiday.active" => "HK2_Urlaub_aktiv",
    "heating.circuits.1.operating.programs.holiday.start" => "HK2_Urlaub_Start_Zeit",
    "heating.circuits.1.operating.programs.holiday.end"   => "HK2_Urlaub_Ende_Zeit",
    "heating.circuits.1.operating.programs.normal.active" =>
      "HK2-Solltemperatur_aktiv",
    "heating.circuits.1.operating.programs.normal.demand" =>
      "HK2-Solltemperatur_Anforderung",
    "heating.circuits.1.operating.programs.normal.temperature" =>
      "HK2-Solltemperatur_normal",
    "heating.circuits.1.operating.programs.reduced.active" =>
      "HK2-Solltemperatur_reduziert_aktiv",
    "heating.circuits.1.operating.programs.reduced.demand" =>
      "HK2-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.1.operating.programs.reduced.temperature" =>
      "HK2-Solltemperatur_reduziert",
    "heating.circuits.1.operating.programs.summerEco.active" =>
      "HK2-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.1.operating.programs.standby.active" =>
      "HK2-Standby_aktiv",
    "heating.circuits.1.sensors.temperature.room.status" => "HK2-Raum_Status",
    "heating.circuits.1.sensors.temperature.room.value" =>
      "HK2-Raum_Temperatur",
    "heating.circuits.1.sensors.temperature.supply.status" =>
      "HK2-Vorlauftemperatur_aktiv",
    "heating.circuits.1.sensors.temperature.supply.unit" =>
      "HK2-Vorlauftemperatur_Einheit",
    "heating.circuits.1.sensors.temperature.supply.value" =>
      "HK2-Vorlauftemperatur",
    "heating.circuits.1.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.circuits.2.active"                  => "HK3_aktiv",
    "heating.circuits.2.type"                    => "HK3_Typ",
    "heating.circuits.2.circulation.pump.status" => "HK3_Zirkulationspumpe",
    "heating.circuits.2.circulation.schedule.active" =>"HK3_Zeitsteuerung_Zirkulation_aktiv",
    "heating.circuits.2.circulation.schedule.entries" =>"HK3_Zeitsteuerung_Zirkulation",
    "heating.circuits.2.frostprotection.status" => "HK3_Frostschutz_Status",
    "heating.circuits.2.geofencing.active"      => "HK3_Geofencing",
    "heating.circuits.2.geofencing.status"      => "HK3_Geofencing_Status",
    "heating.circuits.2.heating.curve.shift"    => "HK3_Heizkurve_Niveau",
    "heating.circuits.2.heating.curve.slope"    => "HK3_Heizkurve_Steigung",
    "heating.circuits.2.heating.schedule.active" => "HK3-Zeitsteuerung_Heizung_aktiv",
    "heating.circuits.2.heating.schedule.entries" => "HK3_Zeitsteuerung_Heizung",
    "heating.circuits.2.name"                         => "HK3_Name",
    "heating.circuits.2.operating.modes.active.value" => "HK3_Betriebsart",
    "heating.circuits.2.operating.modes.dhw.active"   => "HK3_WW_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeating.active" => "HK3_WW_und_Heizen_aktiv",
    "heating.circuits.2.operating.modes.dhwAndHeatingCooling.active" => "HK3-WW_und_Heizen_Kuehlen_aktiv",
    "heating.circuits.2.operating.modes.forcedNormal.active" => "HK3-Solltemperatur_erzwungen",
    "heating.circuits.2.operating.modes.forcedReduced.active" => "HK3-Reduzierte_Temperatur_erzwungen",
    "heating.circuits.2.operating.modes.heating.active" => "HK3-heizen_aktiv",
    "heating.circuits.2.operating.modes.normalStandby.active" => "HK3-Normal_Standby_aktiv",
    "heating.circuits.2.operating.modes.standby.active" => "HK3-Standby_aktiv",
    "heating.circuits.2.operating.programs.active.value" => "HK3-Programmstatus",
    "heating.circuits.2.operating.programs.comfort.active" => "HK3-Solltemperatur_comfort_aktiv",
    "heating.circuits.2.operating.programs.comfort.demand" => "HK3-Solltemperatur_comfort_Anforderung",
    "heating.circuits.2.operating.programs.comfort.temperature" => "HK3-Solltemperatur_comfort",
    "heating.circuits.2.operating.programs.eco.active" => "HK3-Solltemperatur_eco_aktiv",
    "heating.circuits.2.operating.programs.eco.temperature" => "HK3-Solltemperatur_eco",
    "heating.circuits.2.operating.programs.external.active" => "HK3-External_aktiv",
    "heating.circuits.2.operating.programs.external.temperature" => "HK3-External_Temperatur",
    "heating.circuits.2.operating.programs.fixed.active" => "HK3-Fixed_aktiv",
    "heating.circuits.2.operating.programs.forcedLastFromSchedule.active" => "HK3-forcedLastFromSchedule_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.active" => "HK3-HolidayAtHome_aktiv",
    "heating.circuits.2.operating.programs.holidayAtHome.end" => "HK3-HolidayAtHome_Ende",
    "heating.circuits.2.operating.programs.holidayAtHome.start" => "HK3-HolidayAtHome_Start",
    "heating.circuits.2.operating.programs.holiday.active" => "HK3_Urlaub_aktiv",
    "heating.circuits.2.operating.programs.holiday.start" => "HK3_Urlaub_Start_Zeit",
    "heating.circuits.2.operating.programs.holiday.end"   => "HK3_Urlaub_Ende_Zeit",
    "heating.circuits.2.operating.programs.normal.active" =>
      "HK3-Solltemperatur_aktiv",
    "heating.circuits.2.operating.programs.normal.demand" =>
      "HK3-Solltemperatur_Anforderung",
    "heating.circuits.2.operating.programs.normal.temperature" =>
      "HK3-Solltemperatur_normal",
    "heating.circuits.2.operating.programs.reduced.active" =>
      "HK3-Solltemperatur_reduziert_aktiv",
    "heating.circuits.2.operating.programs.reduced.demand" =>
      "HK3-Solltemperatur_reduziert_Anforderung",
    "heating.circuits.2.operating.programs.reduced.temperature" =>
      "HK3-Solltemperatur_reduziert",
    "heating.circuits.2.operating.programs.summerEco.active" =>
      "HK3-Solltemperatur_SummerEco_aktiv",
    "heating.circuits.2.operating.programs.standby.active" =>
      "HK3-Standby_aktiv",
    "heating.circuits.2.sensors.temperature.room.status" => "HK3-Raum_Status",
    "heating.circuits.2.sensors.temperature.room.value" =>
      "HK3-Raum_Temperatur",
    "heating.circuits.2.sensors.temperature.supply.status" =>
      "HK3-Vorlauftemperatur_aktiv",
    "heating.circuits.2.sensors.temperature.supply.unit" =>
      "HK3-Vorlauftemperatur_Einheit",
    "heating.circuits.2.sensors.temperature.supply.value" => "HK3-Vorlauftemperatur",
    "heating.circuits.2.zone.mode.active" => "HK2-ZoneMode_aktive",

    "heating.compressor.active"                     => "Kompressor_aktiv",
    "heating.configuration.multiFamilyHouse.active" => "Mehrfamilenhaus_aktiv",
    "heating.configuration.regulation.mode"         => "Regulationmode",
    "heating.controller.serial.value"  => "Controller_Seriennummer",
    "heating.dhw.active"               => "WW_aktiv",
    "heating.dhw.status"               => "WW_Status",
    "heating.dhw.charging.active"      => "WW_Aufladung",

    "heating.dhw.charging.level.bottom" => "WW_Speichertemperatur_unten",
    "heating.dhw.charging.level.middle" => "WW_Speichertemperatur_mitte",
    "heating.dhw.charging.level.top"    => "WW_Speichertemperatur_oben",
    "heating.dhw.charging.level.value"  => "WW_Speicherladung",

    "heating.errors.active.entries"  => "Fehlereintraege_aktive",
    "heating.errors.history.entries" => "Fehlereintraege_Historie",

    "heating.flue.sensors.temperature.main.status" => "Abgassensor_Status",
    "heating.flue.sensors.temperature.main.unit" => "Abgassensor_Temperatur_Einheit",
    "heating.flue.sensors.temperature.main.value" => "Abgassensor_Temperatur",

    "heating.fuelCell.operating.modes.active.value" => "Brennstoffzelle_Mode",
    "heating.fuelCell.operating.modes.ecological.active" => "Brennstoffzelle_Mode_Ecological",
    "heating.fuelCell.operating.modes.economical.active" => "Brennstoffzelle_Mode_Economical",
    "heating.fuelCell.operating.modes.heatControlled.active" => "Brennstoffzelle_wärmegesteuert",
    "heating.fuelCell.operating.modes.maintenance.active" => "Brennstoffzelle_Wartung",
    "heating.fuelCell.operating.modes.standby.active" => "Brennstoffzelle_Standby",
    "heating.fuelCell.operating.phase.value" => "Brennstoffzelle_Phase",
    "heating.fuelCell.power.production.day" => "Brennstoffzelle_Stromproduktion/Tag",
    "heating.fuelCell.power.production.month" => "Brennstoffzelle_Stromproduktion/Monat",
    "heating.fuelCell.power.production.unit" => "Brennstoffzelle_Stromproduktion_Einheit",
    "heating.fuelCell.power.production.week" => "Brennstoffzelle_Stromproduktion/Woche",
    "heating.fuelCell.power.production.year" => "Brennstoffzelle_Stromproduktion/Jahr",
    "heating.fuelCell.sensors.temperature.return.status" => "Brennstoffzelle_Temperatur_Ruecklauf_Status",
    "heating.fuelCell.sensors.temperature.return.unit" => "Brennstoffzelle_Temperatur_Ruecklauf_Einheit",
    "heating.fuelCell.sensors.temperature.return.value" => "Brennstoffzelle_Temperatur_Ruecklauf",
    "heating.fuelCell.sensors.temperature.supply.status" => "Brennstoffzelle_Temperatur_Vorlauf_Status",
    "heating.fuelCell.sensors.temperature.supply.unit" => "Brennstoffzelle_Temperatur_Vorlauf_Einheit",
    "heating.fuelCell.sensors.temperature.supply.value" => "Brennstoffzelle_Temperatur_Vorlauf",
    "heating.fuelCell.statistics.availabilityRate" => "Brennstoffzelle_Statistic_Verfügbarkeit",
    "heating.fuelCell.statistics.insertions" => "Brennstoffzelle_Statistic_Einschub",
    "heating.fuelCell.statistics.operationHours" => "Brennstoffzelle_Statistic_Bestriebsstunden",
    "heating.fuelCell.statistics.productionHours" => "Brennstoffzelle_Statistic_Produktionsstunden",
    "heating.fuelCell.statistics.productionStarts" => "Brennstoffzelle_Statistic_Produktionsstarts",

    "heating.gas.consumption.fuelCell.day" => "Gas_Brennstoffzelle/Tag",
    "heating.gas.consumption.fuelCell.week" => "Gas_Brennstoffzelle/Woche",
    "heating.gas.consumption.fuelCell.month" => "Gas_Brennstoffzelle/Monat",
    "heating.gas.consumption.fuelCell.year" => "Gas_Brennstoffzelle/Jahr",
    "heating.gas.consumption.fuelCell.unit" => "Gas_Brennstoffzelle/Einheit",

    "heating.heat.production.day"   => "Wärmeproduktion/Tag",
    "heating.heat.production.month" => "Wärmeproduktion/Woche",
    "heating.heat.production.unit"  => "Wärmeproduktion/Einheit",
    "heating.heat.production.week"  => "Wärmeproduktion/Woche",
    "heating.heat.production.year"  => "Wärmeproduktion/Jahr",

    "heating.operating.programs.holiday.active"         => "Urlaub_aktiv",
    "heating.operating.programs.holiday.end"            => "Urlaub_Ende_Zeit",
    "heating.operating.programs.holiday.start"          => "Urlaub_Start_Zeit",

    "heating.operating.programs.holidayAtHome.active"   => "HolidayAtHome_aktiv",
    "heating.operating.programs.holidayAtHome.end"      => "HolidayAtHome_Ende",
    "heating.operating.programs.holidayAtHome.start"    => "HolidayAtHome_Start",

    "heating.power.consumption.day"                     => "Stromverbrauch_Tag",
    "heating.power.consumption.month"                   => "Stromverbrauch_Monat",
    "heating.power.consumption.week"                    => "Stromverbrauch_Woche",
    "heating.power.consumption.year"                    => "Stromverbrauch_Jahr",
    "heating.power.consumption.unit"                    => "Stromverbrauch_Einheit",

    "heating.power.consumption.dhw.day"                 => "Strom_WW_Tage",
    "heating.power.consumption.dhw.dayValueReadAt"      => "Strom_WW_Tage_Zeit",
    "heating.power.consumption.dhw.week"                => "Strom_WW_Wochen",
    "heating.power.consumption.dhw.weekValueReadAt"     => "Strom_WW_Wochen_Zeit",
    "heating.power.consumption.dhw.month"               => "Strom_WW_Monate",
    "heating.power.consumption.dhw.monthValueReadAt"    => "Strom_WW_Monate_Zeit",
    "heating.power.consumption.dhw.year"                => "Strom_WW_Jahre",
    "heating.power.consumption.dhw.yearValueReadAt"     => "Strom_WW_Jahre_Zeit",
    "heating.power.consumption.dhw.unit"                => "Strom_WW_Einheit",

    "heating.power.consumption.heating.day"             => "Strom_Heizung_Tage__kWh",
    "heating.power.consumption.heating.dayValueReadAt"  => "Strom_Heizung_Tage_Zeit",
    "heating.power.consumption.heating.week"            => "Strom_Heizung_Wochen__kWh",
    "heating.power.consumption.heating.weekValueReadAt" => "Strom_Heizung_Wochen_Zeit",
    "heating.power.consumption.heating.month"           => "Strom_Heizung_Monate__kWh",
    "heating.power.consumption.heating.monthValueReadAt"=> "Strom_Heizung_Monate_Zeit",
    "heating.power.consumption.heating.year"            => "Strom_Heizung_Jahre__kWh",
    "heating.power.consumption.heating.yearValueReadAt" => "Strom_Heizung_Jahre_Zeit",
    "heating.power.consumption.heating.unit"            => "Strom_Heizung_Einheit",

    "heating.power.consumption.total.day"               => "Strom_Total_Tage__kWh",
    "heating.power.consumption.total.dayValueReadAt"    => "Strom_Total_Tage_Zeit",
    "heating.power.consumption.total.week"              => "Strom_Total_Wochen__kWh",
    "heating.power.consumption.total.weekValueReadAt"   => "Strom_Total_Wochen_Zeit",
    "heating.power.consumption.total.month"             => "Strom_Total_Monate__kWh",
    "heating.power.consumption.total.monthValueReadAt"  => "Strom_Total_Monate_Zeit",
    "heating.power.consumption.total.year"              => "Strom_Total_Jahre__kWh",
    "heating.power.consumption.total.yearValueReadAt"   => "Strom_Total_Jahre_Zeit",
    "heating.power.consumption.total.unit"              => "Strom_Total_Einheit",

    "heating.power.production.current.status"           => "Stromproduktion_aktueller_Status",
    "heating.power.production.current.value"            => "Stromproduktion",

    "heating.power.production.demandCoverage.current.unit" => "Stromproduktion_Bedarfsabdeckung/Einheit",
    "heating.power.production.demandCoverage.current.value" => "Stromproduktion_Bedarfsabdeckung",
    "heating.power.production.demandCoverage.total.day" => "Stromproduktion_Bedarfsabdeckung_total/Tag",
    "heating.power.production.demandCoverage.total.month" => "Stromproduktion_Bedarfsabdeckung_total/Monat",
    "heating.power.production.demandCoverage.total.unit" => "Stromproduktion_Bedarfsabdeckung_total/Einheit",
    "heating.power.production.demandCoverage.total.week" => "Stromproduktion_Bedarfsabdeckung_total/Woche",
    "heating.power.production.demandCoverage.total.year" => "Stromproduktion_Bedarfsabdeckung_total/Jahr",

    "heating.power.production.day"   => "Stromproduktion_Total/Tag",
    "heating.power.production.month" => "Stromproduktion_Total/Monat",
    "heating.power.production.productionCoverage.current.unit" =>
      "Stromproduktion_Produktionsabdeckung/Einheit",
    "heating.power.production.productionCoverage.current.value" =>
      "Stromproduktion_Produktionsabdeckung",
    "heating.power.production.productionCoverage.total.day" =>
      "Stromproduktion_Produktionsabdeckung_Total/Tag",
    "heating.power.production.productionCoverage.total.month" =>
      "Stromproduktion_Produktionsabdeckung_Total/Monat",
    "heating.power.production.productionCoverage.total.unit" =>
      "Stromproduktion_Produktionsabdeckung_Total/Einheit",
    "heating.power.production.productionCoverage.total.week" =>
      "Stromproduktion_Produktionsabdeckung_Total/Woche",
    "heating.power.production.productionCoverage.total.year" =>
      "Stromproduktion_Produktionsabdeckung_Total/Jahr",
    "heating.power.production.unit" => "Stromproduktion_Total/Einheit",
    "heating.power.production.week" => "Stromproduktion_Total/Woche",
    "heating.power.production.year" => "Stromproduktion_Total/Jahr",

    "heating.power.purchase.current.unit"  => "Stromkauf/Einheit",
    "heating.power.purchase.current.value" => "Stromkauf",
    "heating.power.sold.current.unit"      => "Stromverkauf/Einheit",
    "heating.power.sold.current.value"     => "Stromverkauf",
    "heating.power.sold.day"               => "Stromverkauf/Tag",
    "heating.power.sold.month"             => "Stromverkauf/Monat",
    "heating.power.sold.unit"              => "Stromverkauf/Einheit",
    "heating.power.sold.week"              => "Stromverkauf/Woche",
    "heating.power.sold.year"              => "Stromverkauf/Jahr",

    "heating.sensors.pressure.supply.status" => "Drucksensor_Vorlauf_Status",
    "heating.sensors.pressure.supply.unit"   => "Drucksensor_Vorlauf/Einheit",
    "heating.sensors.pressure.supply.value"  => "Drucksensor_Vorlauf",

    "heating.sensors.power.output.status" => "Sensor_Stromproduktion_Status",
    "heating.sensors.power.output.value"  => "Sensor_Stromproduktion",

    "heating.sensors.temperature.outside.statusWired" => "Aussen_StatusWired",
    "heating.sensors.temperature.outside.statusWireless" =>
      "Aussen_StatusWireless",

    "heating.service.timeBased.serviceDue" => "Service_faellig",
    "heating.service.timeBased.serviceIntervalMonths" =>
      "Service_Intervall_Monate",
    "heating.service.timeBased.activeMonthSinceLastService" =>
      "Service_Monate_aktiv_seit_letzten_Service",
    "heating.service.timeBased.lastService" => "Service_Letzter",
    "heating.service.burnerBased.serviceDue" =>
      "Service_fällig_brennerbasiert",
    "heating.service.burnerBased.serviceIntervalBurnerHours" =>
      "Service_Intervall_Betriebsstunden",
    "heating.service.burnerBased.activeBurnerHoursSinceLastService" =>
      "Service_Betriebsstunden_seit_letzten",
    "heating.service.burnerBased.lastService" =>
      "Service_Letzter_brennerbasiert",

    "heating.solar.active"               => "Solar_aktiv",
    "heating.solar.pumps.circuit.status" => "Solar_Pumpe_Status",
    "heating.solar.rechargeSuppression.status" =>
      "Solar_Aufladeunterdrueckung_Status",
    "heating.solar.sensors.power.status" => "Solar_Sensor_Power_Status",
    "heating.solar.sensors.power.value"  => "Solar_Sensor_Power",
    "heating.solar.sensors.temperature.collector.status" =>
      "Solar_Sensor_Temperatur_Kollektor_Status",
    "heating.solar.sensors.temperature.collector.value" =>
      "Solar_Sensor_Temperatur_Kollektor",
    "heating.solar.sensors.temperature.dhw.status" =>
      "Solar_Sensor_Temperatur_WW_Status",
    "heating.solar.sensors.temperature.dhw.value" =>
      "Solar_Sensor_Temperatur_WW",
    "heating.solar.statistics.hours" => "Solar_Sensor_Statistik_Stunden",

    "heating.solar.power.cumulativeProduced.value" =>
      "Solarproduktion_Gesamtertrag",
    "heating.solar.power.production.month" => "Solarproduktion/Monat",
    "heating.solar.power.production.day"   => "Solarproduktion/Tag",
    "heating.solar.power.production.unit"  => "Solarproduktion/Einheit",
    "heating.solar.power.production.week"  => "Solarproduktion/Woche",
    "heating.solar.power.production.year"  => "Solarproduktion/Jahr"
};

#####################################################################################################################
# Modul initialisieren und Namen zusätzlicher Funktionen bekannt geben
#####################################################################################################################
sub vitoconnect_Initialize {
    my ($hash) = @_;
    $hash->{DefFn}   = \&vitoconnect_Define;    # wird beim 'define' eines Gerätes aufgerufen
    $hash->{UndefFn} = \&vitoconnect_Undef;     # # wird beim Löschen einer Geräteinstanz aufgerufen
    $hash->{SetFn}   = \&vitoconnect_Set;       # set-Befehle
    $hash->{GetFn}   = \&vitoconnect_Get;       # get-Befehle
    $hash->{AttrFn}  = \&vitoconnect_Attr;      # Attribute setzen/ändern/löschen
    $hash->{ReadFn}  = \&vitoconnect_Read;
    $hash->{AttrList} =
        "disable:0,1 "
      . "vitoconnect_mappings:textField-long "
      . "vitoconnect_translations:textField-long "
      . "vitoconnect_mapping_roger:0,1 "
# Wird nicht verwendet
#      . "model:Vitodens_200-W_(B2HB),Vitodens_200-W_(B2KB),"
#      . "Vitotronic_200_(HO1),Vitotronic_200_(HO1A),Vitotronic_200_(HO1B),Vitotronic_200_(HO1D),"
#      . "Vitotronic_200_(HO2B),"
#      . "Vitotronic_200_RF_(HO1C),Vitotronic_200_RF_(HO1E),"
#      . "Vitotronic_200_(KO1B),Vitotronic_200_(KO2B),Vitotronic_200_(KW6),Vitotronic_200_(KW6A),"
#      . "Vitotronic_200_(KW6B),Vitotronic_200_(KW1),Vitotronic_200_(KW2),Vitotronic_200_(KW4),"
#      . "Vitotronic_200_(KW5),"
#      . "Vitotronic_300_(KW3),Vitotronic_200_(WO1A),Vitotronic_200_(WO1B),Vitotronic_200_(WO1C),"
#      . "Vitoligno_300-C,Vitoligno_200-S,Vitoligno_300-P_mit_Vitotronic_200_(FO1),Vitoligno_250-S,"
#      . "Vitoligno_300-S "
      . "vitoconnect_raw_readings:0,1 "         # Liefert nur die raw readings und verhindert das mappen wenn gesetzt
      . "vitoconnect_gw_readings:0,1 "          # Schreibt die GW readings als Reading ins Device
      . "vitoconnect_actions_active:0,1 "
      . "vitoconnect_device:0,1 "               # Hier kann Device 0 oder 1 angesprochen worden, default ist 0 und ich habe keinen GW mit Device 1
      . "vitoconnect_serial:textField-long "    # Legt fest welcher Gateway abgefragt werden soll, wenn nicht gesetzt werden alle abgefragt
      . "vitoconnect_timeout:selectnumbers,10,1.0,30,0,lin "
      . $readingFnAttributes;

      eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'
    return;
}

#####################################################################################################################
# wird beim 'define' eines Gerätes aufgerufen
#####################################################################################################################
sub vitoconnect_Define {
    my ( $hash, $def ) = @_;
    my $name  = $hash->{NAME};
    my $type  = $hash->{TYPE};
    
      my $params = {
      hash        => $hash,
      name        => $name,
      type        => $type,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 0,
  };

  use version 0.77; our $VERSION = moduleVersion ($params);                                              # Versionsinformationen setzen
  delete $params->{hash};
    
    
    my @param = split( '[ \t]+', $def );

    if ( int(@param) < 5 ) {
        return "too few parameters: "
          . "define <name> vitoconnect <user> <passwd> <intervall>";
    }

    $hash->{user}            = $param[2];
    $hash->{intervall}       = $param[4];
    $hash->{counter}         = 0;
    $hash->{timeout}         = 15;
    $hash->{".access_token"} = "";
    $hash->{".installation"} = "";
    $hash->{".gw"}           = "";
    $hash->{".gwa"}           = ();
    $hash->{"Redirect_URI"}  = $callback_uri;

    my $isiwebpasswd = vitoconnect_ReadKeyValue($hash,"passwd");    # verschlüsseltes Kennwort auslesen
    if ($isiwebpasswd eq "")        {   # Kennwort (noch) nicht gespeichert
        my $err = vitoconnect_StoreKeyValue($hash,"passwd",$param[3]);  # Kennwort verschlüsselt speichern
        return $err if ($err);
    }
    else                            {   # Kennwort schon gespeichert
        Log3($name,3,$name." - Passwort war bereits gespeichert");
    }
    $hash->{apiKey} = vitoconnect_ReadKeyValue($hash,"apiKey");         # verschlüsselten apiKey auslesen
    RemoveInternalTimer($hash); # Timer löschen, z.b. bei intervall change
    InternalTimer(gettimeofday() + 10,"vitoconnect_GetUpdate",$hash);   # nach 10s
    return;
}

#####################################################################################################################
# wird beim Löschen einer Geräteinstanz aufgerufen
#####################################################################################################################
sub vitoconnect_Undef {
    my ($hash,$arg ) = @_;      # Übergabe-Parameter
    RemoveInternalTimer($hash); # Timer löschen
    return;
}

#####################################################################################################################
# bisher kein 'get' implementiert
#####################################################################################################################
sub vitoconnect_Get {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    return "get ".$name." needs at least one argument" unless (defined($opt) );
    return;
}

#####################################################################################################################
# Implementierung set-Befehle
#####################################################################################################################
sub vitoconnect_Set_New {
    my ($hash, $name, $opt, @args) = @_;
    my $gwatemp      = $hash->{".gwa"};
    my $gw           = $hash->{".gw"};
    
    my $val = "unknown value $opt, choose one of update:noArg clearReadings:noArg password apiKey logResponseOnce:noArg ";
    Log(5,$name.", -set started: ". $opt);
    
    my @gwa = ();
    if (defined($gwatemp) && $gwatemp ne "") {
      @gwa = @{$gwatemp};
    }
    if (defined($gw) && $gw ne "") {
        Log(5,$name.", - vitoconnect_Set_New Resource gw found reduce gwa: ".$gw);
        @gwa = $gw;
    }
    
    my $gwaCount = scalar @gwa;
    if ($gwaCount == 0) {
        readingsSingleUpdate($hash,"Aktion_Status","Warnung: Gateway noch nicht eingelesen. Entweder bis zum ersten Update warten oder mit logResponseOnce einlesen",1);    # Reading 'Aktion_Status' setzen
    } elsif ($gwaCount > 1) {
        readingsSingleUpdate($hash,"Aktion_Status","Fehler: Mehr als ein Gateway. Für Setter bitte eine Serial in vitoconnect_serial vorgeben.",1); # Reading 'Aktion_Status' setzen
    } else {
        readingsSingleUpdate($hash,"Aktion_Status","ready",1);  # Reading 'Aktion_Status' setzen
    }
    

    if ($gwaCount == 1 && $Response) {  # Überprüfen, ob $Response Daten enthält
        my $data;
        eval { $data = decode_json($Response); };
        if ($@) {
            # JSON-Dekodierung fehlgeschlagen, nur Standardoptionen zurückgeben
            return $val;
        }
        
        foreach my $item (@{$data->{'data'}}) {

            if (exists $item->{commands}) {
                my $feature = $item->{feature};
                Log(5,$name.", -set feature: ". $feature);

                foreach my $commandName (keys %{$item->{commands}}) {           #<====== Loop Commands
                    my $commandNr = keys %{$item->{commands}};
                    my @propertyKeys = keys %{$item->{properties}};
                    my $propertyKeysNr = keys %{$item->{properties}};
                    my $paramNr = keys %{$item->{commands}{$commandName}{params}};
                    
                    Log(5,$name.", -set isExecutable: ". $item->{commands}{$commandName}{isExecutable}); 
                    if ($item->{commands}{$commandName}{isExecutable} == 0) {
                    Log(5,$name.", -set $commandName nicht ausführbar"); 
                     next; #diser Befehl ist nicht ausführbar, nächster 
                    }

                    Log(5,$name.", -set commandNr: ". $commandNr); 
                    Log(5,$name.", -set commandname: ". $commandName); 
                    my $readingNamePrep;
                    if ($commandNr == 1 and $propertyKeysNr == 1) {               # Ein command value = property z.B. heating.circuits.0.operating.modes.active
                     $readingNamePrep .= $feature.".". $propertyKeys[0];
                    } elsif ( $commandName eq "setTemperature" ) {
                        $readingNamePrep .= $feature.".temperature";              #<------- setTemperature only 1 param, so it can be defined here
                    } elsif ( $commandName eq "setHysteresis" ) {                 #<------- setHysteresis very special mapping, must be predefined
                        $readingNamePrep .= $feature.".value";
                    } elsif ( $commandName eq "setHysteresisSwitchOnValue" ) {    #<------- setHysteresis very special mapping, must be predefined
                        $readingNamePrep .= $feature.".switchOnValue";
                    } elsif ( $commandName eq "setHysteresisSwitchOffValue" ) {   #<------- setHysteresis very special mapping, must be predefined
                        $readingNamePrep .= $feature.".switchOffValue";
                    } elsif ( $commandName eq "setMin" ) {
                        $readingNamePrep .= $feature.".min";                      #<------- setMin/setMax very special mapping, must be predefined
                    } elsif ( $commandName eq "setMax" ) {
                        $readingNamePrep .= $feature.".max";
                    } elsif ( $commandName eq "setSchedule" ) {                   #<------- setSchedule very special mapping, must be predefined
                        $readingNamePrep .= $feature.".entries";
                    } elsif ( $commandName eq "setLevels" ) {
                        # duplicate, setMin, setMax can do this https://api.viessmann.com/iot/v2/features/installations/2772216/gateways/7736172146035226/devices/0/features/heating.circuits.0.temperature.levels/commands/setLevels
                        next;
                    }
                    else {
                    # all other cases, will be defined in param loop
                    }
                    if(defined($readingNamePrep))
                    {
                    Log(5,$name.", -set readingNamePrep: ". $readingNamePrep); 
                    }

                    if ($paramNr > 2) {                                          #<------- more then 2 parameters, with unsorted JSON can not be handled, but also do not exist at the moment
                        Log(5,$name.", -set mehr als 2 Parameter in Command $commandName, kann nicht berechnet werden"); 
                        next;
                    } elsif ($paramNr == 0){                                     #<------- mo parameters, create here, param loop will not be executed
                        $readingNamePrep .= $feature.".".$commandName;
                        $val .= "$readingNamePrep:noArg ";
                        
                        # Set execution
                        if ($opt eq $readingNamePrep) {
                            my $uri = $item->{commands}->{$commandName}->{'uri'};
                            my ($shortUri) = $uri =~ m|.*features/(.*)|; #<=== URI ohne gateway zeug
                           Log(5,$name.", -set short uri: ".$shortUri);
                            vitoconnect_action($hash,
                                $shortUri,
                                "{}",
                                $name, $opt, @args
                            );
                            return;
                        }
                    }
                
                # 1 oder 2 Params, all other cases see above
                my @params = keys %{$item->{commands}{$commandName}{params}};
                    foreach my $paramName (@params) {   #<==== Loop params
                       
                       my $otherParam;
                       my $otherReadingName;
                       if ($paramNr == 2) {
                        $otherParam = $params[0] eq $paramName ? $params[1] : $params[0];
                       }
                       
                       my $readingName = $readingNamePrep;
                       if (!defined($readingName)) {                                            #<==== Bisher noch kein Reading gefunden, z.B. setCurve
                         $readingName = $feature.".".$paramName;
                         if (defined($otherParam)) {
                            $otherReadingName = $feature.".".$otherParam;
                         }
                       }
                       
                       my $param = $item->{commands}{$commandName}{params}{$paramName};
                       
                       # fill $val
                       if ($param->{type} eq 'number') {
                            $val .= $readingName.":slider," . ($param->{constraints}{min}) . "," . ($param->{constraints}{stepping}) . "," . ($param->{constraints}{max});
                        # Schauen ob float für slider
                          if ($param->{constraints}{stepping} =~ m/\./)  {
                                $val .= ",1 ";
                          } else { 
                            $val .= " ";
                          }
                       }
                        elsif ($param->{'type'} eq 'string') {
                            if ($commandName eq "setMode") {
                              my $enum = $param->{constraints}->{'enum'};
                              Log(5,$name.", -set enum: ". $enum); 
                              my $enumNr = scalar @$enum;
                              Log(5,$name.", -set enumNr: ". $enumNr); 
                            
                              my $i = 1;
                              $val .= $readingName.":";
                               foreach my $value (@$enum) {
                                if ($i < $enumNr) {
                                 $val .= $value.",";
                                } else {
                                 $val .= $value." ";
                                }
                                $i++;
                               }
                            } else {
                              $val .= $readingName.":textField-long ";
                            }
                            
                        } elsif ($param->{'type'} eq 'Schedule') {
                            $val .= $readingName.":textField-long ";
                        } elsif ($param->{'type'} eq 'boolean') {
                            $val .= "$readingName ";
                        } else {
                            # Ohne type direkter befehl ohne args
                            $val .= "$readingName:noArg ";
                            Log(5,$name.", -set unknown type: ".$readingName);
                        }
                        
                        # Set execution
                        if ($opt eq $readingName) {
                            
                            my $data;
                            my $otherData = '';
                            if ($param->{type} eq 'number') {
                             $data = "{\"$paramName\":@args";
                            } else {
                             $data = "{\"$paramName\":\"@args\"";
                            }
                            
                            # 2 params, one can be set the other must just be read and handed overload
                            # This logic ensures that we get the correct names in an unsortet JSON
                            if (defined($otherReadingName)) {
                               my $otherValue = ReadingsVal($name,$otherReadingName,"");
                              if ($param->{type} eq 'number') {
                               $otherData = ",\"$otherParam\":$otherValue";
                              } else {
                               $otherData = ",\"$otherParam\":\"$otherValue\"";
                              }
                            }
                            $data .= $otherData . '}';
                            my $uri = $item->{commands}->{$commandName}->{'uri'};
                            my ($shortUri) = $uri =~ m|.*features/(.*)|; #<=== URI ohne gateway zeug
                            vitoconnect_action($hash,
                                $shortUri,
                                $data,
                                $name, $opt, @args
                            );
                            Log(5,$name.", -set data: ".$data);
                            return;
                        }
                    }
                }
            }
        }
    }

    # Zusätzliche Optionen
    if ($opt eq "update") {
        RemoveInternalTimer($hash);
        vitoconnect_GetUpdate($hash);
        return;
    } elsif ($opt eq "logResponseOnce") {
        $hash->{".logResponseOnce"} = 1;
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);
        return;
    } elsif ($opt eq "clearReadings") {
        AnalyzeCommand($hash, "deletereading $name .*");
        return;
    } elsif ($opt eq "password") {
        my $err = vitoconnect_StoreKeyValue($hash, "passwd", $args[0]);
        return $err if ($err);
        vitoconnect_getCode($hash);
        return;
    } elsif ($opt eq "apiKey") {
        $hash->{apiKey} = $args[0];
        my $err = vitoconnect_StoreKeyValue($hash, "apiKey", $args[0]);
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);
        return;
    }
    
    # Rückgabe der dynamisch erstellten $val Variable
    Log(5,$name.", -set val: ". $val);
    Log(5,$name.", -set ended ");
    
    #vitoconnect_check_gwa_and_get_gw($hash,$name);
    
    return $val;
}


sub vitoconnect_Set {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    
    if  (AttrVal( $name, 'vitoconnect_raw_readings', 0 ) eq "1" ) {
        #use new dynamic parsing of JSON to get raw setters
        
        return vitoconnect_Set_New ($hash,$name,$opt,@args);
    }
    
    if  (AttrVal( $name, 'vitoconnect_mapping_roger', 0 ) eq "1" ) {
        #use new dynamic parsing of JSON to get raw setters
        return vitoconnect_Set_Roger ($hash,$name,$opt,@args);
    }
    
    # SVN mapping original handling of modul
    return "set ".$name." needs at least one argument" unless (defined($opt) );

    if    ($opt eq "update")                            {   # set <name> update: update readings immeadiatlely
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_GetUpdate($hash);                       # neue Abfrage starten
        return;
    }
    elsif ($opt eq "logResponseOnce" )                  {   # set <name> logResponseOnce: dumps the json response of Viessmann server to entities.json, gw.json, actions.json in FHEM log directory
        $hash->{".logResponseOnce"} = 1;                    # in 'Internals' merken
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "clearReadings" )                    {   # set <name> clearReadings: clear all readings immeadiatlely
        AnalyzeCommand($hash,"deletereading ".$name." .*");
        return;
    }
    elsif ($opt eq "password" )                         {   # set <name> password: store password in key store
        my $err = vitoconnect_StoreKeyValue($hash,"passwd",$args[0]);   # Kennwort verschlüsselt speichern
        return $err if ($err);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "apiKey" )                           {   # set <name> apiKey: bisher keine Beschreibung
        $hash->{apiKey} = $args[0];
        my $err = vitoconnect_StoreKeyValue($hash,"apiKey",$args[0]);   # apiKey verschlüsselt speichern
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ( $opt eq "HK1-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK1-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK2-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Heizkurve-Niveau" ) {
        my $slope = ReadingsVal( $name, "HK3-Heizkurve-Steigung", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK1-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK2-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Heizkurve-Steigung" ) {
        my $shift = ReadingsVal( $name, "HK3-Heizkurve-Niveau", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK1-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK2-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "HK3-Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK1-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK2-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "HK3-Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.0.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.1.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Urlaub_unschedule" ) {
        vitoconnect_action(
            $hash,
            "heating.circuits.2.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Zeitsteuerung_Heizung" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Betriebsart" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_comfort_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.programs.comfort/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_comfort" ) {
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.0.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;

    }
    elsif ( $opt eq "HK2-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.1.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_eco_aktiv" ) {
        vitoconnect_action( $hash,
            "heating.circuits.2.operating.programs.eco/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_normal" ) {
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK2-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK3-Solltemperatur_reduziert" ) {
        vitoconnect_action($hash,
               "heating.circuits.2.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,
            $opt,
            @args
        );
        return;
    }
    elsif ( $opt eq "HK1-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.0/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK2-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.1/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "HK3-Name" ) {
        vitoconnect_action( $hash, "heating.circuits.2/commands/setName",
            "{\"name\":\"@args\"}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-einmaliges_Aufladen" ) {
        vitoconnect_action( $hash,
            "heating.dhw.oneTimeCharge/commands/$args[0]",
            "{}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Zirkulationspumpe_Zeitplan" ) {
        vitoconnect_action( $hash,
            "heating.dhw.pumps.circulation.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Zeitplan" ) {
        vitoconnect_action( $hash, "heating.dhw.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Haupttemperatur" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature.main/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Solltemperatur" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature/commands/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "WW-Temperatur_2" ) {
        vitoconnect_action( $hash,
            "heating.dhw.temperature.temp2/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}", $name, $opt, @args );
        return;
    }
    elsif ( $opt eq "Urlaub_Start" ) {
        my $end = ReadingsVal( $name, "Urlaub_Ende", "" );
        if ( $end eq "" ) {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action(
            $hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "Urlaub_Ende" ) {
        my $start = ReadingsVal( $name, "Urlaub_Start", "" );
        vitoconnect_action(
            $hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name, $opt, @args
        );
        return;
    }
    elsif ( $opt eq "Urlaub_unschedule" ) {
        vitoconnect_action( $hash,
            "heating.operating.programs.holiday/commands/unschedule",
            "{}", $name, $opt, @args );
        return;
    }

    my $val =
        "unknown value $opt, choose one of update:noArg clearReadings:noArg "
      . "password apiKey logResponseOnce:noArg "
      . "WW-einmaliges_Aufladen:activate,deactivate "
      . "WW-Zirkulationspumpe_Zeitplan:textField-long "
      . "WW-Zeitplan:textField-long "
      . "WW-Haupttemperatur:slider,10,1,60 "
      . "WW-Solltemperatur:slider,10,1,60 "
      . "WW-Temperatur_2:slider,10,1,60 "
      . "Urlaub_Start "
      . "Urlaub_Ende "
      . "Urlaub_unschedule:noArg ";

    if ( ReadingsVal( $name, "HK1-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK1-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK1-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK1-Zeitsteuerung_Heizung:textField-long "
          . "HK1-Urlaub_Start "
          . "HK1-Urlaub_Ende "
          . "HK1-Urlaub_unschedule:noArg "
          . "HK1-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK1-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK1-Solltemperatur_comfort:slider,4,1,37 "
          . "HK1-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK1-Solltemperatur_normal:slider,3,1,37 "
          . "HK1-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK1-Name ";
    }
    if ( ReadingsVal( $name, "HK2-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK2-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK2-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK2-Zeitsteuerung_Heizung:textField-long "
          . "HK2-Urlaub_Start "
          . "HK2-Urlaub_Ende "
          . "HK2-Urlaub_unschedule:noArg "
          . "HK2-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK2-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK2-Solltemperatur_comfort:slider,4,1,37 "
          . "HK2-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK2-Solltemperatur_normal:slider,3,1,37 "
          . "HK2-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK2-Name ";
    }
    if ( ReadingsVal( $name, "HK3-aktiv", "0" ) eq "1" ) {
        $val .=
            "HK3-Heizkurve-Niveau:slider,-13,1,40 "
          . "HK3-Heizkurve-Steigung:slider,0.2,0.1,3.5,1 "
          . "HK3-Zeitsteuerung_Heizung:textField-long "
          . "HK3-Urlaub_Start "
          . "HK3-Urlaub_Ende "
          . "HK3-Urlaub_unschedule:noArg "
          . "HK3-Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK3-Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK3-Solltemperatur_comfort:slider,4,1,37 "
          . "HK3-Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK3-Solltemperatur_normal:slider,3,1,37 "
          . "HK3-Solltemperatur_reduziert:slider,3,1,37 "
          . "HK3-Name ";
    }
    
    #vitoconnect_check_gwa_and_get_gw($hash,$name);
    
    return $val;
}


sub vitoconnect_Set_Roger {
    my ($hash,$name,$opt,@args ) = @_;  # Übergabe-Parameter
    return "set ".$name." needs at least one argument" unless (defined($opt) );

    if    ($opt eq "update")                            {   # set <name> update: update readings immeadiatlely
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_GetUpdate($hash);                       # neue Abfrage starten
        return;
    }
    elsif ($opt eq "logResponseOnce" )                  {   # set <name> logResponseOnce: dumps the json response of Viessmann server to entities.json, gw.json, actions.json in FHEM log directory
        $hash->{".logResponseOnce"} = 1;                    # in 'Internals' merken
        RemoveInternalTimer($hash);                         # bisherigen Timer löschen
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "clearReadings" )                    {   # set <name> clearReadings: clear all readings immeadiatlely
        AnalyzeCommand($hash,"deletereading ".$name." .*");
        return;
    }
    elsif ($opt eq "password" )                         {   # set <name> password: store password in key store
        my $err = vitoconnect_StoreKeyValue($hash,"passwd",$args[0]);   # Kennwort verschlüsselt speichern
        return $err if ($err);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "apiKey" )                           {   # set <name> apiKey: bisher keine Beschreibung
        $hash->{apiKey} = $args[0];
        my $err = vitoconnect_StoreKeyValue($hash,"apiKey",$args[0]);   # apiKey verschlüsselt speichern
        RemoveInternalTimer($hash);
        vitoconnect_getCode($hash);                         # Werte für: Access-Token, Install-ID, Gateway anfragen
        return;
    }
    elsif ($opt eq "HK1_Betriebsart" )                  {   # set <name> HKn_Betriebsart: sets HKn_Betriebsart to heating,standby
        vitoconnect_action($hash,
            "heating.circuits.0.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_normal" )     {   # set <name> HK1_Soll_Temp_normal: sets the normale target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_reduziert" )      {   # set <name> HK1_Soll_Temp_reduziert: sets the reduced target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_comfort" )        {   # set <name> HK1_Soll_Temp_comfort: set comfort target temperatur for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_comfort_aktiv" )  {   # set <name> HK1_Soll_Temp_comfort_aktiv: activate/deactivate comfort temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.comfort/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Soll_Temp_eco_aktiv" )      {   # set <name> HK1_Soll_Temp_eco_aktiv: activate/deactivate eco temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.eco/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Betriebsart" )                   {   # set <name> HKn_Betriebsart: sets WW_Betriebsart to balanced,off
        vitoconnect_action($hash,
            "heating.dhw.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_einmaliges_Aufladen" )           {   # set <name> WW_einmaliges_Aufladen: activate or deactivate one time charge for hot water
        vitoconnect_action($hash,
            "heating.dhw.oneTimeCharge/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Solltemperatur" )                {   # set <name> WW_Solltemperatur: sets hot water main temperature to targetTemperature, targetTemperature is an integer between 10 and 60
        vitoconnect_action($hash,
            "heating.dhw.temperature.main/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Zirkulationspumpe_Zeitplan" )    {   # set <name> WW_Zirkulationspumpe_Zeitplan: sets the schedule in JSON format for hot water circulation pump
        vitoconnect_action($hash,
            "heating.dhw.pumps.circulation.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "WW_Zeitplan" )                      {   # set <name> WW_Zeitplan: sets the schedule in JSON format for hot water
        vitoconnect_action($hash,
            "heating.dhw.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
#   elsif ($opt eq "WW_Solltemperatur" )                {   # set <name> WW_Solltemperatur: sets hot water temperature to targetTemperature, targetTemperature is an integer between 10 and 60
#       vitoconnect_action($hash,
#           "heating.dhw.temperature/commands/commands/setTargetTemperature",
#           "{\"temperature\":$args[0]}",
#           $name,$opt,@args
#       );
#       return;
#   }
    elsif ($opt eq "WW_Temperatur_2" )                  {   # set <name> WW_Temperatur_2: sets hot water 2 temperature to targetTemperature, targetTemperature is an integer between 10 and 60
        vitoconnect_action($hash,
            "heating.dhw.temperature.temp2/commands/setTargetTemperature",
            "{\"temperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "Urlaub_Start_Zeit" )                        {   # set <name> Urlaub_Start_Zeit: set holiday start time, start has to look like this: 2019-02-02
        my $end = ReadingsVal($name,"Urlaub_Ende_Zeit","");
        if ($end eq "")                                 {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "Urlaub_Ende_Zeit" )                     {   # set <name> Urlaub_Ende_Zeit: set holiday end time, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "Urlaub_stop" )              {   # set <name> Urlaub_stop: remove holiday start and end time
        vitoconnect_action($hash,
            "heating.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Name" )                         {   # set <name> HK1_Name: sets the name of the circuit for HKn
        vitoconnect_action($hash,
            "heating.circuits.0/commands/setName",
            "{\"name\":\"@args\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Name" )                         {   # set <name> HK2_Name: sets the name of the circuit for HKn
        vitoconnect_action($hash,
            "heating.circuits.1/commands/setName",
            "{\"name\":\"@args\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Name" )                         {   # set <name> HK3_Name: sets the name of the circuit for HKn
        vitoconnect_action($hash,
            "heating.circuits.2/commands/setName",
            "{\"name\":\"@args\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Heizkurve_Niveau" )             {   # set <name> HK1_Heizkurve_Niveau: set shift of heating curve for HKn
        my $slope = ReadingsVal($name,"HK1_Heizkurve_Steigung","");
        vitoconnect_action($hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Heizkurve_Niveau" )             {   #  set <name> HK2_Heizkurve_Niveau: set shift of heating curve for HKn
        my $slope = ReadingsVal($name,"HK2_Heizkurve_Steigung","");
        vitoconnect_action($hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Heizkurve_Niveau" )             {   # set <name> HK3_Heizkurve_Niveau: set shift of heating curve for HKn
        my $slope = ReadingsVal($name,"HK3_Heizkurve_Steigung","");
        vitoconnect_action($hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$args[0],\"slope\":$slope}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Heizkurve_Steigung" )           {   # set <name> HK1_Heizkurve_Steigung: set slope of heating curve for HKn
        my $shift = ReadingsVal($name,"HK1_Heizkurve_Niveau","");
        vitoconnect_action($hash,
            "heating.circuits.0.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Heizkurve_Steigung" )           {   # set <name> HK2_Heizkurve_Steigung: set slope of heating curve for HKn
        my $shift = ReadingsVal($name,"HK2-Heizkurve-Niveau","");
        vitoconnect_action($hash,
            "heating.circuits.1.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Heizkurve_Steigung" )           {   # set <name> HK3_Heizkurve_Steigung:  set slope of heating curve for HKn
        my $shift = ReadingsVal($name,"HK3-Heizkurve-Niveau","");
        vitoconnect_action($hash,
            "heating.circuits.2.heating.curve/commands/setCurve",
            "{\"shift\":$shift,\"slope\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Urlaub_Start_Zeit" )            {   # set <name> HK1_Urlaub_Start_Zeit: set holiday start time for HKn, start  has to look like this: 2019-02-16
        my $end = ReadingsVal($name,"HK1_Urlaub_Ende_Zeit","");
        if ($end eq "")         {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Urlaub_Start_Zeit" )            {   # set <name> HK2_Urlaub_Start_Zeit: set holiday start time for HKn, start  has to look like this: 2019-02-16
        my $end = ReadingsVal($name,"HK2_Urlaub_Ende_Zeit","");
        if ($end eq "")                                 {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Urlaub_Start_Zeit" )                    {   # set <name> HK3-HK3_Urlaub_Start_Zeit: set holiday start time for HKn, start  has to look like this: 2019-02-16
        my $end = ReadingsVal($name,"HK3_Urlaub_Ende_Zeit","");
        if ($end eq "")                                 {
            my $t = Time::Piece->strptime( $args[0], "%Y-%m-%d" );
            $t += ONE_DAY;
            $end = $t->strftime("%Y-%m-%d");
        }
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$args[0]\",\"end\":\"$end\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Urlaub_Ende_Zeit" )                 {   # set <name> HK1_Urlaub_Ende_Zeit: set holiday end time for HKn, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"HK1_Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Urlaub_Ende_Zeit" )                 {   # set <name> HK2_Urlaub_Ende_Zeit: set holiday end time for HKn, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"HK2_Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Urlaub_Ende_Zeit" )                 {   # set <name> HK3_Urlaub_Ende_Zeit: set holiday end time for HKn, end has to look like this: 2019-02-16
        my $start = ReadingsVal($name,"HK3_Urlaub_Start_Zeit","");
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.holiday/commands/schedule",
            "{\"start\":\"$start\",\"end\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Urlaub_stop" )          {   # set <name> HK1_Urlaub_stop: remove holiday start and end time for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Urlaub_stop" )          {   # set <name> HK2_Urlaub_stop: remove holiday start and end time for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Urlaub_stop" )          {   # set <name> HK3_Urlaub_stop: remove holiday start and end time for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.holiday/commands/unschedule",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK1_Zeitsteuerung_Heizung" )        {   # set <name> HK1_Zeitsteuerung_Heizung: sets the heating schedule in JSON format for HKn
        vitoconnect_action($hash,
            "heating.circuits.0.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2-Zeitsteuerung_Heizung" )        {   # set <name> HK2-Zeitsteuerung_Heizung: sets the heating schedule in JSON format for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3-Zeitsteuerung_Heizung" )        {   # set <name> HK3-Zeitsteuerung_Heizung: sets the heating schedule in JSON format for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.heating.schedule/commands/setSchedule",
            "{\"newSchedule\":@args}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Betriebsart" )                  {   # set <name> HK2-Betriebsart: sets HKn_Betriebsart to  heating,standby
        vitoconnect_action($hash,
            "heating.circuits.1.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Betriebsart" )                  {   # set <name> HK3-Betriebsart: sets HKn_Betriebsart to  heating,standby
        vitoconnect_action($hash,
            "heating.circuits.2.operating.modes.active/commands/setMode",
            "{\"mode\":\"$args[0]\"}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2-Solltemperatur_comfort_aktiv" ) {   # set <name> HK2-Solltemperatur_comfort_aktiv: activate/deactivate comfort temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3-Solltemperatur_comfort_aktiv" ) {   # set <name> HK3-Solltemperatur_comfort_aktiv: activate/deactivate comfort temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2-Solltemperatur_comfort" )       {   # set <name> HK2-Solltemperatur_comfort: set comfort target temperatur for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3-Solltemperatur_comfort" )       {   # set <name> HK3-Solltemperatur_comfort: set comfort target temperatur for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.comfort/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Solltemperatur_eco_aktiv" )     {   # set <name> HK2_Solltemperatur_eco_aktiv: activate/deactivate eco temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.eco/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Solltemperatur_eco_aktiv" )     {   # set <name> HK3_Solltemperatur_eco_aktiv: activate/deactivate eco temperature for HKn
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.eco/commands/$args[0]",
            "{}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Solltemperatur_normal" )        {   # set <name> HK2_Solltemperatur_normal: sets the normale target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Solltemperatur_normal" )        {   # set <name> HK3_Solltemperatur_normal: sets the normale target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.normal/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK2_Solltemperatur_reduziert" )     {   # set <name> HK2_Solltemperatur_reduziert: sets the reduced target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.1.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}",
            $name,$opt,@args
        );
        return;
    }
    elsif ($opt eq "HK3_Solltemperatur_reduziert" )     {   # set <name> HK3_Solltemperatur_reduziert: sets the reduced target temperature for HKn, where targetTemperature is an integer between 3 and 37
        vitoconnect_action($hash,
            "heating.circuits.2.operating.programs.reduced/commands/setTemperature",
            "{\"targetTemperature\":$args[0]}"
            ,$name,$opt,@args
        );
        return;
    }

    my $val =
         "unknown value $opt, choose one of update:noArg clearReadings:noArg "
        ."password apiKey logResponseOnce:noArg "
        ."WW_einmaliges_Aufladen:activate,deactivate "
        ."WW_Zirkulationspumpe_Zeitplan:textField-long "
        ."WW_Zeitplan:textField-long "
#       ."WW_Haupttemperatur:slider,10,1,60 "
        ."WW_Solltemperatur:slider,10,1,60 "
        ."WW_Temperatur_2:slider,10,1,60 "
        ."WW_Betriebsart:balanced,off "
        ."Urlaub_Start_Zeit "
        ."Urlaub_Ende_Zeit "
        ."Urlaub_stop:noArg ";

    if (ReadingsVal($name,"HK1_aktiv","0") eq "1") {
        $val .=
             "HK1_Heizkurve_Niveau:slider,-13,1,40 "
            ."HK1_Heizkurve_Steigung:slider,0.2,0.1,3.5,1 "
            ."HK1_Zeitsteuerung_Heizung:textField-long "
            ."HK1_Urlaub_Start_Zeit "
            ."HK1_Urlaub_Ende_Zeit "
            ."HK1_Urlaub_stop:noArg "
            ."HK1_Betriebsart:active,standby "
            ."HK1_Soll_Temp_comfort_aktiv:activate,deactivate "
            ."HK1_Soll_Temp_comfort:slider,4,1,37 "
            ."HK1_Soll_Temp_eco_aktiv:activate,deactivate "
            ."HK1_Soll_Temp_normal:slider,3,1,37 "
            ."HK1_Soll_Temp_reduziert:slider,3,1,37 "
            ."HK1_Name ";
    }
    if (ReadingsVal($name,"HK2_aktiv","0") eq "1") {
        $val .=
            "HK2_Heizkurve_Niveau:slider,-13,1,40 "
          . "HK2_Heizkurve_Steigung:slider,0.2,0.1,3.5,1 "
          . "HK2_Zeitsteuerung_Heizung:textField-long "
          . "HK2_Urlaub_Start_Zeit "
          . "HK2_Urlaub_Ende_Zeit "
          . "HK2_Urlaub_stop:noArg "
          . "HK2_Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK2_Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK2_Solltemperatur_comfort:slider,4,1,37 "
          . "HK2_Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK2_Solltemperatur_normal:slider,3,1,37 "
          . "HK2_Solltemperatur_reduziert:slider,3,1,37 "
          . "HK2_Name ";
    }
    if (ReadingsVal($name,"HK3_aktiv","0") eq "1") {
        $val .=
            "HK3_Heizkurve_Niveau:slider,-13,1,40 "
          . "HK3_Heizkurve_Steigung:slider,0.2,0.1,3.5,1 "
          . "HK3_Zeitsteuerung_Heizung:textField-long "
          . "HK3_Urlaub_Start_Zeit "
          . "HK3_Urlaub_Ende_Zeit "
          . "HK3_Urlaub_stop:noArg "
          . "HK3_Betriebsart:active,standby,heating,dhw,dhwAndHeating,forcedReduced,forcedNormal "
          . "HK3_Solltemperatur_comfort_aktiv:activate,deactivate "
          . "HK3_Solltemperatur_comfort:slider,4,1,37 "
          . "HK3_Solltemperatur_eco_aktiv:activate,deactivate "
          . "HK3_Solltemperatur_normal:slider,3,1,37 "
          . "HK3_Solltemperatur_reduziert:slider,3,1,37 "
          . "HK3_Name ";
    }
    
    #vitoconnect_check_gwa_and_get_gw($hash,$name);
    
    return $val;
}

#####################################################################################################################
# Attribute setzen/ändern/löschen
#####################################################################################################################
sub vitoconnect_Attr {
    my ($cmd,$name,$attr_name,$attr_value ) = @_;
        #Log(5,$name.", ".$cmd ." vitoconnect_: ".$attr_name." value: ".$attr_value);
    if ($cmd eq "set")  {
        if ($attr_name eq "vitoconnect_raw_readings" )      {
            if ($attr_value !~ /^0|1$/)                     {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_gw_readings")     {
            if ( $attr_value !~ /^0|1$/ ) {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_actions_active")  {
            if ($attr_value !~ /^0|1$/)                     {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_mappings")                        {
            $RequestListMapping = eval $attr_value;
            if ($@) {
                # Fehlerbehandlung
                my $err = "Invalid argument: $@\n";
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_translations")                        {
            %translations = eval $attr_value;
            if ($@) {
                # Fehlerbehandlung
                my $err = "Invalid argument: $@\n";
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_mapping_roger")   {
            if ($attr_value !~ /^0|1$/)                     {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 0 or 1.";
                Log(1,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "vitoconnect_serial")                      {
            # Zur Zeit kein prüfung, einfacher String
            if (length($attr_value) != 16)                      {
                my $err = "Invalid argument ".$attr_value." to ".$attr_name.". Must be 16 characters long.";
                Log(5,$name.", vitoconnect_Attr: ".$err);
                return $err;
            }
        }
        elsif ($attr_name eq "disable")                     {
        }
        elsif ($attr_name eq "verbose")                     {
        }
        else                                                {
            # return "Unknown attr $attr_name";
        }
    }
    elsif ($cmd eq "del") {
        if ($attr_name eq "vitoconnect_mappings") {
            undef $RequestListMapping;
    #       Log(1,$name.", undef $Requestlistmapping");
        }
        elsif ($attr_name eq "vitoconnect_translations") {
            undef %translations;
    #       Log(1,$name.", undef translations");
        }
    #   if ($attr_name eq "vitoconnect_serial") {
    #     $hash->{".gw"} = "";
    #     Log3($name,4,$name." - serial deleted");
    #   }
    }
    return;
}


#####################################################################################################################
# # Abfrage aller Werte starten
#####################################################################################################################
sub vitoconnect_GetUpdate {
    my ($hash) = @_;# Übergabe-Parameter
    my $name = $hash->{NAME};
    Log3($name,4,$name." - GetUpdate called ...");
    if (IsDisabled($name))      {   # Device disabled
        Log3($name,4,$name." - device disabled");
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);   # nach Intervall erneut versuchen
    }
    else                        {   # Device nicht disabled
        vitoconnect_getResource($hash);
    }
    return;
}


#####################################################################################################################
# Werte für: Access-Token, Install-ID, Gateway anfragen
#####################################################################################################################
sub vitoconnect_getCode {
    my ($hash)       = @_;  # Übergabe-Parameter
    my $name         = $hash->{NAME};
    my $isiwebpasswd = vitoconnect_ReadKeyValue($hash,"passwd");        # verschlüsseltes Kennwort auslesen
    my $client_id    = $hash->{apiKey};
    if (!defined($client_id))   {   # $client_id/apiKey nicht definiert
        Log3($name,1,$name." - set apiKey first");                      # Fehlermeldung ins Log
        readingsSingleUpdate($hash,"state","Set apiKey to continue",1); # Reading 'state' setzen
        return;
    }
    my $authorizeURL = 'https://iam.viessmann.com/idp/v2/authorize';

    my $param = {
        url => $authorizeURL
        ."?client_id=".$client_id
        ."&redirect_uri=".$callback_uri."&"
        ."code_challenge=2e21faa1-db2c-4d0b-a10f-575fd372bc8c-575fd372bc8c&"
        ."&scope=IoT%20User%20offline_access"
        ."&response_type=code",
        hash            => $hash,
        header          => "Content-Type: application/x-www-form-urlencoded",
        ignoreredirects => 1,
        user            => $hash->{user},
        pwd             => $isiwebpasswd,
        sslargs         => { SSL_verify_mode => 0 },
        timeout         => $hash->{timeout},
        method          => "POST",
        callback        => \&vitoconnect_getCodeCallback
    };

    #Log3 $name, 4, "$name - user=$param->{user} passwd=$param->{pwd}";
    #Log3 $name, 5, Dumper($hash);
    HttpUtils_NonblockingGet($param);   # Anwort an: vitoconnect_getCodeCallback()
    return;
}


#####################################################################################################################
# Rückgabe: Access-Token, Install-ID, Gateway von vitoconnect_getCode Anfrage
#####################################################################################################################
sub vitoconnect_getCodeCallback {
    my ($param,$err,$response_body ) = @_;  # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err eq "")                 {   # Antwort kein Fehler
        Log3($name,4,$name." - getCodeCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body);
        $response_body =~ /code=(.*)"/;
        $hash->{".code"} = $1;          # in Internal '.code' speichern
        Log3($name,4,$name." - code: ".$hash->{".code"});
        if ( $hash->{".code"} && $hash->{".code"} ne "4" )  {
            $hash->{login} = "ok";      # Internal 'login'
        }
        else {
            $hash->{login} = "failure"; # Internal 'login'
        }
    }
    else                            {   # Fehler als Antwort
        Log3($name,1,$name.", vitoconnect_getCodeCallback - An error occured: ".$err);
        $hash->{login} = "failure";
    }

    if ( $hash->{login} eq "ok" )   {   # Login hat geklappt
        readingsSingleUpdate($hash,"state","login ok",1);       # Reading 'state' setzen
        vitoconnect_getAccessToken($hash);  # Access & Refresh-Token holen
    }
    else                            {   # Fehler beim Login
        readingsSingleUpdate($hash,"state","Login failure. Check password and apiKey",1);   # Reading 'state' setzen
        Log3($name,1,$name." - Login failure. Check password and apiKey");
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);   # Forum: #880
    }
    return;
}


#####################################################################################################################
# Access & Refresh-Token holen
#####################################################################################################################
sub vitoconnect_getAccessToken {
    my ($hash)    = @_;                 # Übergabe-Parameter
    my $name      = $hash->{NAME};      # Device-Name
    my $client_id = $hash->{apiKey};    # Internal: apiKey
    my $param     = {
        url    => "https://iam.viessmann.com/idp/v2/token",
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=authorization_code"
        . "&code_verifier="
        . $client_secret
        . "&client_id=$client_id"
        . "&redirect_uri=$callback_uri"
        . "&code="
        . $hash->{".code"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        callback => \&vitoconnect_getAccessTokenCallback
    };

    #Log3 $name, 1, "$name - " . $param->{"data"};
    HttpUtils_NonblockingGet($param);   # Anwort an: vitoconnect_getAccessTokenCallback()
    return;
}


#####################################################################################################################
# Access & Refresh-Token speichern, Antwort auf: vitoconnect_getAccessToken
#####################################################################################################################
sub vitoconnect_getAccessTokenCallback {
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};   # Device-Name

    if ($err eq "")                 {   # kein Fehler bei Antwort
        Log3($name,4,$name." - getAccessTokenCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $decode_json = eval {decode_json($response_body)};
        if ($@)                     {
            Log3($name,1,$name.", vitoconnect_getAccessTokenCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        my $access_token = $decode_json->{"access_token"};              # aus JSON dekodieren
        if ($access_token ne "")    {
            $hash->{".access_token"} = $access_token;                   # in Internals speichern
            $hash->{"refresh_token"} = $decode_json->{"refresh_token"}; # in Internals speichern
#list   Heiz_ViessMann i:.access_token i:refresh_token

            Log3($name,4,$name." - Access Token: ".substr($access_token,0,20)."...");
            vitoconnect_getGw($hash);   # Abfrage Gateway-Serial
        }
        else                        {
            Log3($name,1,$name." - Access Token: nicht definiert");
            Log3($name,5,$name." - Received response: ".$response_body."\n");
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
        }
    }
    else                            {   # Fehler bei Antwort
        Log3($name,1,$name.",vitoconnect_getAccessTokenCallback - getAccessToken: An error occured: ".$err);
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# neuen Access-Token anfragen
#####################################################################################################################
sub vitoconnect_getRefresh {
    my ($hash,$gw,$last)    = @_;
    my $name      = $hash->{NAME};
    my $client_id = $hash->{apiKey};
    my $param     = {
        url    => "https://iam.viessmann.com/idp/v2/token",
        hash   => $hash,
        header => "Content-Type: application/x-www-form-urlencoded",
        data   => "grant_type=refresh_token"
          . "&client_id=$client_id"
          . "&refresh_token="
          . $hash->{"refresh_token"},
        sslargs  => { SSL_verify_mode => 0 },
        method   => "POST",
        timeout  => $hash->{timeout},
        gw       => $gw,
        last     => $last,
        callback => \&vitoconnect_getRefreshCallback
    };

    #Log3 $name, 1, "$name - " . $param->{"data"};
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# neuen Access-Token speichern
#####################################################################################################################
sub vitoconnect_getRefreshCallback {
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw     = $param->{gw};
    my $last   = $param->{last};

    if ($err eq "")                 {
        Log3($name,4,$name.". - getRefreshCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $decode_json = eval {decode_json($response_body)};
        if ($@)                     {   # Fehler aufgetreten
            Log3($name,1,$name.", vitoconnect_getRefreshCallback: JSON error while request: ".$@);
            if ($last == 1 ) {
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            }
            return;
        }
        my $access_token = $decode_json->{"access_token"};
        if ($access_token ne "")    {   # kein Fehler
            $hash->{".access_token"} = $access_token;   # in Internal merken
            Log3($name,4,$name." - Access Token: ".substr($access_token,0,20)."...");
            #vitoconnect_getGw($hash);  # Abfrage Gateway-Serial
            # directly call get resource to save API calls
            vitoconnect_getResource_per_gw($hash,$gw,$last);
        }
        else {
            Log3 $name, 1, "$name - Access Token: nicht definiert";
            Log3 $name, 5, "$name - Received response: $response_body\n";
            if ($last == 1 ) {
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);    # zurück zu getCode?
            return;
            }
        }
    }
    else {
        Log3 $name, 1, "$name - getRefresh: An error occured: $err";
        if ($last == 1 ) {
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
        }
    }
    return;
}


#####################################################################################################################
# Abfrage Gateway-Serial
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################
sub vitoconnect_getGw {
    my ($hash)       = @_;  # Übergabe-Parameter
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $param        = {
#       url      => $apiURL
        url      => $iotURL_V1
        ."gateways",
        hash     => $hash,
        header   => "Authorization: Bearer ".$access_token,
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getGwCallback
    };
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# Gateway-Serial speichern, Anwort von Abfrage Gateway-Serial
#####################################################################################################################
sub vitoconnect_getGwCallback {
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $singleSerial = "";
    

    if ($err eq "")                         {   # kein Fehler aufgetreten
        Log3($name,4,$name." - getGwCallback went ok");
        Log3($name,5,$name." - Received response: ".$response_body."\n");
        my $items = eval {decode_json($response_body)};
        if ($@)                             {   # Fehler beim JSON dekodieren
            readingsSingleUpdate($hash,"state","JSON error while request: ".$@,1);  # Reading 'state'
            Log3($name,1,$name.", vitoconnect_getGwCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        $err = vitoconnect_errorHandling($hash,$items);
        if ($err ==1){
           return;
        }
        
        if ($hash->{".logResponseOnce"} )   {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $file        = $dir->child("gw.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($items));            # Datei 'gw.json' schreiben
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
            }
            
            # Alle Gateways holen
            my @gwa=();
            foreach ( @{ $items->{data} } ) {
             my $gw    = $_;
             my $serial = $gw->{serial};
             if ( defined($serial) ) {
                 Log(5,$name.", - getGwCallback serial found, push to gwa: ".$serial);
                 push(@gwa, $serial);
                 if ( defined(AttrVal( $name, 'vitoconnect_serial', 0 )) && AttrVal( $name, 'vitoconnect_serial', 0 ) == $serial) {
                      $singleSerial = $serial;
                 } 
                 #else {
                #   $hash->{".gw"} = "";
                 #}
             }
            }
            $hash->{".gwa"} = [@gwa];
            my $string = join(", ", @gwa);
            Log(5,$name.", - getGwCallback gwa set to hash: ".$string);
            
            Log(5,$name.",  - getGwCallback vitoconnect_serial: ".AttrVal( $name, 'vitoconnect_serial', 0 ));
            if ($singleSerial eq "") {
                $hash->{".gw"} = "";
                Log(5,$name.", - getGwCallback No singleSerial will use gwa");
            } 
            else {
            Log(5,$name.", - getGwCallback Gw Serial matches given attribute serial, will take this serial for queries: ".$singleSerial);
            $hash->{".gw"} = $singleSerial;
            }
            
      if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
        readingsSingleUpdate($hash,"gw",$response_body,1);  # im Reading 'gw' merken
        readingsSingleUpdate($hash,"number_of_gateways",scalar @gwa,1);
      }

        vitoconnect_getInstallation($hash);
        vitoconnect_getInstallationFeatures($hash);
    }
    else                                    {   # Fehler aufgetreten
        Log3($name,1,$name." - An error occured: ".$err);
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# Abfrage Install-ID
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################
sub vitoconnect_getInstallation {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $param        = {
#       url      => $apiURL
        url      => $iotURL_V1
        ."installations",
        hash     => $hash,
        header   => "Authorization: Bearer ".$access_token,
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getInstallationCallback
        };
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# Install-ID speichern, Antwort von Abfrage Install-ID
#####################################################################################################################
sub vitoconnect_getInstallationCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ($err eq "")                         {
        Log3 $name, 4, "$name - getInstallationCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body";
        my $items = eval { decode_json($response_body) };
        if ($@) {
            readingsSingleUpdate( $hash, "state","JSON error while request: ".$@,1);
            Log3($name,1,$name.", vitoconnect_getInstallationCallback: JSON error while request: ".$@);
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        if ($hash->{".logResponseOnce"})    {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $file        = $dir->child("installation.json");
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($items));                # Datei 'installation.json' schreiben
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
        }
        my $id = $items->{data}[0]->{id};
        if ($id eq "")                      {
            Log3($name,1,$name." - Something went wrong. Will retry");
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
        }
        else {
            $hash->{".installation"} = $items->{data}[0]->{id};
            if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
               readingsSingleUpdate( $hash, "installation", $response_body, 1 );
            }
            vitoconnect_getDevice($hash);
        }
    }
    else {
        Log3 $name, 1, "$name - An error occured: $err";
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# Abfrage von Install-features speichern
#####################################################################################################################
sub vitoconnect_getInstallationFeatures {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    
    
    # installation features      #Fixme call only once
    my $param = {
#       url     => $apiURL
        url     => $iotURL_V2
        ."installations/".$installation."/features",
        hash    => $hash,
        header  => "Authorization: Bearer ".$access_token,
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getInstallationFeaturesCallback
    };
    
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
#Install-features speichern
#####################################################################################################################
sub vitoconnect_getInstallationFeaturesCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    
    my $decode_json = eval {decode_json($response_body)};
    if ((defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "")) {   # Fehler aufgetreten
        Log3($name,1,$name.",vitoconnect_getFeatures: Fehler während installation features: ".$err." :: ".$response_body);
        $err = vitoconnect_errorHandling($hash,$decode_json);
        if ($err ==1){
           return;
        }
    }
    else                                                {   #  kein Fehler aufgetreten
        if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
        readingsSingleUpdate($hash,"installation_features",$response_body,1);   # im Reading 'installation_features' merken
        }

    return;
    }
}
#####################################################################################################################
# Abfrage Device-ID
#####################################################################################################################
sub vitoconnect_getDevice {
    my ($hash)       = @_;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $gw           = $hash->{".gw"};
    my @gwa          = @{$hash->{".gwa"}};
    
    if (defined($gw) && $gw ne "") {
        Log(5,$name.", - getDevice gw found reduce gwa: ".$gw);
        @gwa = $gw;
    }
    my $index = 0;
    my $last = 0;
    my $last_index = $#gwa;
    foreach ( @gwa ) {
    $gw = $_;
    Log(5,$name.", --getDevice gw for call set: ".$gw);
    if ($index == $last_index) { 
     $last = 1;
    }
    my $param        = {
#       url     => $apiURL
        url     => $iotURL_V1
        ."installations/".$installation."/gateways/".$gw."/devices",
        hash    => $hash,
        gw      => $gw,
        last     => $last,
        header  => "Authorization: Bearer ".$access_token,
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getDeviceCallback
    };
    HttpUtils_NonblockingGet($param);
    $index++;
    };
    return;
}


#####################################################################################################################
# Device-ID speichern, Anwort von Abfrage Device-ID
#####################################################################################################################
sub vitoconnect_getDeviceCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw = $param->{gw};
    my $last = $param->{last};
   Log(5,$name.", -getDeviceCallback get device gw: ".$gw);
    if ($err eq "")                         {
        Log3 $name, 4, "$name - getDeviceCallback went ok";
        Log3 $name, 5, "$name - Received response: $response_body\n";
        my $items = eval { decode_json($response_body) };
        if ($@)                             {
            RemoveInternalTimer($hash);
            readingsSingleUpdate($hash,"state","JSON error while request: ".$@,1);
            Log3($name,1,$name.", vitoconnect_getDeviceCallback: JSON error while request: ".$@);           
            InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            return;
        }
        if ( $hash->{".logResponseOnce"} )  {
            my $dir         = path( AttrVal("global","logdir","log"));
            my $filename    = "device_" . $gw . ".json";
            my $file        = $dir->child($filename);
            my $file_handle = $file->openw_utf8();
            $file_handle->print(Dumper($items));            # Datei 'device.json' schreiben
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
        }
        if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
          readingsSingleUpdate($hash,"device",$response_body,1);    # im Reading 'device' merken
        }
        vitoconnect_getFeatures($hash,$gw,$last);
    }
    else {
        if ((defined($err) && $err ne "")) {    # Fehler aufgetreten
        Log3($name,1,$name." - An error occured: ".$err);
        } else {
        Log3($name,1,$name." - An undefined error occured");
        }
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    return;
}


#####################################################################################################################
# Abruf GW Features, Anwort von Abfrage Device-ID
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################

sub vitoconnect_getFeatures {
    my ($hash)       =  shift;  # Übergabe-Parameter
    my $gw           =  shift;
    my $last         =  shift;
    my $name         = $hash->{NAME};
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    #my $gw           = $hash->{".gw"};
    my $dev          = AttrVal($name,'vitoconnect_device',0);   # Attribut: vitoconnect_device (0,1), Standard: 0

    Log3($name,4,$name." - getFeatures went ok");

# Service Documents -ToDo

# Gateway features
    my $param = {
#       url    => $apiURL
        url    => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/features",
        hash   => $hash,
        gw     => $gw,
        last     => $last,
        header => "Authorization: Bearer ".$access_token,
        timeout => $hash->{timeout},
        sslargs => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getFeaturesCallback
    };
    
    HttpUtils_NonblockingGet($param);
    return;
}


#####################################################################################################################
# GW Features speichern
#   https://documentation.viessmann.com/static/iot/overview
#####################################################################################################################

sub vitoconnect_getFeaturesCallback {
    my ( $param, $err, $response_body ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $gw = $param->{gw};
    my $last = $param->{last};
    my @gwa = @{$hash->{".gwa"}};
    my $gwFilter = $hash->{".gw"};
    my $readingName ="gw_features";
    
    if (defined($gwFilter) && $gwFilter ne "") {
        Log(5,$name.", -getFeaturesCallback feature gwFilter found reduce gwa: ".$gw);
        @gwa = $gwFilter;
    }
    
    my $decode_json = eval {decode_json($response_body)};

    if ((defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "")) {   # Fehler aufgetreten
        Log3($name,1,$name.",vitoconnect_getFeatures: Fehler während Gateway features: ".$err." :: ".$response_body);
        $err = vitoconnect_errorHandling($hash,$decode_json);
        if ($err ==1){
           return;
        }
    }   
    else                                                {   # kein Fehler aufgetreten
    if (AttrVal( $name, 'vitoconnect_gw_readings', 0 ) eq "1") {
    if (scalar @gwa > 1) {
        $readingName = $readingName ."_". $gw;
    };
        readingsSingleUpdate($hash,$readingName,$response_body,1);  # im Reading 'gw_features' merken
    }
        vitoconnect_getResource_per_gw($hash,$gw,$last);
    }
}


#####################################################################################################################
# Errors bearbeiten
#####################################################################################################################
sub vitoconnect_errorHandling {
    my ($hash,$items,$gw,$last) = @_;
    my $name         = $hash->{NAME};
    
        if (!$items->{statusCode} eq "")    {
            Log3 $name, 4,
                "$name - statusCode: $items->{statusCode} "
              . "errorType: $items->{errorType} "
              . "message: $items->{message} "
              . "error: $items->{error}";
            readingsSingleUpdate(
                $hash,
                "state",
                "statusCode: $items->{statusCode} "
                  . "errorType: $items->{errorType} "
                  . "message: $items->{message} "
                  . "error: $items->{error}",
                1
            );
            if ( $items->{statusCode} eq "401" ) {
                #  EXPIRED TOKEN
                vitoconnect_getRefresh($hash,$gw,$last);    # neuen Access-Token anfragen
                return(1);
            }
            elsif ( $items->{statusCode} eq "404" ) {
                # DEVICE_NOT_FOUND
                readingsSingleUpdate($hash,"state","Device not found: Optolink prüfen!",1);
                Log3 $name, 1, "$name - Device not found: Optolink prüfen!";
                if ($last == 1 ) {
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                }
                return(1);
            }
            elsif ( $items->{statusCode} eq "429" ) {
                # RATE_LIMIT_EXCEEDED
                readingsSingleUpdate($hash,"state","Anzahl der möglichen API Calls in überschritten!",1);
                Log3 $name, 1,
                  "$name - Anzahl der möglichen API Calls in überschritten!";
                if ($last == 1 ) {
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                }
                return(1);
            }
            elsif ( $items->{statusCode} eq "502" ) {
                readingsSingleUpdate($hash,"state","temporärer API Fehler",1);
                # DEVICE_COMMUNICATION_ERROR error: Bad Gateway
                Log3 $name, 1, "$name - temporärer API Fehler";
                if ($last == 1 ) {
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                }
                return(1);
            }
            else {
                readingsSingleUpdate($hash,"state","unbekannter Fehler, bitte den Entwickler informieren!",1);
                Log3 $name, 1, "$name - unbekannter Fehler: "
                  . "Bitte den Entwickler informieren!";
                Log3 $name, 1,
                    "$name - statusCode: $items->{statusCode} "
                  . "errorType: $items->{errorType} "
                  . "message: $items->{message} "
                  . "error: $items->{error}";
                if ($last == 1 ) {
                InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
                }
                return(1);
            }
        }
};


#####################################################################################################################
# Get der Daten vom Gateway
# per GW ist für die logOnce und fürs initializieren
# Es wird in diesen Modi pro Gateway gerufen
#####################################################################################################################
sub vitoconnect_getResource_per_gw {
    my ($hash)       = shift;               # Übergabe-Parameter
    my $gw           = shift;
    my $last         = shift;
    my $name         = $hash->{NAME};   # Device-Name
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $dev          = AttrVal($name,'vitoconnect_device',0);

    Log3($name,4,$name." - enter getResourceOnce");
    Log3($name,4,$name." - access_token: ".substr($access_token,0,20)."...");
    Log3($name,4,$name." - installation: ".$installation);
    Log3($name,4,$name." - gw: ".$gw);
    if ($access_token eq "" || $installation eq "" || $gw eq "") {  # noch kein: Token, ID, GW
        if ($last == 1) {
         vitoconnect_getCode($hash);
        }
        return;
    }
    my $param = {
        url => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/devices/".$dev."/features",
        hash     => $hash,
        gw       => $gw,
        last     => $last,
        header   => "Authorization: Bearer $access_token",
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getResourceCallback
    };
    HttpUtils_NonblockingGet($param);   # non-blocking aufrufen --> Antwort an: vitoconnect_getResourceCallback
    return;
}


#####################################################################################################################
# Get der Daten vom Gateway
# Hier für den normalen Update
# Es wird im Sub entschieden ob für alle Gateways oder für eine vorgegeben Gateway Serial
#####################################################################################################################
sub vitoconnect_getResource {
    my ($hash)       = @_;              # Übergabe-Parameter
    my $name         = $hash->{NAME};   # Device-Name
    my $access_token = $hash->{".access_token"};
    my $installation = $hash->{".installation"};
    my $gw           = $hash->{".gw"};
    my $dev          = AttrVal($name,'vitoconnect_device',0);
    my $gwatemp      = $hash->{".gwa"};
    my @gwa = ();
    
    if (defined($gwatemp) && $gwatemp ne "") {
      @gwa = @{$gwatemp};
    }
    if (defined($gw) && $gw ne "") {
        Log(5,$name.", - vitoconnect_getResource Resource gw found reduce gwa: ".$gw);
        @gwa = $gw;
    }
    
    my $index = 0;
    my $last = 0;
    my $last_index = $#gwa;
    if ($last_index == -1)
    {
         Log3($name,3,$name." - getResource missing gateway information: will try to get it fresh");
         vitoconnect_getCode($hash);
    }
    foreach ( @gwa ) {
    $gw = $_;
    Log3($name,4,$name." - enter getResource");
    Log3($name,4,$name." - access_token: ".substr($access_token,0,20)."...");
    Log3($name,4,$name." - installation: ".$installation);
    Log3($name,4,$name." - gw: ".$gw);
    if ($access_token eq "" || $installation eq "" || $gw eq "") {  # noch kein: Token, ID, GW
        Log3($name,3,$name." - getResource missing information Token: $access_token, Installation: $installation, Gateway: $gw");
        if ($last == 1) {
         Log3($name,3,$name." - getResource missing information: will try to get it fresh");
         vitoconnect_getCode($hash);
        }
        return;
    }
    if ($index == $last_index) { 
     $last = 1;
    }
    my $param = {
#       url => $apiURL
        url => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/devices/".$dev."/features",
        hash     => $hash,
        gw       => $gw,
        last     => $last,
        header   => "Authorization: Bearer $access_token",
        timeout  => $hash->{timeout},
        sslargs  => { SSL_verify_mode => 0 },
        callback => \&vitoconnect_getResourceCallback
    };
    HttpUtils_NonblockingGet($param);   # non-blocking aufrufen --> Antwort an: vitoconnect_getResourceCallback
    $index++;
    };
    return;
}


#####################################################################################################################
# Verarbeiten der Daten vom Gateway und schreiben in Readings
# Entweder statisch gemapped oder über attribute mapping gemapped oder nur raw Werte
# Wenn gemapped wird wird für alle Treffer des Mappings kein raw Wert mehr aktualisiert
#####################################################################################################################
sub vitoconnect_getResourceCallback {   
    my ($param,$err,$response_body) = @_;   # Übergabe-Parameter
    my $hash   = $param->{hash};
    my $name   = $hash->{NAME};
    my $gw     = $param->{gw};
    my $last   = $param->{last};
    my @gwa    = @{$hash->{".gwa"}};
    my $gwFilter = $hash->{".gw"};
    
    $Response = $response_body;

    Log(5,$name.", -getResourceCallback started");
    
    if (defined($gwFilter) && $gwFilter ne "") {
        Log(5,$name.", -getResourceCallback feature gwFilter found reduce gwa: ".$gw);
        @gwa = $gwFilter;
    }
    
    Log3($name,5,$name." getResourceCallback calles with gw:".$gw); 
    Log3($name,5,$name." getResourceCallback calles with number gwas:".scalar @gwa );
    
    if ($err eq "")                         {   # kein Fehler aufgetreten
        Log3($name,4,$name." - getResourceCallback went ok");
        Log3($name,5,$name." - Received response: ".substr($response_body,0,100)."...");
        my $items = eval {decode_json($response_body)};
        if ($@)                             {   # Fehler beim JSON dekodieren
            readingsSingleUpdate($hash,"state","JSON error while request: ".$@,1);  # Reading 'state'
            Log3($name,1,$name.", vitoconnect_getResourceCallback: JSON error while request: ".$@);
            if ($last == 1) {
             InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
            }
            return;
        }
        
        $err = vitoconnect_errorHandling($hash,$items,$gw,$last);
        if ($err ==1){
           return;
        }

        if ($hash->{".logResponseOnce"} ) {
            my $dir         = path(AttrVal("global","logdir","log"));   # Verzeichnis
            my $file        = $dir->child("resource_".$gw.".json");             # Dateiname
            my $file_handle = $file->openw_utf8();
            #$file_handle->print(Dumper($items));                       # Datei 'resource.json' schreiben
            $file_handle->print(Dumper($response_body));                        # Datei 'resource.json' schreiben
            Log3($name,3,$name." Datei: ".$dir."/".$file." geschrieben");
            if ($last == 1) {
            $hash->{".logResponseOnce"} = 0;
            }
        }
        
        my $gwaCount = scalar @gwa;
        
        Log(5,$name.", translations count:".scalar keys %translations);
        Log(5,$name.", RequestListMapping count:".scalar keys %$RequestListMapping);
        
        readingsBeginUpdate($hash);
        foreach ( @{ $items->{data} } ) {
            my $feature    = $_;
            my $properties = $feature->{properties};
            
            
        if (AttrVal( $name, 'vitoconnect_actions_active', 0 ) eq "1") {
        # Write all commands
         if (exists $feature->{commands}) {
          foreach my $command (keys %{$feature->{commands}}) {
           my $Reading = $feature->{feature}.".".$command;
           my $Value = $feature->{commands}{$command}{uri};
            readingsBulkUpdate($hash,$Reading,$Value,1);
          }
         }
        }
        
            
            foreach my $key ( sort keys %$properties ) {
                
                
                my $Reading = "";
                
                if ( scalar keys %translations > 0) {
                    
                    # Use translation from attr
                    my @parts = split(/\./, $feature->{feature} . "." . $key);
                     foreach my $part (@parts) {
                      if ($part !~ /\d+/) {
                       $part = $translations{$part} // $part;  # Übersetze den Teil oder behalte ihn bei
                      }
                     }
                    
                    $Reading = join('.', @parts);
                    
                }
                elsif ( scalar keys %$RequestListMapping > 0) {
                # Use RequestListMapping from Attr
                $Reading =
                  $RequestListMapping->{ $feature->{feature} . "." . $key };
                }
                elsif (AttrVal( $name, 'vitoconnect_mapping_roger', 0 ) eq "1") {
                 # Use build in Mapping Roger (old way)
                 $Reading = $RequestListRoger->{ $feature->{feature} . "." . $key };
                }
                else {
                 # Use build in Mapping SVN (old way)
                 $Reading = $RequestListSvn->{ $feature->{feature} . "." . $key };
                };

                if ( !defined($Reading) || AttrVal( $name, 'vitoconnect_raw_readings', 0 ) eq "1" )
                {   
                    $Reading = $feature->{feature} . "." . $key;
                }
                
                # If no serial is defined and there is more than one gateway add the gateway serial to the readings
                if ($gwaCount > 1) {
                 $Reading = $Reading ."_". $gw;
                };
                
                my $Type  = $properties->{$key}->{type};
                my $Value = $properties->{$key}->{value};
                my $comma_separated_string = "";
                if ( $Type eq "array" ) {
                    if ( defined($Value) ) {
                        if (ref($Value->[0]) eq 'HASH') {
                        foreach my $entry (@$Value) {
                            foreach my $hash_key (sort keys %$entry) {
                                if ($hash_key ne "audiences") {
                                    my $hash_value = $entry->{$hash_key};
                                    if (ref($hash_value) eq 'ARRAY') {
                                        $comma_separated_string .= join(", ", @$hash_value) . ", ";
                                    } else {
                                        $comma_separated_string .= $hash_value . ", ";
                                    }
                                }
                            }
                        }
                         # Entferne das letzte Komma und Leerzeichen
                         $comma_separated_string =~ s/, $//;
                         readingsBulkUpdate($hash,$Reading,$comma_separated_string);
                        }
                        elsif (ref($Value) eq 'ARRAY') {
                            $comma_separated_string = ( join(",",@$Value) );
                            readingsBulkUpdate($hash,$Reading,$comma_separated_string);
                            Log3($name,5,$name." - ".$Reading." ".$comma_separated_string." (".$Type.")");
                        }
                        else {
                            Log3($name,4,$name." - Array Workaround for Property: ".$Reading);
                        }
                    }
                }
                elsif ($Type eq 'object') {
                    # Iteriere durch die Schlüssel des Hashes
                    foreach my $hash_key (sort keys %$Value) {
                        my $hash_value = $Value->{$hash_key};
                        $comma_separated_string .= $hash_value . ", ";
                    }
                # Entferne das letzte Komma und Leerzeichen
                $comma_separated_string =~ s/, $//;
                readingsBulkUpdate($hash,$Reading,$comma_separated_string);
                }
                elsif ( $Type eq "Schedule" ) {
                    my $Result = encode_json($Value);
                    readingsBulkUpdate($hash,$Reading,$Result);
                    Log3($name, 5, "$name - $Reading: $Result ($Type)");
                }
                else {
                    readingsBulkUpdate($hash,$Reading,$Value);
                    Log3 $name, 5, "$name - $Reading: $Value ($Type)";
                    #Log3 $name, 1, "$name - $Reading: $Value ($Type)";
                }
                
                # Store power readings as asSingleValue
                if ($Reading =~ m/dayValueReadAt$/) {
                 Log(5,$name.", -call setpower $Reading");
                 vitoconnect_getPowerLast ($hash,$name,$Reading);
                }
            }
        }

        readingsBulkUpdate($hash,"state","last update: ".TimeNow().""); # Reading 'state'
        readingsEndUpdate( $hash, 1 );  # Readings schreiben
    }
    else {
        Log3($name,1,$name." - An error occured: ".$err);
    }
    if ($last == 1 ) {
      InternalTimer(gettimeofday() + $hash->{intervall},"vitoconnect_GetUpdate",$hash);
    }
    Log(5,$name.", -getResourceCallback ended");
    
    
    return;
}

sub vitoconnect_getPowerLast {
    my ($hash, $name, $Reading) = @_;

    # entferne alles hinter dem letzten Punkt
    $Reading =~ s/\.[^.]*$//;
    
    # Liste der Stromwerte
    my @values = split(",", ReadingsVal($name,$Reading.".day","")); #(1.2, 76.7, 52.6, 40.9, 40.4, 30, 33.9, 75);

    # Zeitpunkt des ersten Wertes
    my $timestamp = ReadingsVal($name,$Reading.".dayValueReadAt",""); #'2024-11-29T11:28:56.915Z';

    if (!defined($timestamp)) {
        return;
    }

    # Datum extrahieren und in ein Time::Piece Objekt umwandeln
    my $date = Time::Piece->strptime(substr($timestamp, 0, 10), '%Y-%m-%d');

    # Anzahl der Sekunden in einem Tag
    my $one_day = 24 * 60 * 60;
    
    # Hash für die Key-Value-Paare
    my %data;
    my $readingLastTimestamp = ReadingsTimestamp($name,$Reading.".day.asSingleValue",'');
    my $lastTS = "0000000000";
    if ($readingLastTimestamp ne "") {
    $lastTS = time_str2num($readingLastTimestamp);
    }
    Log(5,$name.", -setpower: readinglast: $readingLastTimestamp lastTS $lastTS");
    
    # Werte den entsprechenden Tagen zuordnen, start mit 1, letzten Tag ausschließen weil unvollständig
    for (my $i = $#values; $i >= 1; $i--) {
        my $current_date = $date - ($one_day * $i);
        Log3($name, 5, ", -setpower: date:$current_date value:$values[$i] ($i)");
        my $readingDate = $current_date->ymd . " 23:59:59";
        my $readingTS = time_str2num($readingDate);
        Log(5,$name.", -setpower: date $readingDate lastdate $readingLastTimestamp");
        if ($readingTS > $lastTS) {
         readingsBulkUpdate ($hash, $Reading.".day.asSingleValue", $values[$i], undef, $readingDate);
         Log(4,$name.", -setpower: readingsBulkUpdate ($hash, $Reading.day.asSingleValue, $values[$i], undef, $readingDate");
        }
    }

    return;
}


#   https://documentation.viessmann.com/static/getting-started
#V1     https://documentation.viessmann.com/gatewayfeatures-featuresapi-mw-iot/v1#gatewayfeatures-featuresapi-mw-iot_Execute_gateway_feature_command

#   Execute gateway feature command
#       https://api.viessmann.com/iot/v1/features/gateways/{gatewaySerial}/features/{featureName}/commands/{commandName}
#   Execute installation gateway device feature command
#       https://api.viessmann.com/iot/v1/features/installations/{installationId}/gateways/{gatewaySerial}/devices/{deviceId}/features/{featureName}/commands/{commandName}
#   Execute installation gateway feature command
#       https://api.viessmann.com/iot/v1/features/installations/{installationId}/gateways/{gatewaySerial}/features/{featureName}/commands/{commandName}
#   Update gateway device
#       https://api.viessmann.com/iot/v1/equipment/installations/{installationId}/gateways/{gatewaySerial}/devices/{deviceId}

#V2     https://documentation.viessmann.com/gatewayfeatures-featuresapi-mw-iot/v2#gatewayfeatures-featuresapi-mw-iot_Execute_gateway_feature_command
#   Execute gateway feature command
#       https://api.viessmann.com/iot/v2/features/gateways/{gatewaySerial}/features/{featureName}/commands/{commandName}
#   Execute installation gateway device feature command
#   https://documentation.viessmann.com/installationgatewaydevicefeatures-featuresapi-mw-iot/v2#installationgatewaydevicefeatures-featuresapi-mw-iot_Execute_installation_gateway_device_feature_command
#             https://api.viessmann.com/iot/v2/features/installations/{installationId}/gateways/{gatewaySerial}/devices/{deviceId}/features/{featureName}/commands/{commandName}


#   https://documentation.viessmann.com/gatewaydevices-equipment-mw-iot/v1#gatewaydevices-equipment-mw-iot_Update_gateway_device
#       https://api.viessmann.com/iot/v1/equipment/installations/{installationId}/gateways/{gatewaySerial}/devices/{deviceId}
#       curl --request PUT \
#       --url https://api.viessmann.com/iot/v1/equipment/installations/{installationId}/gateways/{gatewaySerial}/devices/{deviceId} \
#       --header 'content-type: application/json' \
#       --header 'authorization: auth_token' \
#       --data '{
#           "boilerSerial": "123456789012",
#           "bmuSerial": "123456789012"
#       }'
#set    Heiz_ViessMann HK1_Betriebsart standby

sub vitoconnect_check_gwa_and_get_gw {
    my ($hash,$name) = @_;  # Übergabe-Parameter
    my $gw           = $hash->{".gw"};                  # Internal: .gw
    my $gwatemp      = $hash->{".gwa"};
    my @gwa = ();

    if (defined($gwatemp) && $gwatemp ne "") {
      @gwa = @{$gwatemp};
    }
    
    if (defined($gw) && $gw ne "") {
        Log3($name,3,$name.", -vitoconnect_check_gwa_and_get_gw: gwFilter found reduce gwa: ".$gw);
        @gwa = $gw;
    }
    
    if (scalar @gwa > 1) {
        readingsSingleUpdate($hash,"Aktion_Status","Fehler: mehr als ein Gateway. Bitte Device Doku lesen und vitoconnect_serial setzen",1);    # Reading 'Aktion_Status' setzen
        return(-1);
    } elsif (scalar @gwa == 0) {
        readingsSingleUpdate($hash,"Aktion_Status","Fehler: kein Gateway gefunden. Bitte Entwickler melden mit gw.json aud FHEM log",1);    # Reading 'Aktion_Status' setzen
        return(-1);
    } else {
     $gw = $gwa[0];
    }
    return $gw;
}

#####################################################################################################################
# Setzen von Daten
#####################################################################################################################
sub vitoconnect_action {
    my ($hash,$feature,$data,$name,$opt,@args ) = @_;   # Übergabe-Parameter
    my $access_token = $hash->{".access_token"};        # Internal: .access_token
    my $installation = $hash->{".installation"};        # Internal: .installation   
    my $dev          = AttrVal($name,'vitoconnect_device',0);   # Attribut: vitoconnect_device
    
    my $gw = vitoconnect_check_gwa_and_get_gw($hash,$name);
    if ($gw == -1){
        return;
    }
    
    my $param        = {
        url => $iotURL_V2
        ."installations/".$installation."/gateways/".$gw."/"
        ."devices/".$dev."/features/".$feature,
        hash   => $hash,
        header => "Authorization: Bearer ".$access_token."\r\n"
        . "Content-Type: application/json",
        data    => $data,
        timeout => $hash->{timeout},            # Timeout von Internals = 15s
        method  => "POST",
        sslargs => { SSL_verify_mode => 0 },
    };
    Log3($name,3,$name.", vitoconnect_action url=" .$param->{url});
    Log3($name,3,$name.", vitoconnect_action data=".$param->{data});
#   https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_BlockingGet
    (my $err,my $msg) = HttpUtils_BlockingGet($param);
    my $decode_json = eval {decode_json($msg)};

    Log3($name,3,$name.", vitoconnect_action call finished err:" .$err);
    my $Text = join(' ',@args); # Befehlsparameter in Text
    if ( (defined($err) && $err ne "") || (defined($decode_json->{statusCode}) && $decode_json->{statusCode} ne "") )                   {   # Fehler bei Befehlsausführung
        readingsSingleUpdate($hash,"Aktion_Status","Fehler: ".$opt." ".$Text,1);    # Reading 'Aktion_Status' setzen
        Log3($name,1,$name.",vitoconnect_action: set ".$name." ".$opt." ".@args.", Fehler bei Befehlsausfuehrung: ".$err." :: ".$msg);
    }
    else                                                                {   # Befehl korrekt ausgeführt
        readingsSingleUpdate($hash,"Aktion_Status","OK: ".$opt." ".$Text,1);    # Reading 'Aktion_Status' setzen
        readingsSingleUpdate($hash,$opt,$Text,1);   # Reading updaten
        Log3($name,3,$name.",vitoconnect_action: set ".$name." ".$opt." ".$Text.", korrekt ausgefuehrt");
    }
    return;
}


#####################################################################################################################
# Werte verschlüsselt speichern
#####################################################################################################################
sub vitoconnect_StoreKeyValue {
    # checks and stores obfuscated keys like passwords
    # based on / copied from FRITZBOX_storePassword
    my ( $hash, $kName, $value ) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;
    my $enc   = "";

    if ( eval "use Digest::MD5;1" ) {
        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
    }
    for my $char ( split //, $value ) {
        my $encode = chop($key);
        $enc .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }
    my $err = setKeyValue( $index, $enc );      # Die Funktion setKeyValue() speichert die Daten $value unter dem Schlüssel $key ab.
    return "error while saving the value - ".$err if ( defined($err) ); # Fehler
    return;
}


#####################################################################################################################
# verschlüsselte Werte auslesen
#####################################################################################################################
sub vitoconnect_ReadKeyValue {

    # reads obfuscated value

    my ($hash,$kName) = @_;     # Übergabe-Parameter
    my $name = $hash->{NAME};

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_".$kName;
    my $key   = getUniqueId().$index;

    my ( $value, $err );

    Log3($name,5,$name." - ReadKeyValue tries to read value for ".$kName." from file");
    ($err,$value ) = getKeyValue($index);       # Die Funktion getKeyValue() gibt Daten, welche zuvor per setKeyValue() gespeichert wurden, zurück.

    if ( defined($err) )    {   # im Fehlerfall
        Log3($name,1,$name." - ReadKeyValue is unable to read value from file: ".$err);
        return;
    }

    if ( defined($value) )  {
        if ( eval "use Digest::MD5;1" ) {
            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }
        my $dec = '';
        for my $char ( map  { pack( 'C', hex($_) ) } ( $value =~ /(..)/g ) ) {
            my $decode = chop($key);
            $dec .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }
        return $dec;            # Rückgabe dekodierten Wert
    }
    else                    {   # Fehler: 
        Log3($name,1,$name." - ReadKeyValue could not find key ".$kName." in file");
        return;
    }
    return;
}


1;


=pod
=item device
=item summary support for Viessmann API
=item summary_DE Unterstützung für die Viessmann API
=begin html

<a id="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implements a device for the Viessmann API
    <a href="https://www.viessmann.de/de/viessmann-apps/vitoconnect.html">Vitoconnect100</a>
    based on investigation of
    <a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a><br>
    
     You need the user and password from the ViCare App account.<br>
     
     For details see: <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (german)</a><br><br>
     
     vitoconnect needs the following libraries:
     <ul>
     <li>Path::Tiny</li>
     <li>JSON</li>
     <li>JSON:XS</li>
     <li>DateTime</li>
     </ul>   
         
     Use <code>sudo apt install libtypes-path-tiny-perl libjson-perl libdatetime-perl</code> or 
     install the libraries via cpan. 
     Otherwise you will get an error message "cannot load module vitoconnect".
     
    <br><br>
    <a id="vitoconnect-define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code><br>
        It is a good idea to use a fake password here an set the correct one later because it is
        readable in the detail view of the device
        <br><br>
        Example:<br>
        <code>define vitoconnect vitoconnect user@mail.xx fakePassword 60</code><br>
        <code>set vitoconnect password correctPassword 60</code>
        <br><br>
                
    </ul>
    <br>
    
    <a id="vitoconnect-set"></a>
    <b>Set</b><br>
    <ul>
        <a id="vitoconnect-set-update"></a>
        <li><code>update</code><br>
            update readings immeadiatlely</li>
        <a id="vitoconnect-set-clearReadings"></a>
        <li><code>clearReadings</code><br>
            clear all readings immeadiatlely</li> 
        <a id="vitoconnect-set-password"></a>
        <li><code>password passwd</code><br>
            store password in key store</li>
        <a id="vitoconnect-set-logResponseOnce"></a>
        <li><code>logResponseOnce</code><br>
            Dumps the json response of Viessmann server to entities.json,
            gw.json, actions.json in FHEM log directory.
            If you have more than one gateway the gateway serial is attached to the files.</li>
        <a id="vitoconnect-set-apiKey"></a>
        <li><code>apiKey</code><br>
            Since viessmann changed to V2 API you need to create an API Key under https://developer.viessmann.com/.
            Create an account, add a new client (google reCAPTCHA disabled, Redirect URI = http://localhost:4200/).
            Copy the Client ID here as apiKey</li>
        <br>
        <code>New setters used if vitoconnect_raw_readings = 1, if you have more than one gateway serial you must define it to use the setters<code>
        <code>Old static mapping setters, only used if attr vitoconnect_raw_readings = 0<code>
        <li><code>HKn_Heizkurve_Niveau shift</code><br>
            set shift of heating curve for HKn</li>
        <li><code>HKn_Heizkurve_Steigung slope</code><br>
            set slope of heating curve for HKn</li>
      
        <li><code>HKn_Urlaub_Start_Zeit start</code><br>
            set holiday start time for HKn<br>
            start has to look like this: 2019-02-02</li>
        <li><code>HKn_Urlaub_Ende_Zeit end</code><br>
            set holiday end time for HKn<br>
            end has to look like this: 2019-02-16</li>
        <li><code>HKn_Urlaub_stop</code> <br>
            remove holiday start and end time for HKn</li>
            
        <li><code>HKn_Zeitsteuerung_Heizung schedule</code><br>
            sets the heating schedule for HKn in JSON format <br>
            e.g. {"mon":[],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[],"sun":[]} is completly off
            and {"mon":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "tue":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "wed":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "thu":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "fri":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "sat":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "sun":[{"mode":"on","start":"00:00","end":"24:00","position":0}]} is on 24/7</li>

        <li><code>HKn_Betriebsart heating,standby</code> <br>
            sets HKn_Betriebsart to heating,standby</li>

        <li><code>WW_Betriebsart balanced,off</code> <br>
            sets WW_Betriebsart to balanced,off</li>

        <li><code>HKn_Soll_Temp_comfort_aktiv activate,deactivate</code> <br>
            activate/deactivate comfort temperature for HKn</li>
        <li><code>HKn_Soll_Temp_comfort targetTemperature</code><br>
            set comfort target temperatur for HKn</li>
        <li><code>HKn_Soll_Temp_eco_aktiv activate,deactivate </code><br>
            activate/deactivate eco temperature for HKn</li>
            
        <li><code>HKn_Soll_Temp_normal targetTemperature</code><br>
            sets the normale target temperature for HKn, where targetTemperature is an
            integer between 3 and 37</li>
        <li><code>HKn_Soll_Temp_reduziert targetTemperature</code><br>
            sets the reduced target temperature for HKn, where targetTemperature is an
            integer between 3 and 37 </li>
        
        <li><code>HKn_Name name</code><br>
            sets the name of the circuit for  HKn</li>      
        
        <li><code>WW_einmaliges_Aufladen activate,deactivate</code><br>
            activate or deactivate one time charge for hot water </li>
       
        <li><code>WW_Zirkulationspumpe_Zeitplan  schedule</code><br>
            sets the schedule in JSON format for hot water circulation pump </li>
        <li><code>WW_Zeitplan schedule</code> <br>
            sets the schedule in JSON format for hot water </li>
            
#       <li><code>WW_Haupttemperatur targetTemperature</code><br>
#           targetTemperature is an integer between 10 and 60<br>
#           sets hot water main temperature to targetTemperature </li>
        <li><code>WW_Solltemperatur targetTemperature</code><br>
            targetTemperature is an integer between 10 and 60<br>
            sets hot water temperature to targetTemperature </li>    

        <li><code>Urlaub_Start_Zeit start</code><br>
            set holiday start time <br>
            start has to look like this: 2019-02-02</li>
        <li><code>Urlaub_Ende_Zeit end</code><br>
            set holiday end time <br>
            end has to look like this: 2019-02-16</li>
        <li><code>Urlaub_stop</code> <br>
            remove holiday start and end time </li>
       
    </ul>
    </ul>
    <br>

    <a name="vitoconnectget"></a>
    <b>Get</b><br>
    <ul>
        nothing to get here 
    </ul>
    <br>
    
<a name="vitoconnect-attr"></a>
<b>Attributes</b>
<ul>
    <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
    <br><br>
    See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more info about the attr command.
    <br><br>
    Attributes:
    <ul>
        <a id="vitoconnect-attr-disable"></a>
        <li><i>disable</i>:<br>         
            Stop communication with the Viessmann server.
        </li>
        <a id="vitoconnect-attr-verbose"></a>
        <li><i>verbose</i>:<br>         
            Set the verbosity level.
        </li>           
        <a id="vitoconnect-attr-vitoconnect_raw_readings"></a>
        <li><i>vitoconnect_raw_readings</i>:<br>         
            Create readings with plain JSON names like 'heating.circuits.0.heating.curve.slope' instead of German identifiers (old mapping), mapping attribute, or translation attribute.<br>
            When using raw readings, setters will be created dynamically matching the raw readings (new).<br>
            I recommend this setting since you get everything as dynamically as possible from the API.<br>
            You can use stateFormat or userReadings to display your important readings with a readable name.<br>
            If vitoconnect_raw_readings is set, no mapping will be used.
        </li>
        <a id="vitoconnect-attr-vitoconnect_gw_readings"></a>
        <li><i>vitoconnect_gw_readings</i>:<br>         
            Create readings from the gateway, including information if you have more than one gateway.
        </li>
        <a id="vitoconnect-attr-vitoconnect_actions_active"></a>
        <li><i>vitoconnect_actions_active</i>:<br>
            Create readings for actions, e.g., 'heating.circuits.0.heating.curve.setCurve.setURI'.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mappings"></a>
        <li><i>vitoconnect_mappings</i>:<br>
            Define your own mapping of key-value pairs instead of using the built-in ones. The format has to be:<br>
            mapping<br>
            {  'device.serial.value' => 'device_serial',<br>
                'heating.boiler.sensors.temperature.main.status' => 'status',<br>
                'heating.boiler.sensors.temperature.main.value' => 'haupt_temperatur'}<br>
            Mapping will be preferred over old mapping.
        </li>
        <a id="vitoconnect-attr-vitoconnect_translations"></a>
        <li><i>vitoconnect_translations</i>:<br>
            Define your own translation; it will translate every word part by part. The format has to be:<br>
            translation<br>
            {  'device' => 'gerät',<br>
                'messages' => 'nachrichten',<br>
                'errors' => 'fehler'}<br>
            Translation will be preferred over mapping and old mapping.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mapping_roger"></a>
        <li><i>vitoconnect_mapping_roger</i>:<br>
            Use the mapping from Roger from 8. November (https://forum.fhem.de/index.php?msg=1292441) instead of the SVN mapping.
        </li>
        <a id="vitoconnect-attr-vitoconnect_serial"></a>
        <li><i>vitoconnect_serial</i>:<br>
            Define the serial of the gateway to be used.<br>
            If there is only one gateway, you do not have to care about it.<br>
            If you have more than one gateway, by default all readings of all gateways are collected, and every reading is appended by the gateway serial.<br>
            For example, if you have two gateways, this will be two calls to the API.<br>
            The Viessmann API has a limit of 1400 calls a day.<br>
            It makes sense in a hybrid setup to define two devices for every gateway.<br>
            With this, you can get the data of the heat pump more frequently than the data of the burner.<br>
            You can get the serials by setting vitoconnect_gw_readings = 1 and checking the corresponding readings gw and number_of_gateways.<br>
            If you want to use the setters, please set a vitoconnect_serial.<br>
            If not, you will get an error message in Aktion_Status to do so.
        </li>
        <a id="vitoconnect-attr-vitoconnect_timeout"></a>
        <li><i>vitoconnect_timeout</i>:<br>
            Sets a timeout for the API call.
        </li>
        <a id="vitoconnect-attr-vitoconnect_device"></a>
        <li><i>vitoconnect_device</i>:<br>
            You can define the device 0 (standard) or 1. I cannot test this because I have only one device.
        </li>
    </ul>
</ul>

=end html
=begin html_DE

<a id="vitoconnect"></a>
<h3>vitoconnect</h3>
<ul>
    <i>vitoconnect</i> implementiert ein Gerät für die Viessmann API
    <a href="https://www.viessmann.de/de/viessmann-apps/vitoconnect.html">Vitoconnect100</a>
    basierend auf der Untersuchung von
    <a href="https://github.com/thetrueavatar/Viessmann-Api">thetrueavatar</a><br>
    
    Sie benötigen Benutzer und Passwort des ViCare App-Kontos.<br>
     
    Für Details siehe: <a href="https://wiki.fhem.de/wiki/Vitoconnect">FHEM Wiki (deutsch)</a><br><br>
     
    vitoconnect benötigt die folgenden Bibliotheken:
    <ul>
    <li>Path::Tiny</li>
    <li>JSON</li>
    <li>JSON:XS</li>
    <li>DateTime</li>
    </ul>   
         
    Verwenden Sie <code>sudo apt install libtypes-path-tiny-perl libjson-perl libdatetime-perl</code> oder 
    installieren Sie die Bibliotheken über cpan. 
    Andernfalls erhalten Sie eine Fehlermeldung "cannot load module vitoconnect".
     
    <br><br>
    <a id="vitoconnect-define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; vitoconnect &lt;user&gt; &lt;password&gt; &lt;interval&gt;</code><br>
        Es ist eine gute Idee, hier ein falsches Passwort zu verwenden und das richtige später zu setzen, da es
        in der Detailansicht des Geräts lesbar ist.
        <br><br>
        Beispiel:<br>
        <code>define vitoconnect vitoconnect user@mail.xx fakePassword 60</code><br>
        <code>set vitoconnect password correctPassword 60</code>
        <br><br>
                
    </ul>
    <br>
    
    <a id="vitoconnect-set"></a>
    <b>Set</b><br>
    <ul>
        <a id="vitoconnect-set-update"></a>
        <li><code>update</code><br>
            Lese sofort die aktuellen Werte aus</li>
        <a id="vitoconnect-set-clearReadings"></a>
        <li><code>clearReadings</code><br>
            Lösche sofort alle Werte</li> 
        <a id="vitoconnect-set-password"></a>
        <li><code>password passwd</code><br>
            Speichere das Passwort im Schlüsselbund</li>
        <a id="vitoconnect-set-logResponseOnce"></a>
        <li><code>logResponseOnce</code><br>
            Speichert die JSON-Antwort des Viessmann-Servers in entities.json,
            gw.json, actions.json im FHEM-Log-Verzeichnis.
            Wenn Sie mehr als ein Gateway haben, wird die Gateway-Seriennummer an die Dateien angehängt.</li>
        <a id="vitoconnect-set-apiKey"></a>
        <li><code>apiKey</code><br>
            Da Viessmann auf die V2 API umgestellt hat, müssen Sie einen API-Schlüssel unter https://developer.viessmann.com/ erstellen.
            Erstellen Sie ein Konto, fügen Sie einen neuen Client hinzu (Google reCAPTCHA deaktiviert, Redirect URI = http://localhost:4200/).
            Kopieren Sie die Client-ID hier als apiKey</li>
        <br>
        <code>Neue Setter werden verwendet, wenn vitoconnect_raw_readings = 1, wenn Sie mehr als eine Gateway-Seriennummer haben, müssen Sie diese definieren, um die Setter zu verwenden<code>
        <code>Alte statische Mapping-Setter, werden nur verwendet, wenn attr vitoconnect_raw_readings = 0<code>
        <li><code>HKn_Heizkurve_Niveau shift</code><br>
            Setzt die Verschiebung der Heizkurve für HKn</li>
        <li><code>HKn_Heizkurve_Steigung slope</code><br>
            Setzt die Steigung der Heizkurve für HKn</li>
      
        <li><code>HKn_Urlaub_Start_Zeit start</code><br>
            Setzt die Urlaubsstartzeit für HKn<br>
            Start muss so aussehen: 2019-02-02</li>
        <li><code>HKn_Urlaub_Ende_Zeit end</code><br>
            Setzt die Urlaubsendzeit für HKn<br>
            Ende muss so aussehen: 2019-02-16</li>
        <li><code>HKn_Urlaub_stop</code> <br>
            Entfernt die Urlaubsstart- und Endzeit für HKn</li>
            
        <li><code>HKn_Zeitsteuerung_Heizung schedule</code><br>
            Setzt den Heizplan für HKn im JSON-Format <br>
            z.B. {"mon":[],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[],"sun":[]} ist komplett aus
            und {"mon":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "tue":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "wed":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "thu":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "fri":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "sat":[{"mode":"on","start":"00:00","end":"24:00","position":0}],
            "sun":[{"mode":"on","start":"00:00","end":"24:00","position":0}]} ist 24/7 an</li>

        <li><code>HKn_Betriebsart heating,standby</code> <br>
             Setzt HKn_Betriebsart auf heizen, standby</li>

        <li><code>WW_Betriebsart balanced,off</code> <br>
            Setzt WW_Betriebsart auf ausgeglichen, aus</li>
        
        <li><code>HKn_Soll_Temp_comfort_aktiv activate,deactivate</code> <br>
            Aktiviert/deaktiviert die Komforttemperatur für HKn</li>
        <li><code>HKn_Soll_Temp_comfort targetTemperature</code><br>
            Setzt die Komfortzieltemperatur für HKn</li>
        <li><code>HKn_Soll_Temp_eco_aktiv activate,deactivate </code><br>
            Aktiviert/deaktiviert die Ökotemperatur für HKn</li>
            
        <li><code>HKn_Soll_Temp_normal targetTemperature</code><br>
            Setzt die normale Zieltemperatur für HKn, wobei targetTemperature ein
            Integer zwischen 3 und 37 ist</li>
        <li><code>HKn_Soll_Temp_reduziert targetTemperature</code><br>
            Setzt die reduzierte Zieltemperatur für HKn, wobei targetTemperature ein
            Integer zwischen 3 und 37 ist</li>
        
        <li><code>HKn_Name name</code><br>
            Setzt den Namen des Kreislaufs für HKn</li>      
        
        <li><code>WW_einmaliges_Aufladen activate,deactivate</code><br>
            Aktiviert oder deaktiviert einmaliges Aufladen für Warmwasser</li>
        
        <li><code>WW_Zirkulationspumpe_Zeitplan schedule</code><br>
            Setzt den Zeitplan im JSON-Format für die Warmwasserzirkulationspumpe</li>
        <li><code>WW_Zeitplan schedule</code> <br>
            Setzt den Zeitplan im JSON-Format für Warmwasser</li>
            
        # <li><code>WW_Haupttemperatur targetTemperature</code><br>
        # targetTemperature ist ein Integer zwischen 10 und 60<br>
        # Setzt die Haupttemperatur des Warmwassers auf targetTemperature</li>
        <li><code>WW_Solltemperatur targetTemperature</code><br>
            targetTemperature ist ein Integer zwischen 10 und 60<br>
            Setzt die Warmwassertemperatur auf targetTemperature</li>    
        
        <li><code>Urlaub_Start_Zeit start</code><br>
            Setzt die Urlaubsstartzeit <br>
            Start muss so aussehen: 2019-02-02</li>
        <li><code>Urlaub_Ende_Zeit end</code><br>
            Setzt die Urlaubsendzeit <br>
            Ende muss so aussehen: 2019-02-16</li>
        <li><code>Urlaub_stop</code> <br>
            Entfernt die Urlaubsstart- und Endzeit</li>
    </ul>
</ul>
<br>
    <a name="vitoconnectget"></a>
      <b>Get</b><br>
        <ul>
            nichts zum Abrufen hier
        </ul>
<br>

<a name="vitoconnect-attr"></a>
<b>Attributes</b>
<ul>
    <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
    <br><br>
    Siehe <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> für weitere Informationen über den attr-Befehl.
    <br><br>
    Attribute:
    <ul>
        <a id="vitoconnect-attr-disable"></a>
        <li><i>disable</i>:<br>         
            Stoppt die Kommunikation mit dem Viessmann-Server.
        </li>
        <a id="vitoconnect-attr-verbose"></a>
        <li><i>verbose</i>:<br>         
            Setzt das Verbositätslevel.
        </li>
        <a id="vitoconnect-attr-vitoconnect_raw_readings"></a>
        <li><i>vitoconnect_raw_readings</i>:<br>         
            Erstellt Readings mit einfachen JSON-Namen wie 'heating.circuits.0.heating.curve.slope' anstelle von deutschen Bezeichnern (altes Mappping), mapping Attribute, oder translation Attribute.<br>
            Werden raw Readings verwenbdet werden die setter dynamisch erstellt, die den raw Readings entsprechen (neu).<br>
            Ich empfehle diese Einstellung, da Sie alles so dynamisch wie möglich von der API erhalten.<br>
            Sie können stateFormat oder userReadings verwenden, um Ihre wichtigen Readings mit einem lesbaren Namen anzuzeigen.<br>
            Wenn vitoconnect_raw_readings gesetzt ist, wird kein Mapping verwendet.
        </li>
        <a id="vitoconnect-attr-vitoconnect_gw_readings"></a>
        <li><i>vitoconnect_gw_readings</i>:<br>         
            Erstellt ein Reading vom Gateway, einschließlich Informationen, wenn Sie mehr als ein Gateway haben.
        </li>
        <a id="vitoconnect-attr-vitoconnect_actions_active"></a>
        <li><i>vitoconnect_actions_active</i>:<br>
            Erstellt Readings für Aktionen, z.B. 'heating.circuits.0.heating.curve.setCurve.setURI'.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mappings"></a>
        <li><i>vitoconnect_mappings</i>:<br>
            Definieren Sie Ihre eigene Zuordnung von Schlüssel-Wert-Paaren anstelle der eingebauten. Das Format muss sein:<br>
            mapping<br>
            {  'device.serial.value' => 'device_serial',<br>
                'heating.boiler.sensors.temperature.main.status' => 'status',<br>
                'heating.boiler.sensors.temperature.main.value' => 'haupt_temperatur'}<br>
            Die Zuordnung wird gegenüber der alten Zuordnung bevorzugt.
        </li>
        <a id="vitoconnect-attr-vitoconnect_translations"></a>
        <li><i>vitoconnect_translations</i>:<br>
            Definieren Sie Ihre eigene Übersetzung; sie wird jedes Wort Teil für Teil übersetzen. Das Format muss sein:<br>
            translation<br>
            {  'device' => 'gerät',<br>
                'messages' => 'nachrichten',<br>
                'errors' => 'fehler'}<br>
            Die Übersetzung wird gegenüber der Zuordnung und der alten Zuordnung bevorzugt.
        </li>
        <a id="vitoconnect-attr-vitoconnect_mapping_roger"></a>
        <li><i>vitoconnect_mapping_roger</i>:<br>
            Verwenden Sie das Mapping von Roger vom 8. November (https://forum.fhem.de/index.php?msg=1292441) anstelle der SVN-Zuordnung.
        </li>
        <a id="vitoconnect-attr-vitoconnect_serial"></a>
        <li><i>vitoconnect_serial</i>:<br>
            Definieren Sie die Seriennummer des zu verwendenden Gateways.<br>
            Wenn es nur ein Gateway gibt, müssen Sie sich nicht darum kümmern.<br>
            Wenn Sie mehr als ein Gateway haben, werden standardmäßig alle Readings aller Gateways gesammelt, und jedes Reading wird mit der Gateway-Seriennummer versehen.<br>
            Wenn Sie beispielsweise zwei Gateways haben, werden zwei API-Aufrufe durchgeführt.<br>
            Die Viessmann-API hat ein Limit von 1400 Aufrufen pro Tag.<br>
            Es macht in einem hybriden Setup Sinn, zwei Geräte für jedes Gateway zu definieren.<br>
            Damit können Sie die Daten der Wärmepumpe häufiger als die Daten des Brenners abrufen.<br>
            Sie können die Seriennummern erhalten, indem Sie vitoconnect_gw_readings = 1 setzen und die entsprechenden Readings gw und number_of_gateways überprüfen.<br>            
            Wenn Sie die Setter verwenden möchten, setzen Sie bitte eine vitoconnect_serial.<br>
            Andernfalls erhalten Sie eine Fehlermeldung in Aktion_Status, dies zu tun.
        </li>
        <a id="vitoconnect-attr-vitoconnect_timeout"></a>
        <li><i>vitoconnect_timeout</i>:<br>
            Setzt ein Timeout für den API-Aufruf.
        </li>
        <a id="vitoconnect-attr-vitoconnect_device"></a>
        <li><i>vitoconnect_device</i>:<br>
            Sie können das Gerät 0 (Standard) oder 1 definieren. Ich kann dies nicht testen, da ich nur ein Gerät habe.
        </li>
    </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 98_vitoconnect.pm
{
  "abstract": "Using the viessmann API to read and set data",
  "x_lang": {
    "de": {
      "abstract": "Benutzt die Viessmann API zum lesen und setzen von daten"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "heating",
    "burner",
    "heatpump",
    "gas",
    "oil"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Stefan Runge <stefanru@gmx.de>"
  ],
  "x_fhem_maintainer": [
    "Stefanru"
  ],
  "x_fhem_maintainer_github": [
    "stefanru1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "POSIX": 0,
        "GPUtils": 0,
        "Encode": 0,
        "Blocking": 0,
        "Color": 0,
        "utf8": 0,
        "HttpUtils": 0,
        "JSON": 4.020,
        "FHEM::SynoModules::SMUtils": 1.0270,
        "Time::HiRes": 0,
        "MIME::Base64": 0,
        "Math::Trig": 0,
        "List::Util": 0,
        "Storable": 0
      },
      "recommends": {
        "FHEM::Meta": 0,
        "FHEM::Utility::CTZ": 1.00,
        "DateTime": 0,
        "DateTime::Format::Strptime": 0,
        "AI::DecisionTree": 0,
        "Data::Dumper": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/Vitoconnect",
      "title": "vitoconnect"
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/98_vitoconnect.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/98_vitoconnect.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut
