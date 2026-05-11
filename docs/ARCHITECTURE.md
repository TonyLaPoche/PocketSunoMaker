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
  - creation/chargement/sauvegarde de projet local `.psm`
  - edition timeline (move/trim/split/snap)
  - orchestration etat projet (controllers Riverpod)
- `features/media_import`
  - import fichiers via picker
  - import drag and drop
  - classification media (audio/video/image) + metadonnees (`ffprobe`)
- `features/preview`
  - transport lecture/pause/seek
  - synchronisation audio/video en preview
  - rendu media actif (video/image)
- `features/export`
  - file de jobs export
  - presets cibles (YouTube, Shorts, Reels)
  - service export FFmpeg (base)

## Modules planifies

- `features/effects`
  - transformations, effets, texte, sous-titres
- `features/inspector`
  - panneau contextuel des proprietes clip/piste/projet
  - edition rapide des parametres (transform, opacite, audio)
- `features/timeline_advanced`
  - automation courbes/keyframes
  - gestion avancee des pistes (mute/solo/lock, routing)
- `features/export_advanced`
  - progression fine, annulation, retries
  - presets utilisateurs et profils personnalises

## Donnees projet (cible)

Format `*.psm` (JSON):
- metadonnees projet (fps, resolution, duree)
- media bin (assets references)
- timeline (tracks, clips, keyframes/effects)
- options export

## Etat de maturite (resume)

- base fonctionnelle de montage local: OK
- preview synchronisee: OK
- export v1: present, a renforcer vers pipeline complet
- refonte UX/UI Studio (M3.5): prochaine priorite

## Principes qualite

- un use case = une responsabilite claire
- pas de logique metier dans les widgets
- tester en priorite `domain` et `application`
- garder des interfaces stables avant de brancher des engines lourds
