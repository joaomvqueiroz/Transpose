#pragma once
#include <algorithm>
#include <cmath>

// Preserve the pinned demucs.cpp transposed convolution's row mapping and
// accumulation order, while materializing only a few GEMM rows at a time.
namespace transpono_stems {
template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width, bool gelu>
Eigen::Tensor3dXf conv2d_bounded(const Eigen::Tensor3dXf &x,
                                 const Eigen::Tensor4dXf &w,
                                 const Eigen::Tensor1dXf &b) {
  const int in_height = x.dimension(1), in_width = x.dimension(2);
  const int height_col = int(std::ceil((in_height + 2*pad_height -
      dilation_height*(kernel_height-1) - 1) / float(stride_height)) + 1);
  const int width_col = int(std::ceil((in_width + 2*pad_width -
      dilation_width*(kernel_width-1) - 1) / float(stride_width)) + 1);
  // Match the pinned upstream output shape, including its dilation formula.
  const int out_height = int(std::ceil(float(in_height + 2*pad_height -
      (kernel_height-1) - 1) / stride_height)) + 1;
  const int out_width = int(std::ceil(float(in_width + 2*pad_width -
      (kernel_width-1) - 1) / stride_width)) + 1;

  Eigen::Tensor4dXf w_swapped = w.shuffle(Eigen::array<int, 4>({0, 3, 2, 1}));
  Eigen::Tensor2dXf weights_tensor = w_swapped.reshape(Eigen::array<int, 2>{
      out_channels, in_channels * kernel_width * kernel_height});
  Eigen::MatrixXf weights = Eigen::Map<Eigen::MatrixXf>(
      weights_tensor.data(), weights_tensor.dimension(0), weights_tensor.dimension(1));
  Eigen::Tensor3dXf output(out_channels, out_height, out_width);
  output.setZero();
  constexpr int rows_per_block = 256;
  const int usable_rows = std::min(out_height*out_width, height_col*width_col);
  for (int first = 0; first < usable_rows; first += rows_per_block) {
    const int rows = std::min(rows_per_block, usable_rows-first);
    Eigen::MatrixXf columns = Eigen::MatrixXf::Zero(
        rows, in_channels * kernel_height * kernel_width);
    for (int c = 0; c < in_channels; ++c) {
      for (int kh = 0; kh < kernel_height; ++kh) {
        for (int kw = 0; kw < kernel_width; ++kw) {
          const int column = c*kernel_height*kernel_width + kh*kernel_width + kw;
          for (int local = 0; local < rows; ++local) {
            const int row = first+local;
            const int h = row/width_col*stride_height + kh*dilation_height-pad_height;
            const int width = row%width_col*stride_width + kw*dilation_width-pad_width;
            if (h >= 0 && h < in_height && width >= 0 && width < in_width)
              columns(local, column) = x(c, h, width);
          }
        }
      }
    }
    Eigen::MatrixXf result = columns * weights.transpose();
    for (int ch = 0; ch < out_channels; ++ch) {
      result.col(ch).array() += b(ch);
      for (int local = 0; local < rows; ++local) {
        float value = result(local, ch);
        if constexpr (gelu)
          value = 0.5f * value * (1.0f + std::erf(value / std::sqrt(2.0f)));
        const int row = first+local;
        output(ch, row/out_width, row%out_width) = value;
      }
    }
  }
  return output;
}

template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width, bool gelu>
Eigen::Tensor3dXf conv2d_tr_bounded(const Eigen::Tensor3dXf &x,
                                    const Eigen::Tensor4dXf &w,
                                    const Eigen::Tensor1dXf &b) {
  const int in_height = x.dimension(1), in_width = x.dimension(2);
  const int effective_height = kernel_height + (kernel_height - 1) * (dilation_height - 1);
  const int effective_width = kernel_width + (kernel_width - 1) * (dilation_width - 1);
  const int expanded_width = (in_width - 1) * stride_width + effective_width;
  const int out_height = (in_height - 1) * stride_height + effective_height - 2 * pad_height;
  const int out_width = expanded_width - 2 * pad_width;

  Eigen::Tensor4dXf w_swapped = w.shuffle(Eigen::array<int, 4>({1, 3, 2, 0}));
  Eigen::Tensor2dXf weights_tensor = w_swapped.reshape(Eigen::array<int, 2>{
      out_channels, in_channels * kernel_height * kernel_width});
  Eigen::MatrixXf weights = Eigen::Map<Eigen::MatrixXf>(
      weights_tensor.data(), weights_tensor.dimension(0), weights_tensor.dimension(1));
  Eigen::Tensor3dXf output(out_channels, out_height, out_width);
  output.setZero();
  constexpr int rows_per_block = 256;
  const int output_rows = out_height * out_width;
  for (int first = 0; first < output_rows; first += rows_per_block) {
    const int rows = std::min(rows_per_block, output_rows - first);
    Eigen::MatrixXf columns = Eigen::MatrixXf::Zero(
        rows, in_channels * kernel_height * kernel_width);
    for (int c = 0; c < in_channels; ++c) {
      for (int kh = 0; kh < kernel_height; ++kh) {
        for (int kw = 0; kw < kernel_width; ++kw) {
          const int column = c * kernel_height * kernel_width + kh * kernel_width + kw;
          for (int local = 0; local < rows; ++local) {
            const int row = first + local;
            // Upstream copies the first out_height*out_width GEMM rows,
            // indexed in the *expanded* grid even when padding is nonzero.
            const int expanded_h = row / expanded_width;
            const int expanded_w = row % expanded_width;
            const int source_h_numerator = expanded_h - kh * dilation_height + pad_height;
            const int source_w_numerator = expanded_w - kw * dilation_width + pad_width;
            if (source_h_numerator % stride_height || source_w_numerator % stride_width)
              continue;
            const int h = source_h_numerator / stride_height;
            const int width = source_w_numerator / stride_width;
            if (h >= 0 && h < in_height && width >= 0 && width < in_width)
              columns(local, column) = x(c, h, width);
          }
        }
      }
    }
    Eigen::MatrixXf result = columns * weights.transpose();
    for (int ch = 0; ch < out_channels; ++ch) {
      result.col(ch).array() += b(ch);
      for (int local = 0; local < rows; ++local) {
        float value = result(local, ch);
        if constexpr (gelu)
          value = 0.5f * value * (1.0f + std::erf(value / std::sqrt(2.0f)));
        const int row = first + local;
        output(ch, row / out_width, row % out_width) += value;
      }
    }
  }
  return output;
}
} // namespace transpono_stems
