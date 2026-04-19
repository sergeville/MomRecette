# Recipe Photo Helper

This folder contains local utilities that support the MomRecette photo pipeline.

## `recipe_audit.py`

Audit the MomRecette recipe catalog for structural and formatting drift before a cleanup pass.

Examples:

```bash
python3 scripts/recipe_audit.py
python3 scripts/recipe_audit.py --format markdown --limit 25
python3 scripts/recipe_audit.py --format markdown --output /tmp/momrecette-recipe-audit.md
```

The audit focuses on:

- recipes with missing ingredients or steps
- placeholder or malformed recipe names
- ingredient rows that look like pasted headers or inline notes
- ingredient rows where quantity and name are split incorrectly
- inconsistent step punctuation

## `recipe_photo_helper.py`

Save a meal photo for a chosen recipe into:

`Resources/RecipePhotos/`

The filename is normalized to match the Swift app's automatic lookup logic.

Examples:

```bash
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --status
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --search
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --file ~/Downloads/biscuit.jpg
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --url https://example.com/biscuit.jpg
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --file ~/Downloads/new-photo.png --overwrite
```

After saving the image, relaunch MomRecette so the store can hydrate missing recipe photos from the local photo pack.

## `fetch_recipe_photo.py`

Search the web for a recipe page, extract a likely recipe image, and save it
through the same filename rules as `recipe_photo_helper.py`.

Examples:

```bash
python3 scripts/fetch_recipe_photo.py "Naan" --dry-run --print-candidates
python3 scripts/fetch_recipe_photo.py "Naan"
python3 scripts/fetch_recipe_photo.py "Naan" --page-url https://www.ricardocuisine.com/recettes/153-pain-naan
python3 scripts/fetch_recipe_photo.py "Naan" --target live
```

Notes:

- requires outbound network access
- prefers recipe pages over Google Images screenshots
- falls back to manual search if no usable page image is found

## `batch_recipe_photos.py`

Use this script to scale the same process across all recipes.

Examples:

```bash
python3 scripts/batch_recipe_photos.py --status
python3 scripts/batch_recipe_photos.py --category Plats --print-searches 3
python3 scripts/batch_recipe_photos.py --category Plats --open-searches 3
python3 scripts/batch_recipe_photos.py --export-missing /tmp/momrecette-missing-photos.csv
python3 scripts/batch_recipe_photos.py --apply /tmp/momrecette-missing-photos.csv
python3 scripts/batch_recipe_photos.py --apply /tmp/momrecette-missing-photos.csv --overwrite
```

Suggested workflow:

1. Print or open image searches for the next missing recipe titles.
2. Copy the right direct image URLs or download the chosen images locally.
3. Export the missing-photo CSV template if you want to process many at once.
4. Fill `file_path` with local images and/or `image_url` with direct image links.
5. Apply the manifest in one run.

See also:

- `recipe_photo_manifest.example.csv`

## `recipe_card_generator.py`

Create a local recipe-card style image from a title, ingredient list, and optional dish photo.

Examples:

```bash
python3 scripts/recipe_card_generator.py \
  --title "Bifteck de Flan Farci" \
  --ingredients "2 bifteck de flan;2 c. a table de margarine;2 gros oignons haches finement" \
  --output local/examples/bifteck_recipe.png

python3 scripts/recipe_card_generator.py \
  --title "Bifteck de Flan Farci" \
  --ingredients-file /tmp/ingredients.txt \
  --photo /tmp/dish.jpg \
  --output local/examples/bifteck_recipe.png
```

Notes:

- this is a local Pillow-based generator
- keep one-off outputs in `local/` instead of the repo root
- use `recipe_card_ai_cli/` when you want the OpenAI-backed image workflow


## `package_sergeiphone_ipa.sh`

Archive and export an iPhone installable build named `sergeiPhone`.

Examples:

```bash
./scripts/package_sergeiphone_ipa.sh
ALLOW_PROVISIONING_UPDATES=YES ./scripts/package_sergeiphone_ipa.sh
IOS_EXPORT_METHOD=ad-hoc ./scripts/package_sergeiphone_ipa.sh
```

This script:

- prepares a temporary export workspace so the repo is not mutated
- seeds the iPhone build from the live `Documents` payload when available
- exports `dist/sergeiPhone-<version>-<build>.ipa`
- refreshes `dist/sergeiPhone.ipa`
- writes `dist/sergeiPhone-PACKAGE_INFO.txt`

## Packaging assets

Reusable packaging assets belong under `scripts/assets/`.

Current tracked asset:

- `scripts/assets/momrecette-dmg-background.png`
