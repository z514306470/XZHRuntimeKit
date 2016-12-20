//
//  XZHProtocolObserverCenter.m
//  XZHRuntimeDemo
//
//  Created by fenqile on 16/12/1.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import "XZHProtocolObserverCenter.h"
#import <objc/runtime.h>
#import "XZHRuntime.h"
#import "NSObject+XZHInvocation.h"

@interface XZHProtocolObserver : NSObject {
    @package
    id          _observer;
    __unsafe_unretained Protocol    *_protocol;
    
    NSUInteger  _methodCnt;
    NSArray     *_methods;
}
@end
@implementation XZHProtocolObserver
- (instancetype)initWithObserver:(id)observer protocol:(Protocol *)protocol {
    if (!observer || !protocol) {return nil;}
    if (self = [super init]) {
        _observer = observer;
        _protocol = protocol;
        _methods = XZHGetMethodListForProtocol(protocol);
        _methodCnt = _methods.count;
    }
    return self;
}
@end

static dispatch_semaphore_t context_semephore = NULL;
@interface XZHProtocolObserverContext : NSObject {
    /**
     *  key >>>> method.name
     *  value >>>> @[observer1, observer2, observer3, ..., observerN]
     */
    NSMutableDictionary *_cache;
}
@end
@implementation XZHProtocolObserverContext
+ (instancetype)context {
    static XZHProtocolObserverContext *_context = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _context = [XZHProtocolObserverContext new];
        _context->_cache = [NSMutableDictionary new];
        context_semephore = dispatch_semaphore_create(1);
    });
    return _context;
}
- (void)saveObserver:(id)object forProtocol:(Protocol *)protocol {
    if (!object || !protocol) {return;}
    __unsafe_unretained NSArray *methods = XZHGetMethodListForProtocol(protocol);
    dispatch_semaphore_wait(context_semephore, DISPATCH_TIME_FOREVER);
    for (NSDictionary *methodDic in methods) {
        NSString *methodName = [methodDic objectForKey:kMethodName];
        NSMutableArray *observers = [_cache objectForKey:methodName];
        if (!observers) {
            observers = [NSMutableArray new];
            [observers addObject:object];
        }
        if (![observers containsObject:object]) {
            [observers addObject:object];
        }
        [_cache setObject:observers forKey:methodName];
    }
    dispatch_semaphore_signal(context_semephore);
}
/**
 *  返回的dic结构
 *  @{
 *      method1 : @[observer1, observer2, observer3],
 *      method2 : @[observer1, observer2, observer3];
 *   }
 */
- (NSDictionary *)getObjectForProtocol:(Protocol *)protocol {
    if (!protocol) {return nil;}
    NSMutableDictionary *allObservers = [NSMutableDictionary new];
    __unsafe_unretained NSArray *methods = XZHGetMethodListForProtocol(protocol);
    dispatch_semaphore_wait(context_semephore, DISPATCH_TIME_FOREVER);
    for (NSDictionary *methodDic in methods) {
        NSString *methodName = [methodDic objectForKey:kMethodName];
        NSArray *observers = [_cache objectForKey:methodName];
        if (observers) {
            [allObservers setObject:observers forKey:methodName];
        }
    }
    dispatch_semaphore_signal(context_semephore);
    return allObservers.copy;
}
- (void)removeObjectForProtocol:(Protocol *)protocol {
    [self removeObject:nil forProtocol:protocol];
}
- (void)removeObject:(id)object forProtocol:(Protocol *)protocol {
    if (!protocol) {return;}
    __unsafe_unretained NSArray *methods = XZHGetMethodListForProtocol(protocol);
    dispatch_semaphore_wait(context_semephore, DISPATCH_TIME_FOREVER);
    for (NSDictionary *methodDic in methods) {
        NSString *methodName = [methodDic objectForKey:kMethodName];
        if (!object) {
            [_cache removeObjectForKey:methodName];
        } else {
            NSMutableArray *observers = [_cache objectForKey:methodName];
            [observers removeObject:object];
            [_cache setObject:observers forKey:methodName];
        }
    }
    dispatch_semaphore_signal(context_semephore);
}
- (void)clean {
    dispatch_semaphore_wait(context_semephore, DISPATCH_TIME_FOREVER);
    [_cache removeAllObjects];
    dispatch_semaphore_signal(context_semephore);
}
@end

static XZHProtocolObserverCenter *_centerInstance;
@implementation XZHProtocolObserverCenter

+ (instancetype)observerCenter {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _centerInstance = [[XZHProtocolObserverCenter alloc] init];
    });
    return _centerInstance;
}

- (void)addObserver:(id)observer forProtocol:(Protocol *)protocol {
    if (![observer conformsToProtocol:protocol]) {return;}
    if (protocol_isEqual(protocol, @protocol(NSObject))) {return;}
    [[XZHProtocolObserverContext context] saveObserver:observer forProtocol:protocol];
}

- (void)notifyObserversForProtocol:(Protocol *)protocol selector:(SEL)sel arguments:(NSArray*)args {
    if (!protocol || !sel) {return;}
    NSDictionary *map = [[XZHProtocolObserverContext context] getObjectForProtocol:protocol];
    NSArray *observers = [map objectForKey:NSStringFromSelector(sel)];
    for (id observer in observers) {
        [observer xzh_performSelector:sel withArgs:args];
    }
}

- (void)removeObserver:(id)observer forProtocol:(Protocol *)protocol {
    if (!protocol) {return;}
    [[XZHProtocolObserverContext context] removeObject:observer forProtocol:protocol];
}

- (void)removeObserverForProtocol:(Protocol *)protocol {
    [[XZHProtocolObserverContext context] removeObjectForProtocol:protocol];
}

- (void)clean {
    [[XZHProtocolObserverContext context] clean];
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _centerInstance = [super allocWithZone:zone];
    });
    return _centerInstance;
}

- (id)copyWithZone:(NSZone *)zone {
    return _centerInstance;
}

@end
