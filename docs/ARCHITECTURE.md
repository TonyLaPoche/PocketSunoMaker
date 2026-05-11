# Architecture technique

## Objectif

Cette architecture suit une logique Clean Architecture pour garder une base maintenable et scalable sur le long terme.

## Couches

- `presentation`
  - widgets, ecrans, controllers Riverpod
  - orchestration UI uniquement
- `application`
  - use cases metier
  - coordination des repositories
- `domain`
  - entites metier et contrats (interfaces)
  - aucune dependance framework
- `infrastructure`
  - implementations concretes (filesystem, ffmpeg/ffprobe, plugins desktop)

## Regles de dependance

- `presentation -> application -> domain`
- `infrastructure -> domain` (impl des contrats)
- `domain` ne depend de rien

## Modules actuels

- `features/project`
  - creation de projet locale (base)
  - presets export (modele domaine)
- `features/media_import`
  - import fichiers via picker
  - import drag and drop
  - classification media (audio/video/image)

## Modules planifies

- `features/timeline`
  - pistes, clips, trim, snapping
- `features/preview`
  - lecteur, seek, synchro
- `features/export`
  - pipeline ffmpeg, presets, progress/cancel
- `features/effects`
  - transformations, effets, texte, sous-titres

## Donnees projet (cible)

Format `*.psm` (JSON):
- metadonnees projet (fps, resolution, duree)
- media bin (assets references)
- timeline (tracks, clips, keyframes/effects)
- options export

## Principes qualite

- un use case = une responsabilite claire
- pas de logique metier dans les widgets
- tester en priorite `domain` et `application`
- garder des interfaces stables avant de brancher des engines lourds
