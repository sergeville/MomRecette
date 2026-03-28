#!/usr/bin/env python3
"""
convert_recipes.py
------------------
Converts Word (.doc / .docx) and text recipe files from "recettes 2/"
into a single momrecette.json ready to import into the MomRecette app.

Usage:
    pip install python-docx
    python3 convert_recipes.py

Output:
    momrecette.json   (place in Files app or AirDrop to your device)
"""

import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

# ── Config ──────────────────────────────────────────────────────────────────
SOURCE_DIR = Path(__file__).parent.parent / "recettes 2"
OUTPUT_FILE = Path(__file__).parent / "momrecette.json"

# Category keywords (French)
CATEGORY_MAP = {
    "Desserts":    ["gateau", "gâteau", "tarte", "biscuit", "muffin", "pouding", "fondant",
                    "creme", "crème", "glacage", "glaçage", "buche", "bûche", "barre",
                    "carré", "carre", "fondue au chocolat", "stuffed banana", "peanut butter pie"],
    "Soupes":      ["soupe", "bouillon", "velouté", "veloute", "chaudree", "chaudrée",
                    "chowder", "harira", "won ton", "tonkinoise"],
    "Salades":     ["salade"],
    "Sauces":      ["sauce", "vinaigrette", "coulis", "pesto", "marinade", "relish", "chutney",
                    "moutarde", "sel sante", "sel santé"],
    "Fondues":     ["fondue"],
    "Entrées":     ["creton", "créton", "coquille", "mousse", "ramequin", "petoncle",
                    "pétoncle", "feuillete", "feuilleté", "amuse", "boule au fromage",
                    "bouchee", "bouchée", "mini cornet", "hummus", "egg roll",
                    "rouleaux", "roules", "roulés"],
    "Plats":       ["poulet", "boeuf", "bœuf", "veau", "porc", "poisson", "dore",
                    "doré", "saumon", "crevettes", "fondue japonaise", "fondue thai",
                    "brochette", "filet", "tournedos", "feves", "fèves", "curry",
                    "pasta", "pates", "pâtes", "spaghetti", "quesadilla", "chicken",
                    "beef", "fish", "tofu", "dinde", "cipate", "meat"],
    "Pâtisseries": ["pain", "beignes", "croissant", "naan", "pizza", "pate a",
                    "pâte à", "pate pour"],
}

DEFAULT_CATEGORY = "Autres"


def detect_category(name: str) -> str:
    low = name.lower()
    for cat, keywords in CATEGORY_MAP.items():
        if any(k in low for k in keywords):
            return cat
    return DEFAULT_CATEGORY


def read_docx(path: Path) -> str:
    """Extract text from .docx file."""
    try:
        from docx import Document
        doc = Document(str(path))
        return "\n".join(p.text for p in doc.paragraphs if p.text.strip())
    except Exception as e:
        return ""


def read_doc_textutil(path: Path) -> str:
    """Use macOS textutil to convert old .doc → plain text."""
    import subprocess
    try:
        result = subprocess.run(
            ["textutil", "-stdout", "-convert", "txt", str(path)],
            capture_output=True, text=True, timeout=10
        )
        return result.stdout
    except Exception:
        return ""


