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


@class ORKUploadableDataStore;
@class ORKUploadableItem;

@protocol ORKUploadableDataStoreDelegate <NSObject>

- (void)dataStore:(ORKUploadableDataStore *)dataStore didReceiveItemWithIdentifier:(NSString *)identifier;

@end


typedef void (^ORKDataStoreEnumerationBlock)(ORKUploadableItem *dataItem, BOOL *stop);

/**
 The `ORKUploadableDataStore` class manages `ORKTaskResult` and files to be uploaded.
 
 `ORKUploadableDataStore` take the ownership of the data by moving them into its managed directory.
 */
ORK_CLASS_AVAILABLE
@interface ORKUploadableDataStore : NSObject

@property (nonatomic, readonly) NSURL *managedDirectory;

@property (nonatomic, weak) id<ORKUploadableDataStoreDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithManagedDirectory:(NSURL *)directory NS_DESIGNATED_INITIALIZER;

/**
    Save result to disk and move linked files to managed directory.
 */
- (NSString *)addTaskResult:(ORKTaskResult *)result metadata:(nullable NSDictionary *)metadata error:(NSError * __autoreleasing *)error;

/**
    Save data
 */
- (NSString *)addData:(NSData *)data metadata:(nullable NSDictionary *)metadata error:(NSError * __autoreleasing *)error;

/**
    Move the file or directory to managed directory.
 */
- (NSString *)addFileURL:(NSURL *)fileURL metadata:(nullable NSDictionary *)metadata error:(NSError * __autoreleasing *)error;

/**
    Get a mananged item with an identifier
 */
- (ORKUploadableItem *)managedItemForIdentifier:(NSString *)identifier;

/**
    Remove a `ORKUploadableItem` from this store. Everything adssociated with this item will be deleted.
 */
- (NSError *)removeManagedItemWithIdentifier:(NSString *)identifer;

/**
    Sorted by createTime / lastUploadTime, exclude uploaded items
 */
- (BOOL)enumerateManagedItems:(ORKDataStoreEnumerationBlock)block
                    exclusion:(ORKDataStoreExclusionOption)exclusionOption
                      sorting:(ORKDataStoreSortingOption)sortingOption
                    ascending:(BOOL)ascending
                        error:(NSError * __autoreleasing *)error;

@end


NS_ASSUME_NONNULL_END
