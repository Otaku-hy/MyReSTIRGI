__exported import Utils.Math.MathHelpers;

float Luminance(float3 color)
{
    return dot(color,float3(0.299f, 0.587f, 0.114f));
}

float TransformJacobian(float3 originPos,float3 dstPos,float3 samplePos,float3 sampleNorm)
{
    float3 offsetB = samplePos - originPos;
    float3 offsetA = samplePos - dstPos;

    float disA = dot(offsetA,offsetA);
    float disB = dot(offsetB,offsetB);

    offsetA = normalize(offsetA);
    offsetB = normalize(offsetB);

    float cosPhiA = -dot(offsetA,sampleNorm);
    float cosPhiB = -dot(offsetB,sampleNorm);

    if(cosPhiB <= 0.f) return -1;

    if(cosPhiA <=0.f || disA <= 0.f || disB <= 0.f)
        return 0.f;

    return disB * cosPhiA / (disA * cosPhiB);
}
