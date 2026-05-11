# Stack technique recommandee

## Application

- Flutter desktop (macOS)
- Dart
- Riverpod (state management + DI)
- Theme system global dark-only (cyberpunk neon rose/violet)

## Moteur media

- FFmpeg (rendu/export)
- ffprobe (analyse metadata)
- VideoToolbox (acceleration materielle Apple)
- ffmpeg-full (Homebrew) requis pour les filtres texte (`drawtext`) et la parite preview/export

## Plugins Flutter

- `file_selector` pour selection fichiers
- `desktop_drop` pour drag and drop
- `path` pour gestion de chemins
- `video_player` pour la preview media locale v1
- `just_audio` pour synchro audio active sur transport preview
- (a venir) plugin lecture preview (ex: `media_kit`)

## Persistance

- format projet JSON `.psm`
- stockage local uniquement (pas de login/cloud en v1)

## Cibles export initiales

- YouTube Video 16:9 (1080p)
- YouTube Shorts 9:16 (1080x1920)
- Instagram Reels 9:16 (1080x1920)

## Perimetre open source

- code app open source
- pipelines export documentes
- effets ajoutes progressivement

## UI/UX direction

- dark mode exclusif
- style cyberpunk neon uniforme dans toutes les vues
- tokens de styles centralises dans le theme global
