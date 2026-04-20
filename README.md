# MomRecette

Application iOS / iPadOS / macOS pour conserver et consulter les recettes de famille.

## Fonctionnalités

- **Carnet de recettes** — nom, catégorie, portions, temps de préparation et de cuisson, ingrédients, étapes, photo, notes
- **Interface Rolodex** (iPhone) — défilement en cartes empilées, swipe pour naviguer
- **Interface split-view** (iPad / Mac) — barre latérale + liste + détail
- **Filtres** — par catégorie et par recherche (nom, catégorie, ingrédients)
- **Ajout / modification** — formulaire complet avec galerie photo et caméra
- **Import JSON** — importer un fichier de recettes au format JSON
- **Sync manuel gratuit** — exporter / importer un package complet entre iPhone, iPad et Mac
- **Persistance locale** — Core Data local avec migration de l'ancien `momrecette.json`
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
│   └── RecipeStore.swift             Store ObservableObject — CRUD + persistance locale + sync package + liste d'épicerie
│   └── RecipePersistentContainer.swift  Stack Core Data locale / CloudKit-ready
│   └── RecipeCoreDataRepository.swift   Repository Core Data
│   └── RecipeMigrationCoordinator.swift Migration / sauvegardes
│   └── RecipeCoreDataImporter.swift     Import JSON/images vers Core Data
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
│       └── ImportView.swift          Surface Sync / import / export
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

## Hygiène du dépôt

Les surfaces suivies par git doivent rester limitées au code produit, aux ressources du bundle, aux scripts réutilisables et à leur documentation.

Les chemins locaux suivants sont maintenant considérés comme hors dépôt:

- `.env` pour les secrets locaux
- `build/` pour les workspaces temporaires de packaging
- `dist/` pour les artefacts DMG / IPA
- `local/` pour les fichiers de scratch et exports ad hoc
- `recipe_card_ai_cli/output/` pour les images générées par le CLI Python

Le détail de cette convention est documenté dans [docs/LOCAL_WORKSPACE.md](docs/LOCAL_WORKSPACE.md).

## Packaging macOS DMG

Le script `scripts/package_momrecette_dmg.sh` produit maintenant deux artefacts dans `dist/`:

- `MomRecette-<version>-<build>.dmg` pour l'archive de release
- `MomRecette.dmg` comme alias stable vers la dernière build packagée

Le DMG contient l'app Mac Catalyst, un raccourci `Applications`, un `README.txt`, un `PACKAGE_INFO.txt` avec les métadonnées de release, `MomRecette Data.zip` quand des données live existent dans le conteneur local, et une fenêtre Finder personnalisée avec fond graphique et positions d'icônes fixes.

L'archive contient le contenu complet de `Documents`, y compris la base de recettes JSON et le dossier `RecipePhotos`. L'installeur décompresse ensuite cette archive avant de remplacer le contenu de `~/Library/Containers/com.villeneuves.MomRecette/Data/Documents`.

```bash
./scripts/package_momrecette_dmg.sh
```

Par défaut, le script désactive la signature Xcode pour permettre un build local du DMG sans certificat `Mac Development`. Vous pouvez réactiver la signature avec `XCODE_CODE_SIGNING_ALLOWED=YES XCODE_CODE_SIGNING_REQUIRED=YES`.

Pour une mise à niveau, remplacez l'app existante dans `Applications`. Si vous exécutez `Install MomRecette Data.command`, le script confirme l'opération, sauvegarde les données actuelles sur le Bureau, décompresse `MomRecette Data.zip`, puis remplace le contenu de `~/Library/Containers/com.villeneuves.MomRecette/Data/Documents`. Le script DMG crée d'abord une image writable, applique la mise en page Finder, puis convertit le résultat en UDZO final.

## Packaging iPhone IPA

Le script `scripts/package_sergeiphone_ipa.sh` produit maintenant un export iPhone signé nommé `sergeiPhone`:

- `sergeiPhone-<version>-<build>.ipa` pour l'archive de release
- `sergeiPhone.ipa` comme alias stable
- `sergeiPhone-PACKAGE_INFO.txt` avec les métadonnées d'export

Ce script prépare un workspace temporaire, remplace le seed bundle par les données live du conteneur quand elles existent, puis archive et exporte l'app iOS. En pratique:

- `momrecette.json` live devient le seed `momrecette_bundle.json`
- `momrecette-grocery-list.json` live est inclus comme seed de liste d'épicerie
- `RecipePhotos/` live est fusionné par-dessus les photos bundle pour le build iPhone

```bash
./scripts/package_sergeiphone_ipa.sh
```

Prérequis:

- signature iPhone valide dans Xcode
- provisioning profile compatible avec votre iPhone 15

Si Xcode doit régénérer les profils automatiquement, exécutez:

```bash
ALLOW_PROVISIONING_UPDATES=YES ./scripts/package_sergeiphone_ipa.sh
```

L'artefact `.ipa` sert à l'installation iPhone; l'installation sur l'appareil passe ensuite par un flux iOS signé, par exemple via Xcode Organizer, Apple Configurator ou TestFlight selon votre profil de distribution.

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

Au premier lancement, MomRecette peut migrer la bibliothèque locale historique vers un magasin Core Data local.

Entrées historiques encore prises en charge comme source de migration:

- `Documents/momrecette.json`
- `Documents/momrecette-grocery-list.json`
- `Documents/RecipePhotos/`
- `Documents/RecipeImages/`

Après migration, la source active devient le magasin Core Data local:

- `Library/Application Support/MomRecette/RecipeStore.sqlite`

La liste d'épicerie, les photos live, les photos générées et les recipe cards restent préservées pendant cette migration locale.

## Sync manuel gratuit

Sans abonnement Apple Developer, MomRecette peut maintenant transférer la bibliothèque complète entre appareils via un package manuel.

La surface visible dans l'app s'appelle maintenant `Sync`.

Le package contient:

- recettes
- liste d'épicerie active
- photos live `RecipePhotos`
- images générées `RecipeImages`

Flux recommandé:

1. sur l'appareil source, ouvrez `Sync`
2. utilisez `Exporter un package de sync`
3. enregistrez le fichier
4. sur l'appareil cible, ouvrez `Sync`
5. utilisez `Importer un package MomRecette`
6. confirmez le remplacement de la bibliothèque locale

Le nom de fichier stable utilisé par défaut est:

- `MomRecette-Sync-Latest.json`

L'import crée automatiquement une sauvegarde locale avant remplacement.

Limites actuelles:

- ce n'est pas un sync temps réel
- chaque nouvel export doit être réimporté sur l'autre appareil
- l'import remplace la bibliothèque locale de l'appareil cible après sauvegarde automatique

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

## Outil compagnon local `recipe_card_ai_cli`

Le générateur Python de cartes de recette peut vivre dans `recipe_card_ai_cli/` comme workspace local compagnon.

- ce dossier est considéré comme local-only et ignoré par git
- les environnements virtuels et builds Python restent locaux
- les images générées doivent être déposées dans `recipe_card_ai_cli/output/`

Si vous gardez ce workspace local, conservez sa propre documentation directement dans `recipe_card_ai_cli/README.md`.
