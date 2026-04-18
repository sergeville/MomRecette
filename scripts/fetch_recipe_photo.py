#!/usr/bin/env python3
"""
Search recipe pages on the web, extract a likely hero image, and save it into
the MomRecette photo pack using the same filename rules as recipe_photo_helper.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from html.parser import HTMLParser

import recipe_photo_helper as helper


USER_AGENT = "MomRecette recipe photo fetcher/1.0"
SEARCH_URLS = [
    "https://duckduckgo.com/html/?q={query}",
    "https://html.duckduckgo.com/html/?q={query}",
    "https://lite.duckduckgo.com/lite/?q={query}",
]
KNOWN_RECIPE_DOMAINS = {
    "allrecipes.com": 10,
    "atelierdeschefs.fr": 8,
    "bbcgoodfood.com": 8,
    "coupdepouce.com": 12,
    "food.com": 6,
    "glouton.app": 8,
    "karo.com": 5,
    "karosyrup.com": 8,
    "kingarthurbaking.com": 8,
    "lepoulet.qc.ca": 8,
    "leslubiesdecadia.com": 6,
    "macuisinesante.com": 8,
    "passionrecettes.com": 9,
    "radio-canada.ca": 8,
    "recettes-asselin.com": 7,
    "recettes.qc.ca": 10,
    "ricardocuisine.com": 12,
    "supertoinette.com": 8,
    "thekitchn.com": 6,
}
BAD_IMAGE_HINTS = {
    "avatar",
    "blank",
    "button",
    "favicon",
    "icon",
    "logo",
    "placeholder",
    "pixel",
    "sprite",
    "thumb",
    "thumbnail",
    "tracking",
}
GOOD_IMAGE_HINTS = {
    "dish",
    "featured",
    "food",
    "hero",
    "main",
    "photo",
    "plate",
    "post",
    "recipe",
}
BAD_RESULT_DOMAINS = {
    "duckduckgo.com",
    "google.com",
    "images.google.com",
    "youtube.com",
    "facebook.com",
    "instagram.com",
    "pinterest.com",
    "tiktok.com",
    "x.com",
    "twitter.com",
}


@dataclass
class SearchResult:
    url: str
    title: str
    score: int


@dataclass
class ImageCandidate:
    page_url: str
    image_url: str
    score: int
    source: str
    detail: str = ""


class SearchResultsParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str, str]] = []
        self._capture_title = False
        self._current_href: str | None = None
        self._current_class: str = ""
        self._text_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        if tag == "a":
            href = attrs_dict.get("href")
            if not href:
                return
            class_name = attrs_dict.get("class", "") or ""
            self._capture_title = True
            self._current_href = href
            self._current_class = class_name
            self._text_parts = []

    def handle_data(self, data: str) -> None:
        if self._capture_title:
            self._text_parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._capture_title and self._current_href:
            title = " ".join(part.strip() for part in self._text_parts if part.strip())
            self.links.append((self._current_href, title, self._current_class))
            self._capture_title = False
            self._current_href = None
            self._current_class = ""
            self._text_parts = []


class RecipePageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.meta_tags: list[dict[str, str]] = []
        self.link_tags: list[dict[str, str]] = []
        self.image_tags: list[dict[str, str]] = []
        self.ld_json_blocks: list[str] = []
        self._capture_ld_json = False
        self._ld_json_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = {key: value or "" for key, value in attrs}
        if tag == "meta":
            self.meta_tags.append(attrs_dict)
        elif tag == "link":
            self.link_tags.append(attrs_dict)
        elif tag == "img":
            self.image_tags.append(attrs_dict)
        elif tag == "script":
            script_type = (attrs_dict.get("type") or "").lower()
            if "ld+json" in script_type:
                self._capture_ld_json = True
                self._ld_json_parts = []

    def handle_data(self, data: str) -> None:
        if self._capture_ld_json:
            self._ld_json_parts.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._capture_ld_json:
            payload = "".join(self._ld_json_parts).strip()
            if payload:
                self.ld_json_blocks.append(payload)
            self._capture_ld_json = False
            self._ld_json_parts = []


def fetch_url(url: str, *, accept: str | None = None) -> tuple[str, bytes, str]:
    headers = {"User-Agent": USER_AGENT}
    if accept:
        headers["Accept"] = accept
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        final_url = response.geturl()
        content_type = response.headers.get("Content-Type", "")
        data = response.read()
    return final_url, data, content_type


def fetch_text(url: str) -> tuple[str, str]:
    final_url, data, content_type = fetch_url(
        url,
        accept="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    )
    charset = "utf-8"
    match = re.search(r"charset=([A-Za-z0-9_-]+)", content_type)
    if match:
        charset = match.group(1)
    return final_url, data.decode(charset, errors="replace")


def domain_score(url: str) -> int:
    host = urllib.parse.urlparse(url).netloc.casefold()
    if host.startswith("www."):
        host = host[4:]
    return KNOWN_RECIPE_DOMAINS.get(host, 0)


def result_domain(url: str) -> str:
    host = urllib.parse.urlparse(url).netloc.casefold()
    return host[4:] if host.startswith("www.") else host


def decode_search_href(href: str) -> str | None:
    absolute = urllib.parse.urljoin("https://duckduckgo.com", href)
    parsed = urllib.parse.urlparse(absolute)
    query = urllib.parse.parse_qs(parsed.query)
    if "uddg" in query and query["uddg"]:
        return urllib.parse.unquote(query["uddg"][0])
    if parsed.scheme in {"http", "https"} and result_domain(absolute) not in BAD_RESULT_DOMAINS:
        return absolute
    return None


def is_plausible_result(url: str, title: str, class_name: str) -> bool:
    domain = result_domain(url)
    if domain in BAD_RESULT_DOMAINS:
        return False
    folded_title = title.casefold()
    folded_class = (class_name or "").casefold()
    if any(token in folded_class for token in {"nav", "menu", "header", "footer"}):
        return False
    if not title.strip():
        return False
    if domain_score(url) > 0:
        return True
    recipeish = {"recipe", "recette", "naan", "food", "cuisine"}
    return any(token in folded_title for token in recipeish)


def iter_search_queries(recipe_name: str) -> list[str]:
    return [
        f'"{recipe_name}" recipe',
        f'{recipe_name} recipe',
        recipe_name,
    ]


def search_recipe_pages(recipe_name: str, limit: int) -> list[SearchResult]:
    seen: set[str] = set()
    results: list[SearchResult] = []

    for query_rank, raw_query in enumerate(iter_search_queries(recipe_name)):
        query = urllib.parse.quote_plus(raw_query)
        for provider_rank, search_url in enumerate(SEARCH_URLS):
            try:
                _, html = fetch_text(search_url.format(query=query))
            except Exception:
                continue
            parser = SearchResultsParser()
            parser.feed(html)
            for href, title, class_name in parser.links:
                url = decode_search_href(href)
                if not url:
                    continue
                parsed = urllib.parse.urlparse(url)
                if parsed.scheme not in {"http", "https"}:
                    continue
                normalized = urllib.parse.urlunparse(
                    (parsed.scheme, parsed.netloc, parsed.path, "", parsed.query, "")
                )
                if normalized in seen:
                    continue
                if not is_plausible_result(url, title, class_name):
                    continue
                seen.add(normalized)
                score = domain_score(url)
                folded_title = title.casefold()
                if "recipe" in folded_title or "recette" in folded_title:
                    score += 4
                if recipe_name.casefold() in folded_title:
                    score += 6
                score += max(0, 4 - query_rank)
                score += max(0, 2 - provider_rank)
                results.append(SearchResult(url=url, title=title, score=score))
            if len(results) >= limit * 2:
                break
        if len(results) >= limit * 2:
            break

    results.sort(key=lambda item: item.score, reverse=True)
    return results[:limit]


def absolutize_url(base_url: str, candidate: str) -> str | None:
    candidate = (candidate or "").strip()
    if not candidate:
        return None
    if candidate.startswith("data:"):
        return None
    return urllib.parse.urljoin(base_url, candidate)


def image_url_penalty(url: str) -> int:
    folded = url.casefold()
    penalty = 0
    for hint in BAD_IMAGE_HINTS:
        if hint in folded:
            penalty -= 40
    return penalty


def image_url_bonus(text: str) -> int:
    folded = text.casefold()
    bonus = 0
    for hint in GOOD_IMAGE_HINTS:
        if hint in folded:
            bonus += 8
    return bonus


def coerce_image_values(value: object) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        items: list[str] = []
        for entry in value:
            items.extend(coerce_image_values(entry))
        return items
    if isinstance(value, dict):
        if isinstance(value.get("url"), str):
            return [value["url"]]
        if isinstance(value.get("@id"), str):
            return [value["@id"]]
    return []


def walk_recipe_objects(node: object) -> list[dict]:
    found: list[dict] = []
    if isinstance(node, dict):
        node_type = node.get("@type")
        if isinstance(node_type, list):
            type_names = {str(item).casefold() for item in node_type}
        else:
            type_names = {str(node_type).casefold()} if node_type else set()
        if "recipe" in type_names:
            found.append(node)
        for value in node.values():
            found.extend(walk_recipe_objects(value))
    elif isinstance(node, list):
        for item in node:
            found.extend(walk_recipe_objects(item))
    return found


def parse_ld_json_candidates(blocks: list[str], base_url: str) -> list[ImageCandidate]:
    candidates: list[ImageCandidate] = []
    for block in blocks:
        try:
            payload = json.loads(block)
        except json.JSONDecodeError:
            continue
        for recipe in walk_recipe_objects(payload):
            for image_url in coerce_image_values(recipe.get("image")):
                absolute = absolutize_url(base_url, image_url)
                if not absolute:
                    continue
                candidates.append(
                    ImageCandidate(
                        page_url=base_url,
                        image_url=absolute,
                        score=220 + domain_score(base_url) + image_url_penalty(absolute),
                        source="json-ld",
                        detail="Recipe.image",
                    )
                )
    return candidates


def parse_meta_candidates(parser: RecipePageParser, base_url: str) -> list[ImageCandidate]:
    candidates: list[ImageCandidate] = []
    for tag in parser.meta_tags:
        content = tag.get("content", "")
        if not content:
            continue
        key = (tag.get("property") or tag.get("name") or tag.get("itemprop") or "").casefold()
        score = 0
        detail = ""
        if key in {"og:image", "og:image:url"}:
            score = 190
            detail = key
        elif key in {"twitter:image", "twitter:image:src"}:
            score = 180
            detail = key
        elif key == "image":
            score = 165
            detail = key
        if not score:
            continue
        absolute = absolutize_url(base_url, content)
        if not absolute:
            continue
        candidates.append(
            ImageCandidate(
                page_url=base_url,
                image_url=absolute,
                score=score + domain_score(base_url) + image_url_penalty(absolute),
                source="meta",
                detail=detail,
            )
        )

    for tag in parser.link_tags:
        rel = (tag.get("rel") or "").casefold()
        href = tag.get("href", "")
        if "image_src" not in rel or not href:
            continue
        absolute = absolutize_url(base_url, href)
        if not absolute:
            continue
        candidates.append(
            ImageCandidate(
                page_url=base_url,
                image_url=absolute,
                score=175 + domain_score(base_url) + image_url_penalty(absolute),
                source="link",
                detail="image_src",
            )
        )

    return candidates


def choose_img_src(attrs: dict[str, str], base_url: str) -> str | None:
    for key in ("src", "data-src", "data-lazy-src", "data-original", "data-image"):
        absolute = absolutize_url(base_url, attrs.get(key, ""))
        if absolute:
            return absolute
    srcset = attrs.get("srcset", "")
    if srcset:
        candidates = [item.strip().split(" ")[0] for item in srcset.split(",") if item.strip()]
        for candidate in reversed(candidates):
            absolute = absolutize_url(base_url, candidate)
            if absolute:
                return absolute
    return None


def parse_dimension(value: str) -> int:
    match = re.search(r"\d+", value or "")
    return int(match.group(0)) if match else 0


def parse_img_tag_candidates(parser: RecipePageParser, base_url: str) -> list[ImageCandidate]:
    candidates: list[ImageCandidate] = []
    for attrs in parser.image_tags:
        image_url = choose_img_src(attrs, base_url)
        if not image_url:
            continue
        width = parse_dimension(attrs.get("width", ""))
        height = parse_dimension(attrs.get("height", ""))
        text_blob = " ".join(
            [
                attrs.get("alt", ""),
                attrs.get("title", ""),
                attrs.get("class", ""),
                attrs.get("id", ""),
                attrs.get("src", ""),
            ]
        )
        score = 80 + domain_score(base_url)
        score += image_url_bonus(text_blob)
        score += image_url_penalty(image_url)
        if width >= 400:
            score += 15
        if height >= 300:
            score += 15
        if width and height and width < 150 and height < 150:
            score -= 25
        candidates.append(
            ImageCandidate(
                page_url=base_url,
                image_url=image_url,
                score=score,
                source="img",
                detail=f"alt={attrs.get('alt', '')[:60]}",
            )
        )
    return candidates


def extract_image_candidates(page_url: str) -> list[ImageCandidate]:
    final_url, html = fetch_text(page_url)
    parser = RecipePageParser()
    parser.feed(html)
    candidates: list[ImageCandidate] = []
    candidates.extend(parse_ld_json_candidates(parser.ld_json_blocks, final_url))
    candidates.extend(parse_meta_candidates(parser, final_url))
    candidates.extend(parse_img_tag_candidates(parser, final_url))

    deduped: dict[str, ImageCandidate] = {}
    for candidate in candidates:
        existing = deduped.get(candidate.image_url)
        if existing is None or candidate.score > existing.score:
            deduped[candidate.image_url] = candidate
    return sorted(deduped.values(), key=lambda item: item.score, reverse=True)


def print_candidate_table(candidates: list[ImageCandidate], limit: int) -> None:
    for candidate in candidates[:limit]:
        print(f"[{candidate.score}] {candidate.image_url}")
        print(f"  page: {candidate.page_url}")
        print(f"  source: {candidate.source} {candidate.detail}".rstrip())


def save_image_for_recipe(recipe_name: str, image_url: str, overwrite: bool, target: str) -> None:
    slug = helper.photo_lookup_key(recipe_name)
    destination_ext = helper.infer_extension_from_url(image_url)
    destinations = [directory / f"{slug}{destination_ext}" for directory in helper.target_directories(target)]

    for destination in destinations:
        existing = helper.find_existing_photo(slug, target="both")
        if existing and existing != destination and not overwrite and destination.parent != existing.parent:
            pass
        if destination.exists() and not overwrite:
            raise SystemExit(f"Destination already exists: {destination}\nUse --overwrite to replace it.")

    for destination in destinations:
        helper.save_from_url(image_url, destination)
        print(f"Downloaded image for '{recipe_name}' -> {destination}")

    if target in {"live", "both"}:
        print("The running app can auto-refresh this photo from the live container folder.")
    else:
        print("The app will pick this bundled photo up on next launch if the recipe does not already have imageData saved.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Search the web for a recipe page and save a likely recipe photo."
    )
    parser.add_argument("recipe", help="Recipe name to match from momrecette_bundle.json")
    parser.add_argument(
        "--page-url",
        action="append",
        help="Skip search and inspect one or more specific recipe pages.",
    )
    parser.add_argument(
        "--max-pages",
        type=int,
        default=5,
        help="How many search-result pages to inspect before choosing an image.",
    )
    parser.add_argument(
        "--print-candidates",
        action="store_true",
        help="Print the best image candidates that were found.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the chosen page/image URL without downloading it.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing photo if one is already present.",
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
    recipe_names = helper.load_recipe_names()
    recipe_name = helper.resolve_recipe_name(args.recipe, recipe_names)
    slug = helper.photo_lookup_key(recipe_name)

    existing = helper.find_existing_photo(slug, target="both")
    if existing and not args.overwrite and not args.dry_run:
        raise SystemExit(f"Existing photo already present: {existing}\nUse --overwrite to replace it.")

    if args.page_url:
        pages = [SearchResult(url=url, title="manual", score=1000) for url in args.page_url]
    else:
        pages = search_recipe_pages(recipe_name, max(args.max_pages, 1))

    if not pages:
        raise SystemExit(
            "No candidate recipe pages found.\n"
            f"Try: python3 scripts/recipe_photo_helper.py \"{recipe_name}\" --search"
        )

    all_candidates: list[ImageCandidate] = []
    failures: list[str] = []
    for result in pages:
        try:
            page_candidates = extract_image_candidates(result.url)
        except Exception as exc:
            failures.append(f"{result.url}: {exc}")
            continue
        all_candidates.extend(page_candidates[:5])

    if not all_candidates:
        failure_summary = "\n".join(f"  - {item}" for item in failures[:10])
        raise SystemExit(
            "No usable image candidate was found on the searched pages.\n"
            + (f"Failures:\n{failure_summary}\n" if failure_summary else "")
            + f"Try manual search: python3 scripts/recipe_photo_helper.py \"{recipe_name}\" --search"
        )

    all_candidates.sort(key=lambda item: item.score, reverse=True)
    if args.print_candidates:
        print_candidate_table(all_candidates, limit=10)

    best = all_candidates[0]
    print(f"Recipe: {recipe_name}")
    print(f"Page: {best.page_url}")
    print(f"Image: {best.image_url}")
    print(f"Source: {best.source} {best.detail}".rstrip())
    print(f"Score: {best.score}")

    if args.dry_run:
        return 0

    save_image_for_recipe(recipe_name, best.image_url, overwrite=args.overwrite, target=args.target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
