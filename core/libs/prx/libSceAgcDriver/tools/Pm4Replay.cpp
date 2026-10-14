#include "Pm4Analysis.hpp"
#include <cstdio>
#include <exception>
#include <filesystem>
#include <string_view>

namespace {

int usage() {
    std::fprintf(stderr, "usage: agc_pm4_replay <capture directory> [--full]\n"
                         "  decodes the submissions APS5_DUMP_SUBMITS=<directory> captured and reports each wait as released when\n"
                         "  the capture alone proves it, unreleased when no store in the capture can release it and unknown\n"
                         "  otherwise (cross-queue timing is not modelled); exit code 1 when a wait is unreleased, 2 on errors\n");
    return 2;
}

}

int main(int argc, char** argv) {
    std::filesystem::path directory;
    bool full = false;
    for (int index = 1; index < argc; ++index) {
        const std::string_view argument = argv[index];
        if (argument == "--full") full = true;
        else if (!argument.starts_with("-") && directory.empty()) directory = argument;
        else return usage();
    }
    if (directory.empty()) return usage();
    try {
        return AgcDriver::Pm4Analysis::Report(directory, full, stdout);
    } catch (const std::exception& error) {
        std::fprintf(stderr, "agc_pm4_replay: %s\n", error.what());
        return 2;
    }
}
