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

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#import <ResearchKit/ResearchKit.h>

@interface ORKUploadableDataStoreTests : XCTestCase<ORKUploadableDataStoreDelegate>

@property (nonatomic) NSInteger delegateCallCount;

@end

@implementation ORKUploadableDataStoreTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
    
    [[NSFileManager defaultManager] removeItemAtPath:[self basePath] error:nil];
}

- (BOOL)fileExistAt:(NSString *)path {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSString *)documentPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
}

- (NSString *)sourcePath {
    NSString *sourcePath = [[self documentPath] stringByAppendingPathComponent:@"source"];
    [[NSFileManager defaultManager] createDirectoryAtPath:sourcePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return sourcePath;
}


- (NSString *)basePath {
    NSString *testPath = [[self documentPath] stringByAppendingPathComponent:@"test"];
    [[NSFileManager defaultManager] createDirectoryAtPath:testPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return testPath;
}

- (NSString *)storePath {
    NSString *basePath = [self basePath];
    NSString *storePath = [basePath stringByAppendingPathComponent:@"managedStore"];
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:nil];
    return storePath;
}

- (void)dataStore:(ORKUploadableDataStore *)dataStore didReceiveItemWithIdentifier:(NSString *)identifier {
    self.delegateCallCount++;
}

- (void)testDataStoreGeneral {
    
    [self measureBlock:^{
        
        ORKUploadableDataStore *dataStore = [[ORKUploadableDataStore alloc] initWithManagedDirectory: [NSURL fileURLWithPath:[self storePath]]];
        dataStore.delegate = self;
        self.delegateCallCount = 0;
        NSInteger newItemCount = 0;
        
        {
            // addTaskResult
            ORKTaskResult *result = [[ORKTaskResult alloc] initWithTaskIdentifier:@"abcd" taskRunUUID:[NSUUID UUID] outputDirectory:[NSURL fileURLWithPath:[self sourcePath]]];
            result.startDate = [NSDate dateWithTimeIntervalSinceNow:-100.0];
            result.endDate = [NSDate dateWithTimeIntervalSinceNow:+100.0];
            
            ORKFileResult *fileResult = [[ORKFileResult alloc] initWithIdentifier:@"file1"];
            NSString *samplePath = [[self sourcePath] stringByAppendingPathComponent:@"result.plist"];
            [@{@"sample":@"sample"} writeToFile:samplePath atomically:YES];
            fileResult.fileURL = [NSURL fileURLWithPath:samplePath];
            
            ORKStepResult *stepResult = [[ORKStepResult alloc] initWithStepIdentifier:@"step0" results:@[fileResult]];
            result.results = @[stepResult];
            
            NSError *error;
            NSString *identifier = [dataStore addTaskResult:result metadata:@{@"key1": @"resultValue"} error:&error];
            
            XCTAssertNotNil(identifier);
            XCTAssertNil(error, @"");
            XCTAssertFalse([self fileExistAt:samplePath]);
            newItemCount++;
        }
        
        {
            // addData
            NSString *str = @"test_string";
            NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
            
            NSError *error;
            NSString *identifier = [dataStore addData:data metadata:@{@"key": @"dataValue"} error:&error];
            
            XCTAssertNotNil(identifier);
            XCTAssertNil(error, @"");
            newItemCount++;
        }
        
        {
            // addFileURL
            NSError *error;
            NSString *samplePath = [[self basePath] stringByAppendingPathComponent:@"sample.plist"];
            [@{@"sample":@"sample"} writeToFile:samplePath atomically:YES];
            
            NSString *identifier = [dataStore addFileURL:[NSURL fileURLWithPath:samplePath] metadata:@{@"key": @"fileValue"} error:&error];
            
            XCTAssertNotNil(identifier);
            XCTAssertNil(error, @"");
            XCTAssertFalse([self fileExistAt:samplePath]);
            newItemCount++;
        }
        
        {
            // addFileURL: folder
            NSError *error;
            NSString *folderPath = [[self basePath] stringByAppendingPathComponent:@"srcFolder"];
            
            [[NSFileManager defaultManager] createDirectoryAtPath:folderPath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            
            NSString *samplePath1 = [folderPath stringByAppendingPathComponent:@"sample1.plist"];
            [@{@"sample1":@"sample1"} writeToFile:samplePath1 atomically:YES];
            NSString *samplePath2 = [folderPath stringByAppendingPathComponent:@"sample2.plist"];
            [@{@"sample2":@"sample2"} writeToFile:samplePath2 atomically:YES];
            NSString *samplePath3 = [folderPath stringByAppendingPathComponent:@"sample3.plist"];
            [@{@"sample3":@"sample3"} writeToFile:samplePath3 atomically:YES];
            
            NSString *identifier = [dataStore addFileURL:[NSURL fileURLWithPath:folderPath] metadata:@{@"key": @"folderValue"} error:&error];
            
            XCTAssertNotNil(identifier);
            XCTAssertNil(error, @"");
            XCTAssertFalse([self fileExistAt:folderPath]);
            newItemCount++;
        }
        
        __block NSInteger count = 0;
        
        [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL * stop) {
            count++;
            
            XCTAssertNotNil(item, @"");
            XCTAssertNotNil(item.identifier, @"");
            XCTAssertNotNil(item.directoryURL, @"");
            
            NSLog(@"[item = %@", item);
            NSLog(@"identifier = %@", item.identifier);
            NSLog(@"dirURL = %@", item.directoryURL);
            
            if ([item isKindOfClass:[ORKUploadableDataItem class]]) {
                
                ORKUploadableDataItem *dataItem = (ORKUploadableDataItem *)item;
                
                NSLog(@"data = %@", dataItem.data);
                XCTAssertNotNil(dataItem.data, @"");
                
            } else if ([item isKindOfClass:[ORKUploadableFileItem class]]) {
                
                ORKUploadableFileItem *fileItem = (ORKUploadableFileItem *)item;
                
                NSLog(@"file = %@", fileItem.fileURL);
                XCTAssertNotNil(fileItem.fileURL, @"%@", item.identifier);
                XCTAssertTrue([self fileExistAt:fileItem.fileURL.path]);
                
                __block NSInteger filesCount = 0;
                __block NSError *error;
                
                [item enumerateManagedFiles:^(NSURL *fileURL, BOOL *stop) {
                    filesCount++;
                    NSLog(@"====%@", fileURL);
                } error:&error];
                
                XCTAssertGreaterThanOrEqual(filesCount, 1, @"enumerationFailed");
                XCTAssertNil(error);
                
            } else if ([item isKindOfClass:[ORKUploadableResultItem class]]) {
                
                ORKUploadableResultItem *resultItem = (ORKUploadableResultItem *)item;
                
                NSLog(@"result = %@", resultItem.result);
                XCTAssertNotNil(resultItem.result, @"");
                
            }
            
           
            XCTAssertNotNil(item.creationDate, @"");
            NSLog(@"c_date = %@", item.creationDate);
            
            // Test tracker functions
            ORKUploadableItemTracker *tracker = item.tracker;
            
            XCTAssertEqual(tracker.retryCount, 0);
            XCTAssertNil(tracker.lastUploadDate, @"");
            
            [tracker increaseRetryCount];
            XCTAssertNotNil(tracker.lastUploadDate, @"");
            XCTAssertEqual(tracker.retryCount, 1);
            
            XCTAssertFalse(tracker.uploaded);
            
            [tracker markUploaded];
            XCTAssertTrue(tracker.uploaded);
            [tracker increaseRetryCount];
            XCTAssertEqual(tracker.retryCount, 1);
            
            NSLog(@"meta = %@", item.metadata);
            
            XCTAssertNotNil(item.metadata, @"");
            XCTAssertEqual(item.metadata.count, 1);
            
            NSError *error =[item setMetadata:@{@"key1":@"1", @"key2":@"2"}];
            XCTAssertNil(error, @"");
            XCTAssertNotNil(item.metadata, @"");
            XCTAssertEqual(item.metadata.count, 2);
            
            [dataStore removeManagedItemWithIdentifier:item.identifier];
            XCTAssertEqual(tracker.retryCount, 0);
            XCTAssertFalse(tracker.uploaded);
            error = [item setMetadata:@{@"key1":@"1", @"key2":@"2"}];
            XCTAssertNotNil(error, @"");
            
            XCTAssertNil([dataStore managedItemForIdentifier:item.identifier]);
        }
                               exclusion:0
                                 sorting:ORKDataStoreSortingOptionByCreationDate
                               ascending:YES
                                   error:nil];
        
        
        XCTAssertEqual(count, newItemCount);
        XCTAssertEqual(self.delegateCallCount, newItemCount);
        
        // Check if all items are removed
        count = 0;
        [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL * stop) {
            count++;
        }
                               exclusion:0
                                 sorting:0
                               ascending:YES
                                   error:nil];
        
        XCTAssertEqual(count, 0);
        
    }];
}

