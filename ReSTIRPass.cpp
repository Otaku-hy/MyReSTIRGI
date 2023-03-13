/***************************************************************************
 # Copyright (c) 2015-21, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#include "ReSTIRPass.h"

const RenderPass::Info ReSTIRPass::kInfo{ "ReSTIRPass", "Insert pass description here." };

// Don't remove this. it's required for hot-reload to function properly
extern "C" FALCOR_API_EXPORT const char* getProjDir()
{
    return PROJECT_DIR;
}

extern "C" FALCOR_API_EXPORT void getPasses(Falcor::RenderPassLibrary & lib)
{
    lib.registerPass(ReSTIRPass::kInfo, ReSTIRPass::create);
}

namespace
{
    const std::string kShaderModel = "6_5";

    const std::string kReflectTypesPath = "RenderPasses/ReSTIRPass/ReflectTypes.cs.slang";
    const std::string kSampleInitialPassPath = "RenderPasses/ReSTIRPass/InitialSampleBuffer.rt.slang";
    const std::string kSpatialTemporalResamplePassPath = "RenderPasses/ReSTIRPass/SpatialtemporalResample.cs.slang";
    const std::string kFinalShadingPassPath = "RenderPasses/ReSTIRPass/FinalShading.rt.slang";
    const std::string kInitialResrvoirPassPath = "RenderPasses/ReSTIRPass/initialReservoir.cs.slang";

    const std::string kInputVBuffer = "vbuffer";
    const std::string kInputeMotionVec = "mvec";
    const std::string kInputDepthBuffer = "depth";
    const std::string kInputNormBuffer = "normW";

    const std::string kInputvPos = "vPosW";
    const std::string kInputvNorm = "vNormW";
    const std::string kInputsPos = "sPosW";
    const std::string kInputsNorm = "sNormW";
    const std::string kInputsColor = "sColor";
    const std::string kInputPdf = "random";

    ChannelList InputChannel
    {
        {kInputVBuffer,"vbuffer","input vbuffer to get visible point",false},
        {kInputeMotionVec,"mvec","input vbuffer used for temporal resample",true},
        {kInputDepthBuffer,"depth","input depthbuffer used for similarity",true,ResourceFormat::R32Float},
        {kInputNormBuffer,"norm","input normalbuffer used for similarity",true,},
        {kInputvPos,  "gVPosW",   "Visible point",                                false},
        {kInputvNorm, "gVNormW",  "Visible surface normal",                       false},
        {kInputsPos,  "gSPosW",   "Sample point",                                 false},
        {kInputsNorm, "gSNormW",  "Sample surface normal",                        false},
        {kInputsColor, "gSColor",  "Outgoing radiance at sample point in RGBA",    false},
        {kInputPdf, "gPdf",     "Random numbers used for path",                 false},
    };

    const std::string kOutputColor = "outputColor";

    ChannelList OutputChannel
    {
        {kOutputColor,"finalColor","the final output color",false,ResourceFormat::RGBA32Float},
    };

    uint32_t kMaxPayloadSizeBytes = 128u;
    uint32_t kMaxRecursionDepth = 3u;

}

ReSTIRPass::SharedPtr ReSTIRPass::create(RenderContext* pRenderContext, const Dictionary& dict)
{
    SharedPtr pPass = SharedPtr(new ReSTIRPass());
    return pPass;
}

void ReSTIRPass::compile(RenderContext* pRenderContext, const CompileData& compileData)
{
    mParams.frameDim = compileData.defaultTexDims;
    mParams.elemCount = mParams.frameDim.x * mParams.frameDim.y;
}

ReSTIRPass::ReSTIRPass() : RenderPass(kInfo)
{
    mpSampleGenerator = SampleGenerator::create(SAMPLE_GENERATOR_UNIFORM);
    auto defines = mpSampleGenerator->getDefines();
    mpReflectTypes = ComputePass::create(Program::Desc(kReflectTypesPath).setShaderModel(kShaderModel).csEntry("main"), defines);
    mpInitialReservoirPass = ComputePass::create(Program::Desc(kInitialResrvoirPassPath).setShaderModel(kShaderModel).csEntry("main"), defines);
}

Dictionary ReSTIRPass::getScriptingDictionary()
{
    return Dictionary();
}

RenderPassReflection ReSTIRPass::reflect(const CompileData& compileData)
{
    // Define the required resources here
    RenderPassReflection reflector;
    addRenderPassInputs(reflector, InputChannel);
    addRenderPassOutputs(reflector, OutputChannel);
    return reflector;
}

void ReSTIRPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    // renderData holds the requested resources
    // auto& pTexture = renderData["src"]->asTexture();
    if (!mpScene)
    {
        clearRenderPassChannels(pRenderContext, OutputChannel, renderData);
        return;
    }

    //SampleInitialPass(pRenderContext, renderData);
    InitialReservoirPass(pRenderContext, renderData);
    SpatialtemporalResamplePass(pRenderContext, renderData);
    FinalShadingPass(pRenderContext, renderData);
    //std::cout << "here";

    
    mParams.frameCount++;
    uint currentTemporal = mParams.temCurOffset;
    mParams.temCurOffset = mParams.temLastOffset;
    mParams.temLastOffset = currentTemporal;
    
    mPrevViewProj = mpScene->getCamera()->getViewProjMatrixNoJitter();
    cameraPrePos = mpScene->getCamera()->getPosition();
}

void ReSTIRPass::InitialReservoirPass(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto vars = mpInitialReservoirPass->getRootVar();

    vars["manager"]["vPosW"] = renderData[kInputvPos]->asTexture();
    vars["manager"]["vNormW"] = renderData[kInputvNorm]->asTexture();
    vars["manager"]["sPosW"] = renderData[kInputsPos]->asTexture();
    vars["manager"]["sNormW"] = renderData[kInputsNorm]->asTexture();
    vars["manager"]["sColor"] = renderData[kInputsColor]->asTexture();
    vars["manager"]["random"] = renderData[kInputPdf]->asTexture();
    vars["initialReservoirs"] = mpInitialReserovir;

    vars["PreBufferCB"]["params"].setBlob(mParams);

    vars["outputColor"] = renderData[kOutputColor]->asTexture();

    mpInitialReservoirPass->execute(pRenderContext, uint3(mParams.frameDim.x, mParams.frameDim.y, 1u));

}

void ReSTIRPass::SampleInitialPass(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto& dict = renderData.getDictionary();
    auto vars = mSampleInitialPass.mVars->getRootVar();

    vars["sampleInitializer"]["vbuffer_"] = renderData[kInputVBuffer]->asTexture();

    vars["initialSampleBuffer"] = mpSampleBuffer;
    vars["temporalReservoirBuffer"] = mpTemporalReservoir;
    vars["spatialReservoirBuffer"] = mpSpatialReservoir;
    vars["PreBufferCB"]["params"].setBlob(mParams);
    vars["outputColor"] = renderData[kOutputColor]->asTexture();
    vars["gScene"] = mpScene->getParameterBlock();

    if (mpEnvMapSampler) mpEnvMapSampler->setShaderData(vars["pathtracer"]["envMapSampler"]);
    if (mpEmissiveSampler) mpEmissiveSampler->setShaderData(vars["pathtracer"]["emissiveSampler"]);

    vars["sampleInitializer"]["gPRNGDimension"] = dict.keyExists(kRenderPassPRNGDimension) ? dict[kRenderPassPRNGDimension] : 0u;
    //mpScene->raytrace(pRenderContext, mSampleInitialPass.mProgram.get(), mSampleInitialPass.mVars, uint3(mParams.frameDim.x, mParams.frameDim.y, 1u));
}

void ReSTIRPass::SpatialtemporalResamplePass(RenderContext* pRenderContext, const RenderData& renderData)
{
    FALCOR_PROFILE("ReStir::resampling");

    auto vars = mSpatialtemporalResamplePass->getRootVar();
    vars["resampleManager"]["motionVec"] = renderData[kInputeMotionVec]->asTexture();
    vars["resampleManager"]["depth"] = renderData[kInputDepthBuffer]->asTexture();
    vars["resampleManager"]["norm"] = renderData[kInputNormBuffer]->asTexture();
    vars["resampleManager"]["prevViewProj"] = mPrevViewProj;
    vars["resampleManager"]["cameraPrePos"] = cameraPrePos;
    vars["initialReservoirs"] = mpInitialReserovir;

    vars["initialSampleBuffer"] = mpSampleBuffer;
    vars["temporalReservoirBuffer"] = mpTemporalReservoir;
    vars["spatialReservoirBuffer"] = mpSpatialReservoir;
    vars["outputColor"] = renderData[kOutputColor]->asTexture();
    vars["PreBufferCB"]["params"].setBlob(mParams);
    vars["gScene"] = mpScene->getParameterBlock();

    mSpatialtemporalResamplePass->addDefine("MAX_ITERATIONS", "8");
    
    mSpatialtemporalResamplePass->execute(pRenderContext, uint3(mParams.frameDim.x, mParams.frameDim.y, 1u));
}

void ReSTIRPass::FinalShadingPass(RenderContext* pRenderContext, const RenderData& renderdata)
{
    auto vars = mFinalShadingPass.mVars->getRootVar();
    vars["vbuffer"] = renderdata[kInputVBuffer]->asTexture();

    //vars["initialSampleBuffer"] = mpSampleBuffer;
    vars["temporalReservoirBuffer"] = mpTemporalReservoir;
    vars["spatialReservoirBuffer"] = mpSpatialReservoir;

    vars["outputColor"] = renderdata[kOutputColor]->asTexture();
    vars["PreBufferCB"]["params"].setBlob(mParams);
    vars["gScene"] = mpScene->getParameterBlock();

    if (mpEnvMapSampler) mpEnvMapSampler->setShaderData(vars["pathtracer"]["envMapSampler"]);
    if (mpEmissiveSampler) mpEmissiveSampler->setShaderData(vars["pathtracer"]["emissiveSampler"]);

    mpScene->raytrace(pRenderContext, mFinalShadingPass.mProgram.get(), mFinalShadingPass.mVars, uint3(mParams.frameDim.x, mParams.frameDim.y, 1u));
}

void ReSTIRPass::setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene)
{
    mpScene = pScene;
    mParams.frameCount = 0;

    mSampleInitialPass.mProgram = nullptr;
    mSampleInitialPass.mBindTable = nullptr;
    mSampleInitialPass.mVars = nullptr;

    if (mpScene->getRenderSettings().useEmissiveLights)
    {
        mpScene->getLightCollection(pRenderContext);
    }

    if (mpScene->useEnvLight())
    {
        mpEnvMapSampler = EnvMapSampler::create(pRenderContext, mpScene->getEnvMap());
    }
    if (mpScene->useEmissiveLights())
    {
        mpEmissiveSampler = EmissiveUniformSampler::create(pRenderContext, mpScene);
    }

    InitSampleBuffer();
    //InitSampleInitialPass();
    InitSpatialtemporalResamplePass();
    InitFinalShadingPass();
}

void ReSTIRPass::renderUI(Gui::Widgets& widget)
{
}

void ReSTIRPass::InitSampleBuffer()
{
    if (!mpSampleBuffer)
    {
        uint32_t sumSampleCount = mParams.frameDim.x * mParams.frameDim.y;
        std::cout << mParams.frameDim.x << " " << mParams.frameDim.y;
        mpSampleBuffer = Buffer::createStructured(mpReflectTypes["initialSampleBuffer"], sumSampleCount, Resource::BindFlags::ShaderResource | Resource::BindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false);
    }
    if (!mpTemporalReservoir)
    {
        uint32_t sumTemporalReservoir = 2 * mParams.frameDim.x * mParams.frameDim.y;
        mpTemporalReservoir = Buffer::createStructured(mpReflectTypes["temporalReservoirBuffer"], sumTemporalReservoir, Resource::BindFlags::ShaderResource | Resource::BindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false);
    }
    if (!mpSpatialReservoir)
    {
        uint32_t sumSpatialReservoir = 2 * mParams.frameDim.x * mParams.frameDim.y;
        mpSpatialReservoir = Buffer::createStructured(mpReflectTypes["spatialReservoirBuffer"], sumSpatialReservoir, Resource::BindFlags::ShaderResource | Resource::BindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false);
    }
    if(!mpInitialReserovir)
    {
        uint32_t sumSampleCount = mParams.frameDim.x * mParams.frameDim.y;
        mpInitialReserovir = Buffer::createStructured(mpReflectTypes["initialReservoirs"], sumSampleCount, Resource::BindFlags::ShaderResource | Resource::BindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false);
    }
}

void ReSTIRPass::InitSampleInitialPass()
{
    RtProgram::Desc desc;
    desc.addShaderLibrary(kSampleInitialPassPath);
    desc.setShaderModel(kShaderModel);
    desc.addTypeConformances(mpScene->getTypeConformances());
    desc.setMaxAttributeSize(mpScene->getRaytracingMaxAttributeSize());
    desc.setMaxPayloadSize(kMaxPayloadSizeBytes);
    desc.setMaxTraceRecursionDepth(kMaxRecursionDepth);

    mSampleInitialPass.mBindTable = RtBindingTable::create(1, 1, mpScene->getGeometryCount());
    mSampleInitialPass.mBindTable->setRayGen(desc.addRayGen("RayGen"));
    mSampleInitialPass.mBindTable->setMiss(0, desc.addMiss("ScatterMiss"));
    mSampleInitialPass.mBindTable->setHitGroup(0, mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh), desc.addHitGroup("ScatterTriangleClosestHit", "ScatterTriangleAnyHit"));

    auto defines = mpScene->getSceneDefines();
    defines.add(mpSampleGenerator->getDefines());
    defines.add("USE_ANALYTIC_LIGHTS", mpScene && mpScene->useAnalyticLights() ? "1" : "0");
    defines.add("USE_EMISSIVE_LIGHTS", mpScene && mpScene->useEmissiveLights() ? "1" : "0");
    defines.add("USE_ENV_LIGHT", mpScene && mpScene->useEnvLight() ? "1" : "0");
    defines.add("PATH_MAX_BOUNCES", std::to_string(kMaxRecursionDepth));
    if (mpEmissiveSampler) defines.add(mpEmissiveSampler->getDefines());
    mSampleInitialPass.mProgram = RtProgram::create(desc, defines);

    mSampleInitialPass.mVars = RtProgramVars::create(mSampleInitialPass.mProgram, mSampleInitialPass.mBindTable);
}

void ReSTIRPass::InitSpatialtemporalResamplePass()
{
    auto defines = mpSampleGenerator->getDefines();
    defines.add(mpScene->getSceneDefines());
    mSpatialtemporalResamplePass = ComputePass::create(Program::Desc(kSpatialTemporalResamplePassPath).setShaderModel(kShaderModel).csEntry("main").addTypeConformances(mpScene->getTypeConformances()), defines);
}

void ReSTIRPass::InitFinalShadingPass()
{
    RtProgram::Desc desc;
    desc.addShaderLibrary(kFinalShadingPassPath);
    desc.setShaderModel(kShaderModel);
    desc.addTypeConformances(mpScene->getTypeConformances());
    desc.setMaxAttributeSize(mpScene->getRaytracingMaxAttributeSize());
    desc.setMaxPayloadSize(kMaxPayloadSizeBytes);
    desc.setMaxTraceRecursionDepth(kMaxRecursionDepth);

    mFinalShadingPass.mBindTable = RtBindingTable::create(1, 1, mpScene->getGeometryCount());
    mFinalShadingPass.mBindTable->setRayGen(desc.addRayGen("RayGen"));
    mFinalShadingPass.mBindTable->setMiss(0, desc.addMiss("ScatterMiss"));
    mFinalShadingPass.mBindTable->setHitGroup(0, mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh), desc.addHitGroup("ScatterTriangleClosestHit", "ScatterTriangleAnyHit"));

    auto defines = mpScene->getSceneDefines();
    defines.add(mpSampleGenerator->getDefines());
    if (mpEmissiveSampler) defines.add(mpEmissiveSampler->getDefines());
    defines.add("USE_ANALYTIC_LIGHTS", mpScene && mpScene->useAnalyticLights() ? "1" : "0");
    defines.add("USE_EMISSIVE_LIGHTS", mpScene && mpScene->useEmissiveLights() ? "1" : "0");
    defines.add("USE_ENV_LIGHT", mpScene && mpScene->useEnvLight() ? "1" : "0");
    defines.add("PATH_MAX_BOUNCES", std::to_string(kMaxRecursionDepth));
    mFinalShadingPass.mProgram = RtProgram::create(desc, defines);

    mFinalShadingPass.mVars = RtProgramVars::create(mFinalShadingPass.mProgram, mFinalShadingPass.mBindTable);
}
