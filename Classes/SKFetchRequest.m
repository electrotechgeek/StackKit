//
//  SKFetchRequest.m
//  StackKit
//
//  Created by Dave DeLong on 3/29/10.
//  Copyright 2010 Home. All rights reserved.
//
#import "StackKit_Internal.h"
#import <objc/runtime.h>

@implementation SKFetchRequest
@synthesize entity;
@synthesize sortDescriptors;
@synthesize fetchLimit;
@synthesize fetchOffset;
@synthesize predicate;
@synthesize error;
@synthesize delegate;

NSString * SKErrorResponseKey = @"error";
NSString * SKErrorCodeKey = @"code";
NSString * SKErrorMessageKey = @"message";

- (id) initWithSite:(SKSite *)aSite {
	if (self = [super initWithSite:aSite]) {
		fetchLimit = 0;
		fetchOffset = 0;
	}
	return self;
}

- (id) init {
	return [self initWithSite:nil];
}

- (void) dealloc {
	[sortDescriptors release];
	[predicate release];
	[error release];
	[super dealloc];
}

+ (NSArray *) validFetchEntities {
	return [NSArray arrayWithObjects:
			[SKUser class],
			[SKUserActivity class],
			[SKTag class], 
			[SKBadge class], 
			[SKQuestion class], 
			[SKAnswer class], 
			[SKComment class], 
			nil];
}

- (NSPredicate *) cleanedPredicate {
	//TODO: clean the predicate.  replace left expressions as appropriate
	return [self predicate];
}

- (NSArray *) cleanedSortDescriptors {
	//evaluate the sort descriptors.  error if there are non-supported keys, comparators, or selectors, and replace keys as appropriate
	NSDictionary * validSortKeys = [[self entity] validSortDescriptorKeys];
	
	NSMutableArray * cleaned = [NSMutableArray array];
	for (NSSortDescriptor * sort in [self sortDescriptors]) {
		NSString * sortKey = [sort key];
		NSString * cleanedKey = [validSortKeys objectForKey:sortKey];
		if (cleanedKey == nil) {
			NSString * msg = [NSString stringWithFormat:@"%@ is not a valid sort key", sortKey];
			[self setError:[NSError errorWithDomain:SKErrorDomain code:SKErrorCodeInvalidSort userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]]];
			return nil;
		}
		
		//use respondsTo... and perform... so that this will still work on 10.5
		if ([sort respondsToSelector:@selector(comparator)]) {
			id comparator = [sort performSelector:@selector(comparator)];
			if (comparator != nil) {
				NSString * msg = @"Sort descriptors may not use comparator blocks";
				[self setError:[NSError errorWithDomain:SKErrorDomain code:SKErrorCodeInvalidSort userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]]];
				return nil;
			}
		}
		
		SEL comparisonSelector = [sort selector];
		if (comparisonSelector == nil || sel_isEqual(comparisonSelector, @selector(compare:)) == NO) {
			NSString * msg = @"Sort descriptors may only sort using the compare: selector";
			[self setError:[NSError errorWithDomain:SKErrorDomain code:SKErrorCodeInvalidSort userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]]];
			return nil;
		}
		
		NSSortDescriptor * newDescriptor = [[NSSortDescriptor alloc] initWithKey:cleanedKey ascending:[sort ascending] selector:[sort selector]];
		[cleaned addObject:newDescriptor];
		[newDescriptor release];
	}
	
	return cleaned;
}

- (NSURL *) apiCall {
	if ([self site] == nil) { return nil; }
	
	Class fetchEntity = [self entity];
	if ([[[self class] validFetchEntities] containsObject:fetchEntity] == NO) {
		//invalid entity
		NSString * msg = [NSString stringWithFormat:@"%@ is not a valid fetch entity", fetchEntity];
		NSDictionary * userInfo = [NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey];
		[self setError:[NSError errorWithDomain:SKErrorDomain code:SKErrorCodeInvalidEntity userInfo:userInfo]];
		return nil;
	}
	
	if ([self predicate] != nil) {
		NSPredicate * cleanedPredicate = [self cleanedPredicate];
		if (cleanedPredicate == nil) {
			//invalid predicate.  error set in cleanedPredicate
			return nil;
		}
		[self setPredicate:cleanedPredicate];
	}
	
	if ([self sortDescriptors] != nil) {
		NSArray * cleanedSortDescriptors = [self cleanedSortDescriptors];
		if (cleanedSortDescriptors == nil) {
			//invalid sorting.  error set in cleanedSortDescriptors
			return nil;
		}
		[self setSortDescriptors:cleanedSortDescriptors];
	}
	
	return [fetchEntity apiCallForFetchRequest:self];
}

