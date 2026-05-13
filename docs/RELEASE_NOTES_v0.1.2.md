## PocketSunoMaker v0.1.2

### Nouveautes

- Export **fidele preview** frame-by-frame : chaque image est rendue par le meme moteur Flutter que la preview, puis assemblee en MP4 par FFmpeg avec mux audio.
- **Profilage machine** avant l’export (CPU, memoire via `sysctl`, batterie ou secteur via `pmset`) avec modes `safe` / `balanced` / `performance` et cadence entre captures.
- Pendant l’export : **badge** « Export fidele en cours (controles verrouilles) », **progression**, **temps restant estime**, **annulation** possible.
- Fichier de diagnostic **`.export-debug.txt`** a cote du MP4 pour analyser parametres FFmpeg et erreurs.

### Ameliorations

- Alignement preset / **resolution de capture** (canvas preview a la taille de sortie).
- Stabilisation de la timeline **sans gel** lors de captures successives avec **video en pause** (seek systématique a chaque pose d’export, au lieu du seuil historique ~80 ms qui dupliquait des frames alors que l’audio avancait).
- Attentes **cadrees** avant capture (`endOfFrame` + petite marge decodeur).

### Correctifs

- Parité visuelle export vs preview pour effets complexes (priorité au rendu fidèle plutôt qu’a la chaine filtres FFmpeg seule).
- Robustesse FFmpeg (filtres, bruits, parametres hors plage selon builds).

### Notes techniques

- Build cible: **macOS** (universal x86_64 + arm64)
- Binaire **Developer ID** avec **notarisation Apple** (ticket appose sur l’app puis zip final)
- Artifact publie sur GitHub : `PocketSunoMaker-macos-v0.1.2.zip`
- SHA256 : `45922f9530886f396c6f4bafe7bf2af055d09d44c6b80667ba0bb2690e0571c1`

Tag Git : `v0.1.2`

### Prochaines etapes (ROADMAP)

- Recapitulatif pre-export materiel dedie dans l’UI ; pause / reprise d’export long.
- Checkpoint / reprise apres erreur pendant la sequence PNG.
- Selecteur explicite **Rapide (FFmpeg)** vs **Fidele** dans l’onglet Export.

