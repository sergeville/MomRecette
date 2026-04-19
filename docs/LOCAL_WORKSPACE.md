# Local Workspace Hygiene

This repository now uses a simple boundary between tracked product code and local-only working files.

## Canonical tracked surfaces

- `App/`, `Models/`, `ViewModels/`, `Views/`, `Resources/`
- `scripts/` for reusable local operations and packaging helpers
- `README.md` and `scripts/README.md` for operator-facing documentation

## Local-only paths

These paths are intentionally ignored so they do not get swept into normal commits:

- `.env`
  Local API keys and secrets.
- `build/`
  Temporary packaging and Xcode export workspaces.
- `dist/`
  Built DMGs, IPAs, and package metadata.
- `local/`
  Scratch files, ad hoc commands, exported zips, and one-off generated samples.
- `recipe_card_ai_cli/.venv/`
  Python virtual environment.
- `recipe_card_ai_cli/build/`
  Python build output.
- `recipe_card_ai_cli/*.egg-info/`
  Python packaging metadata.
- `recipe_card_ai_cli/output/`
  Generated recipe-card sample images.
- `recipe_card_ai_cli/`
  Local companion workspace for the standalone Python recipe-card generator.

## Where files should live

- App release artifacts: `dist/`
- Temporary package build workspaces: `build/`
- Python tool outputs from `recipe-card-ai`: `recipe_card_ai_cli/output/`
- One-off manual samples or scratch commands: `local/`
- Reusable packaging assets: `scripts/assets/`
- Reusable docs for scripts: `scripts/README.md`

## Recommended workflow

1. Keep reusable code and reusable docs in tracked locations.
2. Put temporary outputs under `dist/`, `build/`, `recipe_card_ai_cli/output/`, or `local/`.
3. Keep secrets only in `.env` or shell environment variables.
4. Before committing, check `git status --short` and confirm only intentional source changes remain.
