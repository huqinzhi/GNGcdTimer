//
//  GNAccessor.h
//  GodNotes
//
//  Created by 胡沁志 on 2020/7/17.
//  Copyright © 2020 hqz. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GNThreadSafeAccessor : NSObject
-(id)readWithGCD:(id(^)(void))readBlock;
-(void)writeWithGCD:(void(^)(void))writeBlock;
@end


NS_ASSUME_NONNULL_END
