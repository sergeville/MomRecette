#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RECIPES_PATH = REPO_ROOT / "momrecette.json"
INLINE_MEASURE_PATTERN = re.compile(
    r"\b(\d+([/.]\d+)?|[¼½¾])\b|\b(tasse|tasses|c\.?\s*a|boite|bte|lb|kg|g|ml|l)\b",
    re.IGNORECASE,
)
NAME_STARTS_WITH_MEASURE_PATTERN = re.compile(
    r"^\s*([¼½¾]|\d+([/.]\d+)?|/\d+|c\.?\s*a|tasse|lb|kg|ml|l)\b",
    re.IGNORECASE,
)
HEADER_LIKE_PATTERN = re.compile(r"^[A-Z0-9 ()'’:/-]{8,}$")


@dataclass(frozen=True)
class Issue:
    code: str
    message: str
    severity: str


def load_recipes(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def audit_recipe(recipe: dict[str, Any]) -> list[Issue]:
    issues: list[Issue] = []
    name = (recipe.get("name") or "").strip()

    if not name:
        issues.append(Issue("recipe_name_missing", "Recipe name is empty.", "error"))
    elif name.lower() == "untitled":
        issues.append(Issue("recipe_name_placeholder", "Recipe name is still 'Untitled'.", "warning"))
    if name.count("(") != name.count(")"):
        issues.append(Issue("recipe_name_unbalanced_parentheses", "Recipe name has unbalanced parentheses.", "warning"))

    servings = recipe.get("servings")
    if not isinstance(servings, int) or servings <= 0:
        issues.append(Issue("servings_invalid", "Servings must be a positive integer.", "error"))

    for field in ("prepTime", "cookTime"):
        value = recipe.get(field)
        if not isinstance(value, int) or value < 0:
            issues.append(Issue(f"{field}_invalid", f"{field} must be a non-negative integer.", "error"))

    ingredients = recipe.get("ingredients") or []
    if not ingredients:
        issues.append(Issue("ingredients_missing", "Recipe has no ingredients.", "error"))
    else:
        for index, ingredient in enumerate(ingredients, start=1):
            quantity = (ingredient.get("quantity") or "").strip()
            ingredient_name = (ingredient.get("name") or "").strip()
            label = f"Ingredient {index}"

            if not ingredient_name:
                issues.append(Issue("ingredient_name_missing", f"{label} is missing a name.", "error"))
                continue

            if not quantity and INLINE_MEASURE_PATTERN.search(ingredient_name):
                issues.append(
                    Issue(
                        "ingredient_quantity_embedded_in_name",
                        f"{label} likely has quantity/unit text embedded in the ingredient name: '{ingredient_name}'.",
                        "warning",
                    )
                )

            if not quantity and HEADER_LIKE_PATTERN.match(ingredient_name):
                issues.append(
                    Issue(
                        "ingredient_header_like",
                        f"{label} looks like a pasted header or note instead of a structured ingredient: '{ingredient_name}'.",
                        "warning",
                    )
                )

            if quantity and NAME_STARTS_WITH_MEASURE_PATTERN.match(ingredient_name):
                issues.append(
                    Issue(
                        "ingredient_split_suspicious",
                        f"{label} looks split incorrectly between quantity and name: '{quantity}' + '{ingredient_name}'.",
                        "warning",
                    )
                )

    steps = recipe.get("steps") or []
    if not steps:
        issues.append(Issue("steps_missing", "Recipe has no preparation steps.", "error"))
    else:
        empty_steps = [index for index, step in enumerate(steps, start=1) if not (step or "").strip()]
        for index in empty_steps:
            issues.append(Issue("step_empty", f"Step {index} is empty.", "warning"))

        non_empty_steps = [(index, (step or "").strip()) for index, step in enumerate(steps, start=1) if (step or "").strip()]
        if non_empty_steps:
            no_punctuation = [index for index, step in non_empty_steps if step[-1] not in ".!?"]
            if no_punctuation:
                issues.append(
                    Issue(
                        "steps_terminal_punctuation_inconsistent",
                        f"{len(no_punctuation)} step(s) do not end with punctuation.",
                        "info",
                    )
                )

    return issues


def build_report(recipes: list[dict[str, Any]]) -> dict[str, Any]:
    per_recipe: list[dict[str, Any]] = []
    issue_counts = Counter()
    severity_counts = Counter()

    for recipe in sorted(recipes, key=lambda item: (item.get("name") or "").lower()):
        issues = audit_recipe(recipe)
        if not issues:
            continue

        for issue in issues:
            issue_counts[issue.code] += 1
            severity_counts[issue.severity] += 1

        per_recipe.append(
            {
                "name": recipe.get("name") or "",
                "issue_count": len(issues),
                "issues": [
                    {"code": issue.code, "severity": issue.severity, "message": issue.message}
                    for issue in issues
                ],
            }
        )

    return {
        "recipe_count": len(recipes),
        "recipes_with_issues": len(per_recipe),
        "issue_counts": dict(issue_counts.most_common()),
        "severity_counts": dict(severity_counts),
        "recipes": per_recipe,
    }


def render_markdown(report: dict[str, Any], limit: int | None) -> str:
    lines = [
        "# MomRecette Recipe Audit",
        "",
        f"- Recipes scanned: {report['recipe_count']}",
        f"- Recipes with issues: {report['recipes_with_issues']}",
        "",
        "## Issue Summary",
        "",
    ]

    for code, count in report["issue_counts"].items():
        lines.append(f"- `{code}`: {count}")

    recipes = report["recipes"]
    if limit is not None:
        recipes = recipes[:limit]

    lines.extend(["", "## Per-Recipe Findings", ""])
    for recipe in recipes:
        lines.append(f"### {recipe['name']} ({recipe['issue_count']})")
        for issue in recipe["issues"]:
            lines.append(f"- `{issue['severity']}` `{issue['code']}`: {issue['message']}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def render_text(report: dict[str, Any], limit: int | None) -> str:
    lines = [
        f"Recipes scanned: {report['recipe_count']}",
        f"Recipes with issues: {report['recipes_with_issues']}",
        "Issue summary:",
    ]
    for code, count in report["issue_counts"].items():
        lines.append(f"  - {code}: {count}")

    recipes = report["recipes"]
    if limit is not None:
        recipes = recipes[:limit]

    lines.append("")
    for recipe in recipes:
        lines.append(f"{recipe['name']} ({recipe['issue_count']})")
        for issue in recipe["issues"]:
            lines.append(f"  - [{issue['severity']}] {issue['code']}: {issue['message']}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit MomRecette recipes for structural and formatting drift.")
    parser.add_argument("--recipes", type=Path, default=DEFAULT_RECIPES_PATH, help="Path to the recipes JSON file.")
    parser.add_argument(
        "--format",
        choices=("text", "markdown", "json"),
        default="text",
        help="Report output format.",
    )
    parser.add_argument("--limit", type=int, default=None, help="Limit the number of per-recipe sections.")
    parser.add_argument("--output", type=Path, default=None, help="Write the report to a file instead of stdout.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    recipes = load_recipes(args.recipes)
    report = build_report(recipes)

    if args.format == "json":
        output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    elif args.format == "markdown":
        output = render_markdown(report, args.limit)
    else:
        output = render_text(report, args.limit)

    if args.output is not None:
        args.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
