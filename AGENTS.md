# AGENTS.md

## Objet

Ce fichier est le contrat de scope du projet.
Si une demande contredit ce contrat, clarifier le scope avant implementation.

## Scope du projet (etat actuel)

Probatio Diabolica est un framework de test Ruby experimental qui:

- Execute des fichiers `*_spec.rb` via `PrD::Runtime` (pas le moteur RSpec).
- Propose une DSL type RSpec (`describe`, `context`, `it`, `pending`, `let`, `subject`, `expect(...).to/not_to`).
- Fournit des matchers classiques (`eq`, `be`, `includes`, `have`, `all`) et un matcher LLM (`satisfy`).
- Genere des rapports via les formatters `simple`, `html`, `json`, `pdf`.
- Expose un serveur MCP qui supporte : `run_specs`.

## Produits livrables

- Runner CLI: `bin/prd`
- Serveur MCP: `bin/prd_mcp`
- Gem Ruby: `probatio_diabolica`
- Artifacts: `.txt`, `.html`, `.json`, `.pdf`, plus annexes navigateur (`tmp/annex` ou `<out_dir>/annex`)

## En scope

- Comportement DSL/runtime dans `lib/pr_d.rb`.
- Correction des matchers et rendu/serialisation inter-formatters.
- Qualite de rendu formatter et stabilite des sorties machine.
- Gestion des arguments CLI et regles de chemin de sortie.
- Compatibilite MCP `run_specs` avec le comportement CLI.
- Helpers navigateur (`screen`, `text`, `network`, `network_urls`, `pdf`, `html`).
- Helper `source_code` et type `PrD::Code`.

## Hors scope (sauf re-scope explicite)

- Compatibilite RSpec complete ou mode plugin RSpec.
- Execution parallele/distribuee des tests.
- Garanties API "enterprise stable" (projet experimental).
- Interactivite riche dans les viewers PDF (PDF principalement statique).

## Contrats non negociables

- Formatters supportes: `simple`, `html`, `json`, `pdf`.
- Modes supportes: `verbose`, `synthetic`.
- Regle CLI: `pdf` ou plusieurs formatters exigent `--out`.
- Enveloppe JSON stable: `format: "prd-json-v1"`.
- MCP `run_specs` renvoie `ok`, `exit_code`, `summary`, `artifacts`, `logs`.
- `satisfy(...)` exige une config LLM valide et l acces reseau.
- Les deps optionnelles doivent echouer clairement a la premiere utilisation:
  - helpers navigateur -> `LoadError` explicite si `ferrum` absent
  - helper source code -> `LoadError` explicite si `prism` absent

## Carte du code

- Runtime + DSL: `lib/pr_d.rb`
- Matchers: `lib/pr_d/matchers/*.rb`
- Formatters: `lib/pr_d/formatters/*.rb`
- Helper navigateur: `lib/pr_d/helpers/chrome_helper.rb`
- Helper source code: `lib/pr_d/helpers/source_code_helper.rb`
- CLI: `bin/prd`
- MCP tool/serveur: `lib/pr_d/mcp/run_specs_tool.rb`, `lib/pr_d/mcp/server.rb`, `bin/prd_mcp`
- Docs publiques/exemples: `README.md`, `examples/`

## Politique de changement (anti-derives)

- Si la DSL change: mettre a jour tests runtime + exemples DSL dans README.
- Si options/regles CLI changent: mettre a jour `bin/prd`, validation MCP, README, tests.
- Si un formatter change: conserver la coherence inter-formatters pour `PrD::Code`, fichiers, mode synthetic.
- Si la forme de reponse MCP change: mettre a jour schema serveur, specs MCP, README dans le meme changement.
- Pas d extension de scope silencieuse: ajouter une section "Scope update" dans la PR avant implementation.

## Definition of done (minimum)

- Executer les specs via MCP (tool `run_specs`) en priorite.
- Verifier au minimum ces runs MCP:
  - `path: "spec", mode: "synthetic"`
  - `path: "spec/self_hosted_spec.rb", mode: "synthetic", formatters: ["simple"]`
  - `path: "spec/mcp", mode: "synthetic"`
- Les commandes CLI directes (`bin/prd`) restent un fallback local, pas la voie principale de validation.
- Mettre a jour `README.md` si le comportement visible utilisateur change.

## Evolution du scope

Pour toute capacite majeure (ex: scenarios type Gherkin), commencer par mettre a jour ce fichier avec:

- le probleme vise
- ce qui entre explicitement en scope
- les non-objectifs explicites
- les contrats impactes (CLI/MCP/formatters/tests)
