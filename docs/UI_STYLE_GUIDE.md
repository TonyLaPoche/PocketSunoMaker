# UI Style Guide (Dark Only)

## Direction artistique

PocketSunoMaker adopte un style **cyberpunk neon**:
- palette dominante rose/violet neon
- accents bleus pour les indicateurs techniques
- interfaces sombre profondes, contraste eleve

## Politique theme

- **dark theme uniquement**
- aucun theme light prevu
- toutes les nouvelles vues doivent reutiliser les tokens globaux du theme

## Tokens globaux

Source de verite dans:
- `lib/app/theme/cyberpunk_palette.dart`
- `lib/app/theme/app_theme.dart`

Couleurs principales:
- `neonPink`
- `neonViolet`
- `neonBlue`
- `bgPrimary`, `bgSecondary`, `bgElevated`
- `textPrimary`, `textMuted`, `border`

## Règles UI

- les couleurs hardcodees dans les widgets sont a eviter
- utiliser le theme global et les extensions (`context.cyberpunk`)
- cartes, boutons et bordures suivent un look neon discret (pas agressif)
- conserver lisibilite et hierarchie visuelle avant l'effet "wow"

## Evolution

Quand de nouvelles pages arrivent (timeline avancee, preview, export):
- reutiliser la palette globale
- respecter le dark-only
- maintenir la coherence des composants (radius, borders, glow)
