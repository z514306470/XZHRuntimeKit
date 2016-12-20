//
//  NSObject+XZHDataBase.m
//  XZHRuntimeDemo
//
//  Created by XiongZenghui on 16/10/18.
//  Copyright © 2016年 com.cn.fql. All rights reserved.
//

#import "NSObject+XZHObjectMappingDatabase.h"
#import "FMDB.h"
#import "XZHRuntime.h"
#import "XZHORMTools.h"

#ifdef DEBUG
#define XZHLogError(fmt, ...) NSLog(@"#XZHORM ERROR:\n" fmt, ##__VA_ARGS__);
#define XZHLogInfo(fmt, ...) NSLog(@"#XZHORM INFO:\n" fmt, ##__VA_ARGS__);
#else
#define XZHLogError(fmt, ...)
#define XZHLogInfo(fmt, ...)
#endif

// 数据库表默认的主键字段名字，类型为integer
static NSString *const kPrimaryKeyColumnName            = @"__rowid__";
static NSString *const kCreatedTimeColumnName           = @"__createdAt__";
static NSString *const kLastModifyTimeColumnName        = @"__updatedAt__";

typedef NS_ENUM(NSInteger, XZHSQLiteColumnConstraint) {
    XZHSQLiteColumnConstraintNOTNULL                    = 0,//确保某列不能有 NULL 值。
    XZHSQLiteColumnConstraintDEFAULT,//当某列没有指定值时，为该列提供默认值。
    XZHSQLiteColumnConstraintUNIQUE,//确保某列中的所有值是不同的
    XZHSQLiteColumnConstraintPRIMARYKey,//唯一标识数据库表中的各行/记录
    XZHSQLiteColumnConstraintCHECK,//确保某列中的所有值满足一定条件
};

typedef NS_ENUM(NSInteger, XZHSQLiteColumnType) {
    XZHSQLiteColumnTypeBLOB                             = 0,
    XZHSQLiteColumnTypeNUMERIC,
    XZHSQLiteColumnTypeINTEGER,
    XZHSQLiteColumnTypeREAL,
    XZHSQLiteColumnTypeTEXT,
    XZHSQLiteColumnTypeDATE,
    XZHSQLiteColumnTypeTable,//Ivar数据类型是: NSArray、NSSet时
};

typedef NS_ENUM(NSInteger, XZHRelationShipType) {
    XZHRelationShipTypeNone                             = 0,
    XZHRelationShipTypeMapToOne,
    XZHRelationShipTypeMapToMany,
};

// sqlite数据库表字段类型亲和性
static NSString *const kXZHSQLiteColumnTypeNONE         = @"NONE";
static NSString *const kXZHSQLiteColumnTypeBLOB         = @"BLOB";
static NSString *const kXZHSQLiteColumnTypeNUMERIC      = @"NUMERIC";
static NSString *const kXZHSQLiteColumnTypeINTEGER      = @"INTEGER";
static NSString *const kXZHSQLiteColumnTypeREAL         = @"REAL";
static NSString *const kXZHSQLiteColumnTypeTEXT         = @"TEXT";
static NSString *const kXZHSQLiteColumnTypeDATE         = @"DATE";

typedef struct GetSQLiteColumnTypeCtx {
    void                    *_typeStr;
    XZHSQLiteColumnType     _columnType;
    XZHRelationShipType     _mapType;
}GetSQLiteColumnTypeCtx;

