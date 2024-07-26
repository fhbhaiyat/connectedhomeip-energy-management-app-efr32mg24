/*
 *
 *    Copyright (c) 2021 Project CHIP Authors
 *    Copyright (c) 2019 Google LLC.
 *    All rights reserved.
 *
 *    Licensed under the Apache License, Version 2.0 (the "License");
 *    you may not use this file except in compliance with the License.
 *    You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *    Unless required by applicable law or agreed to in writing, software
 *    distributed under the License is distributed on an "AS IS" BASIS,
 *    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *    See the License for the specific language governing permissions and
 *    limitations under the License.
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "AppEvent.h"
#include "LightingManager.h"

#include "FreeRTOS.h"
#include "timers.h" // provides FreeRTOS timer support
#include <ble/Ble.h>
#include <platform/CHIPDeviceLayer.h>

extern "C" {
#include "flash_map_backend.h"
}

// Application-defined error codes in the CHIP_ERROR space.
#define APP_ERROR_EVENT_QUEUE_FAILED CHIP_APPLICATION_ERROR(0x01)
#define APP_ERROR_CREATE_TASK_FAILED CHIP_APPLICATION_ERROR(0x02)
#define APP_ERROR_UNHANDLED_EVENT CHIP_APPLICATION_ERROR(0x03)
#define APP_ERROR_CREATE_TIMER_FAILED CHIP_APPLICATION_ERROR(0x04)
#define APP_ERROR_START_TIMER_FAILED CHIP_APPLICATION_ERROR(0x05)
#define APP_ERROR_STOP_TIMER_FAILED CHIP_APPLICATION_ERROR(0x06)

class AppTask
{

public:
    CHIP_ERROR StartAppTask();
    static void AppTaskMain(void * pvParameter);

    void PostLightActionRequest(int32_t actor, LightingManager::Action_t action);
    void PostEvent(const AppEvent * event);

    void ButtonEventHandler(uint8_t btnIdx, uint8_t btnAction);
    void InitOTARequestor();

private:
    friend AppTask & GetAppTask(void);

    CHIP_ERROR Init();

    static void ActionInitiated(LightingManager::Action_t action, int32_t actor);
    static void ActionCompleted(LightingManager::Action_t action);

    void CancelTimer(void);

    void DispatchEvent(AppEvent * event);

    static void FunctionTimerEventHandler(AppEvent * event);
    static void FunctionHandler(AppEvent * event);
    static void LightActionEventHandler(AppEvent * event);
    static void TimerEventHandler(TimerHandle_t timer);

    static void UpdateClusterState(intptr_t context);

    void StartTimer(uint32_t aTimeoutMs);

    enum class Function
    {
        kNoneSelected = 0,
        kFactoryReset = 1,
        kInvalid
    };

    Function mFunction              = Function::kNoneSelected;
    bool mFunctionTimerActive       = false;
    bool mSyncClusterToButtonAction = false;

    static AppTask sAppTask;
};

inline AppTask & GetAppTask(void)
{
    return AppTask::sAppTask;
}
