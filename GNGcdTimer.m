//
//  GNGcdTimer.m
//  GodNotes
//
//  Created by 胡沁志 on 2020/7/17.
//  Copyright © 2020 hqz. All rights reserved.
//

#import "GNGcdTimer.h"
#import "GNThreadSafeAccessor.h"

static NSString *const kGNGcdTimerIntervalFileName = @"gnInterval.gcdTimer.hqz.com";
static NSString *const kGNGcdTimerForeverFileName = @"gnForever.gcdTimer.hqz.com";
static NSString *const kGNGcdTimerLastDate = @"gnLastDate.gcdTimer.hqz.com";

#define GcdTimerErrorDomain @"GNGcdErrorDomian"

@interface GNGcdTimer ()
@property (nonatomic,strong) GNThreadSafeAccessor *timerAccessor;
@property (nonatomic,strong) NSMutableDictionary <NSString *, dispatch_source_t> *timers; // 记录定时器
@property (nonatomic,strong) GNThreadSafeAccessor *callbackAccessor;
@property (nonatomic,strong) NSMutableDictionary <NSString *, GNGcdTimerCallBack> *callBacks; // 记录block
@property (nonatomic,strong) GNThreadSafeAccessor *endDateAccessor;
@property (nonatomic,strong) NSMutableDictionary <NSString *, NSDate *> *endDates; // 记录结束时间
@property (nonatomic,strong) GNThreadSafeAccessor *keyForeverAccessor;
@property (nonatomic,strong) NSMutableDictionary <NSString *, NSNumber *> *keyForever; //记录是否为永久定时器
@property (nonatomic,strong) GNThreadSafeAccessor *keyIntervalAccessor;
@property (nonatomic,strong) NSMutableDictionary <NSString *, NSNumber *> *keyInterval; //记录间隔时间
@property (nonatomic,strong) GNThreadSafeAccessor *keyStatusAccessor;
@property (nonatomic,strong) NSMutableDictionary <NSString *, NSNumber *> *keyStatusStack; // 记录是否已暂停  确保suspend 和 resume 成对
@property (nonatomic,strong) NSMutableDictionary <NSString *, NSNumber *> *keyIsContinue; //记录是否是暂停后 重新resume定时器
@end
@implementation GNGcdTimer

static id _instance;
+ (instancetype)shared {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _timerAccessor = [GNThreadSafeAccessor new];
        _callbackAccessor = [GNThreadSafeAccessor new];
        _endDateAccessor = [GNThreadSafeAccessor new];
        _keyForeverAccessor = [GNThreadSafeAccessor new];
        _keyIntervalAccessor = [GNThreadSafeAccessor new];
        _keyStatusAccessor = [GNThreadSafeAccessor new];
        
        _timers = [NSMutableDictionary dictionary];
        _callBacks = [NSMutableDictionary dictionary];
        _endDates = [NSMutableDictionary dictionary];
        _keyStatusStack = [NSMutableDictionary dictionary];
        _keyIsContinue = [NSMutableDictionary dictionary];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[GNGcdTimer GcdTimerIntervalInfo]]) {
            _keyInterval = [[NSMutableDictionary alloc] initWithContentsOfFile:[GNGcdTimer GcdTimerIntervalInfo]];
        } else {
            _keyInterval = [NSMutableDictionary dictionary];
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:[GNGcdTimer GcdTimerForeverInfo]]) {
            _keyForever = [[NSMutableDictionary alloc] initWithContentsOfFile:[GNGcdTimer GcdTimerForeverInfo]];
        } else {
            _keyForever = [NSMutableDictionary dictionary];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForegroundNotification) name:UIApplicationWillEnterForegroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackgroundNotification) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

+ (void)startTimerWithKey:(NSString *)key
                  count:(NSInteger)count
                 interval:(double) interval
                 callBack:(GNGcdTimerCallBack)callback {
    if (interval <= 0) {
        interval = 1.0;
    }
    NSInteger endtime;
    BOOL forEver;
    if (count > 0) {
        endtime= @(interval * count).integerValue;
        forEver = false;
    } else {
        endtime = INT_MAX;
        forEver = true;
    }
    //计算结束时间
    NSTimeInterval endTimeInterval = [[NSDate date] timeIntervalSince1970] + endtime;
    NSDate *endDate = [NSDate dateWithTimeIntervalSince1970:endTimeInterval];
    
    [[GNGcdTimer shared] startTimerWithKey:key endDate:endDate interval:interval callBack:callback forever:forEver];
}

