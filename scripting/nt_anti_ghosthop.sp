#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.4.5"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

// Caching this stuff because we're potentially using it on each tick
static int _ghost_carrier_userid;
static int _last_ghost; // ent ref
static int _playerprop_weps_offset;
static float _prev_ghoster_pos[3];

//#define DEBUG

ConVar cMaxAirspeed = null;

public Plugin myinfo = {
    name = "NT Anti Ghosthop",
    description = "Forces you to drop the ghost if going too fast mid-air.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-anti-ghosthop"
};

public void OnPluginStart()
{
    CreateConVar("sm_nt_anti_ghosthop_version", PLUGIN_VERSION,
        "NT Anti Ghosthop plugin version", FCVAR_SPONLY  | FCVAR_REPLICATED | FCVAR_NOTIFY);

    cMaxAirspeed = CreateConVar("sm_nt_anti_ghosthop_max_airspeed", "344.56",
        "Maximum allowed ghoster air speed.", _, true, 0.0);

    _playerprop_weps_offset = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
    if (_playerprop_weps_offset <= 0)
    {
        SetFailState("Failed to find required network prop offset");
    }
}

public void OnAllPluginsLoaded()
{
    if (FindConVar("sm_ntghostcap_version") == null)
    {
        SetFailState("This plugin requires the nt_ghostcap plugin");
    }
}

public void OnMapEnd()
{
    ResetGhoster();
}

public void OnGhostCapture(int client)
{
    ResetGhoster();
}

public void OnGhostDrop(int client)
{
    ResetGhoster();
}

public void OnGhostPickUp(int client)
{
    ResetGhoster();
    _ghost_carrier_userid = GetClientUserId(client);
}

public void OnGhostSpawn(int ghost_ref)
{
    _last_ghost = ghost_ref;
    ResetGhoster();
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse,
    const float vel[3], const float angles[3], int weapon, int subtype,
    int cmdnum, int tickcount, int seed, const int mouse[2])
{
#if defined(DEBUG)
	// Need >1 clients for ghost to trigger,
	// but don't want bots input for cleaner srcds debug log lines.
    if (IsFakeClient(client))
    {
        return;
    }
#endif

    if (GetClientUserId(client) != _ghost_carrier_userid)
    {
        return;
    }

    float ghoster_pos[3];
    GetClientAbsOrigin(client, ghoster_pos);

    // Don't need to do any anti-ghosthop checks if we aren't airborne.
    if (!(GetEntityFlags(client) & FL_ONGROUND) &&
        // We need to have a previous known position to calculate velocity.
        !IsNullVector(_prev_ghoster_pos))
    {
        float dir[3];
        SubtractVectors(ghoster_pos, _prev_ghoster_pos, dir);

        // Only interested in lateral movements.
        // Zeroing the vertical axis prevents false positives on fast
        // upwards jumps, or when falling.
        dir[2] = 0.0;

        float distance = GetVectorLength(dir);
        float delta_time = GetTickInterval(); // TODO/FIXME: use client tickrate! We are assuming sv_minmax cmdrates to equal server tickrate as is the case with Creamy, but this is not guaranteed!!!
        // Estimate our current speed in engine units per second.
        // This is the same unit of velocity that cl_showpos displays.
        float lateral_air_velocity = distance / delta_time;

        if (lateral_air_velocity > cMaxAirspeed.FloatValue)
        {
            int ghost = EntRefToEntIndex(_last_ghost);
            // We had a ghoster userid but ghost itself no longer exists for whatever reason.
            if (ghost == 0 || ghost == INVALID_ENT_REFERENCE)
            {
                ResetGhoster();
                return;
            }

            int wep = GetEntDataEnt2(client, _playerprop_weps_offset);
            if (wep == ghost)
            {
                SDKHooks_DropWeapon(client, ghost, ghoster_pos, NULL_VECTOR);

                PrintToChat(client, "%s YOU HAVE DROPPED THE GHOST (Maximum air velocity exceeded.)", PLUGIN_TAG);
            }
            // We had a ghoster userid, and the ghost exists, but that supposed ghoster no longer holds the ghost?
			// This transfer of ghost ownership should be caught by the OnGhostDrop/OnGhostPickUp global forwards,
			// so something's gone wrong somewhere if we ever enter this.
            else
            {
#if defined(DEBUG)
				// This should never happen, but it's recoverable, so we only fail on debug.
                SetFailState("Ghoster (%d) & ghost entdata mismatch (%d != %d)", client, wep, ghost);
#endif
                ResetGhoster(); // no longer reliably know ghoster info - have to reset and give up on this tick
                return;
            }
        }
    }

    _prev_ghoster_pos = ghoster_pos;
}

void ResetGhoster()
{
    _ghost_carrier_userid = 0;
    _prev_ghoster_pos = NULL_VECTOR;
}