static void GetSQLiteColumnType(__unsafe_unretained XZHPropertyModel *proM, GetSQLiteColumnTypeCtx *ctx) {
    if (!proM || NULL == ctx) {return;}
    
    if (proM.isCNumber) {
        ctx->_mapType = XZHRelationShipTypeNone;
        switch (proM.typeEncoding & XZHTypeEncodingDataTypeMask) {
            case XZHTypeEncodingBOOL: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeNUMERIC);
                ctx->_columnType = XZHSQLiteColumnTypeNUMERIC;
            }
                break;
            case XZHTypeEncodingChar:
            case XZHTypeEncodingUnsignedChar:
            case XZHTypeEncodingInt:
            case XZHTypeEncodingUnsignedInt:
            case XZHTypeEncodingShort:
            case XZHTypeEncodingUnsignedShort:
            case XZHTypeEncodingLong32:
            case XZHTypeEncodingLongLong:
            case XZHTypeEncodingUnsignedLong:
            case XZHTypeEncodingUnsignedLongLong: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeINTEGER);
                ctx->_columnType = XZHSQLiteColumnTypeINTEGER;
            }
                break;
            case XZHTypeEncodingFloat:
            case XZHTypeEncodingDouble:
            case XZHTypeEncodingLongDouble: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeREAL);
                ctx->_columnType = XZHSQLiteColumnTypeREAL;
            }
                break;
            default:
                break;
        }
    } else if (proM.foundationType != XZHFoundationTypeNone){
        switch (proM.foundationType) {
            case XZHFoundationTypeNSString:
            case XZHFoundationTypeNSMutableString:
            case XZHFoundationTypeNSURL: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeTEXT);
                ctx->_columnType = XZHSQLiteColumnTypeTEXT;
            }
                break;
            case XZHFoundationTypeNSNumber: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeINTEGER);
                ctx->_columnType = XZHSQLiteColumnTypeINTEGER;
            }
                break;
            case XZHFoundationTypeNSDecimalNumber: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeREAL);
                ctx->_columnType = XZHSQLiteColumnTypeREAL;
            }
                break;
            case XZHFoundationTypeUnknown: {//NSObejct子类 >>> 1:1
                ctx->_columnType = XZHSQLiteColumnTypeTable;
                ctx->_mapType = XZHRelationShipTypeMapToOne;
            }
                break;
            case XZHFoundationTypeNSArray:
            case XZHFoundationTypeNSMutableArray:
            case XZHFoundationTypeNSSet:
            case XZHFoundationTypeNSMutableSet: {//NSArray、NSSet >>> 1:n
                ctx->_columnType = XZHSQLiteColumnTypeTable;
                ctx->_mapType = XZHRelationShipTypeMapToMany;
            }
                break;
            case XZHFoundationTypeNSDictionary:
            case XZHFoundationTypeNSMutableDictionary: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeTEXT);
                ctx->_columnType = XZHSQLiteColumnTypeTEXT;
            }
                break;
            case XZHFoundationTypeNSData:
            case XZHFoundationTypeNSMutableData:
            case XZHFoundationTypeNSValue: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeBLOB);
                ctx->_columnType = XZHSQLiteColumnTypeBLOB;
            }
                break;
            case XZHFoundationTypeNSDate: {
                ctx->_typeStr = (__bridge void *)(kXZHSQLiteColumnTypeDATE);
                ctx->_columnType = XZHSQLiteColumnTypeDATE;
            }
                break;
            default:
                break;
        }
    }
}

/**
 *  NSValue >>>> NSData
 */
@interface __XZHNSValueConvertor : NSObject <NSCoding>
@property (nonatomic, copy) NSString *objcType;
@property (nonatomic, strong) NSData *data;
@end
@implementation __XZHNSValueConvertor
- (instancetype)initWithValue:(NSValue*)value
{
    if (self = [super init]) {
        const char *objCType = [value objCType];
        _objcType = [NSString stringWithCString:objCType encoding:NSUTF8StringEncoding];
        
        NSUInteger size;
        NSGetSizeAndAlignment(objCType, &size, NULL);
        void* ptr = malloc(size);
        [value getValue:ptr];
        NSData* data = [NSData dataWithBytes:ptr length:size];
        free(ptr);
        _data = data;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super init]) {
        _objcType = [aDecoder decodeObjectForKey:@"_objcType"];
        _data = [aDecoder decodeObjectForKey:@"_data"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_objcType forKey:@"_objcType"];
    [aCoder encodeObject:_data forKey:@"_data"];
}
@end

#pragma mark - Class Mapping Table

/**
 *  保存如下二者的映射关系
 *  - 实体类属性
 *  - 数据库表字段
 */
