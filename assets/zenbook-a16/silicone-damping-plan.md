# Zenbook A16 (UX3607OA): coil-whine damping, step by step (pad + putty + silicone)

Goal: soften the residual VRM whine mechanically: a soft pad that couples the bottom cover to the cooler's VRM
plate, thermal putty packed between the VRM inductors, silicone on the charger inductor. Expectation: softer,
not silent; capacitor / board-flex noise is untouched. Opening the machine ends any exchange option. Photos of
every step: TechPowerUp review, "Disassembly" page (techpowerup.com/review/asus-zenbook-a16-ux3607oa/5.html);
local copies of the two useful ones in `~/Pictures/a16-teardown/` on the SER8.

## Shopping list (ordered 2026-09-26)

- **ARCTIC TP-3 thermal pad, 100 × 100 × 1.5 mm.** For the inside of the bottom cover over the VRM plate. Soft
  and lossy (that is the point, conductivity is a bonus), compresses to ~1 mm, stacks if the gap is bigger.
  Alternatives if ever needed: 1 mm self-adhesive silicone sponge, Poron 4701-30. Not EVA, Sorbothane or butyl.
- **UPSIREN UTP-6 thermal putty, 10 g** (non-conductive, non-curing). For the two VRM inductor clusters. Softest
  and heaviest option, fills every gap, conducts heat into the plate, wipes off completely. 10 g is ~5× the job.
- **ASI 388 electronic-grade neutral-cure silicone, 2.8 oz** (clear, non-corrosive; never acetic-cure /
  vinegar-smelling). For the charger inductor only: a lone part at the board edge, unconfined, where bonding
  beats fill.
- precision driver set with **Torx T5** and **Phillips PH0 / PH00**; plastic pry tool or old credit card;
  wooden toothpicks (applicator) and a wooden chopstick (press test); a scrap of card; paper towels; tape or a
  magnetic dish for screws (lengths differ); a pea of Blu-Tack / modelling clay for the gap measurement.
- Optional: isopropyl alcohol + cotton buds (only for removing putty later).

Do not buy: thermal paste (fluid, gives zero damping, and the SoC pad is not being touched), an ESD strap (touch
the chassis), any other glue.

**Rule: putty and silicone never on the same part.** Putty needs bare surfaces to fill and wipe; a cured silicone
skin under it defeats both. Clusters = putty only. Charger inductor = silicone only.

## Where the parts are (board seen from the bottom, cover and cooler removed)

1. **Main VRM cluster**: ~15 dark cube inductors around a PMIC with a black putty blob, on one side of the SoC.
   CPU/GPU rails; the tone tracks the CPU rail. Putty.
2. **Second cluster**: ~8 cubes around another putty-covered PMIC on the other side of the SoC, above the blue
   rubber foot, next to the Wi-Fi card (under the black rubber block). Putty.
3. **Charger**: one or two visibly larger inductors near the USB-C port used for charging, reachable with the
   cover off (not under the cooler). Silicone. Only audible when charging with the machine off.

Everything else (SSD, panel, ports, PMICs, SoC, memory) is left alone. The inductors face the **bottom cover**,
under the fans and the heatpipe assembly.

**The cooler from underneath** (TechPowerUp "cooling-bottom" photo): a copper block with a grey pad on the SoC
die and two putty patties on the memory dies; on each side a **thin black sheet-metal plate** (square cut-outs)
extending over the VRM clusters. Those plates carry round putty blobs that land on the **PMICs only**; the
inductor cubes touch nothing and sit in an air gap under the plate, ~0.5–1.5 mm, set by the squashed PMIC blobs.
So: the thin plate is the resonator the cover pad should press on; putty between the cubes is confined by the
plate and stays put; and putty must stay **level with the cube tops or lower**, because the PMIC blobs set the
plate height and a mound would lift the plate off the PMICs.

## Before opening

- Charge to ~50 %, shut down fully (`systemctl poweroff`), unplug, wait a minute.
- Clean table, lid closed, laptop upside down on a cloth. Lay screws out in the pattern you removed them.

## Step 1: bottom cover

- 10 Torx screws; note which holes take the longer ones.
- Pry behind the hinge cover near the edges first, then around the sides from a lifted corner; the rear exhaust
  vents are part of the cover, release the rear last.
