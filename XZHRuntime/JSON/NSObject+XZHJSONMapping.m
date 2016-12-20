//
//  NSObject+XZHJSONMapping.m
//  XZHRuntimeDemo
//
//  Created by XiongZenghui on 16/9/11.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import "NSObject+XZHJSONMapping.h"
#import <objc/message.h>
#import "XZHRuntime.h"

/**
 *  属性映射jsonkey的类型
 */
typedef NS_ENUM(NSInteger, XZHPropertyMappedToJsonKeyType) {
    /**
     *  映射的jsonkey
     */
    XZHPropertyMappedToJsonKeyTypeSimple             = 1,
    /**
     *  带有路径的jsonkey
     */
    XZHPropertyMappedToJsonKeyTypeKeyPath,
    /**
     *  映射多个jsonkey
     */
    XZHPropertyMappedToJsonKeyTypeKeyArray,
};

@class XZHPropertyMapper;

typedef struct XZHJsonToModelContext {
    void *model;
    void *classMapper;
    void *jsonDic;
}XZHJsonToModelContext;

typedef struct XZHModelToJsonContext {
    void *model;
    void *jsonDic;
}XZHModelToJsonContext;

static xzh_force_inline NSDateFormatter* XZHDateFormatter(__unsafe_unretained NSString *dateFormat);

static xzh_force_inline NSDictionary* XZHJSONStringToDic(__unsafe_unretained NSString *jsonString);

static xzh_force_inline NSNumber* XZHNumberWithValue(__unsafe_unretained id value);

static xzh_force_inline NSNumber* XZHGetNSNumberFromProperty(__unsafe_unretained id object, __unsafe_unretained XZHPropertyMapper *mapper);

static void XZHSetFoundationObjectToProperty(__unsafe_unretained id jsonItemValue, __unsafe_unretained id model, __unsafe_unretained XZHPropertyMapper *propertyMapper);

static void XZHJsonToModelDicApplierFunction(const void *jsonKey, const void *jsonItemValue, void *context);

static void XZHJsonToModelArrayApplierFunction(const void *value, void *context);

static id XZHConvertModelToAbleJSONSerialization(id object);

static void XZHConvertModelToJSONApplierFunction(const void *mappedToKey, const void *propertyMapper, void *context);

@interface XZHPropertyMapper : NSObject {
    @package
    __unsafe_unretained XZHPropertyModel            *_property;
    
    Class                       _generacCls;                // 属性所在类的Class
    Class                       _ivarClass;                 // 属性变量Ivar的类型Class
    Class                       _containerCls;              // 容器属性变量为容器类型（Array、Dic、Set）时，其内部子对象的Class
    
    XZHTypeEncoding             _typeEncoding;              // Ivar的类型编码枚举值
    NSString                    *_ivarEncodingString;       // Ivar的类型编码字符串
    XZHFoundationType           _foundationType;            // Ivar的Foundation类型
    
    BOOL                        _isCNumber;
    BOOL                        _isFoundationObject;
    BOOL                        _isNSNumber;
    
    BOOL                        _isGetterAccess;
    BOOL                        _isSetterAccess;
    
    XZHPropertyMappedToJsonKeyType _mappedType;
    NSString                    *_mappedToSimpleKey;
    NSString                    *_mappedToKeyPath;
    NSArray                     *_mappedToKeyArray;
    XZHPropertyMapper           *_next;
}
@end
@implementation XZHPropertyMapper

- (instancetype)initWithPropertyModel:(XZHPropertyModel *)property containerCls:(Class)containerCls generacCls:(Class)generacCls{
    if (self = [super init]) {
        _property = property;
        _ivarClass = property.cls;
        _generacCls = generacCls;
        _typeEncoding = property.typeEncoding;
        _ivarEncodingString = property.ivarEncodingString;
        _foundationType = property.foundationType;
        _isCNumber = property.isCNumber;
        _isNSNumber = (XZHFoundationTypeNSNumber == _foundationType) || (XZHFoundationTypeNSDecimalNumber == _foundationType);
        _containerCls = containerCls;
        _isSetterAccess = property.isSetterAccess;
        _isGetterAccess = property.isGetterAccess;
    }
    return self;
}

@end

@interface XZHClassMapper : NSObject {
    @package
    __unsafe_unretained XZHClassModel                      *_classModel;
    
    CFMutableDictionaryRef              _jsonKeyPropertyMapperDic;
    CFMutableDictionaryRef              _objectInArrayClassDic;
    CFMutableArrayRef                  _allPropertyMappers;
    CFMutableArrayRef                  _keyPathPropertyMappers;
    CFMutableArrayRef                  _keyArrayPropertyMappers;
    
    CFIndex                            _totalMappedCount;
    CFIndex                            _keyPathMappedCount;
    CFIndex                            _keyArrayMappedCount;
}

@end
@implementation XZHClassMapper

- (void)dealloc {
    _classModel = nil;
    CFRelease(_jsonKeyPropertyMapperDic);
    CFRelease(_objectInArrayClassDic);
    CFRelease(_allPropertyMappers);
    CFRelease(_keyPathPropertyMappers);
    CFRelease(_keyArrayPropertyMappers);
}

