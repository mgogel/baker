//
//  IssuesManager.m
//  Baker
//
//  ==========================================================================================
//
//  Copyright (c) 2010-2012, Davide Casali, Marco Colombo, Alessandro Morandi
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification, are
//  permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this list of
//  conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice, this list of
//  conditions and the following disclaimer in the documentation and/or other materials
//  provided with the distribution.
//  Neither the name of the Baker Framework nor the names of its contributors may be used to
//  endorse or promote products derived from this software without specific prior written
//  permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "IssuesManager.h"
#import "BakerIssue.h"
#import "Utils.h"

#import "JSONKit.h"
#import "NSURL+Extensions.h"

@implementation IssuesManager

@synthesize url;
@synthesize issues;
@synthesize shelfManifestPath;

-(id)init {
    self = [super init];

    if (self) {
        #ifdef BAKER_NEWSSTAND
        self.url = [NSURL URLWithString:NEWSSTAND_MANIFEST_URL];
        #endif
        self.issues = nil;

        NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        self.shelfManifestPath = [cachePath stringByAppendingPathComponent:@"shelf.json"];
    }

    return self;
}

#pragma mark - Singleton

+ (IssuesManager *)sharedInstance {
    static dispatch_once_t once;
    static IssuesManager *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#ifdef BAKER_NEWSSTAND
-(BOOL)refresh {
    NSString *json = [self getShelfJSON];

    if (json) {
        NSArray *jsonArr = [json objectFromJSONString];

        [self updateNewsstandIssuesList:jsonArr];

        NSMutableArray *tmpIssues = [NSMutableArray array];
        [jsonArr enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            BakerIssue *issue = [[[BakerIssue alloc] initWithIssueData:obj] autorelease];
            [tmpIssues addObject:issue];
        }];

        self.issues = [tmpIssues sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            NSDate *first = [Utils dateWithFormattedString:[(BakerIssue*)a date]];
            NSDate *second = [Utils dateWithFormattedString:[(BakerIssue*)b date]];
            return [second compare:first];
        }];

        return YES;
    } else {
        return NO;
    }
}

-(NSString *)getShelfJSON {
    NSError *shelfError = nil;
    NSError *cachedShelfError = nil;
    NSString *json = nil;

    NSString *queryString = [NSString stringWithFormat:@"app_id=%@&user_id=%@", [Utils appID], [PurchasesManager UUID]];
    NSURL *shelfURL = [self.url URLByAppendingQueryString:queryString];

    NSURLResponse *response = nil;
    NSURLRequest *request = [NSURLRequest requestWithURL:shelfURL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:REQUEST_TIMEOUT];
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&shelfError];

    if (shelfError) {
        NSLog(@"Error loading Shelf manifest: %@", shelfError);
        if ([[NSFileManager defaultManager] fileExistsAtPath:self.shelfManifestPath]) {
            NSLog(@"Loading cached Shelf manifest from %@", self.shelfManifestPath);
            json = [NSString stringWithContentsOfFile:self.shelfManifestPath encoding:NSUTF8StringEncoding error:&cachedShelfError];
            if (cachedShelfError) {
                NSLog(@"Error loading cached Shelf manifest: %@", cachedShelfError);
            }
        } else {
            NSLog(@"No cached Shelf manifest found at %@", self.shelfManifestPath);
            json = nil;
        }
    } else {
        json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        // Cache the shelf manifest
        [[NSFileManager defaultManager] createFileAtPath:self.shelfManifestPath contents:nil attributes:nil];
        [json writeToFile:self.shelfManifestPath atomically:YES encoding:NSUTF8StringEncoding error:&cachedShelfError];
        if (cachedShelfError) {
            NSLog(@"Error caching Shelf manifest: %@", cachedShelfError);
        } else {
            [Utils addSkipBackupAttributeToItemAtPath:self.shelfManifestPath];
        }
    }

    return json;
}

-(void)updateNewsstandIssuesList:(NSArray *)issuesList {
    NKLibrary *nkLib = [NKLibrary sharedLibrary];

    for (NSDictionary *issue in issuesList) {
        NSDate *date = [Utils dateWithFormattedString:[issue objectForKey:@"date"]];
        NSString *name = [issue objectForKey:@"name"];

        NKIssue *nkIssue = [nkLib issueWithName:name];
        if(!nkIssue) {
            @try {
                nkIssue = [nkLib addIssueWithName:name date:date];
                NSLog(@"added %@ %@", name, date);
            } @catch (NSException *exception) {
                NSLog(@"EXCEPTION %@", exception);
            }

        }
    }
}

-(NSSet *)productIDs {
    NSMutableSet *set = [NSMutableSet set];
    for (BakerIssue *issue in self.issues) {
        if (issue.productID) {
            [set addObject:issue.productID];
        }
    }
    return set;
}

- (BOOL)hasProductIDs {
    return [[self productIDs] count] > 0;
}

- (BakerIssue *)latestIssue {
    return [issues objectAtIndex:0];
}
#endif

+ (NSArray *)localBooksList {
    NSMutableArray *booksList = [NSMutableArray array];
    NSFileManager *localFileManager = [NSFileManager defaultManager];
    NSString *booksDir = [[NSBundle mainBundle] pathForResource:@"books" ofType:nil];

    NSArray *dirContents = [localFileManager contentsOfDirectoryAtPath:booksDir error:nil];
    for (NSString *file in dirContents) {
        NSString *manifestFile = [booksDir stringByAppendingPathComponent:[file stringByAppendingPathComponent:@"book.json"]];
        if ([localFileManager fileExistsAtPath:manifestFile]) {
            BakerBook *book = [[[BakerBook alloc] initWithBookPath:[booksDir stringByAppendingPathComponent:file] bundled:YES] autorelease];
            BakerIssue *issue = [[[BakerIssue alloc] initWithBakerBook:book] autorelease];
            [booksList addObject:issue];
        } else {
            NSLog(@"CANNOT FIND MANIFEST %@", manifestFile);
        }
    }

    return [NSArray arrayWithArray:booksList];
}

-(void)dealloc {
    [issues release];
    [url release];
    [shelfManifestPath release];

    [super dealloc];
}

@end
