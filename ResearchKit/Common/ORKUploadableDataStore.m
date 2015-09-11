/*
 Copyright (c) 2015, Apple Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1.  Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2.  Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.
 
 3.  Neither the name of the copyright holder(s) nor the names of any contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission. No license is granted to the trademarks of
 the copyright holders even if such marks are included in this software.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */


#import "ORKUploadableDataStore.h"
#import "ORKUploadableItem_Internal.h"
#import "ORKErrors.h"
#import "ORKDefines_Private.h"

#define ORK_HANDLE_ERROR(errorOut) \
if (errorOut) { \
if (error) { \
*error = errorOut; \
} \
return nil; \
}

#define ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier) \
if (errorOut) { \
if (error) { \
*error = errorOut; \
} \
[self removeManagedItemWithIdentifier:itemIdentifier]; \
return nil; \
}

@interface ORKUploadableDataStore ()

@property (nonatomic, copy, readwrite) NSURL *directoryURL;

@end

@implementation ORKUploadableDataStore {
    NSString *_managedDirectory;
    dispatch_queue_t _queue;
}

- (NSURL *)managedDirectory {
    return [NSURL fileURLWithPath:_managedDirectory];
}

- (instancetype)initWithManagedDirectory:(NSURL *)directory {
    
    self = [super init];
    if (self) {
        
        if (directory == nil) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"directory cannot be nil" userInfo:nil];
        }
        
        _managedDirectory = directory.path;
    
        BOOL isDir;
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        BOOL exist = [defaultManager fileExistsAtPath:_managedDirectory isDirectory:&isDir];
        
        if ((exist && isDir == NO)) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"URL is not a directory" userInfo:nil];
        }
        
        if (NO == exist) {
            NSError *error;
            [defaultManager createDirectoryAtPath:_managedDirectory withIntermediateDirectories:YES attributes:nil error:&error];
           
            if (error) {
                @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Failed to create directory at URL." userInfo:@{@"error" : error}];
            }
        }
        
        self.directoryURL = directory;
        
        NSString *queueId = [@"ResearchKit.dataStore." stringByAppendingString:_managedDirectory];
        _queue = dispatch_queue_create([queueId cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Helpers

- (NSString *)directoryPathForIdentifier:(NSString *)identifier {
    return [_managedDirectory stringByAppendingPathComponent:identifier];
}

- (NSString *)addNewItemWithMetadata:(nullable NSDictionary *)metadata error:(NSError **)error {
    
    NSString *itemIdentifier = [NSUUID UUID].UUIDString;
    NSString *itemPath = [self directoryPathForIdentifier:itemIdentifier];
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    
    NSError *errorOut;
    [defaultManager createDirectoryAtPath:itemPath withIntermediateDirectories:YES attributes:nil error:&errorOut];
    
    ORK_HANDLE_ERROR(errorOut);
    
    if (metadata) {
        // Save plist to disk
        NSString *metaPath = [itemPath stringByAppendingPathComponent:ORKUploadableFileMetadata];
        errorOut = [ORKUploadableItem saveDictionary:metadata to:metaPath];;
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    return itemIdentifier;
}

- (NSError *)moveFilesLinkedWithResult:(ORKTaskResult *)result toDirectory:(NSString *)directoryPath {
    
    NSString *sourceDir = result.outputDirectory.path;
    
    NSFileManager *fileMananger = [NSFileManager defaultManager];
    
    // DateStore move the output directory as a whole.
    BOOL isDir;
    if (sourceDir == nil ||
        NO == [fileMananger fileExistsAtPath:sourceDir isDirectory:&isDir] ||
        NO == isDir ) {
        return nil;
    }
    
    NSError *error;
    
    NSString* destinationPath = [directoryPath stringByAppendingPathComponent:result.outputDirectory.lastPathComponent];
    
    BOOL moved = [fileMananger moveItemAtPath:sourceDir toPath:destinationPath error:&error];
    
    // Update file reference
    if (moved) {
        NSArray *stepResults = result.results;
        for (ORKStepResult *stepResult in stepResults) {
            NSArray *results = stepResult.results;
            for (ORKResult *result in results) {
                if ([result isKindOfClass:[ORKFileResult class]]) {
                     ORKFileResult *fileResult = (ORKFileResult *)result;
                     if ([fileResult.fileURL.path hasPrefix:sourceDir]) {
                         
                         NSString *newPath = [fileResult.fileURL.path stringByReplacingCharactersInRange:NSMakeRange(0, sourceDir.length)
                                                                                              withString:destinationPath];
                         
                         if ([fileMananger fileExistsAtPath:newPath]) {
                             fileResult.fileURL = [NSURL fileURLWithPath:newPath];
                         } else {
                             NSLog(@"UploadStore cannot find moved file! %@", newPath);
                         }
                         
                     }
                 }
            }
        }
    }
    
    return error;
}

- (void)notifyDelegateWithIdentifier:(NSString *)identifier {
    if (self.delegate && [self.delegate respondsToSelector:@selector(dataStore:didReceiveItemWithIdentifier:)]) {
        [self.delegate dataStore:self didReceiveItemWithIdentifier:identifier];
    }
}

- (NSString *)addTaskResult:(ORKTaskResult *)result
                       data:(NSData *)data
                    fileURL:(NSURL *)fileURL
                   metadata:(nullable NSDictionary *)metadata
                      error:(NSError **)error {
    
    // Inital setup
    NSError *errorOut;
    NSString *itemIdentifier = [self addNewItemWithMetadata:metadata error:&errorOut];
    ORK_HANDLE_ERROR(errorOut);
    
    NSString *itemPath = [self directoryPathForIdentifier:itemIdentifier];
    
    // Handle result
    if (result) {
        // Move result outpput dir
        NSString *itemPath = [self directoryPathForIdentifier:itemIdentifier];
        errorOut = [self moveFilesLinkedWithResult:result toDirectory:itemPath];
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
        
        // Save result object
        NSData *resultData = [NSKeyedArchiver archivedDataWithRootObject:result];
        NSString *resultDataPath = [itemPath stringByAppendingPathComponent:ORKUploadableFileResult];
        errorOut = [ORKUploadableItem saveData:resultData to:resultDataPath];
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    // Handle NSData
    if (data) {
        NSString *dataPath = [itemPath stringByAppendingPathComponent:ORKUploadableFileData];
        errorOut = [ORKUploadableItem saveData:data to:dataPath];
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    // Handle fileURL
    if (fileURL) {
        
        NSFileManager *defaultManager = [NSFileManager defaultManager];
       
        [defaultManager moveItemAtPath:fileURL.path
                                toPath:[itemPath stringByAppendingPathComponent:[fileURL lastPathComponent]]
                                 error:&errorOut];
        
        
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    [self notifyDelegateWithIdentifier:itemIdentifier];
    
    return itemIdentifier;
}

#pragma mark - Public APIs

- (NSString *)addTaskResult:(ORKTaskResult *)result metadata:(nullable NSDictionary *)metadata error:(NSError **)error {
    
    NSParameterAssert(result != nil);
    return [self addTaskResult:result data:nil fileURL:nil metadata:metadata error:error];
}

- (NSString *)addData:(NSData *)data metadata:(nullable NSDictionary *)metadata error:(NSError **)error {
    
    NSParameterAssert(data != nil);
    return [self addTaskResult:nil data:data fileURL:nil metadata:metadata error:error];
}

- (NSString *)addFileURL:(NSURL *)fileURL metadata:(nullable NSDictionary *)metadata error:(NSError **)error{

    NSParameterAssert(fileURL != nil);    
    return [self addTaskResult:nil data:nil fileURL:fileURL metadata:metadata error:error];
}

- (BOOL)enumerateManagedItems:(ORKDataStoreEnumerationBlock)block
                    exclusion:(ORKDataStoreExclusionOption)exclusionOption
                      sorting:(ORKDataStoreSortingOption)sortingOption
                    ascending:(BOOL)ascending
                        error:(NSError * __autoreleasing *)error {

    if (!block) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Block parameter is required" userInfo:nil];
    }
    
    __block BOOL success = NO;
    dispatch_sync(_queue, ^{
        success = [self queue_enumerateManagedItems:block
                                          exclusion:exclusionOption
                                            sorting:sortingOption
                                          ascending:ascending
                                              error:error];
    });
    return success;
    
}

- (BOOL)queue_enumerateManagedItems:(ORKDataStoreEnumerationBlock)block
                          exclusion:(ORKDataStoreExclusionOption)exclusionOption
                            sorting:(ORKDataStoreSortingOption)sortingOption
                          ascending:(BOOL)ascending
                              error:(NSError * __autoreleasing *)error {
    
    static NSArray *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[NSURLIsDirectoryKey, NSURLCreationDateKey];
    });
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSEnumerator *enumerator = [manager enumeratorAtURL:[NSURL fileURLWithPath:_managedDirectory]
                             includingPropertiesForKeys:@[]
                                                options:(NSDirectoryEnumerationOptions)( NSDirectoryEnumerationSkipsSubdirectoryDescendants|
                                                                                        NSDirectoryEnumerationSkipsHiddenFiles|
                                                                                        NSDirectoryEnumerationSkipsPackageDescendants)
                                           errorHandler:nil];
    
    NSError *errorOut = nil;
    NSMutableArray *items = [NSMutableArray array];
    for (NSURL *url in enumerator) {
       
        NSDictionary *resources = [url resourceValuesForKeys:keys error:&errorOut];
        if (errorOut) {
            // If there's been an error getting the resource values, give up
            break;
        }
        if (! [resources[NSURLIsDirectoryKey] boolValue]) {
            // Skip non directories
            continue;
        }
        
        ORKUploadableItem *item = [[ORKUploadableItem alloc] initWithItemDirectoy:url];
        ORKUploadableItemTracker *tracker = item.tracker;
        
        if ( (exclusionOption & ORKDataStoreExclusionOptionUploadedItems) && tracker.isUploaded) {
            continue;
        }
        
        if ( (exclusionOption & ORKDataStoreExclusionOptionUnuploadedItems) && tracker.isUploaded == NO) {
            continue;
        }
        
        if ( (exclusionOption & ORKDataStoreExclusionOptionTriedItems) && tracker.retryCount > 0) {
            continue;
        }

        if ( (exclusionOption & ORKDataStoreExclusionOptionUntriedItems) && tracker.retryCount == 0) {
            continue;
        }
        
        [items addObject:[item makeSubclassInstance]];
    }
    
    if (! errorOut) {
        // Sort the URLs before beginning enumeration for the caller
        [items sortUsingComparator:^NSComparisonResult(ORKUploadableItem *item1, ORKUploadableItem *item2) {
            // We can assume all relate to files in the same directory
            
            NSComparisonResult result = NSOrderedSame;
            
            if (sortingOption  == ORKDataStoreSortingOptionByCreationDate ) {
                result = [item1.creationDate compare:item2.creationDate];
            } else if (sortingOption  == ORKDataStoreSortingOptionByLastUploadDate ) {
                result = [item1.tracker.lastUploadDate compare:item2.tracker.lastUploadDate];
            } else if (sortingOption  == ORKDataStoreSortingOptionByRetryCount ) {
                result = [@(item1.tracker.retryCount) compare:@(item2.tracker.retryCount)];
            }
            
            if (ascending == NO) {
                if (result == NSOrderedAscending) {
                    result = NSOrderedDescending;
                } else if (result == NSOrderedDescending){
                    result = NSOrderedAscending;
                }
            }
            
            return result;
        }];
        
        for (ORKUploadableItem *item in items) {
            BOOL stop = NO;
            
            block(item, &stop);
            if (stop) {
                break;
            }
        }
    }
    
    if (error && errorOut) {
        *error = errorOut;
    }
    return (errorOut ? NO : YES);
}



- (ORKUploadableItem *)managedItemForIdentifier:(NSString *)identifier {

    NSString *path = [self directoryPathForIdentifier:identifier];
    BOOL exist = [[NSFileManager defaultManager] fileExistsAtPath:path];
    
    return exist? [[ORKUploadableItem alloc] initWithItemDirectoy:[NSURL fileURLWithPath:path]] : nil;
}

- (NSError *)removeManagedItemWithIdentifier:(NSString *)identifier {
    
    NSError *error;
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    [defaultManager removeItemAtPath:[self directoryPathForIdentifier:identifier] error:&error];
    return error;
}

@end
