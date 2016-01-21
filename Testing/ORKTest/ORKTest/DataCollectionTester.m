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


#import "DataCollectionTester.h"
#import <HealthKit/HealthKit.h>
#import <ResearchKit/ResearchKit.h>


@interface DataCollectionTester () <ORKDataCollectionManagerDelegate, ORKUploadableDataStoreDelegate>

@end


@implementation DataCollectionTester {
    HKHealthStore *_healthStore;
    ORKDataCollectionManager *_manager;
    ORKUploadableDataStore *_uploadableDataStore;
    NSMutableArray *_heartRateSamples;
    NSMutableArray *_bloodPressureSamples;
    NSMutableArray *_motionActivitySamples;
    NSDateFormatter *_dateFormatter;
    NSDateComponentsFormatter *_dateComponentsFormatter;
    NSDate *_testStartDate;
}

- (void)start {
    if (!_testStartDate) {
        _testStartDate = [NSDate date];
    }
    
    _healthStore = [[HKHealthStore alloc] init];
    
    HKQuantityType *heartRateType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
    HKQuantityType *diastolicType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureDiastolic];
    HKQuantityType *systolicType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureSystolic];
    
    [_healthStore requestAuthorizationToShareTypes:[NSSet setWithObjects:heartRateType, systolicType, diastolicType, nil]
                                         readTypes:[NSSet setWithObjects:heartRateType, systolicType, diastolicType, nil]
                                        completion:^(BOOL success, NSError * _Nullable error) {
#if TARGET_OS_SIMULATOR
                                            
                                            NSDate *d1 = [NSDate dateWithTimeIntervalSinceNow:-10];
                                            NSDate *d2 = [NSDate dateWithTimeIntervalSinceNow:-7];
                                            
                                            HKUnit *hrUnit = [[HKUnit countUnit] unitDividedByUnit:[HKUnit minuteUnit]];
                                            HKQuantity* quantity = [HKQuantity quantityWithUnit:hrUnit doubleValue:(NSInteger)([NSDate date].timeIntervalSinceReferenceDate)%100];
                                            HKQuantitySample *heartRateSample = [HKQuantitySample quantitySampleWithType:heartRateType quantity:quantity startDate:d1 endDate:d2];
                                            
                                            NSString *identifier = HKCorrelationTypeIdentifierBloodPressure;
                                            HKUnit *bpUnit = [HKUnit unitFromString:@"mmHg"];
                                            
                                            HKQuantitySample *diastolicPressure = [HKQuantitySample quantitySampleWithType:diastolicType quantity:[HKQuantity quantityWithUnit:bpUnit doubleValue:70] startDate:d1 endDate:d2];
                                            HKQuantitySample *systolicPressure = [HKQuantitySample quantitySampleWithType:systolicType quantity:[HKQuantity quantityWithUnit:bpUnit doubleValue:110] startDate:d1 endDate:d2];
                                            
                                            HKCorrelation *bloodPressureCorrelation = [HKCorrelation correlationWithType:[HKCorrelationType correlationTypeForIdentifier:identifier] startDate:d1 endDate:d2 objects:[NSSet setWithObjects:diastolicPressure, systolicPressure, nil]];
                                            
                                            [_healthStore saveObjects:@[heartRateSample, bloodPressureCorrelation] withCompletion:^(BOOL success, NSError * _Nullable error) {
                                                NSLog(@"HK sample saving %@ %@", success ? @"success" : @"failed", error);
                                                [self startDataCollection];
                                            }];
                                            
#else
                                            [self startDataCollection];
#endif
                                            
                                        }];
}

