// Copyright (c) 2019-2021 Lars Fröder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import "CHPMachoParser.h"

#import <litehook.h>

#import <Host.h>
#import <Fat.h>
#import <MachO.h>

#import <mach-o/dyld_images.h>
#import <mach-o/dyld.h>
#import <version.h>

MachO *choicy_fat_find_preferred_slice(Fat *fat)
{
	cpu_type_t cputype;
	cpu_subtype_t cpusubtype;
	if (host_get_cpu_information(&cputype, &cpusubtype) != 0) { return NULL; }
	
	MachO *candidateSlice = NULL;

	if (cputype == CPU_TYPE_ARM64) {
		if (!candidateSlice && cpusubtype == CPU_SUBTYPE_ARM64E) {
			// New arm64e ABI
			if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_14_0) {
				candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E | CPU_SUBTYPE_ARM64E_ABI_V2);
				if (!candidateSlice && kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_15_0) {
					// Old ABI slice is also allowed but only before 15.0
					candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E);
				}
			}
			// Old arm64e ABI
			else {
				candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64E);
			}
		}

		if (!candidateSlice) {
			if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_15_0) {
				// On iOS 15+ the kernels prefers ARM64_V8 to ARM64_ALL
				candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64_V8);
			}
			if (!candidateSlice) {
				candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM64_ALL);
			}
		}
	}
	else if (cputype == CPU_TYPE_ARM) {
		candidateSlice = fat_find_slice(fat, cputype, cpusubtype);
		if (!candidateSlice && cpusubtype == CPU_SUBTYPE_ARM_V7S) {
			candidateSlice = fat_find_slice(fat, cputype, CPU_SUBTYPE_ARM_V7);
		}
	}

	return candidateSlice;
}

@implementation CHPMachoParser

+ (instancetype)sharedInstance
{
	static CHPMachoParser *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^ {
		//Initialise instance
		sharedInstance = [[CHPMachoParser alloc] init];
	});
	return sharedInstance;
}

+ (BOOL)isMachoAtPath:(NSString *)path
{
	return NO;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_bundleIdentifierCache = [NSMutableDictionary new];
		_dependencyPathCache = [NSMutableDictionary new];

		task_dyld_info_data_t dyldInfo;
		uint32_t count = TASK_DYLD_INFO_COUNT;
		task_info(mach_task_self_, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
		struct dyld_all_image_infos *allImageInfos = (void *)dyldInfo.all_image_info_addr;

		_sharedCache = dsc_init_from_path_premapped(litehook_locate_dsc(), allImageInfos->sharedCacheSlide);
	}
	return self;
}

- (NSString *)resolvedDependencyPathForDependencyPath:(NSString *)dependencyPath sourceImagePath:(NSString *)sourceImagePath sourceExecutablePath:(NSString *)sourceExecutablePath
{
	@autoreleasepool {
		if (!dependencyPath) return nil;
		NSString *loaderPath = [sourceImagePath stringByDeletingLastPathComponent];
		NSString *executablePath = [sourceExecutablePath stringByDeletingLastPathComponent];

		NSString *resolvedPath = nil;

		NSString *(^resolveLoaderExecutablePaths)(NSString *) = ^NSString *(NSString *candidatePath) {
			if (!candidatePath) return nil;
			if ([[NSFileManager defaultManager] fileExistsAtPath:candidatePath]) return candidatePath;
			if (dsc_lookup_macho_by_path(_sharedCache, candidatePath.fileSystemRepresentation, NULL)) return candidatePath;
			if ([candidatePath hasPrefix:@"@loader_path"] && loaderPath) {
				NSString *loaderCandidatePath = [candidatePath stringByReplacingOccurrencesOfString:@"@loader_path" withString:loaderPath];
				if ([[NSFileManager defaultManager] fileExistsAtPath:loaderCandidatePath]) return loaderCandidatePath;
			}
			if ([candidatePath hasPrefix:@"@executable_path"] && executablePath) {
				NSString *executableCandidatePath = [candidatePath stringByReplacingOccurrencesOfString:@"@executable_path" withString:executablePath];
				if ([[NSFileManager defaultManager] fileExistsAtPath:executableCandidatePath]) return executableCandidatePath;
			}
			return nil;
		};

		if ([dependencyPath hasPrefix:@"@rpath"]) {
			NSString *(^resolveRpaths)(NSString *) = ^NSString *(NSString *binaryPath) {
				if (!binaryPath) return nil;
				__block NSString *rpathResolvedPath = nil;
				Fat *fat = NULL;
				MachO *macho = dsc_lookup_macho_by_path(_sharedCache, binaryPath.fileSystemRepresentation, NULL);
				if (!macho) {
					fat = fat_init_from_path(binaryPath.fileSystemRepresentation);
					if (fat) {
						macho = choicy_fat_find_preferred_slice(fat);
					}
				}
				if (macho) {
					macho_enumerate_rpaths(macho, ^(const char *rpathC, bool *stop) {
						if (rpathC) {
							NSString *rpath = [NSString stringWithUTF8String:rpathC];
							if (rpath) {
								rpathResolvedPath = resolveLoaderExecutablePaths([dependencyPath stringByReplacingOccurrencesOfString:@"@rpath" withString:rpath]);
								if (rpathResolvedPath) {
									*stop = true;
								}
							}
						}
					});
				}
				if (fat) {
					fat_free(fat);
				}
				return rpathResolvedPath;
			};

			resolvedPath = resolveRpaths(sourceImagePath);
			if (resolvedPath) return resolvedPath;

			// TODO: Check if this is even neccessary
			resolvedPath = resolveRpaths(sourceExecutablePath);
			if (resolvedPath) return resolvedPath;
		}
		else {
			resolvedPath = resolveLoaderExecutablePaths(dependencyPath);
			if (resolvedPath) return resolvedPath;
		}
		
		return nil;
	}
}