- (void)testDataStoreWithBadSourceFilePath {
    
    ORKUploadableDataStore *dataStore = [[ORKUploadableDataStore alloc] initWithManagedDirectory: [NSURL fileURLWithPath:[self storePath]]];
    
    {
        // addTaskResult
        ORKTaskResult *taskResult = [[ORKTaskResult alloc] initWithTaskIdentifier:@"abcd"
                                                                      taskRunUUID:[NSUUID UUID]
                                                                  outputDirectory:[NSURL fileURLWithPath:[self basePath]]];
        
        NSString *samplePath1 = [[self basePath] stringByAppendingPathComponent:@"result1.plist"];
        [@{@"sample":@"sample"} writeToFile:samplePath1 atomically:YES];
        
        
        
        NSMutableArray *stepResults = [NSMutableArray array];
        
        {
            ORKFileResult *goodFileResult = [[ORKFileResult alloc] initWithIdentifier:@"file1"];
            goodFileResult.fileURL = [NSURL fileURLWithPath:samplePath1];
            ORKStepResult *stepResult = [[ORKStepResult alloc] initWithStepIdentifier:@"step1" results:@[goodFileResult]];
            [stepResults addObject:stepResult];
        }
    
        
        taskResult.results = [stepResults copy];
        
        
        NSError *error;
        [dataStore addTaskResult:taskResult metadata:@{} error:&error];
        XCTAssertNotNil(error, @"%@", error);
        XCTAssertTrue([self fileExistAt:samplePath1]);
    }
    
    {
        // Add unexist file
        NSString *filePath = [[self basePath] stringByAppendingPathComponent:@"fileNotExist.plist"];
    
        
        NSError *error;
        NSString *identifier = [dataStore addFileURL:[NSURL fileURLWithPath:filePath]
                                            metadata:nil
                                               error:&error];
        
        XCTAssertNotNil(error, @"%@", error);
        XCTAssertNil(identifier, @"%@", error);
    }
    
    {
        // Add unmoveable directory
        NSString *filePath = [self basePath];
        
        
        NSError *error;
        NSString *identifier = [dataStore addFileURL:[NSURL fileURLWithPath:filePath]
                                            metadata:nil
                                               error:&error];
        
        XCTAssertNotNil(error, @"%@", error);
        XCTAssertNil(identifier, @"%@", error);
    }
    
}

