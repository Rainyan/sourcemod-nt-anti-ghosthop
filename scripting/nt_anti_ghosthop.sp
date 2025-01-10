#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "4.1.3"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

#define DEBUG_PROFILE false
#if DEBUG_PROFILE
#include "benchmark"
#endif

// Class specific max ghost carrier land speeds,
// using a "wall hug" boost angle of 0.14015 radians
// or about 8.030003498758488 degrees.
// To test this, use: setang 0 8.030003498758488 0
// and offset by multiples of 90 to choose cardinal direction.
#define MAX_SPEED_RECON 255.59
#define MAX_SPEED_ASSAULT 204.47
#define MAX_SPEED_SUPPORT 204.47

ConVar _verbosity;
bool _late;
float _max_speed_squared, _ratio;

public Plugin myinfo = {
    name = "NT Anti Ghosthop",
    description = "Limit the max movement speed while bunnyhopping with the ghost.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-anti-ghosthop"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    _late = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    CreateConVar("sm_nt_anti_ghosthop_version", PLUGIN_VERSION,
        "NT Anti Ghosthop plugin version", FCVAR_DONTRECORD);

    ConVar ratio = CreateConVar("sm_nt_anti_ghosthop_ratio", "1.0",
        "Scale for the max carry speed. \
1 means original carry speed. \
2 means double speed. \
0.5 means half speed.",
        _, true, 0.01);
    ratio.AddChangeHook(OnRatioChanged);
    _ratio = ratio.FloatValue;

    _verbosity = CreateConVar("sm_nt_anti_ghosthop_verbosity", "0.0",
        "How verbosely should the speed limiting be announced. \
0: no announcement. \
1: announce to the ghoster in chat.",
        _, true, float(false), true, float(true));

    AutoExecConfig();
    LoadTranslations("nt_anti_ghosthop.phrases");

    if (_late)
    {
        InitGhoster();
    }
}

void InitGhoster()
{
    for (int ent = MaxClients+1; ent < GetMaxEntities(); ++ent)
    {
        if (!IsValidEdict(ent))
        {
            continue;
        }
        if (!IsGhost(ent))
        {
            continue;
        }
        int ghoster = GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity");
        if (ghoster != -1)
        {
            OnGhostPickUp(ghoster);
        }
        break;
    }
}

public void OnAllPluginsLoaded()
{
    if (FindConVar("sm_ntghostcap_version") == null)
    {
        SetFailState("This plugin requires the nt_ghostcap plugin");
    }
}

public void OnConfigsExecuted()
{
    _ratio = FindConVar("sm_nt_anti_ghosthop_ratio").FloatValue;
}

public void OnClientDisconnect(int client)
{
    ClearGhoster(client);
}

void OnRatioChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    _ratio = StringToFloat(newValue);
    InitGhoster();
}

void SetGhoster(int ghoster)
{
    if (!SDKHookEx(ghoster, SDKHook_PreThink, OnGhosterThink))
    {
        SetFailState("Failed to SDKHook");
    }

    _max_speed_squared = Pow(GetMaxGhostSpeed(ghoster) * _ratio, 2.0);
}

void ClearGhoster(int ghoster)
{
    SDKUnhook(ghoster, SDKHook_PreThink, OnGhosterThink);
}

public void OnGhostCapture(int client)
{
    ClearGhoster(client);
}

public void OnGhostDrop(int client)
{
    ClearGhoster(client);
}

public void OnGhostPickUp(int client)
{
    SetGhoster(client);
    ThrottledNag(client);
}

void ThrottledNag(int ghoster)
{
    if (!_verbosity.BoolValue)
    {
        return;
    }

    static int last_nag[NEO_MAXPLAYERS];

    int index = ghoster-1,
        epoch = GetTime(),
        dt = epoch - last_nag[index],
        nag_cooldown_seconds = 5;

    if (dt >= nag_cooldown_seconds)
    {
        PrintToChat(ghoster, "%s %T", PLUGIN_TAG, "SpeedLimited", LANG_SERVER);
        last_nag[index] = epoch;
    }
}

public void OnGhosterThink(int ghoster)
{
#if DEBUG_PROFILE
    BENCHMARK_START();
#endif

    float vel[3];
    GetEntPropVector(ghoster, Prop_Data, "m_vecAbsVelocity", vel);
    vel[2] = 0.0;
    float speed_squared = GetVectorLength(vel, true);

    if (speed_squared <= _max_speed_squared)
    {
#if DEBUG_PROFILE
        BENCHMARK_END();
#endif
        return;
    }

    if (GetEntityMoveType(ghoster) == MOVETYPE_LADDER)
    {
#if DEBUG_PROFILE
        BENCHMARK_END();
#endif
        return;
    }

    float speed = SquareRoot(speed_squared);
    float max_speed = SquareRoot(_max_speed_squared);
    float over_speed = speed - max_speed;

    NormalizeVector(vel, vel);
    ScaleVector(vel, -over_speed);
    ApplyAbsVelocityImpulse(ghoster, vel);

#if DEBUG_PROFILE
    BENCHMARK_END();
#endif
}

public void OnGhostSpawn(int ghost_ref)
{
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientInGame(client))
        {
            ClearGhoster(client);
        }
    }
}

bool IsGhost(int ent)
{
    char name[12+1];
    if (!GetEntityClassname(ent, name, sizeof(name)))
    {
        return false;
    }
    return StrEqual(name, "weapon_ghost");
}

public void OnEntityDestroyed(int entity)
{
    if (!IsGhost(entity))
    {
        return;
    }
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (IsClientInGame(client))
        {
            ClearGhoster(client);
        }
    }
}

stock float GetMaxGhostSpeed(int client)
{
    switch (GetPlayerClass(client))
    {
        case CLASS_RECON: return MAX_SPEED_RECON;
        case CLASS_ASSAULT: return MAX_SPEED_ASSAULT;
        case CLASS_SUPPORT: return MAX_SPEED_SUPPORT;
    }
    LogError("Unknown class %d for client %N (%d)", GetPlayerClass(client), client, client);
    return MAX_SPEED_RECON;
}

stock void ApplyAbsVelocityImpulse(int entity, const float impulse[3])
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
