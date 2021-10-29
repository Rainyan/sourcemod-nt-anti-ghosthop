# sourcemod-nt-anti-ghosthop
SourceMod plugin for Neotokyo. Forces you to drop the ghost if going too fast mid-air.

## Some background
NT has a max speed limitation for the ghost carrier to make rushy quick capping less effective.
However, players could circumvent this limitation by bhopping and/or using the recon AUX jump (dubbed "*ghost hopping*").

For a long time, there's been a sort of gentlemen's agreement not to abuse ghost hopping,
and anti-ghosthop rules have also made their way into many competitive rulesets.

This plugin suggests a different approach, whereby ghost hopping is restricted programmatically, rather than by ambiguous case-by-case rulings.

## How it works

A recon carrying the ghost on flat ground, doing an optimal wallrun speed boost can gain a max speed of around 255.47 units/sec.

**This plugin will instantly drop the ghost** to its current position, if:
* a player is carrying the ghost
* the player is not touching the ground
* the player is moving faster (laterally, falling down doesn't count) than the recon maximum ghost carry speed

## Gameplay changes

* Ghost hopping becomes allowed
  * The plugin will enforce max ghost hop speed restrictions, as described in the section above
  * Penalty for going too fast is automatically losing the ghost to its current position
* Slower moving classes can now utilize ghost hopping, for reaching speeds up to the maximum allowed speed of recon ghost movement (255.47 u/s)

## Motivations

* Encourage skill based movement, but strike a balance with not breaking game timings
* Make ghost hopping rulings less ambiguous (the server can automatically decide what is too fast instead of admin intervention)

Thanks for attending my ted talk.
