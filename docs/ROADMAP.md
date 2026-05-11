# PocketSunoMaker Roadmap

## Vision

Construire un editeur video desktop macOS, 100% open source et gratuit, sous Flutter, avec un workflow complet:
- import medias (audio/video/image)
- montage timeline
- preview fluide
- export cible YouTube / Shorts / Reels

## Statut global

- [x] Initialisation Flutter macOS
- [x] Base Clean Architecture
- [x] Module `project` (creation de projet locale)
- [x] Presets export cibles (modele domaine)
- [x] Module `media_import` (file picker + drag and drop)
- [x] Extraction metadonnees reelles via `ffprobe`
- [x] Sauvegarde/chargement projet `.psm` (JSON)
- [x] Theme global dark-only cyberpunk neon (rose/violet)
- [x] Timeline v1 (pistes + clips + trim/move)
- [x] Preview synchronisee audio/video
- [ ] Export FFmpeg reel (pipeline bout en bout)
- [ ] Effets v1 (rotation, opacity, transforms de base)
- [ ] Texte et sous-titres v1
- [ ] Visualizer audio v1
- [ ] Packaging/release macOS

## Milestones

## M1 - Fondations (en cours)
- [x] Architecture modulaire et scalable
- [x] Ecran principal avec base UX
- [x] Import local des medias
- [x] Flux import robuste (picker permissif + messages d'etat)
- [x] Metadonnees medias automatiques (duree, fps, resolution, codec)
- [x] Persistance projet locale

## M2 - Montage de base
- [x] Ajout clip depuis Media Bin (prototype)
- [x] Timeline visuelle multi-pistes (prototype)
- [x] Barre d'outils edition (selection, lame, trim, main, marqueur)
- [x] Zoom/dezoom timeline
- [x] Ajout/suppression de clips
- [x] Split clip au playhead (outil lame)
- [x] Trim in/out
- [x] Deplacement drag and drop sur timeline
- [x] Snapping basique

## M3 - Preview et export
- [x] Transport preview v1 (play/pause/seek)
- [x] Playhead synchronise avec la timeline
- [x] Preview media reelle v1 (video/image active)
- [x] Preview temps reel robuste
- [x] Synchronisation audio/video v1 (transport + audio actif)
- [x] Queue d'export
- [x] Exports presets: YouTube, Shorts, Reels

## M4 - Enrichissements
- [ ] Sous-titres et texte anime
- [ ] Effets (glitch, rotation, etc.) pluginables
- [ ] Visualizer lie au son
- [ ] UX avancee (raccourcis, undo/redo, marqueurs)

## Convention checklist

- `[x]` = termine
- `[ ]` = a faire
