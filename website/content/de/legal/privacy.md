---
title: Datenschutzerklärung
date: 2026-03-16
translationKey: privacy
---

## Kurzfassung

Dockyard sammelt keine personenbezogenen Daten. Dein Code bleibt auf deinem Rechner. Keine Analysen, keine Telemetrie, keine Absturzberichte.

## Die Anwendung

Dockyard ist eine native macOS-Anwendung, die vollständig auf deinem Computer läuft. Sie:

- Sendet weder deinen Code, Projektinhalte noch Terminal-Ausgaben an einen Server
- Erfordert kein Konto oder Registrierung
- Verfolgt weder dein Verhalten noch deine Aktivitäten
- Greift nicht auf Dateien außerhalb deiner Projektverzeichnisse zu

Alle Projektdaten (Namen, Verzeichnisse, Workstream-Konfigurationen) werden lokal auf deinem Computer in `~/.config/dockyard/` gespeichert.

## Drittanbieterdienste

Dockyard integriert sich mit Tools, die du selbst installierst und konfigurierst:

- **Claude Code** (Anthropic) — bei Nutzung des Coding-Agents werden dein Code und Gesprächskontext an Anthropics API gesendet. Dies ist eine direkte Verbindung zwischen deinem Rechner und Anthropic, die [Anthropics Datenschutzerklärung](https://www.anthropic.com/privacy) unterliegt. Dockyard fängt diese Daten weder ab, speichert sie noch leitet sie weiter.
- **GitHub CLI** — unterliegt [GitHubs Datenschutzerklärung](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- **Ghostty** — die integrierte Terminal-Engine läuft lokal ohne Netzwerkaktivität

Dockyard agiert nicht als Vermittler für diese Dienste. Deine API-Schlüssel und Zugangsdaten werden von jedem Tool direkt verwaltet.

## Diese Website

Die Dockyard-Website (dockyard.barnola.net) verwendet keinerlei Analyse-Tools, Cookies, Tracking-Skripte oder Werbenetzwerke.

Keine weiteren Tracking-Skripte, Werbenetzwerke oder Drittanbieter-Analysen werden auf dieser Website verwendet.

## Kontakt

Für datenschutzbezogene Fragen kontaktiere [barnolacesc](https://github.com/barnolacesc).
