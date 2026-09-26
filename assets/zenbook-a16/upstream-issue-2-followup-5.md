## Speakers: the tweeters are silent as shipped (4ch sink, stereo only reaches the woofers); touchpad palm notes; one reset at idle lock

More A16 findings on the same image (v0.2.2-1, kernel 7.2.0-18). Details and files are in [zoan37/omarchy-setup](https://github.com/zoan37/omarchy-setup/blob/master/zenbook-a16-omarchy-snapdragon.md), sections 14 and 15.

### 1. Speakers: half the drivers get no signal

With the UCM fix from the report, the speaker sink is `alsa_output.platform-sound.HiFi__Speaker__sink`, **4 channels `FL FR RL RR`**, and the machine has 2 woofers + 2 tweeters (`WooferLeft/Right`, `TweeterLeft/Right` WSA884x). PipeWire's default upmix feeds a stereo stream to `FL`/`FR` only, and `RL`/`RR` get nothing. I checked it on the sink monitor: a stereo tone gave peak 0 on both rear channels. Playing a sine per channel and recording it with the internal mic (dB above room noise; the mic rolls off below ~300 Hz):

| Channel | 400 Hz | 1 kHz | 3 kHz | 8 kHz | Driver |
|---|---|---|---|---|---|
| FL | 14.4 | 29.5 | 29.5 | 13.5 | woofer, left |
| FR | 16.3 | 21.3 | 26.4 | 19.3 | woofer, right |
| RL | −4.2 | 7.0 | 32.3 | 45.4 | tweeter, **right** |
| RR | −6.7 | 4.3 | 34.6 | 45.8 | tweeter, **left** |

So out of the box **only the woofers play**, which is why the speakers sound quiet and muffled. The tweeter sides also look **crossed**. With the stereo mic, `RL` was 6.1 dB louder in the right capsule and `RR` 4.4 dB louder in the left. I confirmed it by ear after routing: a left-only signal on `FL`+`RR` comes from the left.

Every amp gain was already at max (`PA Volume` 6/6, BOOST/COMP/DAC on, `WSA*_RX* Digital Volume` at its 81 = −3 dB ceiling, ASM stream volume at unity 8192). Nothing was muted, so this is purely routing.

What I run now is a PipeWire filter-chain in front of the sink ([90-tuning.conf](https://github.com/zoan37/omarchy-setup/blob/master/assets/zenbook-a16/speaker-boost/90-tuning.conf), hosted the same way as Omarchy's `omarchy-speaker-tuning.service`):
- woofers (`FL`/`FR`) get the full band;
- tweeters get a 2 kHz 4th-order highpass, −3 dB, wired `RL` ← right and `RR` ← left;
- an 80 Hz highpass, and an LSP limiter at −1 dBFS with +6 dB of makeup gain.

The crossover matters: sending the full band to the tweeters (for example `channelmix.upmix-method = simple`) would put bass into them, and `VISENSE` speaker protection is off on Linux.

For the image, the least invasive options I can see:
- ship a filter-chain like this one for the A16 (Omarchy already has the `omarchy audio tuning` mechanism, which matches on DMI/SKU);
- or fix the channel map at the source (machine driver / DT), so the tweeter pair isn't crossed and the woofer/tweeter split is explicit.

I haven't checked where the crossing comes from.

### 2. Touchpad palm rejection (info, probably not image material)

The PixArt `093A:3012` pad reports positions and `ABS_MT_TOOL_TYPE` only: **no pressure and no touch size**. The firmware's palm flag (`MT_TOOL_PALM`) does fire, reliably for a hand resting at the top-left corner by the keyboard. libinput's size and pressure palm detection therefore has nothing to work with, and disable-while-typing is all that's left.

I ended up writing a small evdev→uinput filter. It judges each touch by keystroke timing, where it lands on the pad, and how far it travels, and it never mutes the pad for held keys, so games work ([a16-palm-filter](https://github.com/zoan37/omarchy-setup/blob/master/assets/zenbook-a16/a16-palm-filter)). Mentioning it in case anyone else on this pad hits the same thing.

### 3. A hard reset at the idle auto-lock, with suspend already masked

I've seen the machine reset from the lock screen several times. Some of those were probably the suspend reset from my earlier comment, from before I masked the sleep targets. **One happened with sleep already masked**, so it isn't suspend. Its journal ends with `omarchy idle … process-start: lock omarchy-system-lock`, 150 s after the screensaver (ttfx) started, which means the machine died as Omarchy's idle cycle ran the lock. There was no pstore record and no thermal event (my fan daemon logged no ramp). It's the only journaled case since masking, so I can't say yet whether it's reproducible. I've turned on Omarchy's stay-awake mode for now, which disables the screensaver and the auto-lock. I'll report back if it recurs, or if a manual lock alone triggers it.
