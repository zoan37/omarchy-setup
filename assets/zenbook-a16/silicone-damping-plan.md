# Zenbook A16 (UX3607OA): coil-whine damping, step by step (pad + pads-or-putty + silicone)

Goal: soften the residual VRM whine mechanically: a soft pad that couples the bottom cover to the cooler's VRM
plate; on the VRM inductor clusters either **thermal pads on the cube tops or thermal putty between the cubes**
(decided with the cooler out, from photos: step 6); silicone on the charger inductor; a small pad on the SSD or
Wi-Fi card only if the press test points at them. Expectation: softer, not silent; capacitor / board-flex noise
is untouched. Opening the machine ends any exchange option. Photos of
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

Maybe, once the gap is measured (step 6): **soft thermal pad 0.5 mm and/or 1.0 mm** (ARCTIC TP-3 comes in
both) for the pad option on the clusters, if the gap under the VRM plate is under ~1.2 mm. The 1.5 mm sheet
above only fits a gap of ~1.2 mm or more.

Do not buy: thermal paste (fluid, gives zero damping, and the SoC pad is not being touched), an ESD strap (touch
the chassis), any other glue.

**Rule: one material per part.** Putty needs bare surfaces to fill and wipe; a cured silicone skin under it
defeats both, and a pad on top of putty just squeezes it out. Each cluster = pads or putty. Charger inductor =
silicone only.

## Where the parts are (board seen from the bottom, cover and cooler removed)

1. **Main VRM cluster**: ~15 dark cube inductors around a PMIC with a black putty blob, on one side of the SoC.
   CPU/GPU rails; the tone tracks the CPU rail. Putty.
2. **Second cluster**: ~8 cubes around another putty-covered PMIC on the other side of the SoC, above the blue
   rubber foot, next to the Wi-Fi card (under the black rubber block). Putty.
3. **Charger**: one or two visibly larger inductors near the USB-C port used for charging, reachable with the
   cover off (not under the cooler). Silicone. Only audible when charging with the machine off.
4. **SSD and Wi-Fi card** (M.2 cards, cover off, not under the cooler; the Wi-Fi card sits under a black rubber
   block). Each card has its own small regulator and inductor. Suspects because the mic tied the 8.9 kHz tone to
   the SSD's PCIe link power state and the 6.8 kHz tone to the Wi-Fi card's power path (guide section 8), so the
   sound may come from the card itself rather than the board. Press test only; a small pad if it says so (step 3b).

Everything else (panel, ports, PMICs, SoC, memory) is left alone. The inductors face the **bottom cover**,
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
  ear at the board, chopstick on the black VRM plate and on the visible edges of each cluster, then **on the SSD
  (its small inductor if one is visible, else the middle of the card) and on the Wi-Fi card / its rubber block**.
  Press one spot at a time and note which ones change the tone. Pitch drops or dulls under pressure ⇒ damping
  there will do roughly the same. Never run the machine with the heatsink removed.
- **Gap:** a pea of Blu-Tack on the VRM plate, cover on with two screws, cover off, measure the squashed
  thickness. Under ~1.5 mm ⇒ one layer of TP-3; more ⇒ two layers.
- **Charger:** laptop off, brick plugged in: ear on the brick, then on the chassis by the port, chopstick on the
  big charger inductor. If the brick itself whines, nothing on the board helps (see step 6b).

## Step 3: pad on the cover (no cooler removal)

Cut TP-3 to the size of each black VRM plate (both sides of the SoC), peel one film, stick it to the **inside of
the cover** where it will land on the plate, peel the other film. Stack two if the gap said so. Keep it off the
fan intakes and vents. Cover on with four screws, power up, listen. If this is enough, finish the screws and stop
here; the cooler never comes out.

## Step 3b: SSD / Wi-Fi card pad (only if the press test changed the tone there)

Close-up photo of the card first (both sides are not needed; the top faces the cover). Then a piece of TP-3 cut
to the card's inductor or the noisy area, thick enough to touch the inside of the cover lightly (Blu-Tack gap
check as in step 2). Keep it off the M.2 connector and the antenna connectors on the Wi-Fi card; the SSD label
can stay on. A pad from SSD to cover also cools the SSD a little, which is harmless.

## Step 4: power down and disconnect the battery (only if going on to putty)