- Take photos: the whole board, each VRM plate, the charger area by the port, the inside of the cover.

## Step 2: look and measure (optional but cheap)

- **Press test:** power on with the cover off (battery connected, lid open enough to see it boot), idle a minute,
  ear at the board, chopstick on the black VRM plate and on the visible edges of each cluster. Pitch drops or
  dulls under pressure ⇒ damping will do roughly the same. Never run the machine with the heatsink removed.
- **Gap:** a pea of Blu-Tack on the VRM plate, cover on with two screws, cover off, measure the squashed
  thickness. Under ~1.5 mm ⇒ one layer of TP-3; more ⇒ two layers.
- **Charger:** laptop off, brick plugged in: ear on the brick, then on the chassis by the port, chopstick on the
  big charger inductor. If the brick itself whines, nothing on the board helps (see step 6b).

## Step 3: pad on the cover (no cooler removal)

Cut TP-3 to the size of each black VRM plate (both sides of the SoC), peel one film, stick it to the **inside of
the cover** where it will land on the plate, peel the other film. Stack two if the gap said so. Keep it off the
fan intakes and vents. Cover on with four screws, power up, listen. If this is enough, finish the screws and stop
here; the cooler never comes out.

## Step 4: power down and disconnect the battery (only if going on to putty)

- Shut down. Battery connector at the board edge: slide the metal cap up, lift the connector's sides, unplug.
  The battery itself stays in.
- Hold the power button 10 s.

## Step 5: cooler out

- Unplug both fan connectors. 6 screws around the fans; free the cables and tape; lift the fans out.
- 4 screws on the CPU block: loosen in a cross pattern, half a turn each, then remove. Lift the heatpipe assembly
  gently, it is stuck to the pads. Set it aside **face up**. Do not touch the grey SoC pad or the memory patties.

## Step 6: putty on the clusters

Pinch a pea of UTP-6, press it into the gaps between the cubes of cluster 1 and around their bases with a
toothpick or fingertip, until the cluster is one filled block **level with the cube tops, no higher**. Same for
cluster 2. Nothing on the PMICs (the plate's blobs must land on bare chips), nothing on the cube tops, nothing on
the SoC or memory. Wipe strays with a paper towel; it never cures, so there is no clock. A gram or two total.

## Step 7: silicone on the charger inductor

Dispense a pea of ASI 388 onto the card (not from the nozzle). Toothpick tip in it, touch it to the base of the
big charger inductor so it wicks under the edge, run a thin fillet around the base; a dab between it and a
neighbour if there is one. Nothing on the charger IC or the port. Wipe smears while still gel. Let it skin over,
20–30 minutes, before the cover goes on.

## Step 8: reassemble

- Cooler back: seat it square, CPU screws in a cross pattern in stages until snug (not tight), fans in (6 screws),
  fan connectors, battery connector (push down, slide the cap back).
- Cover: check it sits flat over the pad with light hand pressure before any screws; if it rocks, the pad is too
  thick (remove a layer). Then the 10 screws.
- Silicone reaches full cure in 7 days; use the laptop normally, avoid a sustained heavy load on day one. Putty
  and pad need no cure.

## Step 6b (any time): the USB-C charging whine, diagnosis

A separate circuit. All with the laptop **off**:

1. **Brick or board?** Ear on the brick, ear on the chassis by the port, and the brick in the wall with nothing
   attached (some bricks whine at no load). Brick ⇒ a different or lower-wattage USB-C PD brick (30–65 W); no
   65–100 W GaN model has a "never whines" record.
2. **Which charge stage?** Plug in at ~40 % (bulk) and at ~95 % (trickle). Whine only near full = the charger
   IC in light-load mode at the end of charge (a ROG G16 owner sees the same at the 80 % cap). Cheap answer:
   unplug once full, or a charge limit if the battery driver ever answers (`charge_control_end_threshold`
   exists on this kernel; the battery manager does not respond yet).
3. **Board?** Step 7 above.

## Step 9: judge it

- Same test as before: ear at the keyboard, laptop on the left, fan at the 700 rpm floor. Listen after the pad
  and again after the putty so each earns its place.
- Quiet room + webcam: `whine-round8.sh` from `whine-mic/` gives numbers at 6.8 / 8.9 kHz; take a "before" the
  day the parts arrive if possible.