- (void)testDataStoreEnumerationSorting {
    
    ORKUploadableDataStore *dataStore = [[ORKUploadableDataStore alloc] initWithManagedDirectory: [NSURL fileURLWithPath:[self storePath]]];
    
    const NSString *kCreationKey = @"c";
    const NSInteger kMaxIndex = 2;
    for (NSInteger index = 0; index <= kMaxIndex; index++) {
        // addTaskResult
        ORKTaskResult *result = [[ORKTaskResult alloc] initWithTaskIdentifier:@"abc" taskRunUUID:[NSUUID UUID] outputDirectory:nil];
        NSError *error;
        [dataStore addTaskResult:result metadata:@{kCreationKey: @(index*10)} error:&error];
        XCTAssertNil(error, @"");
        sleep(1);
    }
    
    NSError *error;
    __block NSInteger enumerateIndex = 0;
    
    // creationIndex : retryCount
    NSDictionary *retryAllocation = @{@(0):@(2), @(10):@(3), @(20): @(1)};
    
    // Test: ORKDataStoreSortingOptionByCreationDate && ascending
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        NSNumber *creationIndex = item.metadata[kCreationKey];
        XCTAssertEqual(creationIndex.integerValue, enumerateIndex * 10);
        enumerateIndex++;
        
        // Apply retry
        
        NSNumber *numberOfRetry = retryAllocation[creationIndex];
        NSInteger count = numberOfRetry.integerValue;
        while (count > 0) {
            [item.tracker increaseRetryCount];
            count--;
        }
        sleep(1);
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:YES
                               error:&error];
    
    
    // Test: ORKDataStoreSortingOptionByCreationDate && decending
    enumerateIndex = kMaxIndex;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        NSNumber *creationIndex = item.metadata[kCreationKey];
        XCTAssertEqual(creationIndex.integerValue, enumerateIndex * 10);
        enumerateIndex--;
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:NO
                               error:&error];
    
    
    // enumerateIndex : creationIndex
    NSDictionary *retryTable = @{@(0):@(20), @(1):@(0), @(2): @(10)};
    
    // Test: ORKDataStoreSortingOptionByRetryCount && ascending
    enumerateIndex = 0;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        
        NSNumber *creationIndex2 = retryTable[@(enumerateIndex)];
        NSNumber *creationIndex = item.metadata[kCreationKey];
        
        
        XCTAssertEqualObjects(creationIndex2, creationIndex);
        enumerateIndex++;
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByRetryCount
                           ascending:YES
                               error:&error];
    
    
    // Test: ORKDataStoreSortingOptionByRetryCount && decending
    enumerateIndex = kMaxIndex;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        
        NSNumber *creationIndex2 = retryTable[@(enumerateIndex)];
        NSNumber *creationIndex = item.metadata[kCreationKey];
        
        
        XCTAssertEqualObjects(creationIndex2, creationIndex);
        enumerateIndex--;
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByRetryCount
                           ascending:NO
                               error:&error];
    
    // Test: ORKDataStoreSortingOptionByLastUploadDate && ascending
    enumerateIndex = 0;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        NSNumber *creationIndex = item.metadata[kCreationKey];
        XCTAssertEqual(creationIndex.integerValue, enumerateIndex * 10);
        enumerateIndex++;
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByLastUploadDate
                           ascending:YES
                               error:&error];
    
    // Test: ORKDataStoreSortingOptionByLastUploadDate && ascending
    enumerateIndex = kMaxIndex;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        NSNumber *creationIndex = item.metadata[kCreationKey];
        XCTAssertEqual(creationIndex.integerValue, enumerateIndex * 10);
        enumerateIndex--;
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByLastUploadDate
                           ascending:NO
                               error:&error];
    
    
}