- Shut down. Battery connector at the board edge: slide the metal cap up, lift the connector's sides, unplug.
  The battery itself stays in.
- Hold the power button 10 s.

## Step 5: cooler out

- Unplug both fan connectors. 6 screws around the fans; free the cables and tape; lift the fans out.
- 4 screws on the CPU block: loosen in a cross pattern, half a turn each, then remove. Lift the heatpipe assembly
  gently, it is stuck to the pads. Set it aside **face up**. Do not touch the grey SoC pad or the memory patties.

## Step 6: pads or putty on the clusters (decide here)

**Photos first:** each cluster straight down and at a low angle (to see the cube heights), and the underside of
the cooler's VRM plates. Then **measure the real gap**: a small pea of Blu-Tack on the cube tops of each
cluster, cooler back on with the four CPU screws snug, cooler off, measure the squashed thickness. Send photos +
gap to Claude to choose.

Both damp by contact, not by blocking sound: a 1 mm pad is too thin and light to stop a 7–9 kHz tone passing
through it; it works by pressing on the parts and turning their vibration into heat. What matters is firm
contact over as much of each part as possible.

**Option A: pads on the cube tops** (cleaner, removes in one piece; NovaCustom reports 50–80 % on its laptops
this way). Pick a pad **0.25–0.5 mm thicker than the measured gap** (soft pads compress 20–30 %). Cut to cover
the cube tops of the cluster, **not the PMIC** in the middle (the plate's own putty blob must land on bare chip).
Uneven cube heights ⇒ separate pieces per height or putty instead. Too thick lifts the plate off the PMICs and
can change the cooler's pressure on the SoC; step 9 checks for that.

**Option B: putty between the cubes** (fits any gap and uneven heights, couples the cubes to each other and the
board, messier). As follows.

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

- If pads went on the clusters: compare SoC temperature under a sustained load against a "before" run (same
  load, same fan setting). Clearly hotter ⇒ the pad is holding the cooler off; go one size thinner.
- Same test as before: ear at the keyboard, laptop on the left, fan at the 700 rpm floor. Listen after the cover pad
  and again after the cluster pads/putty so each earns its place.
- Quiet room + webcam: `whine-round8.sh` from `whine-mic/` gives numbers at 6.8 / 8.9 kHz; take a "before" the
  day the parts arrive if possible.

## What was actually done (2026-09-27)

The cover came off (pry order: hinge corners, both sides, front, hinge edge last). Findings and choices:

- **Press test / chopstick stethoscope:** no audible change anywhere, with the fan stopped over SSH
  (`a16-fan.sh manual 0` with a timed restore of `a16-fan-daemon`). Fan motor ruled out: the whine stays at 0 rpm.
- **Nothing under the fans:** the board is cut around both fans (TechPowerUp's no-cooling photo, saved as
  `~/Pictures/a16-teardown/tpu-*.jpg` on the SER8). The port-side fan's metal tab (the stepped black block next to
  the fan) carries factory pads onto the two largest port-side coils (likely charging / system power); it is part of
  the fan and cannot be lifted alone.
- **Pads (TP-3, stacked where the gap needed it), no cooler removal:** the three cooler VRM plates (above the upper
  bracket, the plate with the white window, the plate below the lower bracket), the fan tab, and one large pad over
  the whole USB-C/HDMI section (ports, USB-C controller chips, the coils next to `L62300`).
- **Putty (UPSIREN, pink):** packed around the fan tab's edges, and one blob each on the exposed coils L61800/L61801,
  L9801-L9805 (around U7901 by the keyboard connector), L10550 (by the audio jack) and the "3R3" coil L60200 near the
  TP connector. Kept flat, off connectors and the fan.
- **Not touched:** heatpipes, cold plate, bracket, grey foam strips, the blue rubber support cubes, SSD, Wi-Fi.
- **Silicone:** not used.

Later the same day more went in: pads on the SSD (controller end), the USB-A board and the power cluster left of
the upper cooler bracket (putty in its gaps), thin pads on top of the putty blobs. Final result by ear with the cover
closed: **coil whine "much less now"**. Earlier interim result: high pitch clearly fainter; a buzz remains at the port side, louder while fast-charging
(~80 W at 32 %). CPU tweaks re-tuned afterwards (guide section 8: cpu6-11 at 3.63 GHz, deep idle off).
