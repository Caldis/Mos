#ifndef MOS_MONITOR_RECORDING_FLAG_H
#define MOS_MONITOR_RECORDING_FLAG_H

#include <stdbool.h>

bool MosMonitorIsRecording(void);
void MosMonitorSetRecording(bool enabled);

#endif
