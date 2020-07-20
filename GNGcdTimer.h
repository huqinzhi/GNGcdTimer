//
//  GNGcdTimer.h
//  GodNotes
//
//  Created by 胡沁志 on 2020/7/17.
//  Copyright © 2020 hqz. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN
typedef void(^GNGcdTimerCallBack)(NSInteger CircleCount, BOOL finished);
typedef void(^GNGcdTimerError)(NSError * _Nullable error);

@interface GNGcdTimer : NSObject

/*
 //启动一个定时器
 @para key:NSString *
 @para count:循环次数  0是无限循环(除非手动停止，否则相当于无限计算其key对应的定时器的间隔时间)
 @para interval：循环时间间隔
 @para callback：循环打点block
                circleCount:一段时间内 循环打点几次
                
 interval 为1 或者0 循环次数可以当做每隔一秒 打点一次
 */
+ (void)startTimerWithKey:(NSString *)key
                    count:(NSInteger)count
                 interval:(double) interval
                 callBack:(GNGcdTimerCallBack)callback;
/*
 继续 与pause成对
 @para key：NSString *
 */
+ (void)continueTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack;
/*
 暂停 与continue 成对，先pause 才可continue
 */
+ (void)pauseTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack;
/*
 结束定时器
  @para key：NSString *
 */
+ (void)stopTimerWithKey:(NSString *)key;

/*
 判断计时器是否已经结束(完成)
  @para key：NSString *
 */
+ (BOOL)isFinishedTimerWithKey:(NSString *)key;


@end

NS_ASSUME_NONNULL_END
