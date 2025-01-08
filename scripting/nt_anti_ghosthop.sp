#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "4.0.0"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"

// Class specific max ghost carrier land speeds (w/ ~36.95 degree "wall hug" boost)
#define MAX_SPEED_RECON 255.427734
#define MAX_SPEED_ASSAULT 204.364746
#define MAX_SPEED_SUPPORT 204.380859

ConVar _ratio;
bool _late;

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

    _ratio = CreateConVar("sm_nt_anti_ghosthop_ratio", "1.0",
        "Scale for the max carry speed. \
1 means original carry speed. \
2 means double speed. \
0.5 means half speed.",
        _, true, 0.01);

    AutoExecConfig();

    if (_late)
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
}

public void OnAllPluginsLoaded()
{
    if (FindConVar("sm_ntghostcap_version") == null)
    {
        SetFailState("This plugin requires the nt_ghostcap plugin");
    }
}

public void OnClientDisconnect(int client)
{
    ClearGhoster(client);
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
    if (!SDKHookEx(client, SDKHook_PreThink, OnGhosterThink))
    {
        SetFailState("Failed to SDKHook");
    }
}

public void OnGhosterThink(int ghoster)
{
    float vel[3];
    GetEntPropVector(ghoster, Prop_Data, "m_vecAbsVelocity", vel);
    vel[2] = 0.0;
    float speed = GetVectorLength(vel);

    float maxSpeed = GetMaxGhostSpeed(ghoster) * _ratio.FloatValue;

    if (speed <= maxSpeed)
    {
        return;
    }

    float overSpeed = speed - maxSpeed;
    NormalizeVector(vel, vel);
    ScaleVector(vel, -overSpeed);
    ApplyAbsVelocityImpulse(ghoster, vel);
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
    LogErrorOnce("Unknown class %d for client %N (%d)", GetPlayerClass(client), client, client);
    return MAX_SPEED_RECON;
}

static void LogErrorOnce(const char[] format, any ...)
{
    static bool once;
    if (!once)
    {
        once = !once;
        char buffer[512];
        VFormat(buffer, sizeof(buffer), format, 2);
        LogError("%s", buffer);
    }
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
