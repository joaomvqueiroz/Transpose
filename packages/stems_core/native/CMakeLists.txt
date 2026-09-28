cmake_minimum_required(VERSION 3.22.1)
project(transpono_stems LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
if(NOT EXISTS "${DEMUCS_SOURCE}/src/model.hpp" OR NOT EXISTS "${DEMUCS_SOURCE}/vendor/eigen/Eigen/Core")
  message(FATAL_ERROR "Run tool/setup_stems.ps1 to obtain the pinned Demucs/Eigen sources")
endif()
set(GENERATED_ROOT "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_ROOT}")
file(GLOB DEMUCS_UPSTREAM "${DEMUCS_SOURCE}/src/*.cpp" "${DEMUCS_SOURCE}/src/*.hpp")
foreach(UPSTREAM_FILE IN LISTS DEMUCS_UPSTREAM)
  get_filename_component(SOURCE_NAME "${UPSTREAM_FILE}" NAME)
  configure_file("${UPSTREAM_FILE}" "${GENERATED_ROOT}/${SOURCE_NAME}" COPYONLY)
endforeach()
# Keep the pinned upstream tree untouched. The exact source replacement fails at
# configure time if upstream changes, so the bounded attention remains reviewable.
file(READ "${DEMUCS_SOURCE}/src/layers.cpp" LAYERS_SOURCE)
string(REPLACE "\r\n" "\n" LAYERS_SOURCE "${LAYERS_SOURCE}")
set(ATTENTION_ORIGINAL [=[        // Compute the dot product of Q_head and K_head
        Eigen::MatrixXf dot_product =
            Q_head * K_head.transpose() / std::sqrt((float)head_split);

        // Apply softmax to the dot product
        Eigen::ArrayXf max_vals = dot_product.rowwise().maxCoeff();
        Eigen::MatrixXf max_vals_expanded = max_vals.replicate(1, S);
        Eigen::MatrixXf softmax_scores =
            (dot_product - max_vals_expanded).array().exp().matrix();
        Eigen::VectorXf row_sums = softmax_scores.rowwise().sum();
        Eigen::MatrixXf divisor = row_sums.replicate(1, S);
        softmax_scores = (softmax_scores.array() / divisor.array()).matrix();

        Eigen::MatrixXf cross_attn_head = softmax_scores * V_head;
        cross_attn_out.block(0, h * head_split, T, head_split) =
            cross_attn_head;]=])
set(ATTENTION_BOUNDED [=[        // Each query still attends to every key. Bound only the temporary
        // score storage; normalize each row in place before multiplying by V.
        constexpr int query_block = 64;
        const float scale = std::sqrt((float)head_split);
        for (int row = 0; row < T; row += query_block)
        {
            const int rows = std::min(query_block, T - row);
            Eigen::MatrixXf scores =
                Q_head.middleRows(row, rows) * K_head.transpose() / scale;
            for (int r = 0; r < rows; ++r)
            {
                const float maximum = scores.row(r).maxCoeff();
                scores.row(r) = (scores.row(r).array() - maximum).exp().matrix();
                const float sum = scores.row(r).sum();
                scores.row(r) /= sum;
            }
            cross_attn_out.block(row, h * head_split, rows, head_split) =
                scores * V_head;
        }]=])
string(FIND "${LAYERS_SOURCE}" "${ATTENTION_ORIGINAL}" ATTENTION_OFFSET)
if(ATTENTION_OFFSET LESS 0)
  message(FATAL_ERROR "Pinned Demucs attention implementation changed; review bounded replacement")
endif()
string(LENGTH "${ATTENTION_ORIGINAL}" ATTENTION_LENGTH)
math(EXPR ATTENTION_AFTER "${ATTENTION_OFFSET} + ${ATTENTION_LENGTH}")
string(SUBSTRING "${LAYERS_SOURCE}" ${ATTENTION_AFTER} -1 ATTENTION_REST)
string(FIND "${ATTENTION_REST}" "${ATTENTION_ORIGINAL}" ATTENTION_DUPLICATE)
if(NOT ATTENTION_DUPLICATE LESS 0)
  message(FATAL_ERROR "Duplicate Demucs attention implementation; review bounded replacement")
endif()
string(REPLACE "${ATTENTION_ORIGINAL}" "${ATTENTION_BOUNDED}" LAYERS_SOURCE "${LAYERS_SOURCE}")
file(READ "${DEMUCS_SOURCE}/LICENSE" DEMUCS_LICENSE)
set(GENERATED_LAYERS "${CMAKE_CURRENT_BINARY_DIR}/generated/layers.cpp")
file(WRITE "${GENERATED_LAYERS}" "/* Derived from demucs.cpp, licensed as follows:\n${DEMUCS_LICENSE}\n*/\n${LAYERS_SOURCE}")

# conv.hpp is included by generated/layers.cpp. Preserve the exact upstream
# header except for its two transposed-convolution bodies.
file(READ "${DEMUCS_SOURCE}/src/conv.hpp" CONV_SOURCE)
string(REPLACE "\r\n" "\n" CONV_SOURCE "${CONV_SOURCE}")
string(SHA256 CONV_SHA256 "${CONV_SOURCE}")
if(NOT CONV_SHA256 STREQUAL "28eaf9ffcc8c4b02a8bdf185267a10f5f5b2f9b5fc64be80b5ac79063191043f")
  message(FATAL_ERROR "Pinned Demucs convolution header changed; review bounded replacement")
endif()
set(CONV_START [=[template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d_tr(]=])
set(NORMAL_START [=[template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d(]=])
set(NORMAL_NEXT [=[template <int in_channels, int out_channels, int kernel_size, int stride,
          int pad, int dilation>
Eigen::Tensor3dXf conv1d(]=])
set(CONV_NEXT [=[template <int in_channels, int out_channels, int kernel_size, int stride,
          int pad, int dilation>
Eigen::Tensor3dXf conv1d_tr(]=])
string(FIND "${CONV_SOURCE}" "${CONV_START}" CONV_FIRST)
string(FIND "${CONV_SOURCE}" "${CONV_NEXT}" CONV_LAST)
string(FIND "${CONV_SOURCE}" "${NORMAL_START}" NORMAL_FIRST)
string(FIND "${CONV_SOURCE}" "${NORMAL_NEXT}" NORMAL_LAST)
if(NORMAL_FIRST LESS 0 OR NORMAL_LAST LESS NORMAL_FIRST OR
   CONV_FIRST LESS NORMAL_LAST OR CONV_LAST LESS CONV_FIRST)
  message(FATAL_ERROR "Cannot locate pinned Demucs transposed convolutions")
endif()
string(SUBSTRING "${CONV_SOURCE}" 0 ${NORMAL_FIRST} CONV_PREFIX)
math(EXPR NORMAL_MIDDLE_LENGTH "${CONV_FIRST} - ${NORMAL_LAST}")
string(SUBSTRING "${CONV_SOURCE}" ${NORMAL_LAST} ${NORMAL_MIDDLE_LENGTH} CONV_MIDDLE)
string(SUBSTRING "${CONV_SOURCE}" ${CONV_LAST} -1 CONV_SUFFIX)
set(NORMAL_WRAPPERS [=[template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d(const Eigen::Tensor3dXf &x,
                         const Eigen::Tensor4dXf &w,
                         const Eigen::Tensor1dXf &b)
{
    return transpono_stems::conv2d_bounded<
        in_channels, out_channels, kernel_height, kernel_width, stride_height,
        stride_width, pad_height, pad_width, dilation_height, dilation_width,
        false>(x, w, b);
}

template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d_fused_gelu(const Eigen::Tensor3dXf &x,
                                    const Eigen::Tensor4dXf &w,
                                    const Eigen::Tensor1dXf &b)
{
    return transpono_stems::conv2d_bounded<
        in_channels, out_channels, kernel_height, kernel_width, stride_height,
        stride_width, pad_height, pad_width, dilation_height, dilation_width,
        true>(x, w, b);
}

]=])
set(CONV_WRAPPERS [=[template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d_tr(const Eigen::Tensor3dXf &x,
                            const Eigen::Tensor4dXf &w,
                            const Eigen::Tensor1dXf &b)
{
    return transpono_stems::conv2d_tr_bounded<
        in_channels, out_channels, kernel_height, kernel_width, stride_height,
        stride_width, pad_height, pad_width, dilation_height, dilation_width,
        false>(x, w, b);
}

template <int in_channels, int out_channels, int kernel_height,
          int kernel_width, int stride_height, int stride_width, int pad_height,
          int pad_width, int dilation_height, int dilation_width>
Eigen::Tensor3dXf conv2d_tr_fused_gelu(const Eigen::Tensor3dXf &x,
                                       const Eigen::Tensor4dXf &w,
                                       const Eigen::Tensor1dXf &b)
{
    return transpono_stems::conv2d_tr_bounded<
        in_channels, out_channels, kernel_height, kernel_width, stride_height,
        stride_width, pad_height, pad_width, dilation_height, dilation_width,
        true>(x, w, b);
}

]=])
set(GENERATED_CONV "${CMAKE_CURRENT_BINARY_DIR}/generated/conv.hpp")
file(WRITE "${GENERATED_CONV}" "/* Derived from demucs.cpp, licensed as follows:\n${DEMUCS_LICENSE}\n*/\n${CONV_PREFIX}${NORMAL_WRAPPERS}${CONV_MIDDLE}${CONV_WRAPPERS}${CONV_SUFFIX}")
file(READ "${GENERATED_CONV}" CONV_GENERATED)
string(REPLACE "namespace demucscpp\n{" "#include \"bounded_conv.hpp\"\n\nnamespace demucscpp\n{" CONV_GENERATED "${CONV_GENERATED}")
file(WRITE "${GENERATED_CONV}" "${CONV_GENERATED}")
file(GLOB DEMUCS_FILES "${GENERATED_ROOT}/*.cpp")
add_library(demucs_inference STATIC ${DEMUCS_FILES})
set_target_properties(demucs_inference PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(demucs_inference PUBLIC "${GENERATED_ROOT}" "${DEMUCS_SOURCE}/vendor/eigen")
target_include_directories(demucs_inference PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(demucs_inference PRIVATE EIGEN_MPL2_ONLY NDEBUG)
target_compile_options(demucs_inference PRIVATE -O2 -fvisibility=hidden)
if(TRANSPONO_STEMS_ANDROID)
  add_library(transpono_stems SHARED stems_jni.cpp)
  target_compile_definitions(transpono_stems PRIVATE TRANSPONO_DEMUCS=1)
  target_link_libraries(transpono_stems PRIVATE demucs_inference dl)
  target_compile_options(transpono_stems PRIVATE -O2 -fvisibility=hidden)
else()
  add_executable(transpono_stems_probe probe.cpp)
  target_link_libraries(transpono_stems_probe PRIVATE demucs_inference)
  target_compile_options(transpono_stems_probe PRIVATE -O2)
  add_executable(transpono_attention_check attention_check.cpp)
  target_include_directories(transpono_attention_check PRIVATE "${DEMUCS_SOURCE}/vendor/eigen")
  target_compile_definitions(transpono_attention_check PRIVATE EIGEN_MPL2_ONLY NDEBUG)
  target_compile_options(transpono_attention_check PRIVATE -O2)
  add_executable(transpono_transconv_check transconv_check.cpp)
  target_include_directories(transpono_transconv_check PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}/generated" "${CMAKE_CURRENT_SOURCE_DIR}"
    "${DEMUCS_SOURCE}/vendor/eigen")
  target_compile_definitions(transpono_transconv_check PRIVATE EIGEN_MPL2_ONLY NDEBUG)
  target_compile_options(transpono_transconv_check PRIVATE -O2)
endif()
