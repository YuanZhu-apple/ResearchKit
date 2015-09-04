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


#import <ResearchKit/ResearchKit.h>
@import Foundation;


typedef NS_ENUM(NSInteger, ORKPreUploadDataItemType) {
    ORKPreUploadDataItemTypeResult,
    ORKPreUploadDataItemTypeData,
    ORKPreUploadDataItemTypeFile
}; ORK_ENUM_AVAILABLE

typedef NS_ENUM(NSInteger, ORKDataStoreSortingOption) {
    ORKDataStoreSortingOptionByCreationDate     = 0,
    ORKDataStoreSortingOptionByLastUploadDate,
    ORKDataStoreSortingOptionByRetryCount
} ORK_ENUM_AVAILABLE;

typedef NS_OPTIONS(NSInteger, ORKDataStoreExclusionOption) {
    ORKDataStoreExclusionOptionNone             = 0,
    ORKDataStoreExclusionOptionUploadedItems    = (1 << 0),
    ORKDataStoreExclusionOptionUnuploadedItems  = (1 << 1),
    ORKDataStoreExclusionOptionTriedItems       = (1 << 2),
    ORKDataStoreExclusionOptionUntriedItems     = (1 << 3)
} ORK_ENUM_AVAILABLE;


NS_ASSUME_NONNULL_BEGIN

typedef void (^ORKDataStoreFilesEnumerationBlock)(NSURL *fileURL, BOOL *stop);

@class ORKUploadableItemTracker;

@interface ORKUploadableItem : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;

@property (nonatomic, copy, readonly) NSURL *directoryURL;

//@property (nonatomic, assign, readonly) ORKPreUploadDataItemType itemType;

@property (nonatomic, copy, readonly) NSDictionary *metadata;

- (NSError *)setMetadata:(NSDictionary *)metadata;

@property (nonatomic, readonly) NSDate * __nullable creationDate;             // Standard File Attributes

- (BOOL)enumerateManagedFiles:(ORKDataStoreFilesEnumerationBlock)block error:(NSError * __autoreleasing *)error;

@property (nonatomic, readonly) ORKUploadableItemTracker *tracker;

@end

@interface ORKUploadableDataItem : ORKUploadableItem

@property (nonatomic, strong, readonly) NSData *data;

@end

@interface ORKUploadableResultItem : ORKUploadableItem

@property (nonatomic, strong, readonly) ORKTaskResult * __nullable result;

@end

@interface ORKUploadableFileItem : ORKUploadableItem

@property (nonatomic, copy, readonly) NSURL * __nullable fileURL;

@property (nonatomic, readonly, getter=isDirectory) BOOL directory;

@end

@interface ORKUploadableItemTracker : NSObject

- (instancetype)initWithUploadableItem:(ORKUploadableItem *)uploadableItem;

@property (nonatomic, assign, readonly, getter=isUploaded) BOOL uploaded;

- (void)markUploaded;

@property (nonatomic, assign, readonly) NSUInteger retryCount;

- (void)increaseRetryCount;

@property (nonatomic, readonly) NSDate * __nullable lastUploadDate;

@end



@class ORKPreUploadDataStore;

@protocol ORKPreUploadDataStoreDelegate <NSObject>

- (void)dataStore:(ORKPreUploadDataStore *)dataStore didReceiveItemWithIdentifier:(NSString *)identifier;

@end


typedef void (^ORKDataStoreEnumerationBlock)(ORKUploadableItem *dataItem, BOOL *stop);

@interface ORKPreUploadDataStore : NSObject

@property (nonatomic, weak) id<ORKPreUploadDataStoreDelegate> delegate;

- (instancetype)initWithManagedDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER; 

/**
    Save result to disk and move linked files to managed directory.
 */
- (NSString *)addTaskResult:(ORKTaskResult *)result metadata:(nullable NSDictionary *)metadata error:(NSError * __autoreleasing *)error;

/**
    Save data to disk
 */
- (NSString *)addData:(NSData *)data metadata:(nullable NSDictionary *)metadata error:(NSError * __autoreleasing *)error;

/**
    Move the file or directory to managed directory.
 */
- (NSString *)addFileURL:(NSURL *)fileURL metadata:(nullable NSDictionary *)metadata error:(NSError * __autoreleasing *)error;

- (ORKUploadableItem *)dataItemForIdentifier:(NSString *)identifier;

- (NSError *)removeDataItemWithIdentifier:(NSString *)identifer;

/**
    Sorted by createTime / lastUploadTime, exclude uploaded items
 */
- (BOOL)enumerateManagedItems:(ORKDataStoreEnumerationBlock)block
                    exclusion:(ORKDataStoreExclusionOption)exclusionOption
                      sorting:(ORKDataStoreSortingOption)sortingOption
                    ascending:(BOOL)ascending
                        error:(NSError * __autoreleasing *)error;

@end

@interface ORKReferenceUploader : NSObject

- (void)initWithDataStore:(ORKPreUploadDataStore *)dataStore;

- (void)startWithItemIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
