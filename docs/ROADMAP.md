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
- [x] Export MP4 reel (FFmpeg assemble + mux; mode principal **fidèle preview** frame-by-frame)
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
- [x] Feedback visuel d'export en cours (progression temps reel 0-100, job actif, annulation manuelle)
- [x] Hardening permissions macOS sur medias references (fallback preview + erreurs explicites)
- [x] Synchronisation Media Bin depuis un projet `.psm` charge
- [x] Suppression unitaire des medias depuis le Media Bin
- [x] Contrat de parite preview/export: un outil applique dans l'editeur doit etre rendu a l'export (sinon export bloque avec erreur explicite)
- [x] Export fidele depuis la preview (capture frame-by-frame, verrouillage transport + badge)
- [x] ETA restante pendant export (inspecteur Export)
- [x] Stabilisation export fidele: seek video a chaque pas timeline en pause de capture pour eviter des PNG repetees alors que la piste audio avance encore dans le MP4 sortant

## M3.9 - Export fidele frame-by-frame + securite materiel

### Etape 1 - Mode export **fidele preview** (livré)
- [x] Capturer le rendu Flutter frame-by-frame aligné sur la timeline (même moteur que la preview)
- [x] Sequence temporaire `frame_%06d.png`
- [x] Assemblage MP4 via FFmpeg (libx264, yuv420p, preset bitrate)
- [x] Mux audio source avec durée projet (FFmpeg `-shortest` où pertinent)

### Etape 2 - Profil machine avant export (partiellement livré)
- [x] Scan best-effort: nombre de CPUs, mémoire via `sysctl`, batterie/secteur via `pmset -g batt`
- [x] Dérivation d'un mode `safe` / `balanced` / `performance` et pause entre captures (`interFrameDelayMs`, réglée plus modeste pour la latence lorsque les ressources le permettent)
- [x] Journal du profil + délai utilisé dans `.export-debug.txt` (phase rendu frames)
- [ ] Récap pré-export dédié (profil détecté, impact machine prévu)

### Etape 3 - Garde-fous anti-surchauffe pendant export (partiellement livré)
- [x] Throttling léger entre captures selon profil matériel
- [ ] Adaptation dynamique a la charge / temperatures en cours d'export
- [ ] Pause / reprise d'un export long

### Etape 4 - Robustesse pipeline (partiellement livré)
- [x] Nettoyage du répertoire temporaire `*.preview-frames` (succès, échec, annulation) en `finally`
- [ ] Reprise après interruption (checkpoint images / reprise FFmpeg)
- [x] Snapshot debug `.export-debug.txt` (phases FFmpeg, filtres/classique, erreurs; notes profil fidèle)

### Etape 5 - UX produit (partiellement livré)
- [x] Pendant l’export fidèle : contrôle preview désactivés, badge visible **Export fidèle en cours (contrôles verrouillés)**, progression temps réel, annulation possible
- [ ] Sélecteur explicite `Rapide (FFmpeg filtres)` vs `Fidèle (frame-by-frame)` dans l’onglet Export (aujourd’hui la voie fidèle est utilisée quand la capture depuis la preview est branchée au déclencheur d’export)
- [ ] Texte UX standardisé recommandant le mode fidèle pour les projets à effets forts / parité maximale avec la prévisualisation

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
  - [x] Progression: headers piste enrichis (mute/solo/lock), toggle snapping global, badge playhead renforce + tete d'epingle draggable (pause uniquement) + aide contextuelle outils timeline (?)
- [x] Etape 3 - Inspecteur et coherence visuelle cyberpunk
  - [x] Panneau inspecteur contextuel (transform, opacite, vitesse, audio de base)
  - [x] Systeme de densite/contraste: neon reserve aux elements actifs, texte secondaire adouci
  - [x] Harmonisation composants (cards, boutons, sliders, separateurs) pour un rendu coherent non "gadget"
  - [x] Progression: inspecteur clip contextuel (transform, opacite, vitesse, volume), persistance `.psm` et application preview (scale/rotation/opacite + vitesse/volume)
