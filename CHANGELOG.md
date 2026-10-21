# Änderungen

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