- (void) executeAsynchronously {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSArray * results = [self execute];
	
	if ([self error] != nil) {
		//ERROR!
		if ([self delegate] && [[self delegate] respondsToSelector:@selector(fetchRequest:didFailWithError:)]) {
			[[self delegate] fetchRequest:self didFailWithError:[self error]];
		}
	} else {
		//OK
		if ([self delegate] && [[self delegate] respondsToSelector:@selector(fetchRequest:didReturnResults:)]) {
			[[self delegate] fetchRequest:self didReturnResults:results];
		}
	}
	
	[pool release];
}

- (NSArray *) execute {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	NSMutableArray * objects = nil;
	
	//construct our fetch url
	NSURL * fetchURL = [self apiCall];
	
	SKLog(@"fetching from: %@", fetchURL);
	
	if ([self error] != nil) { goto cleanup; }
	if (fetchURL == nil) { goto cleanup; }
	
	//signal the delegate
	if ([self delegate] && [[self delegate] respondsToSelector:@selector(fetchRequestWillBeginExecuting:)]) {
		[[self delegate] fetchRequestWillBeginExecuting:self];
	}
	
	//execute the GET request
	NSURLRequest * urlRequest = [NSURLRequest requestWithURL:fetchURL];
	NSURLResponse * response = nil;
	NSError * connectionError = nil;
	NSData * data = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:&connectionError];
	
	//signal the delegate
	if ([self delegate] && [[self delegate] respondsToSelector:@selector(fetchRequestDidFinishExecuting:)]) {
		[[self delegate] fetchRequestDidFinishExecuting:self];
	}
	
	if (connectionError != nil) {
		[self setError:connectionError];
		goto cleanup;
	}
	
	//handle the response
	NSString * responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	
	//TODO: FIX THIS
	NSDictionary * responseObjects = [responseString JSONValue];
	assert([responseObjects isKindOfClass:[NSDictionary class]]);
	assert([[responseObjects allKeys] count] == 1);
	
	//check for an error in the response
	NSDictionary * errorDictionary = [responseObjects objectForKey:SKErrorResponseKey];
	if (errorDictionary != nil) {
		//there was an error responding to the request
		NSNumber * errorCode = [errorDictionary objectForKey:SKErrorCodeKey];
		NSString * errorMessage = [errorDictionary objectForKey:SKErrorMessageKey];
		
		NSDictionary * userInfo = [NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey];
		[self setError:[NSError errorWithDomain:SKErrorDomain code:[errorCode integerValue] userInfo:userInfo]];
		goto cleanup;
	}
	
	//pull out the data container
	id dataObject = [responseObjects objectForKey:[[responseObjects allKeys] objectAtIndex:0]];
	
	objects = [[NSMutableArray alloc] init];	
	
	//parse the response into objects
	if ([dataObject isKindOfClass:[NSArray class]]) {
		for (NSDictionary * dataDictionary in dataObject) {
			SKObject * object = [[self entity] objectWithSite:[self site] dictionaryRepresentation:dataDictionary];
			[objects addObject:object];
		}
	} else if ([dataObject isKindOfClass:[NSDictionary class]]) {
		SKObject * object = [[self entity] objectWithSite:[self site] dictionaryRepresentation:dataObject];
		[objects addObject:object];
	}
	
cleanup:
	[pool release];
	return [objects autorelease];
}

- (void) setFetchLimit:(NSUInteger)newLimit {
	if (newLimit > SKPageSizeLimitMax) {
		newLimit = SKPageSizeLimitMax;
	}
	fetchLimit = newLimit;
}

@end