@interface XZHORMPropertyMapper : NSObject {
    @package
    XZHTypeEncoding             _typeEncoding;
    XZHFoundationType           _foundationType;
    XZHPropertyModel            *_propertyModel;
    Class                       _containerCls;//NSArray、NSSet内部对象Class
    Class                       _ivarCls;
    BOOL                        _isCNumber;
    NSString                    *_columnName;
    NSString                    *_columnTypeStr;
    XZHSQLiteColumnType         _columnType;
    XZHSQLiteColumnConstraint   _constraintType;
    XZHRelationShipType         _mapType;
    BOOL                        _isPrimaryKey;
    
}
@end
@implementation XZHORMPropertyMapper
- (instancetype)initWithPropertyModel:(XZHPropertyModel *)proM columnName:(NSString *)columnName containerCls:(Class)cls {
    if (NULL == proM) {return nil;}
    if (self = [super init]) {
        _propertyModel = proM;
        _typeEncoding = proM.typeEncoding;
        _foundationType = proM.foundationType;
        _isCNumber = proM.isCNumber;
        _columnName = columnName;
        _ivarCls = proM.cls;
        _containerCls = cls;
        
        GetSQLiteColumnTypeCtx ctx = {0};
        GetSQLiteColumnType(proM, &ctx);
        _columnTypeStr = (__bridge NSString *)(ctx._typeStr);
        _columnType = ctx._columnType;
        _mapType = ctx._mapType;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ : %p> propertyModel = %@, columnName = %@, isPrimaryKey = %d", [self class], self, _propertyModel, _columnName, _isPrimaryKey];
}

- (NSString *)debugDescription {
    return [self description];
}

@end

/**
 *  根据XZHPropertyModel，从FMResultSet中获取查询到的id结果对象
 */
static id GetFMResultSetValueWithPropertyModel(__unsafe_unretained FMResultSet *resultSet ,__unsafe_unretained XZHORMPropertyMapper *proMapper) {
    if (!resultSet || [resultSet isKindOfClass:[NSNull class]]) {return nil;}
    if (!proMapper || [proMapper isKindOfClass:[NSNull class]]) {return nil;}
    
    if (proMapper->_isCNumber) {
        switch (proMapper->_typeEncoding & XZHTypeEncodingDataTypeMask) {
            case XZHTypeEncodingChar: {
                int value = [resultSet intForColumn:proMapper->_columnName];
                return [NSNumber numberWithInt:value];
            }
                break;
            case XZHTypeEncodingUnsignedChar: {
                unsigned long long int value = [resultSet unsignedLongLongIntForColumn:proMapper->_columnName];
                return [NSNumber numberWithUnsignedLongLong:value];
            }
                break;
            case XZHTypeEncodingBOOL: {
                int value = [resultSet intForColumn:proMapper->_columnName];
                return [NSNumber numberWithInt:value];
            }
                break;
            case XZHTypeEncodingShort: {
                int value = [resultSet intForColumn:proMapper->_columnName];
                return [NSNumber numberWithInt:value];
            }
                break;
            case XZHTypeEncodingUnsignedShort: {
                unsigned long long int value = [resultSet unsignedLongLongIntForColumn:proMapper->_columnName];
                return [NSNumber numberWithUnsignedLongLong:value];
            }
                break;
            case XZHTypeEncodingInt: {
                int value = [resultSet intForColumn:proMapper->_columnName];
                return [NSNumber numberWithInt:value];
            }
                break;
            case XZHTypeEncodingUnsignedInt: {
                unsigned long long int value = [resultSet unsignedLongLongIntForColumn:proMapper->_columnName];
                return [NSNumber numberWithUnsignedLongLong:value];
            }
                break;
            case XZHTypeEncodingFloat: {
                double value = [resultSet doubleForColumn:proMapper->_columnName];
                return [NSNumber numberWithDouble:value];
            }
                break;
            case XZHTypeEncodingLong32: {
                long value = [resultSet longForColumn:proMapper->_columnName];
                return [NSNumber numberWithLong:value];
            }
                break;
            case XZHTypeEncodingLongLong: {
                long long value = [resultSet longLongIntForColumn:proMapper->_columnName];
                return [NSNumber numberWithLongLong:value];
                
            }
                break;
            case XZHTypeEncodingUnsignedLong: {
                unsigned long long int value = [resultSet unsignedLongLongIntForColumn:proMapper->_columnName];
                return [NSNumber numberWithUnsignedLongLong:value];
            }
                break;
            case XZHTypeEncodingUnsignedLongLong: {
                unsigned long long int value = [resultSet unsignedLongLongIntForColumn:proMapper->_columnName];
                return [NSNumber numberWithUnsignedLongLong:value];
            }
                break;
            case XZHTypeEncodingDouble:
            case XZHTypeEncodingLongDouble: {
                double value = [resultSet doubleForColumn:proMapper->_columnName];
                return [NSNumber numberWithDouble:value];
            }
                break;
            default:
                break;
        }
    } else if (proMapper->_foundationType != XZHFoundationTypeNone) {
        switch (proMapper->_foundationType) {
            case XZHFoundationTypeNSString:
            case XZHFoundationTypeNSMutableString: {
                NSString *string = [resultSet stringForColumn:proMapper->_columnName];
                if (string) {
                    return  (proMapper->_foundationType == XZHFoundationTypeNSMutableString) ? string : [string mutableCopy];
                }
                return nil;
            }
                break;
            case XZHFoundationTypeNSNumber: {
                NSNumber *value = [resultSet objectForColumnName:proMapper->_columnName];
                if ([[value class] isSubclassOfClass:[NSNumber class]]) {
                    return value;
                }
                return nil;
            }
                break;
            case XZHFoundationTypeNSDecimalNumber: {
                NSNumber *value = [resultSet objectForColumnName:proMapper->_columnName];
                if ([[value class] isSubclassOfClass:[NSNumber class]]) {
                    NSDecimalNumber *decimalValue = [NSDecimalNumber decimalNumberWithDecimal:[[NSNumber numberWithDouble:[value doubleValue]] decimalValue]];
                    return decimalValue;
                }
                return nil;
            }
                break;
            case XZHFoundationTypeNSURL: {
                NSString *value = [resultSet stringForColumn:proMapper->_columnName];
                if (value) {
                    return [NSURL URLWithString:value];
                }
                return nil;
            }
                break;
            case XZHFoundationTypeNSDate: {
                NSDate *value = [resultSet dateForColumn:proMapper->_columnName];
                return value;
            }
                break;
            case XZHFoundationTypeNSData:
            case XZHFoundationTypeNSMutableData: {
                NSData *value = [resultSet dataForColumn:proMapper->_columnName];
                return value;
            }
                break;
            case XZHFoundationTypeNSValue: {
                // DB记录 >>> NSData >>> NSValue
                NSData *value = [resultSet objectForColumnName:proMapper->_columnName];
                if (value && [[value class] isSubclassOfClass:[NSData class]]) {
                    __XZHNSValueConvertor *convertor = [NSKeyedUnarchiver unarchiveObjectWithData:value];
                    const char *objCType = [convertor.objcType cStringUsingEncoding:NSUTF8StringEncoding];
                    return [NSValue valueWithBytes:[convertor.data bytes] objCType:objCType];
                }
                return nil;
            }
                break;
            case XZHFoundationTypeNSNull: {
                return (id)kCFNull;
            }
                break;
            default:
                break;
        }
    } else {
        switch (proMapper->_typeEncoding * XZHTypeEncodingDataTypeMask) {
            case XZHTypeEncodingSEL:
            case XZHTypeEncodingClass: {
                NSString *selOrClass = [resultSet stringForColumn:proMapper->_columnName];
                return selOrClass;
            }
                break;
            case XZHTypeEncodingCStruct: {
                //TODO: 结构体实例后续再考虑
            }
                break;
            default:
                break;
        }
    }
    return nil;
}

@interface XZHORMRelationShip : NSObject
@property (nonatomic, copy) NSString *foreignKey;//当前表的一个外键
@property (nonatomic, copy) NSString *refreceTable;//外键关联的表
@property (nonatomic, copy) NSString *refrecePrimaryKey;
@end
@implementation XZHORMRelationShip
@end

/**
 *  保存如下二者的映射关系
 *  - 实体类所有的属性
 *  - 数据库表所有的字段
 */
@interface XZHORMClassMapper : NSObject {
    @package
    __unsafe_unretained XZHClassModel       *_clsModel;
    NSString                                *_tableName;
    NSString                                *_primaryKey;           // 单个主键
    NSArray                                 *_unionPrimaryKey;      // 多个联合主键
    BOOL                                    _isCustomerPrimaryKey;  // 记录 是否使用默认的主键名
    NSMutableArray     <XZHORMRelationShip*>*_foreignKeys;          //当前表关联其他表的所有外键
    CFMutableDictionaryRef                  _propertyMapperDic;     //记录<属性名:XZHORMPropertyMapper对象>
    NSUInteger                              _mappedCount;           // 记录 属性与字段映射的总个数
}
@end
@implementation XZHORMClassMapper
+ (instancetype)mapperWithClass:(Class)cls {
    if (Nil == cls) {return nil;}
    
    static CFMutableDictionaryRef   _cache = NULL;
    static dispatch_semaphore_t     _semephore = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _cache = CFDictionaryCreateMutable(kCFAllocatorDefault, 32, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        _semephore = dispatch_semaphore_create(1);
    });
    
    void *cacheKey = (__bridge void *)(NSStringFromClass(cls));
    dispatch_semaphore_wait(_semephore, DISPATCH_TIME_FOREVER);
    XZHORMClassMapper *mapper = CFDictionaryGetValue(_cache, cacheKey);
    dispatch_semaphore_signal(_semephore);
    
    if (!mapper) {
        mapper = [[XZHORMClassMapper alloc] init];
        
        // 解析 objc_class
        __unsafe_unretained XZHClassModel *clsModel = [XZHClassModel classModelWithClass:cls];
        mapper->_clsModel = clsModel;
        
        // 忽略ORM的类属性
        NSArray *ignoreProperties = nil;
        if (XZHClassRespondsToSelector(cls, @selector(xzh_notContainsProperties))) {
            ignoreProperties = [(id<XZHORMConfig>)cls xzh_notContainsProperties];
        }
        
        // 解析后的类属性的所有XZHPropertyModel数组
        NSMutableArray *propertyModels = [NSMutableArray new];
        __unsafe_unretained XZHClassModel *tmpClsModel = clsModel;
        while (tmpClsModel) {
            for (__unsafe_unretained XZHPropertyModel *proModel in tmpClsModel.propertyMap.allValues) {
                if (!proModel.name || [ignoreProperties containsObject:proModel.name]) {continue;}
                if (!proModel.setter || !proModel.getter) {continue;}
                [propertyModels addObject:proModel];
                tmpClsModel = tmpClsModel.superClassModel;
            }
            tmpClsModel = tmpClsModel.superClassModel;
        }
        
        ///////////////////////////////////////建立类属性与表字段的映射///////////////////////////////////////
        CFMutableDictionaryRef propertyMapperDic = CFDictionaryCreateMutable(kCFAllocatorDefault, propertyModels.count, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (XZHClassRespondsToSelector(cls, @selector(xzh_tableName))) {
            mapper->_tableName = [(id<XZHORMConfig>)cls xzh_tableName];
        } else {
            mapper->_tableName = NSStringFromClass(cls);
        }
        
        NSDictionary *customerMappingDic = nil;
        if (XZHClassRespondsToSelector(cls, @selector(xzh_columnsMappingProperties))) {
            customerMappingDic = [(id<XZHORMConfig>)cls xzh_columnsMappingProperties];
        }
        
        NSDictionary *clsInArrayOrSet = nil;
        if (XZHClassRespondsToSelector(cls, @selector(xzh_clsInNSArrayOrNSSet))) {
            clsInArrayOrSet = [(id<XZHORMConfig>)cls xzh_clsInNSArrayOrNSSet];
        }
        
        // 确定表主键（单个字段、多个字段联合。优先联合主键）
        if (XZHClassRespondsToSelector(cls, @selector(xzh_primaryKey))) {
            id primaryKey = [(id<XZHORMConfig>)cls xzh_primaryKey];
            mapper->_isCustomerPrimaryKey = YES;
            if ([primaryKey isKindOfClass:[NSArray class]]) {
                mapper->_unionPrimaryKey = primaryKey;
            } else if ([primaryKey isKindOfClass:[NSString class]]) {
                mapper->_primaryKey = primaryKey;
            }
        } else {
            mapper->_isCustomerPrimaryKey = NO;
            mapper->_primaryKey = kPrimaryKeyColumnName;
        }
        
        // 建立类属性与表字段的映射
        [propertyModels enumerateObjectsUsingBlock:^(XZHPropertyModel *proM, NSUInteger idx, BOOL * _Nonnull stop)
        {
            NSString *column = proM.name;
            if (customerMappingDic) {
                if ([[customerMappingDic objectForKey:proM.name] isKindOfClass:[NSString class]]) {
                    column = [customerMappingDic objectForKey:proM.name];
                }
            }
            Class containerCls = NULL;
            if (clsInArrayOrSet) {
                id cls = [clsInArrayOrSet objectForKey:proM.name];
                if ([cls isKindOfClass:[NSString class]]) {
                    containerCls = NSClassFromString(cls);
                } else {
                    containerCls = object_getClass(cls);
                }
            }
            XZHORMPropertyMapper *ormProMapper = [[XZHORMPropertyMapper alloc] initWithPropertyModel:proM columnName:column containerCls:containerCls];
            CFDictionarySetValue(propertyMapperDic, (__bridge const void *)(proM.name), (__bridge const void *)(ormProMapper));
        }];
        
        mapper->_propertyMapperDic = propertyMapperDic;
        mapper->_mappedCount = CFDictionaryGetCount(propertyMapperDic);
        mapper->_foreignKeys = [NSMutableArray new];
        
        dispatch_semaphore_wait(_semephore, DISPATCH_TIME_FOREVER);
        CFDictionarySetValue(_cache, cacheKey, (__bridge const void *)(mapper));
        dispatch_semaphore_signal(_semephore);
    }
    
    return mapper;
}
@end

#pragma mark - Create/Read/Update/Delete/ sqlite statement

@protocol XZHORMSQLStatement <NSObject>
- (XZHORMClassMapper *)mapper;
- (instancetype)initWithMapper:(XZHORMClassMapper *)mapper;
- (void)execute;
@end

//插入sql操作
@interface XZHORMSQLInsertStatement : NSObject <XZHORMSQLStatement>

@end

//删除sql操作
@interface XZHORMSQLDeleteStatement : NSObject <XZHORMSQLStatement>

@end

//更新sql操作
@interface XZHORMSQLUpdateStatement : NSObject <XZHORMSQLStatement>

@end

//查询sql操作
@interface XZHORMSQLSearchStatement : NSObject <XZHORMSQLStatement>

@end

#pragma mark - FMDB

/**
 *  封装FMDB的db函数操作
 */
@interface XZHDataBase : NSObject {
    @private
    FMDatabaseQueue *_dbQueue;
}
+ (instancetype)sharedDB;
- (FMDatabaseQueue *)xzh_dbQueue;

+ (BOOL)xzh_executeUpdate:(NSString *)sql;
+ (NSArray *)xzh_executeQueryColumnsInTable:(NSString *)table;
+ (NSUInteger)xzh_countTable:(NSString *)table;
+ (BOOL)xzh_truncateTable:(NSString *)table;
@end
@implementation XZHDataBase

static XZHDataBase *_db;
+ (instancetype)sharedDB {
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        _db = [[XZHDataBase alloc] init];
        NSString *dbPath = [XZHORMTools xzh_dbPath];
        _db->_dbQueue = [FMDatabaseQueue databaseQueueWithPath:dbPath];
        XZHLogInfo(@"XZHDataBase.path = %@", dbPath);
    }) ;
    return _db;
}

