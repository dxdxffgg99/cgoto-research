/*
 * pstat: minimal "perf stat" replacement built directly on perf_event_open.
 * For systems where the perf tool cannot launch workloads (e.g. Android app uid).
 *
 * usage: pstat [-o file] [-e ev1,ev2,...] -- command [args...]
 *   events: task-clock cycles instructions branches branch-misses raw-0xNN (raw PMU event)
 *   default: task-clock,cycles,instructions,branches,branch-misses
 * Output (to stderr or -o file) is CSV like `perf stat -x,`:  value,unit,event
 * followed by  elapsed_seconds,s,time-elapsed.  User-mode counts only.
 * The command's stdout/stderr are passed through; pstat exits with its status.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <linux/perf_event.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAXEV 16

struct ev { const char *name; uint32_t type; uint64_t config; int fd; };

static int parse_event(const char *s, struct ev *e)
{
    e->name = s;
    if (!strcmp(s, "task-clock"))    { e->type = PERF_TYPE_SOFTWARE; e->config = PERF_COUNT_SW_TASK_CLOCK; }
    else if (!strcmp(s, "cycles"))        { e->type = PERF_TYPE_HARDWARE; e->config = PERF_COUNT_HW_CPU_CYCLES; }
    else if (!strcmp(s, "instructions"))  { e->type = PERF_TYPE_HARDWARE; e->config = PERF_COUNT_HW_INSTRUCTIONS; }
    else if (!strcmp(s, "branches"))      { e->type = PERF_TYPE_HARDWARE; e->config = PERF_COUNT_HW_BRANCH_INSTRUCTIONS; }
    else if (!strcmp(s, "branch-misses")) { e->type = PERF_TYPE_HARDWARE; e->config = PERF_COUNT_HW_BRANCH_MISSES; }
    else if (!strncmp(s, "raw-", 4))      { e->type = PERF_TYPE_RAW; e->config = strtoull(s + 4, NULL, 0); }
    else return -1;
    return 0;
}

int main(int argc, char **argv)
{
    const char *out = NULL;
    char evbuf[1024] = "task-clock,cycles,instructions,branches,branch-misses";
    int i = 1;
    for (; i < argc; i++) {
        if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        else if (!strcmp(argv[i], "-e") && i + 1 < argc) snprintf(evbuf, sizeof evbuf, "%s", argv[++i]);
        else if (!strcmp(argv[i], "--")) { i++; break; }
        else break;
    }
    if (i >= argc) { fprintf(stderr, "usage: pstat [-o file] [-e events] -- cmd [args]\n"); return 2; }

    struct ev evs[MAXEV];
    int n = 0;
    for (char *t = strtok(evbuf, ","); t && n < MAXEV; t = strtok(NULL, ",")) {
        if (parse_event(t, &evs[n]) < 0) { fprintf(stderr, "pstat: unknown event %s\n", t); return 2; }
        n++;
    }

    int go[2];
    if (pipe(go) < 0) { perror("pipe"); return 2; }
    pid_t pid = fork();
    if (pid == 0) {                       /* child: wait until counters are attached */
        char c;
        close(go[1]);
        if (read(go[0], &c, 1) != 1) _exit(127);
        execvp(argv[i], argv + i);
        perror("execvp");
        _exit(127);
    }
    close(go[0]);

    for (int k = 0; k < n; k++) {
        struct perf_event_attr a;
        memset(&a, 0, sizeof a);
        a.size = sizeof a;
        a.type = evs[k].type;
        a.config = evs[k].config;
        a.disabled = 1;
        a.enable_on_exec = 1;
        a.inherit = 1;
        a.exclude_kernel = 1;
        a.exclude_hv = 1;
        a.read_format = PERF_FORMAT_TOTAL_TIME_ENABLED | PERF_FORMAT_TOTAL_TIME_RUNNING;
        evs[k].fd = (int)syscall(SYS_perf_event_open, &a, pid, -1, -1, 0);
        if (evs[k].fd < 0)
            fprintf(stderr, "pstat: cannot open %s: %s\n", evs[k].name, strerror(errno));
    }

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    if (write(go[1], "x", 1) != 1) { perror("write"); return 2; }
    close(go[1]);
    int st = 0;
    waitpid(pid, &st, 0);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    FILE *f = out ? fopen(out, "w") : stderr;
    if (!f) { perror(out); f = stderr; }
    for (int k = 0; k < n; k++) {
        uint64_t v[3] = {0, 0, 0};
        if (evs[k].fd < 0 || read(evs[k].fd, v, sizeof v) != sizeof v) {
            fprintf(f, "<not counted>,,%s\n", evs[k].name);
            continue;
        }
        double val = (double)v[0];
        if (v[2] && v[2] < v[1]) val = val * (double)v[1] / (double)v[2];   /* multiplexed */
        if (evs[k].type == PERF_TYPE_SOFTWARE && evs[k].config == PERF_COUNT_SW_TASK_CLOCK)
            fprintf(f, "%.2f,msec,task-clock\n", val / 1e6);
        else
            fprintf(f, "%.0f,,%s%s\n", val, evs[k].name, (v[2] && v[2] < v[1]) ? " (scaled)" : "");
    }
    fprintf(f, "%.9f,s,time-elapsed\n",
            (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9);
    if (f != stderr) fclose(f);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}