- (void)startDataCollection {
    NSURL *url = [NSURL fileURLWithPath:[self.class collectionManagerPath]];
    _manager = [[ORKDataCollectionManager alloc] initWithPersistenceDirectoryURL:url];
    
    if (_manager.collectors.count == 0) {
        NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:-3600];
        NSError *error;
        
        HKQuantityType *heartRateType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
        HKUnit *unit = [[HKUnit countUnit] unitDividedByUnit:[HKUnit minuteUnit]];
        [_manager addHealthCollectorWithSampleType:heartRateType unit:unit startDate:startDate error:&error];
        
        HKCorrelationType *bloodPressureType = [HKCorrelationType correlationTypeForIdentifier:HKCorrelationTypeIdentifierBloodPressure];
        HKQuantityType *diastolicType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureDiastolic];
        HKQuantityType *systolicType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierBloodPressureSystolic];
        HKUnit *bpUnit = [HKUnit unitFromString:@"mmHg"];
        [_manager addHealthCorrelationCollectorWithCorrelationType:bloodPressureType sampleTypes:@[diastolicType, systolicType] units:@[bpUnit, bpUnit] startDate:startDate error:&error];
        
        [_manager addMotionActivityCollectorWithStartDate:startDate error:&error];
    }
    
    _manager.delegate = self;
    [_manager startPassiveCollection];
}

#pragma mark - Delegate

- (BOOL)collector:(ORKCollector *)collector didCollectObjects:(NSArray *)objects {
    NSLog(@"Received %@ %@", @(objects.count), (objects.count? [objects.firstObject class] : nil));
    
    NSArray *serializableObjects = [collector serializableObjectsForObjects:objects];
    NSObject *firstObject = [objects firstObject];
    if ([firstObject isKindOfClass:[HKQuantitySample class]]) {
        [self saveHeartRateSamples:serializableObjects];
    } else if ([firstObject isKindOfClass:[HKCorrelation class]]) {
        [self saveBloodPressureSamples:serializableObjects];
    } else if ([firstObject isKindOfClass:[CMMotionActivity class]]) {
        [self saveMotionActivitySamples:serializableObjects];
    } else {
        NSLog(@"Unexpected type %@", firstObject);
    }
    
    return YES;
}

- (void)collector:(ORKCollector *)collector didFinishWithError:(NSError *)error {
    NSLog(@"%@ didFinishWithError: %@ ", collector, error);
}

- (void)saveHeartRateSamples:(NSArray *)samples {
    if (!_heartRateSamples) {
        _heartRateSamples = [NSMutableArray new];
    }
    [_heartRateSamples addObjectsFromArray:samples];
}

- (void)saveBloodPressureSamples:(NSArray *)samples {
    if (!_bloodPressureSamples) {
        _bloodPressureSamples = [NSMutableArray new];
    }
    [_bloodPressureSamples addObjectsFromArray:samples];
}

- (void)saveMotionActivitySamples:(NSArray *)samples {
    if (!_motionActivitySamples) {
        _motionActivitySamples = [NSMutableArray new];
    }
    [_motionActivitySamples addObjectsFromArray:samples];
}

