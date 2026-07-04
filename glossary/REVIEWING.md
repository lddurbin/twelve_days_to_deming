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

---

# Glossary review guide (English reference)

*This is an English mirror of the instructions above, kept for whoever is
coordinating the review — the reviewer only needs the French version.*

This document accompanies `glossary/glossary-for-review.csv`. Each row is an
English term found in the corpus; your task is to fill in three columns for
each one.

## Columns to fill in

- **`approved_fr`** — the French rendering you've settled on. Leave blank if
  the term is kept in English.
- **`decision`** — one of the following three values, lowercase, exact
  spelling:
  - `translate` — translate the term; `approved_fr` then becomes required.
  - `keep english` — keep the term in English as-is.
  - `gloss on first use` — keep the term in English, but add a short French
    explanation on its first occurrence (note the text of that explanation
    in `reviewer_notes`).
- **`reviewer_notes`** — free-form comment (optional): justification,
  source, or the gloss text for `gloss on first use`.

## Context columns (do not edit)

- `fr_rendering` — an already-established rendering, or just a candidate
  suggestion; it's only a suggestion, `approved_fr` is what counts.
- `frequency`, `occurrence_types`, `contexts` — how often and where the term
  appears in the corpus, to help judge its importance.
- `decision_needed` — `TRUE` if the term is new or contested and needs your
  judgment call; `FALSE` if its translation is already established (already
  pre-filled below, for verification only).
- `source` — the citation/justification for the translation, when one
  exists.

## Once finished

Every row needs a value in `decision` (and in `approved_fr` if `decision` is
`translate`) before the glossary can be locked. A developer will then run
`Rscript scripts/lock-glossary.R`: it fails, listing every term still
missing a decision, until all of them are resolved; once every term is
decided, it produces `glossary/approved-glossary.json`, the final glossary
used for translation.
