#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

struct RenderingRuntimeParams
{
    
    uint2 frameDim = {0,0};
    uint elemCount = 0;

    uint temCurOffset = 1;   // 0 or 1
    uint temLastOffset = 0;      // 0 or 1

    uint frameCount = 0;
};


END_NAMESPACE_FALCOR
