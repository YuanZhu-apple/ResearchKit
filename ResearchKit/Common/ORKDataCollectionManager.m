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


#import "ORKDataCollectionManager_Internal.h"
#import "ORKCollector_Internal.h"
#import "ORKOperation.h"
#import "ORKHelpers.h"
#import <HealthKit/HealthKit.h>


static  NSString *const ORKDataCollectionPersistenceFileName = @".dataCollection.ork.data";

@implementation ORKDataCollectionManager {
    dispatch_queue_t _queue;
    NSOperationQueue *_operationQueue;
    NSString * _Nonnull _managedDirectory;
    NSArray<ORKCollector *> *_collectors;
    HKHealthStore *_healthStore;
    CMMotionActivityManager *_activityManager;
    NSMutableDictionary<HKSampleType *, HKObserverQuery *> *_observerQueries;
    NSMutableArray<HKObserverQueryCompletionHandler> *_completionHandlers;
}

- (instancetype)initWithPersistenceDirectoryURL:(NSURL *)directoryURL {

    self = [super init];
    if (self) {
        if (directoryURL == nil) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"directory cannot be nil" userInfo:nil];
        }
        
        _managedDirectory = directoryURL.path;
        
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
            
            _collectors = [NSArray new];
            [self persistCollectors];
        }
        
        NSString *queueId = [@"ResearchKit.DataCollection." stringByAppendingString:_managedDirectory];
        _queue = dispatch_queue_create([queueId cStringUsingEncoding:NSUTF8StringEncoding], DISPATCH_QUEUE_SERIAL);
        _operationQueue = [[NSOperationQueue alloc] init];
    }
    return self;
}

#pragma mark Data collection

// dispatch_sync, but tries not to deadlock if we're already on the specified queue
static inline void dispatch_sync_if_not_on_queue(dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_queue_set_specific(queue, (__bridge const void *)(queue), (void*)1, NULL);
    if (dispatch_get_specific((__bridge const void *)queue)) {
        block();
    } else {
        dispatch_sync(queue, block);
    }
}

- (void)onWorkQueue:(BOOL (^)(ORKDataCollectionManager *manager))block {
    dispatch_sync_if_not_on_queue(_queue, ^{
        if (block(self)) {
            [self persistCollectors];
        }
    });
}

- (void)onWorkQueueAsync:(BOOL (^)(ORKDataCollectionManager *manager))block {
    dispatch_async(_queue, ^{
        if (block(self)) {
            [self persistCollectors];
        }
    });
}

- (HKHealthStore *)healthStore {
    if (!_healthStore && [HKHealthStore isHealthDataAvailable]){
        _healthStore = [[HKHealthStore alloc] init];
    }
    return _healthStore;
}

- (CMMotionActivityManager *)activityManager {
    if (!_activityManager && [CMMotionActivityManager isActivityAvailable]) {
        _activityManager = [[CMMotionActivityManager alloc] init];
    }
    return _activityManager;
}

- (NSArray<ORKCollector *> *)collectors {
    if (_collectors == nil) {
        _collectors = [NSKeyedUnarchiver unarchiveObjectWithFile:[self persistFilePath]];
        if (_collectors == nil) {
            @throw [NSException exceptionWithName:NSGenericException reason: [NSString stringWithFormat:@"Failed to read from path %@", [self persistFilePath]] userInfo:nil];
        }
    }
    return _collectors;
}

- (NSString * _Nonnull)persistFilePath {
    return [_managedDirectory stringByAppendingPathComponent:ORKDataCollectionPersistenceFileName];
}

- (void)persistCollectors {
    NSArray *collectors = self.collectors;
    
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:collectors];
    NSError *error;
    [data writeToFile:[self persistFilePath] options:NSDataWritingFileProtectionNone error:&error];
    
    if (error) {
        @throw [NSException exceptionWithName:NSGenericException reason: [NSString stringWithFormat:@"Failed to write to path %@", [self persistFilePath]] userInfo:nil];
    }
}

- (void)addCollector:(ORKCollector *)collector {
    NSMutableArray *collectors = [self.collectors mutableCopy];
    [collectors addObject:collector];
    _collectors = [collectors copy];
}

