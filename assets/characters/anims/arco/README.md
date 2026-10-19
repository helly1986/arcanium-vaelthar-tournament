# Clip d'arco per il PROTAGONISTA

Le stesse clip di `assets/characters/enemies/anims/sword/` (autorate dall'utente in
Cascadeur sul rig Nephilite), importate una seconda volta con il profilo del
**player**: bone map `nephilite_humanoid.tres` **e** `fix_silhouette` acceso
(filtro sui piedi, soglia 15), come `protagonista_v4.glb.import`.

⚠️ Perche' due import dello stesso file. I due rig hanno le stesse rotazioni di
riposo (canoniche, dal bone map) ma non le stesse POSIZIONI: il Nephilite
riposa nella stance di combattimento (l'avambraccio sta a (-0.014, 0.146, 0.238)
dal gomito), il player in T-pose (0, 0.298, 0). Una rotazione di posa e' relativa
a quella geometria: la clip dei nemici, caricata cruda sul player, alzava l'arco
sopra la testa. `fix_silhouette` riscrive le tracce per il riposo a silhouette,
che e' quello del player. Le clip di `enemies/anims` NON vanno toccate: sul
Soldato Scelto sono giuste cosi'.

`set_arco.tres` punta qui. Se una clip si riautora, si ricopia il GLB e basta:
il `.import` resta.
