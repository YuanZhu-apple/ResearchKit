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


#import "ORKUploadableItem_Internal.h"


typedef NS_ENUM(NSInteger, ORKUploadableItemType) {
    ORKUploadableItemTypeResult,
    ORKUploadableItemTypeData,
    ORKUploadableItemTypeFile
}; ORK_ENUM_AVAILABLE

static NSString const *ItemUploadedKey = @"uploaded";
static NSString const *ItemRetryCountKey = @"retryCount";
static NSString const *ItemRetryDateKey = @"retryDate";
static NSString const *ItemQueuePrefix = @"ResearchKit.UploadableItem.";




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

- (instancetype)makeSubclassInstance {
    Class itemClass = nil;
    
    switch ([self itemType]) {
        case ORKUploadableItemTypeData:
            itemClass = [ORKUploadableDataItem class];
            break;
        case ORKUploadableItemTypeFile:
            itemClass = [ORKUploadableFileItem class];
            break;
        case ORKUploadableItemTypeResult:
            itemClass = [ORKUploadableResultItem class];
            break;
        default:
            break;
    }
    
    return [[itemClass alloc] initWithItemDirectoy:self.directoryURL];
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

- (ORKUploadableItemType)itemType {
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    
    if ([defaultManager fileExistsAtPath:[self pathOfFile:ORKUploadableFileResult]]) {
        return ORKUploadableItemTypeResult;
    } else if ([defaultManager fileExistsAtPath:[self pathOfFile:ORKUploadableFileData]]) {
        return ORKUploadableItemTypeData;
    }
    
    return ORKUploadableItemTypeFile;
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
    return [NSDictionary dictionaryWithContentsOfFile:[self pathOfFile:ORKUploadableFileMetadata]];
}

- (NSError *)setMetadata:(NSDictionary *)metadata {
    
    NSError *errorOut;
    
    if (metadata == nil) {
        metadata = [NSDictionary new];
    }
    
    errorOut = [[self class] saveDictionary:metadata to:[self pathOfFile:ORKUploadableFileMetadata]];
    
    return errorOut;
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

@implementation ORKUploadableDataItem

- (NSData *)data {
    return [NSData dataWithContentsOfFile:[self pathOfFile:ORKUploadableFileData]];
}

@end

@implementation ORKUploadableResultItem

- (NSURL *)fileURL {
    
    return [super fileURL];
}

- (ORKTaskResult *)result {
    ORKTaskResult *result = [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathOfFile:ORKUploadableFileResult]];
    return result;
}


@end

@implementation ORKUploadableFileItem


- (NSURL *)fileURL {
    
    return [super fileURL];
}

@end

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
    return [NSDictionary dictionaryWithContentsOfFile:[self pathOfFile:ORKUploadableFileInfo]];
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
    [dictionary writeToFile:[self pathOfFile:ORKUploadableFileInfo] atomically:YES];
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
    [dictionary writeToFile:[self pathOfFile:ORKUploadableFileInfo] atomically:YES];
    
}

@end
