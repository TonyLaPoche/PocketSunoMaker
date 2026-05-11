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
- [x] Navigation trackpad macOS (pinch in/out pour zoom + glissement horizontal)
- [x] Ajout/suppression de clips
- [x] Split clip au playhead (outil lame)
- [x] Trim in/out
- [x] Deplacement drag and drop sur timeline
- [x] Snapping basique
- [x] Outils contextuels sur clip selectionne (duree, trim, suppression)
- [x] Etirement rapide de duree pour clips image
- [x] Barres d'outils timeline fixes (non impactees par le zoom de la zone clips)

## M3 - Preview et export
- [x] Transport preview v1 (play/pause/seek)
- [x] Playhead synchronise avec la timeline
- [x] Auto-follow du playhead pendant la lecture (focus tete de lecture)
- [x] Preview media reelle v1 (video/image active)
- [x] Preview temps reel robuste
- [x] Synchronisation audio/video v1 (transport + audio actif)
- [x] Queue d'export
- [x] Exports presets: YouTube, Shorts, Reels

## M3.5 - Refonte UX/UI "Studio" (en cours)
- [x] Etape 1 - Shell applicatif "pro montage"
  - Header compact avec navigation principale (Fichier, Edition, Affichage, Lecture, Export)
  - Layout stable en 4 zones: Media Bin gauche, Preview haut centre, Timeline bas centre, Inspecteur droite
  - Timeline deplacee en bande basse sur toute la largeur disponible
  - Statut bar basse (etat projet, mode magnetique, feedback actions)
- [x] Etape 2 - Timeline orientee production
  - Barre d'outils timeline complete et fixe (selection, lame, trim, split, zoom, snapping, marqueurs)
  - Pistes mieux structurees (headers piste, etats mute/solo/lock, labels plus lisibles)
  - Playhead, ruler et selection clips avec hierarchie visuelle forte (accent actif uniquement)
  - Progression: headers piste enrichis (mute/solo/lock), toggle snapping global, badge playhead et ruler renforce
- [ ] Etape 3 - Inspecteur et coherence visuelle cyberpunk
  - Panneau inspecteur contextuel (transform, opacite, vitesse, audio de base)
  - Systeme de densite/contraste: neon reserve aux elements actifs, texte secondaire adouci
  - Harmonisation composants (cards, boutons, sliders, separateurs) pour un rendu coherent non "gadget"
- [ ] Etape 4 - Finition interaction et ergonomie
  - Micro-interactions fluides (hover, focus, selection, transitions courtes)
  - Accessibilite desktop (tailles minimales de cibles, lisibilite, raccourcis de base)
  - Validation UX sur sessions montage longues (fatigue visuelle, rapidite d'execution)

## M4 - Enrichissements
- [ ] Sous-titres et texte anime
- [ ] Effets (glitch, rotation, etc.) pluginables
- [ ] Visualizer lie au son
- [ ] UX avancee (raccourcis, undo/redo, marqueurs)
- [x] Pinch zoom smooth (interpolation fluide)
- [ ] Affinage sensibilite gestes trackpad (calibrage fin zoom/scroll)

## Convention checklist

- `[x]` = termine
- `[ ]` = a faire
