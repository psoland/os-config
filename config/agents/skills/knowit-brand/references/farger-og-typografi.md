# Farger og typografi – fullstendig referanse

## Fullstendige fargedefinisjoner

### Primary palette
| Navn | HEX | RGB | CMYK | Pantone |
|---|---|---|---|---|
| Knowit Black | #0B0B26 | 11/11/38 | 71/71/0/85 | 5255 C |
| Purple | #CFCEFF | 207/206/255 | 19/19/0/0 | 263 C |
| Knowit White | #FEFBE6 | 254/251/230 | 0/1/9/0 | 9064 C |
| Blue | #372BC5 | 55/43/197 | 91/80/0/0 | Blue 072 C |

### Extended palette
| Navn | HEX | RGB | CMYK | Pantone | NCS |
|---|---|---|---|---|---|
| Green | #55D440 | 85/212/64 | 63/0/96/0 | 802 C | S 0570-G20Y |
| Pink | #FFD6B8 | 255/214/184 | 0/16/28/0 | 475 C | S 1015-Y50R |
| Light Pink | #FFEBDD | 255/235/221 | 0/8/13/0 | 9220 C | S 0804-Y50R |
| Light Purple | #F7F6FF | 247/246/255 | 2/3/0/2 | 9023 C | S 0510-R60B |

Ren svart #000000 (Process black) og hvit #FFFFFF tillatt KUN i spesialtilfeller som case-bakgrunner.

## Kontrastmatrise for tekst (WCAG AA ved 16px digital, min 8pt print)

### ✅ TILLATTE kombinasjoner (tekst på bakgrunn)
Primær:
- Knowit Black på Knowit White
- Knowit White på Knowit Black
- Blue på Knowit White
- Knowit Black på Purple
- Knowit White på Blue

Sekundær:
- Pink på Blue
- Purple på Blue
- Blue på Purple
- Blue på Pink / Light Pink / Light Purple
- Knowit Black på Pink / Light Pink / Light Purple

### ❌ FORBUDTE kombinasjoner (feiler tilgjengelighet – bruk aldri)
- Knowit White på Green
- Blue på Green
- Knowit Black på Blue
- Green på Knowit White
- Pink på Knowit White
- Blue på Knowit Black
- Purple på Knowit White
- Purple på Pink

Bruk ALDRI kombinasjoner som ikke står i tillatt-listen.

## Highlight-farger (utheving av nøkkelord)

Regler: maks ETT uthevet ord eller én setning per flate; aldri to highlight-farger i samme komposisjon; highlight-fargen skal matche eventuelle stjerne-bullets på samme flate.

Tillatte highlight/bakgrunn-par:
- Blue-highlight på: Knowit White, Purple, Pink, Light Pink, Light Purple
- Green-highlight på: Knowit Black, Blue
- Purple-highlight på: Knowit Black, Blue
- Pink-highlight på: Knowit Black, Blue

## Typografi

### Font
- **Bagoss** (Displaay Type Foundry, 2022): økt strøkkontrast, liten enkeltsidet serif. Embedded KUN i Knowits offisielle .pptx- og Word-maler; lisens forbeholdt designprofesjonelle (Brand & Communications-teamet).
- **Arial Regular** er offisiell fallback ALLE andre steder – "the closest web safe alternative". Aldri Helvetica Neue, Inter eller andre erstatninger som primærvalg.
- CSS-stack: `font-family: Bagoss, Arial, Helvetica, sans-serif;`

### Vekt og hierarki
- KUN Regular (400). Aldri bold, semibold, light eller italic for hierarki.
- Hierarki = STORE størrelseskontraster. Gylne snitt: multipliser/divider med 1,618 og rund til nærmeste tall delelig på 8. Hopp gjerne over trinn for dynamikk.
- Referanseskala (fra guiden, 1920px-flate – skaler proporsjonalt):
  - Display/Headline: 164px, line-height 148px (≈0,9)
  - Standfirst/ingress: 64px / 72px (≈1,1)
  - Body: 24px / 36px (1,5)
  - Maks tekstbredde: ca. 724px på 1920-flate (≈ 38 % av bredden, eller ~65 tegn)
- Praktisk webskala (avledet, delelig på 8): 96 → 56 → 40 → 24 → 16px
- Komposisjon: ren venstrejustert tekst. Stor headline øverst, ingress under, brødtekst i smalere kolonne.

### Print
- Minimum brødtekst: 8 pt
- Minimum logobredde: 20 mm
