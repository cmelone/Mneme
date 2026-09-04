#include <hip/hip_runtime.h>

#include <dlfcn.h>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

constexpr std::uint64_t kSizeBytes = 40ull * 1024ull * 1024ull * 1024ull;

std::string hex_addr(uintptr_t value) {
  std::ostringstream os;
  os << "0x" << std::hex << std::setw(sizeof(uintptr_t) * 2) << std::setfill('0')
     << value;
  return os.str();
}

std::string hip_error_string(hipError_t rc) {
  std::ostringstream os;
  os << hipGetErrorName(rc) << ": " << hipGetErrorString(rc);
  return os.str();
}

void hip_check(hipError_t rc, const char *what) {
  if (rc != hipSuccess) {
    std::ostringstream os;
    os << what << " failed with " << hip_error_string(rc);
    throw std::runtime_error(os.str());
  }
}

void usage(const char *argv0, const std::string &msg = "") {
  if (!msg.empty())
    std::cerr << "error: " << msg << "\n\n";
  std::cerr << "usage: " << argv0 << " [--load-library PATH]\n";
  std::exit(2);
}

std::string parse_args(int argc, char **argv) {
  std::string load_library;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--load-library") {
      if (i + 1 >= argc)
        usage(argv[0], "missing value for --load-library");
      load_library = argv[++i];
      continue;
    }
    usage(argv[0], "unknown argument: " + arg);
  }
  return load_library;
}

uintptr_t reserve_range(uintptr_t requested_va, size_t granularity) {
  hipDeviceptr_t dev_ptr = 0;
  hip_check(hipMemAddressReserve(&dev_ptr, kSizeBytes, granularity,
                                 reinterpret_cast<hipDeviceptr_t>(requested_va), 0),
            "hipMemAddressReserve");
  return reinterpret_cast<uintptr_t>(dev_ptr);
}

void maybe_load_library(const std::string &path) {
  if (path.empty())
    return;

  void *handle = dlopen(path.c_str(), RTLD_NOW | RTLD_GLOBAL);
  if (handle == nullptr) {
    std::ostringstream os;
    os << "dlopen failed for " << path << ": " << dlerror();
    throw std::runtime_error(os.str());
  }

  std::cout << "loaded_library=" << path << "\n";
}

} // namespace

int main(int argc, char **argv) {
  try {
    std::string load_library = parse_args(argc, argv);

    hip_check(hipInit(0), "hipInit");
    hip_check(hipSetDevice(0), "hipSetDevice");

    hipMemAllocationProp prop = {};
    prop.type = hipMemAllocationTypePinned;
    prop.location.type = hipMemLocationTypeDevice;
    prop.location.id = 0;

    size_t min_granularity = 0;
    hip_check(
        hipMemGetAllocationGranularity(&min_granularity, &prop,
                                       hipMemAllocationGranularityMinimum),
        "hipMemGetAllocationGranularity(minimum)");

    uintptr_t first = reserve_range(0, min_granularity);
    std::cout << "size_bytes=" << kSizeBytes << "\n";
    std::cout << "first_requested_va=0x0000000000000000\n";
    std::cout << "first_returned_va=" << hex_addr(first) << "\n";

    hip_check(hipMemAddressFree(reinterpret_cast<void *>(first), kSizeBytes),
              "hipMemAddressFree(first)");
    std::cout << "freed_first_range=true\n";

    maybe_load_library(load_library);

    uintptr_t second = reserve_range(first, min_granularity);
    std::cout << "second_requested_va=" << hex_addr(first) << "\n";
    std::cout << "second_returned_va=" << hex_addr(second) << "\n";
    std::cout << "final_exact_match=" << (second == first ? "true" : "false")
              << "\n";

    hip_check(hipMemAddressFree(reinterpret_cast<void *>(second), kSizeBytes),
              "hipMemAddressFree(second)");
    return 0;
  } catch (const std::exception &ex) {
    std::cerr << "fatal: " << ex.what() << "\n";
    return 1;
  }
}
