---
title: Política de privacitat
date: 2026-03-16
translationKey: privacy
---

## La versió curta

Dockyard no recull dades personals. El teu codi es queda al teu ordinador. Sense analítiques, sense telemetria, sense informes d'error.

## L'aplicació

Dockyard és una aplicació nativa de macOS que s'executa completament al teu ordinador. No:

- Envia el teu codi, contingut de projectes ni sortida de terminal a cap servidor
- Requereix cap compte ni registre
- Rastreja el teu comportament ni activitat
- Accedeix a fitxers fora dels teus directoris de projecte

Totes les dades de projecte (noms, directoris, configuracions de fluxos de treball) s'emmagatzemen localment al teu ordinador a `~/.config/dockyard/`.

## Serveis de tercers

Dockyard s'integra amb eines que tu instal·les i configures:

- **Claude Code** (Anthropic) - quan utilitzes l'agent de codi, el teu codi i el context de la conversa s'envien a l'API d'Anthropic. Es tracta d'una connexió directa entre el teu ordinador i Anthropic, subjecta a la [política de privacitat d'Anthropic](https://www.anthropic.com/privacy). Dockyard no intercepta, emmagatzema ni retransmet aquestes dades.
- **Codex** (OpenAI) - quan utilitzes Codex a la pestanya de l'agent de codi, el teu codi i el context de la conversa s'envien a l'API d'OpenAI. Es tracta d'una connexió directa entre el teu ordinador i OpenAI, subjecta a la [política de privacitat d'OpenAI](https://openai.com/policies/privacy-policy/). Dockyard no intercepta, emmagatzema ni retransmet aquestes dades.
- **GitHub CLI** - subjecte a la [política de privacitat de GitHub](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement)
- **Ghostty** - el motor de terminal integrat s'executa localment sense activitat de xarxa

Dockyard no actua com a intermediari per a aquests serveis. Les teves claus d'API i credencials les gestiona cada eina directament.

## Aquest lloc web

El lloc web de Dockyard (dockyard.barnola.net) no utilitza analítiques, galetes, scripts de seguiment ni xarxes publicitàries de cap tipus.

No s'utilitzen altres scripts de seguiment, xarxes publicitàries ni analítiques de tercers en aquest lloc web.

## Contacte

Per a preguntes relacionades amb la privacitat, contacta amb [barnolacesc](https://github.com/barnolacesc).
