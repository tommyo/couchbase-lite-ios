//
//  MicroSyncTest.m
//  CBL ObjC Tests
//
//  Created by Jens Alfke on 9/6/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLDatabase+Micro.h"

@interface MicroSyncTest : CBLTestCase
@end


@implementation MicroSyncTest


- (void)testObserve {
    CBLMicroSync* sync = [_db pullFromMicroServiceNamed: @"DemoServer" intoDocID: @"micro"];

    XCTestExpectation* x = [self expectationWithDescription: @"document change"];

    // Add change listener:
    __block int n = 0;
    id block = ^void(CBLDocumentChange* change) {
        CBLDocument* doc = [_db documentWithID: @"micro"];
        Log(@"**** Doc 'micro' counter = %zd", doc[@"counter"].integerValue);
        if (++n == 3)
            [x fulfill];
    };
    id listener = [_db addDocumentChangeListenerWithID: @"micro" listener: block];
    Log(@"Waiting for Micro-synced document to change...");
    [self waitForExpectationsWithTimeout: 20 handler: NULL];
    [_db removeChangeListenerWithToken:listener];

    [sync stop];
}


@end