+ (void)pauseTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack{
    [[GNGcdTimer shared]pauseTimerWithKey:key error:errorCallBack];
}

+ (void)continueTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack{
    [[GNGcdTimer shared]continueTimerWithKey:key error:errorCallBack];
}

+ (void)stopTimerWithKey:(NSString *)key{
    
    [[GNGcdTimer shared]handleCallbackWithKey:key circleCount:0 isFinished:YES];
}

+ (BOOL)isFinishedTimerWithKey:(NSString *)key {
    return [[GNGcdTimer shared] isFinishedTimerWithKey:key];
}

- (void)startTimerWithKey:(NSString *)key
                    endDate:(NSDate *)endDate
                 interval:(double) interval
                 callBack:(GNGcdTimerCallBack)callback
                  forever:(BOOL)forever{
    //存储对应key 的时间和block

    [self.endDateAccessor writeWithGCD:^{
        self.endDates[key] = endDate;
    }];
    [self.callbackAccessor writeWithGCD:^{
        self.callBacks[key] = callback;
    }];
    //
    double afterTime = [self offlineContinueWithKey:key];
    
    [self.keyIntervalAccessor writeWithGCD:^{
        self.keyInterval[key] = @(interval);
        [self.keyInterval writeToFile:[GNGcdTimer GcdTimerIntervalInfo] atomically:YES];
    }];
    [self.keyForeverAccessor writeWithGCD:^{
        self.keyForever[key] = @(forever);
        [self.keyForever writeToFile:[GNGcdTimer GcdTimerForeverInfo] atomically:YES];
    }];
    if (afterTime > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(afterTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self launchTimerWithKey:key interval:interval forever:forever];
        });
    }else {
        [self launchTimerWithKey:key interval:interval forever:forever];
    }
}

-(void)continueTimerFromBackGroundWithKey:(NSString *)key
                                 callBack:(GNGcdTimerCallBack)callback
                                 lastDate:(NSDate *)lastDate{
    NSDate *endTime = [self endDateWithKey:key];
    NSNumber *foreverNumber = [_keyForeverAccessor readWithGCD:^id _Nonnull{
        return self.keyForever[key];
    }];
    NSNumber *intervalNum = [_keyIntervalAccessor readWithGCD:^id _Nonnull{
        return self.keyInterval[key];
    }];
    double interval = [intervalNum doubleValue];
    BOOL forever = [foreverNumber boolValue];
    NSDate *nowDate = [NSDate date];
    // 后台时间 / 间隔时间 = 其跑了多少次的循环定时器时间
    NSTimeInterval intervalBack = [nowDate timeIntervalSinceDate:lastDate];
    NSInteger circleCount = intervalBack / interval;

    if (!forever) {
        if (!endTime || [self isExpiredWithEndTime:[endTime timeIntervalSince1970]]) {
            //to do :后台时间 循环次数
            [self handleCallbackWithKey:key circleCount:circleCount isFinished:YES];
            return;
        }
    }
    //等待上一次退出后的剩余打点时间后 调用block 再开始下一次打点定时
    double aftertime = 1 - ((intervalBack / interval) - circleCount);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(aftertime * interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self handleCallbackWithKey:key circleCount:circleCount + 1 isFinished:false];
        [self removeCountDownWithKey:key];
        [self startTimerWithKey:key endDate:endTime interval:interval callBack:callback forever:forever];
    });

}

- (void)launchTimerWithKey:(NSString *)key interval:(double) interval forever:(BOOL)forever{
    dispatch_source_t timer = [self createCountDownTimerWithKey:key interval:interval forever:forever];
    [self.timerAccessor writeWithGCD:^{
        self.timers[key] = timer;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dispatch_resume(self.timers[key]);
    });
}

