# Zenbook A16 (UX3607OA): coil-whine damping with silicone, step by step

Goal: soften the residual VRM whine by tying the power inductors to the board with neutral-cure silicone.
Expectation: softer, not silent. Capacitor / board-flex noise is untouched. Opening the machine and gluing parts
ends any exchange option. Photos of every step: TechPowerUp review, "Disassembly" page
(techpowerup.com/review/asus-zenbook-a16-ux3607oa/5.html).

## Shopping list

- **Upsiren UTP-8 thermal putty, 10 g** (non-conductive, non-curing): the preferred material for the inductor
  clusters. Softest and heaviest of the options, packs into every gap, conducts heat to the VRM plate, and comes
  off completely. Best field record for VRM whine.
- ASI 388 electronic-grade neutral-cure silicone, 2.8 oz tube (clear, non-corrosive; **not** acetic-cure /
  vinegar-smelling): the bonding fallback, for a part that rocks on its joints, a lone inductor (charger), or a
  cluster edge where putty would migrate.
- for the cover-side damping (step 2b): **1 mm self-adhesive silicone sponge sheet** (e.g. 250×250 mm, ~$10–15 on
  Amazon) or Poron 4701-30 very-soft foam 0.8–1.6 mm with adhesive; or a **1.5 mm soft thermal pad** (Arctic /
  Gelid) for the same job with a thermal bonus. Not EVA, not Sorbothane, not butyl (Dynamat/Kilmat)
- precision driver set with **Torx T5** and **Phillips PH0 / PH00**
- plastic pry tool, or an old credit card / guitar pick
- wooden toothpicks (applicator) and a wooden chopstick (press test)
- a scrap of card to dispense onto, paper towels, optional isopropyl alcohol + cotton buds
- tape or a magnetic dish to keep screws sorted (lengths differ)

Do not buy: thermal paste (the cooler uses pads and you are not disturbing the CPU face), ESD strap (touch the
chassis), any other glue.

## Where the parts are (board seen from the bottom, cover and cooler removed)

1. **Main VRM cluster, priority 1**: ~15 dark cube inductors packed around a PMIC with a black putty blob, on one
   side of the SoC. CPU/GPU rails: the tone tracks the CPU rail, so this is the target.
2. **Second cluster, priority 2**: ~8 cubes around another putty-covered PMIC on the other side of the SoC, above the
   blue rubber foot, next to the Wi-Fi card (the module under the black rubber block).
3. **Charger, optional**: one or two visibly larger inductors near the USB-C port used for charging. Only audible
   when charging with the machine off.

Everything else (SSD, panel, ports) is left alone. The inductors face the **bottom cover**, under the fans and the
heatpipe assembly; the cooler has a VRM plate resting on cluster 1 through a pad.

## Before opening

- Charge to ~50 %, then shut down fully (`systemctl poweroff`), unplug the charger, wait a minute.
- Work on a clean table, lid closed, laptop upside down on a cloth.

## Step 1: bottom cover

- 10 Torx screws. Note which holes take the longer ones.
- Start the pry behind the hinge cover near the edges, then work around the sides from a lifted corner; the rear
  exhaust vents are part of the cover, release the rear last with the pry tool.

## Step 2: press test (before removing anything else)

Power on with the cover off (battery still connected, lid open enough to see it boot). Let it idle a minute.
Ear at the board. Press the chopstick on:

- the visible edge of cluster 1 and the VRM plate above it,
- cluster 2,
- and, with the laptop **off** and the charger plugged in, the big charger inductor.

Tone drops or dulls under pressure ⇒ silicone will do roughly the same. No change on a cluster ⇒ skip that cluster.
Never run the machine with the heatsink removed.

## Step 2b: foam on the cover (cheapest fix, try before any glue)

With the cover off, look at the VRM plate (the metal plate on the heatpipe assembly over cluster 1) and the
inside of the cover above it. Cut a strip of the 1 mm silicone sponge / Poron / 1.5 mm thermal pad the size of
the plate, stick it to the **inside of the cover** so it presses on the plate when the cover is on (a Dell XPS
write-up with 1.5–2.5 mm pads in the same place reports a lasting, noticeable reduction). Put the cover back
with four screws and listen. If the gap is larger than the pad, stack two. Keep it off the fans and vents.
Then decide whether to go on to the silicone.

## Step 3: power down and disconnect the battery

- Shut down. Battery connector is at the board edge: slide the metal cap up, lift the connector's sides, unplug.
  (Five screws hold the battery; it can stay in place.)
- Hold the power button 10 s to drain.

## Step 4: cooler out

- Unplug both fan connectors. 6 screws around the fans; untangle the cables and tape over the housings; lift the
  fans out.
- 4 screws on the CPU heat spreader (there is usually a numbered order; loosen in a cross pattern, half a turn
  each, then remove). Pry the heatpipe assembly up gently, it is stuck to the pads. Set it aside face up. Do not
  touch the CPU pad.

## Step 5: apply

Putty first, silicone only where bonding is needed.

**Putty:** pinch a pea, press it into the gaps between the cubes of cluster 1 and around their bases with a
toothpick or a fingertip, so the cluster becomes one filled block up to roughly the top of the parts. Same for
cluster 2. Keep it off the tops (the plate's pad sits there) and off the PMICs. Wipe stray putty with a paper
towel; it never cures, so there is no clock.

**Silicone (where the press test showed a single part moving, or for the charger inductor):**

- Dispense a pea of silicone onto the card. Do not apply from the nozzle.
- Toothpick tip in the silicone, then touch it to the base of an inductor so it wicks into the gap between part
  and board; run it around the base. Then a small dab in each gap between neighbouring cubes.
- Cluster 1 (~15 parts), then cluster 2 (~8), then the charger inductor(s) if the press test said so.
- **Nothing on the tops** of the inductors (the VRM plate and its pad sit there) and **nothing on the PMICs** with
  the putty (they must keep touching the cooler). Nothing on the SoC or its pad.
- Stray smears: wipe with a paper towel while still gel; peel after cure.
- Total used: well under a gram.

## Step 6: wait, then reassemble

- Let it skin over: 20–30 minutes, no longer tacky. Reassemble after that, or after a few hours if you can wait.
- Cooler back on: seat it, CPU screws in a cross pattern in stages until snug (not tight), fans in with their 6
  screws, fan connectors, battery connector (push down, slide the cap back), cover, 10 screws.
- Full cure is 7 days; use the laptop normally, avoid a sustained heavy load on day one.

## Step 7: judge it

- Same test as before: ear at the keyboard, laptop on the left, fan at the 700 rpm floor.
- If a quiet room is available: `whine-round8.sh` from `whine-mic/` gives numbers at 6.8 / 8.9 kHz for a
  before/after, so record a "before" the day the tube arrives.
