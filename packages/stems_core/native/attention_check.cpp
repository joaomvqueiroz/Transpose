#include <Eigen/Dense>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <random>

int main() {
  constexpr int T = 301, S = 379, width = 32;
  std::mt19937 generator(20260928);
  std::normal_distribution<float> random(0.0f, 0.5f);
  Eigen::MatrixXf q(T, width), k(S, width), v(S, width);
  for (int i = 0; i < q.size(); ++i) q.data()[i] = random(generator);
  for (int i = 0; i < k.size(); ++i) k.data()[i] = random(generator);
  for (int i = 0; i < v.size(); ++i) v.data()[i] = random(generator);
  const float scale = std::sqrt(float(width));

  // Pinned upstream implementation, evaluated on the same input.
  Eigen::MatrixXf dots = q * k.transpose() / scale;
  Eigen::ArrayXf maxima = dots.rowwise().maxCoeff();
  Eigen::MatrixXf expanded = maxima.replicate(1, S);
  Eigen::MatrixXf softmax = (dots - expanded).array().exp().matrix();
  Eigen::VectorXf sums = softmax.rowwise().sum();
  Eigen::MatrixXf divisors = sums.replicate(1, S);
  softmax = (softmax.array() / divisors.array()).matrix();
  const Eigen::MatrixXf expected = softmax * v;

  Eigen::MatrixXf actual(T, width);
  constexpr int block = 64;
  for (int row = 0; row < T; row += block) {
    const int rows = std::min(block, T - row);
    Eigen::MatrixXf scores = q.middleRows(row, rows) * k.transpose() / scale;
    for (int r = 0; r < rows; ++r) {
      const float maximum = scores.row(r).maxCoeff();
      scores.row(r) = (scores.row(r).array() - maximum).exp().matrix();
      const float sum = scores.row(r).sum();
      scores.row(r) /= sum;
    }
    actual.middleRows(row, rows) = scores * v;
  }
  const float maximum = (expected - actual).cwiseAbs().maxCoeff();
  const float rms = std::sqrt((expected - actual).squaredNorm() / expected.size());
  std::cout << "ATTENTION_CHECK maxAbs=" << maximum << " rms=" << rms << '\n';
  return maximum <= 1e-5f && rms <= 1e-6f ? 0 : 1;
}
