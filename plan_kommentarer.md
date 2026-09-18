# Implementeringsplan: varige dokumentkommentarer i LazyVim

Opprettet: 18. september 2026  
Status: Klar for implementering  
Første målplattform: Neovim 0.12.x på Linux og macOS  
Første dokumenttype: Markdown

## 1. Beslutning

Løsningen skal være en liten lokal Neovim-plugin med arbeidstittelen
`document-comments.nvim`. Den skal ligge i dotfiles-repositoriet og lastes av
LazyVim. Eksisterende annoteringsverktøy er ikke en del av beslutningen og skal
bare brukes som oppslagsverk dersom implementeringen møter et konkret problem.

Førsteversjonen skal løse denne arbeidsflyten:

1. Marker et vilkårlig tekstområde i en lagret Markdown-fil.
2. Skriv og lagre en kommentar i et eget redigeringsvindu.
3. Se området markert i dokumentet.
4. Lukk og start Neovim på nytt uten å miste kommentaren.
5. List, åpne, rediger og naviger mellom kommentarer.
6. Marker kommentarer som `open` eller `resolved`.
7. Finn igjen flyttet tekst når treffet er entydig, og varsle i stedet for å
   gjette når treffet er tvetydig eller borte.
8. Eksporter åpne kommentarer til en lesbar Markdown-fil som en agent kan
   behandle.
9. La brukeren kontrollere resultatet og selv markere kommentarene som løst.

Pluginen skal være eneste skriver til kommentarlageret. Agenten skal bare lese
eksporten og endre kildedokumentene.

## 2. Verifisert grunnlag

Følgende er kontrollert i det faktiske oppsettet før planen ble skrevet.

<!-- markdownlint-disable MD013 -->

| Område | Verifisert resultat | Konsekvens |
| --- | --- | --- |
| Neovim | Alle kontrollerte Home Manager-profiler evaluerer til Neovim `0.12.5`. Den aktive installasjonen er også `0.12.5`. | Pluginen kan målrettes mot Neovim 0.12 og trenger ikke kompatibilitetskode for eldre versjoner. |
| Distribusjon | `modules/home/programs/nvim.nix` kobler `config/nvim` inn som en skrivbar out-of-store-symlink. | En lokal plugin under `config/nvim` trenger ingen ny Nix-pakke. |
| LazyVim | LazyVim 8 lastes fra `config/nvim/lua/config/lazy.lua`, og lokale spesifikasjoner importeres fra `lua/plugins`. | Pluginen registreres med én lokal lazy.nvim-spesifikasjon. |
| Markdown | LazyVims Markdown-extra er aktivert. `render-markdown.nvim` og Markdown-preview er installert. | Visning må sameksistere med conceal og andre extmark-navnerom, men ingen ny Markdown-avhengighet trengs. |
| UI | Snacks og which-key er installert. `vim.ui.select` kan brukes som stabil abstraksjon og forbedres av eksisterende UI. | Førsteversjonen trenger ikke egen picker eller ny UI-avhengighet. |
| Keymaps | `<leader>a` og de planlagte underbindingene er ledige. `[a` og `]a` er allerede bundet til `:previous` og `:next`. | Bruk `<leader>a…`; ikke overstyr `[a` eller `]a`. |
| Filendringer | `autoread=true`, og LazyVim kjører `:checktime` ved blant annet `FocusGained`. | Pluginen må håndtere buffer-reload og kjøre reankring etter reload. |
| Visuelle områder | Neovim 0.12 anbefaler `getregionpos()` og `getregion()`; `vim.region()` er deprecated. Et lokalt forsøk bevarte korrekt flerlinjeområde med `æøå` og emoji. | Bruk de nye Vim-funksjonene og lagre bytekolonner, ikke skjermkolonner. |
| Extmarks | Et lokalt forsøk bekreftet at extmarks følger innsetting før området og håndterer UTF-8. `invalidate=true` gjør imidlertid en full teksterstatning ugyldig selv når ny tekst settes inn samtidig. | Bruk `invalidate=false`, start med venstretyngde og slutt med høyretyngde, og oppdag tomme områder eksplisitt. |
| JSON | Neovim 0.12 støtter `vim.json.encode(..., { indent = "  ", sort_keys = true })`. | Lageret kan være lesbart og deterministisk uten `jq` eller annen avhengighet. |
| Holdbar skriving | Et lokalt forsøk bekreftet `vim.uv.fs_open`, `fs_write`, `fs_fsync`, `fs_rename` og fsync av katalog på gjeldende Linux-system. | Lageret kan skrives via midlertidig fil og atomisk rename uten eksterne programmer. |
| Plattform | Flaken deler samme Neovim-modul og Neovim `0.12.5` mellom x86_64-linux, aarch64-linux og aarch64-darwin. | Bruk bare Neovim- og libuv-API-er; gjør en manuell macOS-smoketest før løsningen regnes som ferdig. |
| OpenCode | `config/agents/commands` kobles til `~/.config/opencode/commands`. OpenCode V2 støtter globale Markdown-kommandoer der. | En enkel agentkommando kan legges til uten plugin-, MCP- eller API-integrasjon. |
| Eksisterende OpenCode-plugin | `config/nvim/lua/plugins/opencode.lua` har `enabled = false`. | Dokumentkommentarene skal ikke avhenge av eller aktivere denne pluginen. |

