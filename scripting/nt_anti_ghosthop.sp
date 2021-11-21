#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

//#define DEBUG
//#define DEBUG_PROFILE

#if defined(DEBUG_PROFILE)
#include <profiler>
Profiler _profiler = null;
#endif

#define PLUGIN_VERSION "0.6.0"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

#define NEO_MAXPLAYERS 32

// Class specific max ghost carrier land speeds (w/ 8 degree "wall hug" boost)
#define MAX_SPEED_RECON 255.47
#define MAX_SPEED_ASSAULT 204.38
#define MAX_SPEED_SUPPORT 153.28

// Caching this stuff because we're potentially using it on each tick
static int _ghost_carrier_userid;
static int _last_ghost; // ent ref
static int _playerprop_weps_offset;
static float _prev_ghoster_pos[3];
static float _prev_cmd_time[NEO_MAXPLAYERS + 1];

public Plugin myinfo = {
    name = "NT Anti Ghosthop",
    description = "Forces you to drop the ghost if going too fast mid-air.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-anti-ghosthop"
};

public void OnPluginStart()
{
#if defined(DEBUG_PROFILE)
    _profiler = CreateProfiler();
#endif

    CreateConVar("sm_nt_anti_ghosthop_version", PLUGIN_VERSION,
        "NT Anti Ghosthop plugin version", FCVAR_SPONLY  | FCVAR_REPLICATED | FCVAR_NOTIFY);

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

    for (int i = 0; i < sizeof(_prev_cmd_time); ++i)
    {
        _prev_cmd_time[i] = 0.0;
    }
}

public void OnClientDisconnect(int client)
{
    _prev_cmd_time[client] = 0.0;
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
#if defined(DEBUG_PROFILE)
        _profiler.Start();
#endif

        float dir[3];
        SubtractVectors(ghoster_pos, _prev_ghoster_pos, dir);
        // Only interested in lateral movements.
        // Zeroing the vertical axis prevents false positives on fast
        // upwards jumps, or when falling.
        dir[2] = 0.0;
        float distance = GetVectorLength(dir);

        float time = GetGameTime();
        float delta_time = time - _prev_cmd_time[client];
        // Would result in division by zero, so get some reasonable approximation.
        if (delta_time == 0)
        {
            delta_time = GetTickInterval();
        }
        _prev_cmd_time[client] = time;

        // Estimate our current speed in engine units per second.
        // This is the same unit of velocity that cl_showpos displays.
        float lateral_air_velocity = distance / delta_time;

#if defined(DEBUG_PROFILE)
        _profiler.Stop();
        PrintToServer("Profiler (OnPlayerRunCmdPost): %f", _profiler.Time);
#endif

        int class = GetPlayerClass(client);
        float max_vel = (class == CLASS_RECON) ? MAX_SPEED_RECON
            : (class == CLASS_ASSAULT) ? MAX_SPEED_ASSAULT : MAX_SPEED_SUPPORT;

        if (lateral_air_velocity > max_vel)
        {
            int ghost = EntRefToEntIndex(_last_ghost);
            // We had a ghoster userid but the ghost itself no longer exists for whatever reason.
            if (ghost == 0 || ghost == INVALID_ENT_REFERENCE)
            {
                ResetGhoster();
                return;
            }

            int wep = GetEntDataEnt2(client, _playerprop_weps_offset);
            if (wep == ghost)
            {
                SDKHooks_DropWeapon(client, ghost, ghoster_pos, NULL_VECTOR);

                // Printing maximum velocity as integer, since the decimals are meaninglessly precise in this context.
                PrintToChat(client, "%s YOU HAVE DROPPED THE GHOST (max air velocity of %.0f ups exceeded)", PLUGIN_TAG, max_vel);
                PrintToServer("%s YOU HAVE DROPPED THE GHOST (max air velocity of %.0f ups exceeded)", PLUGIN_TAG, max_vel);
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

                ResetGhoster(); // no longer reliably know ghoster info - have to reset and give up on this cmd
            }

            return;
        }
    }

    _prev_ghoster_pos = ghoster_pos;
}

void ResetGhoster()
{
    int prev_client = GetClientOfUserId(_ghost_carrier_userid);
    if (prev_client != 0)
    {
        _prev_cmd_time[prev_client] = 0.0;
    }

    _ghost_carrier_userid = 0;
    _prev_ghoster_pos = NULL_VECTOR;
}