- (dispatch_source_t) createCountDownTimerWithKey:(NSString *)key interval:(double) interval forever:(BOOL)forever{

    NSDate *endTime = [_endDateAccessor readWithGCD:^id _Nonnull{
        return self.endDates[key];
    }];
    NSTimeInterval endTimeInterval = [endTime timeIntervalSince1970];
    if (!forever) {
        if ([self isExpiredWithEndTime:endTimeInterval]) {
            [self handleCallbackWithKey:key circleCount:1 isFinished:true];
            return nil;
        }
    }

    dispatch_source_t timer;
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, interval * NSEC_PER_SEC, 0);
    __block NSInteger countDown = endTimeInterval - [[NSDate date] timeIntervalSince1970] + 1;
    typeof(self) __weak weakself = self;
    dispatch_source_set_event_handler(timer, ^{
        countDown--;
        BOOL isFinished = countDown <= 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![weakself.keyIsContinue[key] isEqualToNumber:@(1)]) {
                [weakself handleCallbackWithKey:key circleCount:1 isFinished:isFinished];
            } else {
                weakself.keyIsContinue[key] = @(0);
            }
        });
    });
    return timer;
}

- (void)handleCallbackWithKey:(NSString *)key circleCount:(NSInteger)count isFinished:(BOOL)isFinished {
    
    GNGcdTimerCallBack callback = [_callbackAccessor readWithGCD:^id _Nonnull{
        return self.callBacks[key];
    }];
    if (!callback) {
        return;
    }
    callback(count, isFinished);
    [[NSUserDefaults standardUserDefaults]setObject:[NSDate date] forKey:[NSString stringWithFormat:@"%@%@",key,kGNGcdTimerLastDate]];
    if (isFinished) {
        [self removeCountDownWithKey:key];
    }
}

- (void)removeCountDownWithKey:(NSString *)key {
    dispatch_source_t timer = [_timerAccessor readWithGCD:^id _Nonnull{
        return self.timers[key];
    }];
    if (timer != nil){
        [_timerAccessor writeWithGCD:^{
            dispatch_source_cancel(self.timers[key]);
            self.timers[key] = nil;
            [self.timers removeObjectForKey:key];
        }];
    }

    [_callbackAccessor writeWithGCD:^{
        [self.callBacks removeObjectForKey:key];
    }];
    [_endDateAccessor writeWithGCD:^{
        [self.endDates removeObjectForKey:key];
    }];
    [_keyIntervalAccessor writeWithGCD:^{
        [self.keyInterval removeObjectForKey:key];
        [self.keyInterval writeToFile:[GNGcdTimer GcdTimerIntervalInfo] atomically:YES];
    }];
    [_keyForeverAccessor writeWithGCD:^{
        [self.keyForever removeObjectForKey:key];
        [self.keyForever writeToFile:[GNGcdTimer GcdTimerForeverInfo] atomically:YES];

    }];
    [[NSUserDefaults standardUserDefaults]removeObjectForKey:[NSString stringWithFormat:@"%@%@",key,kGNGcdTimerLastDate]];
}

- (BOOL)isFinishedTimerWithKey:(NSString *)key {

    BOOL isFinished = [_timerAccessor readWithGCD:^id _Nonnull{
        return self.timers[key];
    }] == nil;
    return isFinished;
}
// todo ： 需要记录 是否暂停的状态 预防崩溃 + error 放回调
- (void)pauseTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack{
    //1 为暂停 0位继续
    NSNumber *status = [_keyStatusAccessor readWithGCD:^id _Nonnull{
        return self.keyStatusStack[key];
    }];
    dispatch_source_t timer = [_timerAccessor readWithGCD:^id _Nonnull{
        return self.timers[key];
    }];
    if (timer != nil) {
        if ([status isEqual:@(0)] || status == nil) {
            [_timerAccessor writeWithGCD:^{
                dispatch_suspend(self.timers[key]);
            }];
            [_keyStatusAccessor writeWithGCD:^{
                self.keyStatusStack[key] = @(1);
            }];
        } else {
            NSError *error = [NSError errorWithDomain:@"timer isn't paused" code:3001 userInfo:nil];
            errorCallBack(error);
            return;
        }
        errorCallBack(nil);
        return;
    }
    NSError *error = [NSError errorWithDomain:@"timer doesn't exist" code:3002 userInfo:nil];
    errorCallBack(error);
}

