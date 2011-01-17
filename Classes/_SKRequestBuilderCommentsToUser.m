//
//  _SKRequestBuilderCommentsToUser.m
//  StackKit
//
//  Created by Dave DeLong on 1/9/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "_SKRequestBuilderCommentsToUser.h"


@implementation _SKRequestBuilderCommentsToUser

+ (Class) recognizedFetchEntity {
	return [SKComment class];
}

+ (NSDictionary *) recognizedPredicateKeyPaths {
	return [NSDictionary dictionaryWithObjectsAndKeys:
			SK_BOX(NSEqualToPredicateOperatorType, NSInPredicateOperatorType), SKCommentInReplyToUser,
			SK_BOX(NSGreaterThanOrEqualToPredicateOperatorType, NSLessThanOrEqualToPredicateOperatorType), SKCommentCreationDate,
			SK_BOX(NSGreaterThanOrEqualToPredicateOperatorType, NSLessThanOrEqualToPredicateOperatorType), SKCommentScore,
			nil];
}

+ (NSSet *) requiredPredicateKeyPaths {
	return [NSSet setWithObjects:
			SKCommentInReplyToUser,
			nil];
}

+ (NSSet *) recognizedSortDescriptorKeys {
	return [NSSet setWithObjects:
			SKCommentCreationDate,
			SKCommentScore,
			nil];
}

- (void) buildURL {
	NSPredicate * p = [self requestPredicate];
	
	id users = [p constantValueForLeftKeyPath:SKCommentInReplyToUser];
	[self setPath:[NSString stringWithFormat:@"/users/%@/mentioned", SKExtractUserID(users)]];
	[[self query] setObject:SKQueryTrue forKey:SKQueryBody];
	
	SKRange dateRange = [p rangeOfConstantValuesForLeftKeyPath:SKCommentCreationDate];
	if (dateRange.lower != SKNotFound) {
		[[self query] setObject:[NSNumber numberWithUnsignedInteger:dateRange.lower] forKey:SKQueryFromDate];
	}
	if (dateRange.upper != SKNotFound) {
		[[self query] setObject:[NSNumber numberWithUnsignedInteger:dateRange.upper] forKey:SKQueryToDate];
	}
	
	if ([self requestSortDescriptor] != nil && ![[[self requestSortDescriptor] key] isEqual:SKCommentCreationDate]) {
		SKRange sortRange = [p rangeOfConstantValuesForLeftKeyPath:[[self requestSortDescriptor] key]];
		if (sortRange.lower != SKNotFound) {
			[[self query] setObject:[NSNumber numberWithUnsignedInteger:sortRange.lower] forKey:SKQueryMinSort];
		}
		if (sortRange.upper != SKNotFound) {
			[[self query] setObject:[NSNumber numberWithUnsignedInteger:sortRange.upper] forKey:SKQueryMaxSort];
		}
	}
	
	[super buildURL];
}

@end
