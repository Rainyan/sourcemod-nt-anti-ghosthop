#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.4.4"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

// Caching this stuff because we're using it on each tick
static int _ghost_carrier_userid;
static int _last_ghost; // ent ref
static int _playerprop_weps_offset;
static float _prev_ghoster_pos[3];
static bool _is_ghoster_approaching_speed_limit = false;

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
        "Maximum allowed ghoster air speed.", _, true, 0.0, true, 10000.0);

    _playerprop_weps_offset = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
    if (_playerprop_weps_offset == -1)
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
    if (IsFakeClient(client))
    {
        return;
    }
#endif

    int ghost = EntRefToEntIndex(_last_ghost);

    // If there's no ghost in existence right now.
    if (ghost == 0 || ghost == INVALID_ENT_REFERENCE)
    {
        return;
    }

    int userid = GetClientUserId(client);

    // Userid cannot be 0 here, so if this evaluates to true,
    // we are guaranteed to have a valid ghost carrier client.
    if (userid == _ghost_carrier_userid)
    {
        float ghoster_pos[3];
        GetClientAbsOrigin(client, ghoster_pos);

        // Don't need to do any anti-ghosthop checks if we aren't airborne.
        if (!(GetEntityFlags(client) & FL_ONGROUND))
        {
            // We need to have a previous known position to calculate velocity.
            if (!IsNullVector(_prev_ghoster_pos))
            {
                float dir[3];
                SubtractVectors(ghoster_pos, _prev_ghoster_pos, dir);

                // Only interested in lateral movements.
                // Zeroing the vertical axis prevents false positives on fast
                // upwards jumps, or when falling.
                dir[2] = 0.0;

                float distance = GetVectorLength(dir);
                float delta_time = GetTickInterval();
                // Estimate our current speed in engine units per second.
                // This is the same unit of velocity that cl_showpos displays.
                float lateral_air_velocity = distance / delta_time;

                float max_speed = cMaxAirspeed.FloatValue;
                float warn_speed = max_speed * 0.75;

                // Check yourself
                if (lateral_air_velocity > warn_speed)
                {
                    int wep = GetEntDataEnt2(client,_playerprop_weps_offset);
                    if (wep == ghost)
                    {
                        // Before you wreck yourself
                        if (lateral_air_velocity > max_speed)
                        {
                            SDKHooks_DropWeapon(client, ghost, ghoster_pos, NULL_VECTOR);
                            CancelApproachSpeedLimit();

                            PrintToChat(client, "%s YOU HAVE DROPPED THE GHOST (Maximum air velocity exceeded.)", PLUGIN_TAG);
                        }
                        else
                        {
                            ApproachSpeedLimit();
                        }
                    }
                }
                // Else, we have a reasonably slow air speed.
                // This is not considered ghost hopping at all,
                // but just good old regular jumping while holding the ghost.
                else
                {
                    CancelApproachSpeedLimit();
                }
            }
        }

        _prev_ghoster_pos = ghoster_pos;
    }
}

void ResetGhoster()
{
    CancelApproachSpeedLimit();
    _ghost_carrier_userid = 0;
    _prev_ghoster_pos = NULL_VECTOR;
}

void ApproachSpeedLimit()
{
    if (!_is_ghoster_approaching_speed_limit)
    {
        int ghost = EntRefToEntIndex(_last_ghost);
        if (ghost == 0 || ghost == INVALID_ENT_REFERENCE)
        {
            return;
        }

        _is_ghoster_approaching_speed_limit = true;

        int carrier = GetClientOfUserId(_ghost_carrier_userid);
        if (carrier != 0)
        {
            PrintToChat(carrier, "%s You are approaching maximum allowed ghost hopping speed (%.1f).", PLUGIN_TAG, cMaxAirspeed.FloatValue);
            PrintToChat(carrier, "The ghost will drop from your hands if you exceed this speed limit.");
        }
        else
        {
            CancelApproachSpeedLimit();
            // Have to hard fail because if this ever happens, we'd otherwise destroy server performance with the OnPlayerRunCmdPost call errors here
            SetFailState("Invalid ghost carrier userid %d", _ghost_carrier_userid);
        }
    }
}

void CancelApproachSpeedLimit()
{
    _is_ghoster_approaching_speed_limit = false;
}
