#if SOURCEMOD_V_MAJOR <= 1 && SOURCEMOD_V_MINOR < 9
// Because we require OnPlayerRunCmdPost, which was added in 1.9.
#error This plugin does not support SourceMod older than 1.9
#endif

#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#include <neotokyo>

// Compile flags for plugin debugging.
// Not recommended on release for performance reasons.
//#define DEBUG
//#define DEBUG_PROFILE
//#define DEBUG_VISUALIZE_HACK_RAYTRACE

#if defined(DEBUG_PROFILE)
#include <profiler>
Profiler _profiler = null;
#endif

#define PLUGIN_VERSION "0.12.1+CompHotfix"
#define PLUGIN_TAG "[ANTI-GHOSTHOP]"
#define NEO_MAXPLAYERS 32

// Class specific max ghost carrier land speeds (w/ 8 degree "wall hug" boost)
#define MAX_SPEED_RECON 255.47
#define MAX_SPEED_ASSAULT 204.38
#define MAX_SPEED_SUPPORT 153.28

// "Grace period" is the buffer during which slight ghost-hopping is tolerated.
// This buffer is used to avoid unintentional & confusing immediate ghost drops
// that can happen when the initial ghost pickup happens at a high speed impulse,
// such as strafe-jumping on the ghost.
#define DEFAULT_GRACE_PERIOD 100.0
// 0.08 is the magic number that felt correct for supports.
// Assault and recon numbers are scaled up from it based on their speed difference.
#define GRACE_PERIOD_BASE_SUBTRAHEND_SUPPORT 0.08
#define GRACE_PERIOD_BASE_SUBTRAHEND_ASSAULT (GRACE_PERIOD_BASE_SUBTRAHEND_SUPPORT * (MAX_SPEED_ASSAULT / MAX_SPEED_SUPPORT))
#define GRACE_PERIOD_BASE_SUBTRAHEND_RECON (GRACE_PERIOD_BASE_SUBTRAHEND_SUPPORT * (MAX_SPEED_RECON / MAX_SPEED_SUPPORT))

// How many seconds of no ghost-jumping at all is required to reset the grace period.
#define GRACE_PERIOD_RESET_MIN_COOLDOWN 0.5
#define GRACE_PERIOD_RESET_MAX_COOLDOWN 3.0
#define GRACE_PERIOD_RESET_INCREMENT 0.25
#define GRACE_PERIOD_RESET_DECREMENT 0.5
#define GRACE_PERIOD_DEFAULT_COOLDOWN GRACE_PERIOD_RESET_MIN_COOLDOWN

// The distance, in Hammer units, that we consider as "free falling". Value must be >= zero!
#define FREEFALL_DISTANCE 300.0

enum GracePeriodEnum {
    FIRST_WARNING, // Only warn once about going too fast
    STILL_TOO_FAST, // Then, tolerate overspeed until we consume the grace period
    FREEFALLING, // Special case where we may choose to ignore a freefalling ghoster
    PENALIZE // ...And finally penalize by forcing ghost drop
};

// Caching this stuff because we're potentially using it on each tick
static int _ghost_carrier_userid;
static int _last_ghost; // ent ref
static float _prev_ghoster_pos[3];
static float _prev_cmd_time[NEO_MAXPLAYERS + 1];
static float _grace_period = DEFAULT_GRACE_PERIOD;
static float _gp_reset_interval = GRACE_PERIOD_RESET_MIN_COOLDOWN;
static float _freefall_velocity;
static bool _freefalling = false;
// Handle for tracking the grace period reset timer
static Handle _timer_reset_gp = INVALID_HANDLE;
// To manually trigger OnGhostDrop event
static Handle g_hForwardDrop;

static ConVar _cvar_gravity;

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

    _cvar_gravity = FindConVar("sv_gravity");
    if (_cvar_gravity == null)
    {
        SetFailState("Could not find sv_gravity");
    }
    _cvar_gravity.AddChangeHook(OnGravityChanged);
    _freefall_velocity = InstantaneousFreeFallVelocity(_cvar_gravity.FloatValue, FREEFALL_DISTANCE);

