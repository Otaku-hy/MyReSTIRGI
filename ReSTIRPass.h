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
#pragma once
#include "Falcor.h"
#include "Utils/Sampling/SampleGenerator.h"
 //#include "Rendering/Lights/LightBVHSampler.h"
 //#include "Rendering/Lights/EmissivePowerSampler.h"
#include "Rendering/Lights/EmissiveUniformSampler.h"
#include "Rendering/Lights/EnvMapSampler.h"
#include "ReSTIRParams.slang"

using namespace Falcor;

class ReSTIRPass : public RenderPass
{
public:
    using SharedPtr = std::shared_ptr<ReSTIRPass>;

    static const Info kInfo;

    /** Create a new render pass object.
        \param[in] pRenderContext The render context.
        \param[in] dict Dictionary of serialized parameters.
        \return A new object, or an exception is thrown if creation failed.
    */
    static SharedPtr create(RenderContext* pRenderContext = nullptr, const Dictionary& dict = {});

    virtual Dictionary getScriptingDictionary() override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    ReSTIRPass();

    void InitSampleBuffer();
    void InitSampleInitialPass();
    void InitSpatialtemporalResamplePass();
    void InitFinalShadingPass();

    void InitialReservoirPass(RenderContext* pRenderContext, const RenderData& renderData);
    void SampleInitialPass(RenderContext* pRenderContext, const RenderData& renderData);
    void SpatialtemporalResamplePass(RenderContext* pRenderContext, const RenderData& renderData);
    void FinalShadingPass(RenderContext* pRenderContext, const RenderData& renderdata);
    //void SetSamplers(RenderContext* pRenderContext);

    RenderingRuntimeParams mParams;

    SampleGenerator::SharedPtr mpSampleGenerator;
    EnvMapSampler::SharedPtr mpEnvMapSampler;
    EmissiveLightSampler::SharedPtr mpEmissiveSampler;

    ComputePass::SharedPtr mpInitialReservoirPass;
    ComputePass::SharedPtr mpReflectTypes;
    ComputePass::SharedPtr mSpatialtemporalResamplePass;

    Buffer::SharedPtr mpSampleBuffer;
    Buffer::SharedPtr mpTemporalReservoir;
    Buffer::SharedPtr mpSpatialReservoir;
    Buffer::SharedPtr mpInitialReserovir;

    Scene::SharedPtr mpScene;

    struct RtPass
    {
        RtProgram::SharedPtr mProgram;
        RtBindingTable::SharedPtr mBindTable;
        RtProgramVars::SharedPtr mVars;
    };

    RtPass mSampleInitialPass;
    RtPass mFinalShadingPass;

    glm::float4x4 mPrevViewProj;
    float3 cameraPrePos;
};