- (ORKHealthCollector *)addHealthCollectorWithSampleType:(HKSampleType*)sampleType unit:(HKUnit *)unit startDate:(NSDate *)startDate error:(NSError* __autoreleasing *)error {
    
    if (!sampleType) {
        @throw [NSException exceptionWithName:ORKInvalidArgumentException reason:@"sampleType cannot be nil" userInfo:nil];
    }
    if (!unit) {
        @throw [NSException exceptionWithName:ORKInvalidArgumentException reason:@"unit cannot be nil" userInfo:nil];
    }
    
    __block ORKHealthCollector *healthCollector = nil;

    [self onWorkQueue:^BOOL(ORKDataCollectionManager *manager){
        
        ORKHealthCollector *collector = [[ORKHealthCollector alloc] initWithSampleType:sampleType unit:unit startDate:startDate];
        [self addCollector:collector];
        healthCollector = collector;
    
        return YES;
    }];
    
    return healthCollector;
}

- (ORKHealthCorrelationCollector *)addHealthCorrelationCollectorWithCorrelationType:(HKCorrelationType *)correlationType
                                                                        sampleTypes:(NSArray<HKSampleType *> *)sampleTypes
                                                                              units:(NSArray<HKUnit *> *)units
                                                                          startDate:(NSDate *)startDate
                                                                              error:(NSError * __autoreleasing *)error {
    if (!correlationType) {
        @throw [NSException exceptionWithName:ORKInvalidArgumentException reason:@"correlationType cannot be nil" userInfo:nil];
    }
    if (![sampleTypes count]) {
        @throw [NSException exceptionWithName:ORKInvalidArgumentException reason:@"sampleTypes cannot be empty" userInfo:nil];
    }
    if ([units count] != [sampleTypes count]) {
        @throw [NSException exceptionWithName:ORKInvalidArgumentException reason:@"units should be same length as sampleTypes" userInfo:nil];
    }
    
    __block ORKHealthCorrelationCollector *healthCorrelationCollector = nil;
    [self onWorkQueue:^BOOL(ORKDataCollectionManager *manager) {
        
        ORKHealthCorrelationCollector *collector = [[ORKHealthCorrelationCollector alloc] initWithCorrelationType:correlationType sampleTypes:sampleTypes units:units startDate:startDate];
        [self addCollector:collector];
        healthCorrelationCollector = collector;
        return YES;
    }];
    
    return healthCorrelationCollector;
}

- (ORKMotionActivityCollector *)addMotionActivityCollectorWithStartDate:(NSDate *)startDate
                                                                  error:(NSError* __autoreleasing *)error {
   
    __block ORKMotionActivityCollector *motionActivityCollector = nil;

    [self onWorkQueue:^BOOL(ORKDataCollectionManager *manager) {
        
        ORKMotionActivityCollector *collector = [[ORKMotionActivityCollector alloc] initWithStartDate:startDate];
        [self addCollector:collector];
        motionActivityCollector = collector;

        return YES;
    }];

    return motionActivityCollector;
}

- (BOOL)removeCollector:(ORKCollector *)collector error:(NSError* __autoreleasing *)error {
    if (!collector) {
        @throw [NSException exceptionWithName:ORKInvalidArgumentException reason:@"collector cannot be nil" userInfo:nil];
    }
    
    __block BOOL success = NO;
    __block NSError *errorOut = nil;
    __weak typeof(self) weakSelf = self;
    [self onWorkQueue:^BOOL(ORKDataCollectionManager *manager) {
        
        NSMutableArray *collectors = [self.collectors mutableCopy];
      
        if (![collectors containsObject:collector]) {
            errorOut = [NSError errorWithDomain:ORKErrorDomain code:ORKErrorObjectNotFound userInfo:@{NSLocalizedFailureReasonErrorKey: @"Cannot find collector."}];
            return NO;
        }
        
        // Stop observer queries
        if ([collector conformsToProtocol:@protocol(ORKHealthCollectable)]) {
            id<ORKHealthCollectable> healthCollectable = (id<ORKHealthCollectable>)collector;
            typeof(self) strongSelf = weakSelf;
            for (HKSampleType *sampleType in healthCollectable.collectableSampleTypes) {
                [strongSelf removeObserverQueryForSampleType:sampleType];
            }
        }
        
        // Remove the collector from the collectors array
        [collectors removeObject:collector];
        _collectors = [collectors copy];
        
        success = YES;
        return YES;
    }];
    
    if (error) {
        *error = errorOut;
    }
    return success;
}

- (void)doCollectionOnce {
    
}

