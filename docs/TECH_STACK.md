# Stack technique recommandee

## Application

- Flutter desktop (macOS)
- Dart
- Riverpod (state management + DI)

## Moteur media

- FFmpeg (rendu/export)
- ffprobe (analyse metadata)
- VideoToolbox (acceleration materielle Apple)

## Plugins Flutter

- `file_selector` pour selection fichiers
- `desktop_drop` pour drag and drop
- `path` pour gestion de chemins
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
