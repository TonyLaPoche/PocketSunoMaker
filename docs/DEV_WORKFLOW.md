# Workflow developpement

## Prerequis

- Flutter stable installe
- Xcode CLI tools
- macOS recent
- ffmpeg/ffprobe disponibles dans le `PATH` (a confirmer/installer)

## macOS permissions (sandbox)

- les entitlements doivent inclure `com.apple.security.files.user-selected.read-write`
- redemarrer completement l'app apres toute modif d'entitlements
- en cas de doute, tester en relancant `flutter run -d macos`

## Commandes utiles

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter run -d macos`
- `flutter build macos --debug`

## Regles projet

- respecter la Clean Architecture
- ajouter une feature dans son module dedie
- garder les cas d'usage testables
- eviter la logique metier dans la couche UI

## Definition of Done (DoD)

- code formate
- `flutter analyze` passe
- tests existants passent
- documenter changements si impact architectural

## Sequence de travail recommandee

1. Ajouter/adapter entites domaine
2. Ajouter use cases application
3. Implementer infrastructure
4. Brancher presentation
5. Valider tests + analyse