+ (instancetype)classMapperWithClass:(Class)cls {
    if (Nil == cls) return nil;
    static CFMutableDictionaryRef _cache;
    static dispatch_semaphore_t _semephore;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _cache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        _semephore = dispatch_semaphore_create(1);
    });
    
    const void *clsName =  (__bridge const void *)(NSStringFromClass(cls));
    dispatch_semaphore_wait(_semephore, DISPATCH_TIME_FOREVER);
    XZHClassMapper *clsMapper = CFDictionaryGetValue(_cache, clsName);
    dispatch_semaphore_signal(_semephore);
    
    if (!clsMapper) {
        __unsafe_unretained XZHClassModel *clsModel = [XZHClassModel classModelWithClass:cls];
        
        clsMapper = [[XZHClassMapper alloc] init];
        clsMapper->_classModel = clsModel;
        
        __block CFIndex totalMappedCount = 0;
        __block CFIndex keyPathMappedCount = 0;
        __block CFIndex keyArrayMappedCount = 0;
        
        CFMutableDictionaryRef jsonKeyPropertyMapperDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFMutableDictionaryRef objectInArrayClassDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        CFMutableArrayRef allPropertyMappers = CFArrayCreateMutable(CFAllocatorGetDefault(), 32, &kCFTypeArrayCallBacks);
        CFMutableArrayRef keyPathPropertyMappers = CFArrayCreateMutable(CFAllocatorGetDefault(), 32, &kCFTypeArrayCallBacks);
        CFMutableArrayRef keyArrayPropertyMappers = CFArrayCreateMutable(CFAllocatorGetDefault(), 32, &kCFTypeArrayCallBacks);
        
        NSMutableArray *allPropertyNames = [[NSMutableArray alloc] initWithCapacity:32];
        __unsafe_unretained XZHClassModel *clsTmpModel = clsModel;
        while (clsTmpModel) {
            for (__unsafe_unretained XZHPropertyModel *propertyModel in clsTmpModel.propertyMap.allValues) {
                if (!propertyModel.name) {continue;}
                if (!propertyModel.setter || !propertyModel.getter) {continue;}
                [allPropertyNames addObject:propertyModel.name];
            }
            clsTmpModel = clsTmpModel.superClassModel;
        }

        if (XZHClassRespondsToSelector(cls, @selector(xzh_ignoreMappingJSONKeys))) {
            NSArray *ignoreJSONKeys = [(id<XZHJSONModelMappingRules>)cls xzh_ignoreMappingJSONKeys];
            if (ignoreJSONKeys) {[allPropertyNames removeObjectsInArray:ignoreJSONKeys];}
        }
      
        if (XZHClassRespondsToSelector(cls, @selector(xzh_containerClass))) {
            NSDictionary *classInArrayDic = [(id<XZHJSONModelMappingRules>)cls xzh_containerClass];
            [classInArrayDic enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull propertyName, id  _Nonnull class, BOOL * _Nonnull stop) {
                if ([propertyName isKindOfClass:[NSString class]]) {
                    if ([class isKindOfClass:[NSString class]]) {
                        Class cls = NSClassFromString(class);
                        if (cls) {CFDictionarySetValue(objectInArrayClassDic, (__bridge const void *)(propertyName), (__bridge const void *)(cls));}
                    } else {
                        if (!class_isMetaClass(cls)) {
                            CFDictionarySetValue(objectInArrayClassDic, (__bridge const void *)(propertyName), (__bridge const void *)(class));
                        }
                    }
                }
            }];
        }
        if (XZHClassRespondsToSelector(cls, @selector(xzh_customerMappings))) {
            NSDictionary *customerJSONKeyMapping = [(id<XZHJSONModelMappingRules>)cls xzh_customerMappings];
            [customerJSONKeyMapping enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull propertyName, id  _Nonnull jsonKey, BOOL * _Nonnull stop) {
                if (![propertyName isKindOfClass:[NSString class]]) {return ;}
                [allPropertyNames removeObject:propertyName];
                
                __unsafe_unretained XZHPropertyModel *propertyModel = [clsModel.propertyMap objectForKey:propertyName];
                if (!propertyModel) {return ;}
                
                XZHPropertyMapper *newMapper = [[XZHPropertyMapper alloc] initWithPropertyModel:propertyModel containerCls:CFDictionaryGetValue(objectInArrayClassDic, (__bridge const void *)(propertyName)) generacCls:cls];
                if (!newMapper) {return ;}
                
                XZHPropertyMappedToJsonKeyType type = 0;
                if ([jsonKey isKindOfClass:[NSString class]]) {
                    
                    if ([jsonKey rangeOfString:@"."].location != NSNotFound) {
                        newMapper->_mappedToKeyPath = jsonKey;
                        type = XZHPropertyMappedToJsonKeyTypeKeyPath;
                    } else {
                        newMapper->_mappedToSimpleKey = jsonKey;
                        type = XZHPropertyMappedToJsonKeyTypeSimple;
                    }
                } else if ([jsonKey isKindOfClass:[NSArray class]]) {
                    
                    newMapper->_mappedToKeyArray = jsonKey;
                    type = XZHPropertyMappedToJsonKeyTypeKeyArray;
                }
                newMapper->_mappedType = type;
                __unsafe_unretained XZHPropertyMapper *preMapper = CFDictionaryGetValue(jsonKeyPropertyMapperDic, (__bridge const void *)(jsonKey));
                if (preMapper) {
                    newMapper->_next = preMapper;
                } else {
                    totalMappedCount++;
                    CFArrayAppendValue(allPropertyMappers, (__bridge const void *)(newMapper));
                    switch (type) {
                        case XZHPropertyMappedToJsonKeyTypeKeyPath: {
                            CFArrayAppendValue(keyPathPropertyMappers, (__bridge const void *)(newMapper));
                            keyPathMappedCount++;
                            break;
                        }
                        case XZHPropertyMappedToJsonKeyTypeKeyArray: {
                            CFArrayAppendValue(keyArrayPropertyMappers, (__bridge const void *)(newMapper));
                            keyArrayMappedCount++;
                            break;
                        }
                        default:
                            break;
                    }
                }
                CFDictionarySetValue(jsonKeyPropertyMapperDic, (__bridge const void *)(jsonKey), (__bridge const void *)(newMapper));
            }];
        }
        
        [allPropertyNames enumerateObjectsUsingBlock:^(NSString * _Nonnull propertyName, NSUInteger idx, BOOL * _Nonnull stop) {
            __unsafe_unretained XZHPropertyModel *propertyModel = [clsModel.propertyMap objectForKey:propertyName];
            if (!propertyModel) {return ;}
            
            XZHPropertyMapper *newMapper = [[XZHPropertyMapper alloc] initWithPropertyModel:propertyModel containerCls:CFDictionaryGetValue(objectInArrayClassDic, (__bridge const void *)(propertyName)) generacCls:cls];
            newMapper->_mappedToSimpleKey = propertyName;
            newMapper->_mappedType = XZHPropertyMappedToJsonKeyTypeSimple;
            
            __unsafe_unretained XZHPropertyMapper *preMapper = CFDictionaryGetValue(jsonKeyPropertyMapperDic, (__bridge const void *)(propertyName));
            if (preMapper) {
                newMapper->_next = preMapper;
            } else {
                totalMappedCount++;
                CFArrayAppendValue(allPropertyMappers, (__bridge const void *)(newMapper));
            }
            CFDictionarySetValue(jsonKeyPropertyMapperDic, (__bridge const void *)(propertyName), (__bridge const void *)(newMapper));
        }];
        
        clsMapper->_jsonKeyPropertyMapperDic = jsonKeyPropertyMapperDic;
        clsMapper->_objectInArrayClassDic = objectInArrayClassDic;
        clsMapper->_allPropertyMappers = allPropertyMappers;
        clsMapper->_keyPathPropertyMappers = keyPathPropertyMappers;
        clsMapper->_keyArrayPropertyMappers = keyArrayPropertyMappers;
        clsMapper->_totalMappedCount = totalMappedCount;
        clsMapper->_keyPathMappedCount = keyPathMappedCount;
        clsMapper->_keyArrayMappedCount = keyArrayMappedCount;
        
        dispatch_semaphore_wait(_semephore, DISPATCH_TIME_FOREVER);
        CFDictionarySetValue(_cache, clsName, (__bridge const void *)(clsMapper));
        dispatch_semaphore_signal(_semephore);
    }
    
    return clsMapper;
}

@end

@implementation NSObject (XZHJSONModelMapping)

