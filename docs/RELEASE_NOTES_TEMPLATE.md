# Release Notes Template (incremente)

Ce template est volontairement court: il sert aux releases regulieres (ex: `v0.1.1`, `v0.1.2`) avec focus sur les changements depuis la version precedente.

## 1) Template markdown

Copier/coller et adapter:

```md
## PocketSunoMaker vX.Y.Z

### Nouveautes
- ...
- ...

### Ameliorations
- ...
- ...

### Correctifs
- ...
- ...

### Notes techniques
- Build cible: macOS
- Artifact: `PocketSunoMaker-macos.zip`
- SHA256: `...`

### Prochaines etapes (ROADMAP)
- ...
- ...
```

## 2) Exemple concret (v0.1.1)

```md
## PocketSunoMaker v0.1.1

### Nouveautes
- Finalisation de l'overlay texte v1 (workflow edition plus fluide).
- Premiere iteration d'effets pluginables (selon avancement M4).

### Ameliorations
- UX timeline/panneaux peaufinee pour sessions longues.
- Qualite et lisibilite preview/export alignees sur le preset de sortie.

### Correctifs
- Stabilisation des cas limites export FFmpeg.
- Corrections diverses de regressions UI/interaction.

### Notes techniques
- Build cible: macOS
- Artifact: `PocketSunoMaker-macos.zip`
- SHA256: `<a-remplir>`

### Prochaines etapes (ROADMAP)
- Effets pluginables: extension progressive.
- UX avancee: undo/redo, marqueurs, raccourcis.
```

## 3) Commande GitHub Release (gh)

Remplacer `vX.Y.Z` et le contenu des notes:

```bash
gh release create vX.Y.Z \
  "build/macos/Build/Products/Release/PocketSunoMaker-macos.zip" \
  --title "PocketSunoMaker vX.Y.Z" \
  --notes "$(cat <<'EOF'
## PocketSunoMaker vX.Y.Z

### Nouveautes
- ...

### Ameliorations
- ...

### Correctifs
- ...

### Notes techniques
- Build cible: macOS
- Artifact: `PocketSunoMaker-macos.zip`
- SHA256: `...`

### Prochaines etapes (ROADMAP)
- ...
EOF
)"
```

## 4) Mini checklist avant publication

- Build release OK: `flutter build macos --release`
- Zip regenere: `PocketSunoMaker-macos.zip`
- Hash calcule: `shasum -a 256 ...`
- Tag pousse: `git push origin vX.Y.Z`
- Release publiee via `gh release create`