- (FMDatabaseQueue *)xzh_dbQueue {
    return _dbQueue;
}

- (BOOL)xzh_executeUpdate:(NSString *)sql {
    if (!sql || sql.length < 1) {return NO;}
    __block BOOL ret = NO;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        ret = [db executeUpdate:sql];
    }];
    return ret;
}

- (NSArray *)xzh_executeQueryColumnsInTable:(NSString *)table {
    NSMutableArray *columnsM=[NSMutableArray array];
    NSString *sql=[NSString stringWithFormat:@"PRAGMA table_info (%@);",table];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:sql];
        while ([set next]) {
            NSString *column = [set stringForColumn:@"name"];
            [columnsM addObject:column];
        }
        [set close];
    }];
    return ([[columnsM copy] length] > 0) ? [columnsM copy] : nil;
}

- (BOOL)xzh_isTableCreated:(NSString *)tableName {
    static NSString *sql = @"select count(name) from sqlite_master where type='table' and name=?;";
    __block BOOL isTableCreated = NO;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:sql, tableName];
        if ([set next]) {
            if ([set intForColumnIndex:0] > 0) {
                isTableCreated = YES;
            }
        }
        [set close];
    }];
    return isTableCreated;
}

- (NSUInteger)xzh_countTable:(NSString *)table {
    NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(*) AS count FROM %@;" ,table];
    __block NSUInteger count=0;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *set = [db executeQuery:sql];
        while ([set next]) {
            count = [set intForColumn:@"count"];
        }
        [set close];
    }];
    return count;
}

