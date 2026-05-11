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
- [x] Outils contextuels sur clip selectionne (duree, trim, suppression) [retires ensuite pour alleger l'UI]
- [x] Etirement rapide de duree pour clips image
- [x] Barres d'outils timeline fixes (non impactees par le zoom de la zone clips)
- [x] Zoom par defaut a 10% et increment boutons +/- a 2%
- [x] Graduation/rule timeline retiree (UI simplifiee)

## M3 - Preview et export
- [x] Transport preview v1 (play/pause/seek)
- [x] Playhead synchronise avec la timeline
- [x] Auto-follow du playhead pendant la lecture (focus tete de lecture)
- [x] Preview media reelle v1 (video/image active)
- [x] Preview temps reel robuste
- [x] Synchronisation audio/video v1 (transport + audio actif)
- [x] Queue d'export
- [x] Exports presets: YouTube, Shorts, Reels
- [x] Feedback visuel d'export en cours (spinner + barre indeterminee + job actif)
- [x] Hardening permissions macOS sur medias references (fallback preview + erreurs explicites)
- [x] Synchronisation Media Bin depuis un projet `.psm` charge
- [x] Suppression unitaire des medias depuis le Media Bin

## M3.5 - Refonte UX/UI "Studio" (en cours)
- [x] Etape 1 - Shell applicatif "pro montage"
  - [x] Header compact avec actions reelles uniquement (placeholders retires tant qu'ils ne sont pas fonctionnels)
  - [x] Layout stable en 4 zones: Media Bin gauche, Preview haut centre, Timeline bas centre, Inspecteur droite
  - [x] Timeline deplacee en bande basse sur toute la largeur disponible
  - [x] Statut bar basse (etat projet, mode magnetique, feedback actions)
- [x] Etape 2 - Timeline orientee production
  - [x] Barre d'outils timeline complete et fixe (selection, lame, trim, split, zoom, snapping, marqueurs)
  - [x] Pistes mieux structurees (headers piste, etats mute/solo/lock, labels plus lisibles)
  - [x] Playhead et selection clips avec hierarchie visuelle forte (accent actif uniquement)
  - [x] Progression: headers piste enrichis (mute/solo/lock), toggle snapping global, badge playhead renforce
- [x] Etape 3 - Inspecteur et coherence visuelle cyberpunk
  - [x] Panneau inspecteur contextuel (transform, opacite, vitesse, audio de base)
  - [x] Systeme de densite/contraste: neon reserve aux elements actifs, texte secondaire adouci
  - [x] Harmonisation composants (cards, boutons, sliders, separateurs) pour un rendu coherent non "gadget"
  - [x] Progression: inspecteur clip contextuel (transform, opacite, vitesse, volume), persistance `.psm` et application preview (scale/rotation/opacite + vitesse/volume)
- [x] Etape 4 - Finition interaction et ergonomie
  - [x] Micro-interactions fluides (hover, focus, selection, transitions courtes)
  - [x] Accessibilite desktop (tailles minimales de cibles, lisibilite, raccourcis de base)
  - [x] Validation UX sur sessions montage longues (fatigue visuelle, rapidite d'execution)
  - [x] Progression: micro-interactions hover sur panneaux studio + raccourcis clavier de base (Play/Pause, Nouveau, Importer, Sauvegarder, Charger) + cibles boutons principales agrandies + raccourcis timeline (V/B/T/H/M, N snapping, S split) + seek clavier rapide (fleches gauche/droite) + mode confort visuel (intensite neon reduite)

## M4 - Enrichissements
- [x] Section Timeline étirable (réduction des trois sections "Media", "Lecteur" et Inspecteur/Export)
- [x] Preview adaptable et orientee export (agrandissement manuel, ratio auto sur preset, cadre neon rose/violet)
- [ ] Sous-titres et texte anime
  - Progression en cours: texte overlay v1 (clip texte dedie, edition depuis inspecteur, style typographique de base: police/taille px/gras/italique/couleurs, positionnement drag dans preview, rendu timeline specifique, persistance `.psm`, projection preview en coordonnees canvas + export drawtext pour coherence taille/position, lisibilite renforcee en preview avec adaptation a l'echelle du preset de sortie)
- [ ] Effets (glitch, rotation, etc.) pluginables
- [ ] Visualizer lie au son
- [ ] UX avancee (raccourcis, undo/redo, marqueurs)
- [x] Pinch zoom smooth (interpolation fluide)
- [ ] Affinage sensibilite gestes trackpad (calibrage fin zoom/scroll)

## Convention checklist

- `[x]` = termine
- `[ ]` = a faire
