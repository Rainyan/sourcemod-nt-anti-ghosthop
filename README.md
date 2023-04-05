# sourcemod-nt-anti-ghosthop
SourceMod plugin for Neotokyo. Forces you to drop the ghost if going too fast mid-air.

https://user-images.githubusercontent.com/6595066/139524476-7a089902-74a4-49ce-bfe6-f721eb7ad004.mp4

## Some background
NT has a max speed limitation for the ghost carrier to make rushy quick capping less effective.
However, players could circumvent this limitation by bhopping and/or using the recon AUX jump (dubbed "*ghost hopping*").

For a long time, there's been a sort of gentlemen's agreement not to abuse ghost hopping,
and anti-ghosthop rules have also made their way into many competitive rulesets.

This plugin suggests a different approach, whereby ghost hopping is restricted programmatically, rather than by ambiguous case-by-case rulings.

## Gameplay changes

* **Ghost hopping becomes fully allowed**
  * The plugin will enforce max ghost hop speed restrictions, adjusted for competitive gameplay balance. Whatever ghost movement you can get away with, is by definition now allowed.
  * Penalty for going too fast is automatically losing hold of the ghost, auto-dropping it to its current position.

![Figure_GhostHop](https://user-images.githubusercontent.com/6595066/149028760-bc9cfc14-5e6e-4efe-802f-92a5d8351a18.png)

#### Terms used in the above graph, explained:
* *air velocity*: The lateral speed (vertical up/down velocity of jumping/falling is ignored) of the ghosting player.
* *grace period*: An arbitrary per-player counter which begins depleting when ghosthopping, and recovers gradually. When it hits zero, the ghost is forced to drop. Dropping the ghost will also instantly replenish that player's grace period counter.
* *max air speed limit*: The highest air velocity allowed before grace period starts depleting. Its value is set as the highest speed the ghoster could plausibly move were they not bhopping.

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

### Troubleshooting
If *SDKHooks_DropWeapon()* is erroring out in your SourceMod logs, and you are using SM 1.10, make sure your build version [is at least 6517](https://github.com/alliedmodders/sourcemod/commit/36341a5984f21aeb4621d321f3af940) or newer.

## Wasn't there a version of this plugin which allowed faster ghost hopping?
Yes, it is still available in the [version 0.5 legacy branch](https://github.com/Rainyan/sourcemod-nt-anti-ghosthop/tree/legacy_v0.5), although no longer supported.
