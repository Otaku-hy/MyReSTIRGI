#include "Scene/SceneDefines.slangh"

import ReSTIRHelpFunctions;
import Scene.shading;
import Scene.Raytracing;
import Scene.Intersection;
import Scene.RaytracingInline;
import Utils.Math.MathHelpers;
import Utils.Geometry.GeometryHelpers;
import Rendering.Lights.LightHelpers;

#include "Scene/SceneDefines.slangh"

import Scene.shading;
import Scene.Raytracing;
import Scene.Intersection;
import Scene.RaytracingInline;
import Utils.Math.MathHelpers;
import Utils.Geometry.GeometryHelpers;
import Rendering.Lights.LightHelpers;
import Rendering.Lights.EnvMapSampler;
import Rendering.Lights.EmissiveLightSampler;
import Rendering.Lights.EmissiveLightSamplerHelpers;
import ReSTIRHelpFunctions;
import PathTracer;

RWTexture2D<float3> outputColor;

RWTexture2D<float4> gVPosW;
RWTexture2D<float4> gVNormW;
RWTexture2D<float4> gVColor;
RWTexture2D<float4> gSPosW;
RWTexture2D<float4> gSNormW;
RWTexture2D<float4> gSColor;
RWTexture2D<float>  gPdf;

struct SampleInitializer
{
    Texture2D<PackedHitInfo> vbuffer_;
    uint gPRNGDimension;
 
    void TraceScatterRay(inout PathPayLoad pathState)
    {
        Ray ray= Ray(pathState.nextOrigin,pathState.direction);
        uint rayFlags = RAY_FLAG_NONE;
        TraceRay(gScene.rtAccel, rayFlags, 0xff, 0, rayTypeCount, 0, ray.toRayDesc(), pathState);
    };
    
   
    void WriteSample(RisSample sample,uint2 pixel)
    {
        if (dot(sample.sNorm, sample.vPos - sample.sPos) < 0)
        {
            sample.sNorm *= -1;
        }
        if (dot(sample.vNorm, sample.sPos - sample.vPos) < 0)
        {
            sample.vNorm *= -1;
        }
        uint index = pixel.y * params.frameDim.x + pixel.x;
        initialSampleBuffer[index] = sample;
    };
    
    void GenerateSamplePoint(inout RisSample sample,ShadingData sd,inout SampleGenerator sg,ITextureSampler lod)
    {
        let bsdf = gScene.materials.getBSDF(sd,lod);
        BSDFSample bsdfSample;
        float3 rayOrigin = sd.computeNewRayOrigin();
        PathPayLoad pathState = PathPayLoad(sg);
    
        if(!pathtracer.GenerateScatterRay(sd,bsdf, lod,rayOrigin,pathState)) return;

        pathState.thp = float3(1,1,1); // reset the thp because we only need the lo at sample point
        sample.sPdf = pathState.pdf;
        TraceScatterRay(pathState);
        pathState.isPrimaryHit = false;
        if(!pathState.isTerminated)
        {
            sample.sPos = pathState.currentPos;
            sample.sNorm = pathState.currentNorm;
    
            for(uint i=0;i<pathtracer.kMaxBounces-1 && !pathState.isTerminated;i++)
            {
                TraceScatterRay(pathState);
            }
    
            sample.radiance = pathState.radiance;
        }
        else
        {
            sample.radiance = float3(0.f);
        }

    };
    
    void GenerateVisiblePoint(uint2 pixel)
    {
        HitInfo hit = HitInfo(vbuffer_[pixel]);
    
        let lod = ExplicitLodTextureSampler(0.f);
        SampleGenerator sg = SampleGenerator(pixel,params.frameCount);

        RisSample sample = RisSample();
        PathPayLoad pathState = PathPayLoad(sg);
    
        float3 primaryRayDir = pathtracer.ComputeRayDir(pixel,params.frameDim,gScene.camera);
    
        if(hit.isValid())
        {
            ShadingData sd = pathtracer.LoadShadingData(hit,primaryRayDir,lod);
            let bsdf = gScene.materials.getBSDF(sd,lod);
 
            sample.vPos = sd.posW;
            sample.vNorm = sd.N;

            GenerateSamplePoint(sample,sd,sg,lod);
            
        }

        gVPosW[pixel] = float4(sample.vPos, 1.f);
        gVNormW[pixel] = float4(sample.vNorm, 0.f);
        gVColor[pixel] = float4(0,0,0, 1.f);
        gSPosW[pixel] = float4(sample.sPos, 1.f);
        gSNormW[pixel] = float4(sample.sNorm, 0.f);
        gSColor[pixel] = float4(sample.radiance, 1.f);
        gPdf[pixel] = sample.sPdf;

        WriteSample(sample,pixel);
    };

    void TestFunction(uint2 pixel)
    {
        HitInfo hit = HitInfo(vbuffer_[pixel]);
    
        let lod = ExplicitLodTextureSampler(0.f);
        SampleGenerator sg = SampleGenerator(pixel,params.frameCount);
        PathPayLoad pathState = PathPayLoad(sg);
    
        float3 primaryRayDir = pathtracer.ComputeRayDir(pixel,params.frameDim,gScene.camera);
        pathState.direction = primaryRayDir;
        pathState.pdf = 1;

        if(hit.isValid())
        {
            //ShadingData sd = pathtracer.LoadShadingData(hit,primaryRayDir,lod);
            //let bsdf = gScene.materials.getBSDF(sd,lod);

            pathtracer.HandleHit(pathState,hit);
            pathState.radiance = 0.f;
            pathState.isPrimaryHit = false;

            for(uint i=0;i<pathtracer.kMaxBounces && !pathState.isTerminated;i++)
            {
                TraceScatterRay(pathState);
            }

            outputColor[pixel] = pathState.radiance;
        }
        else
        {
            outputColor[pixel] = float3(0.f);
        }

    }

};

ParameterBlock<SampleInitializer> sampleInitializer;

[shader("miss")]
void ScatterMiss(inout PathPayLoad pathState)
{
    pathtracer.HandleMiss(pathState);
}

[shader("anyhit")]
void ScatterTriangleAnyHit(inout PathPayLoad pathState, BuiltInTriangleIntersectionAttributes attribs)
{
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f)) IgnoreHit();
}

[shader("closesthit")]
void ScatterTriangleClosestHit(inout PathPayLoad pathState,BuiltInTriangleIntersectionAttributes attribs)
{
    TriangleHit thit;
    thit.instanceID = getGeometryInstanceID();
    thit.primitiveIndex = PrimitiveIndex();
    thit.barycentrics = attribs.barycentrics;
    HitInfo hit = HitInfo(thit);

    pathtracer.HandleHit(pathState,hit);   
}

[shader("raygeneration")]
void RayGen()
{
    uint2 pixel = DispatchRaysIndex().xy;
    sampleInitializer.GenerateVisiblePoint(pixel);
    //sampleInitializer.TestFunction(pixel);
}
