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
#import <HealthKit/HealthKit.h>
#import <ResearchKit/ORKErrors.h>
#import <ResearchKit/ORKDefines.h>


@class ORKCollector;
@class ORKHealthCollector;
@class ORKMotionActivityCollector;

ORK_CLASS_AVAILABLE
@interface ORKCollector : NSObject <NSCopying, NSSecureCoding>

- (instancetype)init NS_UNAVAILABLE;

/**
 * @brief identifier to be provided to an uploader.
 *
 */
@property (copy, readonly) NSString *identifier;


/**
 * @brief Serialization helper that produces serialized output.
 *
 * Subclasses should implement to provide a default serialization for upload.
 */
- (NSData *)serializedDataForObjects:(NSArray *)objects;

/**
 * @brief Serialization helper that produces objects suitable for serialization to JSON.
 *
 * Subclasses should implement to provide a default JSON serialization for upload.
 * Called by -serializedDataForObjects:
 */
- (NSArray<NSDictionary *> *)serializableObjectsForObjects:(NSArray *)objects;

@end


ORK_CLASS_AVAILABLE
@interface ORKHealthCollector : ORKCollector

@property (copy, readonly) HKSampleType *sampleType;
@property (copy, readonly) HKUnit *unit;
@property (copy, readonly) NSDate *startDate;

// Last anchor already seen
@property (copy, readonly) HKQueryAnchor *lastAnchor;

@end


ORK_CLASS_AVAILABLE
@interface ORKHealthCorrelationCollector : ORKCollector

@property (copy, readonly) HKCorrelationType *correlationType;
@property (copy, readonly) NSArray<HKSampleType *> *sampleTypes;
@property (copy, readonly) NSArray<HKUnit *> *units;

@property (copy, readonly) NSDate *startDate;

// Last anchor already seen
@property (copy, readonly) HKQueryAnchor *lastAnchor;

@end


ORK_CLASS_AVAILABLE
@interface ORKMotionActivityCollector : ORKCollector

@property (copy, readonly) NSDate *startDate;

// Last date already seen
@property (copy, readonly) NSDate *lastDate;

@end
