#!/usr/bin/env python3
"""
Attach a meal photo to an existing MomRecette recipe.

The app already auto-loads bundled images from:
    Resources/RecipePhotos/<normalized-recipe-name>.<ext>

This helper validates the recipe name against the seed bundle, normalizes the
filename the same way as the Swift app, and then either:
    - copies a local image file
    - downloads an image from a direct image URL
    - prints/open a search URL to help you find one manually
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RECIPES_BUNDLE_PATH = PROJECT_ROOT / "Resources" / "momrecette_bundle.json"
BUNDLED_PHOTOS_DIR = PROJECT_ROOT / "Resources" / "RecipePhotos"
LIVE_PHOTOS_DIR = Path.home() / "Library" / "Containers" / "com.villeneuves.MomRecette" / "Data" / "Documents" / "RecipePhotos"
PHOTOS_DIR = BUNDLED_PHOTOS_DIR
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def folded_for_matching(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(ch for ch in normalized if not unicodedata.combining(ch)).lower()


def photo_lookup_key(value: str) -> str:
    folded = folded_for_matching(value).replace("&", " and ")
    pieces = re.split(r"[^a-z0-9]+", folded)
    return "-".join(piece for piece in pieces if piece)


def load_recipe_names() -> list[str]:
    with RECIPES_BUNDLE_PATH.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    return [entry["name"] for entry in payload if isinstance(entry, dict) and entry.get("name")]


def resolve_recipe_name(recipe_query: str, recipe_names: list[str]) -> str:
    direct_match = next(
        (name for name in recipe_names if name.casefold() == recipe_query.casefold()),
        None,
    )
    if direct_match:
        return direct_match

    normalized_query = photo_lookup_key(recipe_query)
    normalized_matches = [name for name in recipe_names if photo_lookup_key(name) == normalized_query]
    if len(normalized_matches) == 1:
        return normalized_matches[0]

    suggestions = difflib.get_close_matches(recipe_query, recipe_names, n=5, cutoff=0.45)
    available = "\n".join(f"  - {item}" for item in suggestions) or "  (no close match found)"
    raise SystemExit(
        "Recipe not found in momrecette_bundle.json.\n"
        f"Requested: {recipe_query}\n"
        f"Suggestions:\n{available}"
    )


def infer_extension_from_url(url: str) -> str:
    path_ext = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if path_ext in ALLOWED_EXTENSIONS:
        return path_ext
    return ".jpg"


def ensure_supported_extension(path: Path) -> None:
    if path.suffix.lower() not in ALLOWED_EXTENSIONS:
        allowed = ", ".join(sorted(ALLOWED_EXTENSIONS))
        raise SystemExit(f"Unsupported image format: {path.suffix or '(none)'}\nAllowed: {allowed}")


def target_directories(target: str) -> list[Path]:
    if target == "bundled":
        return [BUNDLED_PHOTOS_DIR]
    if target == "live":
        return [LIVE_PHOTOS_DIR]
    if target == "both":
        return [LIVE_PHOTOS_DIR, BUNDLED_PHOTOS_DIR]
    raise ValueError(f"Unknown target: {target}")


def find_existing_photo(slug: str, target: str = "both") -> Path | None:
    for directory in target_directories(target):
        for ext in sorted(ALLOWED_EXTENSIONS):
            candidate = directory / f"{slug}{ext}"
            if candidate.exists():
                return candidate
    return None


def save_from_file(source: Path, destination: Path) -> None:
    ensure_supported_extension(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def remove_sibling_variants(destination: Path) -> None:
    stem = destination.stem
    for ext in sorted(ALLOWED_EXTENSIONS):
        candidate = destination.parent / f"{stem}{ext}"
        if candidate == destination or not candidate.exists():
            continue
        candidate.unlink()


def normalized_request_url(url: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    path = urllib.parse.quote(parsed.path, safe="/%")
    query = urllib.parse.quote(parsed.query, safe="=&?/%:+,;")
    fragment = urllib.parse.quote(parsed.fragment, safe="")
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, path, query, fragment))


def save_from_url(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        normalized_request_url(url),
        headers={
            "User-Agent": "MomRecette recipe photo helper/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        content_type = response.headers.get("Content-Type", "")
        if not content_type.startswith("image/"):
            raise SystemExit(f"URL did not return an image. Content-Type: {content_type or 'unknown'}")
        data = response.read()
    destination.write_bytes(data)


def print_status(recipe_name: str, slug: str) -> None:
    bundled_existing = find_existing_photo(slug, target="bundled")
    live_existing = find_existing_photo(slug, target="live")
    print(f"Recipe: {recipe_name}")
    print(f"Photo key: {slug}")
    print(f"Bundled photo: {bundled_existing or 'none'}")
    print(f"Live photo: {live_existing or 'none'}")
    print(f"Bundled directory: {BUNDLED_PHOTOS_DIR}")
    print(f"Live directory: {LIVE_PHOTOS_DIR}")


def open_search(recipe_name: str) -> None:
    query = urllib.parse.quote_plus(recipe_name)
    url = f"https://www.google.com/search?tbm=isch&q={query}"
    try:
        subprocess.run(["open", url], check=True)
        print(f"Opened search in browser: {url}")
    except Exception:
        print(f"Search URL: {url}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Attach a meal photo to a chosen MomRecette recipe."
    )
    parser.add_argument("recipe", help="Recipe name to match from momrecette_bundle.json")
    parser.add_argument("--file", dest="file_path", help="Local image file to copy into RecipePhotos")
    parser.add_argument("--url", dest="image_url", help="Direct image URL to download into RecipePhotos")
    parser.add_argument(
        "--search",
        action="store_true",
        help="Open a browser image search for the chosen recipe",
    )
    parser.add_argument(
        "--status",
        action="store_true",
        help="Print the normalized filename and whether a photo already exists",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing photo if one is already present",
    )
    parser.add_argument(
        "--target",
        choices=["bundled", "live", "both"],
        default="bundled",
        help="Where to save the photo. Use 'live' or 'both' for auto-refresh while the app is running.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    recipe_names = load_recipe_names()
    recipe_name = resolve_recipe_name(args.recipe, recipe_names)
    slug = photo_lookup_key(recipe_name)

    if args.status or (not args.file_path and not args.image_url and not args.search):
        print_status(recipe_name, slug)

    if args.search:
        open_search(recipe_name)

    if args.file_path and args.image_url:
        raise SystemExit("Use either --file or --url, not both.")

    if not args.file_path and not args.image_url:
        return 0

    source_path = Path(args.file_path).expanduser().resolve() if args.file_path else None
    if source_path and not source_path.exists():
        raise SystemExit(f"Image file not found: {source_path}")

    destination_ext = source_path.suffix.lower() if source_path else infer_extension_from_url(args.image_url)
    destinations = [directory / f"{slug}{destination_ext}" for directory in target_directories(args.target)]

    for destination in destinations:
        existing = find_existing_photo(slug, target="both")
        if existing and existing != destination and not args.overwrite and destination.parent != existing.parent:
            pass
        if destination.exists() and not args.overwrite:
            raise SystemExit(f"Destination already exists: {destination}\nUse --overwrite to replace it.")

    for destination in destinations:
        if args.overwrite:
            remove_sibling_variants(destination)

        if source_path:
            save_from_file(source_path, destination)
            print(f"Saved local image for '{recipe_name}' -> {destination}")
        else:
            save_from_url(args.image_url, destination)
            print(f"Downloaded image for '{recipe_name}' -> {destination}")

    if args.target in {"live", "both"}:
        print("The running app can auto-refresh this photo from the live container folder.")
    else:
        print("The app will pick this bundled photo up on next launch if the recipe does not already have imageData saved.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