- (NSSet *)_dependencyPathsForMachoAtPath:(NSString *)path sourceImagePath:(NSString *)sourceImagePath sourceExecutablePath:(NSString *)sourceExecutablePath
{
	NSString *standardizedPath = path.stringByStandardizingPath;

	if (_dependencyPathCache[standardizedPath]) {
		return _dependencyPathCache[standardizedPath];
	}

	_dependencyPathCache[standardizedPath] = [NSMutableSet new];

	Fat *fat = NULL;
	MachO *macho = dsc_lookup_macho_by_path(_sharedCache, standardizedPath.fileSystemRepresentation, NULL);
	if (!macho) {
		fat = fat_init_from_path(standardizedPath.fileSystemRepresentation);
		if (fat) {
			macho = choicy_fat_find_preferred_slice(fat);
		}
	}

	if (macho) {
		macho_enumerate_dependencies(macho, ^(const char *imagePathC, uint32_t cmd, struct dylib* dylib, bool *stop){
			if (!imagePathC) return;
			NSString *imagePath = [NSString stringWithUTF8String:imagePathC].stringByStandardizingPath;
			imagePath = [self resolvedDependencyPathForDependencyPath:imagePath sourceImagePath:sourceImagePath sourceExecutablePath:sourceExecutablePath];
			if (!imagePath) return;
			if (![_dependencyPathCache[standardizedPath] containsObject:imagePath]) {
				[_dependencyPathCache[standardizedPath] addObject:imagePath];
				NSSet *nestedPaths = [self _dependencyPathsForMachoAtPath:imagePath sourceImagePath:path sourceExecutablePath:sourceExecutablePath];
				[_dependencyPathCache[standardizedPath] unionSet:nestedPaths];
			}
		});
	}

	if (fat) {
		fat_free(fat);
	}

	return _dependencyPathCache[standardizedPath];
}

- (NSSet *)dependencyPathsForMachoAtPath:(NSString *)path
{
	return [self _dependencyPathsForMachoAtPath:path sourceImagePath:nil sourceExecutablePath:path];
}

- (NSSet *)frameworkBundleIdentifiersForMachoAtPath:(NSString *)path
{
	NSString *standardizedPath = path.stringByStandardizingPath;

	if (_bundleIdentifierCache[standardizedPath]) {
		return _bundleIdentifierCache[standardizedPath];
	}

	NSMutableSet *bundleIdentifiers = [NSMutableSet set];
	NSSet *dependencyPaths = [self dependencyPathsForMachoAtPath:standardizedPath];

	void (^processDependencyPaths)(NSString *) = ^(NSString *dependencyPath){
		NSString *parentPath = [dependencyPath stringByDeletingLastPathComponent];
		if ([parentPath.pathExtension isEqualToString:@"framework"]) {
			NSString *infoPlistPath = [parentPath stringByAppendingPathComponent:@"Info.plist"];
			NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
			if (infoDictionary) {
				NSString *bundleIdentifier = infoDictionary[@"CFBundleIdentifier"];
				if (bundleIdentifier) {
					[bundleIdentifiers addObject:bundleIdentifier];
				}
			}
		}
	};

	processDependencyPaths(standardizedPath);
	for (NSString *dependencyPath in dependencyPaths) {
		processDependencyPaths(dependencyPath);
	}

	if (bundleIdentifiers) {
		_bundleIdentifierCache[standardizedPath] = bundleIdentifiers;
	}

	return bundleIdentifiers;
}

@end