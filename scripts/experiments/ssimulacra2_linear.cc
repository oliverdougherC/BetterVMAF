// BetterVMAF experimental adapter, MIT. Upstream SSIMULACRA2 remains BSD-3-Clause.
// One pair of raw interleaved little-endian float32 linear-sRGB frames. No video pooling.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <vector>
#include "lib/extras/codec_in_out.h"
#include "lib/jxl/base/status.h"
#include "tools/no_memory_manager.h"
#include "tools/ssimulacra2.h"
#define QUIT(message) do { fprintf(stderr, "%s\n", message); return 4; } while (0)

jxl::Status Load(const char* path, size_t w, size_t h, jxl::CodecInOut* image) {
  JXL_ASSIGN_OR_RETURN(auto pixels, jxl::Image3F::Create(image->memory_manager, w, h));
  std::unique_ptr<FILE, decltype(&fclose)> file(fopen(path, "rb"), fclose);
  if (!file) return JXL_FAILURE("Input could not be opened");
  std::vector<float> row(w * 3);
  for (size_t y = 0; y < h; ++y) {
    if (fread(row.data(), sizeof(float), row.size(), file.get()) != row.size())
      return JXL_FAILURE("Truncated frame");
    for (size_t x = 0; x < w; ++x) for (size_t c = 0; c < 3; ++c) {
      float value = row[x * 3 + c];
      if (!std::isfinite(value) || value < 0 || value > 1)
        return JXL_FAILURE("Requires finite normalized SDR linear RGB");
      pixels.PlaneRow(c, y)[x] = value;
    }
  }
  if (fgetc(file.get()) != EOF) return JXL_FAILURE("Frame has trailing bytes");
  return image->SetFromImage(std::move(pixels), jxl::ColorEncoding::LinearSRGB());
}
int main(int argc, char** argv) {
  if (argc != 5) {fprintf(stderr, "Usage: ssimulacra2_linear width height ref.f32 dist.f32\n"); return 2;}
  char *we, *he; const auto w = strtoul(argv[1], &we, 10), h = strtoul(argv[2], &he, 10);
  if (*we || *he || w < 8 || h < 8 || w > 4096 || h > 2160) {fprintf(stderr, "Dimensions outside experiment bounds\n"); return 2;}
  auto* mm = jpegxl::tools::NoMemoryManager(); jxl::CodecInOut ref(mm), dis(mm);
  if (!Load(argv[3], w, h, &ref) || !Load(argv[4], w, h, &dis)) return 3;
  JXL_ASSIGN_OR_QUIT(Msssim result, ComputeSSIMULACRA2(ref.Main(), dis.Main()), "Metric failed");
  printf("%.8f\n", result.Score()); return 0;
}
