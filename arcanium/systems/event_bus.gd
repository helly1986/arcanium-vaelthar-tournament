extends Node
## Autoload: EventBus
## Bus di eventi minimale per il dialogue system. Per ora solo shop_requested
## (trigger OPEN_SHOP): il negozio di Solan non esiste ancora, quindi nessuno
## ascolta il segnale — va bene così, è un placeholder per il futuro.

signal shop_requested(npc_id : String)
## Richiesta di aprire l'Atlante (la mappa del regno). La alza il trigger
## OPEN_ATLAS nel dialogo di Mira; l'ascoltatore sara' il modale dell'atlante.
signal atlas_requested(npc_id : String)