def parse_text_to_recipe(name: str, text: str) -> dict:
    """
    Smart heuristic parser: classifies each line as ingredient, step, or note
    based on content — works even without section headers.
    """
    # Split long paragraphs at sentence boundaries first
    raw_lines = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        # If line is a long paragraph (>120 chars), split at sentence endings
        if len(line) > 120:
            sentences = re.split(r'(?<=[.!?])\s+', line)
            raw_lines.extend(s.strip() for s in sentences if s.strip())
        else:
            raw_lines.append(line)

    ingredients = []
    steps = []
    notes_lines = []

    # ── Section header patterns ──────────────────────────────────────────────
    INGREDIENTS_HEADERS = re.compile(
        r"^(ingr[eé]dients?|vous aurez besoin|il faut|pour la recette|pour le|pour la)", re.I
    )
    STEPS_HEADERS = re.compile(
        r"^(pr[eé]paration|m[eé]thode|instructions?|[eé]tapes?|proc[eé]d[eé]|"
        r"pr[eé]parer|cuisson|sauce|garniture|finition|finale)", re.I
    )
    NOTES_HEADERS = re.compile(r"^(notes?|remarques?|conseils?|trucs?|suggestion)", re.I)
    SECTION_LABEL = re.compile(r"^[A-ZÀÂÉÈÊÎÔÙÛŒÆÇ][A-ZÀÂÉÈÊÎÔÙÛŒÆÇ\s]{3,}$")

    # ── Ingredient indicators ────────────────────────────────────────────────
    MEASURE_WORDS = re.compile(
        r"\b(tasse|tasses|c\.?\s*[àa]\s*(th[eé]|soupe|table|s\b|t\b)|ml|cl|dl|"
        r"\bg\b|kg|lb|oz|litre|litres|l\b|bte|boite|boîte|sachet|pincée|pincee|"
        r"gousse|gousses|tranche|tranches|branche|branches|feuille|feuilles|"
        r"paquet|paquets|boîtes|pkg|poign[eé]e|filet|cube|cubes)\b", re.I
    )
    STARTS_QUANTITY = re.compile(r"^[\d½¼¾⅓⅔⅛\s/]+")
    FRACTION_LEAD = re.compile(r"^[½¼¾⅓⅔⅛]")

    # ── Step indicators ──────────────────────────────────────────────────────
    COOKING_VERBS = re.compile(
        r"^(cuire|ajouter|m[eé]langer|verser|faire|pr[eé]chauffer|incorporer|"
        r"d[eé]poser|couvrir|retirer|servir|garnir|r[eé]duire|[eé]goutter|"
        r"r[oô]tir|brunir|fondre|dissoudre|battre|fouetter|saupoudrer|arroser|"
        r"enfourner|d[eé]glacer|mijoter|porter|amener|chauffer|hacher|couper|"
        r"trancher|[eé]mincer|[eé]plucher|peler|laver|rincer|m[eé]langer|"
        r"mettre|placer|r[eé]server|dans une|dans un|sur un|en ajouter|bien|"
        r"laisser|sortir|retourner|griller|r[eé]partir|d[eé]congeler|cuisson|"
        r"assaisonner|saler|poivrer|parsemer|d[eé]corer|napper|d[eé]molir|"
        r"[eé]goutter|pr[eé]parer|combiner|m[eé]langer|d[eé]geler|[eé]taler|"
        r"piquer|badigeonner|r[eé]duire|filtrer|tamiser|d[eé]canter)", re.I
    )

    def is_ingredient_line(line):
        low = line.lower()
        if MEASURE_WORDS.search(low):
            return True
        first_char = line[0] if line else ''
        if first_char.isdigit() or FRACTION_LEAD.match(line):
            # starts with a number/fraction and is short
            if len(line) < 70:
                return True
        return False

    def is_step_line(line):
        if COOKING_VERBS.match(line.lower()):
            return True
        # Long lines without measurement words are steps
        if len(line) > 70 and not MEASURE_WORDS.search(line.lower()):
            return True
        return False

    def extract_ingredient(line):
        """Split a line into (quantity, name)."""
        # Match: quantity + rest
        m = re.match(
            r'^([\d½¼¾⅓⅔⅛][^,]*?'
            r'(?:tasse|tasses|c\.?\s*[àa]\s*\w+|ml|cl|g\b|kg|lb|oz|litre|l\b|'
            r'bte|sachet|gousse\w*|tranche\w*|branche\w*|feuille\w*|pincée|pincee)?'
            r'\s*(?:de\s+|d\')?\s*)'
            r'(.+)', line, re.I
        )
        if m:
            return m.group(1).strip(), m.group(2).strip()
        return "", line

    mode = "unknown"

    for line in raw_lines:
        # Skip recipe title (first line often repeats name)
        if line.upper() == name.upper() or line.upper() == name.upper().strip():
            continue

        # Section header detection
        if INGREDIENTS_HEADERS.match(line):
            mode = "ingredients"
            continue
        if STEPS_HEADERS.match(line):
            mode = "steps"
            continue
        if NOTES_HEADERS.match(line):
            mode = "notes"
            continue
        # ALL-CAPS section label (e.g. "LA SAUCE", "PREPARATION FINALE")
        if SECTION_LABEL.match(line) and len(line) < 40:
            low = line.lower()
            if any(w in low for w in ["sauce", "garniture", "finition", "finale", "preparation", "préparation"]):
                mode = "steps"
            else:
                mode = "ingredients"
            continue

        # Strip leading step numbers
        clean = re.sub(r"^[\d]+[.)]\s*", "", line)

        if mode == "ingredients":
            qty, food = extract_ingredient(clean)
            ingredients.append({"quantity": qty, "name": food})
        elif mode == "steps":
            steps.append(clean)
        elif mode == "notes":
            notes_lines.append(clean)
        else:
            # Content-based classification (no header found yet)
            if is_step_line(clean):
                mode = "steps"
                steps.append(clean)
            elif is_ingredient_line(clean):
                if mode != "steps":  # don't go back to ingredients after steps started
                    qty, food = extract_ingredient(clean)
                    ingredients.append({"quantity": qty, "name": food})
                else:
                    steps.append(clean)
            else:
                # Short ambiguous line: ingredient if we haven't hit steps yet
                if not steps and len(clean) < 60:
                    ingredients.append({"quantity": "", "name": clean})
                else:
                    steps.append(clean)

    return {
        "id": str(uuid.uuid4()),
        "name": name,
        "category": detect_category(name),
        "servings": 4,
        "prepTime": 20,
        "cookTime": 30,
        "ingredients": ingredients[:40],   # cap at 40
        "steps": steps[:30],               # cap at 30
        "notes": " ".join(notes_lines),
        "createdAt": datetime.now(timezone.utc).isoformat()
    }


