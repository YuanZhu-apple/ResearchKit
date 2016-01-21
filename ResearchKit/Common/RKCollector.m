//
//  RKCollector.m
//  ResearchKit
//
//  Copyright (c) 2014 Apple. All rights reserved.
//

#import "RKCollector.h"
#import "RKCollector_Internal.h"
#import "ORKHelpers.h"
#import "RKUploader.h"
#import "HKSample+ORKJSONDictionary.h"
#import "CMMotionActivity+ORKJSONDictionary.h"
#import "RKHealthSampleQueryOperation.h"
#import "RKMotionActivityQueryOperation.h"
#import "RKStudy_Internal.h"

#import <CoreMotion/CoreMotion.h>

static NSString *const kRKItemsKey = @"items";

@implementation RKCollector

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        ORK_DECODE_OBJ_CLASS(aDecoder, identifier, NSString);
        ORK_DECODE_OBJ_CLASS(aDecoder, uploader, RKUploader);
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    ORK_ENCODE_OBJ(aCoder, identifier);
    ORK_ENCODE_OBJ(aCoder, uploader);
}


- (RKOperation*)_collectionOperationWithStudy:(RKStudy*)study
{
    ORKThrowMethodUnavailableException();
    return nil;
}


- (instancetype)_initWithIdentifier:(NSString *)identifier
{
    self = [super init];
    if (self)
    {
        _identifier = identifier;
    }
    return self;
}


-(NSData*)serializedDataForObjects:(NSArray*)objects
{
    // Expect an array of CMMotionActivity objects
    
    NSDictionary *output = @{ kRKItemsKey : [self serializableObjectsForObjects:objects] };
    
    NSError *localError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:output
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&localError];
    if (!jsonData)
    {
        [NSException raise:NSInternalInconsistencyException format:@"Error serializing objects to JSON: %@", [localError localizedDescription]];
        return nil;
    }
    
    return jsonData;
}


- (NSArray *)serializableObjectsForObjects:(NSArray *)objects
{
    ORKThrowMethodUnavailableException();
    return nil;
}

@end

@implementation RKHealthCollector : RKCollector


- (instancetype)_initWithSampleType:(HKSampleType*)sampleType unit:(HKUnit*)unit startDate:(NSDate*)startDate
{
    NSString *itemIdentifier = [NSString stringWithFormat:@"com.apple.healthkit.%@.%@",sampleType.identifier,unit.unitString];
    self = [super _initWithIdentifier:itemIdentifier];
    if (self)
    {
        _sampleType = sampleType;
        _unit = unit;
        _startDate = startDate;
    }
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        ORK_DECODE_OBJ(aDecoder, sampleType);
        ORK_DECODE_OBJ(aDecoder, unit);
        ORK_DECODE_OBJ(aDecoder, startDate);
        ORK_DECODE_OBJ(aDecoder, lastAnchor);
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    
    ORK_ENCODE_OBJ(aCoder, sampleType);
    ORK_ENCODE_OBJ(aCoder, unit);
    ORK_ENCODE_OBJ(aCoder, startDate);
    ORK_ENCODE_OBJ(aCoder, lastAnchor);
}



- (NSArray *)serializableObjectsForObjects:(NSArray *)objects
{
    NSMutableArray *elements = [NSMutableArray arrayWithCapacity:[objects count]];
    for (HKSample *sample in objects)
    {
        [elements addObject:[sample ork_JSONDictionaryWithOptions:(ORKSampleJSONOptions)(ORKSampleIncludeMetadata|ORKSampleIncludeSource|ORKSampleIncludeUUID) unit:self.unit]];
    }
    
    return elements;
}

- (RKOperation*)_collectionOperationWithStudy:(RKStudy*)study
{
    if (! [HKHealthStore isHealthDataAvailable])
    {
        return nil;
    }
    
    return [[RKHealthSampleQueryOperation alloc] initWithCollector:self study:study];
}

- (NSArray *)_collectableSampleTypes
{
    return @[_sampleType];
}

- (BOOL)_queue_reportResults:(NSArray *)results forAnchor:(NSNumber *)anchor toStudy:(RKStudy *)study
{
    BOOL success = NO;
    id<RKStudyDelegate> delegate = study.delegate;
    RKStudyStore *studyStore = study.studyStore;
    BOOL canSend = [studyStore.studies containsObject:study] &&
        [study.collectors containsObject:self] && (delegate != nil);
    
    if (!canSend)
    {
        delegate = nil;
    }
    success = [delegate study:study healthCollector:self anchor:anchor didCollectObjects:results];
    return success;
}


