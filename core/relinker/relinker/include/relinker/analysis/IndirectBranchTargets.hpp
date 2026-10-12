#ifndef RELINKER_ANALYSIS_INDIRECTBRANCHTARGETS_HPP
#define RELINKER_ANALYSIS_INDIRECTBRANCHTARGETS_HPP

#include <relinker/domain/IElfReader.hpp>
#include <vector>

namespace Relinker {

std::vector<VirtualAddress> ReadIndirectBranchTargets(const IElfReader& reader);

}

#endif
