/*
 * Created by Marcos Luciano
 * https://www.github.com/marcoslucianops
 */

#include <stdint.h>

__global__ void gpuYoloLayer_nc(const float* input, float* output, int* count, const uint netWidth, const uint netHeight,
    const uint gridSizeX, const uint gridSizeY, const uint numOutputClasses, const uint numBBoxes, const float scaleXY,
    const float* anchors, const int* mask)
{
  uint x_id = blockIdx.x * blockDim.x + threadIdx.x;
  uint y_id = blockIdx.y * blockDim.y + threadIdx.y;
  uint z_id = blockIdx.z * blockDim.z + threadIdx.z;

  if (x_id >= gridSizeX || y_id >= gridSizeY || z_id >= numBBoxes)
    return;

  const int numGridCells = gridSizeX * gridSizeY;
  const int bbindex = y_id * gridSizeX + x_id;

  const float objectness = input[bbindex + numGridCells * (z_id * (5 + numOutputClasses) + 4)];

  const float alpha = scaleXY;
  const float beta = -0.5 * (scaleXY - 1);

  float xc = (input[bbindex + numGridCells * (z_id * (5 + numOutputClasses) + 0)] * alpha + beta + x_id) * netWidth /
      gridSizeX;

  float yc = (input[bbindex + numGridCells * (z_id * (5 + numOutputClasses) + 1)] * alpha + beta + y_id) * netHeight /
      gridSizeY;

  float w = __powf(input[bbindex + numGridCells * (z_id * (5 + numOutputClasses) + 2)] * 2, 2) * anchors[mask[z_id] * 2];

  float h = __powf(input[bbindex + numGridCells * (z_id * (5 + numOutputClasses) + 3)] * 2, 2) * anchors[mask[z_id] * 2 + 1];

  float maxProb = 0.0f;
  int maxIndex = -1;

  for (uint i = 0; i < numOutputClasses; ++i) {
    float prob = input[bbindex + numGridCells * (z_id * (5 + numOutputClasses) + (5 + i))];
    if (prob > maxProb) {
      maxProb = prob;
      maxIndex = i;
    }
  }

  int _count = (int)atomicAdd(count, 1);

  output[_count * 7 + 0] = xc;
  output[_count * 7 + 1] = yc;
  output[_count * 7 + 2] = w;
  output[_count * 7 + 3] = h;
  output[_count * 7 + 4] = maxProb;
  output[_count * 7 + 5] = maxIndex;
  output[_count * 7 + 6] = objectness;
}

cudaError_t cudaYoloLayer_nc(const void* input, void* output, void* count, const uint& batchSize, uint64_t& inputSize,
    uint64_t& outputSize, const uint& netWidth, const uint& netHeight, const uint& gridSizeX, const uint& gridSizeY,
    const uint& numOutputClasses, const uint& numBBoxes, const float& scaleXY, const void* anchors, const void* mask,
    cudaStream_t stream);

cudaError_t cudaYoloLayer_nc(const void* input, void* output, void* count, const uint& batchSize, uint64_t& inputSize,
    uint64_t& outputSize, const uint& netWidth, const uint& netHeight, const uint& gridSizeX, const uint& gridSizeY,
    const uint& numOutputClasses, const uint& numBBoxes, const float& scaleXY, const void* anchors, const void* mask,
    cudaStream_t stream)
{
  dim3 threads_per_block(16, 16, 4);
  dim3 number_of_blocks((gridSizeX / threads_per_block.x) + 1, (gridSizeY / threads_per_block.y) + 1,
      (numBBoxes / threads_per_block.z) + 1);

  for (unsigned int batch = 0; batch < batchSize; ++batch) {
    gpuYoloLayer_nc<<<number_of_blocks, threads_per_block, 0, stream>>>(
        reinterpret_cast<const float*> (input) + (batch * inputSize),
        reinterpret_cast<float*> (output) + (batch * 7 * outputSize),
        reinterpret_cast<int*> (count) + (batch),
        netWidth, netHeight, gridSizeX, gridSizeY, numOutputClasses, numBBoxes, scaleXY,
        reinterpret_cast<const float*> (anchors), reinterpret_cast<const int*> (mask));
  }
  return cudaGetLastError();
}
