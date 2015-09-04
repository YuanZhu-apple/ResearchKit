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


#import "ORKPreUploadDataStore.h"
#import "ORKErrors.h"
#import "ORKDefines_Private.h"

static NSString * const kFileMetadata = @".ork.metadata.plist";
static NSString * const kFileInfo = @".ork.item.info.plist";
static NSString * const kFileResult = @".ork.result.data";
static NSString * const kFileData = @".ork.data.data";

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
    [self removeDataItemWithIdentifier:itemIdentifier]; \
    return nil; \
}

static NSString const *ItemUploadedKey = @"uploaded";
static NSString const *ItemRetryCountKey = @"retryCount";
static NSString const *ItemRetryDateKey = @"retryDate";
static NSString const *ItemQueuePrefix = @"ResearchKit.UploadableItem.";

@implementation ORKUploadableItemTracker {
    __weak ORKUploadableItem *_item;
    dispatch_queue_t _queue;
}

- (instancetype)initWithUploadableItem:(ORKUploadableItem *)uploadableItem {
    NSParameterAssert(uploadableItem);
    self = [super init];
    if (self) {
        _item = uploadableItem;
    }
    return self;
}

- (NSDictionary *)infoDictionary {
    return [NSDictionary dictionaryWithContentsOfFile:[self pathOfFile:kFileInfo]];
}

- (NSString *)pathOfFile:(NSString *)fileName {
    return [_item.directoryURL.path stringByAppendingPathComponent:fileName];
}

- (dispatch_queue_t)queue {
    if (_queue == nil) {
        NSString *queueId = [ItemQueuePrefix stringByAppendingString:_item.identifier];
        _queue = dispatch_queue_create([queueId cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
    }
    return _queue;
}

- (BOOL)isUploaded {
    NSNumber *value = [self infoDictionary][ItemUploadedKey];
    return value? value.boolValue : NO;
}

- (void)markUploaded {
    
    dispatch_sync(self.queue, ^{
        [self queue_markUploaded];
    });
}

- (void)queue_markUploaded {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithDictionary:[self infoDictionary]];
    dictionary[ItemUploadedKey] = @(YES);
    dictionary[ItemRetryDateKey] = [NSDate date];
    [dictionary writeToFile:[self pathOfFile:kFileInfo] atomically:YES];
}

- (NSUInteger)retryCount {
    NSNumber *value = [self infoDictionary][ItemRetryCountKey];
    return value? value.unsignedIntegerValue : 0;
}

- (NSDate *)lastUploadDate {
    NSDate *value = [self infoDictionary][ItemRetryDateKey];
    return value;
}

- (void)increaseRetryCount {
    
    dispatch_sync(self.queue, ^{
        [self queue_increaseRetryCount];
    });
}

- (void)queue_increaseRetryCount {
    
    if (self.uploaded) {
        return;
    }
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithDictionary:[self infoDictionary]];
    NSNumber *count = dictionary[ItemRetryCountKey];
    if (count == nil) {
        count = @(1);
    } else {
        count = @(count.integerValue + 1);
    }
    dictionary[ItemRetryDateKey] = [NSDate date];
    dictionary[ItemRetryCountKey] = count;
    [dictionary writeToFile:[self pathOfFile:kFileInfo] atomically:YES];
    
}

@end

// inner class
@interface ORKDataStoreFileMovingCandidate : NSObject

@property (nonatomic, strong) NSURL *sourceFileURL;

@property (nonatomic, strong) NSURL *destinationFileURL;

@property (nonatomic, strong) ORKFileResult *fileResult;

- (BOOL)moveFile:(NSError **)error;

- (BOOL)rollback:(NSError **)error;

@end

@implementation ORKDataStoreFileMovingCandidate

- (BOOL)moveFile:(NSError **)error {
    NSError *errorOut = [self moveToDestination:YES];
    
    if (error && errorOut) {
        *error = errorOut;
    }
    
    return (errorOut == nil);
}

- (NSError *)moveToDestination:(BOOL)toDestination {
    NSURL *fromURL = self.sourceFileURL;
    NSURL *toURL = self.destinationFileURL;
    
    if (toDestination == NO) {
        toURL = self.sourceFileURL;
        fromURL = self.destinationFileURL;
    }
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    NSError *errorOut;
    [defaultManager moveItemAtURL:fromURL toURL:toURL error:&errorOut];
    
    if (errorOut == nil) {
        // Update the link on fileResult
        self.fileResult.fileURL = toURL;
    }
    
    return errorOut;
}

- (BOOL)rollback:(NSError **)error {
    
    NSError *errorOut = [self moveToDestination:NO];
  
    if (error && errorOut) {
        *error = errorOut;
    }

    return (errorOut == nil);
}

@end


@interface ORKUploadableItem ()

- (instancetype)initWithItemDirectoy:(NSURL *)directory;

@property (nonatomic, copy, readwrite) NSString *identifier;

@property (nonatomic, copy, readwrite) NSURL *directoryURL;

@end

@implementation ORKUploadableItem {
    dispatch_queue_t _queue;
    NSDate *_creationDate;
    ORKUploadableItemTracker *_tracker;
}

