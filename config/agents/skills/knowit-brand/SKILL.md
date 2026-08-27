---
name: knowit-brand
description: Knowits visuelle identitet "Nordic Skies" – farger, logo, typografi, grafiske elementer, gradienter og bildestil. Bruk ALLTID denne skillen når noe skal lages med Knowit-profil eller for Knowit, slik som HTML-prototyper, nettsider, presentasjoner/slides, Word-/tekstdokumenter, PDF-er, one-pagers, diagrammer, grafer, sosiale medier-bilder, tilbud, rapporter eller maler. Trigger også på "i vår profil", "Knowit-farger", "brand guide", "visuell identitet", "Nordic Skies", eller når brukeren ber om noe som skal "se Knowit ut" – selv om ordet brand ikke nevnes.
---

# Knowit Brand – Nordic Skies

Knowits visuelle identitet. Konseptet er **Nordic Skies**: nordisk lys og himmel – flekkete sollys, glødende solnedganger, nordlys, endeløse sommernetter. Lys er et fyrtårn for kunnskap og håp.

Fire designprinsipper styrer alle valg:
1. **Simple** – identiteten hvisker, den roper ikke, men med dyp effekt
2. **Unified** – alt henger sammen i ett helhetlig uttrykk
3. **Sustainable** – støtter posisjonen "Makers of a Sustainable Future"
4. **Humane** – i stadig endring, men konsistent og pålitelig

## Steg 0: Velg volum (gjør alltid dette først)

Identiteten skaleres etter kontekst på en akse:

- **Elegant** (formelt: kundetilbud, rapporter, styredokumenter): mørkere, enklere, bolder. Mer Knowit Black, mer typografi og case-fokus, færre farger. "Show, not tell."
- **Playful** (uformelt: rekruttering, employer branding, SoMe, events): flere farger, gradienter, buet tekst, stjerner, høyere volum.

De fleste leveranser ligger midt på: kremhvit base med 1–2 aksentfarger. Er konteksten uklar, spør brukeren eller velg midten.

## Kjernefarger (lær disse)

| Token | HEX | Bruk |
|---|---|---|
| Knowit Black | `#0B0B26` | Tekst, mørke flater. ALDRI ren #000000 |
| Knowit White | `#FEFBE6` | Standard bakgrunn. ALDRI ren #FFFFFF |
| Purple | `#CFCEFF` | Primær aksentflate |
| Blue | `#372BC5` | Primær aksent, highlights, lenker |
| Green | `#55D440` | Aksent (extended) |
| Pink | `#FFD6B8` | Varm flate (extended) |
| Light Pink | `#FFEBDD` | Rolig flate (extended) |
| Light Purple | `#F7F6FF` | Rolig flate (extended) |

Hierarki: Knowit White og Knowit Black skal DOMINERE; aksentfargene er støtte i mindre doser. Ren svart/hvit kun i spesialtilfeller (f.eks. case-bakgrunner).

## Typografi (kortversjon)

- Brand-font: **Bagoss** (kun i offisielle ppt-/Word-maler). **Arial er offisiell fallback** alle andre steder – aldri en annen font.
- CSS: `font-family: Bagoss, Arial, Helvetica, sans-serif;`
- **KUN Regular-vekt. Aldri bold/light.** Hierarki skapes med STORE størrelseskontraster (gylne snitt: ×/÷ 1,618, rund til delelig på 8). Store overskrifter har line-height ≈ 0,9; brødtekst ≈ 1,5.
- Venstrejustert tekst er primærkomposisjonen.
- Highlight: maks ETT ord/setning i kontrastfarge per flate; aldri bland highlight-farger.
- Tekst står ALLTID på flat farge – aldri oppå gradient eller bilde.

## Logo

- Ordmerket "knowit" (lowercase slab serif) – ALDRI endres, strekkes eller omfarges.
- `assets/Logo_positive.svg` (#0B0B26) på lyse flater; `assets/Logo_negative.svg` (#FEFBE6) på mørke. Format 477×109.
- Friareal: "o"-ens bredde på alle sider. Min. bredde 72 px digitalt / 20 mm print.
- Plassering: nede til venstre (standard) eller oppe til høyre/venstre. Lav kontrast forbudt (f.eks. svart logo på Blue).

## Grafiske signaturelementer

- **Vinduer**: avrundede rektangler (radius 24px, skaler proporsjonalt; aldri strekk hjørner) som rammer bilder, gradienter og tekst.
- **Gradienter**: bruk KUN filene i `assets/gradients/` (aldri CSS-/egenlagde gradienter). Primary: aurora, afterglow, evening.
- **Knowit-stjernen** ✱: kun som bullets (størrelse = tekst ÷ 1,5) eller som liten "pin". Aldri begge i samme layout. SVG-er i `assets/stars/`.
- **Buet tekst**: identitetsmarkør i playful-enden – én myk bue, aldri flere bølger eller flere rader.

## Tone of voice (for tekstinnhold)

Vennlig, hverdagslig og tilgjengelig ("The Nordic way"). Ingen corporate-klisjeer. Enkelt språk uten unødvendig sjargong. Leken selvtillit: "We are it", "Hey, we get it".

## Referanser – les etter behov

| Fil | Når |
|---|---|
| `references/farger-og-typografi.md` | ALLTID før design: full kontrastmatrise (tillatte/forbudte kombinasjoner), highlight-regler, typografiskala |
| `references/grafikk-og-elementer.md` | Ved bruk av vinduer/kollasjer, gradienter, stjerner, buet tekst, ikoner, diagrampalett |
| `references/html-prototyper.md` | HTML/web/React: koble inn `assets/knowit-tokens.css`, komponentmønstre, eksempler |
| `references/presentasjoner.md` | PowerPoint/slides: slide-oppsett, logoplassering, volumvalg |
| `references/dokumenter.md` | Word/PDF/tekstdokumenter |
| `references/bildestil.md` | Valg/generering av foto: naturlig lys-kriteriene |

## Sjekkliste før levering

- [ ] Knowit White/Black brukt i stedet for ren hvit/svart
- [ ] Kun Regular fontvekt; hierarki via størrelse
- [ ] Alle tekst/bakgrunn-kombinasjoner finnes i kontrastmatrisen
- [ ] Logo: riktig variant, friareal, min-størrelse, aldri på urolig bakgrunn
- [ ] Maks ett highlight-ord per flate; ett storskala-symbol per flate
- [ ] Gradienter fra assets (ikke egenlagde), aldri tekst oppå
- [ ] Volumnivå passer konteksten (elegant ↔ playful)