<!-- markdownlint-enable MD013 -->

Ingen eksisterende brukerfiler eller konfigurasjon skal overskrives under
implementeringen. Før hver implementeringsrunde skal `git status` kontrolleres.

## 3. Omfang for førsteversjonen

### 3.1 Skal støttes

- Vanlige, filbaserte Markdown-buffere.
- Tegnvis markering på én eller flere linjer.
- Linjevis markering, normalisert til et sammenhengende tekstområde.
- Norske tegn, emoji, tabulatorer og UTF-8 generelt.
- Flere separate eller overlappende kommentarer på samme linje.
- Kommentarer i frontmatter, avsnitt, lister, tabeller og kodeblokker.
- Prosjekter med Git, inkludert worktrees, og enkeltfiler uten Git.
- Linux og macOS gjennom de eksisterende Home Manager-profilene.
- Statusene `open` og `resolved`.
- Manuell gjenplassering av tvetydige og foreldreløse kommentarer.
- Eksport av alle åpne kommentarer i prosjektet, alle åpne kommentarer i
  gjeldende fil eller kommentaren under markøren.

### 3.2 Skal ikke støttes i førsteversjonen

- Blokkvis Visual-markering. Kommandoen skal avslå dette med en tydelig melding.
- Kommentarer i ulagrede eller navnløse buffere.
- Andre filtyper enn `markdown`.
- Agentsvar eller diskusjonstråder i lageret.
- At agenten endrer status eller skriver i kommentarlageret.
- Direkte sending til en levende OpenCode-sesjon.
- Semantisk eller fuzzy matching av omskrevet tekst.
- Automatisk fletting mellom flere skrivere.
- Sanntidssamarbeid, skybackend eller nettverkstjeneste.
- Automatisk sporing av filflytting eller filomdøping.
- Angrehistorikk for sletting eller statusendringer.
- Automatisk endring av `.gitignore`.

## 4. Foreslått filstruktur

Pluginen holdes adskilt fra resten av Neovim-konfigurasjonen, slik at den senere
kan flyttes til et eget repository uten å skrive om modulene.

```text
config/nvim/
├── local/
│   └── document-comments.nvim/
│       ├── lua/document_comments/
│       │   ├── init.lua
│       │   ├── config.lua
│       │   ├── model.lua
│       │   ├── root.lua
│       │   ├── range.lua
│       │   ├── storage.lua
│       │   ├── anchor.lua
│       │   ├── extmarks.lua
│       │   ├── commands.lua
│       │   ├── export.lua
│       │   └── ui/
│       │       ├── editor.lua
│       │       └── select.lua
│       └── tests/
│           ├── minimal_init.lua
│           ├── fixtures/
│           └── run.lua
└── lua/plugins/
    └── document-comments.lua

config/agents/commands/
└── comments.md
```

`config/nvim/lua/plugins/document-comments.lua` skal peke lazy.nvim til den
lokale katalogen, laste pluginen for `markdown` og registrere opsjoner og
keymaps. Det skal ikke gjøres endringer i `nvim.nix`.

Pluginen skal ikke ha runtime-avhengigheter utover Neovim. Snacks og which-key
kan forbedre eksisterende `vim.ui` og keymap-visning, men domenekoden skal ikke
importere deres interne API-er.

## 5. Prosjektrot, lager og filidentitet

### 5.1 Prosjektrot

For en navngitt Markdown-buffer bestemmes roten slik:

1. Normaliser filstien med `vim.uv.fs_realpath()`.
2. Finn nærmeste forelder med `.git` ved hjelp av `vim.fs.root()`.
3. Hvis Git-rot ikke finnes, bruk dokumentets foreldrekatalog.
4. Tillat senere en konfigurerbar `root(bufnr)`-funksjon, men ikke krev den i
   første implementasjon.

Dette gjør at en Git-worktree får sitt eget lager i worktree-roten. En symlink
peker på samme kommentaridentitet som den kanoniske målfilen. Nested Git-repoer
bruker nærmeste `.git`.

### 5.2 Lagerplassering

```text
<prosjektrot>/.document-comments/comments.json
<prosjektrot>/.document-comments/export.md
```

- Kildebaner lagres relativt til prosjektroten med `/` som separator.
- Absolutt maskinsti lagres ikke i `comments.json`.
- Katalogen opprettes først når første kommentar bekreftes.
- Nye kataloger opprettes med modus `0700` og filer med `0600`, så langt
  plattformen tillater det.
- Verktøyet endrer ikke `.gitignore`. Brukeren kan velge lokal eller
  Git-versjonert lagring.
- `export.md` er et regenererbart øyeblikksbilde. Sletting av eksporten påvirker
  aldri `comments.json`.

Automatisk filflytting er utenfor førsteversjonen. Hvis en fil flyttes, blir
kommentarene stående med gammel relativ bane til brukeren gjenplasserer dem.

## 6. Datamodell og format

Lageret skal være versjonert, deterministisk formatert JSON. Første skjema:

```json
{
  "comments": [
    {
      "anchor": {
        "current": {
          "document_hash": "sha256-of-canonical-buffer-text",
          "position": {
            "end": { "byte_column": 29, "line": 17 },
            "start": { "byte_column": 8, "line": 17 }
          },
          "quote": {
            "exact": "europeisk forankring",
            "prefix": "tilbyr en ",
            "suffix": " for kundens data"
          }
        },
        "original": {
          "document_hash": "sha256-at-creation",
          "position": {
            "end": { "byte_column": 29, "line": 17 },
            "start": { "byte_column": 8, "line": 17 }
          },
          "quote": {
            "exact": "europeisk forankring",
            "prefix": "tilbyr en ",
            "suffix": " for kundens data"
          }
        },
        "state": "attached"
      },
      "body": "Presiser om dette gjelder eierskap, jurisdiksjon eller drift.",
      "created_at": "2026-09-18T12:00:00Z",
      "id": "c_<stabil-id>",
      "resolved_at": null,
      "source": { "path": "produkter/enterprise_ai/enterprise_ai.md" },
      "status": "open",
      "updated_at": "2026-09-18T12:00:00Z"
    }
  ],
  "schema_version": 1,
  "store_revision": 1,
  "updated_at": "2026-09-18T12:00:00Z"
}
```

### 6.1 Regler for feltene

- `id` genereres én gang og endres aldri.
- `status` er bare `open` eller `resolved`.
- `anchor.state` er `attached`, `ambiguous` eller `orphaned` og er uavhengig
  av kommentarstatus.
- `original` er uforanderlig og bevarer teksten og konteksten kommentaren ble
  opprettet mot.
- `current` oppdateres når et levende extmark følger en lagret dokumentendring,
  ved entydig reankring eller ved manuell gjenplassering.
- Linjer og bytekolonner er nullbaserte. Sluttposisjonen er eksklusiv, i tråd
  med Neovims tekst-API-er.
- `quote.exact`, `prefix` og `suffix` er UTF-8-tekst. Prefix og suffix begrenses
  til opptil 128 Unicode-kodepunkter på hver side.
- Dokumenthash beregnes fra bufferlinjer sammenføyd med `\n`. Fysiske CRLF/LF-
  forskjeller skal derfor ikke alene bryte et anker.
- Tidsstempler lagres som UTC i RFC 3339-format.
- `store_revision` økes ved hver vellykkede endring av lageret.

Loaderen skal validere rotobjekt, skjemaversjon, unike ID-er, statuser,
ankerstatus, relative kildebaner og gyldige posisjoner. Ukjent høyere
`schema_version` skal åpnes skrivebeskyttet med en tydelig feil, aldri tolkes
som et tomt lager.

## 7. Markeringer og tekstkoordinater

### 7.1 Oppretting fra Visual mode

`DocumentCommentsAdd` skal bare kunne startes fra Visual mode.