- (instancetype)initWithItemDirectoy:(NSURL *)directoryURL {

    self = [super init];
    if (self) {
        self.identifier = directoryURL.lastPathComponent;
        self.directoryURL = directoryURL;
    }
    return self;
}

#pragma mark - Helpers

+ (NSError *)saveData:(NSData *)data to:(NSString *)path {
    NSError *error;
    [data writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUnlessOpen error:&error];
    return error;
}

+ (NSError *)saveDictionary:(NSDictionary *)dictionary to:(NSString *)path {
    NSError *error;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:dictionary
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&error];
    
    if (error) {
        return error;
    }
    
    return [self saveData:plistData to:path];
}

- (NSString *)pathOfFile:(NSString *)fileName {
    return [self.directoryURL.path stringByAppendingPathComponent:fileName];
}

- (ORKPreUploadDataItemType)itemType {
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    
    if ([defaultManager fileExistsAtPath:[self pathOfFile:kFileResult]]) {
        return ORKPreUploadDataItemTypeResult;
    } else if ([defaultManager fileExistsAtPath:[self pathOfFile:kFileData]]) {
        return ORKPreUploadDataItemTypeData;
    }
    
    return ORKPreUploadDataItemTypeFile;
}

- (BOOL)isValid {
    BOOL isDir;
    BOOL exist = [[NSFileManager defaultManager] fileExistsAtPath:self.directoryURL.path isDirectory:&isDir];
    return exist&&isDir;
}

- (dispatch_queue_t)queue {
    if (_queue == nil) {
        NSString *queueId = [ItemQueuePrefix stringByAppendingString:self.identifier];
        _queue = dispatch_queue_create([queueId cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
    }
    return _queue;
}

#pragma mark - Managed Attribute

- (ORKUploadableItemTracker *)tracker {
    
    if (_tracker == nil) {
        _tracker = [[ORKUploadableItemTracker alloc] initWithUploadableItem:self];
    }
    
    return _tracker;
}

- (NSDictionary *)metadata {
    return [NSDictionary dictionaryWithContentsOfFile:[self pathOfFile:kFileMetadata]];
}

- (NSError *)setMetadata:(NSDictionary *)metadata {
    
    NSError *errorOut;
    
    if (metadata == nil) {
        metadata = [NSDictionary new];
    }
    
    errorOut = [[self class] saveDictionary:metadata to:[self pathOfFile:kFileMetadata]];
    
    return errorOut;
}

- (ORKTaskResult *)result {
    ORKTaskResult *result = [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathOfFile:kFileResult]];
    return result;
}

- (NSData *)data {
    return [NSData dataWithContentsOfFile:[self pathOfFile:kFileData]];
}

- (NSURL *)fileURL {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray * dirContents =
    [fileManager contentsOfDirectoryAtURL:self.directoryURL
               includingPropertiesForKeys:@[]
                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                    error:nil];
    if (dirContents.count > 1) {
        NSLog(@"%@", dirContents);
    }
    return dirContents.firstObject;
}

- (NSDate *)creationDate {
    
    if ([self isValid] == NO) {
        return nil;
    }
    
    if (_creationDate == nil) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:self.directoryURL.path error:nil];

        if (attributes != nil) {
            _creationDate = (NSDate *)[attributes objectForKey: NSFileCreationDate];
        }
    }
    
    return _creationDate;
}

#pragma mark - Enumerate

- (BOOL)enumerateManagedFiles:(ORKDataStoreFilesEnumerationBlock)block error:(NSError * __autoreleasing *)error {
    
    if (!block) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Block parameter is required" userInfo:nil];
    }
    
    __block BOOL success = NO;
    dispatch_sync(self.queue, ^{
        success = [self queue_enumerateManagedFiles:block
                                              error:error];
    });
    return success;
}

