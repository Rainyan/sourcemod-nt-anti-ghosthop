#if defined(_BENCHMARK_INC_H_)
#endinput
#else
#define _BENCHMARK_INC_H_
#endif

#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR < 10
stock void BENCHMARK_START(){}
stock void BENCHMARK_END(){}
#endinput
#endif

#include <profiler>

// Can nest max this many profilers, total.
#define MAX_PROFILERS 32
#define MAX_PROFILE_SECTIONNAME_STRLEN 32

static Profiler _profilers_stack[MAX_PROFILERS];
static int _profilers_index = 0;
static char _profilers_sections[MAX_PROFILERS][MAX_PROFILE_SECTIONNAME_STRLEN];

stock void BENCHMARK_START(const char[] section="unnamed")
{
    PrintToServer("BENCHMARK START: %s", section);
    _profilers_stack[_profilers_index] = new Profiler();
    strcopy(_profilers_sections[_profilers_index], sizeof(_profilers_sections[]), section);
    _profilers_stack[_profilers_index++].Start();
}

stock void BENCHMARK_END()
{
    _profilers_stack[--_profilers_index].Stop();
    float time = _profilers_stack[_profilers_index].Time;
    PrintToServer("%s FINISHED IN TIME: %f", _profilers_sections[_profilers_index], time);
    delete _profilers_stack[_profilers_index];

    static DataPack avgs[MAX_PROFILERS] = { null, ... };
    int idx = _profilers_index+1;
    if (avgs[idx] == null)
    {
        avgs[idx] = new DataPack();
    }
    avgs[idx].WriteFloat(time);
    int n = avgs[idx].Position;
    avgs[idx].Reset();
    float avg;
    for (int i = 0; i < n; ++i)
    {
        float t = avgs[idx].ReadFloat();
        avg += t;
    }
    avg /= n;
    PrintToServer("Avg of %d: %f", n, avg);
}