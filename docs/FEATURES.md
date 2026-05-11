# Catalogue features

## 1) Projet

- creer un nouveau projet
- sauvegarder/charger un projet local `.psm`
- config de base: resolution, fps, nom

## 2) Media Bin

- import via picker
- import via drag and drop
- affichage metadata (nom, type, taille)
- recherche et filtrage

## 3) Timeline

- multi-pistes (video, audio, overlay, texte)
- placement clips
- trim / split / move
- zoom timeline et snapping
- marqueurs
- modes d'edition (selection, lame, trim, main, marqueur)
- tete du playhead draggable (seulement en pause) pour ajustement fin
- aide integree des outils timeline via bouton "?"

## 4) Preview

- lecture/pause/seek
- synchro audio/video
- transport compact sur une seule ligne (play, temps, slider)
- zone preview agrandissable/reductible
- cadre preview neon (rose/violet) aligne sur le format de sortie
- adaptation automatique du ratio selon preset export (YouTube/Shorts/Reels)
- grille de reperes activable pour positionnement precis
- rendu preview progressif (qualite adaptable)
- rendu proxy pour medias lourds

## 5) Export

- presets:
  - YouTube video
  - YouTube Shorts
  - Instagram Reels
- H.264/H.265 avec acceleration materielle macOS (VideoToolbox)
- progression export temps reel (0-100%)
- annulation manuelle de l export en cours
- jobs export actionnables: copie du message d erreur, ouverture Finder du fichier termine
- parite stricte outils->export: les elements appliques dans l'editeur (ex: texte) doivent etre rendus dans le fichier final

## 6) Effets et animation

- transformations de base (position, scale, rotation, opacity)
- effets visuels (glitch, blur, color, etc.)
- transitions
- systeme extensible d'effets (plugin-like)

## 7) Texte / sous-titres

- titres statiques et animes
- templates de style
- import sous-titres (phase suivante: SRT)
- timeline dediee texte
- style texte editable: couleur, fond, bordure, angle (avec toggles fond/bordure)

## 8) Audio

- volume clip
- fades in/out
- visualizer synchronise au son
- normalisation/loudness basique

## 9) Productivite

- undo/redo
- raccourcis clavier
- autosave
- crash recovery

## 10) Qualite et stabilite

- tests unitaires (domain/application)
- tests d'integration infrastructure
- logs d'erreurs et diagnostic export

## 11) Direction visuelle

- theme dark-only
- design cyberpunk neon rose/violet
- tokens visuels centralises et reutilisables
