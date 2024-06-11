# sourcemod-nt-anti-ghosthop
SourceMod plugin for Neotokyo that limits the max movement speed while bunnyhopping with the ghost:

![velocity vector plot](https://github.com/Rainyan/sourcemod-nt-anti-ghosthop/assets/6595066/8ecaf061-85e6-4cd9-b45b-937427fada8f)

where:
* v<sub>0</sub> = initial lateral velocity
* Δv = velocity impulse (inverse of current overspeed)
* v<sub>f</sub> = final lateral velocity, clamped within max ghost carry speed.

The overspeed limiter only triggers at the moment of the player's feet touching the ground; air strafes are unaffected.

## Example videos:

### Walking cap with max speed (about 14 seconds), and ghost hop blocked by the plugin, side by side:

[hop_example.webm](https://github.com/Rainyan/sourcemod-nt-anti-ghosthop/assets/6595066/f4c784b1-1309-49e5-83ba-eba7c72d693b)

### Unrestricted ghost hop (about 9 seconds):

[hopex2.webm](https://github.com/Rainyan/sourcemod-nt-anti-ghosthop/assets/6595066/61589967-6ed9-4631-97a5-e11e74237d16)


## Some background
NT has a max speed limitation for the ghost carrier to make rushy quick capping less effective.
However, players could circumvent this limitation by bhopping and/or using the recon AUX jump (dubbed "*ghost hopping*").

For a long time, there's been a sort of gentlemen's agreement not to abuse ghost hopping,
and anti-ghosthop rules have also made their way into many competitive rulesets.

This plugin suggests a different approach, whereby ghost hopping is restricted programmatically, rather than by ambiguous case-by-case rulings.

## Gameplay changes

* **Attempting to ghost hop becomes fully allowed**
  * The plugin will enforce max ghost hop speed limits, adjusted for competitive gameplay balance. Whatever ghost movement you can get away with, is by definition allowed.

## Motivations

* **Encourage skill based movement**, but strike a balance with not breaking game timings.
* **Make tournament rulings less ambiguous** — the server will automatically decide what is too fast, instead of relying on subjective human admin intervention.

Thanks for attending my ted talk.

<hr>

## More info for server operators

### Build requirements
* SourceMod version 1.9 or newer
* The [Neotokyo include](https://github.com/softashell/sourcemod-nt-include) .inc file (place inside <i>scripting/includes</i>)

### Plugin requirements
* The [nt_ghostcap plugin](https://github.com/softashell/nt-sourcemod-plugins/blob/master/scripting/nt_ghostcap.sp) is required to use this plugin.

### Cvars
* `sm_nt_anti_ghosthop_verbosity` How much feedback to give to the players about ghosthopping. 0: disabled, 1: notify when being limited in text chat. Default: 0
* `sm_nt_anti_ghosthop_speed_scale` Scaling for the mx allowed ghosthop speed before slowdown begins. 1.0 means class specific max ghost movement speed, 0.0 means no speed limit. Minimum: 0.0, Default: 1.0
  * This cvar replaces the old, removed cvar `sm_nt_anti_ghosthop_scale`, which was a divisor instead of the current multiplier.
* `sm_nt_anti_ghosthop_n_extra_hops` How many extra ghost hops to tolerate before limiting speed. Resets at the end of the bhop chain. Minimum: 0, Default: 0.
  * This cvar replaces the old, removed cvar `sm_nt_anti_ghosthop_n_allowed_hops`, which counted from the initial hop. If you had a value of `1`, it should be changed to `0` for similar behaviour.

### What happened to the older versions?
The old versions are still available [from the tags](https://github.com/Rainyan/sourcemod-nt-anti-ghosthop/tags). Note that any tags older than the newest one are no longer supported.
