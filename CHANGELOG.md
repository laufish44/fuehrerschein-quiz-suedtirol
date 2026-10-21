# Änderungen

## 1.5.1

- **Verbesserung vorschlagen** (unter Mehr): kurzen Titel und Beschreibung eingeben – die App öffnet einen vorausgefüllten Vorschlag auf GitHub

## 1.5.0

- **Lernplan:** Aus dem Prüfungstermin rechnet die App aus, wie viele Fragen du pro Tag schaffen solltest (die letzten Tage bleiben für Prüfungssimulationen frei) – auf Wunsch direkt als Tagesziel
- **Prüfungsreif-Ampel:** Jedes Kapitel ist grün, gelb oder rot; mit einem Knopf übst du gezielt die roten und gelben
- **Gegensatzpaare:** 571 Paare fast gleich klingender Aussagen mit gegenteiliger Lösung – beide nebeneinander beantworten
- **Bilder-Quiz:** Verkehrszeichen sehen und aus vier Aussagen die passende wählen
- **Prüfung mit Freunden:** Ein sechsstelliger Code ergibt bei allen genau dieselben 30 Prüfungsfragen
- **Erfolge und Abzeichen:** 19 Abzeichen (Serien, Prüfungen, Kapitel grün, fehlerfrei …), neue werden auf der Startseite angezeigt
- **Widget für den Android-Startbildschirm:** Tagesziel, Lernserie, Bestehenschance und Tage bis zur Prüfung
- **Fehler melden:** Fahne an jeder Frage öffnet einen vorausgefüllten Fehlerbericht auf GitHub

## 1.4.0

- Offline-Erklärungen für alle 7.020 Aussagen: neu sind Zusatztafeln, Geschwindigkeit, Abstand, Fahrbahnposition und Abbiegen, Vorfahrt-Beispiele, Überholen, Halten und Parken, Autobahn, Ladung und Anhänger, Licht und Kontrollleuchten, Gurte und Helm, Führerschein und Punkte, Unfälle und Erste Hilfe, Alkohol, Haftung und Versicherung, Umwelt sowie Fahrzeugtechnik. Die Erklärung erscheint nach jeder Antwort – auch wenn sie richtig war (nicht während der Prüfungssimulation)
- KI-Erklärung mit Gemini viel schneller: Standard ist jetzt das schnelle Modell gemini-flash-lite-latest (1–2 Sekunden statt teils über 2 Minuten beim großen Modell). Hängt eine Anfrage, fragt die App nach 6 Sekunden parallel ein zweites Modell; ist eines überlastet, sofort das andere
- Gemini bekommt die Offline-Erklärung als Grundlage mit und soll keine Details oder Artikelnummern erfinden

## 1.3.1

- Sync: Änderungen, die während eines laufenden Abgleichs entstehen (z. B. ein Quiz direkt nach dem Start), werden sofort danach hochgeladen statt erst beim nächsten Mal
- Sync unter Windows: Beim Schließen des Fensters und vor einem Update wird der Lernstand noch ins Google Drive hochgeladen
- KI-Chat mit eigenem Gemini-Schlüssel: Bei Überlastung („high demand“), Minutenlimit oder Zeitüberschreitung versucht die App es automatisch erneut und weicht notfalls auf ein kleineres Gemini-Modell aus; während des Wartens steht da, was passiert
- Schnellere Gemini-Antworten (weniger „Nachdenken“), dadurch seltener Zeitüberschreitungen
- Verständliche Fehlermeldungen (ungültiger Schlüssel, Tageslimit, kein Internet, …) mit Knopf „Nochmal versuchen“ und einem Knopf, der die Frage stattdessen an den bevorzugten KI-Dienst (z. B. ChatGPT) schickt
- Schlüssel testen jetzt auch in den Einstellungen

## 1.3.0

- Anmeldung mit dem eigenen Google-Konto ist jetzt Voraussetzung: Der Lernstand wird in einem versteckten App-Ordner im eigenen Google Drive gesichert und beim Start zwischen Handy und PC abgeglichen. Der bisherige Lernstand auf dem Gerät bleibt erhalten und wird bei der ersten Anmeldung hochgeladen
- Die App sieht nur ihre eigene Sicherungsdatei, nicht den Rest des Drives; die Anmeldung bleibt nur auf dem eigenen Gerät
- Abmelden unter Einstellungen → Sync & Backup
- Offline-Erklärungen für Kapitel 1 (Straßen und Fahrzeuge) und 9 (Lichtzeichen und Handzeichen der Polizei) – damit sind 3.620 der 7.020 Aussagen erklärt
- Webseite mit Datenschutzerklärung: https://laufish44.github.io/fuehrerschein-quiz-suedtirol/

## 1.2.0

- Kapitel wie im Theoriebuch (24 Kapitel, gleiche Nummern und Namen) – die Prüfungssimulation folgt weiter dem Ministeriumsprogramm
- Neu: „Schwierige Fragen“ – deine persönlich schwierigen Fragen plus typische Fallen (Aussagen, die fast gleich klingen wie eine mit gegenteiliger Lösung); auf der Startseite, im Lernen-Tab, je Kapitel und im eigenen Quiz
- Neu: Einrichtung beim ersten Start mit Google-Drive-Anmeldung (sobald verfügbar) und optionalem Gemini-Schlüssel inkl. Test
- Liste „Fallen-Fragen“ unter Mehr

## 1.1.0

- Offline-Erklärungen für Kapitel 6 (Bodenmarkierungen), 7 (Ampeln und Polizei) und 8 (Hinweiszeichen)
- Damit sind jetzt 2.926 der 7.020 Aussagen erklärt

## 1.0.0

Erste Version.

- Alle 7.020 Prüfungsfragen A/B auf Deutsch und Italienisch, 25 Kapitel, 332 Bilder
- Lernen nach Kapitel und nach Bild, intelligentes Lernen mit Spaced Repetition, Fehlerordner
- Offizielle Prüfungssimulation (30 Fragen, 20 Minuten, max. 3 Fehler) und eigene Quiz
- Statistiken: Prüfungsreife, Kapitel, Verlauf, Prüfungen, Lernzeit, Serien
- Offline-Erklärungen für Kapitel 2–5 (Gefahren-, Verbots-, Gebots- und Vorfahrtszeichen) – weitere Kapitel folgen per Update
- KI-Erklärungen über ChatGPT/Claude/Perplexity oder eigenen Gemini-Schlüssel
- Vorlesen, Favoriten, Notizen, Suche, Verkehrszeichen-Lexikon, Lern-Erinnerung
- Export/Import des Lernstands, automatische Updates über GitHub
