# HTML-prototyper og web – referanse

## Oppsett

1. Les `references/farger-og-typografi.md` (kontrastmatrisen er obligatorisk kunnskap).
2. Kopier innholdet i `assets/knowit-tokens.css` inn i prototypen (inline `<style>` for én fil, eller som egen fil).
3. Kopier nødvendige assets (logo-SVG, stjerne-SVG-er, gradient-JPG-er) til prototypens mappe, eller inline SVG-ene direkte i HTML.
4. Sett `class="knowit"` på body og bruk `surface-*`-klassene.

## Standard sidestruktur (Knowit-mønster, observert i guiden)

```html
<body class="knowit surface-white">
  <header>  <!-- logo oppe til venstre, ev. enkel meny til høyre -->
    <img class="logo" src="Logo_positive.svg" alt="Knowit" width="96">
  </header>

  <main>
    <h1 class="display">Kort, slagkraftig overskrift</h1>   <!-- stor Bagoss/Arial -->
    <p class="lead">Ingress i venstrejustert, smal kolonne.</p>

    <div class="window window--gradient">                    <!-- gradient som "hero-bilde" -->
      <img src="gradients/primary-aurora.jpg" alt="">
    </div>

    <p>Brødtekst, maks ~65 tegn bredde…</p>
  </main>

  <footer>  <!-- logo nede til venstre -->
    <img class="logo logo--footer" src="Logo_positive.svg" alt="Knowit">
  </footer>
</body>
```

Mørk variant: `surface-dark` + `Logo_negative.svg`.

## Komponentmønstre

### Kort (fra design principles-slidene)
Kremhvite kort med tynn outline og stjerne foran tittelen:
```html
<div class="window window--outline surface-white" style="padding:24px">
  <p class="small"><img src="stars/star-green.svg" width="12" alt=""> Simple</p>
  <p class="lead">Just like the Nordic skies, our identity doesn't shout…</p>
</div>
```

### Stjerneliste
```html
<ul class="stars">
  <li>Choose courage</li>
  <li>Trust in transparency</li>
</ul>
```
Stjernefargen følger flatens highlight-farge (Blue på lyse flater, Green/White på mørke).

### Diagrammer (Chart.js/recharts/d3)
- Container: `surface-dark`, radius 24px, padding 24–32px
- Seriefarger i rekkefølge: `--chart-1` til `--chart-6`
- Grid: `--chart-grid`, tynne stiplete linjer; akseetiketter små i Knowit White
- Verdietiketter som pills med seriens farge og mørk tekst

### Knapper/lenker (avledet av "View assets"-knappene i guiden)
Pillformede outline-knapper: `border:1px solid currentColor; border-radius:999px; padding:10px 20px;` med tekst + pil →. (Pilleform er forbudt for VINDUER, men knappene i guiden er pillformede – det er ok for interaktive elementer.)

### Buet tekst (playful)
```html
<svg viewBox="0 0 600 220">
  <path id="arc" d="M 40 170 Q 300 40 560 170" fill="none"/>
  <text font-size="48" fill="var(--knowit-black)">
    <textPath href="#arc" startOffset="50%" text-anchor="middle">Let's challenge it</textPath>
  </text>
</svg>
```
Én myk kurve, normal tracking.

## Husk
- ALDRI `#000`/`#fff` – alltid tokens
- ALDRI font-weight over 400
- ALDRI tekst oppå gradient-vinduer eller foto
- Gradient kun som bilde fra assets, aldri `linear-gradient()` i CSS
- Sjekk hver tekst/bakgrunn-kombinasjon mot kontrastmatrisen
- Responsivt: skaler typografien proporsjonalt, behold store kontraster mellom nivåene
