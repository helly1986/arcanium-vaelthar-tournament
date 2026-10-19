extends Resource
class_name ArcaniumSpellResource

## Dati di un incantesimo lanciabile dal player (o in futuro da un nemico
## incantatore). Ricalca i numeri di Lite/Constants.js (es. SPELL_ICE_SHARD:
## cost 5, damage 12, speed 17, radius 0.26, lifetime 1.6, color 0x9fe6ff) ma
## in forma di Resource .tres, coerente col pattern di ArcaniumEquipmentResource.
##
## SpellCaster.cast() legge questi campi per configurare il proiettile
## istanziato da `projectile_scene` e per verificare costo/cooldown.

## ─── Display ──────────────────────────────────────────────────────────────
@export var name : String = "Incantesimo"
@export var icon : String = "◈"
## Illustrazione mostrata sullo slot della SpellBar (come in Arcanium-Lite). Se
## null, la barra ripiega sull'`icon` testuale.
@export var image : Texture2D
@export_multiline var lore : String = ""

## ─── Costo / ritmo ────────────────────────────────────────────────────────
## Arcanium Vivo richiesto per lanciare (PlayerVitals.spend_arcanium).
@export var cost : float = 5.0
## Tempo minimo fra due lanci dello STESSO spell (SpellCaster tiene un
## cooldown per-spell, chiave = questa risorsa).
@export var cooldown : float = 1.2

## ─── Proiettile ───────────────────────────────────────────────────────────
@export var damage : int = 12
@export var projectile_speed : float = 17.0
@export var projectile_radius : float = 0.26
@export var lifetime : float = 1.6
@export var color : Color = Color("#9fe6ff")
## Quanto build-up di Congelamento infligge un colpo di questo spell (vedi
## FrozenEffect.add_buildup / ArcaniumHealthSystem._route_statuses).
@export var frozen_buildup : float = 0.0
## Tipo di danno, letto dalle resistenze del bersaglio (ArcaniumHealthSystem).
@export_enum("FISICO", "TAGLIO", "PERFORAZIONE", "SCHIANTO", "CRIO", "EROSIONE", "SACRO", "FRATTURA", "VELENO", "FUOCO", "FULMINE") var damage_type : String = "CRIO"

## Scena del proiettile da istanziare (es. ice_shard_projectile.tscn). Deve
## avere una root Area3D con script che espone: direction, speed, damage,
## radius, lifetime, color, frozen_buildup, damage_type, faction, caster
## (vedi ice_shard_projectile.gd per il contratto esatto).
@export var projectile_scene : PackedScene

## ─── Piazzamento posizionale (AoE) ─────────────────────────────────────────
## Se true, questo spell NON è a proiettile: il player controller intercetta
## la selezione PRIMA di chiamare SpellCaster.cast() ed entra in placement-mode
## (vedi PlacementController), poi risolve con SpellCaster.cast_positional()
## al centro scelto. Se false (default), comportamento invariato (proiettile).
@export var is_positional : bool = false
## Raggio dell'area d'effetto (m) — usato sia per il decal di piazzamento sia
## per il campo istanziato alla conferma.
@export var aoe_radius : float = 3.0
## Durata (s) del campo a terra dopo la conferma del piazzamento.
@export var aoe_duration : float = 2.0
## Quanto build-up di status (es. Congelamento) al SECONDO infligge il campo
## per bersaglio nel raggio, letto da spell_aoe_field.gd. Alto di proposito per
## spell come "Morsa del gelo" che devono proccare quasi subito.
@export var aoe_status_buildup_per_sec : float = 0.0
## Scena del campo AoE da istanziare al centro scelto (vedi spell_aoe_field.gd
## per il contratto: radius, duration, color, status_buildup_per_sec, damage_type).
@export var aoe_field_scene : PackedScene
