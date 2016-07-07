/*
 Copyright (c) 2016, Apple Inc. All rights reserved.
 
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


#import <XCTest/XCTest.h>
#import <ResearchKit/ResearchKit.h>


@interface ORKDataCollectionTests : XCTestCase <ORKDataCollectionManagerDelegate>

@end


@implementation ORKDataCollectionTests {
    XCTestExpectation *_expectation;
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
    NSString *storePath = [basePath stringByAppendingPathComponent:@"managedDataCollectionStore"];
    return storePath;
}

- (NSString *)cleanStorePath {
    NSString *storePath = [self storePath];
    [[NSFileManager defaultManager] removeItemAtPath:storePath error:nil];
    return storePath;
}

static ORKDataCollectionManager *createManagerWithCollecters (NSURL *url,
                                                              ORKMotionActivityCollector **motionCollector,
                                                              ORKHealthCollector **healthCollector,
                                                              ORKHealthCorrelationCollector **healthCorrelationCollector,
                                                              NSError **error) {
    
    ORKDataCollectionManager *manager = [[ORKDataCollectionManager alloc] initWithPersistenceDirectoryURL:url];
    ORKMotionActivityCollector *mac = [manager addMotionActivityCollectorWithStartDate:[NSDate dateWithTimeIntervalSinceNow:-60*60*24] error:error];
    if (motionCollector) {
        *motionCollector = mac;
    }
    
    if (error && *error) {
        return  nil;
    }
    
    HKQuantityType *type = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
    HKUnit *unit = [[HKUnit countUnit] unitDividedByUnit:[HKUnit minuteUnit]];
    ORKHealthCollector *hc = [manager addHealthCollectorWithSampleType:type unit:unit startDate:[NSDate dateWithTimeIntervalSinceNow:-60*60*24] error:error];

    if (healthCollector) {
        *healthCollector = hc;
    }
    
    if (error && *error) {
        return  nil;
    }
    
    HKCorrelationType *correlationType = [HKCorrelationType correlationTypeForIdentifier:HKCorrelationTypeIdentifierBloodPressure];
    ORKHealthCorrelationCollector *hcc = [manager addHealthCorrelationCollectorWithCorrelationType:correlationType
                                                                                                              sampleTypes:@[[HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureDiastolic], [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureSystolic]]
                                                                                                                    units:@[[HKUnit unitFromString:@"mmHg"], [HKUnit unitFromString:@"mmHg"]]
                                                                                                                startDate:[NSDate dateWithTimeIntervalSinceNow:-60*60*24] error:error];
    
    if (healthCorrelationCollector) {
        *healthCorrelationCollector = hcc;
    }
    
    if (error && *error) {
        return  nil;
    }
    
    return manager;
}

- (void)testDataCollectionManager {

    ORKMotionActivityCollector *motionCollector;
    ORKHealthCollector *healthCollector;
    ORKHealthCorrelationCollector *healthCorrelationCollector;
    NSError *error;
    ORKDataCollectionManager *manager = createManagerWithCollecters([NSURL fileURLWithPath:[self cleanStorePath]],
                                                                    &motionCollector,
                                                                    &healthCollector,
                                                                    &healthCorrelationCollector,
                                                                    &error);
    
    XCTAssertNil(error);
    
    XCTAssertEqual(manager.collectors.count, 3);
    
    manager = [[ORKDataCollectionManager alloc] initWithPersistenceDirectoryURL:[NSURL fileURLWithPath:[self storePath]]];
    
    XCTAssertEqual(manager.collectors.count, 3);
    
    [manager removeCollector:motionCollector error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(manager.collectors.count, 2);
    
    [manager removeCollector:healthCollector error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(manager.collectors.count, 1);
    
    [manager removeCollector:healthCorrelationCollector error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(manager.collectors.count, 0);

}

- (void)testCollection {
    
    _expectation = [self expectationWithDescription:@"Expectation for collection completion"];
    
    ORKDataCollectionManager *manager = createManagerWithCollecters([NSURL fileURLWithPath:[self cleanStorePath]],
                                                                    nil,
                                                                    nil,
                                                                    nil,
                                                                    nil);
    
    manager.delegate = self;
  
    [manager startPassiveCollection];
    
    [self waitForExpectationsWithTimeout:1.0 handler:^(NSError *error) {
        XCTAssertNil(error);
    }];
    
}

#pragma mark - delegate

- (BOOL)collector:(ORKCollector *)collector didCollectObjects:(NSArray *)objects {
    return YES;
}

- (void)dataCollectionManagerDidCompleteCollection:(ORKDataCollectionManager *)manager {
    [_expectation fulfill];
}

- (void)collector:(ORKCollector *)collector didFinishWithError:(NSError *)error {

}

@end
