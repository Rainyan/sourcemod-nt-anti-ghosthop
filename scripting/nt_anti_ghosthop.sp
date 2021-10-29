#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

#define PLUGIN_VERSION "0.2"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

// Max. flat ground speed of a recon wall-running with the ghost in an optimal 8 degree angle.
#define GHOSTER_MAX_VELOCITY 255.47

// This is the fastest lateral velocity permitted for an airborne ghost carrier.
#define GHOSTER_MAX_ALLOWED_AIR_VELOCITY GHOSTER_MAX_VELOCITY

// Sound effect to use for warning player of the speed limit.
#define SFX_AIR_SPEED_WARNING "gameplay/ghost_idle_loop.wav"

// Caching this stuff because we're using it on each tick
static int _ghost_carrier_userid;
static int _last_ghost; // ent ref
static int _playerprop_weps_offset;
static float _prev_ghoster_pos[3];

// Tracking sfx playback state so we don't emit/silence the sound more than necessary.
static bool _is_ghost_making_noises = false;

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
    CreateConVar("sm_nt_anti_ghostcap_version", PLUGIN_VERSION,
        "NT Anti Ghosthop plugin version", FCVAR_SPONLY  | FCVAR_REPLICATED | FCVAR_NOTIFY);

    cMaxAirspeed = CreateConVar("sm_nt_anti_ghostcap_max_airspeed", "255.47",
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

public void OnMapStart()
{
    if (!PrecacheSound(SFX_AIR_SPEED_WARNING))
    {
        SetFailState("Failed to precache sound: %s", SFX_AIR_SPEED_WARNING);
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
            if (!VectorsEqual(_prev_ghoster_pos, NULL_VECTOR))
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
#if defined(DEBUG)
                            PrintToServer("DROP: %f > %f", lateral_air_velocity, max_speed);
#endif
                            SDKHooks_DropWeapon(client, ghost, ghoster_pos, NULL_VECTOR);
                            StopGhostComplainyNoises();

                            PrintToChat(client, "%s YOU HAVE DROPPED THE GHOST (Maximum air velocity exceeded.)", PLUGIN_TAG);
                        }
                        else
                        {
#if defined(DEBUG)
                            PrintToServer("Complain noise!");
#endif
                            StartGhostComplainyNoises();
                        }
                    }
#if(0)
                    // This should never happen. But checking just in case
                    // the client somehow managed to switch primaries.
                    else
                    {
                    }
#endif
                }
                // Else, we have a reasonably slow air speed.
                // This is not considered ghost hopping at all,
                // but just good old regular jumping while holding the ghost.
                else
                {
                    StopGhostComplainyNoises();
                }
            }
        }

        _prev_ghoster_pos = ghoster_pos;
    }
#if defined(DEBUG)
    else
    {
        PrintToServer("Userid %d != ghost carr userid %d", userid, _ghost_carrier_userid);
    }
#endif
}

void ResetGhoster()
{
    StopGhostComplainyNoises();
    _ghost_carrier_userid = 0;
    _prev_ghoster_pos = NULL_VECTOR;
}

// Call this to make the ghost start playing glitchy noises as an audio cue
// for the player that they're nearing the allowed ghosthop speed limit.
// Player will also receive a chat message explaining this mechanic.
void StartGhostComplainyNoises()
{
    if (!_is_ghost_making_noises)
    {
        int ghost = EntRefToEntIndex(_last_ghost);
        if (ghost == 0 || ghost == INVALID_ENT_REFERENCE)
        {
            return;
        }

        EmitSoundToAll(SFX_AIR_SPEED_WARNING, ghost);
        _is_ghost_making_noises = true;

        int carrier = GetClientOfUserId(_ghost_carrier_userid);
        if (carrier != 0)
        {
            PrintToChat(carrier, "%s You are approaching maximum allowed ghost hopping speed (%.1f).", PLUGIN_TAG, GHOSTER_MAX_VELOCITY);
            PrintToChat(carrier, "The ghost will drop from your hands if you exceed this speed limit.");
        }
        else
        {
            StopGhostComplainyNoises();
            // Have to hard fail because if this ever happens, we'd otherwise destroy server performance with the OnPlayerRunCmdPost call errors here
            SetFailState("Invalid ghost carrier userid %d", _ghost_carrier_userid);
        }
    }
}

// Call this to stop the ghosthop audio cue.
void StopGhostComplainyNoises()
{
    if (_is_ghost_making_noises)
    {
        int ghost = EntRefToEntIndex(_last_ghost);
        if (ghost != 0 && ghost != INVALID_ENT_REFERENCE)
        {
            StopSound(ghost, SNDCHAN_AUTO, SFX_AIR_SPEED_WARNING);
        }
        _is_ghost_making_noises = false;
    }
}

stock float Clamp(float value, float min, float max)
{
    return value < min ? min : value > max ? max : value;
}

stock bool VectorsEqual(const float[3] v1, const float[3] v2,
    const float max_ulps = 0.0)
{
    // Needs to exactly equal.
    if (max_ulps == 0) {
        return v1[0] == v2[0] && v1[1] == v2[1] && v1[2] == v2[2];
    }
    // Allow an inaccuracy of size max_ulps.
    else {
        if (FloatAbs(v1[0] - v2[0]) > max_ulps) { return false; }
        if (FloatAbs(v1[1] - v2[1]) > max_ulps) { return false; }
        if (FloatAbs(v1[2] - v2[2]) > max_ulps) { return false; }
        return true;
    }
}