1. Les gjeldende utvalg med `getpos('v')`, `getpos('.')`, `getregionpos()` og
   `getregion()` mens Visual mode fortsatt er aktiv.
2. Bruk eksplisitt tegnvis eller linjevis type og inkluderende grenser, slik at
   resultatet ikke avhenger skjult av brukerens `selection`-opsjon.
3. Avvis blokkvis markering.
4. Normaliser rekkefølgen slik at baklengs markering gir samme område.
5. Konverter de én-baserte posisjonene til nullbaserte bytekolonner med
   eksklusiv slutt.
6. Hent eksakt tekst med `nvim_buf_get_text()` og kontroller at den er identisk
   med resultatet fra `getregion()`.

Bytekolonner er riktig intern modell fordi Neovim-buffer-API-ene bruker byte-
indekser. Koden skal aldri bruke visuelle skjermkolonner som varig posisjon.
`vim.str_utfindex()` og `vim.str_byteindex()` brukes bare når kontekst må
avgrenses etter Unicode-kodepunkter.

Visuell linjebryting, conceal og folding endrer ikke bufferkoordinatene. De skal
derfor ikke ha egne ankerregler.

### 7.2 Ulagrede dokumentendringer

Førsteversjonen skal avslå oppretting og manuell gjenplassering når
`vim.bo.modified` er sann. Meldingen skal be brukeren lagre dokumentet først.

Dette er et bevisst kompromiss: en bekreftet kommentar skal alltid vise til en
dokumentversjon som finnes på disk. Eksisterende extmarks kan følge ulagrede
redigeringer i minnet, men deres varige ankere oppdateres først etter en
vellykket `BufWritePost`.

## 8. Extmarks i åpne buffere

Hver lastet Markdown-buffer får ett eget plugin-navnerom. Hver tilknyttet
kommentar får et range-extmark med:

- `right_gravity = false`
- `end_right_gravity = true`
- `invalidate = false`
- `undo_restore = true`
- egen highlight for `open` og en svakere highlight for `resolved`
- prioritet høy nok til at markeringen er synlig sammen med vanlig syntaks,
  uten å bruke conceal eller erstatte dokumenttekst

Valget av tyngdekraft gjør at en full erstatning av det kommenterte området
fortsatt omslutter den nye teksten. Når et område slettes helt, kollapser
extmarket. Pluginen skal oppdage et tomt range og sette ankeret til `orphaned`
i stedet for å stole på Neovims `invalid`-felt.

På `BufWritePost`:

1. Les alle levende extmark-områder.
2. Oppdater `anchor.current` for ikke-tomme områder.
3. Bevar alltid `anchor.original`.
4. Sett tomme områder til `orphaned` og behold siste tekst/kontekst.
5. Beregn ny dokumenthash.
6. Skriv lageret atomisk.

Ved buffer-reload skal navnerommet tømmes, dokumentet leses på nytt, ankrene
reankres og extmarks opprettes fra resultatet. `nvim_buf_attach(...,
{ on_reload = ... })` er den primære mekanismen; `BufReadPost` og `BufEnter`
brukes som sikkerhetsnett.

Overlappende extmarks er tillatt. Hvis flere kommentarer dekker markøren, skal
redigering, statusendring og sletting vise et valg med `vim.ui.select` i stedet
for å velge en vilkårlig kommentar.

## 9. Reankring etter eksterne endringer

Reankring skal være konservativ og deterministisk. Den skal ikke bruke fuzzy
matching i førsteversjonen.

For hver kommentar:

1. **Posisjonstreff:** Les teksten ved siste kjente posisjon. Hvis den er lik
   `quote.exact`, sett `attached` uten videre søk.
2. **Eksakt globalt søk:** Søk etter alle byteeksakte forekomster av
   `quote.exact` i dokumentets kanoniske tekst.
3. **Ett treff:** Hvis det finnes nøyaktig ett treff, flytt `current` dit og
   sett `attached`.
4. **Flere treff:** Sammenlign lagret prefix og suffix mot hver kandidat. Bare
   hvis nøyaktig én kandidat passer begge tilgjengelige kontekster, kan den
   festes automatisk.
5. **Fortsatt flere treff:** Sett `ambiguous`. Gammelt linjenummer eller kortest
   avstand skal ikke brukes til å gjette.
6. **Ingen treff:** Sett `orphaned`. Bevar `original` og siste `current`.

