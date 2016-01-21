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


NS_ASSUME_NONNULL_BEGIN

typedef void (^ORKDataStoreFilesEnumerationBlock)(NSURL *fileURL, BOOL *stop);

@class ORKUploadableItemTracker;

ORK_CLASS_AVAILABLE
@interface ORKUploadableItem : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;

@property (nonatomic, copy, readonly) NSURL *directoryURL;

@property (nonatomic, copy, readonly) NSDictionary *metadata;

- (NSError *)setMetadata:(NSDictionary *)metadata;

@property (nonatomic, readonly) NSDate * __nullable creationDate;

- (BOOL)enumerateManagedFiles:(ORKDataStoreFilesEnumerationBlock)block error:(NSError * __autoreleasing *)error;

@property (nonatomic, readonly) ORKUploadableItemTracker *tracker;

@end


ORK_CLASS_AVAILABLE
@interface ORKUploadableDataItem : ORKUploadableItem

@property (nonatomic, strong, readonly) NSData *data;

@end


ORK_CLASS_AVAILABLE
@interface ORKUploadableResultItem : ORKUploadableItem

@property (nonatomic, strong, readonly) ORKTaskResult * __nullable result;

@end


ORK_CLASS_AVAILABLE
@interface ORKUploadableFileItem : ORKUploadableItem

@property (nonatomic, copy, readonly) NSURL * __nullable fileURL;

@property (nonatomic, readonly, getter=isDirectory) BOOL directory;

@end


ORK_CLASS_AVAILABLE
@interface ORKUploadableItemTracker : NSObject

- (instancetype)initWithUploadableItem:(ORKUploadableItem *)uploadableItem;

@property (nonatomic, assign, readonly, getter=isUploaded) BOOL uploaded;

- (void)markUploaded;

@property (nonatomic, assign, readonly) NSUInteger retryCount;

- (void)increaseRetryCount;

@property (nonatomic, readonly) NSDate * __nullable lastUploadDate;

@end

NS_ASSUME_NONNULL_END
