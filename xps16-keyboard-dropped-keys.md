# Dell XPS 16 (DA16260) keyboard: dropped and out-of-order keystrokes

**Date:** 2026-09-18
**Machine:** Dell XPS 16 DA16260 (Panther Lake)
**OS:** Omarchy Linux 4.0.4 (Arch-based; Windows not tested on this machine) · Hyprland 0.56.2 · kernel 7.2.5-3-omarchy · libinput 1.31.3 · fcitx5 5.1.22
**BIOS:** 1.10.1 (2026-07-20) at the start of testing, then updated to **1.11.0** (Dell release of 2026-09-09)

## Summary

The XPS 16's built-in keyboard **loses keystrokes before they reach Linux**. When keys are pressed in quick succession, the keyboard stops reporting for a moment, then catches up by sending only its current state. Any key pressed and released during that pause is lost. A key that was held during the pause can look as if it was held much longer, which sets off key repeat and produces extra characters (`qqqqqqq`).

This matches Dell's known issue [000435203, "Laptop Keyboard Mistyping When Typed Quickly"](https://www.dell.com/support/kbdoc/en-us/000435203/laptop-keyboard-mistyping-when-typed-quickly). That article lists the XPS 16 DA16260 as affected and says BIOS 1.4.1 fixes it. **It still happens on BIOS 1.10.1 and on the latest BIOS, 1.11.0.** With 1.11.0, 9 of 19 test swipes came through complete (47%), up from 0 of 7 on 1.10.1. That's an improvement, but the problem is still there.

A Dell XPS 13 running the same Omarchy setup **passes the same test perfectly**, and so does an **external USB keyboard plugged into this XPS 16** (11 of 11). That rules out Linux, Omarchy, the configuration, and the rest of the laptop. The fault is in the built-in keyboard. This is a hardware or firmware defect on the XPS 16 and should be handled by Dell warranty support.

A side observation: a palm resting on the touchpad can nudge the pointer while you type, and Linux can't tell palms from fingers on this touchpad. It **doesn't explain the missing letters**, though. The symptoms happen with a single window on the workspace, so there's no other window for keystrokes to go to, and the keyboard defect fully explains them.

## Symptoms reported

- Keys sometimes don't register, especially **Space**, **Enter**, and **Alt**.
- Letters come out **out of order**, and some go missing.
- The keyboard "feels off" compared with a Dell XPS 13 and a MacBook Pro 16" (M5 Max). Both of those type reliably.

## Investigation

### 1. Software and configuration: ruled out

| Check | Result |
|---|---|
| Hyprland input config (`~/.config/hypr/input.lua`) | Only a Super/Alt swap and natural scrolling, the same as on the XPS 13 |
| Key repeat | 40 repeats per second after 250ms, Omarchy's defaults. Repeat only affects held keys and can't drop a key press. |
| Keyboard device | `AT Translated Set 2 keyboard` on the i8042 controller (`/dev/input/event3`). The kernel does no debouncing that could discard key presses. |
| Kernel log | No i8042 or keyboard errors |
| Key remappers or virtual keyboards | None, apart from fcitx5's own virtual keyboard, which doesn't hide keys from libinput. Omarchy issue #5071, where Makima broke disable-while-typing, doesn't apply here. |

### 2. Normal typing test (`libinput debug-events`)

About 30 seconds of normal typing on BIOS 1.10.1: **every key press that reached libinput arrived in the correct order.** Two things stood out:

- The touchpad **moved the pointer while the hands were typing**: about 60 small movements between 4.97s and 5.73s, ending 3ms before a key press, and another nudge at 8.00s, 1ms before a key press. That's palm contact slipping past libinput's disable-while-typing, which only blocks the touchpad for a fraction of a second after each key.
- There were no touchpad taps or clicks during typing, so tap-to-click isn't involved.

Ordinary typing may not trigger the keyboard bug reliably, so this test didn't settle the keyboard question. The swipe test below did.

