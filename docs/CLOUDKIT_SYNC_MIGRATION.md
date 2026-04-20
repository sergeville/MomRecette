# MomRecette Cloud Sync Migration

## Current Status

Current shipped state on `upgrade/1.0.5`:

- local Core Data foundation exists
- JSON/image migration scaffolding exists
- CloudKit-ready container scaffolding exists
- free manual package transfer exists as the current operator-facing sync path

Until Apple Developer / CloudKit provisioning is available, the practical cross-device workflow is:

- export `MomRecette-Sync-Latest.json`
- import that package on the other device

So this document remains the target architecture contract, not the current live operator workflow.

## Goal

Move MomRecette from per-device local JSON storage to a local-first store that stays synchronized across iPhone, iPad, and Mac Catalyst without data loss.

The target architecture is:

- local Core Data store on every device
- `NSPersistentCloudKitContainer` for sync
- CloudKit private database for per-user recipe data
- synced user/imported/generated image assets
- one-time migration from existing local JSON and image folders

This document is the implementation contract for the migration.

## Why This Architecture

This is the best fit for MomRecette because it:

- preserves local-first behavior
- supports offline edits
- uses Apple-managed sync semantics instead of a custom JSON sync engine
- handles device-to-device propagation with persistent history and remote change notifications
- is safer for future schema evolution than a shared iCloud Drive JSON file

## Canonical Source of Truth

After migration, the source of truth must be the Core Data store.

The following current surfaces become migration inputs only:

- `Documents/momrecette.json`
- `Documents/momrecette-grocery-list.json`
- `Documents/RecipeImages/`
- `Documents/RecipePhotos/`

Bundled recipe resources remain app resources, not cloud-synced records:

- `Resources/momrecette_bundle.json`
- bundled `Resources/RecipePhotos/*`

## Data Model

### RecipeEntity

Required fields:

- `id: UUID`
- `name: String`
- `categoryRawValue: String`
- `servings: Int32`
- `caloriesPerServing: Int32?`
- `prepTime: Int32`
- `cookTime: Int32`
- `notes: String`
- `isFavorite: Bool`
- `createdAt: Date`
- `updatedAt: Date`
- `lastModifiedByDeviceID: String`
- `bundlePhotoKey: String?`
- `deletedAt: Date?`

Relationships:

- `ingredients`
- `steps`
- `imageAssets`

### IngredientEntity

- `id: UUID`
- `recipeID: UUID`
- `position: Int32`
- `quantity: String`
- `name: String`
- `kindRawValue: String`

### StepEntity

- `id: UUID`
- `recipeID: UUID`
- `position: Int32`
- `text: String`

### RecipeImageAssetEntity

- `id: UUID`
- `recipeID: UUID`
- `roleRawValue: String`
- `filename: String?`
- `prompt: String?`
- `generatedModeRawValue: String?`
- `contentHash: String`
- `imageData: Binary Data`
- `createdAt: Date`
- `updatedAt: Date`
- `deletedAt: Date?`

Roles:

- `dishPhoto`
- `recipeCard`
- later, if needed: `referencePhoto`

## Image Sync Best Practices

- Do not upload bundled recipe photos to CloudKit.
- Only sync user-imported or app-generated images.
- Store active image role assignment in metadata, not by filename convention alone.
- Use Core Data binary data with external storage enabled for local efficiency.
- Mirror those objects to CloudKit so assets are managed as CloudKit-backed binary content.
- Compute and store a `contentHash` so duplicate images can be detected during migration or retry.
- Keep old asset records temporarily when replacing images; do not hard-delete immediately during sync races.

## Migration Best Practices

### Safety Rules

- Never delete `momrecette.json` or local image folders during the first migration pass.
- Create a migration marker only after a full successful import and verification.
- Migration must be idempotent.
- Matching must use stable recipe identity, not display order.
- Keep backups until at least one successful cloud-backed launch has completed.

### Identity Rules

Preferred identity:

- existing recipe `UUID` if present and stable

Fallback matching key for bundle/import repair only:

- normalized category + normalized recipe name

### Migration Sequence

1. open or create the Core Data store locally with CloudKit disabled
2. read current JSON recipes
3. import recipe records into Core Data
4. import ingredient rows and ordered steps
5. attach bundled-photo keys where applicable
6. import generated/imported local images into `RecipeImageAssetEntity`
7. persist a migration checkpoint
8. verify counts and references
9. only then enable CloudKit mirroring in a later phase

### What Must Be Preserved

- favorites
- notes
- calories per serving
- generated prompts and generated modes
- current dish photo assignment
- current recipe card assignment
- all user-generated images

## Conflict Handling Best Practices

There is no true "perfect real-time" merge for arbitrary concurrent recipe edits. The app needs deterministic rules.

### Recipe Scalars

For top-level scalar fields:

- use `updatedAt`
- use last-write-wins per object revision
- always stamp `lastModifiedByDeviceID`

### Ingredients And Steps

Treat ingredients and steps as ordered snapshots owned by the recipe revision.

Rule:

- newer recipe revision replaces the ordered ingredient list and ordered step list as a unit

Reason:

- this is much safer than trying to merge reordered cooking steps field-by-field

### Images

Rules:

- one active image asset per role
- latest `updatedAt` wins for active assignment
- losing asset remains retained temporarily for cleanup and audit

### Deletes

Use soft delete first:

- set `deletedAt`
- sync deletion
- clean up only after delete propagation is stable

## Operator Visibility

The app should expose a minimal sync diagnostics surface in Settings:

- iCloud availability status
- CloudKit account status
- migration state
- total recipe count
- total synced image asset count
- pending local changes count
- last successful sync time
- last sync error

## Implementation Phases

### Phase 1

- add Core Data model
- add local persistence stack
- add repository abstraction
- make app run locally from Core Data only
- migration from JSON and image folders

### Phase 2

- enable `NSPersistentCloudKitContainer`
- add persistent history tracking
- merge remote changes into UI state
- add sync diagnostics

### Phase 3

- expand sync to grocery list if desired
- add cleanup jobs for orphaned assets and tombstones
- add user-facing reset/recovery tools

## Validation Gates

Do not enable CloudKit for broad usage until these pass:

1. local migration preserves all recipes and images on one device
2. repeated launches do not duplicate migrated objects
3. editing a recipe locally persists correctly in Core Data
4. generated dish photo and recipe card both survive relaunch
5. two-device same-account test converges after edits
6. replace image on one device and confirm remote update on the other
7. delete on one device and confirm remote deletion on the other

## Out Of Scope For The First Sync Slice

- collaborative sharing between different iCloud users
- full multi-user merge semantics
- recipe version history UI
- cross-user shared grocery lists
