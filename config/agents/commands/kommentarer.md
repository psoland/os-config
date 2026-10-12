---
description: Bruk eksporterte dokumentkommentarer i Markdown-kildefilene
---

# Bruk dokumentkommentarer

Les eksporten av dokumentkommentarer fra `$ARGUMENTS`, eller
`.document-comments/export.md` når ingen sti er oppgitt.

For hver kommentar-ID i en toppnivåseksjon i eksporten:

1. Les den refererte Markdown-kildefilen, samt det eksporterte sitatet og konteksten.
2. Følg typen: `comment` ber om en endring eller avklaring; `delete` ber om å fjerne
   den valgte teksten; `looks_good` er positiv tilbakemelding og krever ingen endring.
   Eldre eksporter uten type er vanlige kommentarer. Gjør eventuelle endringer kun
   i det refererte kildedokumentet.
3. Ikke rediger `.document-comments/comments.json`, eksportfilen eller noen
   kommentarstatus.
4. Ikke gjett dersom et `ambiguous`- eller `orphaned`-anker ikke identifiserer en
   trygg redigering; rapporter blokkeringen i stedet.
5. Oppsummer endringen, bekreftelsen eller blokkeringen separat for hver kommentar-ID
   når du er ferdig. Eksportert betyr ikke sendt eller løst; bare brukeren løser kommentarer.

Seksjoner med refererte kommentarer er kun kontekst, og er ikke egne oppgaver
med mindre kommentaren også har en egen toppnivåseksjon.
