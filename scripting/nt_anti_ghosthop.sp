#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "2.0.5"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

// Class specific max ghost carrier land speeds (w/ ~36.95 degree "wall hug" boost)
#define MAX_SPEED_RECON 255.427734
#define MAX_SPEED_ASSAULT 204.364746
#define MAX_SPEED_SUPPORT 204.380859

// Caching this stuff because we're potentially using it on each tick
static int _ghost_carrier, _num_hops;
static float _prev_ghoster_pos[3];
static float _rest_duration;
static bool _was_on_ground_last_cmd;

ConVar _verbose, _scale, _n_allowed_hops;

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
        "NT Anti Ghosthop plugin version", FCVAR_DONTRECORD);

    _verbose = CreateConVar("sm_nt_anti_ghosthop_verbosity", "0",
        "How much feedback to give to the players about ghosthopping. \
0: disabled, 1: notify when being limited in text chat",
        _, true, float(false), true, float(true));
    _scale = CreateConVar("sm_nt_anti_ghosthop_speed_scale", "1.0",
        "Scaling for the of anti-ghosthop slowdown. Higher value means \
harsher speed penalty. 0 means no speed limit. 1 means class-specific land \
ghost carry max speed.",
        _, true, 0.0);
    _n_allowed_hops = CreateConVar("sm_nt_anti_ghosthop_n_allowed_hops", "1",
        "How many ghost hops to tolerate before limiting speed. Resets \
at the end of the bhop chain.", _, true, 0.0);

    HookEvent("game_round_start", OnRoundStart, EventHookMode_Pre);

    AutoExecConfig();
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

    bool is_on_ground = GetEntityFlags(client) & FL_ONGROUND != 0;

    if (!_was_on_ground_last_cmd)
    {
        _rest_duration = 0.0;

        if (is_on_ground && _scale.FloatValue > 0)
        {
            if (GetVectorLength(_prev_ghoster_pos, true) != 0.0 &&
                ++_num_hops > _n_allowed_hops.IntValue)
            {
                float ups[3];
                SubtractVectors(_prev_ghoster_pos, pos, ups);
                float delta_time = GetTickInterval();
                ups[0] /= delta_time;
                ups[1] /= delta_time;
                ups[2] = 0.0;

                float speed = GetVectorLength(ups);
                float max_speed = GetMaxGhostSpeed(client) * _scale.FloatValue;

                if (speed > max_speed)
                {
                    ScaleVector(ups, max_speed / speed);
                    ApplyAbsVelocityImpulse(client, ups);

                    if (_verbose.BoolValue)
                    {
                        static int last_nag_time;
                        int time = GetTime();
                        if (time - last_nag_time > 15)
                        {
                            PrintToChat(client, "%s Limiting speed: %.0f -> %.0f",
                                PLUGIN_TAG, speed, max_speed);
                            last_nag_time = time;
                        }
                    }
                }
            }
        }
    }
    else if (_num_hops != 0 && is_on_ground)
    {
        _rest_duration += GetTickInterval();
        if (_rest_duration > 1.0)
        {
            _num_hops = 0;
        }
    }

    _was_on_ground_last_cmd = is_on_ground;

    _prev_ghoster_pos = pos;

    return Plugin_Continue;
}

void ResetGhoster()
{
    _ghost_carrier = 0;
    _num_hops = 0;
    _rest_duration = 0.0;
    _prev_ghoster_pos[0] = 0.0;
    _prev_ghoster_pos[1] = 0.0;
    _prev_ghoster_pos[2] = 0.0;
    _was_on_ground_last_cmd = false;
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
    _ghost_carrier = client;
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
    // Note: Must fail on unknown class to avoid division by zero at call site
    SetFailState("Unknown class %d for client %N (%d)", GetPlayerClass(client), client, client);
    return 0.0;
}

void ApplyAbsVelocityImpulse(int entity, const float impulse[3])
{
    static Handle call = INVALID_HANDLE;
    if (call == INVALID_HANDLE)
    {
        char sig[] = "\xD9\x05\x2A\x2A\x2A\x2A\x83\xEC\x0C\x56\x57\x8B\x7C\x24\x18\xD9\x07\x8B\xF1\xDA\xE9\xDF\xE0\xF6\xC4\x44\x7A\x2A\xD9\x05\x2A\x2A\x2A\x2A\xD9\x47\x04\xDA\xE9\xDF\xE0\xF6\xC4\x44\x7A\x2A\xD9\x05\x2A\x2A\x2A\x2A\xD9\x47\x08\xDA\xE9\xDF\xE0\xF6\xC4\x44\x7B\x2A\x80\xBE\xDE\x00\x00\x00\x06\x75\x2A\x8B\x8E\xF8\x01\x00\x00\x8B\x01\x8B\x90\xB0\x00\x00\x00";
        StartPrepSDKCall(SDKCall_Entity);
        PrepSDKCall_SetSignature(SDKLibrary_Server, sig, sizeof(sig) - 1);
        PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
        call = EndPrepSDKCall();
        if (call == INVALID_HANDLE)
        {
            SetFailState("Failed to prepare SDK call");
        }
    }
    SDKCall(call, entity, impulse);
}
