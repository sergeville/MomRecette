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
├── ViewModels/
│   └── RecipeStore.swift             Store ObservableObject — CRUD + persistence JSON + filtrage
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
│   └── Components/
│       ├── ImagePickerView.swift     Sélecteur photo (galerie + caméra)
│       └── ImportView.swift          Import JSON
├── Resources/
│   └── momrecette_bundle.json        Recettes de départ (seed)
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