### 3. Touchpad palm detection by pressure: not possible

The touchpad is a **Sensel pressure-sensing pad** (`VEN_2C2F:00 2C2F:0033`). libinput's Dell quirks file already lists it as `INPUT_PROP_PRESSUREPAD`. From `libinput measure touchpad-pressure`:

| Contact | Maximum pressure |
|---|---|
| Palm resting while typing | about 17–29 |
| Finger moving the pointer | about 17–29 |
| libinput's palm threshold | 130, never reached |

Palms and fingers press equally hard, so no pressure threshold can tell them apart. The pad doesn't report contact size either, so libinput has no other way to detect palms.

### 4. Swipe test (Dell's reproduction from article 000435203)

**Method:** one finger slid across `q w e r t y u i o p` in about 0.5–1 second, several times, logged with `sudo libinput debug-events --show-keycodes`.

#### XPS 16, BIOS 1.10.1

| Swipe | Registered | Missing |
|---|---|---|
| 1 | q w e r · y u i o p | t |
| 2 | q ········· `[` | w e r t y u i o p |
| 3 | q w e ····· o | r t y u i p |
| 4 | q w ······· o p | e r t y u i |
| 5 | q w ········· p | e r t y u i o |
| 6 | q w e ······· p `[` | r t y u i o |
| 7 | q w ········· p | e r t y u i o |

Evidence of the stalls:
- In swipe 4, **W appears to be held for 200ms**, then "W released" and "O pressed" arrive **in the same millisecond**. A finger sliding across the row can't stay on W while it travels to O.
- In swipe 2, **Q appears to be held for 384ms**, long enough for key repeat to type `qqqqqqq`, which the user never typed.

#### XPS 16, BIOS 1.11.0

| Swipe | Registered | Missing |
|---|---|---|
| 1 | q w e r · · u i o p | t y |
| 2 | q w e r t y u i o p | none |
| 3 | q w e r t y u i o p | none |
| 4 | q w · r t · · i o p | e y u |
| 5 | q w e r t y u i o p | none |
| 6 | q w e r t y u i o p | none |

Swipe 1 has the same signature as before: R appears held for about 95ms, then "R released" and "U pressed" arrive in the same millisecond, and T and Y are lost.

#### XPS 16, BIOS 1.11.0, second run (13 swipes)

| Swipe | Registered | Missing |
|---|---|---|
| 1 | q w e r t y u i o p | none |
| 2 | q w · · · · · i o p | e r t y u |
| 3 | q w · · · · · · o p | e r t y u i |
| 4 | q w e r t y u i o p | none |
| 5 | q w e r t · u i o p | y |
| 6 | q w e r t y u i o p | none |
| 7 | q w e r t y u i o p | none |
| 8 | q w e r · · · · o p | t y u i |
| 9 | q w e · · · · · o p | r t y u i |
| 10 | q w e · · · · · o p | r t y u i |
| 11 | q w e r t · · · o p | y u i |
| 12 | q w e r · · · · o p | t y u i |
| 13 | q w e r t y u i o p | none |

Same signature again. In swipe 2, W appears held for 192ms, then "W released" and "I pressed" arrive in the same millisecond, and E R T Y U are lost.

#### External Dell USB keyboard plugged into the same XPS 16 (BIOS 1.11.0)

Dell support asked for this test. **11 of 11 swipes registered all 10 keys in order.** The only extras were normal key repeat from resting on Q or O longer than 250ms, and three keys pressed twice during one slower swipe. Nothing was missing. Timestamps fall on a 16ms grid, which is ordinary USB reporting. So the same laptop, BIOS, OS, and input stack handle fast key sequences perfectly, which isolates the fault to the **built-in keyboard** (the keyboard itself or its controller firmware).

#### XPS 13 on Omarchy, for comparison

**6 of 6 swipes registered all 10 keys in order.** Key events arrive a few milliseconds apart and overlap naturally. For example, W is pressed at 0.319s, E at 0.365s, and W released at 0.376s. The XPS 16 almost always reports a release and the next press in the same millisecond, which means it sends key changes in batches.

