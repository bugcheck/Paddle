/* Copyright (c) 2016 PaddlePaddle Authors. All Rights Reserve.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License. */

#include "paddle/operators/clip_op.h"

#define CUDA_1D_KERNEL_LOOP(i, n)                            \
  for (int i = blockIdx.x * blockDim.x + threadIdx.x; i < n; \
       i += blockDim.x * gridDim.x)

namespace paddle {
namespace operators {

using framework::LoDTensor;

template <typename T>
__global__ void ClipGradientKernel(const int N, const T min, const T max,
                                   const T* Y, const T* dY, T* dX) {
  CUDA_1D_KERNEL_LOOP(i, N) {
    if (Y[i] > min && Y[i] < max) {
      dX[i] = dY[i];
    } else {
      dX[i] = 0;
    }
  }
}

template <typename T>
class ClipGradientOpCUDAKernel : public framework::OpKernel {
 public:
  void Compute(const framework::ExecutionContext& context) const override {
    auto max = context.Attr<float>("max");
    auto min = context.Attr<float>("min");
    auto* d_out = context.Input<LoDTensor>(framework::GradVarName("Out"));
    auto* d_x = context.Output<LoDTensor>(framework::GradVarName("X"));
    if (d_x != nullptr) {
      auto* x = context.Input<LoDTensor>("X");
      auto dims = d_x->dims();
      int64_t count = d_out->numel();
      auto d_x_data = d_x->mutable_data<T>(context.GetPlace());
      auto d_out_data = d_out->data<T>();
      auto x_data = x->data<T>();

      int N = d_x->dims()[0];
      int D = d_x->dims()[1];
      int block = 512;
      int grid = (N * D + block - 1) / block;
      ClipGradientKernel<T><<<
          grid, block, 0, reinterpret_cast<const platform::CUDADeviceContext&>(
                              context.device_context())
                              .stream()>>>(count, min, max, x_data, d_out_data,
                                           d_x_data);
    }
  }
};

}  // namespace operators
}  // namespace paddle

namespace ops = paddle::operators;
REGISTER_OP_GPU_KERNEL(clip,
                       ops::ClipKernel<paddle::platform::GPUPlace, float>);
REGISTER_OP_GPU_KERNEL(clip_grad, ops::ClipGradientOpCUDAKernel<float>);