def recipe_name_from_path(path: Path) -> str:
    """Convert filename to readable recipe name."""
    stem = path.stem
    # Remove trailing numbers/copy suffixes
    stem = re.sub(r'\s*\d+\s*$', '', stem)
    stem = re.sub(r'\s*-\s*copie\s*$', '', stem, flags=re.I)
    stem = stem.strip()
    # Title-case: capitalize each word, handle accented chars correctly
    words = stem.replace('_', ' ').split()
    SMALL = {'a', 'au', 'aux', 'de', 'des', 'du', 'et', 'en', 'la', 'le', 'les',
             'ou', 'par', 'sur', 'un', 'une', 'avec', 'sans', 'pour'}
    result = []
    for i, w in enumerate(words):
        if i == 0 or w.lower() not in SMALL:
            result.append(w.capitalize())
        else:
            result.append(w.lower())
    return ' '.join(result)


def main():
    if not SOURCE_DIR.exists():
        print(f"Source directory not found: {SOURCE_DIR}")
        return

    files = sorted(SOURCE_DIR.iterdir())
    recipes = []
    skipped = []

    for f in files:
        suffix = f.suffix.lower()
        if suffix not in (".doc", ".docx", ".odt", ".rtf"):
            continue

        name = recipe_name_from_path(f)
        text = ""

        if suffix == ".docx":
            text = read_docx(f)
        elif suffix in (".doc", ".odt", ".rtf"):
            text = read_doc_textutil(f)

        if not text:
            # Still add with name only
            text = ""

        recipe = parse_text_to_recipe(name, text)
        recipes.append(recipe)
        print(f"  ✓  {name}  [{recipe['category']}]  "
              f"({len(recipe['ingredients'])} ingr., {len(recipe['steps'])} étapes)")

    # Deduplicate by name
    seen = set()
    unique = []
    for r in recipes:
        key = r["name"].lower().strip()
        if key not in seen:
            seen.add(key)
            unique.append(r)

    output = json.dumps(unique, ensure_ascii=False, indent=2)
    OUTPUT_FILE.write_text(output, encoding="utf-8")

    print(f"\n✅  {len(unique)} recettes exportées → {OUTPUT_FILE}")
    print(f"   AirDrop ce fichier sur votre iPhone/iPad/Mac,")
    print(f"   puis utilisez 'Importer JSON' dans MomRecette.")


if __name__ == "__main__":
    main()