Et svært kort sitat kan dermed festes automatisk bare når sitat og kontekst gir
ett entydig mål. Omskrevet tekst gir `orphaned`; automatisk semantisk matching
utsettes.

`DocumentCommentsReattach` skal la brukeren markere ny tekst og velge en
`ambiguous` eller `orphaned` kommentar. Kommandoen oppdaterer `current`, kildebanen
og ankerstatus, men aldri `original`.

## 10. Lagring, feil og samtidighet

### 10.1 Lasting

Ved første tilgang til et prosjekt:

1. Les råbytes fra `comments.json`, eller bruk en eksplisitt «finnes ikke»-tilstand.
2. Beregn SHA-256 av råinnholdet.
3. Dekod og valider hele dokumentet.
4. Behold råhashen som versjonen denne Neovim-prosessen har lastet.

Ugyldig JSON, ugyldig skjema eller leseproblemer blokkerer all skriving for
prosjektet. Feilen skal vises med lagerstien. «Kunne ikke laste» må aldri bli
behandlet som «ingen kommentarer».

### 10.2 Atomisk skriving

Alle mutasjoner skal bruke samme lagringsfunksjon:

1. Les lagerfilen på nytt og sammenlign råhashen med sist lastede hash.
2. Avbryt med konfliktmelding hvis filen er opprettet, slettet eller endret av
   en annen prosess.
3. Muter en kopi av modellen og valider den.
4. Kod deterministisk JSON med to mellomrom, sorterte nøkler og avsluttende
   linjeskift.
5. Skriv til en unik midlertidig fil i `.document-comments`.
6. Kjør `fsync` på den midlertidige filen og lukk den.
7. Bytt filen inn med `fs_rename` i samme katalog.
8. Kjør `fsync` på katalogen der plattformen støtter det.
9. Oppdater prosessens råhash først etter vellykket rename.

Hvis skriving, fsync eller rename feiler, skal den gamle lagerfilen forbli
urørt. En kommentar regnes ikke som bekreftet før dette løpet har lykkes. Ved
feil i kommentarvinduet blir vinduet stående åpent med teksten intakt.

Midlertidige filer fra et avbrudd kan ryddes ved neste vellykkede lasting etter
at hovedfilen er validert. Atomisk rename og fsync gir god beskyttelse ved
prosesskrasj; planen lover ikke absolutt holdbarhet ved maskinvarefeil eller
filsystem som bryter disse garantiene.

### 10.3 Flere prosesser

Førsteversjonen har én forventet skriver og ingen fletting eller fillås.

- Hashkontrollen før hver skriving forhindrer stille overskriving.
- `BufEnter` og `FocusGained` kan kontrollere om lagerhashen er endret og laste
  inn på nytt når det ikke finnes et åpent kommentarutkast.
- Ved konflikt skal brukeren få valget mellom å beholde utkastet og laste
  lageret på nytt. Pluginen skal aldri velge «siste skriver vinner».
- Agenten skal uttrykkelig instrueres om ikke å endre `comments.json`.

## 11. Brukergrensesnitt

### 11.1 Kommentarredigering

Oppretting og redigering skjer i et flytende `acwrite`-buffer med Markdown som
filtype.

- Kommentaren kan bestå av flere linjer.
- `:write` utløser validering og lagring gjennom `BufWriteCmd`.
- Eksisterende LazyVim-binding for `<C-s>` vil dermed også fungere når
  terminalen sender kombinasjonen.
- `:q` avbryter et uendret utkast; et endret utkast får Neovims vanlige varsel.
- Tom kommentar avvises.
- Vinduet lukkes bare etter vellykket lagring.
- Footer eller buffertekst forklarer `:w` for lagring og `:q` for avbrytelse.

Det er ikke krav om krasjgjenoppretting for tekst som ennå ikke er bekreftet med
`:write`. Denne begrensningen skal stå i brukerhjelpen.

### 11.2 Liste og valg

`vim.ui.select` brukes til prosjektlisten og når flere kommentarer finnes ved
markøren. Hvert element viser:

```text
[open/attached] produkter/enterprise_ai/enterprise_ai.md:18  Presiser om …
```

Standardfilter er åpne kommentarer. Kommandoen skal også kunne vise `resolved`
eller `all`. Valg hopper til fil og område. For `ambiguous` og `orphaned` hoppes
det til siste kjente posisjon når den fortsatt er gyldig, ellers åpnes filen og
kommentardetaljene vises uten å hevde at ankeret er korrekt.

### 11.3 Kommandoer