#pragma mark - JSON To Model

+ (instancetype)xzh_modelFromObject:(id)obj {
    if (!obj || (id)kCFNull == obj) {return nil;}
    if ([obj isKindOfClass:[NSDictionary class]]) {
        return [self xzh_modelFromJSONDictionary:(NSDictionary*)obj];
    } else if ([obj isKindOfClass:[NSString class]]) {
        return [self xzh_modelFromJSONString:(NSString*)obj];
    } else if ([obj isKindOfClass:[NSData class]]) {
        return [self xzh_modelFromJSONData:(NSData*)obj];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        return [self xzh_modelFromJSONArray:obj];
    }
    return nil;
}

// NSString >>> NSData >>> NSDictionary
+ (instancetype)xzh_modelFromJSONString:(NSString *)jsonString {
    if (!jsonString || ((id)kCFNull == jsonString) || (jsonString.length < 1)) {return nil;}
    NSData *jsonData = [(NSString *)jsonString dataUsingEncoding: NSUTF8StringEncoding];
    return [self xzh_modelFromJSONData:jsonData];
}

// NSData >>> NSDictionary
+ (instancetype)xzh_modelFromJSONData:(NSData *)jsonData {
    if (!jsonData || (id)kCFNull == jsonData) {return nil;}
    NSDictionary *jsonDic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
    if (![jsonDic isKindOfClass:[NSDictionary class]]) {return nil;}
    return [self xzh_modelFromJSONDictionary:jsonDic];
}

+ (instancetype)xzh_modelFromJSONDictionary:(NSDictionary *)jsonDic {
    if (![jsonDic isKindOfClass:[NSDictionary class]]) {return nil;}
    
    __unsafe_unretained XZHClassMapper *clsMapper = [XZHClassMapper classMapperWithClass:[self class]];
    if (!clsMapper || 0 == clsMapper->_totalMappedCount) {return nil;}

    id model = [[self alloc] init];
    if (!model) {return nil;}
    
    XZHJsonToModelContext ctx = {0};
    ctx.model       = (__bridge void*)(model);
    ctx.jsonDic     = (__bridge void *)(jsonDic);
    ctx.classMapper = (__bridge void *)(clsMapper);
    
    if (jsonDic.count <= clsMapper->_totalMappedCount) {
        // property mapped to simpleKey
        CFDictionaryApplyFunction((CFDictionaryRef)jsonDic, XZHJsonToModelDicApplierFunction, &ctx);
        
        // property mapped to keyPath
        if(clsMapper->_keyPathMappedCount > 0) {
            CFArrayApplyFunction(clsMapper->_keyPathPropertyMappers, CFRangeMake(0, clsMapper->_keyPathMappedCount), XZHJsonToModelArrayApplierFunction, &ctx);
        }
        
        // property mapped to keyArray
        if(clsMapper->_keyArrayMappedCount > 0) {
            CFArrayApplyFunction(clsMapper->_keyArrayPropertyMappers, CFRangeMake(0, clsMapper->_keyArrayMappedCount), XZHJsonToModelArrayApplierFunction, &ctx);
        }
    } else {
        CFArrayApplyFunction(clsMapper->_allPropertyMappers, CFRangeMake(0, clsMapper->_totalMappedCount), XZHJsonToModelArrayApplierFunction, &ctx);
    }
    return model;
}

+ (instancetype)xzh_modelFromJSONArray:(NSArray *)jsonArray {
    if ([jsonArray isKindOfClass:[NSArray class]]) {
        NSMutableArray *modelArray = [[NSMutableArray alloc] initWithCapacity:jsonArray.count];
        id model = nil;
        id json = nil;
        for (id jsonItem in jsonArray) {
            if ([jsonItem isKindOfClass:[NSString class]]) {
                json = [(NSString *)jsonItem dataUsingEncoding: NSUTF8StringEncoding];
            }
            if ([jsonItem isKindOfClass:[NSData class]]) {
                json = [NSJSONSerialization JSONObjectWithData:jsonItem options:kNilOptions error:NULL];
            }
            if ([jsonItem isKindOfClass:[NSDictionary class]]) {
                model = [self xzh_modelFromJSONDictionary:jsonItem];
            }
        }
        if (model) {[modelArray addObject:model];}
    }
    return nil;
}

#pragma mark - Model To JSON

- (instancetype)xzh_modelToJSONObject {
    id json = XZHConvertModelToAbleJSONSerialization(self);
    if ([json isKindOfClass:[NSDictionary class]]) {return json;}
    if ([json isKindOfClass:[NSArray class]]) {return json;}
    return nil;
}

- (instancetype)xzh_modelToJSONData {
    id json = [self xzh_modelToJSONObject];
    if (!json) {return nil;}
    return [NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
}

- (instancetype)xzh_modelToJSONString {
    id data = [self xzh_modelToJSONData];
    if (!data) {return nil;}
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end

#pragma mark - >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Tools

static xzh_force_inline NSDateFormatter* XZHDateFormatter(__unsafe_unretained NSString *dateFormat) {
    if (!dateFormat) return nil;
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    });
    if (dateFormat) {
        formatter.dateFormat = dateFormat;
    } else {
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
    }
    return formatter;
}

static xzh_force_inline NSDictionary* XZHJSONStringToDic(__unsafe_unretained NSString *jsonString) {
//    jsonString = XZHConvertNullNSString(jsonString);
    NSData* data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError* error = nil;
    id result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    if (error) {
        return nil;
    }
    return result;
}

/**
 *  主要是NSString转NSNumber
 */
static xzh_force_inline NSNumber* XZHNumberWithValue(__unsafe_unretained id value) {
    static NSCharacterSet *dot = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dot = [NSCharacterSet characterSetWithRange:NSMakeRange('.', 1)];
    });
    if ([value isKindOfClass:[NSString class]]) {
        
        // 代表数值的字符串
        static NSDictionary *defaultDic = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            defaultDic = @{
                           @"true" : @(1),
                           @"TRUE" : @(1),
                           @"True" : @(1),
                           @"false" : @(0),
                           @"FALSE" : @(0),
                           @"False" : @(0),
                           @"YES" : @(1),
                           @"yes" : @(1),
                           @"Yes" : @(1),
                           @"NO" : @(0),
                           @"no" : @(0),
                           @"No" : @(0),
                           };
        });
        id tmp = [defaultDic objectForKey:value];
        if (tmp) {return tmp;}
        
        // 直接可以转NSNumber的数值字符串，过滤掉 NaN、Inf 的情况
        if ([(NSString *)value rangeOfCharacterFromSet:dot].location != NSNotFound) {// 带小数的
            const char *cstring = ((NSString *)value).UTF8String;
            if (!cstring) return @(0);
            double num = atof(cstring);
            if (isnan(num) || isinf(num)) return @(0);//NaN、Inf默认返回0
            return @(num);
        } else {// 整数
            return @([value integerValue]);
        }
    } else if ([value isKindOfClass:[NSNumber class]]) {
        return (NSNumber*)value;
    } else if (value == (id)kCFNull) {
        return nil;
    }
    return nil;
}

