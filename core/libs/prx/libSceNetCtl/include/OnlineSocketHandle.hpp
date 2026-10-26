#ifndef CORE_LIBS_PRX_LIBSCENETCTL_ONLINESOCKETHANDLE_HPP
#define CORE_LIBS_PRX_LIBSCENETCTL_ONLINESOCKETHANDLE_HPP

#include <cstdint>

namespace Online::Net {

// A socket of the online bridge: a descriptor on POSIX, a SOCKET on Windows. Kept apart from
// OnlineSocket.hpp so headers can hold one without the system's socket headers.
using Handle = std::intptr_t;
constexpr Handle None = -1;

}

#endif