<!-- markdownlint-disable MD013 -->

| Kommando | Funksjon |
| --- | --- |
| `:DocumentCommentsAdd` | Opprett kommentar fra Visual-markering. |
| `:DocumentCommentsList [open\|resolved\|all]` | List prosjektets kommentarer. |
| `:DocumentCommentsEdit` | Rediger kommentar under markøren eller velg ved overlapp. |
| `:DocumentCommentsResolve` | Bytt mellom `open` og `resolved`. |
| `:DocumentCommentsDelete` | Slett etter eksplisitt bekreftelse. |
| `:DocumentCommentsNext` | Gå til neste åpne kommentar i gjeldende fil. |
| `:DocumentCommentsPrev` | Gå til forrige åpne kommentar i gjeldende fil. |
| `:DocumentCommentsReattach` | Knytt valgt kommentar til ny Visual-markering. |
| `:DocumentCommentsExport [project\|file\|current] [path]` | Lag Markdown-eksport. Standard er `project`. |
| `:DocumentCommentsReload` | Forkast lastet modell og les lageret på nytt når det er trygt. |
| `:DocumentCommentsStorePath` | Vis rot, lagersti og lastet revisjon. |

<!-- markdownlint-enable MD013 -->

### 11.4 Keymaps

| Modus | Binding | Handling |
| --- | --- | --- |
| Visual | `<leader>aa` | Legg til kommentar. |
| Normal | `<leader>al` | List kommentarer. |
| Normal | `<leader>ae` | Rediger ved markøren. |
| Normal | `<leader>ar` | Løs eller gjenåpne. |
| Normal | `<leader>an` | Neste åpne kommentar. |
| Normal | `<leader>ap` | Forrige åpne kommentar. |
| Visual | `<leader>aR` | Gjenplasser kommentar. |
| Normal | `<leader>ax` | Eksporter åpne prosjektkommentarer. |
| Normal | `<leader>ad` | Slett kommentar. |

Registrer `<leader>a` som gruppen «annotations» i which-key. Keymaps skal bare
være aktive for Markdown-buffere der det er relevant.

## 12. Eksport og agentarbeidsflyt

`DocumentCommentsExport` skriver som standard
`.document-comments/export.md`. Eksporten er et øyeblikksbilde og inneholder:

- genereringstid
- `store_revision` og hash av lageret
- eksplisitt instruksjon om at agenten ikke skal endre lageret eller eksporten
- kommentar-ID
- status og ankerstatus
- prosjekt-relativ kildebane
- siste kjente linje og bytekolonne
- eksakt valgt tekst
- prefix og suffix eller et lesbart kontekstutdrag
- kommentartekst
- originalt sitat når det avviker fra gjeldende sitat

Eksempelstruktur:

```markdown
# Document comments

Generated: 2026-09-18T12:30:00Z
Store revision: 7

Edit the referenced source documents. Do not edit comments.json or this export.
Report what was done for each comment ID.

## c_ab12 — produkter/enterprise_ai/enterprise_ai.md:18

- Status: open
- Anchor: attached
- Selected text: `europeisk forankring`

> Presiser om dette gjelder eierskap, jurisdiksjon, drift eller alle tre.
```

Eksport av `project` tar alle åpne kommentarer i prosjektet. `file` begrenser
til gjeldende fil. `current` eksporterer kommentaren under markøren. Dette gir
et enkelt valg uten å innføre en egen «valgt for eksport»-status i datamodellen.

`config/agents/commands/comments.md` skal følge det eksisterende kommandoformatet
og instruere agenten om å:

1. lese oppgitt eksportfil, eller `.document-comments/export.md` som standard
2. lese de refererte Markdown-filene
3. behandle hver kommentar-ID
4. endre bare kildedokumentene
5. ikke endre `comments.json`, eksporten eller kommentarstatus
6. oppsummere resultatet per kommentar-ID

Dette er kompatibelt med OpenCode V2s globale Markdown-kommandoer og den
eksisterende Home Manager-koblingen. Ingen OpenCode API-, plugin- eller
sesjonsintegrasjon skal implementeres.

## 13. Implementering i trinn

Hvert trinn skal avsluttes med de angitte porttestene før neste trinn begynner.

### Trinn 1: Plugin-skall og testharness

Opprett lokal pluginstruktur, lazy.nvim-spesifikasjon og et rent headless
testoppsett uten ny runtime-avhengighet.

Leveranser:

