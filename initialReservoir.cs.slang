import GIReservoir;
import ReSTIRHelpFunctions;

RWTexture2D<float3> outputColor;
RWStructuredBuffer<Reservoir> initialReservoirs;

struct InitialReservoir
{
    Texture2D<float4> vPosW;
    Texture2D<float4> vNormW;
    Texture2D<float4> sPosW;
    Texture2D<float4> sNormW;
    Texture2D<float4> sColor;
    Texture2D<float> random;

    

    Reservoir SetGIReservoir(float3 vPos,float3 vNorm,float3 sPos,float3 sNorm,float3 radiance,float random)
    {
        Reservoir initialReservoir = {};
        RisSample sample = {};
        sample.vPos = vPos;
        sample.vNorm = vNorm;
        sample.sPos = sPos;
        sample.sNorm = sNorm;
        sample.radiance = radiance;
        initialReservoir.z = sample;

        if(dot(initialReservoir.z.vNorm,initialReservoir.z.sPos - initialReservoir.z.vPos) < 0)
        {
            initialReservoir.z.vNorm *= -1;
        }
        if(dot(initialReservoir.z.sNorm,initialReservoir.z.vPos - initialReservoir.z.sPos) < 0)
        {
            initialReservoir.z.sNorm *= -1;
        }

        initialReservoir.weightF = random > 0.f ? 1.f / random : 0.f;
        initialReservoir.M = random > 0.f ? 1u :0u;
        initialReservoir.age = 0;

        return initialReservoir;
    }

    void execute(uint2 pixel)
    {
        Reservoir initialReservoir = SetGIReservoir(vPosW[pixel].xyz,vNormW[pixel].xyz,sPosW[pixel].xyz,sNormW[pixel].xyz,sColor[pixel].xyz,random[pixel]);
        uint linearID = ToLinearIndex(pixel);
        initialReservoirs[linearID] = initialReservoir;

        outputColor[pixel] = normalize(initialReservoir.z.vPos) * 2.f - 1.f;
    }
}

ParameterBlock<InitialReservoir> manager;

[numthreads(16,16,1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    manager.execute(dispatchThreadId.xy);
}