- (void)testDataStoreEnumerationExclusion {
    
    ORKUploadableDataStore *dataStore = [[ORKUploadableDataStore alloc] initWithManagedDirectory: [NSURL fileURLWithPath:[self storePath]]];
    
    const NSString *kCreationKey = @"c";
    const NSInteger kTotal = 4;
    for (NSInteger index = 0; index < kTotal; index++) {
        // addTaskResult
        ORKTaskResult *result = [[ORKTaskResult alloc] initWithTaskIdentifier:@"abc" taskRunUUID:[NSUUID UUID] outputDirectory:nil];
        NSError *error;
        [dataStore addTaskResult:result metadata:@{kCreationKey: @(index)} error:&error];
        XCTAssertNil(error, @"");
    }
    
    NSError *error;
    // Set values
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        NSNumber *creationIndex = item.metadata[kCreationKey];
        
        if (creationIndex.integerValue%2 == 0) {
            [item.tracker markUploaded];
        }
        
        if (creationIndex.integerValue%2 == 1) {
            [item.tracker increaseRetryCount];
        }
        
    }
                           exclusion:0
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:YES
                               error:&error];
    
    // ORKDataStoreExclusionOptionUploadedItems
    __block NSInteger count = 0;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        XCTAssertFalse(item.tracker.isUploaded);
        count++;
    }
                           exclusion:ORKDataStoreExclusionOptionUploadedItems
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:YES
                               error:&error];
    
    XCTAssertEqual(count, kTotal/2);
    
    // ORKDataStoreExclusionOptionUnuploadedItems
    count = 0;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        XCTAssertTrue(item.tracker.isUploaded);
        count++;
    }
                           exclusion:ORKDataStoreExclusionOptionUnuploadedItems
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:YES
                               error:&error];
    
    XCTAssertEqual(count, kTotal/2);
    
    // ORKDataStoreExclusionOptionTriedItems
    count = 0;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        XCTAssertEqual(item.tracker.retryCount, 0);
        count++;
    }
                           exclusion:ORKDataStoreExclusionOptionTriedItems
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:YES
                               error:&error];
    
    XCTAssertEqual(count, kTotal/2);
    
    // ORKDataStoreExclusionOptionUntriedItems
    count = 0;
    [dataStore enumerateManagedItems:^(ORKUploadableItem *item, BOOL *stop) {
        
        XCTAssertEqual(item.tracker.retryCount, 1);
        count++;
    }
                           exclusion:ORKDataStoreExclusionOptionUntriedItems
                             sorting:ORKDataStoreSortingOptionByCreationDate
                           ascending:YES
                               error:&error];
    
    XCTAssertEqual(count, kTotal/2);
    
}

@end
