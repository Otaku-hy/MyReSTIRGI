__exported import ReSTIRParams;
__exported import ReSTIRMathFunctions;
__exported import GIReservoir;

RWStructuredBuffer<RisSample> initialSampleBuffer;
RWStructuredBuffer<Reservoir> temporalReservoirBuffer;
RWStructuredBuffer<Reservoir> spatialReservoirBuffer;

cbuffer PreBufferCB
{
    RenderingRuntimeParams params;
};

bool IsValidPixel(int2 pixel)
{
    if(pixel.x < params.frameDim.x && pixel.y < params.frameDim.y && pixel.x >= 0 && pixel.y >= 0)
    {
        return true;
    }
    return false;
}


bool IsValidSample(RisSample sample)
{
    if(any(sample.sNorm != 0))
        return true;
    return false;
}

bool IsValidReservoir(Reservoir r)
{
    if(IsValidSample(r.z))
        return true;
    return false;
}

bool ReservoirExist(Reservoir r)
{
    if(any(r.z.vNorm !=0))
        return true;
    return false;
}

RisSample GetRisSample(int2 pixel)
{
    if(!IsValidPixel(pixel)) return RisSample();
    uint sampleID = pixel.y * params.frameDim.x + pixel.x;
    return initialSampleBuffer[sampleID];
}

Reservoir GetTemporalReservoir(int2 pixel,bool isLastFrame)
{
    if(!IsValidPixel(pixel)) return Reservoir();
    uint sampleID = pixel.y * params.frameDim.x + pixel.x;
    if(!isLastFrame) return temporalReservoirBuffer[params.temCurOffset * params.elemCount + sampleID];
    return temporalReservoirBuffer[params.temLastOffset * params.elemCount + sampleID];
}

Reservoir GetSpatialReservoir(int2 pixel,bool isLastFrame)
{
    if(!IsValidPixel(pixel)) return Reservoir();
    uint sampleID = pixel.y * params.frameDim.x + pixel.x;
    if(!isLastFrame) return spatialReservoirBuffer[params.temCurOffset * params.elemCount + sampleID];
    return spatialReservoirBuffer[params.temLastOffset * params.elemCount + sampleID];
}

void ResetNeighbor(inout Reservoir neighbor,Reservoir r)
{
    neighbor.z.vPos = r.z.vPos;
    neighbor.z.vNorm = r.z.vNorm;
}

void SetRisSample(int2 pixel,RisSample s)
{
    uint sampleID = pixel.y * params.frameDim.x + pixel.x;
    initialSampleBuffer[sampleID] = s;
}

void SetTemporalReservoir(uint2 pixel,Reservoir r)
{
    uint sampleID = pixel.y * params.frameDim.x + pixel.x;
    temporalReservoirBuffer[params.temCurOffset * params.elemCount + sampleID] = r;
}

void SetSpatialReservoir(uint2 pixel,Reservoir r)
{
    uint sampleID = pixel.y * params.frameDim.x + pixel.x;
    spatialReservoirBuffer[params.temCurOffset * params.elemCount + sampleID] = r;
}

uint ToLinearIndex(uint2 pixel)
{
    return pixel.y * params.frameDim.x + pixel.x;
}
