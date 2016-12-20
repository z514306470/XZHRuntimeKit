##SQLite参考教程

```
http://www.runoob.com/sqlite/sqlite-data-types.html
```

##SQLite表字段类型是`动态`数据类型（`无类型`），也就是会根据存入值自动判断。但其主要分为以下几种数据类型:

###SQLite建表时，可以无需指定变字段类型

```
Create Table ex3(a, b, c);  
```

这样就可以建表，也可以完成数据后续的增删改查。

但是通常情况下，都会手动指定表字段的数据类型，显然比使用动态字段性能会高。那么SQLite主要支持的数据类型:

```
NULL	值是一个 NULL 值。
INTEGER	值是一个带符号的【整数】，根据值的大小存储在 1、2、3、4、6 或 8 字节中。
REAL	值是一个【浮点值】，存储为 8 字节的 IEEE 浮点数字。
TEXT	值是一个【文本字符串】，使用数据库编码（UTF-8、UTF-16BE 或 UTF-16LE）存储。
BLOB	值是一个【二进制数据】，完全根据它的输入存储。
```


###当给某个字段分配一个类型时

```
1. 当给一个字段声明了类型，该字段实际上仅仅具有了该类型的新和性
2. 声明类型 和 类型亲和性 是两回事
3. 类型亲和性 预定SQLite用什么`存储类`来存储字段值
4. 在存储一个给定的值时，到底SQLite会在该字段中用什么存储类决定于值的存储类和字段亲和性的结合
```

###当为字段声明了类型，从根本上说是为字段指定了亲和性。主要有如下几种亲和性

- NUMERIC	

字段默认的亲和性是NUMERIC，该列可以包含使用所有五个存储类的值。

- INTEGER	

如果为字段声明的类型中包含了'INT'(无论大小写)，该字段被指派为INTEGER亲和性。


- TEXT

该列使用存储类 NULL、TEXT 或 BLOB 存储所有数据。 如果为字段声明的类型中包含了'CHAR'、'CLOB'或'TEXT'(无论大小写)，该字段被指派为TEXT亲和性。如'VARCHAR'包含了'CHAR'，所以被指派为TEXT亲和性。

- REAL	

与带有 NUMERIC affinity 的列相似，不同的是，它会强制把整数值转换为浮点表示。


- NONE	

如果为字段声明的类型中包含了'BLOB'(无论大小写)，或者没有为该字段声明类型，该字段被指派为NONE亲和性。所有的值都将以它们本身的(或从它们的表示法中推断的)存储类存储。如果你暂时还不确定要往一个字段里放什么内容，或准备将来修改，用NONE亲和性是一个好的选择

###根据亲和性具体划分的所有数据类型

```
INT
INTEGER
TINYINT
SMALLINT
MEDIUMINT
BIGINT
UNSIGNED BIG INT
INT2
INT8
INTEGER
CHARACTER(20)
VARCHAR(255)
VARYING CHARACTER(255)
NCHAR(55)
NATIVE CHARACTER(70)
NVARCHAR(100)
TEXT
CLOB
TEXT
BLOB
no datatype specified
NONE
REAL
DOUBLE
DOUBLE PRECISION
FLOAT
REAL
NUMERIC
DECIMAL(10,5)
BOOLEAN
DATE
DATETIME
```

###Boolean 数据类型

SQLite 没有单独的 Boolean 存储类。相反，布尔值被存储为整数 0（false）和 1（true）。

###Date 与 Time 数据类型

SQLite 没有一个单独的用于存储日期和/或时间的存储类，但 SQLite 能够把日期和时间存储为 TEXT、REAL 或 INTEGER 值。

```
存储类	  日期格式
TEXT	格式为 "YYYY-MM-DD HH:MM:SS.SSS" 的日期。
REAL	从公元前 4714 年 11 月 24 日格林尼治时间的正午开始算起的天数。
INTEGER	从 1970-01-01 00:00:00 UTC 算起的秒数。
```

##FMDatabase的线程安全

