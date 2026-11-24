#include "MonitorRecordingFlag.h"
#include <stdatomic.h>

_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2, "The monitor recording flag must be lock-free");

static atomic_bool recording = false;

bool MosMonitorIsRecording(void) {
    return atomic_load_explicit(&recording, memory_order_relaxed);
}

void MosMonitorSetRecording(bool enabled) {
    atomic_store_explicit(&recording, enabled, memory_order_relaxed);
}