+ (BOOL)xzh_truncateTable:(NSString *)table {
    BOOL res = [self xzh_executeUpdate:[NSString stringWithFormat:@"DELETE FROM '%@'", table]];
    [self xzh_executeUpdate:[NSString stringWithFormat:@"DELETE FROM sqlite_sequence WHERE name='%@';", table]];
    return res;
}

@end


#pragma mark - ORM Interface

static BOOL XZHCreateTableWithORMClassMapper(__unsafe_unretained XZHORMClassMapper *clsMapper);

@implementation NSObject (XZHORM)

- (BOOL)xzh_save {
    static CFMutableDictionaryRef cache = NULL;
    static dispatch_semaphore_t semephore = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = CFDictionaryCreateMutable(kCFAllocatorDefault, 32, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        semephore = dispatch_semaphore_create(1);
    });
    
    Class cls = [self class];
    __unsafe_unretained XZHORMClassMapper *clsMapper = [XZHORMClassMapper mapperWithClass:cls];

    NSString *tableName = NSStringFromClass(cls);
    if (XZHClassRespondsToSelector(cls, @selector(xzh_tableName))) {
        tableName = [(id<XZHORMConfig>)cls xzh_tableName];
    }
    
    // 表如果还不存在，则创建表。如果需要更新表结构，请参考XZHORMTools.h中注释
    BOOL isExistTable = [[XZHDataBase sharedDB] xzh_isTableCreated:tableName];
    if (!isExistTable) {
        if (!XZHCreateTableWithORMClassMapper(clsMapper)) {return NO;}
    }
    
    // 插入数据
    
    return YES;
}

