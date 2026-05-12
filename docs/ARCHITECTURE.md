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
  - inspecteur contextuel clip (transform, opacite, audio, texte)
  - gestion des clips effets (visuels/sonores) et pistes dediees
- `features/media_import`
  - import fichiers via picker
  - import drag and drop
  - classification media (audio/video/image) + metadonnees (`ffprobe`)
- `features/preview`
  - transport lecture/pause/seek
  - synchronisation audio/video en preview
  - rendu media actif (video/image)
  - canvas ratio export, grille de reperes, overlays texte (position/angle/opacite)
  - animations texte (fade/slide/zoom) + mode karaoke v1 en rendu shader mono-texte
  - rendu effets visuels v1 en temps reel (glitch, tremblement, RGB split, flash, VHS)
- `features/export`
  - file de jobs export
  - presets cibles (YouTube, Shorts, Reels)
  - service export FFmpeg (progression temps reel, annulation, erreurs actionnables)
  - parite preview/export des outils pris en charge (ex: texte, animations, karaoke)

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
  - retries et reprise apres echec
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
- export v1: operationnel (queue, progression 0-100, annulation, ouverture Finder)
- refonte UX/UI Studio (M3.5): implementee sur le socle principal

## Principes qualite

- un use case = une responsabilite claire
- pas de logique metier dans les widgets
- tester en priorite `domain` et `application`
- garder des interfaces stables avant de brancher des engines lourds