@end

@implementation RKHealthCorrelationCollector : RKCollector


- (instancetype)_initWithCorrelationType:(HKCorrelationType *)correlationType sampleTypes:(NSArray *)sampleTypes units:(NSArray *)units startDate:(NSDate *)startDate
{
    NSString *itemIdentifier = [NSString stringWithFormat:@"com.apple.healthkit.%@",correlationType.identifier];
    self = [super _initWithIdentifier:itemIdentifier];
    if (self)
    {
        _correlationType = correlationType;
        _sampleTypes = sampleTypes;
        _units = units;
        _startDate = startDate;
    }
    return self;
}


-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        ORK_DECODE_OBJ(aDecoder, correlationType);
        ORK_DECODE_OBJ(aDecoder, sampleTypes);
        ORK_DECODE_OBJ(aDecoder, units);
        ORK_DECODE_OBJ(aDecoder, startDate);
        ORK_DECODE_OBJ(aDecoder, lastAnchor);
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    
    ORK_ENCODE_OBJ(aCoder, correlationType);
    ORK_ENCODE_OBJ(aCoder, sampleTypes);
    ORK_ENCODE_OBJ(aCoder, units);
    ORK_ENCODE_OBJ(aCoder, startDate);
    ORK_ENCODE_OBJ(aCoder, lastAnchor);
}

- (HKSampleType *)sampleType
{
    return _correlationType;
}


- (NSArray *)_collectableSampleTypes
{
    return self.sampleTypes;
}


- (NSArray *)serializableObjectsForObjects:(NSArray *)objects
{
    NSMutableArray *elements = [NSMutableArray arrayWithCapacity:[objects count]];
    for (HKCorrelation *correlation in objects)
    {
        [elements addObject:[correlation ork_JSONDictionaryWithOptions:(ORKSampleJSONOptions)(ORKSampleIncludeMetadata|ORKSampleIncludeSource|ORKSampleIncludeUUID) sampleTypes:self.sampleTypes units:self.units]];
    }
    
    return elements;
}

- (RKOperation*)_collectionOperationWithStudy:(RKStudy*)study
{
    if (! [HKHealthStore isHealthDataAvailable])
    {
        return nil;
    }
    
    return [[RKHealthSampleQueryOperation alloc] initWithCollector:self study:study];
}


- (BOOL)_queue_reportResults:(NSArray *)results forAnchor:(NSNumber *)anchor toStudy:(RKStudy *)study
{
    BOOL success = NO;
    id<RKStudyDelegate> delegate = study.delegate;
    RKStudyStore *studyStore = study.studyStore;
    BOOL canSend = [studyStore.studies containsObject:study] &&
    [study.collectors containsObject:self] && (delegate != nil);
    
    if (!canSend)
    {
        delegate = nil;
    }
    success = [delegate study:study healthCorrelationCollector:self anchor:anchor didCollectObjects:results];
    return success;
}



@end


@implementation RKMotionActivityCollector : RKCollector

-(instancetype)_initWithStartDate:(NSDate *)startDate
{
    NSString *itemIdentifier = [NSString stringWithFormat:@"com.apple.coremotion.activity"];
    self = [super _initWithIdentifier:itemIdentifier];
    if (self)
    {
        _startDate = startDate;
    }
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        ORK_DECODE_OBJ(aDecoder, startDate);
        ORK_DECODE_OBJ(aDecoder, lastDate);
    }
    return self;
}

-(void)encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    ORK_ENCODE_OBJ(aCoder, startDate);
    ORK_ENCODE_OBJ(aCoder, lastDate);
}


- (NSArray *)serializableObjectsForObjects:(NSArray *)objects
{
    NSMutableArray *elements = [NSMutableArray arrayWithCapacity:[objects count]];
    for (CMMotionActivity *activity in objects)
    {
        [elements addObject:[activity ork_JSONDictionary]];
    }
    
    return elements;
}

- (RKOperation*)_collectionOperationWithStudy:(RKStudy*)study
{
    if (! [CMMotionActivityManager isActivityAvailable])
    {
        return nil;
    }
    
    return [[RKMotionActivityQueryOperation alloc] initWithCollector:self study:study queryQueue:nil];
}


@end