- `setup()` og validerte standardopsjoner
- FileType-avgrensning til Markdown
- kommandoregistrering
- root- og sti-normalisering
- enkel testkjører med `nvim --clean --headless`

Porttest:

- pluginen lastes bare for Markdown
- Git-root, worktree-lignende `.git`-fil, symlink og ikke-Git-fil gir forventet
  rot og relativ bane
- alle eksisterende Neovim-plugins starter uten feil

### Trinn 2: Datamodell og robust lager

Implementer skjema, validering, ID-er, tidsstempler, deterministisk JSON,
atomisk skriving og hashbasert konfliktoppdagelse.

Porttest:

- lagring og ny prosess gir identisk modell
- Unicode overlever encode/decode
- ugyldig JSON blokkerer skriving
- simulert skrive-, fsync- og rename-feil bevarer gammel gyldig fil
- ekstern endring mellom load og save gir konflikt, ikke overskriving
- ukjent skjemaversjon åpnes ikke som tomt lager

### Trinn 3: Visual-markering og første vertikale flyt

Implementer range-normalisering, kommentarvindu, `:write`, oppretting av extmark
og lasting ved ny buffer/prosess.

Porttest:

- to ord på samme lange linje kan kommenteres separat
- flerlinjet utvalg med `æøå`, emoji og tabulator bevares nøyaktig
- fremover- og bakovermarkering gir samme tekst
- blokkvis markering og ulagret buffer avvises tydelig
- kommentarvinduet lukkes ikke ved lagringsfeil
- restart av Neovim viser alle bekreftede kommentarer

### Trinn 4: Levende ankere og reankring

Implementer extmark-oppdatering ved lagring, buffer-reload, konservativ
Text Quote-reankring og manuell gjenplassering.

Porttest:

- innsetting før området flytter kommentaren
- redigering inne i området oppdaterer `current` etter lagring og bevarer
  `original`
- full sletting gir `orphaned`
- unikt flyttet sitat gjenfinnes etter ekstern omskriving
- duplikat med unik prefix/suffix-kontekst gjenfinnes
- fortsatt tvetydig duplikat blir `ambiguous`
- ingen eksakt forekomst blir `orphaned`
- undo/redo og etterfølgende lagring gir konsistent anker

### Trinn 5: Daglig UI og livssyklus

Implementer liste, valg ved overlapp, redigering, status, sletting og
navigasjon.

Porttest:

- overlappende kommentarer kan velges og redigeres uavhengig
- `resolved` skjules fra standardlisten, men finnes i `all`
- neste/forrige navigerer i dokumentrekkefølge og wrapper
- sletting krever bekreftelse og berører bare valgt ID
- alle mutasjoner lagres umiddelbart eller rapporterer feil

### Trinn 6: Eksport og OpenCode-kommando

Implementer prosjekt-, fil- og gjeldende-kommentar-eksport samt den globale
agentkommandoen.

Porttest:

- eksporten inneholder stabil ID, bane, sitat, kontekst, status og ankerstatus
- `ambiguous` og `orphaned` er tydelig merket
- eksporten kan leses uten Neovim-pluginen
- ny eksport endrer ikke originalkommentarer eller status
- `/comments` i OpenCode finner eksporten og instruerer agenten om bare å endre
  kildedokumenter

### Trinn 7: Hardening og innføring

Kjør alle automatiske tester og realistiske manuelle forsøk.

Porttest:

- lang Markdown-fil med visuell linjebryting og `render-markdown.nvim`
- vanlig SSH/tmux uten mus eller nettleser
- prosessavbrudd etter bekreftet lagring
- full disk/skrivebeskyttet katalog gjennom injisert lagringsfeil og minst én
  realistisk manuell test
- to Neovim-prosesser der den andre endrer lageret
- Linux-smoketest på aktiv vert
- macOS-smoketest på en av de eksisterende aarch64-darwin-profilene

## 14. Teststrategi

### 14.1 Rene modultester

Test uten UI der det er mulig:

- skjema og migreringsvakt
- posisjonsnormalisering
- UTF-8-kontekst
- reankringskandidater
- deterministisk serialisering
- konfliktoppdagelse
- eksportformat

Filoperasjoner skal gå gjennom en liten adapter slik at feil i `open`, `write`,
`fsync`, `close` og `rename` kan injiseres deterministisk.

### 14.2 Headless Neovim-tester

Bruk ekte buffere og extmarks for:

