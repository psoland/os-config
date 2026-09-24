---
description: Bruk eksporterte dokumentkommentarer i Markdown-kildefilene
---

# Bruk dokumentkommentarer

Les eksporten av dokumentkommentarer fra `$ARGUMENTS`, eller
`.document-comments/export.md` når ingen sti er oppgitt.

For hver kommentar-ID i en toppnivåseksjon i eksporten:

1. Les den refererte Markdown-kildefilen, samt det eksporterte sitatet og konteksten.
2. Håndter kommentaren ved å redigere kun det refererte kildedokumentet.
3. Ikke rediger `.document-comments/comments.json`, eksportfilen eller noen
   kommentarstatus.
4. Ikke gjett dersom et `ambiguous`- eller `orphaned`-anker ikke identifiserer en
   trygg redigering; rapporter blokkeringen i stedet.
5. Oppsummer endringen eller blokkeringen separat for hver kommentar-ID når du er ferdig.

Seksjoner med refererte kommentarer er kun kontekst, og er ikke egne oppgaver
med mindre kommentaren også har en egen toppnivåseksjon.
