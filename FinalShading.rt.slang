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
import PathTracer;
import GIReservoir;

Texture2D<PackedHitInfo> vbuffer;
RWTexture2D<float3> outputColor;

#ifndef USE_EMISSIVE_LIGHTS
#define USE_EMISSIVE_LIGHTS 1
#endif

#ifndef USE_ANALYTIC_LIGHTS
#define USE_ANALYTIC_LIGHTS 1
#endif

static const bool kUseEmissiveLights = USE_EMISSIVE_LIGHTS;
static const bool kUseAnalyticLights = USE_ANALYTIC_LIGHTS;

float3 FinalShading(uint2 pixel)
{
    HitInfo hit = HitInfo(vbuffer[pixel]);
    if(!hit.isValid()) return float3(0.f);

    let lod = ExplicitLodTextureSampler(0.f);

    float3 rayDir = gScene.camera.computeRayPinhole(pixel,params.frameDim).dir;
    ShadingData sd = pathtracer.LoadShadingData(hit,rayDir,lod);

    let bsdf = gScene.materials.getBSDF(sd,lod);

    SampleGenerator sg = SampleGenerator(pixel,params.frameCount);

    uint reservoirID = params.frameDim.x * params.frameDim.y * params.temCurOffset + pixel.y * params.frameDim.x + pixel.x;
    Reservoir r = spatialReservoirBuffer[reservoirID];
    RisSample s = r.z;

    float3 color = float3(0.f);

    float3 wo = normalize(s.sPos - s.vPos);
    color += bsdf.eval(sd,wo,sg) * s.radiance * max(0.f,r.weightF);
    
    //color += pathtracer.EvalDirectLight(hit,sd,sg);

    return color;
}

[shader("miss")]
void ScatterMiss(inout PathPayLoad rayData)
{
}

[shader("anyhit")]
void ScatterTriangleAnyHit(inout PathPayLoad rayData, BuiltInTriangleIntersectionAttributes attribs)
{
}

[shader("closesthit")]
void ScatterTriangleClosestHit(inout PathPayLoad rayData,BuiltInTriangleIntersectionAttributes attribs)
{
}

[shader("raygeneration")]
void RayGen()
{
    uint2 pixel = DispatchRaysIndex().xy;
    float3 color = FinalShading(pixel);
    outputColor[pixel] = color;
}