- `getregionpos()`/`getregion()`
- samme linje og flere linjer
- Unicode og tabulatorer
- extmark gravity
- sletting, erstatning og undo/redo
- `BufWritePost` og reload
- lasting i en ny Neovim-prosess

Ikke mock extmarks eller bufferkoordinater; dette er nettopp områdene testene
skal verifisere.

### 14.3 Manuelle akseptansetester

Bruk et realistisk Markdown-dokument og kontroller hele flyten fra Visual-
markering til agenteksport. Minst én test skal kjøres gjennom SSH og én på
macOS før førsteversjonen regnes som ferdig.

## 15. Innføring og tilbakerulling

1. Implementer pluginen lokalt og last den bare for Markdown.
2. Bruk et midlertidig testprosjekt frem til lagrings- og krasjtestene passerer.
3. Ta en manuell kopi av `.document-comments` før skjemaendringer under
   utviklingen.
4. Prøv løsningen på ett reelt dokument med kommentarer som ikke er kritiske.
5. Aktiver agentkommandoen først etter at eksportformatet er stabilt.
6. Dokumenter keymaps, lagersti, Git-valget og begrensningen for ulagrede
   buffere i pluginens korte README eller `:help`-tekst.

Tilbakerulling krever bare at lazy.nvim-spesifikasjonen deaktiveres eller
fjernes. `comments.json` og `export.md` er vanlige filer og forblir tilgjengelige.
Ingen avinstallasjon skal slette `.document-comments`.

## 16. Ferdigdefinisjon for førsteversjonen

Førsteversjonen er ferdig når alle disse punktene er demonstrert:

- To separate tekstområder på samme Markdown-linje har uavhengige kommentarer.
- Norske tegn, emoji og et flerlinjeområde overlever lagring og restart.
- Bekreftet kommentar overlever normal avslutning og tvunget prosessavbrudd.
- En lagringsfeil vises tydelig og ødelegger ikke forrige gyldige lager.
- Innsetting før et område og redigering inne i området bevarer riktig extmark.
- Eksternt flyttet, entydig sitat gjenfinnes.
- Duplikat eller slettet sitat kobles aldri stille til feil tekst.
- Konflikt mellom to skrivere oppdages før overskriving.
- Kommentarer kan listes, redigeres, løses, gjenåpnes og plasseres på nytt.
- En lesbar eksport kan behandles av en ny agentsesjon.
- Agenten kan endre dokumentet uten å ha tilgang til den opprinnelige Neovim-
  eller agentsesjonen.
- Pluginen kan deaktiveres uten at dataene blir utilgjengelige.
- Hele grunnflyten fungerer over SSH uten nettleser, server eller port forwarding.

## 17. Bevisst utsatt arbeid

Følgende vurderes først etter at førsteversjonen har vært brukt på reelle
dokumenter:

- fuzzy eller semantisk reankring
- automatisk filflytting
- vilkårlige utvalg av flere kommentarer i én eksport
- agentsvar og statusoppdatering fra agent
- kommentartråder og historikk
- flere samtidige skrivere og fletting
- støtte for andre tekst- og kodefiler
- separat plugin-repository og generell distribusjon
- direkte OpenCode-integrasjon

Brukserfaringen fra førsteversjonen skal avgjøre hvilke av disse som faktisk er
nødvendige.

## 18. Kilder brukt i verifikasjonen

- Lokalt oppsett: `modules/home/programs/nvim.nix`,
  `config/nvim/lua/config/`, `config/nvim/lua/plugins/`,
  `config/nvim/lazyvim.json`, `config/nvim/lazy-lock.json`, `flake.nix` og
  `profiles/home/common.nix`.
- Installert Neovim 0.12.5-dokumentasjon for `nvim_buf_set_extmark()`,
  `getregion()`, `getregionpos()`, `vim.json`, `vim.fs.root()` og `vim.uv`.
- [Neovim API-dokumentasjon](https://neovim.io/doc/user/api.html#nvim_buf_set_extmark()).
- [Neovim-dokumentasjon for `getregionpos()`](https://neovim.io/doc/user/vimfn.html#getregionpos()).
- [W3C Web Annotation: Text Quote Selector](https://www.w3.org/TR/annotation-model/#text-quote-selector).
- [OpenCode V2: Commands](https://opencode.ai/v2/docs/commands).

De lokale API-forsøkene ble kjørt isolert under `/tmp/opencode` og endret ikke
dotfiles-repositoriet.
