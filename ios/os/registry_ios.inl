// ios/os/registry_ios.inl
#pragma once
#include <os/registry.h>

inline bool os::registry::Init() {
    return false;
}

template<typename T>
bool os::registry::ReadValue(const std::string_view&, T&) {
    return false;
}

template<typename T>
bool os::registry::WriteValue(const std::string_view&, const T&) {
    return false;
}