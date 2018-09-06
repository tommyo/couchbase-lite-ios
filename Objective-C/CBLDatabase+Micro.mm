//
//  CBLDatabase+Micro.mm
//  CBL ObjC
//
//  Created by Jens Alfke on 9/6/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLDatabase+Micro.h"
#import "CBLDatabase+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "c4MicroSync.h"


@implementation CBLMicroSync
{
    C4MicroSync* _sync;
}

- (instancetype)initWithDB: (C4Database*)c4db
               serviceName: (NSString*)serviceName
                     docID: (NSString*)docID
{
    self = [super init];
    if (self) {
        _sync = c4microsync_start(c4db, CBLStringBytes(docID), CBLStringBytes(serviceName),
                                  kC4Disabled, kC4OneShot);

    }
    return self;
}

- (void) stop {
    if (_sync) {
        c4microsync_stop(_sync);
        c4microsync_free(_sync);
        _sync = nullptr;
    }
}

- (void) dealloc {
    [self stop];
}

@end



@implementation CBLDatabase (Micro)


- (CBLMicroSync*) pullFromMicroServiceNamed: (NSString*)serviceName
                                  intoDocID: (NSString*)docID
{
    return [[CBLMicroSync alloc] initWithDB: self.c4db serviceName: serviceName docID: docID];
}

@end