- (BOOL)queue_enumerateManagedFiles:(ORKDataStoreFilesEnumerationBlock)block error:(NSError * __autoreleasing *)error {
    
    static NSArray *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[NSURLIsDirectoryKey];
    });
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSEnumerator *enumerator = [manager enumeratorAtURL:self.directoryURL
                             includingPropertiesForKeys:@[]
                                                options:(NSDirectoryEnumerationOptions)(NSDirectoryEnumerationSkipsHiddenFiles)
                                           errorHandler:nil];
    
    NSError *errorOut = nil;
    NSMutableArray *urls = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        
        NSDictionary *resources = [url resourceValuesForKeys:keys error:&errorOut];
        if (errorOut) {
            // If there's been an error getting the resource values, give up
            break;
        }
        if ([resources[NSURLIsDirectoryKey] boolValue]) {
            // Skip directories
            continue;
        }
        
        [urls addObject:url];
    }
    
    if (! errorOut) {
        
        for (NSURL *url in urls) {
            BOOL stop = NO;
            
            block(url, &stop);
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

@end

@interface ORKPreUploadDataStore ()

@property (nonatomic, copy, readwrite) NSURL *directoryURL;

@end

@implementation ORKPreUploadDataStore {
    NSString *_managedDirectory;
    dispatch_queue_t _queue;
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
        NSString *metaPath = [itemPath stringByAppendingPathComponent:kFileMetadata];
        errorOut = [ORKUploadableItem saveDictionary:metadata to:metaPath];;
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    return itemIdentifier;
}

- (NSError *)moveFilesLinkedWithResult:(ORKTaskResult *)result toDirectory:(NSString *)directoryPath {
    
    NSArray *stepResults = result.results;
    NSMutableArray * movedFileCandidates = [NSMutableArray new];
    
    NSError *error;
    
    for (ORKStepResult *stepResult in stepResults) {
        NSArray *results = stepResult.results;
        for (ORKResult *result in results) {
            if ([result isKindOfClass:[ORKFileResult class]]) {
                ORKFileResult *fileResult = (ORKFileResult *)result;
                
                NSURL *sourceURL = fileResult.fileURL;
                if (sourceURL != nil) {
                    
                    NSArray *sourcePathComponents = [sourceURL pathComponents];
                    NSString *destinationFileName = [[sourcePathComponents subarrayWithRange:NSMakeRange(1, sourcePathComponents.count-1)] componentsJoinedByString:@"_"];
                    NSString *destinationFilePath = [directoryPath stringByAppendingPathComponent:destinationFileName];
                    
                    ORKDataStoreFileMovingCandidate *candidate = [ORKDataStoreFileMovingCandidate new];
                    candidate.sourceFileURL = sourceURL;
                    candidate.destinationFileURL = [NSURL fileURLWithPath:destinationFilePath];
                    candidate.fileResult = fileResult;
                    
                    [candidate moveFile:&error];
                    
                    if (error) {
                        break;
                    }
                    
                    [movedFileCandidates addObject:candidate];
                }
            }
        }
        
        if (error) {
            break;
        }
    }
    
    if (error) {
        for (ORKDataStoreFileMovingCandidate *candidate in movedFileCandidates) {
            // TODO: what if there is an error during rollback?
            [candidate rollback:nil];
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
        // Move result linked files
        NSString *itemPath = [self directoryPathForIdentifier:itemIdentifier];
        errorOut = [self moveFilesLinkedWithResult:result toDirectory:itemPath];
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
        
        // Save result object
        NSData *resultData = [NSKeyedArchiver archivedDataWithRootObject:result];
        NSString *resultDataPath = [itemPath stringByAppendingPathComponent:kFileResult];
        errorOut = [ORKUploadableItem saveData:resultData to:resultDataPath];
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    // Handle NSData
    if (data) {
        NSString *dataPath = [itemPath stringByAppendingPathComponent:kFileData];
        errorOut = [ORKUploadableItem saveData:data to:dataPath];
        ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier);
    }
    
    // Handle fileURL
    if (fileURL) {
        BOOL isDir;
        NSFileManager *defaultManager = [NSFileManager defaultManager];
        [defaultManager fileExistsAtPath:fileURL.path isDirectory:&isDir];
        if (isDir) {
            NSString* oldDir = fileURL.path;
            NSArray *files = [defaultManager contentsOfDirectoryAtPath:oldDir error:&errorOut];
            
            ORK_HANDLE_ERROR_AND_REMOVE_DIRECTORY(errorOut, itemIdentifier)
            
            NSMutableArray *movedFileCandidates = [NSMutableArray new];
            
            for (NSString *file in files) {
                
                ORKDataStoreFileMovingCandidate *candidate = [ORKDataStoreFileMovingCandidate new];
                candidate.sourceFileURL = [NSURL fileURLWithPath:[oldDir stringByAppendingPathComponent:file]];
                candidate.destinationFileURL = [NSURL fileURLWithPath:[itemPath stringByAppendingPathComponent:file]];
                [candidate moveFile:&errorOut];
                
                if (errorOut) {
                    break;
                }
                
                [movedFileCandidates addObject:candidate];
            }
            
            if (errorOut) {
                for (ORKDataStoreFileMovingCandidate *candidate in movedFileCandidates) {
                    // TODO: what if there is an error during rollback?
                    [candidate rollback:nil];
                }
            }
            
        } else {
            [defaultManager moveItemAtPath:fileURL.path
                                    toPath:[itemPath stringByAppendingPathComponent:[fileURL lastPathComponent]]
                                     error:&errorOut];
        }
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
    
    BOOL isDir;
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    BOOL exist = [defaultManager fileExistsAtPath:fileURL.path isDirectory:&isDir];
    NSParameterAssert(fileURL != nil && exist);
    
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

        [items addObject:item];
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



- (ORKUploadableItem *)dataItemForIdentifier:(NSString *)identifier {

    NSString *path = [self directoryPathForIdentifier:identifier];
    BOOL exist = [[NSFileManager defaultManager] fileExistsAtPath:path];
    
    return exist? [[ORKUploadableItem alloc] initWithItemDirectoy:[NSURL fileURLWithPath:path]] : nil;
}

- (NSError *)removeDataItemWithIdentifier:(NSString *)identifier {
    
    NSError *error;
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    [defaultManager removeItemAtPath:[self directoryPathForIdentifier:identifier] error:&error];
    return error;
}

@end
