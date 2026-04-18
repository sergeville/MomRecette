#!/usr/bin/env python3
"""
Batch utilities for the MomRecette recipe photo pack.

Main use cases:
  - report how many recipes still need photos
  - export a CSV template for missing recipes
  - apply a CSV manifest of local file paths and/or direct image URLs
"""

from __future__ import annotations

import argparse
import csv
import json
import urllib.parse
from pathlib import Path

import recipe_photo_helper as helper


def get_recipes() -> list[dict]:
    with helper.RECIPES_BUNDLE_PATH.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    return [entry for entry in payload if isinstance(entry, dict) and entry.get("name")]


def normalize_category(category: str | None) -> str | None:
    if not category:
        return None
    folded = helper.folded_for_matching(category)
    known = sorted({recipe.get("category", "") for recipe in get_recipes()})
    for item in known:
        if helper.folded_for_matching(item) == folded:
            return item
    raise SystemExit(
        f"Unknown category: {category}\nValid categories: {', '.join(known)}"
    )


def get_recipe_names(category: str | None = None) -> list[str]:
    normalized_category = normalize_category(category)
    recipes = get_recipes()
    if normalized_category:
        recipes = [recipe for recipe in recipes if recipe.get("category") == normalized_category]
    return [recipe["name"] for recipe in recipes]


def photo_exists(recipe_name: str) -> bool:
    slug = helper.photo_lookup_key(recipe_name)
    return helper.find_existing_photo(slug) is not None


def missing_recipe_names(category: str | None = None) -> list[str]:
    return [name for name in get_recipe_names(category) if not photo_exists(name)]


def print_status(category: str | None = None) -> int:
    names = get_recipe_names(category)
    missing = missing_recipe_names(category)
    with_photos = len(names) - len(missing)
    category_label = normalize_category(category)

    if category_label:
        print(f"Category: {category_label}")

    print(f"Total recipes: {len(names)}")
    print(f"With photos: {with_photos}")
    print(f"Missing photos: {len(missing)}")

    if missing:
        print("Sample missing:")
        for name in missing[:10]:
            print(f"  - {name}")

    return 0


def export_missing_csv(output_path: Path, category: str | None = None) -> int:
    rows = [
        {
            "recipe_name": name,
            "slug": helper.photo_lookup_key(name),
            "file_path": "",
            "image_url": "",
            "notes": "",
        }
        for name in missing_recipe_names(category)
    ]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["recipe_name", "slug", "file_path", "image_url", "notes"],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote missing-photo template: {output_path}")
    print(f"Rows: {len(rows)}")
    return 0


def print_searches(limit: int, category: str | None = None, open_in_browser: bool = False) -> int:
    names = missing_recipe_names(category)[:limit]
    category_label = normalize_category(category)

    if not names:
        print("No missing recipes matched the current filter.")
        return 0

    if category_label:
        print(f"Category: {category_label}")

    print(f"Search targets: {len(names)}")
    for name in names:
        url = f"https://www.google.com/search?tbm=isch&q={urllib.parse.quote_plus(name)}"
        print(f"- {name}")
        print(f"  {url}")
        if open_in_browser:
            helper.open_search(name)

    return 0


def apply_manifest(manifest_path: Path, overwrite: bool) -> int:
    if not manifest_path.exists():
        raise SystemExit(f"Manifest not found: {manifest_path}")

    applied = 0
    skipped = 0
    errors: list[str] = []

    with manifest_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"recipe_name", "file_path", "image_url"}
        if not required.issubset(reader.fieldnames or set()):
            raise SystemExit(
                "Manifest must contain these columns: recipe_name,file_path,image_url"
            )

        for line_number, row in enumerate(reader, start=2):
            recipe_query = (row.get("recipe_name") or "").strip()
            file_path = (row.get("file_path") or "").strip()
            image_url = (row.get("image_url") or "").strip()

            if not recipe_query:
                skipped += 1
                continue

            if not file_path and not image_url:
                skipped += 1
                continue

            try:
                recipe_name = helper.resolve_recipe_name(recipe_query, get_recipe_names())
                slug = helper.photo_lookup_key(recipe_name)

                if file_path and image_url:
                    raise SystemExit("Use either file_path or image_url, not both.")

                source_path = Path(file_path).expanduser().resolve() if file_path else None
                if source_path and not source_path.exists():
                    raise SystemExit(f"Image file not found: {source_path}")

                destination_ext = (
                    source_path.suffix.lower()
                    if source_path
                    else helper.infer_extension_from_url(image_url)
                )
                destination = helper.PHOTOS_DIR / f"{slug}{destination_ext}"
                existing = helper.find_existing_photo(slug)

                if existing and existing != destination and not overwrite:
                    raise SystemExit(
                        f"Existing photo already present: {existing}. Use --overwrite to replace it."
                    )
                if destination.exists() and not overwrite:
                    raise SystemExit(
                        f"Destination already exists: {destination}. Use --overwrite to replace it."
                    )

                if source_path:
                    helper.save_from_file(source_path, destination)
                else:
                    helper.save_from_url(image_url, destination)

                applied += 1
                print(f"[ok] {recipe_name} -> {destination.name}")
            except Exception as exc:
                errors.append(f"line {line_number}: {recipe_query}: {exc}")

    print(f"Applied: {applied}")
    print(f"Skipped: {skipped}")
    print(f"Errors: {len(errors)}")
    for item in errors[:20]:
        print(f"  - {item}")

    return 1 if errors else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Batch workflow for MomRecette recipe photos."
    )
    parser.add_argument(
        "--category",
        help="Optional recipe category filter, e.g. Plats or Desserts.",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Show how many recipes already have bundled photos.",
    )
    parser.add_argument(
        "--export-missing",
        metavar="CSV_PATH",
        help="Write a CSV template for recipes still missing photos.",
    )
    parser.add_argument(
        "--apply",
        metavar="CSV_PATH",
        help="Apply a CSV manifest with file_path and/or image_url values.",
    )
    parser.add_argument(
        "--print-searches",
        metavar="COUNT",
        type=int,
        help="Print Google Images search URLs for the next missing recipes.",
    )
    parser.add_argument(
        "--open-searches",
        metavar="COUNT",
        type=int,
        help="Open Google Images searches for the next missing recipes in the browser.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace existing photos when applying a manifest.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not any([args.status, args.export_missing, args.apply, args.print_searches, args.open_searches]):
        return print_status(args.category)

    exit_code = 0

    if args.status:
        exit_code = max(exit_code, print_status(args.category))
    if args.export_missing:
        exit_code = max(
            exit_code,
            export_missing_csv(Path(args.export_missing).expanduser(), args.category),
        )
    if args.print_searches:
        exit_code = max(exit_code, print_searches(args.print_searches, args.category))
    if args.open_searches:
        exit_code = max(
            exit_code,
            print_searches(args.open_searches, args.category, open_in_browser=True),
        )
    if args.apply:
        exit_code = max(exit_code, apply_manifest(Path(args.apply).expanduser(), args.overwrite))

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