- (void)startWithObserving:(BOOL)observing {
    
    __weak typeof(self) weakSelf = self;
    NSMutableArray<ORKOperation *> *operations = [NSMutableArray array];
    [self onWorkQueueAsync:^BOOL(ORKDataCollectionManager *manager) {
        
        if (_operationQueue.operationCount > 0) {
            ORK_Log_Debug(@"returned due to operation queue is not empty = %@", @(_operationQueue.operationCount));
            return NO;
        }
        
        typeof(self) strongSelf = weakSelf;
        // Create an operation for each collector attached to this study
        for (ORKCollector *collector in self.collectors) {
            
            if ([collector conformsToProtocol:@protocol(ORKHealthCollectable)]) {
                id<ORKHealthCollectable> healthCollectable = (id<ORKHealthCollectable>)collector;
                for (HKSampleType *sampleType in healthCollectable.collectableSampleTypes) {
                    [strongSelf ensureObserverQueryForSampleType:sampleType];
                }
            }
            
            __block ORKOperation *operation = [collector collectionOperationWithManager:self];
            
            // operation could be nil if this type of data collection is not possible
            // on this device.
            if (operation) {
                __block ORKOperation *blockOp = operation;
                
                [operation setCompletionBlock:^{
                    typeof(self) strongSelf = weakSelf;
                    if (blockOp.error) {
                        id<ORKDataCollectionManagerDelegate> delegate = strongSelf.delegate;
                        if (delegate && [delegate respondsToSelector:@selector(collector:didFinishWithError:)]) {
                            [delegate collector:collector didFinishWithError:blockOp.error];
                        }
                    }
                }];
                
                [operations addObject:operation];
            }
            
        }
        
        NSBlockOperation *completionOperation = [NSBlockOperation new];
        [completionOperation addExecutionBlock:^{
            
            typeof(self) strongSelf = weakSelf;
            [strongSelf onWorkQueue:^BOOL(ORKDataCollectionManager *manager) {
                if (_delegate && [_delegate respondsToSelector:@selector(dataCollectionManagerDidCompleteCollection:)]) {
                    [_delegate dataCollectionManagerDidCompleteCollection:self];
                }
                
                for (HKObserverQueryCompletionHandler handler in _completionHandlers) {
                    handler();
                }
                [_completionHandlers removeAllObjects];
                
                return NO;
            }];
        }];
        
        for (NSOperation *operation in operations) {
            [completionOperation addDependency:operation];
        }
        
        ORK_Log_Debug(@"Data Collection queue new operations:\n%@", operations);
        [_operationQueue addOperations:operations waitUntilFinished:NO];
        [_operationQueue addOperation:completionOperation];
        
        // No need to persist collectors
        return NO;
    }];

}

- (void)startPassiveCollection {

}

- (void)ensureObserverQueryForSampleType:(HKSampleType *)sampleType {
    
    if (_observerQueries == nil) {
        _observerQueries = [NSMutableDictionary new];
    }
    
    if (_observerQueries[sampleType] == nil) {
        //Use hourly update for testing
        [[self healthStore] enableBackgroundDeliveryForType:sampleType frequency:HKUpdateFrequencyImmediate withCompletion:^(BOOL success, NSError * _Nullable error) {
            ORK_Log_Debug(@"background delivery: %@ for %@", @(success), sampleType);
        }];
        
        _observerQueries[sampleType] = [[HKObserverQuery alloc] initWithSampleType:sampleType
                                                                         predicate:nil
                                                                     updateHandler:^(HKObserverQuery * _Nonnull query, HKObserverQueryCompletionHandler  _Nonnull completionHandler, NSError * _Nullable error) {
                                                                         if (_completionHandlers == nil) {
                                                                             _completionHandlers = [NSMutableArray new];
                                                                         }
                                                                         [_completionHandlers addObject:completionHandler];
                                                                         ORK_Log_Debug(@"HKObserverQuery wake up for %@", sampleType.identifier);
                                                                         [self startPassiveCollection];
                                                                     }];
        [[self healthStore] executeQuery: _observerQueries[sampleType]];
    }
}

- (void)removeObserverQueryForSampleType:(HKSampleType *)sampleType {
    
    if (_observerQueries[sampleType] != nil) {
        [[self healthStore] stopQuery: _observerQueries[sampleType]];
        [[self healthStore] disableBackgroundDeliveryForType:sampleType withCompletion:^(BOOL success, NSError * _Nullable error) {
            ORK_Log_Debug(@"disableBackgroundDelivery: %@ for %@", @(success), sampleType);
        }];
        [_observerQueries removeObjectForKey:sampleType];
    }
}



@end