#if defined(DEBUG)
    // We track ghost by listening to its custom global spawn forward,
    // so in debug mode just manually look it up instead, so that we can
    // repeatedly reload this plugin mid-level without hassle.
    char ename[12 + 1];
    for (int e = MaxClients + 1; e <= GetMaxEntities(); ++e)
    {
        if (!IsValidEdict(e))
        {
            continue;
        }
        if (!GetEdictClassname(e, ename, sizeof(ename)))
        {
            continue;
        }
        if (StrEqual(ename, "weapon_ghost"))
        {
            _last_ghost = EntIndexToEntRef(e);
            if (EntRefToEntIndex(_last_ghost) == INVALID_ENT_REFERENCE)
            {
                SetFailState("Failed to retrieve entref for %d", e);
            }
            PrintToServer("%s DEBUG :: Assigned _last_ghost manually", PLUGIN_TAG);
            break;
        }
    }
#endif

    CreateTimer(5.0, Timer_RecoverGraceInterval, _, TIMER_REPEAT);
}

public void OnAllPluginsLoaded()
{
    if (FindConVar("sm_ntghostcap_version") == null)
    {
        SetFailState("This plugin requires the nt_ghostcap plugin");
    }
    g_hForwardDrop = CreateGlobalForward("OnGhostDrop", ET_Event, Param_Cell);
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

public void OnGravityChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    _freefall_velocity = InstantaneousFreeFallVelocity(StringToFloat(newValue), FREEFALL_DISTANCE);
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
    _ghost_carrier_userid = GetClientUserId(client);
    return Plugin_Continue;
}

public Action OnGhostSpawn(int ghost_ref)
{
    _last_ghost = ghost_ref;
    ResetGhoster();
    return Plugin_Continue;
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
    if (GetEntityFlags(client) & FL_ONGROUND)
    {
        _freefalling = false;

        // A timer for restoring the grace period after settling down
        if (_timer_reset_gp == INVALID_HANDLE && _grace_period < DEFAULT_GRACE_PERIOD)
        {
            _timer_reset_gp = CreateTimer(_gp_reset_interval, Timer_ResetGp, _ghost_carrier_userid);
            IncrementGpResetInterval();
        }
    }
    // We need to have a previous known position to calculate velocity.
    else if (!VectorsEqual(_prev_ghoster_pos, NULL_VECTOR))
    {
        // Ignore ladders
        if (GetEntityMoveType(client) == MOVETYPE_LADDER)
        {
            ResetGracePeriod();
            _freefalling = false;
            return;
        }
#if defined(DEBUG)
        // Ignore debug noclip flying
        else if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
        {
            ResetGracePeriod();
            _freefalling = true;
            return;
        }
#endif

        if (_freefalling)
        {
            return;
        }

        // Client can't restore their grace period whilst jumping
        CancelGracePeriodRestoreTimer();

#if defined(DEBUG_PROFILE)
        _profiler.Start();
#endif

        float dir[3];
        SubtractVectors(ghoster_pos, _prev_ghoster_pos, dir);

        // Vertical movement
        float vert_distance = dir[2];

        // Lateral movement
        dir[2] = 0.0;
        float lat_distance = GetVectorLength(dir);

        float time = GetGameTime();
        float delta_time = time - _prev_cmd_time[client];
        // Would result in division by zero, so get some reasonable approximation.
        if (delta_time == 0)
        {
            delta_time = GetTickInterval();
        }
        _prev_cmd_time[client] = time;

        // Estimate our current speed in engine units per second.
        float lateral_air_velocity = lat_distance / delta_time;

#if defined(DEBUG_PROFILE)
        _profiler.Stop();
        PrintToServer("Profiler (OnPlayerRunCmdPost :: Vector maths): %f", _profiler.Time);
#endif

        int player_class = GetPlayerClass(client);
        float max_vel = (player_class == CLASS_RECON) ? MAX_SPEED_RECON
            : (player_class == CLASS_ASSAULT) ? MAX_SPEED_ASSAULT : MAX_SPEED_SUPPORT;

        if (lateral_air_velocity > max_vel)
        {
#if defined(DEBUG_PROFILE)
            _profiler.Start();
#endif

            float vertical_air_velocity = vert_distance / delta_time;
            float base_subtrahend = (player_class == CLASS_RECON) ? GRACE_PERIOD_BASE_SUBTRAHEND_RECON
                : (player_class == CLASS_ASSAULT) ? GRACE_PERIOD_BASE_SUBTRAHEND_ASSAULT : GRACE_PERIOD_BASE_SUBTRAHEND_SUPPORT;

            GracePeriodEnum gp = PollGracePeriod(lateral_air_velocity, vertical_air_velocity, max_vel, base_subtrahend, player_class);

#if defined(DEBUG_PROFILE)
            _profiler.Stop();
            PrintToServer("Profiler (OnPlayerRunCmdPost :: Grace period): %f", _profiler.Time);
#endif

            if (gp == STILL_TOO_FAST)
            {
                return;
            }
            else if (gp == FIRST_WARNING)
            {
                PrintToChat(client, "%s Jumping too fast – please slow down to avoid ghost drop", PLUGIN_TAG);
                return;
            }
            else if (gp == FREEFALLING)
            {
                _freefalling = true;
                return;
            }

            int ghost = EntRefToEntIndex(_last_ghost);
            // We had a ghoster userid but the ghost itself no longer exists for whatever reason.
            if (ghost == 0 || ghost == INVALID_ENT_REFERENCE)
            {
                ResetGhoster();
                return;
            }

            int wep = GetEntPropEnt(client, Prop_Data, "m_hMyWeapons");

            if (wep != -1 && wep == ghost)
            {
                // HACK: Final sanity check before we call this penalizable ghost hopping.
                // For some reason, this has been triggering for seemingly not-jumping ghost carriers
                // in un-reproducable ways; this final check should catch those cases.
                // This is kind of awful but necessary for now.
                if (!Hack_IsReallyAirborne(client))
                {
                    _prev_ghoster_pos = ghoster_pos;
                    return;
                }

#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR == 9
                // SM 1.9 bug with the velocity parameter; can't use NULL_VECTOR
                float vec3_zero[3];
                SDKHooks_DropWeapon(client, ghost, ghoster_pos, vec3_zero);
#else
                SDKHooks_DropWeapon(client, ghost, ghoster_pos, NULL_VECTOR);
#endif

                PrintToChat(client, "%s You have dropped the ghost (jumping faster than ghost carry speed)", PLUGIN_TAG);
                Call_StartForward(g_hForwardDrop);
                Call_PushCell(client);
                Call_Finish();
            }
            // We had a ghoster userid, and the ghost exists, but that supposed ghoster no longer holds the ghost.
            // This can happen if the ghoster is ghost hopping exactly as the round ends and the ghost de-spawns.
            // Can also happen on the tick after we already forced a ghost drop, until our entdata updates.
            else
            {
                ResetGhoster(); // no longer reliably know ghoster info - have to reset and give up on this cmd
            }

            return;
        }
    }

    _prev_ghoster_pos = ghoster_pos;
}

