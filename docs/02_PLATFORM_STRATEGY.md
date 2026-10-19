# Strategia multipiattaforma & commerciale — Arcanium

> Target commerciali: **PC** (Steam, GOG), **PC handheld** (Steam Deck, ROG Ally, Legion Go), **console** (PS5, Xbox Series S/X, Nintendo Switch 2).
> Questo documento definisce le decisioni e le regole di architettura da rispettare FIN DALLA FASE 0 perché il progetto sia portabile a basso costo. Chi implementa deve leggerlo prima di aggiungere I/O, input, salvataggi o servizi online.

## 1. Realtà del porting su Godot (cosa possiamo spedire e quando)

| Target | Stato con Godot 4.7 | Note |
|---|---|---|
| Windows / Linux (Steam, GOG) | ✅ Export ufficiale, spedibile subito | GOG = build DRM-free (non integriamo DRM) |
| Steam Deck | ✅ È un PC Linux (Proton/nativo) | 1280×800, budget ~15W: target di tuning, non un export separato |
| ROG Ally / Legion Go | ✅ PC Windows | Come sopra, budget prestazionale ridotto |
| PS5 / Xbox Series / Switch 2 | ⚠️ **Nessun export ufficiale Godot** | Serve porting house o self-porting (vedi sotto) |

**Console — le due strade (da attivare in Fase 5+, non ora):**
- **Porting house / middleware**: la via più pulita è **W4 Games** (fondata dai core dev di Godot, vende il supporto export console). Alternative: Lone Wolf Technology, Pineapple Works.
- **Self-porting**: richiede registrazione come sviluppatore Sony/Microsoft/Nintendo, devkit sotto NDA, e port del layer di piattaforma. Molto oneroso.

**Implicazione chiave:** non portiamo nulla ora, ma **architettiamo perché il port costi poco**. Tutto ciò che è specifico di piattaforma va dietro una nostra interfaccia (§3).

## 2. Renderer — DECISIONE PRESA: **Mobile**

- Impostato in `project.godot`: `renderer/rendering_method="mobile"` (+ override `.mobile="mobile"`, rimosso il tag "GL Compatibility" da `config/features`).
- **Perché Mobile e non Forward+**: priorità sui target deboli (Switch 2 handheld, Steam Deck, Xbox Series S). Il Mobile renderer è Vulkan/D3D12, molto superiore alla GL Compatibility del template, con budget prestazionale sostenibile su hardware a basso wattaggio.
- **Vincoli di art direction accettati** (il Mobile renderer NON offre): SDFGI, Global Illumination in tempo reale avanzata, volumetric fog/light volumetrico completo, alcune feature di post-processing. → Illuminazione basata su **luci bake / lightmap + reflection probe**, non GI dinamica. Da tenere presente per le arene buie low-albedo di Arcanium: si punta su luci puntuali/spot e lightmap, non su GI.
- ⚠️ **Da verificare alla prima apertura in editor (Fase 1)**: il demo era autorato per GL Compatibility; materiali e luci potrebbero rendere diversamente. È previsto e accettabile — si ri-tara la scena demo.

## 3. Astrazioni obbligatorie (da creare quando servono, MAI chiamate dirette sparse)

Ogni sistema qui sotto deve avere UNA sola implementazione da riscrivere per il port. Regola: **nessun `OS.*`, path hardcoded o SDK di piattaforma fuori da questi wrapper.**

1. **`SaveManager`** — tutti i salvataggi passano di qui, sempre su `user://`. Le console hanno API di salvataggio proprie (slot, indicatori "salvataggio in corso"): un solo punto da adattare. Vietato scrivere file su path arbitrari.
2. **`AchievementService`** — interfaccia unica per Steam achievements / PS Trophy / Xbox achievement (tutti diversi). La build console deve compilare senza il codice Steam.
3. **`PlatformServices`** — storefront, rich presence, cloud save, presenza online. Stub no-op di default.
4. **`InputGlyphs`** — mostra i prompt corretti per periferica: ABXY Xbox, simboli PlayStation, layout Switch. Gestire hot-swap e disconnessione controller (requisito di certificazione).

## 4. Regole di input (console-first)

- Il template ha già mappatura gamepad completa (stile Elden Ring/Bloodborne): buona base.
- **Nessuna azione può richiedere solo tastiera/mouse**: tutto deve essere fattibile da controller.
- Gestire: hot-swap periferica, riconnessione controller con pausa automatica (cert), deadzone configurabili.
- UI navigabile interamente da stick/dpad (focus system di Godot).

## 5. Budget prestazionale & scalabilità

- **Target**: 60 fps su PS5/Series X/PC desktop; **fallback 30 fps previsto** per Switch 2 handheld e handheld PC a basso wattaggio.
- **Xbox Series S**: il collo di bottiglia (RAM condivisa ~8GB, spesso target 1440p). Il budget memoria/asset si dimensiona su questo, non su Series X.
- **Risoluzione dinamica** + preset qualità scalabili (ombre, densità particellari, distanza di culling).
- Le GLB Meshy mid-poly attuali sono coerenti col budget; mantenere disciplina su poligoni/texture (1K texture come già in pipeline).

## 6. Certificazione (TRC/XR/Lotcheck) — abitudini da prendere subito

Ogni console ha requisiti di cert. Costa poco se previsto da subito, molto se aggiunto dopo:
- **Suspend/resume** gestito (pausa automatica, ripristino stato).
- **Salvataggio robusto** con indicatore e nessuna corruzione se interrotto.
- **Gestione disconnessione controller** → pausa.
- **Nessun quit istantaneo**: `ui_cancel` apre il menu di pausa (già rimosso il `get_tree().quit()` dal player in Fase 0).
- Nessun crash, gestione errori pulita.

## 7. Versione Godot

- **Pinned su 4.7 stable.** Non aggiornare senza motivo: il middleware console insegue release stabili specifiche e ogni salto va rivalidato. Coordinare eventuali update con la scelta della porting house.

## 8. Steam / GOG (spedibili per primi)

- **Steam**: Steamworks via GodotSteam (GDExtension) per achievements/cloud/rich presence — **dietro `AchievementService`/`PlatformServices`**, così le altre build compilano senza.
- **GOG**: build DRM-free, nessuna integrazione Galaxy obbligatoria. Galaxy SDK opzionale, sempre dietro astrazione.
- Questi due sono la prima release realistica; le console seguono via porting house una volta raggiunto il contenuto.
