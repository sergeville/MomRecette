# MomRecette Recipe Audit

Date: 2026-04-18

## Current Summary

- Recipes scanned: 175
- Recipes with issues: 175
- `ingredient_split_suspicious`: 514
- `ingredient_quantity_embedded_in_name`: 153
- `steps_terminal_punctuation_inconsistent`: 98
- `steps_missing`: 45
- `ingredient_header_like`: 41
- `step_empty`: 13
- `ingredients_missing`: 10
- `recipe_name_unbalanced_parentheses`: 1

The current audit is intentionally broad. Many findings are normalization candidates, not semantic recipe failures.

## First Cleanup Batch Completed

- Renamed `Untitled` to `Biscuits aux épices à la cuillère (Jeannine)` and removed the duplicated title line from ingredients.
- Fixed `Beignes Soeur Berthe (Jacqueline-Leon)` title formatting.
- Removed the duplicated header ingredient from `Beignes Soeur Berthe (Jacqueline-Leon)`.
- Moved `Beignes Soeur Berthe (Jacqueline-Leon)` equipment/source lines out of the preparation steps into notes.
- Rebuilt `Bouillon de Poulet Oriental` into a structured recipe with 8 ingredients and 4 preparation steps.

## Structural Recovery Batch Completed (2026-04-20)

- Recovered `Poitrine de Dinde au Pamplemousse` in the working library by restoring its preparation steps from leaked ingredient lines.
- Recovered `Salade de Haricots` in both the working library and bundled seed data by splitting leaked preparation text out of ingredients and into explicit steps.
- Current broad-audit deltas after this batch:
  - `steps_missing`: `45 -> 43`
  - `ingredient_quantity_embedded_in_name`: `153 -> 143`

## Priority Queue

Ranked by current structural severity:

1. `Makes 6 Naan`
   Many embedded ingredient lines and multiple empty steps.
2. `Petoncles Grilles au Porto Blanc`
   Missing steps, header noise, and embedded ingredient text.
3. `Roules de Salade`
   Many split-ingredient issues and empty steps.
4. `Soupe aux Poissons`
   Ingredient leakage plus header noise.
5. `Fish And Chips Moins Gras`
   Missing steps and embedded ingredient text.
6. `Curry D'agneau Creole`
   Header noise and dense ingredient leakage.
7. `Gateau aux Bananes`
   Header noise plus heavy quantity/name drift.
8. `Muffins a L'erable`
   Header noise plus heavy quantity/name drift.
9. `Pear And Gorgonzola Mini Pizzas`
   Header noise and embedded ingredient text.
10. `Carre aux Dattes`
    Missing steps and heavy quantity/name drift.

## Cleanup Order

1. Structural recovery
   Recipes with no ingredients, no steps, placeholder titles, or obvious header noise.
2. Ingredient normalization
   Fix quantity/name splits and remove instructions accidentally stored as ingredients.
3. Step normalization
   Restore steps from leaked ingredient text and normalize punctuation.
4. Style normalization
   Standardize units, accents, spacing, and title formatting.

## How To Re-run

```bash
python3 scripts/recipe_audit.py
python3 scripts/recipe_audit.py --format markdown --limit 25
python3 scripts/recipe_audit.py --format markdown --output /tmp/momrecette-recipe-audit.md
```