- (void)continueTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack{
    id status = [_keyStatusAccessor readWithGCD:^id _Nonnull{
        return self.keyStatusStack[key];
    }];
    dispatch_source_t timer = [_timerAccessor readWithGCD:^id _Nonnull{
        return self.timers[key];
    }];
    if (timer != nil) {
        if ([status isEqual: @(1)]) {
            [_timerAccessor writeWithGCD:^{
                dispatch_resume(self.timers[key]);
                self.keyIsContinue[key] = @(1);
            }];
            [_keyStatusAccessor writeWithGCD:^{
                self.keyStatusStack[key] = @(0);
            }];
        } else {
            NSError *error = [NSError errorWithDomain:@"timer isn't paused" code:3001 userInfo:nil];
            errorCallBack(error);
            return;
        }
        errorCallBack(nil);
        return;
    }
    NSError *error = [NSError errorWithDomain:@"timer doesn't exist" code:3002 userInfo:nil];
    errorCallBack(error);
}

-(void)willEnterForegroundNotification{
    NSDictionary *tempDict = [NSDictionary dictionaryWithDictionary:_callBacks];
    for (NSString *key in tempDict) {
        GNGcdTimerCallBack callBack = _callBacks[key];
        if (!callBack) {
            continue;
        }
        NSDate *lastDate = [[NSUserDefaults standardUserDefaults]objectForKey:[NSString stringWithFormat:@"%@%@",key,kGNGcdTimerLastDate]];
        NSLog(@"enter foreground %@",lastDate);
        if (lastDate == nil) {
            return;
        }
        dispatch_source_t timer = [self.timerAccessor readWithGCD:^id _Nonnull{
               return self.timers[key];
           }];
        if (timer != nil){
            //恢复定时器，并移除
            [_timerAccessor writeWithGCD:^{
                dispatch_resume(self.timers[key]);
                dispatch_source_cancel(self.timers[key]);
                self.timers[key] = nil;
                [self.timers removeObjectForKey:key];
            }];
        }
        //通过最后一次打点记录的时间 来计算时间差 并开启新的定时器
        [self continueTimerFromBackGroundWithKey:key callBack:callBack lastDate:lastDate];

    }
}

-(void)didEnterBackgroundNotification{
    //暂停定时器
    NSDictionary *tempDict = [NSDictionary dictionaryWithDictionary:_endDates];
    for (NSString *key in tempDict) {
        dispatch_source_t timer = [_timerAccessor readWithGCD:^id _Nonnull{
            return self.timers[key];
        }];
        [_timerAccessor writeWithGCD:^{
            dispatch_suspend(self.timers[key]);
        }];
    }

}

-(double)offlineContinueWithKey:(NSString *)key{
    NSDate *lastDate = [[NSUserDefaults standardUserDefaults]objectForKey:[NSString stringWithFormat:@"%@%@",key,kGNGcdTimerLastDate]];
    NSLog(@"enter background lastDate : %@",lastDate);

    if (lastDate == nil){
        return 0;
    }
    NSNumber *intervalNum = [_keyIntervalAccessor readWithGCD:^id _Nonnull{
        return self.keyInterval[key];
    }];
    double interval = [intervalNum doubleValue];
    
    NSDate *nowDate = [NSDate date];
    // 后台时间 / 间隔时间 = 其跑了多少次的循环定时器时间
    NSTimeInterval intervalBack = [nowDate timeIntervalSinceDate:lastDate];
    NSInteger circleCount = intervalBack / interval;
    double aftertime = (1 - ((intervalBack / interval) - circleCount)) * interval;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(aftertime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self handleCallbackWithKey:key circleCount:circleCount + 1 isFinished:false];
    });
    return aftertime;
}

+(NSString*)GcdTimerIntervalInfo {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:kGNGcdTimerIntervalFileName];
}

+(NSString*)GcdTimerForeverInfo {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0] stringByAppendingPathComponent:kGNGcdTimerForeverFileName];
}

-(NSDate *)endDateWithKey:(NSString *)key{
    NSDate *endTime = [_endDateAccessor readWithGCD:^id _Nonnull{
        NSDate *date = self.endDates[key];
        return date;
    }];
    return endTime;
}

- (BOOL)isExpiredWithEndTime:(NSTimeInterval)endTime {
    return [NSDate date].timeIntervalSince1970 >= endTime;
}

@end
