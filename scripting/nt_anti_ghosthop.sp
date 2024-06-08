#include <sourcemod>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "3.0.0"
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

// There seems to be some kind of "drift" in bhop tick speed calculations,
// where some hops get a ups speed of 0 and others double speed for the missed one.
// Smooth out ups checks over several ticks to avoid false positives.
#define N_SPEED_SAMPLES 2
#assert N_SPEED_SAMPLES > 0
static float _avg_speed[N_SPEED_SAMPLES];
static int _avg_speed_head;

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
    ClearAvgSpeed();

    CreateConVar("sm_nt_anti_ghosthop_version", PLUGIN_VERSION,
        "NT Anti Ghosthop plugin version", FCVAR_DONTRECORD);

    _verbose = CreateConVar("sm_nt_anti_ghosthop_verbosity", "0",
        "How much feedback to give to the players about ghosthopping. \
0: disabled, 1: notify when being limited in text chat occasionally, \
2: notify for every single limited hop",
        _, true, 0.0, true, 2.0);
    _scale = CreateConVar("sm_nt_anti_ghosthop_speed_scale", "1.0",
        "Max allowed ghosthop speed before slowdown begins. 1.0 means class specific \
max ghost movement speed, 0.0 means no speed limit.",
        _, true, 0.0);
    _n_allowed_hops = CreateConVar("sm_nt_anti_ghosthop_n_extra_hops", "0",
        "How many extra ghost hops to tolerate before limiting speed. Resets \
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

public void OnGameFrame()
{
    if (!_ghost_carrier ||
        !IsClientInGame(_ghost_carrier) ||
        !IsPlayerAlive(_ghost_carrier))
    {
        return;
    }

    CheckGhostCarrierSlowdown(_ghost_carrier);
}

void RecordSpeed(float speed)
{
    //PrintToChatAll("Speed: %f", speed);
    _avg_speed[_avg_speed_head] = speed;
    _avg_speed_head = (_avg_speed_head+1) % sizeof(_avg_speed);
}

float GetAvgSpeed()
{
    float speed;
    for (int i = 0; i < sizeof(_avg_speed); ++i)
    {
        speed += _avg_speed[i];
    }
    speed /= sizeof(_avg_speed);
    //PrintToChatAll("Avg: %f", speed);
    return speed;
}

void ClearAvgSpeed()
{
    for (int i = 0; i < sizeof(_avg_speed); ++i)
    {
        _avg_speed[i] = 200.0;
    }
}

void CheckGhostCarrierSlowdown(int client)
{
    float pos[3];
    GetClientAbsOrigin(client, pos);

    bool is_on_ground = GetEntityFlags(client) & FL_ONGROUND != 0;
    float delta_time = GetGameFrameTime();

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
                ups[0] /= delta_time;
                ups[1] /= delta_time;
                ups[2] = 0.0;

                float speed = GetVectorLength(ups);
                RecordSpeed(speed);
                float max_speed = GetMaxGhostSpeed(client) * _scale.FloatValue;

                if (speed > max_speed)
                {
                    NormalizeVector(ups, ups);
                    ScaleVector(ups, (-max_speed+GetAvgSpeed()));
                    ApplyAbsVelocityImpulse(client, ups);
                    ClearAvgSpeed();

                    if (_verbose.BoolValue)
                    {
                        bool printNow = (_verbose.IntValue == 2);

                        if (!printNow)
                        {
                            static int last_nag_time;
                            int time = GetTime();
                            printNow = (time - last_nag_time > 15);
                            if (printNow)
                            {
                                last_nag_time = time;
                            }
                        }

                        if (printNow)
                        {
                            PrintToChat(client, "%s Limiting speed to %.0f",
                                PLUGIN_TAG, max_speed);
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

    ClearAvgSpeed();
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
