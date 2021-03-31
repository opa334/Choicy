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
#import <stdio.h>
#import <string.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <unistd.h>
#import <mach-o/arch.h>
#import <sys/types.h>
#import <sys/sysctl.h>

#ifdef __LP64__
#define segment_command_universal segment_command_64
#define mach_header_universal mach_header_64
#define MH_MAGIC_UNIVERSAL MH_MAGIC_64
#define MH_CIGAM_UNIVERSAL MH_CIGAM_64
#else
#define segment_command_universal segment_command
#define mach_header_universal mach_header
#define MH_MAGIC_UNIVERSAL MH_MAGIC
#define MH_CIGAM_UNIVERSAL MH_CIGAM
#endif

#define SWAP32(x) ((((x) & 0xff000000) >> 24) | (((x) & 0xff0000) >> 8) | (((x) & 0xff00) << 8) | (((x) & 0xff) << 24))

struct dyld_cache_header
{
    char magic[16];
    uint32_t mappingOffset;
    uint32_t mappingCount;
    uint32_t imagesOffset;
    uint32_t imagesCount;
    uint64_t dyldBaseAddress;
    uint64_t codeSignOffset;
};

struct shared_file_mapping {
    uint64_t address;
    uint64_t size;
    uint64_t file_offset;
    uint32_t max_prot;
    uint32_t init_prot;
};

struct dyld_cache_image_info
{
    uint64_t address;
    uint64_t modTime;
    uint64_t inode;
    uint32_t pathFileOffset;
    uint32_t pad;
};

NSMutableDictionary* dyldCacheInformation;