###FMDB对于线程安全上使用的注意说明

Using a single instance of FMDatabase from multiple threads at once is a bad idea. 

It has always been OK to make a FMDatabase object per thread. Just don't share a single instance across threads, and definitely not across multiple threads at the same time. 

Bad things will eventually happen and you'll eventually get something to crash, or maybe get an exception, or maybe meteorites will fall out of the sky and hit your Mac Pro. This would suck.

So don't instantiate a single FMDatabase object and use it across multiple threads.


###上面注释总结为一句话 >>> 在多线程环境时应该使用FMDatabaseQueue

```c
FMDatabaseQueue *queue = [FMDatabaseQueue databaseQueueWithPath:aPath];
```

```c
[queue inDatabase:^(FMDatabase *db) {
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:1]];
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:2]];
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:3]];

    FMResultSet *rs = [db executeQuery:@"select * from foo"];
    while ([rs next]) {
        …
    }
}];
```

```c
[queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:1]];
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:2]];
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:3]];

    if (whoopsSomethingWrongHappened) {
        *rollback = YES;
        return;
    }
    // etc…
    [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:4]];
}];
```

- (1) FMDatabaseQueue will make a `serialized GCD queue` in the background 

- (2) execute the blocks you pass to the GCD queue

- (3) FMDatabaseQueue 按照顺序一个一个执行接收到的DB操作block

###FMDatabaseQueue内部大量使用`dispatch_sync(){}`，用来避免发生线程死锁的办法

```c
static const void * const kDispatchQueueSpecificKey = &kDispatchQueueSpecificKey;
```
 
```c
@implementation FMDatabaseQueue

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags vfs:(NSString *)vfsName {
    self = [super init];
    if (self != nil) {
    	...................
    	
    	//1. 串行GCD队列
    	_queue = dispatch_queue_create([[NSString stringWithFormat:@"fmdb.%@", self] UTF8String], NULL);
    	
    	//2. 给队列绑定的一个标示值
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
       ....................
	}
	return self;
}

@end
```

```c
@implementation FMDatabaseQueue

- (void)inDatabase:(void (^)(FMDatabase *db))block {

	//1. 获取当前GCD Queue绑定的标示值，来判断是否是正确的Queue
    FMDatabaseQueue *currentSyncQueue = (__bridge id)dispatch_get_specific(kDispatchQueueSpecificKey);
    
    //2. 通过对比绑定的标示值，防止dispatch_sync(){}所在线程Queue与将要调度到的Queue是同一个，导致线程死锁
    assert(currentSyncQueue != self && "inDatabase: was called reentrantly on the same queue, which would lead to a deadlock");
    
    FMDBRetain(self);
    
    //3. 使用sync同步队列调度分配线程任务
    dispatch_sync(_queue, ^() {
        
        // 获取当前FMDatabaseQueue对象内部的DB对象
        FMDatabase *db = [self database];
        
        // 回传FMDatabase对象让外面操作
        block(db);
        
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue inDatabase:]");
            
#if defined(DEBUG) && DEBUG
            NSSet *openSetCopy = FMDBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                FMResultSet *rs = (FMResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    });
    
    FMDBRelease(self);
}

@end
```

##BZObjectStore源码参考笔记

###测试的实体类

- (1) ORMPerson

```objc
#import <Foundation/Foundation.h>
#import "ORMDog.h"
#import "ORMCar.h"
#import "ORMHouse.h"
#import "ORMBike.h"

@interface ORMPerson : NSObject 

@property (nonatomic, copy) NSString *pid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *favorates;
@property (nonatomic, assign) int age;
@property (nonatomic, assign) float height;

@property (nonatomic, strong) ORMBike *bike;

@property (nonatomic, strong) NSArray *dogs;
@property (nonatomic, strong) NSArray *cars;

@property (nonatomic, strong) NSDictionary *houseDic;

@end
```

```objc
#import "ORMPerson.h"

@implementation ORMPerson
@end
```


- (2) ORMDog

