//
// Copyright (c) 2017 Emarsys. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface EMSTimestampProvider : NSObject

- (NSNumber *)currentTimeStamp;

- (NSNumber *)timeStampOfDate:(NSDate *)date;

@end