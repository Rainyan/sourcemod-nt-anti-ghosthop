# sourcemod-nt-anti-ghosthop
SourceMod plugin for Neotokyo. Forces you to drop the ghost if going too fast mid-air.

https://user-images.githubusercontent.com/6595066/139524476-7a089902-74a4-49ce-bfe6-f721eb7ad004.mp4

## Some background
NT has a max speed limitation for the ghost carrier to make rushy quick capping less effective.
However, players could circumvent this limitation by bhopping and/or using the recon AUX jump (dubbed "*ghost hopping*").

For a long time, there's been a sort of gentlemen's agreement not to abuse ghost hopping,
and anti-ghosthop rules have also made their way into many competitive rulesets.

This plugin suggests a different approach, whereby ghost hopping is restricted programmatically, rather than by ambiguous case-by-case rulings.

## How it works

### Reference speeds

All speeds listed below assume flat ground, and optimal wallrun angle of 8 degrees.

#### Recon ghost run speed
* A **recon ghost carrier** can achieve a max speed of around **255.47 units/sec**.
#### Recon knife run speed
* A **recon with knife out** can achieve a max speed of around **344.56 units/sec**.

This plugin will instantly **drop the ghost** to its current position, if:
* a player is carrying the ghost
* the player is not touching the ground
* the player is moving faster than a set maximum air speed limit
  * maximum allowed ghost carrier air speed is defined by cvar `sm_nt_anti_ghosthop_max_airspeed`
  * current maximum allowed ghost carrier air speed is set as **Recon knife run speed**

## Gameplay changes

* **Ghost hopping becomes allowed\***
  * \*The plugin will enforce max ghost hop speed restrictions, as described in the section above
  * \*Penalty for going too fast is automatically losing the ghost to its current position
* Slower classes can now utilize ghost hopping for equaling recon ghost carrier speeds

## Motivations

* Encourage skill based movement, but strike a balance with not breaking game timings
* Make ghost hopping rulings less ambiguous (the server can automatically decide what is too fast instead of admin intervention)

## Future considerations

* What is a good value for `sm_nt_anti_ghosthop_max_airspeed`?
  * Needs in-game testing
  * Plugin is currently live at Creamy servers for testing

Thanks for attending my ted talk.

<hr>

## For server operators

### Troubleshooting
If *SDKHooks_DropWeapon()* is erroring out in your SourceMod logs, and you are using SM 1.10, make sure your build version [is at least 6517](https://github.com/alliedmodders/sourcemod/commit/36341a5984f21aeb4621d321f3af940) or newer.