NSString* dyldCachePath()
{
	return [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/System/Library/Caches/com.apple.dyld/" isDirectory:YES] includingPropertiesForKeys:nil options:0 error:nil].firstObject.path;
}

void fetchDyldCacheInformation()
{
	HBLogDebug(@"fetchDyldCacheInformation start");
	static dispatch_once_t onceTokenDyld;

    dispatch_once(&onceTokenDyld, ^
	{
		dyldCacheInformation = [NSMutableDictionary new];
    });

	FILE* dyldCacheFile = fopen(dyldCachePath().UTF8String, "rb");

	if(dyldCacheFile == NULL)
	{
		return;
	}

	struct dyld_cache_header header;

	fread(&header,sizeof(header),1,dyldCacheFile);

	for(NSInteger i = 0; i < header.imagesCount; i++)
	{
		struct dyld_cache_image_info imageInfo;
		uint32_t offset = header.imagesOffset + sizeof(imageInfo) * i;
		fseek(dyldCacheFile,offset,SEEK_SET);
		fread(&imageInfo,sizeof(imageInfo),1,dyldCacheFile);

		uint64_t mappedAdress = 0;

		for(uint32_t i = 0; i < header.mappingCount; i++)
		{
			struct shared_file_mapping mapping;
			fseek(dyldCacheFile,header.mappingOffset + sizeof(mapping) * i,SEEK_SET);
			fread(&mapping,sizeof(mapping),1,dyldCacheFile);

			if ((mapping.address <= imageInfo.address) && (imageInfo.address < (mapping.address + mapping.size)))
			{
				mappedAdress = mapping.file_offset + imageInfo.address - mapping.address;
				break;
			}
		}

		fseek(dyldCacheFile,imageInfo.pathFileOffset,SEEK_SET);
		char pathStr[256];
		fread(pathStr, sizeof(pathStr),1,dyldCacheFile);
		NSString* contentPath = [NSString stringWithUTF8String:pathStr];
		[dyldCacheInformation setObject:[NSNumber numberWithUnsignedLongLong:mappedAdress] forKey:contentPath];
	}

	fclose(dyldCacheFile);

	HBLogDebug(@"fetchDyldCacheInformation end");
}

BOOL pathIsInsideDyldCache(NSString* path)
{
	return [[dyldCacheInformation allKeys] containsObject:path];
}

uint64_t offsetInsideDyldCacheForPath(NSString* path)
{
	return ((NSNumber*)[dyldCacheInformation objectForKey:path]).unsignedLongLongValue;
}

NSMutableDictionary* dependencyCache;

NSString* threeCharsAfterString(NSString* string, NSString* substring)
{
	NSRange substringRange = [string rangeOfString:substring];

	NSRange threeAfterSubstringRange = NSMakeRange(substringRange.location + substringRange.length, 3);

	if(string.length >= threeAfterSubstringRange.location + threeAfterSubstringRange.length)
	{
		return [string substringWithRange:threeAfterSubstringRange];
	}

	return @"";
}

NSString* resolvedPathForPath(NSString* path, NSString* executablePath, NSArray* rpaths)
{
	HBLogDebug(@"resolvedPathForPaths(%@,%@,%@)", path, executablePath, rpaths);

	NSString* resolvedPath = path;

	if([resolvedPath containsString:@"@executable_path"])
	{
		NSString* pathToResolve;

		NSString* threeAfter = threeCharsAfterString(resolvedPath, @"executable_path");
		HBLogDebug(@"%@ threeAfter = %@", resolvedPath, threeAfter);

		if([threeAfter containsString:@".."])
		{
			pathToResolve = executablePath;
		}
		else
		{
			pathToResolve = [executablePath stringByDeletingLastPathComponent];
		}

		resolvedPath = [resolvedPath stringByReplacingOccurrencesOfString:@"@executable_path" withString:pathToResolve];
	}

	if([resolvedPath containsString:@"@loader_path"])
	{
		NSString* pathToResolve;

		NSString* threeAfter = threeCharsAfterString(resolvedPath, @"loader_path");
		HBLogDebug(@"%@ threeAfter = %@", resolvedPath, threeAfter);

		if([threeAfter containsString:@".."])
		{
			pathToResolve = executablePath;
		}
		else
		{
			pathToResolve = [executablePath stringByDeletingLastPathComponent];
		}

		resolvedPath = [resolvedPath stringByReplacingOccurrencesOfString:@"@loader_path" withString:pathToResolve];
	}

	if(!rpaths)
	{
		HBLogDebug(@"= %@", resolvedPath);
		return resolvedPath;
	}

	if([resolvedPath containsString:@"@rpath"])
	{
		for(NSString* rpath in rpaths)
		{
			NSString* resolvedRpath = resolvedPathForPath(rpath, executablePath, nil);
			NSString* possibleCandidatePath = [resolvedPath stringByReplacingOccurrencesOfString:@"@rpath" withString:resolvedRpath];

			HBLogDebug(@"possibleCandidatePath = %@", possibleCandidatePath);

			if([[NSFileManager defaultManager] fileExistsAtPath:possibleCandidatePath])
			{
				HBLogDebug(@"= %@", possibleCandidatePath);
				return possibleCandidatePath;
			}
		}
	}

	HBLogDebug(@"= %@", resolvedPath);
	return resolvedPath;
}

NSSet* _frameworkBundleIDsForMachoAtPath(NSMutableSet* alreadyParsedPaths, NSString* path, NSString* pathOfLinkingExecutable)
{
	static dispatch_once_t onceToken;

    dispatch_once (&onceToken, ^
	{
        fetchDyldCacheInformation();
		dependencyCache = [NSMutableDictionary new];
    });

	if(!alreadyParsedPaths)
	{
		alreadyParsedPaths = [NSMutableSet new];
	}

	HBLogDebug(@"_frameworkBundleIDsForMachoAtPath(%@)",path);

	NSSet* cachedDependencies = [dependencyCache objectForKey:path];

	if(cachedDependencies)
	{
		HBLogDebug(@"cache for %@", path);
		return cachedDependencies;
	}

	NSArray* rpathsForBinary;
	NSArray* dependencies = dependenciesForMachoAtPath(path, &rpathsForBinary);

	if(!dependencies)
	{
		return nil;
	}

	NSMutableSet* frameworkBundleIDs = [NSMutableSet new];

	for(NSString* dependencyPath in dependencies)
	{
		NSString* resolvedDependecyPath = resolvedPathForPath(dependencyPath, path, rpathsForBinary);

		if(!resolvedDependecyPath)
		{
			continue;
		}

		if(![resolvedDependecyPath.pathExtension isEqualToString:@"dylib"])
		{
			NSBundle* frameworkBundle = [NSBundle bundleWithPath:[resolvedDependecyPath stringByDeletingLastPathComponent]];
			if(frameworkBundle && frameworkBundle.bundleIdentifier)
			{
				[frameworkBundleIDs addObject:frameworkBundle.bundleIdentifier];
			}
		}

		if(![alreadyParsedPaths containsObject:resolvedDependecyPath])
		{
			[alreadyParsedPaths addObject:resolvedDependecyPath];
			NSSet* dependencyDependants = _frameworkBundleIDsForMachoAtPath(alreadyParsedPaths, resolvedDependecyPath, path);
			[frameworkBundleIDs unionSet:dependencyDependants];
		}
	}

	NSSet* frameworkBundleIDsCopy = [frameworkBundleIDs copy];

	[dependencyCache setObject:frameworkBundleIDsCopy forKey:path];

	return frameworkBundleIDsCopy;
}

NSSet* frameworkBundleIDsForMachoAtPath(NSString* path)
{
	return _frameworkBundleIDsForMachoAtPath(nil, path, path);
}

uint32_t s32(uint32_t toSwap, BOOL shouldSwap)
{
	return shouldSwap ? SWAP32(toSwap) : toSwap;
}

uint32_t offsetForArchInFatBinary(FILE *machoFile)
{
	fseek(machoFile,0,SEEK_SET);

	struct fat_header fatHeader;
	fread(&fatHeader,sizeof(fatHeader),1,machoFile);

	BOOL swp = fatHeader.magic == FAT_CIGAM;

	for(int i = 0; i < s32(fatHeader.nfat_arch, swp); i++)
	{
		struct fat_arch fatArch;
		fseek(machoFile,sizeof(fatHeader) + sizeof(fatArch) * i,SEEK_SET);
		fread(&fatArch,sizeof(fatArch),1,machoFile);

		fseek(machoFile,s32(fatArch.offset, swp),SEEK_SET);
		struct mach_header_universal header;
		fread(&header,sizeof(header),1,machoFile);

		if(header.magic == MH_MAGIC_UNIVERSAL || header.magic == MH_CIGAM_UNIVERSAL)
		{
			return s32(fatArch.offset, swp);
		}
	}

	return 0;
}

NSArray* dependenciesForMachoAtPath(NSString* path, NSArray** rpaths)
{
	NSMutableArray* dylibPaths;
	NSMutableArray* rpathsTmp;
	FILE *machoFile;

	uint32_t archOffset = 0;
	uint64_t dyldOffset = 0;

	if(pathIsInsideDyldCache(path))
	{
		HBLogDebug(@"dyld path detected!!!!");
		dyldOffset = offsetInsideDyldCacheForPath(path);
		path = dyldCachePath();
	}
	
	const char* pathStr = [path UTF8String];

	machoFile = fopen(pathStr, "rb");

	if(machoFile == NULL)
	{
		NSLog(@"failed to open macho at %@",path);
		return nil;
	}

	fseek(machoFile,dyldOffset,SEEK_SET);
	struct mach_header_universal header;
	fread(&header,sizeof(header),1,machoFile);

	HBLogDebug(@"magic = %llX", (unsigned long long)header.magic);

	if(header.magic == FAT_MAGIC || header.magic == FAT_CIGAM)
	{
		archOffset = offsetForArchInFatBinary(machoFile);
		fseek(machoFile,archOffset,SEEK_SET);
		fread(&header,sizeof(header),1,machoFile);
	}

	uint64_t fullOffset = dyldOffset + archOffset;

	HBLogDebug(@"fullOffset: %llX", (unsigned long long)fullOffset);
	HBLogDebug(@"header.magic: %llX", (unsigned long long)header.magic);

	if(header.magic == MH_MAGIC_UNIVERSAL || header.magic == MH_CIGAM_UNIVERSAL)
	{
		BOOL swp = header.magic == MH_CIGAM_UNIVERSAL;
		dylibPaths = [NSMutableArray new];
		rpathsTmp = [NSMutableArray new];

		uint32_t offset = fullOffset + sizeof(header);

		while(offset < fullOffset + s32(header.sizeofcmds,swp))
		{
			fseek(machoFile,offset,SEEK_SET);
			struct load_command cmd;
			fread(&cmd,sizeof(cmd),1,machoFile);
			HBLogDebug(@"fread(%p,%llu)", &cmd, (unsigned long long)sizeof(cmd));
			if(s32(cmd.cmd,swp) == LC_LOAD_DYLIB || s32(cmd.cmd,swp) == LC_LOAD_WEAK_DYLIB)
			{
				fseek(machoFile,offset,SEEK_SET);
				struct dylib_command dylibCommand;
				HBLogDebug(@"fread(%p,%llu)", &dylibCommand, (unsigned long long)sizeof(dylibCommand));
				fread(&dylibCommand,sizeof(dylibCommand),1,machoFile);
				size_t stringLength = s32(dylibCommand.cmdsize,swp) - sizeof(dylibCommand);
				fseek(machoFile,offset + s32(dylibCommand.dylib.name.offset,swp),SEEK_SET);
				char* dylibPathC = malloc(stringLength);
				HBLogDebug(@"fread(%p,%llu)", dylibPathC, (unsigned long long)stringLength);
				fread(dylibPathC,stringLength,1,machoFile);
				NSString* dylibPath = [NSString stringWithUTF8String:dylibPathC];
				[dylibPaths addObject:dylibPath];
				free(dylibPathC);
			}
			else if(s32(cmd.cmd,swp) == LC_RPATH)
			{
				fseek(machoFile,offset,SEEK_SET);
				struct rpath_command rpathCommand;
				HBLogDebug(@"fread(%p,%llu)", &rpathCommand, (unsigned long long)sizeof(rpathCommand));
				fread(&rpathCommand,sizeof(rpathCommand),1,machoFile);
				size_t stringLength = s32(rpathCommand.cmdsize,swp) - sizeof(rpathCommand);
				fseek(machoFile,offset + s32(rpathCommand.path.offset,swp),SEEK_SET);
				char* rpathC = malloc(stringLength);
				HBLogDebug(@"fread(%p,%llu)", rpathC, (unsigned long long)stringLength);
				fread(rpathC,stringLength,1,machoFile);
				NSString* rpath = [NSString stringWithUTF8String:rpathC];
				[rpathsTmp addObject:rpath];
				free(rpathC);
			}

			offset += cmd.cmdsize;
		}
	}

	fclose(machoFile);

	HBLogDebug(@"dylibPaths = %@", dylibPaths);
	HBLogDebug(@"rpathsTmp = %@", rpathsTmp);

	if(rpaths)
	{
		*rpaths = [rpathsTmp copy];
	}

	return dylibPaths;
}