#### Totals

| | Complete swipes | Keys lost |
|---|---|---|
| XPS 13 | **6 of 6** | 0 |
| External USB keyboard on the XPS 16 | **11 of 11** | 0 |
| XPS 16, BIOS 1.10.1 | 0 of 7 | 1–9 per swipe |
| XPS 16, BIOS 1.11.0 (two runs) | **9 of 19 (47%)** | 1–6 in the failed swipes |

### 5. BIOS update

- Dell's article 000435203 lists XPS 14 DA14260 and XPS 16 DA16260 as fixed in **BIOS 1.4.1 and later**.
- The latest BIOS on Dell's site is **1.11.0** (driver ID `V9F7P`, released 09 Sep 2026). Its only release note is "Improved the stability of the system."
- LVFS, where Linux's firmware updater gets updates, only has **1.9.0**, so it couldn't be used.
- 1.11.0 was flashed using a FAT32 USB stick and Dell's F12 → **BIOS Flash Update** menu. Getting into that menu needed **Extend BIOS POST Time = 10 seconds**, and no keys or touchpad touched once the menu started loading.
- Result: somewhat better (47% of swipes complete, up from 0%), **not fixed** (see the tables above).

### 6. Existing Omarchy issues

There was no existing report of this. Related XPS 16 DA16260 issues exist for audio (#7206), the camera (#10624), the display (#11176), and the function row (#6114), but none for keyboard reliability. #5071 (Makima breaking disable-while-typing) and #10815 (disable-while-typing on T2 MacBooks) are different causes.

## Conclusions

1. **Main cause: an XPS 16 keyboard firmware or hardware defect.** Keystrokes are lost or delayed before reaching the OS. This is the issue Dell documents in article 000435203, and it still happens on the latest BIOS, 1.11.0. It needs a Dell warranty or support case: a keyboard replacement, or a firmware fix from Dell.
2. **Not the cause:** key repeat settings, the Hyprland config, tap-to-click, remappers, or touchpad palm drift. The drift is real, but the symptoms happen with only one window open, so it can't send keystrokes anywhere else.

## Recommended actions

- [x] Update the BIOS to 1.11.0
- [ ] Open a Dell support case: article 000435203 still reproduces on BIOS 1.11.0, and another Dell laptop passes the same test.
- [ ] Optional: set **Extend BIOS POST Time** back to 0 in the BIOS settings.
- [x] Posted a heads-up in `omacom/omarchy` Discussions (General): [#12478](https://github.com/omacom/omarchy/discussions/12478)

## How to reproduce

```
sudo libinput debug-events --show-keycodes
```

Slide one finger across `q w e r t y u i o p` in about 0.7 seconds, 6 or more times. Each swipe should show 10 `pressed` lines, in order. On the XPS 16, look for missing letters, and for a release and the next press arriving in the same millisecond after a long apparent hold.

---

## Addendum: 18–19 Sep 2026, night (Dell support chat follow-up)

*Added after the report above, which is unchanged. The results below are newer than the Conclusions section.*

**Context:** Dell social media support asked for a keyboard test in the BIOS. For that the laptop was **fully powered off**, then started straight into BIOS setup (F2). All tests below come from the Linux boot that followed (started 23:50 EDT, BIOS 1.11.0, same OS and software as before).

### Results

| Test | Conditions | Result |
|---|---|---|
| BIOS password field, first try | Typed "hello world". Hard to judge because the field only shows dots, and a palm on the touchpad took focus away a few times | Last letter "d" may have dropped. Inconclusive |
| BIOS password field, swipe test | Q-to-P swipe, dots counted | **10 of 10 complete** |
| Linux, deep CPU sleep states off | C6S and C10 disabled on all CPUs; on battery, power-saver | **10 of 10 complete** |
| Linux, deep CPU sleep states back on | C6S and C10 re-enabled and confirmed in use; on battery, power-saver | **11 of 11 complete** |
| Linux, on the charger | AC connected, power-saver, Bluetooth keyboard and mouse disconnected | **10 of 10 complete** |
| Linux, on the charger, second run | Same as above, about 00:07 EDT (17 minutes after boot, no suspend yet) | **20 of 20 complete** |
| Linux, after suspend/resume | Lid closed 00:08, suspended (s2idle) for about 1.7 minutes, lid opened 00:10; on the charger | **15 of 15 complete.** Two extras came from the user's finger: `ppp` (a finger rested on P for about 350ms, so it auto-repeated) and a `[` (the finger slid past P) |
| Linux, after a normal restart | `systemctl reboot` at 00:13 (no full power-off), about 2 minutes after boot; on the charger | **11 of 12 complete. Swipe 6 lost Y:** T appeared held for about 66ms (the usual gap is 35–45ms), then "T released" and "U pressed" arrived in the same millisecond, which matches the original stall. Swipe 12 was complete but slightly odd: O appeared held for about 200ms, and its release arrived in the same millisecond as P's |
| Linux, same boot after the restart, second run | About 00:17 EDT; on the charger | **20 of 21 complete. Swipe 19 lost Y and U:** T appeared held for 94ms, then "T released" and "I pressed" arrived in the same millisecond. This is the same signature as the original BIOS 1.11.0 failures (section 4: R held for about 95ms, then T and Y lost) |
| Linux, after a second full power-off | `systemctl poweroff` at 00:18, off for about 80 seconds, powered on at 00:19; on the charger | **20 of 20 complete.** No stalls. One `qq` came from a finger resting on Q for about 250ms (normal key repeat) |
| Linux, after a second normal restart | `systemctl reboot` at 00:22, booted 00:23; on the charger | **18 of 18 complete.** No stalls. One extra `[` came from the finger sliding past P |
| Linux, same boot as the second restart, second run | About 00:27 EDT; on the charger | **36 of 36 complete.** No stalls |
| Linux, Dell thermal mode set to **quiet** | Same boot, about 00:47 EDT. `dell-pc` platform profile changed from balanced (Dell "Optimized") to quiet, which was the mode during the original failing tests on Sep 17–18 according to the fan-test notes. Turbo off, power-profiles-daemon on power-saver, on the charger | **20 of 20 complete.** No stalls. One swipe also caught Tab at the same moment as Q (a finger touching two keys) |

Linux total for the boot after the full power-off: **66 of 66 complete swipes**, including after a suspend/resume. After a normal restart: **31 of 33** over two runs. Both failures show the stall signature. After a second full power-off: **20 of 20**. Earlier on the same BIOS 1.11.0: 9 of 19 (47%).

**By how the laptop was started (BIOS 1.11.0):**

| Start method | Complete swipes | Failures |
|---|---|---|
| Full power-off, then on (2 boots) | **86 of 86** | none |
| Normal restart, first boot | **31 of 33** | 2, both with the stall signature |
| Normal restart, second boot (three runs, the last one in Dell quiet mode) | **74 of 74** | none |
| **All tests in this addendum** | **191 of 193** | 2 |
| Original runs, before this addendum | 9 of 19 | 10 |

Swipes here took about 0.6–0.9 seconds, with 35–60ms between keys, similar to the earlier runs. A release and the next press still often land in the same millisecond, but **no keys were lost, and there were no long apparent holds** like the ones described in section 4. The occasional `qq` in the terminal came from a finger resting on Q for more than 250ms (normal key repeat). No keys were missing.

### What this rules out

- **Deep CPU sleep states (C6S and C10):** results were the same with them on and off.
- **Charging vs battery:** results were the same on both.

### Current hypothesis (unconfirmed)

The problem went away after a **full power-off** following the BIOS 1.11.0 update. The keyboard controller's part of the update may only take full effect after a complete shutdown, not after a restart. It's not yet known whether the earlier failed runs on 1.11.0 happened before any full shutdown. The problem could also be intermittent and simply not have come back yet.

**Update after the restart test:** the problem came back once (1 of 12 swipes) after a normal restart, following 66 clean swipes on the boot after the full power-off. A second run on the same boot lost two more keys (20 of 21), so after the restart the drops are back: **31 of 33 (94%)**, compared with 66 of 66 on the boot after the full power-off and 9 of 19 (47%) originally. **The problem isn't fixed.** The full power-off seemed to suppress it, at least for a while, and after a normal restart it came back at a lower rate than originally. The next useful comparison is a normal full shutdown and power-on, then more swipes after a restart.

**Update after the second full power-off:** 20 of 20 clean again. The pattern has repeated: after a full power-off, 86 of 86 swipes were clean over two boots. After a normal restart, 31 of 33 were clean, with 2 stall-signature failures. At the post-restart failure rate of about 6%, 86 clean swipes in a row would happen by chance well under 1% of the time. **Current finding:** on BIOS 1.11.0, the keyboard fault shows up after a normal restart and not after a full power-off. Only a few boots are behind this, so one more restart that brings the drops back would strengthen it. Either way, the bug from Dell article 000435203 is still present on 1.11.0.

**Update after the second normal restart: the restart pattern isn't confirmed.** The second restart boot was clean (18 of 18, then 36 of 36 on the same boot, for 54 of 54), so a restart doesn't reliably bring the drops back. The earlier "full power-off clears it, a restart brings it back" finding doesn't hold up. Both failures happened on one restart boot, and they could just be rare failures that can happen on any boot.

**Current conclusions:**
1. **The bug is still present on BIOS 1.11.0.** Both failures tonight have the same stall signature as section 4: one key appears held for about 65–95ms, then its release and a later key's press arrive in the same millisecond, and the keys in between are lost.
2. **It's much rarer than in the original tests:** 2 of 173 swipes failed tonight (about 1 in 85), versus 10 of 19 originally (about 1 in 2). This improvement started around the full power-off and BIOS visit, but that link isn't proven.
3. **No trigger found.** Deep CPU sleep states, charging vs battery, suspend/resume, restart vs full power-off, and Dell thermal mode (quiet vs Optimized): none of these clearly changes the result. The Dell mode was quiet during the original failing tests, but switching back to quiet gave 20 of 20.

### Next tests

- [x] Swipe test after a suspend/resume (close and reopen the lid): 15 of 15 complete
- [x] Swipe test after a normal restart: 31 of 33 over two runs. Both failures show the original stall signature
- [x] Swipe test after a second full power-off: 20 of 20 complete
- [x] Swipe test after another normal restart, to confirm the pattern: 18 of 18. **The pattern wasn't confirmed**
- [ ] Swipe test after a few hours of normal use
- [ ] If drops come back during normal typing, capture them right away with `sudo libinput debug-events --show-keycodes`

The Omarchy discussion was updated with these results: [comment](https://github.com/omacom/omarchy/discussions/12478#discussioncomment-18510903). The Dell case hasn't been updated yet.

*Helper script:* a small `swipe.py` that counts Q-to-P swipes from terminal input (no sudo) was used locally; it isn't included here. libinput remains the reference method.

## Outcome (2026-09-19)

**Returning the laptop.** The dropped-key bug became rare (2 of 193 swipes), but typing on the XPS 16's **zero-lattice** keyboard (keys flush, no gaps) never felt right. On monkeytype (time 30, english) it scored 96, 88, and 87 wpm, against 113 wpm on the XPS 13 (DX13260, same ~0.8 mm travel but gapped keys), with frequent missed spaces and transposed letters. PCWorld's review describes the same thing: 97 wpm at 95% accuracy, and "when I go faster, my accuracy tanks" ([review](https://www.pcworld.com/article/3110951/dell-xps-16-2026-review.html)). Turning off fcitx5 made no difference to the scores.