/**
 *  属性映射多个jsonkey时，其内部子jsonkey只支持两种:
 *  - (1) simple key
 *  - (2) keyPath
 */
static xzh_force_inline id XZHGetValueFromDictionaryWithKeyArray(__unsafe_unretained NSDictionary *dic, __unsafe_unretained NSArray *keyArray) {
    if (!keyArray) {return nil;}
    if (![keyArray isKindOfClass:[NSArray class]]) {return nil;}
    id value = nil;
    for (id itemKey in keyArray) {
        if ([itemKey isKindOfClass:[NSString class]]) {
            if ([itemKey rangeOfString:@"."].location != NSNotFound) {
                // 防止KVC崩溃
                @try {
                    value = [dic valueForKeyPath:itemKey];
                }
                @catch (NSException *exception) {
                    value = nil;
                }
            } else {
                value = [dic valueForKey:itemKey];
            }
        } else if ([itemKey isKindOfClass:[NSArray class]]) {
            //keypath没必要解析成数组形式，KVC可以valueForKeyPath:
        }
        
        if (value) {return value;}
    }
    return nil;
}

#pragma mark - >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> Model To JSON

static xzh_force_inline NSNumber* XZHGetNSNumberFromProperty(__unsafe_unretained id object, __unsafe_unretained XZHPropertyMapper *mapper) {
    if (!object || !mapper) return nil;
    SEL getter = mapper->_property.getter;
    if (!getter) return nil;
    
    if (mapper->_isCNumber) {
        switch (mapper->_typeEncoding & XZHTypeEncodingDataTypeMask) {
            case XZHTypeEncodingChar: {//char、int8_t
                char num = ((char (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithChar:num];
            }
                break;
            case XZHTypeEncodingUnsignedChar: {//unsigned char、uint8_t
                unsigned char num = ((unsigned char (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithUnsignedChar:num];
            }
                break;
            case XZHTypeEncodingBOOL: {
                BOOL num = ((BOOL (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithBool:num];
            }
                break;
            case XZHTypeEncodingShort: {//short、int16_t、
                short num = ((short (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithShort:num];
            }
                break;
            case XZHTypeEncodingUnsignedShort: {//unsigned short、uint16_t、
                unsigned short num = ((unsigned short (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithUnsignedShort:num];
            }
                break;
            case XZHTypeEncodingInt: {//int、int32_t、
                int num = ((int (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithInt:num];
            }
                break;
            case XZHTypeEncodingUnsignedInt: {//unsigned int、uint32_t
                unsigned int num = ((unsigned int (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithUnsignedInt:num];
            }
                break;
            case XZHTypeEncodingFloat: {
                float num = ((float (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                return [NSNumber numberWithFloat:num];
            }
                break;
            case XZHTypeEncodingLong32: {
                long num = ((long (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                if (isnan(num) || isinf(num)) return nil;
                return [NSNumber numberWithLong:num];
            }
                break;
            case XZHTypeEncodingLongLong: {
                long long num = ((long long (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                if (isnan(num) || isinf(num)) return nil;
                return [NSNumber numberWithLongLong:num];
            }
                break;
            case XZHTypeEncodingLongDouble: {
//                long double num = ((long double (*)(id, SEL))(void *) objc_msgSend)(object, getter); 使用double类型接收
                double num = ((long double (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                if (isnan(num) || isinf(num)) return nil;
                return @(num);
            }
                break;
            case XZHTypeEncodingUnsignedLong: {
                unsigned long num = ((unsigned long (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                if (isnan(num) || isinf(num)) return nil;
                return [NSNumber numberWithUnsignedLong:num];
            }
                break;
            case XZHTypeEncodingUnsignedLongLong: {
                unsigned long long num = ((unsigned long long (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                if (isnan(num) || isinf(num)) return nil;
                return [NSNumber numberWithUnsignedLongLong:num];
            }
                break;
            case XZHTypeEncodingDouble: {
                double num = ((double (*)(id, SEL))(void *) objc_msgSend)(object, getter);
                if (isnan(num) || isinf(num)) return nil;
                return [NSNumber numberWithDouble:num];
            }
                break;
        }
    } else if (XZHFoundationTypeNSNumber == mapper->_foundationType || XZHFoundationTypeNSDecimalNumber == mapper->_foundationType) {
        return ((NSNumber* (*)(id, SEL))(void *) objc_msgSend)(object, getter);
    } else if (XZHFoundationTypeNSString == mapper->_foundationType || XZHFoundationTypeNSMutableString == mapper->_foundationType) {
        NSString *value = ((NSString* (*)(id, SEL))(void *) objc_msgSend)(object, getter);
        return XZHNumberWithValue(value);
    }
    return nil;
}

static void XZHSetDictioanryWithKeyPath(__unsafe_unretained NSArray *keypathArray, __unsafe_unretained NSMutableDictionary *desDic, __unsafe_unretained id value) {
    NSMutableDictionary *superDic = desDic;
    NSMutableDictionary *subDic = nil;
    for (NSUInteger i = 0, max = keypathArray.count; i < max; i++) {
        NSString *key = keypathArray[i];
        if (i + 1 == max) {
            if (!superDic[key]) superDic[key] = value;
            break;
        }
        
        subDic = superDic[key];
        if (subDic) {
            if ([subDic isKindOfClass:[NSDictionary class]]) {
                subDic = subDic.mutableCopy;
                superDic[key] = subDic;
            } else {
                break;
            }
        } else {
            subDic = [NSMutableDictionary new];
            superDic[key] = subDic;
        }
        superDic = subDic;
        subDic = nil;
    }
}

static id XZHConvertModelToAbleJSONSerialization(__unsafe_unretained id object) {
    if (!object || ((id)kCFNull == object)) {return nil;}
    if ([object isKindOfClass:[NSString class]]) {return object;}
    if ([object isKindOfClass:[NSNumber class]]) {return object;}
    if ([object isKindOfClass:[NSAttributedString class]]) {return [(NSAttributedString*)object string];}
    if ([object isKindOfClass:[NSURL class]]) {return [(NSURL*)object absoluteString];}
    if ([object isKindOfClass:[NSDate class]]) {return [XZHDateFormatter(nil) stringFromDate:object];}
    if ([object isKindOfClass:[NSData class]]) return nil;

    if ([object isKindOfClass:[NSDictionary class]]) {
        if ([NSJSONSerialization isValidJSONObject:object]) {return object;}
        NSMutableDictionary *newDic = [NSMutableDictionary new];
        [newDic enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull value, BOOL * _Nonnull stop) {
            NSString *dic_key = ([key isKindOfClass:[NSString class]]) ? key : [key description];
            if (!dic_key) {return ;}
            id dic_value = XZHConvertModelToAbleJSONSerialization(value);
            if (!dic_value || ((id)kCFNull == dic_value)) {return ;}
            newDic[dic_key] = dic_value;
        }];
        return newDic;
    }
  
    if ([object isKindOfClass:[NSArray class]]) {
        if ([NSJSONSerialization isValidJSONObject:object]) {return object;}
        NSArray *arrayObj = object;
        NSMutableArray *newArray = [[NSMutableArray alloc] initWithCapacity:arrayObj.count];
        [arrayObj enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) {
                [newArray addObject:obj];
            } else {
                id arr_value = XZHConvertModelToAbleJSONSerialization(obj);
                if (!arr_value || ((id)kCFNull == arr_value)) {return ;}
                [newArray addObject:arr_value];
            }
        }];
        return newArray;
    }
  
    if ([object isKindOfClass:[NSSet class]]) {
        if ([NSJSONSerialization isValidJSONObject:object]) {return object;}
        NSSet *setObj = object;
        NSMutableArray *newArray = [[NSMutableArray alloc] initWithCapacity:setObj.count];
        [setObj enumerateObjectsUsingBlock:^(id  _Nonnull value, BOOL * _Nonnull stop) {
            if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
                [newArray addObject:value];
            } else {
                id arr_value = XZHConvertModelToAbleJSONSerialization(value);
                if (!arr_value || ((id)kCFNull == arr_value)) {return ;}
                [newArray addObject:arr_value];
            }
        }];
        return newArray;
    }
    
    __unsafe_unretained XZHClassMapper *classMapper = [XZHClassMapper classMapperWithClass:[object class]];
    if (!classMapper || (0 == classMapper->_totalMappedCount)) {return nil;}
    NSMutableDictionary *objectDic = [[NSMutableDictionary alloc] initWithCapacity:64];
    XZHModelToJsonContext ctx = {0};
    ctx.model = (__bridge void*)object;
    ctx.jsonDic = (__bridge void*)objectDic;
    CFDictionaryApplyFunction(classMapper->_jsonKeyPropertyMapperDic, XZHConvertModelToJSONApplierFunction, &ctx);
    return objectDic;
}

#pragma mark - model to json ApplierFunction

static void XZHConvertModelToJSONApplierFunction(const void *mappedToKey, const void *propertyMapper, void *context) {
    XZHPropertyMapper *_propertyMapper = (__bridge XZHPropertyMapper *)(propertyMapper);
    
    if (NULL == context) {return;}
    XZHModelToJsonContext *ctx = (XZHModelToJsonContext *)context;
    
    __unsafe_unretained id model = (__bridge id)(ctx->model);
    if (!model || (id)kCFNull == model) return;
    
    __unsafe_unretained NSMutableDictionary *jsonDic = (__bridge NSMutableDictionary*)(ctx->jsonDic);
    if (!jsonDic) return;
    
    id dic_value = nil;
    if (_propertyMapper->_isCNumber) {
        dic_value = XZHGetNSNumberFromProperty(model, _propertyMapper);
    } else if (XZHFoundationTypeNone != _propertyMapper->_foundationType) {
        dic_value = ((id (*)(id, SEL))(void *) objc_msgSend)(model, _propertyMapper->_property.getter);
        dic_value = XZHConvertModelToAbleJSONSerialization(dic_value);
    } else {
        if (XZHTypeEncodingClass == (_propertyMapper->_typeEncoding & XZHTypeEncodingDataTypeMask)) {
            Class cls = ((Class (*)(id, SEL))(void *) objc_msgSend)(model, _propertyMapper->_property.getter);
            dic_value = (NULL != cls) ? NSStringFromClass(cls) : nil;
        } else if (XZHTypeEncodingSEL == (_propertyMapper->_typeEncoding & XZHTypeEncodingDataTypeMask)) {
            SEL sel = ((SEL (*)(id, SEL))(void *) objc_msgSend)(model, _propertyMapper->_property.getter);
            dic_value = (NULL != sel) ? NSStringFromSelector(sel) : nil;
        }
    }
    if (!dic_value || (id)kCFNull == dic_value) {return ;}
    if (_propertyMapper->_mappedToKeyPath) {
        NSArray *keyArray = [_propertyMapper->_mappedToSimpleKey componentsSeparatedByString:@"."];
        XZHSetDictioanryWithKeyPath(keyArray, jsonDic, dic_value);
    } else if (_propertyMapper->_mappedToKeyArray) {
        for (NSString *keyItem in _propertyMapper->_mappedToKeyArray) {
            if (NSNotFound != [keyItem rangeOfString:@"."].location) {
                NSArray *keyArray = [keyItem componentsSeparatedByString:@"."];
                XZHSetDictioanryWithKeyPath(keyArray, jsonDic, dic_value);
            } else {
                [jsonDic setObject:dic_value forKey:keyItem];
            }
        }
    } else {
        [jsonDic setObject:dic_value forKey:_propertyMapper->_mappedToSimpleKey];
    }
}

#pragma mark - >>>>>>>>>>>>>>>>>>>>>>>>>>>>>> JSON To Model

static void XZHJsonToModelDicApplierFunction(const void *jsonKey, const void *jsonItemValue, void *context) {
    if (NULL == jsonKey || NULL == jsonItemValue || NULL == context) {return;}
    
    XZHJsonToModelContext *ctx = (XZHJsonToModelContext *)context;
    __unsafe_unretained id model = (__bridge id)(ctx->model);
    if (!model) {return;}
    
    __unsafe_unretained XZHClassMapper *clsMapper = (__bridge XZHClassMapper*)(ctx->classMapper);
    if (!clsMapper || clsMapper->_totalMappedCount < 1) {return;}
    
    __unsafe_unretained XZHPropertyMapper *propertyMapper = CFDictionaryGetValue(clsMapper->_jsonKeyPropertyMapperDic, jsonKey);
    while (propertyMapper) {
        XZHSetFoundationObjectToProperty((__bridge __unsafe_unretained id)jsonItemValue, model, propertyMapper);
        propertyMapper = propertyMapper->_next;
    }
}

static void XZHJsonToModelArrayApplierFunction(const void *value, void *context) {
    if (NULL == value || NULL == context) {return;}
    XZHJsonToModelContext *ctx = (XZHJsonToModelContext *)context;
    __unsafe_unretained NSDictionary *jsonDic = (__bridge NSDictionary *)(ctx->jsonDic);
    if (!jsonDic || ![jsonDic isKindOfClass:[NSDictionary class]]) return;
    
    __unsafe_unretained XZHPropertyMapper *propertyMapper = (__bridge XZHPropertyMapper*)(value);
    while (propertyMapper) {
        //find json item value with property mapped to jsonkey
        __unsafe_unretained id jsonValue = nil;
        if (XZHPropertyMappedToJsonKeyTypeKeyPath == propertyMapper->_mappedType) {
            jsonValue = [jsonDic valueForKeyPath:propertyMapper->_mappedToKeyPath];
        } else if (XZHPropertyMappedToJsonKeyTypeKeyArray == propertyMapper->_mappedType) {
            jsonValue = XZHGetValueFromDictionaryWithKeyArray(jsonDic, propertyMapper->_mappedToKeyArray);
        } else {
            jsonValue = [jsonDic objectForKey:propertyMapper->_mappedToSimpleKey];
        }
        if (!jsonValue) {break;}
        if (((id)kCFNull) == jsonValue) {break;}
        
        // set finded json item value to model with propertyMapper
        __unsafe_unretained id model = (__bridge __unsafe_unretained id)(ctx->model);
        XZHSetFoundationObjectToProperty(jsonValue, model, propertyMapper);
        propertyMapper = propertyMapper->_next;
    }
}

static void XZHSetFoundationObjectToProperty(__unsafe_unretained id jsonItemValue, __unsafe_unretained id model, __unsafe_unretained XZHPropertyMapper *propertyMapper)
{
    if (!jsonItemValue || !model || !propertyMapper) {return;}
    if (!propertyMapper->_isSetterAccess) {return;}
    SEL setter = propertyMapper->_property.setter;
    
    if (XZHFoundationTypeNone != propertyMapper->_foundationType){
        if (XZHFoundationTypeNSNull == propertyMapper->_foundationType) {
            if ([jsonItemValue isKindOfClass:[NSNull class]]) {((void (*)(id, SEL, NSNull*))(void *) objc_msgSend)(model, setter, (id)kCFNull);}
        } else {
            if ((id)kCFNull == jsonItemValue) {return;}
            switch (propertyMapper->_foundationType) {
                case XZHFoundationTypeNSString:
                case XZHFoundationTypeNSMutableString: {
                    if ([jsonItemValue isKindOfClass:[NSString class]]) {//NSString
                        ((void (*)(id, SEL, NSString*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSString) ? jsonItemValue : [jsonItemValue mutableCopy]);
                    } else if ([jsonItemValue isKindOfClass:[NSNumber class]]) {//NSNumber
                        NSString *valueString = [(NSNumber*)jsonItemValue stringValue];
                        if (valueString) {
                            ((void (*)(id, SEL, NSString*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSString) ? valueString : [valueString mutableCopy]);
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSURL class]]) {//NSURL
                        NSString *valueString = [(NSURL*)jsonItemValue absoluteString];
                        if (valueString) {
                            ((void (*)(id, SEL, NSString*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSString) ? valueString : [valueString mutableCopy]);
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSDate class]]) {//NSDate
                        if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_dateFormat))) {
                            NSString *dateFormat = [propertyMapper->_generacCls xzh_dateFormat];
                            if (dateFormat) {
                                NSDateFormatter *fomatter = XZHDateFormatter(dateFormat);
                                NSString *dateStr = [fomatter stringFromDate:jsonItemValue];
                                if (dateStr) {
                                    ((void (*)(id, SEL, NSString*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSString) ? dateStr : [dateStr mutableCopy]);
                                }
                            }
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSData class]]) {//NSData
                        NSString *valueString = [[NSString alloc] initWithData:jsonItemValue encoding:NSUTF8StringEncoding];
                        if (valueString) {
                            ((void (*)(id, SEL, NSString*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSString) ? valueString : [valueString mutableCopy]);
                        }
                    }
                }
                    break;
                case XZHFoundationTypeNSNumber:
                case XZHFoundationTypeNSDecimalNumber: {
                    if ([jsonItemValue isKindOfClass:[NSNumber class]]) {//NSNumber
                        ((void (*)(id, SEL, NSNumber*))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    } else if ([jsonItemValue isKindOfClass:[NSString class]]) {//NSString >>> (1)日期字符串 (2)数字字符串
                        NSDate *date  = nil;
                        if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_dateFormat))) {
                            NSString *dateFormat = [propertyMapper->_generacCls xzh_dateFormat];
                            if (dateFormat) {
                                NSDateFormatter *fomatter = XZHDateFormatter(dateFormat);
                                date = [fomatter dateFromString:jsonItemValue];
                            }
                        }
                        NSNumber *number = nil;
                        if (date) {
                            number = [NSNumber numberWithDouble:[date timeIntervalSinceReferenceDate]];
                        } else {
                            number = XZHNumberWithValue(jsonItemValue);
                        }
                        if (number) {
                            ((void (*)(id, SEL, NSNumber*))(void *) objc_msgSend)(model, setter, number);
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSDate class]]) {//NSDate
                        NSNumber *number = [NSNumber numberWithDouble:[(NSDate*)jsonItemValue timeIntervalSinceReferenceDate]];
                        if (number) {
                            ((void (*)(id, SEL, NSNumber*))(void *) objc_msgSend)(model, setter, number);
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSValue class]]) {//NSValue
                        ((void (*)(id, SEL, NSNumber*))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    }
                }
                    break;
                case XZHFoundationTypeNSURL: {
                    if ([jsonItemValue isKindOfClass:[NSURL class]]) {//NSURL
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    } else if ([jsonItemValue isKindOfClass:[NSString class]]) {//NSString
                        if (jsonItemValue) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)(model, setter, [[NSURL alloc] initWithString:jsonItemValue]);
                        }
                    }
                }
                    break;
                case XZHFoundationTypeNSArray :
                case XZHFoundationTypeNSMutableArray: {
                    NSArray *valueArray = nil;
                    if ([jsonItemValue isKindOfClass:[NSArray class]]) {valueArray = jsonItemValue;}
                    else if ([jsonItemValue isKindOfClass:[NSSet class]]) {valueArray = [jsonItemValue allObjects];}//NSSet >>> NSArray
                    if (!valueArray) {return;}
                    
                    /**
                     *  按照 `Class cls = [NSObejct xzh_containerClass];` 返回的Dic中配置的数组内子对象的Class进行json解析model
                     *  id newItem = [cls xzh_modelFromJSONDictionary:itemJSON];
                     */
                    if (propertyMapper->_containerCls) {
                        NSMutableArray *mutableArray = [[NSMutableArray alloc] initWithCapacity:valueArray.count];
                        for (id item in valueArray) {
                            if ([item isKindOfClass:propertyMapper->_containerCls]) {
                                [mutableArray addObject:item];
                            } else if ([item isKindOfClass:[NSDictionary class]]) {
                                Class cls = propertyMapper->_containerCls;
                                if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_classForDictionary:))) {
                                    cls = [(id<XZHJSONModelMappingRules>)propertyMapper->_generacCls xzh_classForDictionary:item];
                                }
                                id newItem = [cls xzh_modelFromJSONDictionary:item];
                                if (newItem)  {[mutableArray addObject:newItem];}
                            }
                            /**
                             *  如果数组元素内部子元素又是Array类型，通过如下组装成如下json格式:
                             *  @[
                             *      @"array1" : @[@"1", @"2", @"3"],
                             *      @"array2" : @[@"1", @"2", @"3"],
                             *      @"array3" : @[@"1", @"2", @"3"]
                             *   ]
                             *  将内部的Array子对象，包装成一个实体类，其内部拥有一个Array类型的属性即可.
                             */
                        }
                        ((void (*)(id, SEL, NSArray*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSArray) ? mutableArray.copy : mutableArray);
                    } else {
                        ((void (*)(id, SEL, NSArray*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSArray) ? valueArray : valueArray.mutableCopy);
                    }
                }
                    break;
                case XZHFoundationTypeNSDictionary:
                case XZHFoundationTypeNSMutableDictionary: {
                    NSDictionary *valueDic = nil;
                    if ([jsonItemValue isKindOfClass:[NSDictionary class]]) {valueDic = jsonItemValue;}
                    else if ([jsonItemValue isKindOfClass:[NSString class]]) {valueDic = XZHJSONStringToDic(jsonItemValue);}// 支持JSON字符串
                    if (!valueDic){return;}
                    
                    if (propertyMapper->_containerCls) {
                        NSMutableDictionary *mutableDic = [[NSMutableDictionary alloc] initWithCapacity:valueDic.count];
                        [valueDic enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                            if ([obj isKindOfClass:propertyMapper->_containerCls]) {
                                [mutableDic setObject:obj forKey:key];
                            } else if ([obj isKindOfClass:[NSDictionary class]]){
                                Class cls = propertyMapper->_containerCls;
                                if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_classForDictionary:))) {
                                    cls = [(id<XZHJSONModelMappingRules>)propertyMapper->_generacCls xzh_classForDictionary:obj];
                                }
                                id newItem = [propertyMapper->_containerCls xzh_modelFromJSONDictionary:obj];
                                if (newItem) {[mutableDic setObject:newItem forKey:key];}
                            }
                        }];
                        ((void (*)(id, SEL, NSDictionary*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSDictionary) ? mutableDic.copy : mutableDic);
                    } else {
                        ((void (*)(id, SEL, NSDictionary*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSDictionary) ? valueDic : valueDic.mutableCopy);
                    }
                }
                    break;
                case XZHFoundationTypeNSSet:
                case XZHFoundationTypeNSMutableSet: {
                    NSSet *valueSet = nil;
                    if ([jsonItemValue isKindOfClass:[NSSet class]]) {valueSet = jsonItemValue;}
                    else if ([jsonItemValue isKindOfClass:[NSArray class]]) {valueSet = [NSSet setWithArray:jsonItemValue];}//Array >>> Set
                    if (!valueSet) return;
                    
                    if (propertyMapper->_containerCls) {
                        NSMutableSet *mutableSet = [[NSMutableSet alloc] initWithCapacity:valueSet.count];
                        for (id item in valueSet) {
                            if ([item isKindOfClass:propertyMapper->_containerCls]) {
                                [mutableSet addObject:item];
                            } else if ([item isKindOfClass:[NSDictionary class]]) {
                                Class cls = propertyMapper->_containerCls;
                                if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_classForDictionary:))) {
                                    cls = [(id<XZHJSONModelMappingRules>)propertyMapper->_generacCls xzh_classForDictionary:item];
                                }
                                
                                id newItem = [propertyMapper->_containerCls xzh_modelFromJSONDictionary:item];
                                if (newItem) {[mutableSet addObject:newItem];}
                            }
                            ((void (*)(id, SEL, NSSet*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSDictionary) ? mutableSet.copy : mutableSet);
                        }
                    } else {
                        ((void (*)(id, SEL, NSSet*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSDictionary) ? valueSet : valueSet.mutableCopy);
                    }
                }
                    break;
                case XZHFoundationTypeUnknown: {
                    if ([jsonItemValue isKindOfClass:propertyMapper->_ivarClass]) {
                        ((void (*)(id, SEL, id))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    } else if ([jsonItemValue isKindOfClass:[NSDictionary class]]) {
                        Class cls = propertyMapper->_ivarClass;
                        if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_classForDictionary:))) {
                            cls = [propertyMapper->_generacCls xzh_classForDictionary:jsonItemValue];
                        }
                        id newItem = [cls xzh_modelFromJSONDictionary:jsonItemValue];
                        if (newItem) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)(model, setter, newItem);
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSString class]]) {
                        jsonItemValue = XZHJSONStringToDic(jsonItemValue);
                        if (!jsonItemValue) {return;}
                        Class cls = propertyMapper->_ivarClass;
                        if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_classForDictionary:))) {
                            cls = [propertyMapper->_generacCls xzh_classForDictionary:jsonItemValue];
                        }
                        id newItem = [cls xzh_modelFromJSONDictionary:jsonItemValue];
                        if (newItem) {
                            ((void (*)(id, SEL, id))(void *) objc_msgSend)(model, setter, newItem);
                        }
                    }
                }
                    break;
                case XZHFoundationTypeNSDate: {
                    if ([jsonItemValue isKindOfClass:[NSDate class]]) {
                        ((void (*)(id, SEL, NSDate*))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    } else if ([jsonItemValue isKindOfClass:[NSString class]]) {
                        if (!jsonItemValue)return;
                        if (XZHClassRespondsToSelector(propertyMapper->_generacCls, @selector(xzh_dateFormat))) {
                            NSString *dateFormat = [propertyMapper->_generacCls xzh_dateFormat];
                            if (dateFormat) {
                                NSDateFormatter *fomatter = XZHDateFormatter(dateFormat);
                                NSDate *date = [fomatter dateFromString:jsonItemValue];
                                if (date) {
                                    ((void (*)(id, SEL, NSDate*))(void *) objc_msgSend)(model, setter, date);
                                }
                            }
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSNumber class]]) {
                        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[(NSNumber*)jsonItemValue doubleValue]];
                        if (date) {
                            ((void (*)(id, SEL, NSDate*))(void *) objc_msgSend)(model, setter, date);
                        }
                    }
                }
                    break;
                case XZHFoundationTypeNSData:
                case XZHFoundationTypeNSMutableData: {
                    if ([jsonItemValue isKindOfClass:[NSData class]]) {
                        ((void (*)(id, SEL, NSData*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSData) ? jsonItemValue : [jsonItemValue mutableCopy]);
                    } else if ([jsonItemValue isKindOfClass:[NSString class]]) {
                        NSData *data = [(NSString*)jsonItemValue dataUsingEncoding:NSUTF8StringEncoding];
                        if (data) {
                            ((void (*)(id, SEL, NSData*))(void *) objc_msgSend)(model, setter, (propertyMapper->_foundationType == XZHFoundationTypeNSData) ? data : [data mutableCopy]);
                        }
                    }
                }
                    break;
                case XZHFoundationTypeNSValue: {
                    if ([jsonItemValue isKindOfClass:[NSValue class]]) {
                        ((void (*)(id, SEL, NSValue*))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    }
                }
                    break;
                case XZHFoundationTypeNSBlock: {
                    if ([jsonItemValue isKindOfClass:XZHGetNSBlockClass()]) {
                        /**
                         *  NSBlock的任意类 >>>> void(^)()
                         * 任意参数类型的block都可以设置进去，但是取出来执行的时候需要看参数类型去执行，否则会程序崩溃.
                         */
                        ((void (*)(id, SEL, void(^)()))(void *) objc_msgSend)(model, setter, jsonItemValue);
                    }
                }
                    break;
                    
                default:
                    break;
            }
        }
    } else if (propertyMapper->_isCNumber) {
        NSNumber *number = XZHNumberWithValue(jsonItemValue);
        if (!number) return;
        switch (propertyMapper->_typeEncoding & XZHTypeEncodingDataTypeMask) {
            case XZHTypeEncodingChar: {
                char num = [number charValue];
                ((void (*)(id, SEL, char))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingUnsignedChar: {
                unsigned char num = [number unsignedCharValue];
                ((void (*)(id, SEL, unsigned char))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingBOOL: {
                BOOL num = [number boolValue];
                ((void (*)(id, SEL, BOOL))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingShort: {
                short num = [number shortValue];
                ((void (*)(id, SEL, short))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingUnsignedShort: {
                unsigned short num = [number shortValue];
                ((void (*)(id, SEL, unsigned short))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingInt: {
                int num = [number intValue];
                ((void (*)(id, SEL, int))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingUnsignedInt: {
                unsigned int num = [number unsignedIntValue];
                ((void (*)(id, SEL, unsigned int))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingFloat: {
                float num = [number floatValue];
                ((void (*)(id, SEL, float))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingLong32: {
                long num = [number longValue];
                ((void (*)(id, SEL, long))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingLongLong: {
                long long num = [number longLongValue];
                ((void (*)(id, SEL, long long))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingLongDouble: {
                //TODO: Important: Objective-C does not support the long double type. @encode(long double) returns d, which is the same encoding as for double.
                long double num = [number doubleValue];
                ((void (*)(id, SEL, long double))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingUnsignedLong: {
                unsigned long num = [number unsignedLongValue];
                ((void (*)(id, SEL, unsigned long))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingUnsignedLongLong: {
                unsigned long long num = [number unsignedLongLongValue];
                ((void (*)(id, SEL, unsigned long long))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            case XZHTypeEncodingDouble: {
                double num = [number doubleValue];
                ((void (*)(id, SEL, double))(void *) objc_msgSend)(model, setter, num);
            }
                break;
            default:
                break;
        }
    } else {
        switch (propertyMapper->_typeEncoding & XZHTypeEncodingDataTypeMask) {
            case XZHTypeEncodingCString:
            case XZHTypeEncodingCPointer: {
                if (jsonItemValue == (id)kCFNull) {
                    ((void (*)(id, SEL, void*))(void *) objc_msgSend)(model, setter, (void*)0);
                } else if ([jsonItemValue isKindOfClass:[NSValue class]]) {
                    NSValue *nsvalue = (NSValue *)jsonItemValue;
                    if (nsvalue.objCType && (0 == strcmp(nsvalue.objCType, "^v"))) {
                        ((void (*)(id, SEL, void*))(void *) objc_msgSend)(model, setter, nsvalue.pointerValue);
                    }
                }
            }
                break;
            case XZHTypeEncodingClass: {
                if (jsonItemValue == (id)kCFNull) {
                    ((void (*)(id, SEL, Class))(void *) objc_msgSend)(model, setter, (Class)0);
                } else {
                    if ([jsonItemValue isKindOfClass:[NSString class]]) {
                        Class cls = objc_getClass([jsonItemValue UTF8String]);
                        if (Nil != cls) {
                            ((void (*)(id, SEL, Class))(void *) objc_msgSend)(model, setter, cls);
                        }
                    } else if ([jsonItemValue isKindOfClass:[NSValue class]]) {
                        NSValue *nsvalue = (NSValue *)jsonItemValue;
                        if (nsvalue.objCType && (0 == strcmp(nsvalue.objCType, "^v"))) {
                            char *clsName = (char *)nsvalue.pointerValue;
                            if (NULL != clsName) {
                                Class cls = objc_getClass(clsName);
                                if (cls) {
                                    ((void (*)(id, SEL, Class))(void *) objc_msgSend)(model, setter, cls);
                                }
                            }
                        }
                    } else {
                        Class cls = object_getClass(jsonItemValue);
                        if (cls) {
                            ((void (*)(id, SEL, Class))(void *) objc_msgSend)(model, setter, cls);
                        }
                    }
                }
            }
                break;
            case XZHTypeEncodingSEL: {
                if (jsonItemValue == (id)kCFNull) {
                    ((void (*)(id, SEL, SEL))(void *) objc_msgSend)(model, setter, (SEL)NULL);
                } else if ([jsonItemValue isKindOfClass:[NSString class]]){
                    SEL sel = NSSelectorFromString(jsonItemValue);
                    if (sel) {
                        ((void (*)(id, SEL, SEL))(void *) objc_msgSend)(model, setter, sel);
                    }
                } else if ([jsonItemValue isKindOfClass:[NSValue class]]) {
                    NSValue *nsvalue = (NSValue *)jsonItemValue;
                    if (nsvalue.objCType && strcmp(nsvalue.objCType, "^v")) {
                        char *selC = (char *)nsvalue.pointerValue;
                        if (selC) {
                            SEL sel = sel_registerName(selC);
                            if (sel) {
                                ((void (*)(id, SEL, SEL))(void *) objc_msgSend)(model, setter, sel);
                            }
                        }
                    }
                }
            }
                break;
            case XZHTypeEncodingCArray:
            case XZHTypeEncodingCStruct:
            case XZHTypeEncodingCUnion: {
                //只能当做NSValue进行存取
                if (jsonItemValue == (id)kCFNull) {
                    ((void (*)(id, SEL, SEL))(void *) objc_msgSend)(model, setter, (SEL)NULL);
                } else if ([jsonItemValue isKindOfClass:[NSValue class]]) {
                    NSValue *nsvalue = (NSValue *)jsonItemValue;
                    const char *nsvalueCoding = nsvalue.objCType;
                    const char *propertyCoding = propertyMapper->_ivarEncodingString.UTF8String;
                    if (nsvalueCoding && propertyCoding && (0 == strcmp(nsvalueCoding, propertyCoding))) {
                        ((void (*)(id, SEL, NSValue*))(void *) objc_msgSend)(model, setter, nsvalue);
                    }
                }
            }
                break;
        }
    }
}