// HACK: We're hitting false positives, but there's no reproducible case yet,
// so just do a dumb heuristic to verify if we're actually hopping.
// This should get cleaned up to fix the underlying bug, initially.
// This could get us a false negative with really bad luck,
// but it's much better than a false positive ruining rounds.
//
// This does a bunch of raycasts around the bottom of the player's
// mins/maxs collision boundary, and measure the distance to walkable
// geometry from below those points. If any point of the player collider
// is sufficiently close to standing atop walkable geometry, we consider it not jumping.
//
// All of this stuff should be handled for us by the engine, via the FL_ONGROUND flag, but alas.
bool Hack_IsReallyAirborne(int client)
{
#if defined(DEBUG_PROFILE)
    _profiler.Start();
#endif

    float start[3];
    float end[3];
    GetClientAbsOrigin(client, start);

    // Offsets to fire raycasts from
    float minsmaxs_offsets[][] = {
        // Get abs origin center first
        { 0.0, 0.0, 0.0 },

        // The lateral mins/maxs are the same (16) for all classes in NT.
        { -16.0, -16.0, 0.0 },
        { -16.0, 16.0, 0.0 },
        { 16.0, -16.0, 0.0 },
        { 16.0, 16.0, 0.0 },
        // The centers of the outer edge of the lateral bottom-minsmaxs.
        { -16.0, 0.0, 0.0 },
        { 0.0, -16.0, 0.0 },
        { 16.0, 0.0, 0.0 },
        { 0.0, 16.0, 0.0 },

        // ... And centers of in-between the corners and the centers.
        // We mostly care about this outer circle, because that's what will detect
        // us standing on a sloped surface where the abs origin is not making contact with the ground.
        { -16.0, 4.0, 0.0 },
        { -16.0, -4.0, 0.0 },
        { 16.0, 4.0, 0.0 },
        { 16.0, -4.0, 0.0 },
        { 4.0, 16.0, 0.0 },
        { -4.0, -16.0, 0.0 },
        { 4.0, 16.0, 0.0 },
        { 4.0, -16.0, 0.0 },
        { -16.0, 8.0, 0.0 },
        { -16.0, -8.0, 0.0 },
        { 16.0, 8.0, 0.0 },
        { 16.0, -8.0, 0.0 },
        { 8.0, 16.0, 0.0 },
        { -8.0, -16.0, 0.0 },
        { 8.0, 16.0, 0.0 },
        { 8.0, -16.0, 0.0 },
        { -16.0, 12.0, 0.0 },
        { -16.0, -12.0, 0.0 },
        { 16.0, 12.0, 0.0 },
        { 16.0, -12.0, 0.0 },
        { 12.0, 16.0, 0.0 },
        { -12.0, -16.0, 0.0 },
        { 12.0, 16.0, 0.0 },
        { 12.0, -16.0, 0.0 },
        { -12.0, 16.0, 0.0 },
        { -8.0, 16.0, 0.0 },
        { -4.0, 16.0, 0.0 },

        // And finally, do an X-shape to get some spots around the middle of the collider's bottom.
        { 4.0, 4.0, 0.0 },
        { -4.0, -4.0, 0.0 },
        { 4.0, -4.0, 0.0 },
        { -4.0, 4.0, 0.0 },
        { 8.0, 8.0, 0.0 },
        { -8.0, -8.0, 0.0 },
        { 8.0, -8.0, 0.0 },
        { -8.0, 8.0, 0.0 },
        { 12.0, 12.0, 0.0 },
        { -12.0, -12.0, 0.0 },
        { 12.0, -12.0, 0.0 },
        { -12.0, 12.0, 0.0 },
    };

    // Angle to fire at (directly down)
    float ang_down[3] = { 90.0, 0.0, 0.0 };

    for (int i = 0; i < sizeof(minsmaxs_offsets); ++i)
    {
        // Offset from the abs origin
        AddVectors(start, minsmaxs_offsets[i], start);

        // Playersolid masks anything player-standable
        TR_TraceRay(start, ang_down, MASK_PLAYERSOLID,
            RayType_Infinite);
        TR_GetEndPosition(end);

        // Visualize the ray casts for debug
#if defined(DEBUG_VISUALIZE_HACK_RAYTRACE)
#define BEAM_ASSET "materials/sprites/purplelaser1.vmt"
        if (!FileExists(BEAM_ASSET, true, NULL_STRING))
        {
            SetFailState("File doesn't exist: \"%s\"", BEAM_ASSET);
        }
        int model = PrecacheModel(BEAM_ASSET);
        if (model == 0)
        {
            SetFailState("Failed to precache: \"%s\"", BEAM_ASSET);
        }
        int color[4] = { 255, 255, 0, 255 };
        TE_SetupBeamPoints(start, end, model, model, 0, 1, 10.0, 3.0, 3.0, 1, 1.0, color, 10);
        TE_SendToAll();
#endif

        float dist_to_ground = GetVectorDistance(start, end);
#if defined(DEBUG)
        PrintToChat(client,"%s (DEBUG) Dist %d: %f", PLUGIN_TAG, i, dist_to_ground);
#endif

#define DIST_TO_GROUND_CONSIDERED_AIRBONE 4.0
        // If any of the lateral mins of the client are at a near-brushing distance
        // from a solid surface, consider us to not be fully airborne.
        if (dist_to_ground <= DIST_TO_GROUND_CONSIDERED_AIRBONE)
        {
#if defined(DEBUG_PROFILE)
            _profiler.Stop();
            PrintToServer("Profiler (Hack_IsReallyAirborne :: Raycasting stuff -- early return at %d): %f", i, _profiler.Time);
#if defined(DEBUG_VISUALIZE_HACK_RAYTRACE)
            PrintToServer("WARNING: Also visualizing the raytrace(s) -- this will degrade performance in the measurement!");
#endif
#endif
            return false;
        }

        // Undo the offset so we can reuse variables.
        SubtractVectors(start, minsmaxs_offsets[i], start);
    }

    // Combined with the FL_ONGROUND flag (which really should be doing all of this stuff),
    // we're reasonably confident we are actually in-air if we got this far.
    // There is a small chance of false positive with some really unfortunate "holey" geometry,
    // but this should catch nearly all usual cases.
#if defined(DEBUG_PROFILE)
    _profiler.Stop();
    PrintToServer("Profiler (Hack_IsReallyAirborne :: Raycasting stuff -- complete loop): %f", _profiler.Time);
#if defined(DEBUG_VISUALIZE_HACK_RAYTRACE)
    PrintToServer("WARNING: Also visualizing the raytrace(s) -- this will degrade performance in the measurement!");
#endif
#endif
    return true;
}

