# Grafiske elementer – fullstendig referanse

## 1. Vinduer ("Frames of light")

Avrundede rektangler som rammer inn bilder, gradienter og tekst. Representerer transparens og nordisk lys.

### Radius
- Referanse: 24px. Skaler proporsjonalt med elementstørrelse (lite kort 16px, stor flate 32–40px – hold deg til tall delelig på 8).
- Nøstede elementer: indre radius = ytre radius − margin (rund til nærmeste 8).
- ALDRI strekk hjørnene – formen kan forlenges fritt, hjørneradius er konstant.
- Unngå pilleform (for smal/avlang i forhold til radius).

### To kollasjetyper
**Cluttered** (playful – case-bilder, portretter):
- Bilder overlapper TYDELIG eller ikke i det hele tatt (min. 24px avstand; 16px på små flater)
- Topp- eller bunnjuster bildene mot hverandre – aldri sentrer
- Tydelig størrelsesforskjell gir "tilfeldig" preg; 2+ former kan dele samme bilde
- Aldri overlapp-på-overlapp, aldri "larve" (samme bilde repetert diagonalt)

**Structured** (gridbasert – bildecontainere blant andre elementer):
- Grid med min. 24/16/8px avstand etter flatestørrelse
- Bilder fyller ALLTID hele vinduet (object-fit: cover) – aldri strekk eller flislegg
- Topp- eller bunnjusterte rader; kvadrater ok
- Kan inneholde tekst og brukes mellom setninger (med måte)

## 2. Gradienter

Bruk KUN de offisielle filene i `assets/gradients/` – aldri CSS-gradienter eller egenkomponerte. Tenk på gradienten som BILDEINNHOLD som står alene i et vindu.

| Fil | Hierarki | Karakter |
|---|---|---|
| primary-aurora.jpg | Primary | Grønn → teal → blå (nordlys) – mest brand-bærende |
| primary-afterglow.jpg | Primary | Hvit → fersken → blå bølge |
| primary-evening.jpg | Primary | Hvit/fersken → blå → oransje |
| secondary-arctic-horizon.jpg | Secondary | Blålilla → hvit, rolig |
| secondary-cloudy.jpg | Secondary | Mint → lilla → teal → blå |
| secondary-evening-ray.jpg | Secondary | Blå → fersken → lys, rolig |
| secondary-midwinter-haze.jpg | Secondary | Mørkblå → lilla → fersken |
| secondary-morning-glow.jpg | Secondary | Fersken → grågrønn → hvit, rolig |
| secondary-solar-arc.jpg | Secondary | Hvit → fersken → rosa, rolig |
| secondary-summer-dusk.jpg | Secondary | Lilla → fersken → krem |
| secondary-twilight.jpg | Secondary | Mørkblå → fersken-stripe → blå |
| secondary-winter-dusk.jpg | Secondary | Lilla → blå → mint |

Regler:
- Velg primary først; secondary/rolige for dempede flater og mørke bakgrunner
- Gradient i avgrenset vindu, IKKE som fullflate bak innhold
- ALDRI tekst oppå gradient; ALDRI gradient i tekst; ALDRI gradient som border
- Ikke overbruk – én gradient per flate er nok

## 3. Knowit-stjernen ✱

SVG-er: `assets/stars/star-{black|blue|green|pink|purple}.svg` (90×90).
Kun to bruksområder:

**Som bullets:** størrelse = tekststørrelse ÷ 1,5 (36px tekst → 24px stjerne). Aldri samme størrelse som teksten. Farge følger highlight-fargen på flaten.

**Som pin:** liten markør (typisk øverst i et hjørne) som peker på/markerer en tekstbolk. Hold den LITEN – innholdet er nr. 1 i hierarkiet. Stjernen skal være et aktivt element, ikke dekorasjon (ellers ser den ut som et logosymbol).

Fargekombinasjoner (stjerne på bakgrunn):
- På Knowit White: Black eller Blue
- På Knowit Black: White, Green, Purple eller Pink
- På Blue: White, Green, Pink eller Purple
- På Purple/Light Purple/Pink/Light Pink: Black eller Blue

Don'ts: aldri pin OG bullets i samme layout; kun ETT storskala-symbol per flate (stjerne ELLER pil).

## 4. Buet tekst (arches)

Identitetsmarkør i playful-enden. Tekst langs én myk kurve (arched eller undulating).
- Én bue/bølge – aldri flere bølger
- Aldri del tekstbanen over flere rader
- Normal tracking – verken for tett eller for løs
- I HTML: bruk SVG `<textPath>` langs en enkel kvadratisk kurve

## 5. Diagrampalett (UI color kit)

Diagrammer settes ALLTID på mørk bakgrunn (Knowit Black) og avviker bevisst fra brand-paletten for tilgjengelighet.

Fargerekkefølge (maksimal kontrast mellom naboer – start øverst):
1. `#9796FF` UI Purple (kun diagram/UI)
2. `#FFD6B8` Pink
3. `#55D440` Green
4. `#FEFBE6` Knowit White
5. `#FCB27C` Orange (kun diagram/UI)
6. `#CFCEFF` Purple

Stil: tynne stiplete gridlinjer i dempet hvit, små akseetiketter i Knowit White, verdietiketter som "pills" fylt med samme farge som serien (mørk tekst), grønn som aksent for nøkkeltall.

## 6. Ikoner

Knowits offisielle ikonsett (tynn outline, Knowit Black) er embedded i PowerPoint-malene og er de ENESTE tillatte ikonene der. Kategorier: Basic, Accessibility, Tech, Business, Reactions, Achievements, Festive & seasonal, Sustainability.
For HTML-prototyper (utenfor malene): bruk et minimalistisk tynt outline-sett (f.eks. lucide, strokeWidth 1.25–1.5) i Knowit Black som nærmeste ekvivalent, sparsommelig.
