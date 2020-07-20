# GNGcdTimer
****
**使用dispatch_source_t实现无限循环计时功能**<br>
首先先说一下场景<br>
由于项目需求要实现检测非联网用户离线(即使应用到后台，或杀死应用，仍然能计算用户上次关闭app到当前启动app之间的时长)总时长除以间隔时长得到的打点次数。<br>
遂写了一个定时工具：<br>
使用:
```
/*<br>
 //启动一个定时器
 @para key:NSString 定时器标识符
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
```
暂停：
```
/*
 暂停 与continue 成对，先pause 才可continue
 */
+ (void)pauseTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack;
```
继续：
```
/*
 继续 与pause成对
 @para key：NSString *
 */
+ (void)continueTimerWithKey:(NSString *)key error:(GNGcdTimerError)errorCallBack;
```
停止：
```
/*
 结束定时器
  @para key：NSString *
 */
+ (void)stopTimerWithKey:(NSString *)key;
```
判断是否停止：
```
/*
 判断计时器是否已经结束(完成)
  @para key：NSString *
 */
+ (BOOL)isFinishedTimerWithKey:(NSString *)key;
```
之前发现调用dispatch_source_t 的dispatch_resume 继续运行定时器时，会直接调用dispatch_source_set_event_handler<br>
****
例子：如果时间间隔为5s，当前定时器运行到3s时暂停，过一会继续启动定时器，按照预期应该时2s之后回调，结果出现调用dispatch_resume后立刻就丢了一个回调回来，过了2s之后又一次回调。以下通过一个状态记录当前是否为恢复继续定时器来解决当前问题。
****
```
    dispatch_source_set_event_handler(timer, ^{
        countDown--;
        BOOL isFinished = countDown <= 0;
        dispatch_async(dispatch_get_main_queue(), ^{
        //这里的变量用来记录当前回调是否时通过恢复定时器触发的，如果是则此时不回调，否则回调
            if (![weakself.keyIsContinue[key] isEqualToNumber:@(1)]) {
                [weakself handleCallbackWithKey:key circleCount:1 isFinished:isFinished];
            } else {
                weakself.keyIsContinue[key] = @(0);
            }
        });
    });
```
整体代码逻辑可能比较复杂，在实现中用到了各种key 和 value 去存储了定时器的各种维度的状态，以下是属性及属性对应的作用（注释）
```
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
```
以上代码中用到的GNThreadSafeAccessor，是为了保证线程读写安全<br>
详细参考另一个类GNThreadSafeAccessor。<br>


使用示例：
```
    __block NSInteger testCount = 0;
    @weakify(self)
    [GNGcdTimer startTimerWithKey:@"mainExKey" count:0 interval:5 callBack:^(NSInteger CircleCount, BOOL finished) {
        @strongify(self)
        if (CircleCount > 0) {
            testCount += CircleCount;
        }
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(11 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @weakify(self)
        [GNGcdTimer pauseTimerWithKey:@"mainExKey" error:^(NSError * _Nullable error) {
            @strongify(self)
            if (error == nil) {
                NSLog(@"定时器暂停");
            } else {
                NSLog(@"%@",error);
            }
        }];
    });
    @weakify(self)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [GNGcdTimer continueTimerWithKey:@"mainExKey" error:^(NSError * _Nullable error) {
            @strongify(self)
            if (error == nil) {
                NSLog(@"定时器继续");
            } else {
                NSLog(@"%@",error);
            }
        }];
    });
```

[github代码连接](https://github.com/huqinzhi/GNGcdTimer)<br>

pod：方式可以直接引入
```
pod 'GNGcdTimer'
```
