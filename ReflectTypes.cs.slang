import ReSTIRParams;
import GIReservoir;

RWStructuredBuffer<RisSample> initialSampleBuffer;
RWStructuredBuffer<Reservoir> initialReservoirs;
RWStructuredBuffer<Reservoir> temporalReservoirBuffer;
/*this dimension should be two times as the frameDim, in that after temporal resanple,
the final result will store in the temporal buffer, but there's a offset between
current frame and last frame,so this frame's final result should store in this
frame's temporalbuffer */

RWStructuredBuffer<Reservoir> spatialReservoirBuffer;

void main() {}
