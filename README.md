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

* **Ghost hopping becomes allowed**
  * The plugin will enforce max ghost hop speed restrictions, adjusted for competitive gameplay balance.
  * Penalty for going too fast is automatically losing hold of the ghost, auto-dropping it to its current position.
* **Slower classes can now utilize ghost hopping** for equaling recon ghost carrier speeds.

![Figure_GhostHop](https://user-images.githubusercontent.com/6595066/149028760-bc9cfc14-5e6e-4efe-802f-92a5d8351a18.png)

## Motivations

* **Encourage skill based movement**, but strike a balance with not breaking game timings.
* **Make tournament rulings less ambiguous** — the server will automatically decide what is too fast, instead of relying on subjective human admin intervention.

Thanks for attending my ted talk.

<hr>

## More info for server operators

### Troubleshooting
If *SDKHooks_DropWeapon()* is erroring out in your SourceMod logs, and you are using SM 1.10, make sure your build version [is at least 6517](https://github.com/alliedmodders/sourcemod/commit/36341a5984f21aeb4621d321f3af940) or newer.