@end


typedef struct ORMStatementCtx {
    void *ormClsMapper;
    void *tableName;
    void *sql;
}ORMStatementCtx;

static void __CreateTableCFDictionaryApplierFunction(const void *key, const void *value, void *context);

static BOOL XZHCreateTableWithORMClassMapper(__unsafe_unretained XZHORMClassMapper *clsMapper) {
    if (!clsMapper) {return NO;}
    NSMutableString *sql = [[NSMutableString alloc] initWithString:@"CREATE TABLE "];
    [sql appendFormat:@"%@ (", clsMapper->_tableName];
    if (clsMapper->_primaryKey) {
        //单个主键
        [sql appendFormat:@"%@ INT PRIMARY KEY NOT NULL,", clsMapper->_primaryKey];
        ORMStatementCtx ctx = {0};
        ctx.sql = (__bridge void *)(sql);
        ctx.tableName = (__bridge void *)(clsMapper->_tableName);
        ctx.ormClsMapper = (__bridge void *)(clsMapper);
        CFDictionaryApplyFunction(clsMapper->_propertyMapperDic, __CreateTableCFDictionaryApplierFunction, &ctx);
        [sql appendFormat:@"%@ DATE, ", kCreatedTimeColumnName];
        [sql appendFormat:@"%@ DATE, ", kLastModifyTimeColumnName];
        for (XZHORMRelationShip *ship in clsMapper->_foreignKeys) {
            [sql appendFormat:@"%@ INT, ",  ship.foreignKey];
        }
        for (XZHORMRelationShip *ship in clsMapper->_foreignKeys) {
            [sql appendFormat:@"FOREIGN KEY(%@) REFERENCES %@(%@), ", ship.foreignKey, ship.refreceTable, ship.refrecePrimaryKey];
        }
        sql = [[sql substringWithRange:NSMakeRange(0, sql.length-2)] mutableCopy];
        [sql appendFormat:@");"];
        
    } else if (clsMapper->_unionPrimaryKey){
        //联合主键
    }
//    XZHLogInfo(@"%@", sql);
    return [[XZHDataBase sharedDB] xzh_executeUpdate:[sql copy]];
}

