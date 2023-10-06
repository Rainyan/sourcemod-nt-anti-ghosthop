#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR < 7
// Because we require OnPlayerRunCmd, which was added in 1.7.
#error This plugin does not support SourceMod older than 1.7
#endif

#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0.1"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

// Class specific max ghost carrier land speeds (w/ 8 degree "wall hug" boost)
#define MAX_SPEED_RECON 255.47
#define MAX_SPEED_ASSAULT 204.38
#define MAX_SPEED_SUPPORT 153.28

// Caching this stuff because we're potentially using it on each tick
static int _ghost_carrier;
static float _prev_ghoster_pos[3];
static bool _done_initial_hop;

ConVar _verbose, _scale;

public Plugin myinfo = {
    name = "NT Anti Ghosthop",
    description = "Limit the max movement speed while bunnyhopping with the ghost.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-anti-ghosthop"
};

public void OnPluginStart()
{
    CreateConVar("sm_nt_anti_ghosthop_version", PLUGIN_VERSION,
        "NT Anti Ghosthop plugin version", FCVAR_SPONLY  | FCVAR_REPLICATED | FCVAR_NOTIFY);

    _verbose = CreateConVar("sm_nt_anti_ghosthop_verbosity", "1",
        "How much feedback to give to the players about ghosthopping. \
0: disabled, 1: notify when being limited in text chat",
        _, true, float(false), true, float(true));
    _scale = CreateConVar("sm_nt_anti_ghosthop_scale", "1.0",
        "Scaling for the strictness of anti-ghosthop slowdown.",
        _, true, 0.0);

    HookEvent("game_round_start", OnRoundStart, EventHookMode_Pre);
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetGhoster();
}

public void OnAllPluginsLoaded()
{
    if (FindConVar("sm_ntghostcap_version") == null)
    {
        SetFailState("This plugin requires the nt_ghostcap plugin");
    }
}

public void OnClientDisconnect_Post(int client)
{
    if (client == _ghost_carrier)
    {
        ResetGhoster();
    }
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3],
    float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount,
    int& seed, int mouse[2])
{
    if (client != _ghost_carrier)
    {
        return Plugin_Continue;
    }

    float pos[3];
    GetClientAbsOrigin(client, pos);

    if ((buttons & IN_JUMP) &&
        (GetEntityFlags(client) & FL_ONGROUND) &&
        _scale.FloatValue > 0)
    {
        // Allow one initial hop; this makes it possible for the ghoster to
        // cross some environment dangers like the fire pit with ghost in hand.
        if (!_done_initial_hop)
        {
            _done_initial_hop = true;
        }
        else if (GetVectorLength(_prev_ghoster_pos, true) != 0.0)
        {
            float ups[3];
            SubtractVectors(pos, _prev_ghoster_pos, ups);
            float delta_time = GetTickInterval();
            ups[0] /= delta_time;
            ups[1] /= delta_time;
            ups[2] = 0.0;

            float speed = GetVectorLength(ups);
            float max_speed = GetMaxGhostSpeed(client) / _scale.FloatValue;

            if (speed > max_speed)
            {
                ClampVelocityInPlace2D(ups, speed - max_speed);
                NegateVector(ups);
                ApplyAbsVelocityImpulse(client, ups);

                if (_verbose.BoolValue)
                {
                    PrintToChat(client, "%s Limiting speed: %.0f -> %.0f",
                        PLUGIN_TAG, speed, max_speed);
                }
            }
        }
    }

    _prev_ghoster_pos = pos;

    return Plugin_Continue;
}

void ResetGhoster()
{
    _ghost_carrier = 0;
    _prev_ghoster_pos[0] = 0.0;
    _prev_ghoster_pos[1] = 0.0;
    _prev_ghoster_pos[2] = 0.0;
    _done_initial_hop = false;
}

public Action OnGhostCapture(int client)
{
    ResetGhoster();
    return Plugin_Continue;
}

public Action OnGhostDrop(int client)
{
    ResetGhoster();
    return Plugin_Continue;
}

public Action OnGhostPickUp(int client)
{
    ResetGhoster();
    return Plugin_Continue;
}

public Action OnGhostSpawn(int ghost_ref)
{
    ResetGhoster();
    return Plugin_Continue;
}

float GetMaxGhostSpeed(int client)
{
    switch (GetPlayerClass(client))
    {
        case CLASS_RECON: return MAX_SPEED_RECON;
        case CLASS_ASSAULT: return MAX_SPEED_ASSAULT;
        case CLASS_SUPPORT: return MAX_SPEED_SUPPORT;
    }
    SetFailState("Unknown class %d for client %N (%d)", GetPlayerClass(client), client, client);
    return 0.0;
}

void ClampVelocityInPlace2D(float vel[3], float max)
{
    if (FloatAbs(vel[0]) > max)
    {
        vel[0] = vel[0] < 0 ? -max : max;
    }
    if (FloatAbs(vel[1]) > max)
    {
        vel[1] = vel[1] < 0 ? -max : max;
    }
}

void ApplyAbsVelocityImpulse(int entity, const float impulse[3])
{
    static Handle call = INVALID_HANDLE;
    if (call == INVALID_HANDLE)
    {
        char sig[] = "\xD9\x05\x2A\x2A\x2A\x2A\x83\xEC\x0C\x56\x57\x8B\x7C\x24\x18\xD9\x07\x8B\xF1\xDA\xE9\xDF\xE0\xF6\xC4\x44\x7A\x2A\xD9\x05\x2A\x2A\x2A\x2A\xD9\x47\x04\xDA\xE9\xDF\xE0\xF6\xC4\x44\x7A\x2A\xD9\x05\x2A\x2A\x2A\x2A\xD9\x47\x08\xDA\xE9\xDF\xE0\xF6\xC4\x44\x7B\x2A\x80\xBE\xDE\x00\x00\x00\x06\x75\x2A\x8B\x8E\xF8\x01\x00\x00\x8B\x01\x8B\x90\xB0\x00\x00\x00";
        int sig_size = 87;
        StartPrepSDKCall(SDKCall_Entity);
        PrepSDKCall_SetSignature(SDKLibrary_Server, sig, sig_size);
        PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
        call = EndPrepSDKCall();
        if (call == INVALID_HANDLE)
        {
            SetFailState("Failed to prepare SDK call");
        }
    }
    SDKCall(call, entity, impulse);
}
