//
//  GNAccessor.m
//  GodNotes
//
//  Created by 胡沁志 on 2020/7/17.
//  Copyright © 2020 hqz. All rights reserved.
//

#import "GNThreadSafeAccessor.h"

@interface GNThreadSafeAccessor ()
@property(nonatomic,strong) dispatch_queue_t syncQueue;
@end


@implementation GNThreadSafeAccessor
//并发同步队列
-(instancetype)init{
    self = [super init];
    if (self != nil) {
        _syncQueue = dispatch_queue_create("accessor", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

-(id)readWithGCD:(id(^)(void))readBlock{
    __block id readValue = nil;
    dispatch_sync(_syncQueue, ^{
        readValue = readBlock();
    });
    return readValue;
}

-(void)writeWithGCD:(void(^)(void))writeBlock{
    dispatch_barrier_async(_syncQueue, writeBlock);
}


@end

