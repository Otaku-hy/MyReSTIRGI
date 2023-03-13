__exported import Utils.Sampling.SampleGenerator;
__exported import ReSTIRMathFunctions;

struct RisSample
{
    float sPdf;
    float3 vPos;
    float3 vNorm;
    float3 sPos;
    float3 sNorm;
    float3 radiance;

    __init()
    {
        sPdf = 0.f;
        vPos = float3(0.f);
        vNorm = float3(0.f);
        sPos = float3(0.f);
        sNorm = float3(0.f);
        radiance = float3(0.f);
    };

};

struct Reservoir
{
    RisSample z;

    uint M;
    float weightF;                //the weight use for compute final illuminance W = Weight / (Mount * pdf)
    int age;                      //age the sample  > maxSampleAge will be discard

    __init()
    {
        z = RisSample();
        this.M = 0;
        this.weightF = 0;
    };

    [mutating] bool Update(inout SampleGenerator sg,RisSample newSample,float weight,inout float weightS)
    {
        weightS += weight;
        M ++;

        bool isUpdate = sampleNext1D(sg) * weightS <= weight;

        if(isUpdate)
        {
            z.sPos = newSample.sPos;
            z.sNorm = newSample.sNorm;
            z.radiance = newSample.radiance;
        }
        return isUpdate;
    };

    [mutating] bool Merge(inout SampleGenerator sg,Reservoir r,float pdf,inout float weightS)
    {
        float weight = r.M * max(0.f,r.weightF) * pdf;

        weightS += weight;
        M += r.M;
    
        float random = sampleNext1D(sg);
        bool isUpdate = random * weightS <= weight;
        if (isUpdate)
        {
            z.sPos = r.z.sPos;
            z.sNorm = r.z.sNorm;
            z.radiance = r.z.radiance;
            age = r.age;
        }
        return isUpdate;
    };

    [mutating] void ComputeFinalWeight(float targetPdf,float weightS)
    {
        float weight = targetPdf * M;
        this.weightF = weight > 0.f ? weightS / weight : 0.f;
    }
};
