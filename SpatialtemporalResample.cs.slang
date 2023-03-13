#include "Scene/SceneDefines.slangh"

__exported import Scene.shading;
import Scene.Raytracing;
import Scene.Intersection;
import Scene.RaytracingInline;
import Utils.Math.MathHelpers;
import Utils.Geometry.GeometryHelpers;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers; 
import ReSTIRHelpFunctions;
import GIReservoir;

#ifndef MAX_ITERATIONS
#define MAX_ITERATIONS 9
#endif

RWTexture2D<float3> outputColor;
RWStructuredBuffer<Reservoir> initialReservoirs;

bool TraceVisibilityRay(float3 origin,float3 norm,float3 dst)
{

    float3 dir = normalize(dst- origin);
    Ray ray = Ray(origin,dir,0.001,0.999*length(dst- origin));
    SceneRayQuery<1> sceneQuery; 
    bool V = sceneQuery.traceVisibilityRay(ray, RAY_FLAG_NONE, 0xff);
    return V;
}

struct ResampleManager
{
    static const uint kMaxIterations = MAX_ITERATIONS;
    static const float largeFloat = 1e20f;

    Texture2D<float2> motionVec;
    Texture2D<float> depth;
    Texture2D<float3> norm;

    float4x4 prevViewProj;
    float3 cameraPrePos;

    //RWStructuredBuffer<Reservoir> initialReservoirs;

    bool CompareSimilarity(uint2 this,uint2 neighbor)
    {
        if(abs(depth[this] - depth[neighbor]) > 0.1f * depth[this])
            return false;
        if(dot(norm[this],norm[neighbor]) < 0.9f)
            return false;
        return true;
    }

    void TemporalResample(uint2 pixel)
    {
        uint linearID = ToLinearIndex(pixel);

        SampleGenerator sg = SampleGenerator(pixel,params.frameCount);
        Reservoir initialSample = initialReservoirs[linearID];
 
        float4 prevClip = mul(float4(initialSample.z.vPos, 1.f), prevViewProj);
        float3 prevScreen = prevClip.xyz / prevClip.w;
        float2 prevUV = prevScreen.xy * float2(0.5f, -0.5f) + 0.5f;
        uint2 prevPixel = clamp(prevUV * params.frameDim.xy, 0, params.frameDim.xy - 1);
        
        bool isPrevValid = all(prevUV > 0.f) && all(prevUV < 1.f) ? true : false;
        float viewDepth = length(initialSample.z.vPos - gScene.camera.data.posW);
        float prevViewDepth = length(initialSample.z.vPos - cameraPrePos);
        float rand = sampleNext1D(sg);
        if (viewDepth / prevViewDepth < 0.98f && rand < 0.15f)
        {
            isPrevValid = false;
        }

        Reservoir temporalReservoir = GetTemporalReservoir(prevPixel,true);
        //temporalReservoir.M = 0;
        temporalReservoir.M = clamp(temporalReservoir.M, 0, 30);
        if(!isPrevValid || length(temporalReservoir.z.vPos - initialSample.z.vPos) > 1.f || temporalReservoir.age > 100)
        {
            temporalReservoir.M = 0;
        }

        float tp = Luminance(temporalReservoir.z.radiance);
        float wSum = temporalReservoir.M * tp * max(0.f,temporalReservoir.weightF);        

        float tpCurrent = Luminance(initialSample.z.radiance);

        temporalReservoir.Merge(sg,initialSample,tpCurrent,wSum);
       
        float tpNew = Luminance(temporalReservoir.z.radiance);
        temporalReservoir.ComputeFinalWeight(tpNew,wSum);

        //temporalReservoir.M = clamp(temporalReservoir.M, 0, 30);
        temporalReservoir.age ++;

        temporalReservoir.z.vPos = initialSample.z.vPos;
        temporalReservoir.z.vNorm = initialSample.z.vNorm;
        SetTemporalReservoir(pixel,temporalReservoir);
        
    }
    

