# Guide de relecture du glossaire

Ce document accompagne `glossary/glossary-for-review.csv` (issue #327).
Chaque ligne est un terme anglais rencontré dans le corpus ; votre tâche est
de compléter trois colonnes pour chacune.

## Colonnes à remplir

- **`approved_fr`** — la traduction française retenue. Laissez vide si le
  terme est conservé en anglais.
- **`decision`** — une des trois valeurs suivantes, en minuscules, orthographe
  exacte :
  - `translate` — traduire le terme ; `approved_fr` devient alors
    obligatoire.
  - `keep english` — conserver le terme en anglais tel quel.
  - `gloss on first use` — conserver le terme en anglais, mais ajouter une
    courte explication en français lors de sa première occurrence (notez le
    texte de cette explication dans `reviewer_notes`).
- **`reviewer_notes`** — commentaire libre (facultatif) : justification,
  source, ou texte de la glose pour `gloss on first use`.

## Colonnes de contexte (ne pas modifier)

- `fr_rendering` — traduction déjà établie ou simple proposition à titre
  indicatif ; ce n'est qu'une suggestion, `approved_fr` fait foi.
- `frequency`, `occurrence_types`, `contexts` — combien de fois et où le
  terme apparaît dans le corpus, pour juger de son importance.
- `decision_needed` — `TRUE` si le terme est nouveau ou contesté et
  nécessite votre arbitrage ; `FALSE` si sa traduction est déjà établie
  (ligne déjà pré-remplie ci-dessous à titre de vérification seulement).
- `source` — justification/citation de la traduction, quand elle existe.

## Une fois terminé

Chaque ligne doit porter une valeur dans `decision` (et dans `approved_fr` si
`decision` vaut `translate`) avant que le glossaire puisse être verrouillé.
Un développeur exécutera alors `Rscript scripts/lock-glossary.R` : le script
échoue en listant les termes encore manquants tant qu'il en reste ; une fois
tous les termes décidés, il produit `glossary/approved-glossary.json`, le
glossaire définitif utilisé pour la traduction.
