#pragma once

// Native RootHide deliberately rejects the legacy <libroot.h> entry point.
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#include <roothide.h>
#define JBROOT_PATH(path) jbroot(path)
#define JBROOT_PATH_CSTRING(path) jbroot(path)
#define JBROOT_PATH_NSSTRING(path) jbroot(path)
#else
#include <libroot.h>
#endif