    void SpatialResample(uint2 pixel)
    {
        Reservoir r = GetTemporalReservoir(pixel,false);
        if(!any(r.z.vNorm != 0))
        {
            SetSpatialReservoir(pixel,r);
            return;
        }

        uint sampleRadius = 30;
        SampleGenerator sg = SampleGenerator(pixel,params.frameCount);
        
        float3 positionList[10];
        float3 normalList[10];
        int MList[10];
        int nReuse = 0;
        positionList[nReuse] = r.z.vPos;
        normalList[nReuse] = r.z.vNorm;
        MList[nReuse] = r.M;
        nReuse++;

        float tp = Luminance(r.z.radiance);
        float wSum = r.M * tp * max(0.f,r.weightF);

        for(uint i=0;i<3;i++)
        {
            float2 offset = sampleNext2D(sg) * 2.f - 1.f;
            offset *= sampleRadius;
            int2 neighbor = pixel + offset;
            if(!IsValidPixel(neighbor)) continue;

            uint2 neighborPixel = clamp(neighbor, 0, params.frameDim.xy - 1) ;
            if(!CompareSimilarity(pixel,neighborPixel)) continue;
            
            Reservoir neighborReservoir = GetTemporalReservoir(neighborPixel,true);
           
            if(neighborReservoir.M <= 0) continue;

            float targetPdf = Luminance(neighborReservoir.z.radiance);
            float jacobi;
            {
                float3 offsetB = neighborReservoir.z.sPos - neighborReservoir.z.vPos;
                float3 offsetA = neighborReservoir.z.sPos - r.z.vPos;
                // Discard back-face.
                if (dot(r.z.vNorm, offsetA) <= 0.f)
                {
                    targetPdf = 0.f;
                }

                float RB2 = dot(offsetB, offsetB);
                float RA2 = dot(offsetA, offsetA);
                offsetB = normalize(offsetB);
                offsetA = normalize(offsetA);
                float cosA = dot(r.z.vNorm, offsetA);
                float cosB = dot(neighborReservoir.z.vNorm, offsetB);
                float cosPhiA = -dot(offsetA, neighborReservoir.z.sNorm);
                float cosPhiB = -dot(offsetB, neighborReservoir.z.sNorm);
                if (cosB <= 0.f || cosPhiB <= 0.f)
                {
                    continue;
                }
                if (cosA <= 0.f || cosPhiA <= 0.f || RA2 <= 0.f || RB2 <= 0.f)
                {
                    targetPdf = 0.f;
                }
                jacobi = RA2 * cosPhiB <= 0.f ? 0.f : clamp(RB2 * cosPhiA / (RA2 * cosPhiB), 0.f, 10.f);
            }
    
            targetPdf *= jacobi;
            bool V = TraceVisibilityRay(r.z.vPos,r.z.vNorm,neighborReservoir.z.sPos);
            if(!V) targetPdf = 0.f;

            r.Merge(sg,neighborReservoir,targetPdf,wSum);
            positionList[nReuse] = neighborReservoir.z.vPos;
            normalList[nReuse] = neighborReservoir.z.vNorm;
            MList[nReuse] = neighborReservoir.M;
            nReuse++;
        }

        int z =0;
        for(int i=0;i<nReuse;i++)
        {
            bool shouldTest = true;
            bool isVisible = true;
            float3 dir = normalize(r.z.sPos - positionList[i]);
            if(dot(dir,normalList[i]) < 0.f)
            {
                shouldTest = false;
                isVisible = false;
            }
            if(shouldTest)
            {
                isVisible = TraceVisibilityRay(positionList[i],normalList[i],r.z.sPos);
            }
            if(isVisible)
            {
                z += MList[i];
            }
        }

        r.M = z;
        float tpNew = Luminance(r.z.radiance);
        r.ComputeFinalWeight(tpNew,wSum);

        r.weightF = clamp(r.weightF, 0.f, 10.f);
        SetSpatialReservoir(pixel,r);

    }
}

ParameterBlock<ResampleManager> resampleManager;

[numthreads(16,16,1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    resampleManager.TemporalResample(dispatchThreadId.xy);
    resampleManager.SpatialResample(dispatchThreadId.xy);
}