```objc
#import <Foundation/Foundation.h>

@interface ORMDog : NSObject
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *size;
@end
```

```objc
#import "ORMDog.h"

@implementation ORMDog
@end
```

- (3) ORMCar

```objc
#import <Foundation/Foundation.h>

@interface ORMCar : NSObject
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *price;
@end
```

```objc
#import "ORMCar.h"

@implementation ORMCar
@end
```

- (4) ORMHouse

```objc
#import <Foundation/Foundation.h>

@interface ORMHouse : NSObject
@property (nonatomic, copy) NSString *hid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *price;
@end
```

```objc
#import "ORMHouse.h"

@implementation ORMHouse
@end
```

- (5) ORMBike

```objc
#import <Foundation/Foundation.h>

@interface ORMBike : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *price;
@end
```

```objc
#import "ORMBike.h"

@implementation ORMBike
@end
```

###测试BZObjectStore持久化对象

```objc
- (void)testBZObjectStore {
    ORMPerson *person = [ORMPerson new];
    person.pid = @"p001";
    person.name = @"xiongzenghui";
    person.favorates = @"打篮球";
    person.age = 19;
    person.height = 154.2;
    
    ORMBike *bike = [ORMBike new];
    bike.name = @"捷安特500公路车";
    bike.price = @"39999元";
    person.bike = bike;
    
    NSArray *dogNames = @[@"哈士奇", @"杜比犬", @"松狮", @"秋田犬", @"约克夏"];
    NSArray *dogSizes = @[@"大型犬", @"小型犬", @"中型犬", @"袖珍型犬", @"土狗型犬"];
    NSMutableArray *dogs = [NSMutableArray new];
    for (NSInteger i = 0; i < 5; i++) {
        ORMDog *dog = [ORMDog new];
        dog.did = [NSString stringWithFormat:@"dog00%ld", i+1];
        dog.name = [dogNames objectAtIndex:i];
        dog.size = [dogSizes objectAtIndex:i];
        [dogs addObject:dog];
    }
    person.dogs = [dogs copy];
    
    NSArray *carNames = @[@"雷克萨斯", @"梅赛德斯", @"保时捷", @"兰博基尼", @"劳斯莱斯"];
    NSArray *carPrices = @[@"500W", @"300W", @"1000W", @"200W", @"800W"];
    NSMutableArray *cars = [NSMutableArray new];
    for (NSInteger i = 0; i < 5; i++) {
        ORMCar *car = [ORMCar new];
        car.cid = [NSString stringWithFormat:@"car00%ld", i+1];
        car.name = [carNames objectAtIndex:i];
        car.price = [carPrices objectAtIndex:i];
        [cars addObject:car];
    }
    person.cars = [cars copy];
    
    NSArray *houseNames = @[@"福岗园，中心天元配套", @"栖棠映山 香蜜湖半山豪宅", @"信义假日名城 精装 2室2厅 ", @"罗湖庆云花园大社区", @"红本无税 待旧改物业 "];
    NSMutableDictionary *houseDic = [NSMutableDictionary new];
    for (NSInteger i = 0; i < 5; i++) {
        ORMHouse *house = [ORMHouse new];
        house.hid = [NSString stringWithFormat:@"house00%ld", i+2];
        house.name = [houseNames objectAtIndex:i];
        [houseDic setObject:house forKey:house.hid];
    }
    person.houseDic = [houseDic copy];
    
    BZObjectStore *os = [BZObjectStore openWithPath:@"database.sqlite" error:NULL];
    
    NSError *error = nil;
    [os saveObject:person error:&error];
    
    if (error) {
        NSLog(@"error: %@", [error localizedDescription]);
    }
}
```

###运行后打开沙盒下database.sqlite

总共创建了8张表

