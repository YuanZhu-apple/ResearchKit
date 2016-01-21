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


#import <Foundation/Foundation.h>
#import <ResearchKit/ResearchKit.h>
#import <CoreMotion/CoreMotion.h>


@class ORKCollector;
@class ORKHealthCollector;
@class ORKHealthCorrelationCollector;
@class ORKMotionActivityCollector;
@class ORKDataCollectionManager;

@protocol ORKDataCollectionManagerDelegate <NSObject>

@required
- (BOOL)collector:(ORKCollector *)collector didCollectObjects:(NSArray *)objects;

- (void)dataCollectionManagerDidCompleteCollection:(ORKDataCollectionManager *)manager;

@optional
- (void)collector:(ORKCollector *)collector didFinishWithError:(NSError *)error;

@end


ORK_CLASS_AVAILABLE
@interface ORKDataCollectionManager : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPersistenceDirectoryURL:(NSURL *)directoryURL NS_DESIGNATED_INITIALIZER;

@property (copy, readonly) NSArray<ORKCollector *> *collectors;

@property (nonatomic, weak) id<ORKDataCollectionManagerDelegate> delegate;

/**
 * @brief Add a collector for HealthKit quantity and category samples
 *
 * @param sampleType HealthKit sample type
 *
 * @param unit HealthKit unit into which data should be collected
 *
 * @param startDate Samples should be collected starting at this date
 */
- (ORKHealthCollector *)addHealthCollectorWithSampleType:(HKSampleType *)sampleType
                                                    unit:(HKUnit *)unit
                                               startDate:(NSDate *)startDate
                                                   error:(NSError * __autoreleasing *)error;

/**
 * @brief Add a collector for HealthKit correlations
 *
 * @param correlationType HealthKit correlation type
 *
 * @param sampleTypes Array of HKSampleType expected in the correlation
 *
 * @param units Array of HKUnit to use when serializing the samples collected (should be same size as sampleTypes)
 *
 * @param startDate Samples should be collected starting at this date
 */
- (ORKHealthCorrelationCollector *)addHealthCorrelationCollectorWithCorrelationType:(HKCorrelationType *)correlationType
                                                                        sampleTypes:(NSArray *)sampleTypes units:(NSArray *)units
                                                                          startDate:(NSDate *)startDate
                                                                              error:(NSError * __autoreleasing *)error;

/**
 * @brief Add an RKCMActivityCollector
 *
 * @param startDate     When data collection should start.
   @param error         Error during this operation.
 *
 */
- (ORKMotionActivityCollector *)addMotionActivityCollectorWithStartDate:(NSDate *)startDate
                                                                  error:(NSError* __autoreleasing *)error;

/**
 * @brief Remove the specified collector
 */
- (BOOL)removeCollector:(ORKCollector *)collector error:(NSError* __autoreleasing *)error;

/**
 * @brief Trigger passive data collection
 *
 * This method triggers running all the RKCollector collections associated with
 * the present manager, if needed.
 *
 */
- (void)startPassiveCollection;


- (void)doCollectionOnce;


@end
