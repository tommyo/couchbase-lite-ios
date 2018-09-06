//
//  CBLDatabase+Micro.m
//  CBL ObjC
//
//  Created by Jens Alfke on 9/6/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLDatabase+Micro.h"
#import "CBLDatabase+Internal.h"
#import "CBLCoreBridge.h"
#import "c4MicroSync.h"

@implementation CBLDatabase (Micro)


- (void) pullFromMicroServiceNamed: (NSString*)serviceName
                         intoDocID: (NSString*)docID
{
    c4microsync_start(self.c4db, <#C4String docID#>, <#C4String remoteURL#>, <#C4ReplicatorMode push#>, <#C4ReplicatorMode pull#>)
}

@end