static void __CreateTableCFDictionaryApplierFunction(const void *key, const void *value, void *context) {
    if (NULL == context) {return;}
    ORMStatementCtx *ctx = (ORMStatementCtx *)context;
    NSMutableString *sql = (__bridge NSMutableString *)ctx->sql;
    //    NSString *propertyName = (__bridge NSString *)(key);
    __unsafe_unretained XZHORMClassMapper *clsMapper = (__bridge XZHORMClassMapper *)(ctx->ormClsMapper);
    __unsafe_unretained XZHORMPropertyMapper *proMapper = (__bridge XZHORMPropertyMapper *)(value);
    switch (proMapper->_columnType) {
        case XZHSQLiteColumnTypeBLOB: {
            [sql appendFormat:@"%@ BLOB, ", proMapper->_columnName];
        }
            break;
        case XZHSQLiteColumnTypeNUMERIC: {
            [sql appendFormat:@"%@ NUMERIC, ", proMapper->_columnName];
        }
            break;
        case XZHSQLiteColumnTypeINTEGER: {
            [sql appendFormat:@"%@ INTEGER, ", proMapper->_columnName];
        }
            break;
        case XZHSQLiteColumnTypeREAL: {
            [sql appendFormat:@"%@ REAL, ", proMapper->_columnName];
        }
            break;
        case XZHSQLiteColumnTypeTEXT: {
            [sql appendFormat:@"%@ TEXT, ", proMapper->_columnName];
        }
            break;
        case XZHSQLiteColumnTypeDATE: {
            [sql appendFormat:@"%@ DATE, ", proMapper->_columnName];
        }
            break;
        case XZHSQLiteColumnTypeTable: {
            __unsafe_unretained XZHORMClassMapper *foreignClsMapper = nil;
            if (proMapper->_mapType == XZHRelationShipTypeMapToOne) {
                foreignClsMapper = [XZHORMClassMapper mapperWithClass:proMapper->_ivarCls];
            } else if (proMapper->_mapType == XZHRelationShipTypeMapToMany) {
                foreignClsMapper = [XZHORMClassMapper mapperWithClass:proMapper->_containerCls];
            }
            if (foreignClsMapper) {
                XZHORMRelationShip *ship = [[XZHORMRelationShip alloc] init];
                ship.foreignKey = [NSString stringWithFormat:@"%@_foreign_rowid", (__bridge NSString*)ctx->tableName];
                ship.refreceTable = (__bridge NSString*)ctx->tableName;
                ship.refrecePrimaryKey = clsMapper->_primaryKey;//TODO: 待解决如果被关联表的主键是【联合主键】的情况
                [foreignClsMapper->_foreignKeys addObject:ship];
                XZHCreateTableWithORMClassMapper(foreignClsMapper);
            }
        }
            break;
    }
}