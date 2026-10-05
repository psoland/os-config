**Keep it as a skill.** In OpenCode V2, yours already has the settings you want:

```yaml
slash: true
metadata:
  opencode/autoinvoke: false
```

- `autoinvoke: false` hides it from the model’s available-skills list, while allowing explicit loading by ID.
- `slash: true` keeps it available in the interactive command catalog.

You can explicitly invoke `/knowit-brand` or ask: “Use the knowit-brand skill.”

A skill is especially suitable here because it keeps `assets/` and `references/` together with a reliable base directory. Commands are primarily reusable prompt templates.

**One cleanup worth making:** your description currently says “Bruk ALLTID” and lists automatic triggers. Replace it with wording matching your intent, for example:

```yaml
description: Knowits visuelle identitet «Nordic Skies» – farger, logo, typografi og grafiske elementer. Bruk kun når brukeren eksplisitt ber om knowit-brand-skillen.
```

The metadata controls discovery; that description makes the intent consistent and clearer for other tools.
