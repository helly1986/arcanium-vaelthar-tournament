"""Le domande per Jev: una Choice per l'azione, e un Noul di significato per
ogni nemico in vista.

Regole dalla documentazione (docs.typesafe.ai, "How to build", "Jev 1.13
jaggedness"), che qui si seguono apposta:
  - una domanda = un giudizio stretto; le domande NON vedono le risposte delle
    altre, quindi ogni premessa sta scritta per intero dentro la domanda;
  - si punta allo stato con i percorsi fra backtick (`observed.enemies[2]`);
  - in inglese, la lingua in cui Jev rende meglio;
  - niente conti: lo stato e' gia' in parole (lo prepara osservatore.gd).

⚠️ Cosa NON si chiede piu' a Jev, e perche' (misurato nella prima partita,
2026-10-07, 1.320 risposte, vedi docs/15_PLAYTEST_JEV.md): "nemico vicino che
non attacca" e "colpo senza aggressore" sopra 0,8 erano veri nello 0% e nel 3%
dei casi. Jev scambiava "close" per "very close", mescolava le condizioni di
nemici DIVERSI della lista e ignorava "just now" contro "a moment ago". Sono
condizioni che il codice calcola esattamente: restano ai sorveglianti
(sorveglianti.gd). A Jev resta il giudizio di SIGNIFICATO, e uno per nemico,
non "c'e' qualcuno nella lista che...".

Gli id delle domande servono solo al codice: il modello non li vede. Le soglie
sono un primo tentativo dichiarato; le risposte grezze si salvano tutte, cosi'
una soglia nuova non richiede di rifare l'inferenza.
"""

# Soglia provvisoria oltre cui un Noul chiede una cattura di fotogrammi.
SOGLIA_CATTURA = 0.8
# Fascia "incerto": un Noul qui dentro si scala a Claude, non si conta.
FASCIA_INCERTA = (0.35, 0.65)
# Prefisso degli id dei Noul per nemico: "anim_<indice>".
PREFISSO_ANIM = "anim_"


def domanda_azione(criteri: dict) -> dict:
    return {
        "type": "choice",
        "instructions": {
            "question": "Which action should the player take right now?",
            "goal": "Defeat the enemies that stand in the way, then reach `observed.objective`. "
                    "Fighting is part of the task: strike when an enemy is recovering after its attack, "
                    "staggered or low on health, and defend only when a strike is coming.",
            "focus": "Use `observed` (facts) and `inferred` (the code's reading of the facts). "
                     "Choose only among the listed options.",
        },
        "criteria": criteri,
    }


def domanda_animazione(i: int) -> dict:
    e = f"`observed.enemies[{i}]`"
    return {
        "type": "noul",
        "instructions": {
            "question": f"Does the animation named in {e}.animation contradict what {e}.state and "
                        f"{e}.attack say this one creature is doing?",
            "contradictions": [
                "a death or lying-down animation while the state is chasing or fighting",
                "an idle or standing animation while the attack is winding up or striking",
                "a running animation while the state is dead",
                "a howl animation while the attack says it is biting",
            ],
            "not_contradictions": [
                "a bite, leap or attack animation while fighting",
                "a run or walk animation while chasing",
                "an idle animation while idle or between attacks",
                "a hit or stagger animation right after being hit",
            ],
        },
        "criteria": {
            "true": "The animation shows something different from what the state and attack describe.",
            "false": "The animation fits the state and attack, or is a normal transition between them.",
        },
    }


def domande(criteri: dict, stato: dict) -> dict:
    q = {"action": domanda_azione(criteri)}
    for i, _ in enumerate(stato.get("observed", {}).get("enemies", [])):
        q[f"{PREFISSO_ANIM}{i}"] = domanda_animazione(i)
    return q
