#include <nanobind/nanobind.h>

namespace nb = nanobind;

int add(int a, int b) { return a + b; }

NB_MODULE(_ext, m) {
    m.def("add", &add, "Add two integers");
}
