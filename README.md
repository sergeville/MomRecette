# MomRecette

Application iOS / iPadOS / macOS pour conserver et consulter les recettes de famille.

## Fonctionnalités

- **Carnet de recettes** — nom, catégorie, portions, temps de préparation et de cuisson, ingrédients, étapes, photo, notes
- **Interface Rolodex** (iPhone) — défilement en cartes empilées, swipe pour naviguer
- **Interface split-view** (iPad / Mac) — barre latérale + liste + détail
- **Filtres** — par catégorie et par recherche (nom, catégorie, ingrédients)
- **Ajout / modification** — formulaire complet avec galerie photo et caméra
- **Import JSON** — importer un fichier de recettes au format JSON
- **Persistance locale** — `momrecette.json` dans le dossier Documents de l'app
- **Liste d'épicerie** — générer une liste à cocher depuis une recette et la sauvegarder localement

## Catégories

| Icône | Catégorie     |
|-------|---------------|
| 🍲    | Soupes        |
| 🥗    | Entrées       |
| 🍽️    | Plats         |
| 🍰    | Desserts      |
| 🫙    | Sauces        |
| 🫕    | Fondues       |
| 🥬    | Salades       |
| 🥐    | Pâtisseries   |
| 🍴    | Autres        |

## Structure du projet

```
MomRecette/                           Racine du projet
├── MomRecette.xcodeproj/
├── App/
│   └── MomRecetteApp.swift           Point d'entrée (@main)
├── Models/
│   └── Recipe.swift                  Modèle Recipe + Ingredient + Category + données d'exemple
│   └── GroceryList.swift             Modèle de liste d'épicerie générée depuis une recette
├── ViewModels/
│   └── RecipeStore.swift             Store ObservableObject — CRUD + persistence JSON + filtrage + liste d'épicerie
├── Views/
│   ├── ContentView.swift             Racine — bascule Rolodex (iPhone) ↔ SplitView (iPad/Mac)
│   ├── AddEdit/
│   │   └── AddEditRecipeView.swift   Formulaire ajout / modification
│   ├── Card/
│   │   └── RecipeCardView.swift      Carte individuelle dans le Rolodex
│   ├── Deck/
│   │   └── RolodexDeckView.swift     Carousel de cartes empilées
│   ├── Detail/
│   │   └── RecipeDetailView.swift    Vue détail de la recette
│   ├── Grocery/
│   │   └── GroceryListView.swift     Liste d'épicerie à cocher générée depuis une recette
│   └── Components/
│       ├── ImagePickerView.swift     Sélecteur photo (galerie + caméra)
│       └── ImportView.swift          Import JSON
├── Resources/
│   └── momrecette_bundle.json        Recettes de départ (seed)
│   └── RecipePhotos/                 Pack optionnel de photos de plats liées automatiquement
├── Assets.xcassets/
├── Info.plist
└── MomRecetteTests/
    └── MomRecetteTests.swift
```

## Prérequis

- Xcode 15+
- iOS 16+ / iPadOS 16+ / macOS 13+ (via Mac Catalyst)
- Swift 5.9

## Build

```bash
# Avec XcodeGen (project.yml)
xcodegen generate
open MomRecette.xcodeproj
```

Ou ouvrir `MomRecette.xcodeproj` directement dans Xcode et lancer sur simulateur ou appareil.

## Format JSON d'import

```json
[
  {
    "name": "Nom de la recette",
    "category": "Desserts",
    "servings": 4,
    "prepTime": 15,
    "cookTime": 30,
    "ingredients": [
      { "quantity": "1 tasse", "name": "farine" }
    ],
    "steps": ["Étape 1", "Étape 2"],
    "notes": ""
  }
]
```

Les catégories valides : `Soupes`, `Entrées`, `Plats`, `Desserts`, `Sauces`, `Fondues`, `Salades`, `Pâtisseries`, `Autres`.

## Persistance

Au premier lancement, les recettes du fichier bundle `momrecette_bundle.json` sont chargées.
Toutes les modifications sont sauvegardées automatiquement dans `Documents/momrecette.json`.
La liste d'épicerie active est sauvegardée dans `Documents/momrecette-grocery-list.json`.

## Pack de photos des recettes

MomRecette peut maintenant lier automatiquement des photos de plats aux recettes existantes.

Déposez vos images dans:

`Resources/RecipePhotos/`

Nommez chaque fichier avec une version normalisée du nom de la recette:

- `steak-au-poivre.jpg`
- `biscuit-raisins-haches.jpg`
- `beef-stuffed-cabbage.jpg`

Formats supportés:

- `.jpg`
- `.jpeg`
- `.png`
- `.webp`

Au lancement, l'application hydrate automatiquement les recettes qui n'ont pas encore de photo en utilisant ce pack local.

## Script pour attacher une photo à une recette

Si vous avez choisi une recette et trouvé une bonne photo du plat, utilisez le script local:

```bash
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --status
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --search
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --file ~/Downloads/biscuit.jpg
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --url https://example.com/biscuit.jpg
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --url https://example.com/biscuit.jpg --target live
python3 scripts/recipe_photo_helper.py "Biscuit Raisins Haches" --url https://example.com/biscuit.jpg --target both
```

Ce script:

- vérifie que la recette existe dans `momrecette_bundle.json`
- normalise automatiquement le nom du fichier
- enregistre l'image dans `Resources/RecipePhotos/`
- permet d'ouvrir une recherche d'images pour la recette choisie

Pour l'auto-refresh pendant que l'application tourne:

- utilisez `--target live` pour écrire dans le dossier `Documents/RecipePhotos` du conteneur de l'app
- ou `--target both` pour écrire dans le dossier live et le pack de ressources du projet

MomRecette surveille maintenant ce dossier live et hydrate automatiquement la recette quand une photo y apparaît.

Pour traiter plusieurs recettes d'un coup:

```bash
python3 scripts/batch_recipe_photos.py --status
python3 scripts/batch_recipe_photos.py --category Plats --print-searches 3
python3 scripts/batch_recipe_photos.py --category Plats --open-searches 3
python3 scripts/batch_recipe_photos.py --export-missing /tmp/momrecette-missing-photos.csv
python3 scripts/batch_recipe_photos.py --apply /tmp/momrecette-missing-photos.csv
```

Le script batch écrit un CSV pour toutes les recettes sans photo, puis applique en masse les fichiers locaux ou URLs d'images que vous renseignez.
Il peut aussi ouvrir les recherches Google Images à partir des vrais titres présents dans MomRecette.
