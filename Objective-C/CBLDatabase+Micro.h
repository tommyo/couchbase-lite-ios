//
//  CBLDatabase+Micro.h
//  CBL ObjC
//
//  Created by Jens Alfke on 9/6/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLDatabase.h"

NS_ASSUME_NONNULL_BEGIN


@interface CBLMicroSync : NSObject
- (void) stop;
@end


@interface CBLDatabase (Micro)

- (CBLMicroSync*) pullFromMicroServiceNamed: (nonnull NSString*)serviceName
                                  intoDocID: (nonnull NSString*)docID;

@end

NS_ASSUME_NONNULL_END
