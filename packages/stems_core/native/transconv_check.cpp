#include "conv.hpp"
#include <cmath>
#include <iostream>
#include <random>

template <int cin, int cout, int kh, int kw, int sh, int sw, int ph, int pw,
          int dh, int dw, bool gelu>
float check(std::mt19937& generator) {
  Eigen::Tensor3dXf x(cin, 7, 9);
  Eigen::Tensor4dXf w(cin, cout, kh, kw);
  Eigen::Tensor1dXf b(cout);
  std::normal_distribution<float> random(0, 0.2f);
  for (int i = 0; i < x.size(); ++i) x.data()[i] = random(generator);
  for (int i = 0; i < w.size(); ++i) w.data()[i] = random(generator);
  for (int i = 0; i < b.size(); ++i) b.data()[i] = random(generator);

  const int height = (x.dimension(1)-1)*sh + kh+(kh-1)*(dh-1)-2*ph;
  const int width = (x.dimension(2)-1)*sw + kw+(kw-1)*(dw-1)-2*pw;
  Eigen::MatrixXf columns = demucscpp::im2col_transposed<kh,kw,sh,sw,ph,pw,dh,dw>(x);
  Eigen::Tensor4dXf swapped = w.shuffle(Eigen::array<int,4>({1,3,2,0}));
  Eigen::Tensor2dXf weight_tensor = swapped.reshape(Eigen::array<int,2>{cout,cin*kh*kw});
  Eigen::MatrixXf weights = Eigen::Map<Eigen::MatrixXf>(weight_tensor.data(),cout,cin*kh*kw);
  Eigen::MatrixXf result = columns * weights.transpose();
  for (int c=0;c<cout;++c) result.col(c).array() += b(c);
  Eigen::Tensor3dXf expected(cout,height,width);
  expected.setZero();
  for (int c=0;c<cout;++c) for (int h=0;h<height;++h) for (int pos=0;pos<width;++pos) {
    float value=result(h*width+pos,c);
    if constexpr (gelu) value=0.5f*value*(1.0f+std::erf(value/std::sqrt(2.0f)));
    expected(c,h,pos)+=value;
  }
  Eigen::Tensor3dXf actual = gelu
      ? demucscpp::conv2d_tr_fused_gelu<cin,cout,kh,kw,sh,sw,ph,pw,dh,dw>(x,w,b)
      : demucscpp::conv2d_tr<cin,cout,kh,kw,sh,sw,ph,pw,dh,dw>(x,w,b);
  float maximum=0;
  for (int i=0;i<expected.size();++i)
    maximum=std::max(maximum,std::abs(expected.data()[i]-actual.data()[i]));
  return maximum;
}

template <int cin, int cout, int kh, int kw, int sh, int sw, int ph, int pw,
          int dh, int dw, bool gelu>
float check_normal(std::mt19937& generator) {
  Eigen::Tensor3dXf x(cin, 7, 9);
  Eigen::Tensor4dXf w(cout, cin, kh, kw);
  Eigen::Tensor1dXf b(cout);
  std::normal_distribution<float> random(0, 0.2f);
  for (int i=0;i<x.size();++i) x.data()[i]=random(generator);
  for (int i=0;i<w.size();++i) w.data()[i]=random(generator);
  for (int i=0;i<b.size();++i) b.data()[i]=random(generator);
  const int height = int(std::ceil(float(x.dimension(1)+2*ph-(kh-1)-1)/sh))+1;
  const int width = int(std::ceil(float(x.dimension(2)+2*pw-(kw-1)-1)/sw))+1;
  Eigen::MatrixXf columns=demucscpp::im2col<kh,kw,sh,sw,ph,pw,dh,dw>(x);
  Eigen::Tensor4dXf swapped=w.shuffle(Eigen::array<int,4>({0,3,2,1}));
  Eigen::Tensor2dXf weight_tensor=swapped.reshape(Eigen::array<int,2>{cout,cin*kh*kw});
  Eigen::MatrixXf weights=Eigen::Map<Eigen::MatrixXf>(weight_tensor.data(),cout,cin*kh*kw);
  Eigen::MatrixXf result=columns*weights.transpose();
  for (int c=0;c<cout;++c) result.col(c).array()+=b(c);
  Eigen::Tensor3dXf expected(cout,height,width);
  expected.setZero();
  for (int c=0;c<cout;++c) for (int h=0;h<height;++h) for (int pos=0;pos<width;++pos) {
    const int row=h*width+pos;
    if (row>=result.rows()) continue;
    float value=result(row,c);
    if constexpr (gelu) value=0.5f*value*(1.0f+std::erf(value/std::sqrt(2.0f)));
    expected(c,h,pos)=value;
  }
  Eigen::Tensor3dXf actual=gelu
      ? demucscpp::conv2d_fused_gelu<cin,cout,kh,kw,sh,sw,ph,pw,dh,dw>(x,w,b)
      : demucscpp::conv2d<cin,cout,kh,kw,sh,sw,ph,pw,dh,dw>(x,w,b);
  float maximum=0;
  for (int i=0;i<expected.size();++i)
    maximum=std::max(maximum,std::abs(expected.data()[i]-actual.data()[i]));
  return maximum;
}

int main() {
  std::mt19937 generator(20260928);
  float maximum=0;
  maximum=std::max(maximum,check<3,5,4,1,2,1,1,0,1,1,false>(generator));
  maximum=std::max(maximum,check<4,3,3,3,2,2,1,1,1,1,false>(generator));
  maximum=std::max(maximum,check<4,3,3,3,2,2,1,1,1,1,true>(generator));
  maximum=std::max(maximum,check_normal<3,5,3,3,1,1,1,1,1,1,false>(generator));
  maximum=std::max(maximum,check_normal<3,5,3,3,1,1,1,1,1,1,true>(generator));
  maximum=std::max(maximum,check_normal<4,3,4,1,2,1,0,0,1,1,false>(generator));
  std::cout << "CONV_CHECK maxAbs=" << maximum << '\n';
  return maximum <= 1e-5f ? 0 : 1;
}