![](http://a1.qpic.cn/psb?/V11ePBui4Hz4Py/881884*9uWRKbtJSc8jl9AXErrCFDHjNkEvLSsrWQVA!/b/dN4AAAAAAAAA&bo=MAeAAgAAAAAFB5E!&rf=viewer_4)

可以用如下sql查看所有的表结构

```c
select * from sqlite_master where type="table";
```

也可以用如下sql查看某一个表的结构

```c
select * from sqlite_master where type="table" and name="ORMBike";
```

分别得到上面8张表建立时候的sql分别如下:

- table	ORMBike

```
CREATE TABLE ORMBike (
name TEXT,
price TEXT,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	ORMDog

```
CREATE TABLE ORMDog (
did TEXT,
name TEXT,
size TEXT,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	ORMCar

```
CREATE TABLE ORMCar (
cid TEXT,
name TEXT,
price TEXT,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	ORMHouse

```
CREATE TABLE ORMHouse (
hid TEXT,
name TEXT,
price TEXT,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	ORMPerson

```
CREATE TABLE ORMPerson (
pid TEXT,
name TEXT,
favorates TEXT,
age NUMERIC,
height REAL,
bike TEXT,
dogs TEXT,
cars TEXT,
houseDic TEXT,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	`__ObjectStoreRelationship__`

```
CREATE TABLE __ObjectStoreRelationship__ (
fromClassName TEXT,
fromTableName TEXT,
fromAttributeName TEXT,
fromRowid INTEGER,
toClassName TEXT,
toTableName TEXT,
toRowid INTEGER,
attributeLevel INTEGER,
attributeSequence INTEGER,
attributeParentLevel INTEGER,
attributeParentSequence INTEGER,
attributeKey TEXT,
attributeValue NONE,
attributeValue_attributeType TEXT,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	`__ObjectStoreRuntime__`

```
CREATE TABLE __ObjectStoreRuntime__ (
clazzName TEXT,
isArrayClazz NUMERIC,
isSimpleValueClazz NUMERIC,
isObjectClazz NUMERIC,
isRelationshipClazz NUMERIC,
attributes TEXT,
fullTextSearch3 NUMERIC,
fullTextSearch4 NUMERIC,
modelDidLoad NUMERIC,
modelDidSave NUMERIC,
modelDidDelete NUMERIC,
hasIdentificationAttributes NUMERIC,
hasRelationshipAttributes NUMERIC,
insertPerformance NUMERIC,
updatePerformance NUMERIC,
notification NUMERIC,
cascadeNotification NUMERIC,
osclazz BLOB,
tableName TEXT,
selectTemplateStatement TEXT,
updateTemplateStatement TEXT,
selectRowidTemplateStatement TEXT,
insertIntoTemplateStatement TEXT,
insertOrIgnoreIntoTemplateStatement TEXT,
insertOrReplaceIntoTemplateStatement TEXT,
deleteFromTemplateStatement TEXT,
createTableTemplateStatement TEXT,
dropTableTemplateStatement TEXT,
createUniqueIndexTemplateStatement TEXT,
dropIndexTemplateStatement TEXT,
countTemplateStatement TEXT,
referencedCountTemplateStatement TEXT,
uniqueIndexNameTemplateStatement TEXT,
hasNotUpdateIfValueIsNullAttribute NUMERIC,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

- table	`__ObjectStoreRuntimeProperty__`

```
CREATE TABLE __ObjectStoreRuntimeProperty__ (
tableName TEXT,
columnName TEXT,
sqliteColumns BLOB,
clazzName TEXT,
name TEXT,
attributeType TEXT,
isSimpleValueClazz NUMERIC,
isArrayClazz NUMERIC,
isObjectClazz NUMERIC,
isPrimaryClazz NUMERIC,
isValid NUMERIC,
identicalAttribute NUMERIC,
ignoreAttribute NUMERIC,
weakReferenceAttribute NUMERIC,
notUpdateIfValueIsNullAttribute NUMERIC,
serializableAttribute NUMERIC,
fetchOnRefreshingAttribute NUMERIC,
onceUpdateAttribute NUMERIC,
isRelationshipClazz NUMERIC,
osclazz BLOB,
__createdAt__ DATE,
__updatedAt__ DATE
)
```

###上面8张表结构中，都没有一个int类型的primary key的字段

但是通过插入第二条数据之后，表突然添加了一个字段叫做`rowid`。但是从表结构中查看，并没有这个叫做`rowid`的字段...

###BZObjectStoreClazz

- (1) 获取Runtime属性解析，以及数据库表字段解析的协议: BZObjectStoreClazzProtocol

```objc
@protocol BZObjectStoreClazzProtocol <NSObject>
@optional
- (Class)superClazz;
- (BOOL)isSimpleValueClazz;
- (BOOL)isArrayClazz;
- (BOOL)isObjectClazz;
- (BOOL)isRelationshipClazz;
- (BOOL)isPrimaryClazz;
- (BOOL)isSubClazz:(Class)clazz;
- (NSString*)attributeType;
- (id)objectWithObjects:(NSArray*)objects keys:(NSArray*)keys initializingOptions:(NSString*)initializingOptions;
- (id)objectWithClazz:(Class)clazz;
- (NSEnumerator*)objectEnumeratorWithObject:(id)object;
- (NSArray*)keysWithObject:(id)object;
- (NSArray*)storeValuesWithValue:(id)value attribute:(BZObjectStoreRuntimeProperty*)attribute;
- (id)valueWithResultSet:(FMResultSet*)resultSet attribute:(BZObjectStoreRuntimeProperty*)attribute;
- (NSString*)sqliteDataTypeName;
- (NSArray*)sqliteColumnsWithAttribute:(BZObjectStoreRuntimeProperty*)attribute;
- (NSArray*)requiredPropertyList;
@end
```

- (2) 抽象实现类: BZObjectStoreClazz

```objc
@interface BZObjectStoreClazz : NSObject<BZObjectStoreClazzProtocol>
+ (BZObjectStoreClazz*)osclazzWithClazz:(Class)clazz;
+ (BZObjectStoreClazz*)osclazzWithPrimitiveEncodingCode:(NSString*)primitiveEncodingCode;
+ (BZObjectStoreClazz*)osclazzWithStructureName:(NSString*)StructureName;
+ (void)addClazz:(Class)clazz;
@end
```

- (3) 各种集成自BZObjectStoreClazz的具体实现子类

```objc
- 基本数值类型
	- BZObjectStoreClazzC99Bool
	- BZObjectStoreClazzChar
	- BZObjectStoreClazzDouble
	- BZObjectStoreClazzFloat
	- BZObjectStoreClazzInt
	- BZObjectStoreClazzLong
	- BZObjectStoreClazzLongLong
	- BZObjectStoreClazzShort
	- BZObjectStoreClazzUnsignedChar
	- BZObjectStoreClazzUnsignedInt
	- BZObjectStoreClazzUnsignedLong
	- BZObjectStoreClazzUnsignedLongLong
	- BZObjectStoreClazzUnsignedShort
- Foundation类型
	- BZObjectStoreClazzID
	- BZObjectStoreClazzNSObject
	- BZObjectStoreClazzNSString
	- BZObjectStoreClazzNSMutableString
	- BZObjectStoreClazzImage
	- BZObjectStoreClazzNSArray
	- BZObjectStoreClazzNSMutableArray
	- BZObjectStoreClazzNSDictionary
	- BZObjectStoreClazzNSMutableDictionary
	- BZObjectStoreClazzNSSet
	- BZObjectStoreClazzNSMutableSet
	- BZObjectStoreClazzNSData
	- BZObjectStoreClazzNSDate
	- BZObjectStoreClazzNSNumber
	- BZObjectStoreClazzNSDecimalNumber
	- BZObjectStoreClazzNSImage
	- BZObjectStoreClazzNSNull
	- BZObjectStoreClazzNSRange
	- BZObjectStoreClazzNSURL
	- BZObjectStoreClazzNSValue
- c结构体类型/CoreFoundation类型
	- BZObjectStoreClazzCGPoint
	- BZObjectStoreClazzCGRect
	- BZObjectStoreClazzCGSize
```

使用每一个类对象，来记录每一种数据oc数据类型，对应的db数据库表中的字段类型。

最后发现，他使用表同时记录了runtime的一些解析后的数据对象。但其实最终的一个问题，就是多表之间的关系（1:n，n:n）仍然就是直接将array/set/dic序列化成json string，然后表字段是TEXT类型，存入到db。

###建表时指定单个主键与联合主键

1、sqlite支持建立自增主键，sql语句如下： 

```
CREATE TABLE w_user( 
	id integer primary key autoincrement, 
	userename varchar(32), 
	usercname varchar(32), 
	userpassword varchar(32), 
	userpermission varchar(32), 
	userrole varchar(32), 
	userdesc varchar(32) 
); 
```

2、联合主键 

```
CREATE TABLE tb_test ( 
	bh varchar(5), 
	id integer, 
	ch varchar(20),
	mm varchar(20),
	primary key (id,bh)
); 
```

注意：在创建联合主键时，主键创建要放在所有字段最后面，否则也会创建失败


###目前能够支持NSArray、NSSet、单个NSObejct自定义类对象关系统一映射为1:n，对于NSDictionary暂时只支持json字符串TEXT字段存储，并且只支持单向依赖关联


```objc
@interface ORMPerson : NSObject <XZHORMConfig>

@property (nonatomic, copy) NSString *pid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *favorates;
@property (nonatomic, assign) int age;
@property (nonatomic, assign) float height;

@property (nonatomic, strong) ORMBike *bike;

@property (nonatomic, strong) NSArray *dogs;
@property (nonatomic, strong) NSArray *cars;

@property (nonatomic, strong) NSDictionary *houseDic;//dic类型数据，暂时还没想好使用哪一种关联关系表结构，只能暂时使用json string字段存储

@end
```

```objc
@interface ORMDog : NSObject
@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *size;
@end
```

```objc
@interface ORMCar : NSObject
@property (nonatomic, copy) NSString *cid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *price;
@end
```

```objc
@interface ORMHouse : NSObject
@property (nonatomic, copy) NSString *hid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *price;
@end
```

```objc
@interface ORMBike : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *price;
@end
```

如上分别建立的表数据结构为:

```c
CREATE TABLE ORMPerson (
    __rowid__     INT     PRIMARY KEY     NOT NULL,
    favorates     TEXT,
    height        REAL,
    pid           TEXT,
    age           INTEGER,
    houseDic      TEXT,//NSDictionary暂时只支持json字符串TEXT字段存储
    name          TEXT,
    __createdAt__ DATE,
    __updatedAt__ DATE
);
```

```c
CREATE TABLE ORMBike (
    __rowid__               INT  PRIMARY KEY   NOT NULL,
    name                    TEXT,
    price                   TEXT,
    __createdAt__           DATE,
    __updatedAt__           DATE,
    ORMPerson_foreign_rowid INT,
    FOREIGN KEY (
        ORMPerson_foreign_rowid
    )
    REFERENCES ORMPerson (__rowid__) 
);
```

```objc
CREATE TABLE ORMCar (
    __rowid__               INT  PRIMARY KEY   NOT NULL,
    cid                     TEXT,
    name                    TEXT,
    price                   TEXT,
    __createdAt__           DATE,
    __updatedAt__           DATE,
    ORMPerson_foreign_rowid INT,
    FOREIGN KEY (
        ORMPerson_foreign_rowid
    )
    REFERENCES ORMPerson (__rowid__) 
);
```

```c
CREATE TABLE ORMDog (
    __rowid__               INT  PRIMARY KEY   NOT NULL,
    did                     TEXT,
    name                    TEXT,
    size                    TEXT,
    __createdAt__           DATE,
    __updatedAt__           DATE,
    ORMPerson_foreign_rowid INT,
    FOREIGN KEY (
        ORMPerson_foreign_rowid
    )
    REFERENCES ORMPerson (__rowid__) 
);
```