- [x] Etape 4 - Finition interaction et ergonomie
  - [x] Micro-interactions fluides (hover, focus, selection, transitions courtes)
  - [x] Accessibilite desktop (tailles minimales de cibles, lisibilite, raccourcis de base)
  - [x] Validation UX sur sessions montage longues (fatigue visuelle, rapidite d'execution)
  - [x] Progression: micro-interactions hover sur panneaux studio + raccourcis clavier de base (Play/Pause, Nouveau, Importer, Sauvegarder, Charger) + cibles boutons principales agrandies + raccourcis timeline (V/B/T/H/M, N snapping, S split) + seek clavier rapide (fleches gauche/droite) + mode confort visuel (intensite neon reduite) + transport preview compacte (play/temps/seek sur une ligne) + nettoyages visuels preview (infos media actives retirees) + jobs export actionnables (copie erreur, annuler en cours, ouvrir fichier termine)

## M4 - Enrichissements
- [x] Section Timeline étirable (réduction des trois sections "Media", "Lecteur" et Inspecteur/Export)
- [x] Preview adaptable et orientee export (agrandissement manuel, ratio auto sur preset, cadre neon rose/violet)
- [x] Sous-titres et texte anime
  - Termine: texte overlay v1 (clip texte dedie, edition depuis inspecteur, style typographique de base: police/taille px/gras/italique/couleurs + polices enrichies, positionnement drag dans preview, angle, rendu timeline specifique, persistance `.psm`, projection preview en coordonnees canvas + export drawtext pour coherence taille/position, lisibilite renforcee en preview avec adaptation a l'echelle du preset de sortie, toggles fond/bordure dans inspecteur avec application preview+export, inspecteur texte UX amelioree avec sous-onglet Animation + mini timeline de courbe entree/sortie, animations apparition/sortie cumulables (fade + slide up/down + zoom) avec controles de duree/intensite + indicateur de courbe dans les blocs texte timeline, mode karaoke v1 en mono-rendu shader (remplissage lineaire progressif du texte, sans double superposition) + controle couleur/delai/duree en preview/export, support multi-blocs texte simultanes, ciblage piste texte (meme piste ou nouvelle source), glisser-deposer d un clip texte entre pistes texte, renommage de piste texte depuis la timeline)
- [ ] Effets (glitch, rotation, etc.) pluginables
  - Progression v1: boite a outils Effets avec 2 categories (visuels/sonores), ajout d effets sur timelines dediees multi-pistes, premiers effets visuels Filmora-like en preview (glitch, tremblement, RGB split, flash, VHS), inspecteur enrichi pour tremblement (intensite + amplitude + frequence + synchro timeline audio + Auto BPM detection reelle via analyse audio), mode shake audio-reactive temps reel (profil energie audio pour reduire fortement le tremblement pendant les silences), glitch v2 controle (dechirure, bruit, mix lignes + blocs rectangles, taille blocs, palette manuelle ou auto-detectee dynamique, synchro sonore on/off), premiers effets sonores audibles en preview (bip censure, distorsion, stutter), parite export FFmpeg active pour effets visuels v1 (chaine filtres dediee) et effets sonores v1 (censor/mute segment, distorsion telephone, gate stutter), avec garde-fou explicite si aucun media audio n est present
- [ ] Visualizer lie au son
- [ ] UX avancee (raccourcis, undo/redo, marqueurs)
- [x] Panneau Media enrichi (tabs Media/Outils, action "Ajouter texte au playhead" deplacee dans Outils > Texte)
- [x] Pinch zoom smooth (interpolation fluide)
- [ ] Affinage sensibilite gestes trackpad (calibrage fin zoom/scroll)

## Convention checklist

- `[x]` = termine
- `[ ]` = a faire