- (void)dataCollectionManagerDidCompleteCollection:(ORKDataCollectionManager *)manager {
    NSLog(@"dataCollection complete");
    
    if (!_uploadableDataStore) {
        NSURL *url = [NSURL fileURLWithPath:[self.class storePath]];
        NSLog(@"%@", url);
        _uploadableDataStore = [[ORKUploadableDataStore alloc] initWithManagedDirectory:url];
        _uploadableDataStore.delegate = self;
        
    }
    
    if (_bloodPressureSamples) {
        [_uploadableDataStore addData:[NSJSONSerialization dataWithJSONObject:_bloodPressureSamples options:NSJSONWritingPrettyPrinted error:nil]
                             metadata:@{@"date": [NSDate date], @"type": @"blood_pressure"}
                                error:nil];
        _bloodPressureSamples = nil;
    }
    
    if (_heartRateSamples) {
        [_uploadableDataStore addData:[NSJSONSerialization dataWithJSONObject:_heartRateSamples options:NSJSONWritingPrettyPrinted error:nil]
                             metadata:@{@"date": [NSDate date], @"type": @"heart_rate"}
                                error:nil];
        _heartRateSamples = nil;
    }
    
    if (_motionActivitySamples) {
        [_uploadableDataStore addData:[NSJSONSerialization dataWithJSONObject:_motionActivitySamples options:NSJSONWritingPrettyPrinted error:nil]
                             metadata:@{@"date": [NSDate date], @"type": @"motion_activity"}
                                error:nil];
        _motionActivitySamples = nil;
    }
    
    
    NSMutableArray *logs = [NSMutableArray new];
    for (ORKCollector *collector in _manager.collectors) {
        
        NSString *anchor;
        NSString *type;
        if ([collector isKindOfClass:[ORKMotionActivityCollector class]]) {
            ORKMotionActivityCollector *motionActivityCollector = (ORKMotionActivityCollector *)collector;
            if (!_dateFormatter) {
                _dateFormatter = [[NSDateFormatter alloc] init];
                _dateFormatter.timeStyle = NSDateFormatterMediumStyle;
                _dateFormatter.dateStyle = NSDateFormatterShortStyle;
            }
            anchor = [_dateFormatter stringFromDate:motionActivityCollector.lastDate];
            type = @"Motion";
        } else {
            ORKHealthCollector *healthCollector = (ORKHealthCollector *)collector;
            anchor = @(healthCollector.lastAnchor.hash).description;
            type = healthCollector.sampleType.description;
        }

        [logs addObject:@{@"type": type, @"anchor": anchor? : @""}];
    }

    NSString *stateString = @"Unknown";
    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (state == UIApplicationStateBackground) {
        stateString = @"Background";
    } else if (state == UIApplicationStateInactive) {
        stateString = @"Inactive";
    } else if (state == UIApplicationStateActive) {
        stateString = @"Active";
    }
    
    NSTimeInterval secondsSinceStart = [[NSDate date] timeIntervalSinceDate:_testStartDate];
    
    if (_dateComponentsFormatter == nil) {
        _dateComponentsFormatter = [[NSDateComponentsFormatter alloc] init];
        _dateComponentsFormatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute |
        NSCalendarUnitSecond;
        _dateComponentsFormatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorPad;
    }
    
    [_uploadableDataStore addData:[NSJSONSerialization dataWithJSONObject:logs
                                                                  options:NSJSONWritingPrettyPrinted error:nil]
                         metadata:@{@"date": [NSDate date], @"type": [NSString stringWithFormat:@"log - %@ - %@", stateString, [_dateComponentsFormatter stringFromTimeInterval:secondsSinceStart]]}
                            error:nil];
    
}

- (void)dataStore:(ORKUploadableDataStore *)dataStore didReceiveItemWithIdentifier:(NSString *)identifier {
    ORKUploadableItem* item = [dataStore managedItemForIdentifier:identifier];
    
    NSLog(@"didReceiveItem and Uploading ...");
    
    [item.tracker markUploaded];
}

#pragma mark - Path Helpers

+ (NSString *)documentPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
}

+ (NSString *)basePath {
    NSString *testPath = [[self documentPath] stringByAppendingPathComponent:@"test"];
    [[NSFileManager defaultManager] createDirectoryAtPath:testPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return testPath;
}

+ (void)resetTestPath {
    [[NSFileManager defaultManager] removeItemAtPath:[self basePath] error:nil];
}

+ (NSString *)collectionManagerPath {
    NSString *basePath = [self basePath];
    NSString *managerPath = [basePath stringByAppendingPathComponent:@"managedDataCollection"];
    return managerPath;
}

+ (NSString *)storePath {
    NSString *basePath = [self basePath];
    NSString *storePath = [basePath stringByAppendingPathComponent:@"preUploadStore"];
    return storePath;
}

#pragma mark - Other Helpers

+ (ORKUploadableDataStore *)dataStore {
    return [[ORKUploadableDataStore alloc] initWithManagedDirectory:[NSURL fileURLWithPath:[self storePath]]];
}

+ (ORKDataCollectionManager *)collectionManager {
    return [[ORKDataCollectionManager alloc] initWithPersistenceDirectoryURL:[NSURL fileURLWithPath:[self collectionManagerPath]]];
}

@end