public Action Timer_ResetGp(Handle timer, int userid)
{
    if (userid == _ghost_carrier_userid)
    {
        ResetGracePeriod();
    }

    _timer_reset_gp = INVALID_HANDLE;
    return Plugin_Stop;
}

public Action Timer_RecoverGraceInterval(Handle timer)
{
    if (_timer_reset_gp == INVALID_HANDLE)
    {
        DecrementGpResetInterval();
    }
    return Plugin_Continue;
}

void CancelGracePeriodRestoreTimer()
{
    if (_timer_reset_gp != INVALID_HANDLE)
    {
        CloseHandle(_timer_reset_gp);
        _timer_reset_gp = INVALID_HANDLE;
    }
}

void ResetGhoster()
{
    CancelGracePeriodRestoreTimer();
    _prev_cmd_time[GetClientOfUserId(_ghost_carrier_userid)] = 0.0;
    _ghost_carrier_userid = 0;
    _prev_ghoster_pos = NULL_VECTOR;
    ResetGracePeriod();
    _gp_reset_interval = GRACE_PERIOD_DEFAULT_COOLDOWN;
    _freefalling = false;
}

// Updates grace period, and returns current grace status.
GracePeriodEnum PollGracePeriod(float lateral_vel, float vertical_vel, float max_lateral_vel, float base_subtrahend, int player_class)
{
#if defined(DEBUG)
    // the 'should never happen's
    if (max_lateral_vel == 0)
    {
        SetFailState("Division by zero");
    }
    if (_grace_period > DEFAULT_GRACE_PERIOD)
    {
        SetFailState("_grace_period > DEFAULT_GRACE_PERIOD");
    }
#endif

    // Give a free pass to ghosters who are freefalling from a drop higher than
    // FREEFALL_DISTANCE, as they are likely to do large sweeping air strafes
    // to correct their fall path, which could well trigger the bhop speed limit.
    // This check sidesteps such issue of players inadvertently losing ghost
    // during long falls, such as the nt_rise_ctg roof drop (which is ~600 units
    // in height, total).
    if (vertical_vel <= _freefall_velocity)
    {
        return FREEFALLING;
    }

    bool initial_state = (_grace_period == DEFAULT_GRACE_PERIOD);
    static bool has_seen_first_warning;
    if (initial_state)
    {
        has_seen_first_warning = false;
    }

    float subtrahend = base_subtrahend * (lateral_vel / max_lateral_vel);
    // Special case for supports because their inheritly slow speed makes the
    // penalty kick in unreasonably quick otherwise.
    if (player_class == CLASS_SUPPORT)
    {
        subtrahend *= 0.4;
    }

    _grace_period -= subtrahend;

    // Regardless of other factors, instantly penalize if crossed the limit
    if (_grace_period <= 0)
    {
        return PENALIZE;
    }
    // Need manual adjustment for supports' warnings because their lack of sprinting throws off the values otherwise
    if (_grace_period <= ((player_class == CLASS_SUPPORT) ? (DEFAULT_GRACE_PERIOD * 0.625) : DEFAULT_GRACE_PERIOD))
    {
        if (!has_seen_first_warning)
        {
            has_seen_first_warning = true;
            return FIRST_WARNING;
        }
    }

    return STILL_TOO_FAST;
}

void ResetGracePeriod()
{
    _grace_period = DEFAULT_GRACE_PERIOD;
}

void IncrementGpResetInterval()
{
    _gp_reset_interval = Min(_gp_reset_interval + GRACE_PERIOD_RESET_INCREMENT, GRACE_PERIOD_RESET_MAX_COOLDOWN);
}

void DecrementGpResetInterval()
{
    _gp_reset_interval = Max(_gp_reset_interval - GRACE_PERIOD_RESET_DECREMENT, GRACE_PERIOD_RESET_MIN_COOLDOWN);
}

float InstantaneousFreeFallVelocity(float gravity, float distance)
{
    // This return value is negated because we'll be later comparing it to a vertical 3D velocity component,
    // where falling motion is discriminated by a negative sign. We also ignore the possibility of negative
    // gravity in favor of a simpler code path, since comparisons that use this (cached) value may be
    // running very frequently, possibly 66 times per second.
    return -SquareRoot(2.0 * (gravity * gravity) * distance);
}

stock float Min(float a, float b)
{
    return a < b ? a : b;
}

stock float Max(float a, float b)
{
    return a > b ? a : b;
}

stock bool VectorsEqual(const float v1[3], const float v2[3], const float max_ulps = 0.0)
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
